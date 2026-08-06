//  SettingsView.swift
//  StikDebug
//
//  Created by Stephen on 3/27/25.

import SwiftUI
import UIKit

private enum SettingsLinks {
    static let githubStars = URL(string: "https://github.com/StikDebug/StikDebug/stargazers")!
    static let pairingFileGuide = URL(string: "https://github.com/StikDebug/StikDebug-Guide/blob/main/pairing_file.md")!
    static let localDevVPN = URL(string: "https://apps.apple.com/us/app/localdevvpn/id6755608044")!
    static let discord = URL(string: "https://discord.gg/qahjXNTDwS")!
}

private struct DeviceProfileEditorConfiguration: Identifiable {
    let id = UUID()
    let profile: DeviceProfile?
}

private struct DeviceProfileDraft {
    let name: String
    let ipAddress: String
    let pairingFileData: Data?
}

struct SettingsView: View {
    @State private var activeDeviceName = DeviceProfileStore.selectedProfile().name
    @State private var showDDIConfirmation = false
    @State private var isRedownloadingDDI = false
    @State private var ddiDownloadProgress: Double = 0.0
    @State private var ddiStatusMessage: String = ""
    @State private var ddiResultMessage: (text: String, isError: Bool)?

    private var appVersion: String {
        let marketingVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return marketingVersion
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 12) {
                            Image("StikDebug")
                                .resizable().aspectRatio(contentMode: .fit)
                                .frame(width: 80, height: 80)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            Text("StikDebug").font(.title2.weight(.semibold))
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                    .padding(.vertical, 8)
                }

                Section {
                    Link(destination: SettingsLinks.githubStars) {
                        Label("Star on GitHub", systemImage: "star")
                    }
                }

                Section("Device Profiles") {
                    NavigationLink {
                        DeviceProfilesManagerView()
                    } label: {
                        LabeledContent("Active Device", value: activeDeviceName)
                    }
                }

                Section("Advanced") {
                    Button { openAppFolder() } label: {
                        Label("App Folder", systemImage: "folder")
                    }.foregroundStyle(.primary)
                    Button { showDDIConfirmation = true } label: {
                        Label("Redownload DDI", systemImage: "arrow.down.circle")
                    }.foregroundStyle(.primary).disabled(isRedownloadingDDI)
                    if isRedownloadingDDI {
                        VStack(alignment: .leading, spacing: 4) {
                            ProgressView(value: ddiDownloadProgress, total: 1.0)
                            Text(ddiStatusMessage).font(.caption).foregroundStyle(.secondary)
                        }
                    } else if let result = ddiResultMessage {
                        Text(result.text).font(.caption).foregroundStyle(result.isError ? .red : .green)
                    }
                }

                Section("Help") {
                    Link(destination: SettingsLinks.pairingFileGuide) {
                        Label("Pairing File Guide", systemImage: "questionmark.circle")
                    }
                    Link(destination: SettingsLinks.localDevVPN) {
                        Label("Download LocalDevVPN", systemImage: "arrow.down.circle")
                    }
                    Link(destination: SettingsLinks.discord) {
                        Label("Discord Support", systemImage: "bubble.left.and.bubble.right")
                    }
                }

                Section {
                    Text(versionFooter)
                        .font(.footnote).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                refreshActiveDevice()
            }
            .onReceive(NotificationCenter.default.publisher(for: .pairingFileImported)) { _ in
                refreshActiveDevice()
            }
        }
        .confirmationDialog("Redownload DDI Files?", isPresented: $showDDIConfirmation, titleVisibility: .visible) {
            Button("Redownload", role: .destructive) {
                redownloadDDIPressed()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Existing DDI files will be removed before downloading fresh copies.")
        }
    }

    private var versionFooter: String {
        let processInfo = ProcessInfo.processInfo
        let txmLabel: String
        txmLabel = processInfo.hasDetectedTXM ? "TXM" : "Non TXM"
        return "Version \(appVersion) • iOS \(UIDevice.current.systemVersion) • \(txmLabel)"
    }

    private func refreshActiveDevice() {
        activeDeviceName = DeviceProfileStore.selectedProfile().name
    }

    // MARK: - Business Logic

    private func openAppFolder() {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let path = documentsURL.absoluteString.replacingOccurrences(of: "file://", with: "shareddocuments://")
        if let url = URL(string: path) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }

    private func redownloadDDIPressed() {
        guard !isRedownloadingDDI else { return }
        Task {
            await MainActor.run {
                isRedownloadingDDI = true
                ddiDownloadProgress = 0
                ddiStatusMessage = "Preparing download…"
                ddiResultMessage = nil
            }
            do {
                try await redownloadDDI { progress, status in
                    Task { @MainActor in
                        self.ddiDownloadProgress = progress
                        self.ddiStatusMessage = status
                    }
                }
                await MainActor.run {
                    isRedownloadingDDI = false
                    ddiResultMessage = ("DDI files refreshed successfully.", false)
                }
            } catch {
                await MainActor.run {
                    isRedownloadingDDI = false
                    ddiResultMessage = ("Failed to redownload DDI files: \(error.localizedDescription)", true)
                }
            }
        }
        scheduleDDIStatusDismiss()
    }

    private func scheduleDDIStatusDismiss() {
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            await MainActor.run {
                if !isRedownloadingDDI {
                    ddiResultMessage = nil
                }
            }
        }
    }
}

