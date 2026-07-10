//
//  HomeViewModel.swift
//  StikDebug
//

import Foundation
import Combine

@MainActor
final class HomeViewModel: ObservableObject {
    static let shared = HomeViewModel()

    @Published private(set) var isJITOperationInFlight = false
    @Published var toast: StatusToast?
    @Published var scriptRunModel: RunJSViewModel?
    @Published var pendingExternalURLAction: HomeExternalAction?

    @Published private var hasAppeared = false
    private var pendingJITEnableConfiguration: JITEnableConfiguration?

    private init() {}

    private var confirmExternalJITRequests: Bool {
        if UserDefaults.standard.object(forKey: UserDefaults.Keys.confirmExternalJITRequests) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: UserDefaults.Keys.confirmExternalJITRequests)
    }

    func handleAppear() {
        startTunnelInBackground()
        hasAppeared = true

        if let config = pendingJITEnableConfiguration {
            startJIT(
                bundleID: config.bundleID,
                pid: config.pid,
                scriptData: config.scriptData,
                scriptName: config.scriptName,
                triggeredByURLScheme: true
            )
            pendingJITEnableConfiguration = nil
        }
    }

    func handleScriptReady(_ notification: Notification) {
        guard let model = notification.userInfo?["model"] as? RunJSViewModel else {
            return
        }
        scriptRunModel = model
    }

    func handleExternalURL(_ url: URL) {
        guard let host = url.host()?.lowercased() else { return }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)

        switch host {
        case "enable-jit":
            var config = JITEnableConfiguration()
            if let pidStr = URLQueryHelpers.queryValue(["pid"], in: components), let pid = Int(pidStr) {
                config.pid = pid
            }
            if let bundleId = URLQueryHelpers.queryValue(
                ["bundle-id", "bundleID", "bundle_id", "bundleId"],
                in: components
            ) {
                config.bundleID = bundleId
            }
            if let scriptBase64URL = URLQueryHelpers.queryValue(
                ["script-data", "scriptData", "script_data"],
                in: components
            )?.removingPercentEncoding {
                let base64 = URLQueryHelpers.base64URLToBase64(scriptBase64URL)
                if let scriptData = Data(base64Encoded: base64) {
                    config.scriptData = scriptData
                }
            }
            if let scriptName = URLQueryHelpers.queryValue(
                ["script-name", "scriptName", "script_name"],
                in: components
            ) {
                config.scriptName = scriptName
            }
            if config.scriptData == nil,
               let bundleID = config.bundleID,
               let scriptInfo = ScriptStore.preferredScript(for: bundleID) {
                config.scriptData = scriptInfo.data
                config.scriptName = scriptInfo.name
            }

            let action = HomeExternalAction.enableJIT(config)
            if confirmExternalJITRequests {
                pendingExternalURLAction = action
            } else {
                performExternalURLAction(action)
            }

        case "kill-process":
            if let pidStr = URLQueryHelpers.queryValue(["pid"], in: components), let pid = Int(pidStr) {
                pendingExternalURLAction = .killProcess(pid)
            }

        case "launch-app":
            if let bundleId = URLQueryHelpers.queryValue(
                ["bundle-id", "bundleID", "bundle_id", "bundleId"],
                in: components
            ) {
                pendingExternalURLAction = .launchApp(bundleId)
            }

        default:
            break
        }
    }

    func performExternalURLAction(_ action: HomeExternalAction) {
        switch action {
        case .enableJIT(let config):
            if hasAppeared {
                startJIT(
                    bundleID: config.bundleID,
                    pid: config.pid,
                    scriptData: config.scriptData,
                    scriptName: config.scriptName,
                    triggeredByURLScheme: true
                )
            } else {
                pendingJITEnableConfiguration = config
            }

        case .killProcess(let pid):
            markTunnelDisconnected()
            startTunnelInBackground(showErrorUI: false) { [weak self] result in
                guard case .success = result else {
                    let message = result.failureMessage ?? "Unable to connect before killing process \(pid)."
                    LogManager.shared.addErrorLog(message)
                    return
                }

                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        try JITEnableContext.shared.killProcess(withPID: Int32(pid))
                        DispatchQueue.main.async {
                            LogManager.shared.addInfoLog("Killed process \(pid) via URL scheme")
                        }
                    } catch {
                        DispatchQueue.main.async {
                            LogManager.shared.addErrorLog(
                                "Failed to kill process \(pid): \(error.localizedDescription)"
                            )
                        }
                    }
                }
            }

        case .launchApp(let bundleID):
            Haptics.medium()
            DispatchQueue.global(qos: .userInitiated).async {
                _ = JITEnableContext.shared.launchAppWithoutDebug(bundleID, logger: nil)
            }
        }
    }

    func startJIT(
        bundleID: String? = nil,
        pid: Int? = nil,
        scriptData: Data? = nil,
        scriptName: String? = nil,
        triggeredByURLScheme: Bool = false,
        displayName: String? = nil
    ) {
        guard !isJITOperationInFlight else {
            AccessibilityAnnouncer.announce("A JIT request is already in progress.".localized)
            return
        }

        isJITOperationInFlight = true
        let targetName = displayName
            ?? bundleID
            ?? pid.map { String(format: "process %d".localized, $0) }
            ?? "app".localized
        let startingMessage = String(format: "Starting JIT for %@".localized, targetName)
        LogManager.shared.addInfoLog("Starting Debug for \(bundleID ?? String(pid ?? 0))")
        toast = .working(startingMessage)
        AccessibilityAnnouncer.announce(startingMessage)

        let beginDebugRequest = { [weak self] in
            self?.runJITRequest(
                bundleID: bundleID,
                pid: pid,
                scriptData: scriptData,
                scriptName: scriptName,
                targetName: targetName
            )
        }

        if triggeredByURLScheme {
            markTunnelDisconnected()
            startTunnelInBackground(showErrorUI: false) { [weak self] result in
                switch result {
                case .success:
                    beginDebugRequest()
                case .failure(let error):
                    self?.finishJITOperation(
                        success: false,
                        targetName: targetName,
                        detail: error.localizedDescription
                    )
                }
            }
        } else {
            beginDebugRequest()
        }
    }

    private func runJITRequest(
        bundleID: String?,
        pid: Int?,
        scriptData: Data?,
        scriptName: String?,
        targetName: String
    ) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var scriptData = scriptData
            var scriptName = scriptName
            if scriptData == nil,
               let bundleID,
               let preferred = ScriptStore.preferredScript(for: bundleID) {
                scriptName = preferred.name
                scriptData = preferred.data
            }

            var callback: DebugAppCallback?
            if ProcessInfo.processInfo.hasTXM, let sd = scriptData {
                callback = self?.makeJSCallback(sd, name: scriptName ?? bundleID ?? "Script")
            }

            var lastDebugMessage: String?
            let logger: LogFunc = { message in
                if let message {
                    lastDebugMessage = message
                    LogManager.shared.addInfoLog(message)
                }
            }

            let success: Bool
            if let pid {
                success = JITEnableContext.shared.debugApp(
                    withPID: Int32(pid),
                    logger: logger,
                    jsCallback: callback
                )
            } else if let bundleID {
                success = JITEnableContext.shared.debugApp(
                    withBundleID: bundleID,
                    logger: logger,
                    jsCallback: callback
                )
            } else {
                lastDebugMessage = "Either bundle ID or PID should be specified.".localized
                success = false
            }

            if success {
                LogManager.shared.addInfoLog("Debug process completed for \(bundleID ?? String(pid ?? 0))")
            }

            Task { @MainActor in
                self?.finishJITOperation(
                    success: success,
                    targetName: targetName,
                    detail: success ? nil : lastDebugMessage
                )
            }
        }
    }

    private func makeJSCallback(_ script: Data, name: String?) -> DebugAppCallback {
        { [weak self] pid, debugProxyHandle, remoteServerHandle, semaphore in
            let model = RunJSViewModel(
                pid: Int(pid),
                debugProxy: debugProxyHandle,
                remoteServer: remoteServerHandle,
                semaphore: semaphore
            )

            DispatchQueue.main.async {
                self?.scriptRunModel = model
            }

            do {
                try model.runScript(data: script, name: name)
            } catch {
                semaphore.signal()
                DispatchQueue.main.async {
                    showAlert(
                        title: "Error Occurred While Executing Script.".localized,
                        message: error.localizedDescription,
                        showOk: true
                    )
                }
            }
        }
    }

    private func finishJITOperation(success: Bool, targetName: String, detail: String?) {
        let message = success
            ? String(format: "JIT request completed for %@".localized, targetName)
            : String(format: "JIT failed for %@".localized, targetName)

        isJITOperationInFlight = false
        toast = success ? .success(message) : .failure(message)
        AccessibilityAnnouncer.announce(message)

        if !success {
            let failureMessage = detail
                ?? "StikDebug could not launch or attach to the selected app. Check that the VPN is enabled, the pairing file is current, and the app is still installed.".localized
            showAlert(title: "Failed to Enable JIT".localized, message: failureMessage, showOk: true)
        }
    }
}

private extension Result where Success == Void, Failure == NSError {
    var failureMessage: String? {
        guard case .failure(let error) = self else {
            return nil
        }
        return error.localizedDescription
    }
}
