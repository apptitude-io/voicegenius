import Foundation
import UIKit
import CryptoKit
import Network
import os

// MARK: - Download Errors

enum ModelDownloadError: Error, LocalizedError {
    case insufficientDiskSpace(required: Int64, available: Int64)
    case networkUnavailable
    case checksumMismatch(expected: String, actual: String)
    case invalidResponse
    case downloadFailed(Error)
    case fileOperationFailed(Error)

    var errorDescription: String? {
        switch self {
        case .insufficientDiskSpace(let required, let available):
            let requiredGB = Double(required) / 1_000_000_000
            let availableGB = Double(available) / 1_000_000_000
            return String(format: "Insufficient disk space. Required: %.1f GB, Available: %.1f GB", requiredGB, availableGB)
        case .networkUnavailable:
            return "No network connection available"
        case .checksumMismatch(let expected, let actual):
            return "File integrity check failed. Expected: \(expected.prefix(8))..., Got: \(actual.prefix(8))..."
        case .invalidResponse:
            return "Invalid response from server"
        case .downloadFailed(let error):
            return "Download failed: \(error.localizedDescription)"
        case .fileOperationFailed(let error):
            return "File operation failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Download State

enum ModelDownloadState: Equatable {
    case idle
    case checkingRequirements
    case downloading(bytesReceived: Int64, totalBytes: Int64, currentFile: String)
    case validating
    case completed
    case failed(String)

    var isActive: Bool {
        switch self {
        case .checkingRequirements, .downloading, .validating:
            return true
        default:
            return false
        }
    }
}

// MARK: - File Info from HuggingFace API

private struct HFFileInfo: Decodable {
    let path: String
    let type: String
    let size: Int64?
    let lfs: LFSInfo?

    struct LFSInfo: Decodable {
        let size: Int64
        let sha256: String
    }
}

// MARK: - Model Downloader

/// Service for downloading LLM model files from HuggingFace with resume support
@MainActor
final class ModelDownloader: NSObject, ObservableObject {

    // MARK: - Configuration

    /// Get the model repo from current settings (uses preset selection)
    @MainActor
    private var modelRepo: String {
        SettingsViewModel.shared.currentModelRepoId
    }

    private let baseURL = "https://huggingface.co"

    /// Minimum required free space (model size + 800MB buffer)
    private let minimumFreeSpaceBytes: Int64 = 2_500_000_000 // 2.5 GB

    /// Returns a friendly model name (e.g., "Qwen 2.5 3B")
    @MainActor
    var modelName: String {
        SettingsViewModel.shared.selectedPreset.friendlyModelName
    }

    // MARK: - Published State

    @Published private(set) var state: ModelDownloadState = .idle
    @Published private(set) var isOnCellular = false

    /// Computed progress (0.0 to 1.0)
    var downloadProgress: Double {
        if case .downloading(let received, let total, _) = state, total > 0 {
            return Double(received) / Double(total)
        }
        return 0.0
    }

    /// Human-readable progress string
    var progressText: String {
        if case .downloading(let received, let total, _) = state {
            let receivedMB = Double(received) / 1_000_000
            let totalMB = Double(total) / 1_000_000
            return String(format: "%.0f / %.0f MB", receivedMB, totalMB)
        }
        return ""
    }

    /// Current file being downloaded
    var currentFile: String {
        if case .downloading(_, _, let file) = state {
            return file
        }
        return ""
    }

    // MARK: - Private Properties

    private var downloadSession: URLSession!
    private var activeDownloadTask: URLSessionDownloadTask?
    private var resumeData: Data?
    private var filesToDownload: [(path: String, size: Int64, sha256: String?)] = []
    private var currentFileIndex = 0
    private var totalBytesExpected: Int64 = 0
    private var bytesDownloadedPreviously: Int64 = 0
    private var downloadContinuation: CheckedContinuation<URL, Error>?
    private let networkMonitor = NWPathMonitor()

    /// Model storage directory: Library/Application Support/Models/
    /// This is nonisolated because it's a pure path computation.
    nonisolated static var modelDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Models", isDirectory: true)
    }

    private var modelDirectory: URL { Self.modelDirectory }

    /// Resume data file location
    private var resumeDataURL: URL {
        modelDirectory.appendingPathComponent(".resume_data")
    }

    // MARK: - Initialization

    override init() {
        super.init()

        // Configure background-capable URLSession
        let config = URLSessionConfiguration.default
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.allowsCellularAccess = true
        self.downloadSession = URLSession(configuration: config, delegate: self, delegateQueue: .main)

        // Start network monitoring
        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isOnCellular = (path.usesInterfaceType(.cellular))
            }
        }
        networkMonitor.start(queue: DispatchQueue.global(qos: .utility))

        // Load any saved resume data
        loadResumeData()
    }

