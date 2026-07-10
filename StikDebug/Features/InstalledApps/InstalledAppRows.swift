//
//  InstalledAppRows.swift
//  StikDebug
//

import SwiftUI
import UIKit

struct AppButton: View {
    let bundleID: String
    let appName: String
    let isFavorite: Bool
    let favoriteCount: Int

    @Binding var recentApps: [String]
    @Binding var favoriteApps: [String]

    @AppStorage("loadAppIconsOnJIT") private var loadAppIconsOnJIT = true
    @AppStorage("enableAdvancedOptions") private var enableAdvancedOptions = false

    var onSelectApp: (String, String) -> Void
    let isPerformingPrimaryAction: Bool

    @State private var showScriptPicker = false
    @State private var assignedScriptName: String?
    @StateObject private var iconLoader: IconLoader

    init(
        bundleID: String,
        appName: String,
        isFavorite: Bool,
        favoriteCount: Int,
        recentApps: Binding<[String]>,
        favoriteApps: Binding<[String]>,
        onSelectApp: @escaping (String, String) -> Void,
        isPerformingPrimaryAction: Bool
    ) {
        self.bundleID = bundleID
        self.appName = appName
        self.isFavorite = isFavorite
        self.favoriteCount = favoriteCount
        self._recentApps = recentApps
        self._favoriteApps = favoriteApps
        self.onSelectApp = onSelectApp
        self.isPerformingPrimaryAction = isPerformingPrimaryAction
        _iconLoader = StateObject(wrappedValue: IconLoader(bundleID: bundleID))
        _assignedScriptName = State(initialValue: AppButton.currentAssignment(for: bundleID))
    }

