//
//  PairingFileStore.swift
//  StikDebug
//

import Foundation
import UniformTypeIdentifiers

enum PairingFileStore {
    static let fileName = "rp_pairing_file.plist"
    static let supportedContentTypes: [UTType] = [
        UTType(filenameExtension: "mobiledevicepairing", conformingTo: .data)!,
        UTType(filenameExtension: "mobiledevicepair", conformingTo: .data)!,
        .propertyList
    ]

    private static let legacyFileName = "pairingFile.plist"

    static var url: URL {
        directoryURL.appendingPathComponent(fileName)
    }

    private static var directoryURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pairing", isDirectory: true)
    }

    private static var legacyURLs: [URL] {
        [
            URL.documentsDirectory.appendingPathComponent(fileName),
            URL.documentsDirectory.appendingPathComponent(legacyFileName)
        ]
    }

    @discardableResult
    static func prepareURL(fileManager: FileManager = .default) -> URL {
        let destination = url
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        if !fileManager.fileExists(atPath: destination.path) {
            migrateLegacyCopy(to: destination, fileManager: fileManager)
        } else {
            removeLegacyCopies(fileManager: fileManager)
        }
        return destination
    }

    static func importFromPicker(_ sourceURL: URL, fileManager: FileManager = .default) throws {
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessing { sourceURL.stopAccessingSecurityScopedResource() }
        }

        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw CocoaError(.fileNoSuchFile)
        }

        let destination = prepareURL(fileManager: fileManager)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        removeLegacyCopies(fileManager: fileManager)
        try fileManager.copyItem(at: sourceURL, to: destination)
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
    }

    private static func migrateLegacyCopy(to destination: URL, fileManager: FileManager) {
        for legacyURL in legacyURLs where fileManager.fileExists(atPath: legacyURL.path) {
            do {
                try fileManager.moveItem(at: legacyURL, to: destination)
            } catch {
                if let data = try? Data(contentsOf: legacyURL) {
                    try? data.write(to: destination, options: .atomic)
                    try? fileManager.removeItem(at: legacyURL)
                }
            }
            try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
            break
        }
    }

    private static func removeLegacyCopies(fileManager: FileManager) {
        for legacyURL in legacyURLs where fileManager.fileExists(atPath: legacyURL.path) {
            try? fileManager.removeItem(at: legacyURL)
        }
    }
}
