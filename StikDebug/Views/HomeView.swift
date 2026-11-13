//
//  HomeView.swift
//  StikDebug
//
//  Created by Stephen on 3/26/25.
//

import SwiftUI

struct HomeView: View {
    @AppStorage("autoQuitAfterEnablingJIT") private var doAutoQuitAfterEnablingJIT = false
    @AppStorage("bundleID") private var bundleID: String = ""
    @AppStorage(UserDefaults.Keys.confirmExternalJITRequests) private var confirmExternalJITRequests = true

    @State private var hasAppeared = false
    @State private var pendingJITEnableConfiguration: JITEnableConfiguration?
    @State private var isShowingPairingFilePicker = false
    @State private var debugFeedback: DebugFeedback?
    @State private var pendingExternalURLAction: HomeExternalAction?
    @State private var pendingLiveContainerApp: JITWarningApp?
    @State private var pendingStikDebugApp: JITWarningApp?
    @State private var scriptRunModel: RunJSViewModel?
    @State private var isShowingPIDJIT = false

    private struct DebugFeedback: Identifiable {
        let id = UUID()
        let message: String
        let isError: Bool
        let isWorking: Bool
    }

    private struct JITWarningApp {
        let bundleID: String
        let name: String
    }

    var body: some View {
        InstalledAppsListView(onSelectApp: { selectedBundle, selectedName in
            if selectedBundle == Bundle.main.bundleIdentifier {
                pendingStikDebugApp = JITWarningApp(bundleID: selectedBundle, name: selectedName)
            } else if selectedName.localizedCaseInsensitiveContains("LiveContainer") {
                pendingLiveContainerApp = JITWarningApp(bundleID: selectedBundle, name: selectedName)
            } else {
                enableJITForSelectedApp(bundleID: selectedBundle, name: selectedName)
            }
        }, onEnableByPID: {
            isShowingPIDJIT = true
        }, showDoneButton: false)
        .overlay(alignment: .bottom) {
            if let debugFeedback {
                debugFeedbackView(debugFeedback)
                    .padding(.bottom, 40)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear(perform: handleAppear)
        .onReceive(NotificationCenter.default.publisher(for: .intentJSScriptReady), perform: handleScriptReadyNotification)
        .onOpenURL { url in
            handleExternalURL(url)
        }
        .confirmationDialog(
            pendingExternalURLAction?.title ?? "External Request",
            isPresented: Binding(
                get: { pendingExternalURLAction != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingExternalURLAction = nil
                    }
                }
            ),
            titleVisibility: .visible,
            presenting: pendingExternalURLAction
        ) { action in
            Button(action.confirmationTitle, role: action.role) {
                performExternalURLAction(action)
                pendingExternalURLAction = nil
            }
            Button("Cancel", role: .cancel) {
                pendingExternalURLAction = nil
            }
        } message: { action in
            Text(action.message)
        }
        .alert(
            "Enable JIT for LiveContainer?",
            isPresented: Binding(
                get: { pendingLiveContainerApp != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingLiveContainerApp = nil
                    }
                }
            ),
            presenting: pendingLiveContainerApp
        ) { app in
            Button("Cancel", role: .cancel) {
                pendingLiveContainerApp = nil
            }
            Button("Proceed") {
                pendingLiveContainerApp = nil
                enableJITForSelectedApp(bundleID: app.bundleID, name: app.name)
            }
        } message: { _ in
            Text("StikDebug isn't meant to enable JIT for LiveContainer manually. Select StikDebug in LiveContainer settings, enable \"Run with JIT\" for your app, then open your app normally. It will automatically jump back here.")
        }
        .alert(
            "Enable JIT for StikDebug?",
            isPresented: Binding(
                get: { pendingStikDebugApp != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingStikDebugApp = nil
                    }
                }
            ),
            presenting: pendingStikDebugApp
        ) { app in
            Button("Cancel", role: .cancel) {
                pendingStikDebugApp = nil
            }
            Button("Proceed") {
                pendingStikDebugApp = nil
                enableJITForSelectedApp(bundleID: app.bundleID, name: app.name)
            }
        } message: { _ in
            Text("StikDebug isn't meant to attach to itself. Enabling JIT for StikDebug serves no purpose. Select the app you want to enable JIT for instead.")
        }
        .fileImporter(
            isPresented: $isShowingPairingFilePicker,
            allowedContentTypes: PairingFileStore.supportedContentTypes,
            onCompletion: importPairingFile
        )
        .sheet(isPresented: $isShowingPIDJIT) {
            PIDJITConfigurationView { pid, scriptURL in
                enableJITByPID(pid, scriptURL: scriptURL)
            }
        }
        .sheet(item: $scriptRunModel) { model in
            NavigationStack {
                RunJSView(model: model)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { scriptRunModel = nil }
                        }
                    }
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    private func enableJITForSelectedApp(bundleID selectedBundle: String, name: String) {
        bundleID = selectedBundle
        Haptics.medium()
        startJITInBackground(bundleID: selectedBundle, displayName: name)
    }

