import Foundation

/// Service for downloading LLM model files from HuggingFace
@MainActor
final class ModelDownloader: NSObject, ObservableObject {
    private var modelRepo: String { AppConfig.shared.model }
    private let baseURL = "https://huggingface.co"

    /// Returns just the model name (after the last /)
    var modelName: String {
        AppConfig.shared.modelName
    }

    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0.0
    @Published var currentFile: String = ""
    @Published var filesCompleted: Int = 0
    @Published var totalFiles: Int = 0
    @Published var error: Error?

    private var downloadSession: URLSession?
    private var currentDownloadTask: URLSessionDownloadTask?

    private var modelDirectory: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsPath.appendingPathComponent("models", isDirectory: true)
    }

    override init() {
        super.init()
    }

    /// Check if model files already exist
    func isModelDownloaded() -> Bool {
        let configFile = modelDirectory.appendingPathComponent("config.json")
        return FileManager.default.fileExists(atPath: configFile.path)
    }

    /// Download model from HuggingFace
    func downloadModel() async throws {
        isDownloading = true
        error = nil
        downloadProgress = 0.0

        // Create model directory
        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)

        // Get list of files to download
        let files = try await fetchFileList()
        totalFiles = files.count
        filesCompleted = 0

        // Download each file
        for file in files {
            currentFile = file
            try await downloadFile(name: file)
            filesCompleted += 1
            downloadProgress = Double(filesCompleted) / Double(totalFiles)
        }

        isDownloading = false
        currentFile = ""
    }

    private func fetchFileList() async throws -> [String] {
        let url = URL(string: "\(baseURL)/api/models/\(modelRepo)/tree/main")!

        let (data, _) = try await URLSession.shared.data(from: url)

        struct FileInfo: Decodable {
            let path: String
            let type: String
        }

        let fileInfos = try JSONDecoder().decode([FileInfo].self, from: data)

        // Filter to only include model files we need
        let modelFiles = fileInfos
            .filter { $0.type == "file" }
            .map { $0.path }
            .filter { path in
                path.hasSuffix(".json") ||
                path.hasSuffix(".safetensors") ||
                path.hasSuffix(".model") ||
                path == "tokenizer.model"
            }

        return modelFiles
    }

    private func downloadFile(name: String) async throws {
        let url = URL(string: "\(baseURL)/\(modelRepo)/resolve/main/\(name)")!
        let destinationURL = modelDirectory.appendingPathComponent(name)

        // Skip if file already exists
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            return
        }

        // Create subdirectories if needed
        let parentDir = destinationURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

        // Download file
        let (tempURL, _) = try await URLSession.shared.download(from: url)

        // Move to destination
        try FileManager.default.moveItem(at: tempURL, to: destinationURL)
    }

    func cancelDownload() {
        currentDownloadTask?.cancel()
        isDownloading = false
    }
}