private struct DeviceProfilesManagerView: View {
    @State private var profiles = DeviceProfileStore.profiles()
    @State private var selectedProfileID = DeviceProfileStore.selectedProfileID()
    @State private var profileEditor: DeviceProfileEditorConfiguration?

    var body: some View {
        List {
            Section {
                ForEach(profiles) { profile in
                    NavigationLink {
                        DeviceProfileDetailView(profileID: profile.id) {
                            reload()
                        }
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(profile.name)
                                    if profile.id == selectedProfileID {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                    }
                                }
                                Text(profile.ipAddress)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section {
                Button {
                    profileEditor = DeviceProfileEditorConfiguration(profile: nil)
                } label: {
                    Label("Add Device", systemImage: "plus")
                }
            }
        }
        .navigationTitle("Device Profiles")
        .onAppear {
            reload()
        }
        .sheet(item: $profileEditor) { configuration in
            DeviceProfileEditorView(profile: configuration.profile, allowsPairingImport: true) { draft in
                guard let pairingFileData = draft.pairingFileData else {
                    throw NSError(
                        domain: "StikDebug.DeviceProfile",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Select a pairing file before adding the device."]
                    )
                }

                let candidate = DeviceProfile(
                    id: UUID().uuidString,
                    name: draft.name,
                    ipAddress: draft.ipAddress,
                    runScripts: false
                )
                let inspection = try await inspectDevice(
                    profile: candidate,
                    pairingFileData: pairingFileData
                )
                let profile = DeviceProfileStore.addProfile(
                    name: draft.name,
                    ipAddress: draft.ipAddress,
                    runScripts: inspection.hasTXM,
                    txmDetected: inspection.hasTXM
                )
                do {
                    try PairingFileStore.replace(with: pairingFileData, for: profile.id)
                } catch {
                    try? PairingFileStore.remove(for: profile.id)
                    DeviceProfileStore.delete(profile.id)
                    throw error
                }
                DeviceProfileStore.activate(profile.id)
                reload()
            }
        }
    }

    private func reload() {
        profiles = DeviceProfileStore.profiles()
        selectedProfileID = DeviceProfileStore.selectedProfileID()
    }
}

private struct DeviceProfileDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var mounting = MountingProgress.shared

    @AppStorage(UserDefaults.Keys.confirmExternalJITRequests) private var confirmExternalJITRequests = true
    @AppStorage("keepAliveAudio") private var keepAliveAudio = true
    @AppStorage("keepAliveLocation") private var keepAliveLocation = true

    let profileID: String
    let onChange: () -> Void

    @State private var profile: DeviceProfile
    @State private var profileEditor: DeviceProfileEditorConfiguration?
    @State private var isShowingPairingFilePicker = false
    @State private var showDeleteConfirmation = false
    @State private var statusMessage: String?
    @State private var showingError = false
    @State private var isConnected: Bool?

    init(profileID: String, onChange: @escaping () -> Void) {
        self.profileID = profileID
        self.onChange = onChange
        _profile = State(
            initialValue: DeviceProfileStore.profiles().first(where: { $0.id == profileID })
                ?? DeviceProfileStore.localProfile
        )
    }

    private var isSelected: Bool {
        DeviceProfileStore.selectedProfileID() == profile.id
    }

    private var hasPairingFile: Bool {
        PairingFileStore.hasPairingFile(for: profile.id)
    }

    private var txmDetected: Bool? {
        profile.isLocal ? ProcessInfo.processInfo.hasDetectedTXM : profile.txmDetected
    }

    private var isDDIMounted: Bool {
        isSelected && mounting.coolisMounted
    }

    var body: some View {
        Form {
            Section("Profile") {
                LabeledContent("Name", value: profile.name)
                LabeledContent("IP Address", value: profile.ipAddress)
                LabeledContent("Status", value: isSelected ? "Active" : "Inactive")

                if !isSelected {
                    Button("Use This Device") {
                        DeviceProfileStore.activate(profile.id)
                        onChange()
                    }
                }

                if !profile.isLocal {
                    Button("Edit Device") {
                        profileEditor = DeviceProfileEditorConfiguration(profile: profile)
                    }
                }
            }

            Section {
                deviceStatusRow
            }

            if profile.isLocal {
                Section("Local Connection") {
                    Label {
                        Text("Ensure that LocalDevVPN is connected and that either Wi-Fi is connected or Airplane Mode is enabled.")
                    } icon: {
                        Image(systemName: "info.circle")
                    }
                }
            }

            Section("Pairing File") {
                Label(
                    hasPairingFile ? "Pairing File Detected" : "Pairing File Missing",
                    systemImage: hasPairingFile ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                )
                .foregroundStyle(hasPairingFile ? .green : .orange)

                Button(hasPairingFile ? "Replace Pairing File" : "Add Pairing File") {
                    isShowingPairingFilePicker = true
                }

                if profile.isLocal {
                    Text("The Local profile uses pairingFile.plist in the app's Documents folder.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section(profile.isLocal ? "Scripts & Behavior" : "Scripts") {
                if let txmDetected {
                    Label(
                        txmDetected ? "TXM Detected" : "TXM Not Detected",
                        systemImage: txmDetected ? "checkmark.circle.fill" : "xmark.circle.fill"
                    )
                    .foregroundStyle(txmDetected ? .green : .secondary)
                } else {
                    Label("TXM Status Unknown", systemImage: "questionmark.circle.fill")
                        .foregroundStyle(.secondary)
                }

                Toggle(isOn: Binding(
                    get: { profile.runScripts },
                    set: { enabled in
                        profile.runScripts = enabled
                        DeviceProfileStore.update(profile)
                        onChange()
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Run Scripts")
                        Text("Controls whether automatic and assigned scripts run for this device.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if profile.isLocal {
                    Toggle(isOn: $confirmExternalJITRequests) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Confirm JIT Links")
                            Text("Ask before external links enable JIT or run scripts.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if profile.isLocal {
                Section("Background Keep-Alive") {
                    Toggle(isOn: $keepAliveAudio) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Silent Audio")
                            Text("Plays inaudible audio so iOS keeps the app running.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onChange(of: keepAliveAudio) { _, enabled in
                        if enabled { BackgroundAudioManager.shared.start() }
                        else { BackgroundAudioManager.shared.stop() }
                    }

                    Toggle(isOn: $keepAliveLocation) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Background Location")
                            Text("Uses low-accuracy location to stay alive when an activity needs it.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onChange(of: keepAliveLocation) { _, enabled in
                        if !enabled { BackgroundLocationManager.shared.stop() }
                    }
                }
            }

            if !profile.isLocal {
                Section {
                    Button("Delete Device", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                }
            }
        }
        .navigationTitle(profile.name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(profile.id)-\(profile.ipAddress)") {
            await monitorDeviceStatus()
        }
        .fileImporter(
            isPresented: $isShowingPairingFilePicker,
            allowedContentTypes: PairingFileStore.supportedContentTypes,
            allowsMultipleSelection: false
        ) { result in
            importPairingFile(result)
        }
        .sheet(item: $profileEditor) { configuration in
            DeviceProfileEditorView(profile: configuration.profile, allowsPairingImport: false) { draft in
                let wasSelected = isSelected
                profile.name = draft.name
                profile.ipAddress = draft.ipAddress
                DeviceProfileStore.update(profile)
                if wasSelected {
                    DeviceProfileStore.activate(profile.id)
                }
                onChange()
            }
        }
        .confirmationDialog(
            "Delete \(profile.name)?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Device", role: .destructive) {
                deleteProfile()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The device profile and its stored pairing file will be removed.")
        }
        .alert("Device Profile", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(statusMessage ?? "The operation failed.")
        }
    }

    private func importPairingFile(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            try PairingFileStore.importFromPicker(url, for: profile.id)
            statusMessage = "Pairing file imported successfully."
            if isSelected {
                DeviceProfileStore.activate(profile.id)
            }
            onChange()
        } catch {
            statusMessage = "Import failed: \(error.localizedDescription)"
            showingError = true
        }
    }

    @ViewBuilder
    private var deviceStatusRow: some View {
        if canMountDDI {
            Button(action: mountDDI) {
                deviceStatusContent
            }
            .buttonStyle(.plain)
        } else {
            deviceStatusContent
        }
    }

    private var deviceStatusContent: some View {
        HStack {
            Text("Device Status")
                .foregroundStyle(.primary)
            Spacer()
            HStack(spacing: 4) {
                if isConnected == nil {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: deviceStatusSymbol)
                }
                Text(deviceStatusText)
            }
            .foregroundStyle(deviceStatusColor)
        }
    }

    private var deviceStatusText: String {
        guard isConnected == true else { return "Disconnected" }
        return isDDIMounted ? "Ready" : "DDI Unmounted"
    }

    private var deviceStatusSymbol: String {
        isDDIMounted ? "checkmark.circle.fill" : "xmark.circle.fill"
    }

    private var deviceStatusColor: Color {
        guard isConnected == true else {
            return isConnected == nil ? .secondary : .red
        }
        return isDDIMounted ? .green : .orange
    }

    private var canMountDDI: Bool {
        isConnected == true && !isDDIMounted && mounting.mountingThread == nil
    }

    private func monitorDeviceStatus() async {
        while !Task.isCancelled {
            let monitoredProfile = profile
            let connected = await DeviceConnectionContext.isReachable(monitoredProfile)
            guard !Task.isCancelled, monitoredProfile == profile else { return }

            let shouldCheckDDI = connected && isConnected != true
            isConnected = connected
            if shouldCheckDDI, DeviceProfileStore.selectedProfileID() == monitoredProfile.id {
                mounting.checkforMounted()
            }

            do {
                try await Task.sleep(nanoseconds: 3_000_000_000)
            } catch {
                return
            }
        }
    }

    private func mountDDI() {
        guard canMountDDI else { return }

        if !isSelected {
            DeviceProfileStore.activate(profile.id)
            isConnected = nil
            onChange()
        }
        mounting.pubMount()
    }

    private func deleteProfile() {
        do {
            let wasSelected = isSelected
            try PairingFileStore.remove(for: profile.id)
            DeviceProfileStore.delete(profile.id)
            if wasSelected {
                DeviceProfileStore.activate(DeviceProfileStore.localProfileID)
            }
            onChange()
            dismiss()
        } catch {
            statusMessage = "Delete failed: \(error.localizedDescription)"
            showingError = true
        }
    }
}

private struct DeviceProfileEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let profile: DeviceProfile?
    let allowsPairingImport: Bool
    let onSave: (DeviceProfileDraft) async throws -> Void

    @State private var name: String
    @State private var ipAddress: String
    @State private var pairingFileData: Data?
    @State private var pairingFileName: String?
    @State private var isShowingPairingFilePicker = false
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var isSaving = false

    init(
        profile: DeviceProfile?,
        allowsPairingImport: Bool,
        onSave: @escaping (DeviceProfileDraft) async throws -> Void
    ) {
        self.profile = profile
        self.allowsPairingImport = allowsPairingImport
        self.onSave = onSave
        _name = State(initialValue: profile?.name ?? "")
        _ipAddress = State(initialValue: profile?.ipAddress ?? "")
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        DeviceProfileStore.isValidIPv4Address(ipAddress) &&
        (!allowsPairingImport || pairingFileData != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile") {
                    TextField("Device Name", text: $name)
                        .textInputAutocapitalization(.words)

                    TextField("IP Address", text: $ipAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .keyboardType(.numbersAndPunctuation)
                }

                if allowsPairingImport {
                    Section("Pairing File") {
                        Button(pairingFileData == nil ? "Add Pairing File" : "Replace Pairing File") {
                            isShowingPairingFilePicker = true
                        }
                        if let pairingFileName {
                            Label("\(pairingFileName) selected", systemImage: "doc.badge.checkmark")
                                .foregroundStyle(.green)
                        }
                    }
                }

                if isSaving {
                    Section {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Connecting and checking TXM capability…")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(profile == nil ? "Add Device" : "Edit Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(profile == nil ? "Add" : "Save") {
                        isSaving = true
                        Task {
                            do {
                                try await onSave(DeviceProfileDraft(
                                    name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                    ipAddress: ipAddress.trimmingCharacters(in: .whitespacesAndNewlines),
                                    pairingFileData: pairingFileData
                                ))
                                dismiss()
                            } catch {
                                errorMessage = error.localizedDescription
                                showingError = true
                                isSaving = false
                            }
                        }
                    }
                    .disabled(!canSave || isSaving)
                }
            }
        }
        .fileImporter(
            isPresented: $isShowingPairingFilePicker,
            allowedContentTypes: PairingFileStore.supportedContentTypes,
            allowsMultipleSelection: false
        ) { result in
            loadPairingFile(result)
        }
        .alert("Pairing File", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "The pairing file could not be loaded.")
        }
    }

    private func loadPairingFile(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            pairingFileData = try Data(contentsOf: url)
            pairingFileName = url.lastPathComponent
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}

private func inspectDevice(
    profile: DeviceProfile,
    pairingFileData: Data
) async throws -> DeviceConnectionInspection {
    try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                continuation.resume(
                    returning: try JITEnableContext.shared.inspectDevice(
                        profile: profile,
                        pairingFileData: pairingFileData
                    )
                )
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
