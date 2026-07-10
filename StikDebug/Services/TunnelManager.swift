//
//  TunnelManager.swift
//  StikDebug
//

import Foundation

final class TunnelManager: ObservableObject {
    static let shared = TunnelManager()

    @Published private(set) var isConnected = false
    @Published private(set) var isConnecting = false

    private var isStarting = false
    private var completionHandlers: [(Result<Void, NSError>) -> Void] = []

    private init() {}

    func markDisconnected() {
        if Thread.isMainThread {
            isConnected = false
        } else {
            DispatchQueue.main.async { self.isConnected = false }
        }
    }

    func start(
        showErrorUI: Bool = true,
        completion: ((Result<Void, NSError>) -> Void)? = nil
    ) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                self.start(showErrorUI: showErrorUI, completion: completion)
            }
            return
        }

        let pairingFileURL = PairingFileStore.prepareURL()
        guard FileManager.default.fileExists(atPath: pairingFileURL.path) else {
            isConnected = false
            completion?(.failure(NSError(
                domain: "StikDebug",
                code: -17,
                userInfo: [NSLocalizedDescriptionKey: "Pairing file not found."]
            )))
            return
        }

        if isConnected {
            completion?(.success(()))
            return
        }

        if let completion {
            completionHandlers.append(completion)
        }

        guard !isStarting else { return }

        isStarting = true
        isConnecting = true

        DispatchQueue.global(qos: .userInteractive).async { [showErrorUI] in
            let result: Result<Void, NSError>
            do {
                try JITEnableContext.shared.startTunnel()
                result = .success(())
            } catch {
                result = .failure(error as NSError)
            }
            DispatchQueue.main.async {
                self.finishStart(result, showErrorUI: showErrorUI)
            }
        }
    }

    private func finishStart(_ result: Result<Void, NSError>, showErrorUI: Bool) {
        isStarting = false
        isConnecting = false

        switch result {
        case .success:
            isConnected = true
            LogManager.shared.addInfoLog("Tunnel connected successfully")
            let trustcache = URL.documentsDirectory.appendingPathComponent("DDI/Image.dmg.trustcache").path
            if FileManager.default.fileExists(atPath: trustcache),
               !MountingProgress.shared.isDeveloperDiskImageMounted,
               !MountingProgress.shared.isMounting {
                MountingProgress.shared.mountIfNeeded()
            }
        case .failure(let error):
            isConnected = false
            LogManager.shared.addErrorLog(
                "Tunnel connection failed for \(DeviceConnectionContext.targetIPAddress):49152: \(error.localizedDescription) (\(error.domain) \(error.code))"
            )
            if showErrorUI {
                presentConnectionFailure(error)
            }
        }

        let handlers = completionHandlers
        completionHandlers.removeAll()
        handlers.forEach { $0(result) }
    }

    private func presentConnectionFailure(_ error: NSError) {
        if error.code == -9 {
            LogManager.shared.addInfoLog("Pairing file reported invalid; keeping existing file")
            showAlert(
                title: "Invalid Pairing File",
                message: "The pairing file may be invalid or expired. You can import a new pairing file to replace it.",
                showOk: true,
                primaryButtonText: "Select New File"
            ) { _ in
                NotificationCenter.default.post(name: .showPairingFilePicker, object: nil)
            }
            return
        }

        showAlert(
            title: "Connection Error",
            message: """
            Could not open the device tunnel.

            Target: \(DeviceConnectionContext.targetIPAddress):49152
            Expected LocalDevVPN IP: \(DeviceConnectionContext.defaultTargetIPAddress)

            Confirm Wi-Fi and LocalDevVPN are connected, wake the device, then try again.

            Code \(error.code): \(error.localizedDescription)
            """,
            showOk: false,
            showTryAgain: true
        ) { tryAgain in
            if tryAgain {
                startTunnelInBackground()
            }
        }
    }
}

func startTunnelInBackground(
    showErrorUI: Bool = true,
    completion: ((Result<Void, NSError>) -> Void)? = nil
) {
    TunnelManager.shared.start(showErrorUI: showErrorUI, completion: completion)
}

func markTunnelDisconnected() {
    TunnelManager.shared.markDisconnected()
}
