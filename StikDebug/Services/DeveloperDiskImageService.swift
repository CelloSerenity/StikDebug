//
//  DeveloperDiskImageService.swift
//  StikDebug
//

import Foundation

final class DeveloperDiskImageService {
    static let shared = DeveloperDiskImageService()

    private let fileManager: FileManager
    private let session: URLSession

    private init(fileManager: FileManager = .default, session: URLSession = .shared) {
        self.fileManager = fileManager
        self.session = session
    }

    func downloadMissingFiles() async throws {
        for item in Self.downloadItems {
            let destination = URL.documentsDirectory.appendingPathComponent(item.relativePath)
            guard !fileManager.fileExists(atPath: destination.path) else { continue }
            try await download(item.urlString, to: destination)
        }
    }

    func redownload(progressHandler: ((Double, String) -> Void)? = nil) async throws {
        let total = Double(Self.downloadItems.count + 1)
        var done = 0.0

        progressHandler?(0, "Removing existing DDI files...")
        for item in Self.downloadItems {
            let url = URL.documentsDirectory.appendingPathComponent(item.relativePath)
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        }
        done += 1
        progressHandler?(done / total, "Starting downloads...")

        for item in Self.downloadItems {
            progressHandler?(done / total, "Downloading \(item.name)...")
            try await download(
                item.urlString,
                to: URL.documentsDirectory.appendingPathComponent(item.relativePath)
            )
            done += 1
            progressHandler?(done / total, "\(item.name) ready")
        }
        progressHandler?(1, "DDI download complete.")
    }

    private func download(_ urlString: String, to destination: URL) async throws {
        guard let url = URL(string: urlString), url.scheme?.lowercased() == "https" else {
            throw DDIDownloadError.invalidURL(urlString)
        }

        let (tempURL, response) = try await session.download(from: url)
        guard let http = response as? HTTPURLResponse else {
            throw DDIDownloadError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw DDIDownloadError.badStatus(http.statusCode)
        }

        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: tempURL, to: destination)
    }

    private static let downloadItems: [(name: String, relativePath: String, urlString: String)] = [
        (
            "Build Manifest",
            "DDI/BuildManifest.plist",
            "https://github.com/doronz88/DeveloperDiskImage/raw/refs/heads/main/PersonalizedImages/Xcode_iOS_DDI_Personalized/BuildManifest.plist"
        ),
        (
            "Image",
            "DDI/Image.dmg",
            "https://github.com/doronz88/DeveloperDiskImage/raw/refs/heads/main/PersonalizedImages/Xcode_iOS_DDI_Personalized/Image.dmg"
        ),
        (
            "TrustCache",
            "DDI/Image.dmg.trustcache",
            "https://github.com/doronz88/DeveloperDiskImage/raw/refs/heads/main/PersonalizedImages/Xcode_iOS_DDI_Personalized/Image.dmg.trustcache"
        )
    ]
}

enum DDIDownloadError: LocalizedError {
    case invalidURL(String)
    case invalidResponse
    case badStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let string): return "Invalid download URL: \(string)"
        case .invalidResponse: return "The DDI server returned an invalid response."
        case .badStatus(let code): return "The DDI server returned HTTP \(code)."
        }
    }
}