    deinit {
        networkMonitor.cancel()
    }

    // MARK: - Public Methods

    /// Check if model files already exist and are valid
    func isModelDownloaded() -> Bool {
        let configFile = modelDirectory.appendingPathComponent("config.json")
        let weightFiles = (try? FileManager.default.contentsOfDirectory(at: modelDirectory, includingPropertiesForKeys: nil))?.filter { $0.pathExtension == "safetensors" } ?? []
        return FileManager.default.fileExists(atPath: configFile.path) && !weightFiles.isEmpty
    }

    /// Check available disk space
    func availableDiskSpace() -> Int64 {
        let fileURL = URL(fileURLWithPath: NSHomeDirectory())
        do {
            let values = try fileURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            return values.volumeAvailableCapacityForImportantUsage ?? 0
        } catch {
            return 0
        }
    }

    /// Check if network is available
    nonisolated func isNetworkAvailable() -> Bool {
        let monitor = NWPathMonitor()
        let semaphore = DispatchSemaphore(value: 0)
        let result = OSAllocatedUnfairLock(initialState: false)

        monitor.pathUpdateHandler = { path in
            result.withLock { $0 = path.status == .satisfied }
            semaphore.signal()
        }

        let queue = DispatchQueue(label: "network.check")
        monitor.start(queue: queue)
        _ = semaphore.wait(timeout: .now() + 1)
        monitor.cancel()

        return result.withLock { $0 }
    }

    /// Download model from HuggingFace with full validation
    func downloadModel() async throws {
        guard state == .idle || state == .failed("") || !state.isActive else { return }

        state = .checkingRequirements

        // Check network
        guard isNetworkAvailable() else {
            state = .failed(ModelDownloadError.networkUnavailable.localizedDescription)
            throw ModelDownloadError.networkUnavailable
        }

        // Fetch file list and sizes
        filesToDownload = try await fetchFileList()
        totalBytesExpected = filesToDownload.reduce(0) { $0 + $1.size }

        // Check disk space
        let available = availableDiskSpace()
        guard available >= minimumFreeSpaceBytes else {
            let error = ModelDownloadError.insufficientDiskSpace(required: minimumFreeSpaceBytes, available: available)
            state = .failed(error.localizedDescription)
            throw error
        }

        // Create model directory with backup exclusion
        try createModelDirectoryWithBackupExclusion()

        // Disable idle timer during download
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = false }

        // Download each file
        bytesDownloadedPreviously = 0

        for (index, file) in filesToDownload.enumerated() {
            currentFileIndex = index
            let destinationURL = modelDirectory.appendingPathComponent(file.path)

            // Skip if file already exists with correct size
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                if let attrs = try? FileManager.default.attributesOfItem(atPath: destinationURL.path),
                   let existingSize = attrs[.size] as? Int64,
                   existingSize == file.size {
                    bytesDownloadedPreviously += file.size
                    continue
                }
            }

            // Download the file
            let tempURL = try await downloadFile(path: file.path, expectedSize: file.size)

            // Validate checksum if available
            if let expectedSHA256 = file.sha256 {
                state = .validating
                let actualSHA256 = try computeSHA256(of: tempURL)
                guard actualSHA256.lowercased() == expectedSHA256.lowercased() else {
                    try? FileManager.default.removeItem(at: tempURL)
                    let error = ModelDownloadError.checksumMismatch(expected: expectedSHA256, actual: actualSHA256)
                    state = .failed(error.localizedDescription)
                    throw error
                }
            }

            // Move to final destination
            try moveFileWithBackupExclusion(from: tempURL, to: destinationURL)