    private func enableJITByPID(_ pid: Int, scriptURL: URL?) {
        var scriptData: Data?
        if let scriptURL {
            do {
                scriptData = try Data(contentsOf: scriptURL)
            } catch {
                showAlert(
                    title: "Unable to Read Script".localized,
                    message: error.localizedDescription,
                    showOk: true
                )
                return
            }
        }

        isShowingPIDJIT = false
        Haptics.medium()
        startJITInBackground(
            pid: pid,
            scriptData: scriptData,
            scriptName: scriptURL?.lastPathComponent
        )
    }

    private func handleAppear() {
        startTunnelInBackground()
        hasAppeared = true

        if let config = pendingJITEnableConfiguration {
            startJITInBackground(
                bundleID: config.bundleID,
                pid: config.pid,
                scriptData: config.scriptData,
                scriptName: config.scriptName,
                triggeredByURLScheme: true
            )
            pendingJITEnableConfiguration = nil
        }
    }

    private func handleScriptReadyNotification(_ notification: Notification) {
        guard let model = notification.userInfo?["model"] as? RunJSViewModel else {
            return
        }

        scriptRunModel = model
    }

    private func importPairingFile(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            do {
                try PairingFileStore.importFromPicker(url)
                markTunnelDisconnected()
                startTunnelInBackground()
                NotificationCenter.default.post(name: .pairingFileImported, object: nil)
                AlertPresenter.dismissPresentedAlert()
            } catch {
                LogManager.shared.addErrorLog("Failed to import pairing file: \(error.localizedDescription)")
            }
        case .failure(let error):
            LogManager.shared.addErrorLog("Pairing file picker failed: \(error.localizedDescription)")
        }
    }

    private func queryValue(_ names: [String], in components: URLComponents?) -> String? {
        guard let queryItems = components?.queryItems else { return nil }
        for name in names {
            if let rawValue = queryItems.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })?.value {
                let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty {
                    return value
                }
            }
        }
        return nil
    }

    private func handleExternalURL(_ url: URL) {
        guard let host = url.host()?.lowercased() else { return }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)

        switch host {
        case "enable-jit":
            var config = JITEnableConfiguration()
            if let pidStr = queryValue(["pid"], in: components), let pid = Int(pidStr) {
                config.pid = pid
            }
            if let bundleId = queryValue(["bundle-id", "bundleID", "bundle_id", "bundleId"], in: components) {
                config.bundleID = bundleId
            }
            if let scriptBase64URL = queryValue(["script-data", "scriptData", "script_data"], in: components)?.removingPercentEncoding {
                let base64 = base64URLToBase64(scriptBase64URL)
                if let scriptData = Data(base64Encoded: base64) {
                    config.scriptData = scriptData
                }
            }
            if let scriptName = queryValue(["script-name", "scriptName", "script_name"], in: components) {
                config.scriptName = scriptName
                if config.scriptData == nil {
                    if let namedScript = ScriptStore.script(named: scriptName) {
                        config.scriptData = namedScript.data
                        config.scriptName = namedScript.name
                    } else {
                        LogManager.shared.addWarningLog("Script \(scriptName) was not found in the scripts folder")
                    }
                }
            }
            if config.scriptData == nil, let bundleID = config.bundleID,
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
            if let pidStr = queryValue(["pid"], in: components) {
                if let pid = Int32(pidStr), pid > 0 {
                    pendingExternalURLAction = .killProcess(.pid(pid))
                }
            } else if let name = queryValue(["name", "process-name", "processName", "process_name"], in: components) {
                pendingExternalURLAction = .killProcess(.name(name))
            }
        case "launch-app":
            if let bundleId = queryValue(["bundle-id", "bundleID", "bundle_id", "bundleId"], in: components) {
                pendingExternalURLAction = .launchApp(bundleId)
            }
        default:
            break
        }
    }

    private func performExternalURLAction(_ action: HomeExternalAction) {
        switch action {
        case .enableJIT(let config):
            if hasAppeared {
                startJITInBackground(
                    bundleID: config.bundleID,
                    pid: config.pid,
                    scriptData: config.scriptData,
                    scriptName: config.scriptName,
                    triggeredByURLScheme: true
                )
            } else {
                pendingJITEnableConfiguration = config
            }
        case .killProcess(let target):
            markTunnelDisconnected()
            startTunnelInBackground(showErrorUI: false)
            DispatchQueue.global(qos: .userInitiated).async {
                sleep(1)
                do {
                    switch target {
                    case .pid(let pid):
                        try JITEnableContext.shared.killProcess(withPID: pid)
                    case .name(let name):
                        try JITEnableContext.shared.killProcess(withName: name)
                    }
                    DispatchQueue.main.async {
                        LogManager.shared.addInfoLog("Killed process \(target.description) via URL scheme")
                    }
                } catch {
                    DispatchQueue.main.async {
                        LogManager.shared.addErrorLog("Failed to kill process \(target.description): \(error.localizedDescription)")
                        showAlert(title: "Failed to Kill Process".localized, message: error.localizedDescription, showOk: true)
                    }
                }
            }
        case .launchApp(let bundleID):
            Haptics.medium()
            DispatchQueue.global(qos: .userInitiated).async {
                let _ = JITEnableContext.shared.launchAppWithoutDebug(bundleID, logger: nil)
            }
        }
    }

    private func debugFeedbackView(_ feedback: DebugFeedback) -> some View {
        HStack(spacing: 10) {
            if feedback.isWorking {
                ProgressView()
                    .controlSize(.small)
            }

            Text(feedback.message)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Capsule().fill(.ultraThinMaterial))
        .foregroundStyle(feedback.isError ? .red : .primary)
        .shadow(radius: 4)
        .padding(.horizontal, 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(feedback.message)
    }

    private func getJsCallback(_ script: Data, name: String? = nil, resumeBundleID: String? = nil) -> DebugAppCallback {
        return { pid, debugProxyHandle, remoteServerHandle, semaphore in
            let model = RunJSViewModel(pid: Int(pid),
                                       debugProxy: debugProxyHandle,
                                       remoteServer: remoteServerHandle,
                                       semaphore: semaphore,
                                       resumeBundleID: resumeBundleID)

            DispatchQueue.main.async {
                scriptRunModel = model
            }

            do {
                try model.runScript(data: script, name: name)
            } catch {
                semaphore.signal()
                DispatchQueue.main.async {
                    showAlert(title: "Error Occurred While Executing Script.".localized, message: error.localizedDescription, showOk: true)
                }
            }
        }
    }

    private func startJITInBackground(bundleID: String? = nil, pid: Int? = nil, scriptData: Data? = nil, scriptName: String? = nil, triggeredByURLScheme: Bool = false, displayName: String? = nil) {
        let targetName = displayName ?? bundleID ?? pid.map { String(format: "process %d".localized, $0) } ?? "app".localized
        let startingMessage = String(format: "Starting JIT for %@".localized, targetName)
        LogManager.shared.addInfoLog("Starting Debug for \(bundleID ?? String(pid ?? 0))")
        withAnimation {
            debugFeedback = DebugFeedback(message: startingMessage, isError: false, isWorking: true)
        }
        AccessibilityAnnouncer.announce(startingMessage)

        if triggeredByURLScheme {
            markTunnelDisconnected()
            startTunnelInBackground(showErrorUI: false)
        }

        DispatchQueue.global(qos: .background).async {
            let keepAliveLease = DebugKeepAliveLease()
            defer { keepAliveLease.invalidate() }

            if triggeredByURLScheme, !waitForJITPrerequisites() {
                DispatchQueue.main.async {
                    withAnimation {
                        debugFeedback = nil
                    }
                    showAlert(
                        title: "Failed to Enable JIT".localized,
                        message: "The device connection or Developer Disk Image wasn't ready in time. Open StikDebug directly, wait for it to finish connecting, then try again.".localized,
                        showOk: true
                    )
                }
                return
            }

            let finishProcessing: (Bool, String?) -> Void = { success, detail in
                DispatchQueue.main.async {
                    let message = success
                        ? String(format: "JIT request completed for %@".localized, targetName)
                        : String(format: "JIT failed for %@".localized, targetName)
                    let feedback = DebugFeedback(message: message, isError: !success, isWorking: false)
                    withAnimation {
                        debugFeedback = feedback
                    }
                    AccessibilityAnnouncer.announce(message)

                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        if debugFeedback?.id == feedback.id {
                            withAnimation {
                                debugFeedback = nil
                            }
                        }
                    }

                    if !success {
                        let failureMessage = detail ?? "StikDebug could not launch or attach to the selected app. Check that the VPN is enabled, the pairing file is current, and the app is still installed.".localized
                        showAlert(title: "Failed to Enable JIT".localized, message: failureMessage, showOk: true)
                    }
                }
            }

            var scriptData = scriptData
            var scriptName = scriptName
            if scriptData == nil,
               let bundleID,
               let preferred = ScriptStore.preferredScript(for: bundleID) {
                scriptName = preferred.name
                scriptData = preferred.data
            }

            let resumeBundleID = pid == nil ? nil : bundleID

            var callback: DebugAppCallback? = nil
            if ProcessInfo.processInfo.hasTXM, let sd = scriptData {
                callback = getJsCallback(sd, name: scriptName ?? bundleID ?? "Script", resumeBundleID: resumeBundleID)
            }

            var lastDebugMessage: String?
            let logger: LogFunc = { message in
                if let message {
                    lastDebugMessage = message
                    LogManager.shared.addInfoLog(message)
                }
            }
            var success: Bool
            if let pid {
                success = JITEnableContext.shared.debugApp(withPID: Int32(pid), logger: logger, jsCallback: callback)
            } else if let bundleID {
                success = JITEnableContext.shared.debugApp(withBundleID: bundleID, logger: logger, jsCallback: callback)
            } else {
                lastDebugMessage = "Either bundle ID or PID should be specified.".localized
                success = false
            }

            if success {
                DispatchQueue.main.async {
                    LogManager.shared.addInfoLog("Debug process completed for \(bundleID ?? String(pid ?? 0))")

                    if doAutoQuitAfterEnablingJIT {
                        exit(0)
                    }
                }
            }
            finishProcessing(success, success ? nil : lastDebugMessage)
        }
    }

    private func waitForJITPrerequisites(timeout: TimeInterval = 20) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if TunnelManager.shared.isConnected && MountingProgress.shared.coolisMounted {
                return true
            }
            usleep(250_000)
        }
        return TunnelManager.shared.isConnected && MountingProgress.shared.coolisMounted
    }

    private func base64URLToBase64(_ base64url: String) -> String {
        var base64 = base64url.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let pad = 4 - (base64.count % 4)
        if pad < 4 { base64 += String(repeating: "=", count: pad) }
        return base64
    }
}