    var body: some View {
        Button(action: selectApp) {
            HStack(spacing: loadAppIconsOnJIT ? 16 : 12) {
                AppIconView(image: loadAppIconsOnJIT ? iconLoader.image : nil)

                VStack(alignment: .leading, spacing: 3) {
                    Text(appName)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(bundleID)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }

                Spacer()

                if isPerformingPrimaryAction {
                    ProgressView()
                        .controlSize(.small)
                } else if isFavorite {
                    Image(systemName: "star.fill")
                        .imageScale(.medium)
                        .foregroundStyle(.yellow)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, loadAppIconsOnJIT ? 4 : 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isPerformingPrimaryAction)
        .contextMenu {
            Button(action: toggleFavorite) {
                Label(
                    isFavorite ? "Remove Favorite" : "Add to Favorites",
                    systemImage: isFavorite ? "star.slash" : "star"
                )
                .disabled(!isFavorite && favoriteCount >= AppLibraryPreferences.maxFavorites)
            }
            Button {
                copyBundleID()
            } label: {
                Label("Copy Bundle ID", systemImage: "doc.on.doc")
            }
            if enableAdvancedOptions {
                Button {
                    showScriptPicker = true
                } label: {
                    Label("Assign Script", systemImage: "chevron.left.slash.chevron.right")
                }

                if assignedScriptName != nil {
                    Button(action: resetScriptAssignment) {
                        Label("Reset Script", systemImage: "arrow.uturn.left")
                    }
                }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                toggleFavorite()
            } label: {
                Label(isFavorite ? "Unfavorite" : "Favorite", systemImage: "star")
            }
            .tint(.yellow)

            Button {
                copyBundleID()
            } label: {
                Label("Copy ID", systemImage: "doc.on.doc")
            }
        }
        .sheet(isPresented: $showScriptPicker) {
            ScriptListView { url in
                assignScript(url)
                showScriptPicker = false
            }
        }
        .onAppear(perform: beginIconLoadingIfNeeded)
        .onChange(of: loadAppIconsOnJIT) { _, newValue in
            if newValue {
                iconLoader.beginLoading()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(format: "Enable JIT for %@".localized, appName))
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(isPerformingPrimaryAction
                           ? "A JIT request is in progress.".localized
                           : "Double-tap to open the app and enable JIT. Use the actions rotor for favorites or bundle ID.".localized)
        .accessibilityAddTraits(.isButton)
        .accessibilityRemoveTraits(.isStaticText)
        .accessibilityAction(named: Text(favoriteAccessibilityActionLabel)) {
            toggleFavorite()
        }
        .accessibilityAction(named: Text("Copy Bundle ID".localized)) {
            copyBundleID()
        }
    }

    private var accessibilityValue: String {
        var parts = [String(format: "Bundle ID %@".localized, bundleID)]
        if isFavorite {
            parts.append("Favorite".localized)
        }
        if let assignedScriptName {
            parts.append(String(format: "Assigned script %@".localized, assignedScriptName))
        }
        return parts.joined(separator: ", ")
    }

    private var favoriteAccessibilityActionLabel: String {
        isFavorite
            ? "Remove from Favorites".localized
            : "Add to Favorites".localized
    }

    private func beginIconLoadingIfNeeded() {
        guard loadAppIconsOnJIT else {
            return
        }
        iconLoader.beginLoading()
    }

    private func selectApp() {
        Haptics.selection()
        recentApps.removeAll { $0 == bundleID }
        recentApps.insert(bundleID, at: 0)
        if recentApps.count > AppLibraryPreferences.maxRecents {
            recentApps = Array(recentApps.prefix(AppLibraryPreferences.maxRecents))
        }
        onSelectApp(bundleID, appName)
    }

    private func toggleFavorite() {
        Haptics.light()

        if isFavorite {
            favoriteApps.removeAll { $0 == bundleID }
            AccessibilityAnnouncer.announce("Removed from Favorites".localized)
        } else if favoriteCount < AppLibraryPreferences.maxFavorites {
            favoriteApps.insert(bundleID, at: 0)
            recentApps.removeAll { $0 == bundleID }
            AccessibilityAnnouncer.announce("Added to Favorites".localized)
        } else {
            AccessibilityAnnouncer.announce("Favorites are full".localized)
        }
    }

    private func copyBundleID() {
        UIPasteboard.general.string = bundleID
        Haptics.light()
        AccessibilityAnnouncer.announce("Bundle ID copied".localized)
    }

    private func assignScript(_ url: URL?) {
        if let url {
            let filename = url.lastPathComponent
            ScriptStore.updateAssignedScriptName(filename, for: bundleID)
            assignedScriptName = filename
        } else {
            ScriptStore.updateAssignedScriptName(nil, for: bundleID)
            assignedScriptName = nil
        }
        Haptics.light()
    }

    private func resetScriptAssignment() {
        assignScript(nil)
    }

    private static func currentAssignment(for bundleID: String) -> String? {
        ScriptStore.assignedScriptName(for: bundleID)
    }

}

struct LaunchAppRow: View {
    let bundleID: String
    let appName: String
    let isLaunching: Bool
    var launchAction: () -> Void

    @AppStorage("loadAppIconsOnJIT") private var loadAppIconsOnJIT = true
    @StateObject private var iconLoader: IconLoader

    init(
        bundleID: String,
        appName: String,
        isLaunching: Bool,
        launchAction: @escaping () -> Void
    ) {
        self.bundleID = bundleID
        self.appName = appName
        self.isLaunching = isLaunching
        self.launchAction = launchAction
        _iconLoader = StateObject(wrappedValue: IconLoader(bundleID: bundleID))
    }

    var body: some View {
        Button {
            guard !isLaunching else { return }
            launchAction()
        } label: {
            HStack(spacing: loadAppIconsOnJIT ? 16 : 12) {
                AppIconView(image: loadAppIconsOnJIT ? iconLoader.image : nil)

                VStack(alignment: .leading, spacing: 3) {
                    Text(appName)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(bundleID)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }

                Spacer()

                if isLaunching {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Launch".localized)
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.accentColor.opacity(0.18)))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.vertical, loadAppIconsOnJIT ? 4 : 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isLaunching)
        .onAppear(perform: beginIconLoadingIfNeeded)
        .onChange(of: loadAppIconsOnJIT) { _, newValue in
            if newValue {
                iconLoader.beginLoading()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(format: "Launch %@".localized, appName))
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(isLaunching
                           ? "Launch request in progress.".localized
                           : "Double-tap to launch this app without enabling JIT.".localized)
        .accessibilityAddTraits(.isButton)
        .accessibilityRemoveTraits(.isStaticText)
        .accessibilityAction(named: Text("Launch App".localized)) {
            guard !isLaunching else { return }
            launchAction()
        }
    }

    private var accessibilityValue: String {
        let state = isLaunching ? "Launching".localized : "Ready".localized
        return "\(state), \(String(format: "Bundle ID %@".localized, bundleID))"
    }

    private func beginIconLoadingIfNeeded() {
        guard loadAppIconsOnJIT else {
            return
        }
        iconLoader.beginLoading()
    }
}

private struct AppIconView: View {
    let image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 54, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: .black.opacity(0.18), radius: 3, x: 0, y: 1.5)
                    .transition(.opacity.combined(with: .scale))
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(UIColor.systemGray5))
                    .frame(width: 54, height: 54)
                    .overlay {
                        Image(systemName: "app")
                            .font(.system(size: 24, weight: .regular))
                            .foregroundStyle(.gray)
                    }
            }
        }
        .accessibilityHidden(true)
    }
}
