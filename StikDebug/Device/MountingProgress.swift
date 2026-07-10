//
//  MountingProgress.swift
//  StikDebug
//

import Foundation
import idevice

final class MountingProgress: ObservableObject {
    static let shared = MountingProgress()

    @Published private(set) var mountProgress: Double = 0.0
    @Published private(set) var isMounting = false
    @Published private(set) var isDeveloperDiskImageMounted = false

    private init() {}

    func updateProgress(progress: size_t, total: size_t, context: UnsafeMutableRawPointer?) {
        guard total > 0 else { return }
        let percentage = Double(progress) / Double(total) * 100.0
        DispatchQueue.main.async {
            guard abs(self.mountProgress - percentage) >= 1.0 || percentage == 0 || percentage >= 100 else {
                return
            }
            self.mountProgress = percentage
        }
    }

    func mountIfNeeded() {
        guard !isMounting else { return }
        isMounting = true
        mountProgress = 0

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            let currentlyMounted = isMounted()
            guard Self.pairingFileIsReadable(), !currentlyMounted else {
                DispatchQueue.main.async {
                    self.isDeveloperDiskImageMounted = currentlyMounted
                    self.isMounting = false
                }
                return
            }

            let docs = URL.documentsDirectory
            let mountError = mountPersonalDDI(
                imagePath: docs.appendingPathComponent("DDI/Image.dmg").path,
                trustcachePath: docs.appendingPathComponent("DDI/Image.dmg.trustcache").path,
                manifestPath: docs.appendingPathComponent("DDI/BuildManifest.plist").path
            )

            DispatchQueue.main.async {
                self.isMounting = false
                if let mountError {
                    showAlert(title: "DDI Mount Failed", message: mountError, showOk: true, showTryAgain: true) { tryAgain in
                        if tryAgain { self.mountIfNeeded() }
                    }
                } else {
                    self.isDeveloperDiskImageMounted = true
                }
            }
        }
    }

    private static func pairingFileIsReadable() -> Bool {
        let path = PairingFileStore.prepareURL().path
        var pairingFile: OpaquePointer?
        let error = rp_pairing_file_read(path, &pairingFile)
        if error != nil { return false }
        rp_pairing_file_free(pairingFile)
        return true
    }
}