private struct PIDJITConfigurationView: View {
    @Environment(\.dismiss) private var dismiss

    let onEnable: (Int, URL?) -> Void

    @State private var pidText = ""
    @State private var scriptSelection: (url: URL, suggestedPID: Int?)?
    @State private var isShowingScriptPicker = false

    private var pid: Int? {
        guard let value = Int(pidText), value > 0, value <= Int(Int32.max) else {
            return nil
        }
        return value
    }

    private var selectedScriptURL: URL? {
        guard let scriptSelection,
              scriptSelection.suggestedPID == nil || scriptSelection.suggestedPID == pid else { return nil }
        return scriptSelection.url
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Process") {
                    TextField("PID", text: $pidText)
                        .keyboardType(.numberPad)
                    Text("Enter the process identifier of a currently running app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    NavigationLink("Choose Running Process") {
                        PIDProcessPicker(onSelect: selectProcess)
                    }
                }

                Section("Script (Optional)") {
                    LabeledContent(
                        "Selected Script",
                        value: selectedScriptURL?.lastPathComponent ?? "None"
                    )

                    Button(selectedScriptURL == nil ? "Choose Script" : "Change Script") {
                        isShowingScriptPicker = true
                    }
                    .disabled(!ProcessInfo.processInfo.hasTXM)

                    if selectedScriptURL != nil {
                        Button("Remove Script", role: .destructive) {
                            scriptSelection = nil
                        }
                    }

                    if !ProcessInfo.processInfo.hasTXM {
                        Text("Script execution is disabled on this device.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Enable JIT by PID")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enable JIT") {
                        if let pid {
                            onEnable(pid, selectedScriptURL)
                        }
                    }
                    .disabled(pid == nil)
                }
            }
            .sheet(isPresented: $isShowingScriptPicker) {
                ScriptListView(allowsNoScript: false) { scriptURL in
                    scriptSelection = scriptURL.map { (url: $0, suggestedPID: nil) }
                    isShowingScriptPicker = false
                }
            }
        }
    }

    private func selectProcess(_ choice: PIDProcessPicker.Choice) {
        pidText = String(choice.process.pid)
        if scriptSelection?.suggestedPID != nil {
            scriptSelection = nil
        }
        guard ProcessInfo.processInfo.hasTXM, let bundleID = choice.bundleID else { return }

        if let assignedName = ScriptStore.assignedScriptName(for: bundleID),
           let url = try? ScriptStore.scriptURL(named: assignedName),
           FileManager.default.isReadableFile(atPath: url.path) {
            scriptSelection = (url, choice.process.pid)
        } else if #available(iOS 26, *),
                  let appName = choice.appName,
                  let resource = ScriptStore.autoScriptResource(for: appName),
                  let url = try? ScriptStore.scriptURL(named: resource.fileName),
                  FileManager.default.isReadableFile(atPath: url.path) {
            scriptSelection = (url, choice.process.pid)
        }
    }
}