            bytesDownloadedPreviously += file.size
        }

        // Clean up resume data
        try? FileManager.default.removeItem(at: resumeDataURL)

        state = .completed
    }

    /// Cancel current download
    func cancelDownload() {
        activeDownloadTask?.cancel(byProducingResumeData: { [weak self] data in
            self?.resumeData = data
            self?.saveResumeData()
        })
        activeDownloadTask = nil
        state = .idle
        UIApplication.shared.isIdleTimerDisabled = false
    }

    // MARK: - Private Methods

    private func createModelDirectoryWithBackupExclusion() throws {
        let fm = FileManager.default

        if !fm.fileExists(atPath: modelDirectory.path) {
            try fm.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        }

        // Exclude from iCloud backup
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableURL = modelDirectory
        try mutableURL.setResourceValues(resourceValues)
    }

    private func moveFileWithBackupExclusion(from source: URL, to destination: URL) throws {
        let fm = FileManager.default

        // Create parent directory if needed
        let parentDir = destination.deletingLastPathComponent()
        if !fm.fileExists(atPath: parentDir.path) {
            try fm.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }

        // Remove existing file if present
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }

        // Move file
        try fm.moveItem(at: source, to: destination)

        // Exclude from backup
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableURL = destination
        try mutableURL.setResourceValues(resourceValues)
    }

    private func fetchFileList() async throws -> [(path: String, size: Int64, sha256: String?)] {
        let url = URL(string: "\(baseURL)/api/models/\(modelRepo)/tree/main")!

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ModelDownloadError.invalidResponse
        }

        let fileInfos = try JSONDecoder().decode([HFFileInfo].self, from: data)

        // Filter to model files and extract size/checksum info
        return fileInfos
            .filter { $0.type == "file" }
            .filter { path in
                let p = path.path
                return p.hasSuffix(".json") ||
                       p.hasSuffix(".safetensors") ||
                       p.hasSuffix(".model") ||
                       p == "tokenizer.model"
            }
            .map { info in
                let size = info.lfs?.size ?? info.size ?? 0
                let sha256 = info.lfs?.sha256
                return (path: info.path, size: size, sha256: sha256)
            }
    }

    private func downloadFile(path: String, expectedSize: Int64) async throws -> URL {
        let url = URL(string: "\(baseURL)/\(modelRepo)/resolve/main/\(path)")!

        return try await withCheckedThrowingContinuation { continuation in
            self.downloadContinuation = continuation

            // Check for resume data for this file
            if let resumeData = self.resumeData {
                activeDownloadTask = downloadSession.downloadTask(withResumeData: resumeData)
                self.resumeData = nil
            } else {
                activeDownloadTask = downloadSession.downloadTask(with: url)
            }

            state = .downloading(
                bytesReceived: bytesDownloadedPreviously,
                totalBytes: totalBytesExpected,
                currentFile: path
            )

            activeDownloadTask?.resume()
        }
    }

    private func computeSHA256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()

        while autoreleasepool(invoking: {
            guard let data = try? handle.read(upToCount: 1024 * 1024) else { return false }
            guard !data.isEmpty else { return false }
            hasher.update(data: data)
            return true
        }) {}

        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func saveResumeData() {
        guard let data = resumeData else { return }
        try? data.write(to: resumeDataURL)
    }

    private func loadResumeData() {
        resumeData = try? Data(contentsOf: resumeDataURL)
    }
}

// MARK: - URLSessionDownloadDelegate

extension ModelDownloader: URLSessionDownloadDelegate {

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Move to a safe temporary location before returning
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent(UUID().uuidString)

        do {
            try FileManager.default.moveItem(at: location, to: tempFile)
            Task { @MainActor in
                self.downloadContinuation?.resume(returning: tempFile)
                self.downloadContinuation = nil
            }
        } catch {
            Task { @MainActor in
                self.downloadContinuation?.resume(throwing: ModelDownloadError.fileOperationFailed(error))
                self.downloadContinuation = nil
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        Task { @MainActor in
            let totalReceived = self.bytesDownloadedPreviously + totalBytesWritten
            if case .downloading(_, let total, let file) = self.state {
                self.state = .downloading(bytesReceived: totalReceived, totalBytes: total, currentFile: file)
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error = error else { return }

        // Save resume data if available
        let nsError = error as NSError
        if let resumeData = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
            Task { @MainActor in
                self.resumeData = resumeData
                self.saveResumeData()
            }
        }

        Task { @MainActor in
            self.downloadContinuation?.resume(throwing: ModelDownloadError.downloadFailed(error))
            self.downloadContinuation = nil
            self.state = .failed(error.localizedDescription)
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }
}
