//
//  SettingsView.swift
//  StikDebug
//
//  Created by Stephen on 3/27/25.
//

import SwiftUI
import UIKit

private enum SettingsLinks {
    static let githubStars = URL(string: "https://github.com/StephenDev0/StikDebug/stargazers")!
    static let pairingFileGuide = URL(string: "https://github.com/StephenDev0/StikDebug-Guide/blob/main/pairing_file.md")!
    static let localDevVPN = URL(string: "https://apps.apple.com/us/app/localdevvpn/id6755608044")!
    static let discord = URL(string: "https://discord.gg/qahjXNTDwS")!
}

struct SettingsView: View {
    @AppStorage(UserDefaults.Keys.txmOverride) private var overrideTXMDetection = false
    @AppStorage(UserDefaults.Keys.confirmExternalJITRequests) private var confirmExternalJITRequests = true
    @AppStorage(UserDefaults.Keys.immortalized) private var immortalized = false
    @AppStorage(UserDefaults.Keys.targetDeviceIP) private var targetDeviceIP = DeviceConnectionContext.defaultTargetIPAddress

    @ObservedObject private var pairingImport = PairingFileImportCoordinator.shared
    @State private var showDDIConfirmation = false
    @State private var isRedownloadingDDI = false
    @State private var ddiDownloadProgress: Double = 0.0
    @State private var ddiStatusMessage: String = ""
    @State private var ddiResultMessage: (text: String, isError: Bool)?

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Preferences") {
                    Toggle(isOn: $immortalized) {
                        SettingsHubRow(
                            title: "Immortalizer",
                            detail: "Keep StikDebug alive in the background",
                            systemImage: "hourglass.bottomhalf.fill",
                            style: .palette(.indigo)
                        )
                    }
                    .onChange(of: immortalized) { _, _ in
                        ImmortalizerBridge.notifyPreferenceChanged()
                    }

                    Toggle(isOn: $confirmExternalJITRequests) {
                        SettingsHubRow(
                            title: "Confirm JIT Links",
                            detail: "Ask before external links enable JIT or run scripts",
                            systemImage: "hand.raised.fill",
                            style: .palette(.orange)
                        )
                    }

                    Toggle(isOn: $overrideTXMDetection) {
                        SettingsHubRow(
                            title: "Always Run Scripts",
                            detail: "Treat device as TXM-capable to bypass checks",
                            systemImage: "chevron.left.forwardslash.chevron.right",
                            style: .palette(.purple)
                        )
                    }
                }

                Section("Device") {
                    Button {
                        pairingImport.requestImport()
                    } label: {
                        SettingsHubRow(
                            title: "Import Pairing File",
                            detail: "Required for device tools",
                            systemImage: "doc.badge.plus",
                            style: .palette(.blue)
                        )
                    }
                    .buttonStyle(.plain)

                    if let feedback = pairingImport.feedback {
                        SettingsHubRow(
                            title: feedback.message,
                            detail: feedback.isError ? "Import failed" : "Import succeeded",
                            systemImage: feedback.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
                            style: feedback.isError ? .warning : .success
                        )
                    }

                    HStack(spacing: 14) {
                        HubIconBadge(systemImage: "network", style: .palette(.teal))

                        Text("Target Device IP")
                            .font(.body.weight(.semibold))

                        Spacer(minLength: 8)

                        TextField(DeviceConnectionContext.defaultTargetIPAddress, text: $targetDeviceIP)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.secondary)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .keyboardType(.numbersAndPunctuation)
                            .frame(maxWidth: 150)
                    }
                    .padding(.vertical, 4)

                    Button {
                        openAppFolder()
                    } label: {
                        SettingsHubRow(
                            title: "App Folder",
                            detail: "Open Documents in Files",
                            systemImage: "folder.fill",
                            style: .palette(.cyan)
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        showDDIConfirmation = true
                    } label: {
                        SettingsHubRow(
                            title: "Redownload DDI",
                            detail: isRedownloadingDDI ? ddiStatusMessage : "Refresh developer disk image files",
                            systemImage: "arrow.down.circle.fill",
                            style: .palette(.green)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isRedownloadingDDI)

                    if isRedownloadingDDI {
                        ProgressView(value: ddiDownloadProgress, total: 1.0)
                            .padding(.vertical, 4)
                    } else if let result = ddiResultMessage {
                        SettingsHubRow(
                            title: result.text,
                            detail: result.isError ? "Try again" : "Complete",
                            systemImage: result.isError ? "xmark.circle.fill" : "checkmark.circle.fill",
                            style: result.isError ? .danger : .success
                        )
                    }
                }

                Section("About") {
                    HStack(spacing: 14) {
                        Image("StikDebug")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("StikDebug")
                                .font(.body.weight(.semibold))
                            Text(brandSubtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 4)

                    Link(destination: SettingsLinks.githubStars) {
                        SettingsHubRow(
                            title: "Star on GitHub",
                            detail: "Support the project",
                            systemImage: "star.fill",
                            style: .palette(.yellow)
                        )
                    }

                    Link(destination: SettingsLinks.pairingFileGuide) {
                        SettingsHubRow(
                            title: "Pairing File Guide",
                            detail: "How to generate a pairing file",
                            systemImage: "questionmark.circle.fill",
                            style: .palette(.indigo)
                        )
                    }

                    Link(destination: SettingsLinks.localDevVPN) {
                        SettingsHubRow(
                            title: "LocalDevVPN",
                            detail: "Download the required loopback VPN",
                            systemImage: "arrow.down.app.fill",
                            style: .palette(.blue)
                        )
                    }

                    Link(destination: SettingsLinks.discord) {
                        SettingsHubRow(
                            title: "Discord Support",
                            detail: "Get help from the community",
                            systemImage: "bubble.left.and.bubble.right.fill",
                            style: .palette(.purple)
                        )
                    }

                    Link(destination: URL(string: "https://github.com/sergealagon/ImmortalizerJailed")!) {
                        SettingsHubRow(
                            title: "ImmortalizerJailed",
                            detail: "Keep-alive by Serge Alagon",
                            systemImage: "link",
                            style: .palette(.mint)
                        )
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
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

    private var brandSubtitle: String {
        let processInfo = ProcessInfo.processInfo
        let txmLabel: String
        if processInfo.isTXMOverridden {
            txmLabel = "TXM (Override)"
        } else {
            txmLabel = processInfo.hasTXM ? "TXM" : "Non TXM"
        }
        return "v\(appVersion) · iOS \(UIDevice.current.systemVersion) · \(txmLabel)"
    }

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
                try await DeveloperDiskImageService.shared.redownload { progress, status in
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

// MARK: - Shared settings row chrome (matches tools hub)

struct SettingsHubRow: View {
    let title: String
    let detail: String
    let systemImage: String
    var style: HubIconStyle = .palette(.blue)

    var body: some View {
        HStack(spacing: 14) {
            HubIconBadge(systemImage: systemImage, style: style)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(detail)")
    }
}

#Preview {
    SettingsView()
}
