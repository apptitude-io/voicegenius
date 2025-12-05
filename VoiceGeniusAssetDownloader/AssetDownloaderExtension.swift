import BackgroundAssets
import Foundation
import os

/// Background Assets extension for downloading model files before first app launch
@main
final class AssetDownloaderExtension: BADownloaderExtension {
    private let logger = Logger(subsystem: "io.apptitude.voicegenius.AssetDownloader", category: "Download")

    /// Model storage directory - must match the main app
    private static var modelDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Models", isDirectory: true)
    }

    // MARK: - BADownloaderExtension Protocol

    /// Called when the extension starts
    func extensionDidEnterTerminatedState() {
        logger.info("Extension entered terminated state")
    }

    /// Called when downloads should be enqueued
    func downloads(for request: BAContentRequest,
                   manifestURL: URL,
                   extensionInfo: BAAppExtensionInfo) -> Set<BADownload> {
        logger.info("Received download request: \(request.rawValue)")

        // Check if model is already downloaded
        let configFile = Self.modelDirectory.appendingPathComponent("config.json")
        if FileManager.default.fileExists(atPath: configFile.path) {
            logger.info("Model already downloaded, skipping background download")
            return []
        }

        // Return the set of downloads to perform
        return createModelDownloads()
    }

    /// Called when a download is about to begin
    func download(_ download: BADownload,
                  didBegin request: URLRequest) {
        logger.info("Download began: \(download.identifier)")
    }

    /// Called when a download is paused
    func download(_ download: BADownload,
                  didPause reason: URLError) {
        logger.warning("Download paused: \(download.identifier), reason: \(reason.localizedDescription)")
    }

    /// Called when a download fails
    func download(_ download: BADownload,
                  failedWithError error: Error) {
        logger.error("Download failed: \(download.identifier), error: \(error.localizedDescription)")
    }

    /// Called when a download completes successfully
    func download(_ download: BADownload,
                  finishedWithFileURL fileURL: URL) {
        logger.info("Download finished: \(download.identifier)")

        do {
            // Create model directory if needed
            let fm = FileManager.default
            if !fm.fileExists(atPath: Self.modelDirectory.path) {
                try fm.createDirectory(at: Self.modelDirectory, withIntermediateDirectories: true)
            }

            // Exclude from backup
            var modelDir = Self.modelDirectory
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try modelDir.setResourceValues(resourceValues)

            // Determine destination filename from download identifier
            let filename = extractFilename(from: download.identifier)
            let destinationURL = Self.modelDirectory.appendingPathComponent(filename)

            // Create parent directory if needed (for nested files)
            let parentDir = destinationURL.deletingLastPathComponent()
            if !fm.fileExists(atPath: parentDir.path) {
                try fm.createDirectory(at: parentDir, withIntermediateDirectories: true)
            }

            // Move file to destination
            if fm.fileExists(atPath: destinationURL.path) {
                try fm.removeItem(at: destinationURL)
            }
            try fm.moveItem(at: fileURL, to: destinationURL)

            // Exclude file from backup
            var destURL = destinationURL
            try destURL.setResourceValues(resourceValues)

            logger.info("Moved file to: \(destinationURL.path)")
        } catch {
            logger.error("Failed to move downloaded file: \(error.localizedDescription)")
        }
    }

    // MARK: - Private Methods

    private func createModelDownloads() -> Set<BADownload> {
        // Model files to download from HuggingFace
        // Using the Qwen2.5-3B-Instruct-4bit model
        let modelRepo = "mlx-community/Qwen2.5-3B-Instruct-4bit"
        let baseURL = "https://huggingface.co/\(modelRepo)/resolve/main"

        // Essential model files
        let files = [
            "config.json",
            "tokenizer.json",
            "tokenizer_config.json",
            "model.safetensors",
            "special_tokens_map.json"
        ]

        var downloads = Set<BADownload>()

        for file in files {
            guard let url = URL(string: "\(baseURL)/\(file)") else { continue }

            // Create download with unique identifier
            let identifier = "model.\(file)"

            // Essential downloads start immediately on install
            // Check if this is the large model file
            let isEssential = file != "model.safetensors"

            let download = BAURLDownload(
                identifier: identifier,
                request: URLRequest(url: url),
                essential: isEssential,  // Essential files are downloaded with high priority
                fileSize: file == "model.safetensors" ? 1_700_000_000 : 100_000,
                applicationGroupIdentifier: "group.io.apptitude.voicegenius",
                priority: .default
            )
            downloads.insert(download)
            logger.info("Created download for: \(file)")
        }

        return downloads
    }

    private func extractFilename(from identifier: String) -> String {
        // Identifier format: "model.filename.ext"
        if identifier.hasPrefix("model.") {
            return String(identifier.dropFirst(6))
        }
        return identifier
    }
}