private struct PIDProcessPicker: View {
    struct Choice: Identifiable {
        let process: ProcessInfoEntry
        let appName: String?
        let bundleID: String?

        var id: Int { process.pid }
        var title: String { appName ?? process.processName }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var choices: [Choice]?
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var loadError: String?

    let onSelect: (Choice) -> Void

    private var filteredChoices: [Choice] {
        let choices = choices ?? []
        guard !searchText.isEmpty else { return choices }
        return choices.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.process.processName.localizedCaseInsensitiveContains(searchText) ||
            String($0.process.pid).contains(searchText)
        }
    }

    var body: some View {
        let visibleChoices = filteredChoices
        List {
            if let loadError {
                Text(loadError)
                    .foregroundStyle(.secondary)
                Button("Try Again") { Task { await loadProcesses() } }
            } else if choices != nil && visibleChoices.isEmpty {
                Text("No matching processes.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(visibleChoices) { choice in
                    Button {
                        onSelect(choice)
                        dismiss()
                    } label: {
                        HStack {
                            Text(choice.title)
                            Spacer()
                            Text(choice.process.pidLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .overlay {
            if choices == nil && loadError == nil {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Loading Processes…")
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .navigationTitle("Running Processes")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText)
        .task {
            while !Task.isCancelled {
                await loadProcesses()
                do {
                    try await Task.sleep(for: .seconds(10))
                } catch {
                    break
                }
            }
        }
        .refreshable { await loadProcesses() }
    }

    private func loadProcesses() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await Task.detached(priority: .utility) {
                let context = JITEnableContext.shared
                let processes = try context.fetchProcessList().compactMap(ProcessInfoEntry.init(dictionary:))
                let apps = (try? context.getDebuggableAppProcessNames()) ?? []
                return processes.compactMap { process -> Choice? in
                    guard process.pid > 0, process.pid <= Int(Int32.max) else { return nil }
                    let path = process.executablePath
                    let decodedPath = path.removingPercentEncoding ?? path
                    let executablePath = (decodedPath as NSString).standardizingPath
                    let components = decodedPath.lowercased().split(separator: "/").map {
                        let component = String($0)
                        if component.hasSuffix(".app") || component.hasSuffix(".appex") {
                            return (component as NSString).deletingPathExtension
                        }
                        return component
                    }
                    let isLiveContainer = decodedPath.localizedCaseInsensitiveContains("livecontainer")
                    let pathMatches = apps.filter { app in
                        guard let appPath = app.path, !appPath.isEmpty else { return false }
                        let bundlePath = (appPath as NSString).standardizingPath
                        return executablePath.hasPrefix(bundlePath + "/")
                    }
                    let matches = pathMatches.isEmpty ? apps.filter { app in
                        components.contains(app.name.lowercased()) ||
                            components.contains(app.bundleID.lowercased()) ||
                            app.executable.map { components.contains($0.lowercased()) } == true
                    } : pathMatches
                    guard isLiveContainer || !matches.isEmpty else { return nil }
                    let match = matches.count == 1 ? matches.first : nil
                    return Choice(
                        process: process,
                        appName: match?.name,
                        bundleID: match?.bundleID
                    )
                }.sorted {
                    let order = $0.title.localizedStandardCompare($1.title)
                    return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
                }
            }.value
            guard !Task.isCancelled else { return }
            choices = loaded
            loadError = nil
        } catch {
            guard !Task.isCancelled else { return }
            loadError = error.localizedDescription
        }
    }
}

#Preview {
    HomeView()
}
