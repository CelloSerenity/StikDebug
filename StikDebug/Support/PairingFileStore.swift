import Foundation
import UniformTypeIdentifiers

enum PairingFileStore {
    static let fileName = "pairingFile.plist"
    static let supportedContentTypes: [UTType] = [
        UTType(filenameExtension: "mobiledevicepairing", conformingTo: .data)!,
        UTType(filenameExtension: "mobiledevicepair", conformingTo: .data)!,
        .propertyList
    ]

    private static let legacyFileName = "rp_pairing_file.plist"

    static var url: URL {
        url(for: DeviceProfileStore.selectedProfileID())
    }

    static func url(for profileID: String) -> URL {
        if profileID == DeviceProfileStore.localProfileID {
            return localDocumentsURL
        }
        return profilesDirectoryURL.appendingPathComponent(profileID).appendingPathExtension("plist")
    }

    @discardableResult
    static func prepareURL(
        for profileID: String = DeviceProfileStore.selectedProfileID(),
        fileManager: FileManager = .default
    ) -> URL {
        let destination = url(for: profileID)
        if profileID == DeviceProfileStore.localProfileID {
            prepareLocalPairingFile(fileManager: fileManager)
        } else {
            try? fileManager.createDirectory(at: profilesDirectoryURL, withIntermediateDirectories: true)
        }
        return destination
    }

    static func hasPairingFile(
        for profileID: String = DeviceProfileStore.selectedProfileID(),
        fileManager: FileManager = .default
    ) -> Bool {
        let pairingURL = prepareURL(for: profileID, fileManager: fileManager)
        return fileManager.fileExists(atPath: pairingURL.path)
    }

    static func replace(
        with sourceURL: URL,
        for profileID: String = DeviceProfileStore.selectedProfileID(),
        fileManager: FileManager = .default
    ) throws {
        let destination = prepareURL(for: profileID, fileManager: fileManager)
        if sourceURL.standardizedFileURL != destination.standardizedFileURL {
            try replaceItem(at: destination, with: sourceURL, fileManager: fileManager)
        }
        protectPairingFile(at: destination, fileManager: fileManager)
    }

    static func replace(
        with data: Data,
        for profileID: String = DeviceProfileStore.selectedProfileID(),
        fileManager: FileManager = .default
    ) throws {
        let destination = prepareURL(for: profileID, fileManager: fileManager)
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: destination, options: .atomic)
        protectPairingFile(at: destination, fileManager: fileManager)
    }

    static func importFromPicker(
        _ sourceURL: URL,
        for profileID: String = DeviceProfileStore.selectedProfileID(),
        fileManager: FileManager = .default
    ) throws {
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw CocoaError(.fileNoSuchFile)
        }

        try replace(with: sourceURL, for: profileID, fileManager: fileManager)
    }

    static func remove(
        for profileID: String = DeviceProfileStore.selectedProfileID(),
        fileManager: FileManager = .default
    ) throws {
        if profileID == DeviceProfileStore.localProfileID {
            for pairingURL in localPairingURLs where fileManager.fileExists(atPath: pairingURL.path) {
                try fileManager.removeItem(at: pairingURL)
            }
            return
        }

        let pairingURL = url(for: profileID)
        if fileManager.fileExists(atPath: pairingURL.path) {
            try fileManager.removeItem(at: pairingURL)
        }
    }

    private static var localDocumentsURL: URL {
        URL.documentsDirectory.appendingPathComponent(fileName)
    }

    private static var profilesDirectoryURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pairing/Profiles", isDirectory: true)
    }

    private static var legacyInternalDirectoryURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pairing", isDirectory: true)
    }

    private static var localPairingURLs: [URL] {
        [
            localDocumentsURL,
            URL.documentsDirectory.appendingPathComponent(legacyFileName),
            legacyInternalDirectoryURL.appendingPathComponent(fileName),
            legacyInternalDirectoryURL.appendingPathComponent(legacyFileName)
        ]
    }

    private static func prepareLocalPairingFile(fileManager: FileManager) {
        let afcLegacyURL = URL.documentsDirectory.appendingPathComponent(legacyFileName)
        if fileManager.fileExists(atPath: afcLegacyURL.path) {
            do {
                try replaceItem(at: localDocumentsURL, with: afcLegacyURL, fileManager: fileManager)
                try fileManager.removeItem(at: afcLegacyURL)
                protectPairingFile(at: localDocumentsURL, fileManager: fileManager)
            } catch { }
            return
        }

        guard !fileManager.fileExists(atPath: localDocumentsURL.path),
              let sourceURL = localPairingURLs.dropFirst(2).first(where: { fileManager.fileExists(atPath: $0.path) }) else { return }
        try? replaceItem(at: localDocumentsURL, with: sourceURL, fileManager: fileManager)
        protectPairingFile(at: localDocumentsURL, fileManager: fileManager)
    }

    private static func replaceItem(at destination: URL, with source: URL, fileManager: FileManager) throws {
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporary = destination
            .deletingLastPathComponent()
            .appendingPathComponent(UUID().uuidString + ".tmp")
        try? fileManager.removeItem(at: temporary)
        try fileManager.copyItem(at: source, to: temporary)
        defer { try? fileManager.removeItem(at: temporary) }

        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try fileManager.moveItem(at: temporary, to: destination)
        }
    }

    private static func protectPairingFile(at url: URL, fileManager: FileManager) {
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
