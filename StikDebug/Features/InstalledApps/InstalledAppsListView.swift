//
//  InstalledAppsListView.swift
//  StikDebug
//
//  Created by Stossy11 on 28/03/2025.
//

import SwiftUI
import UIKit

enum InstalledAppsListMode: Hashable {
    /// JIT-eligible apps only (Home / JIT tab).
    case jit
    /// Launch installed apps without attaching JIT (Tools).
    case launch
}

struct InstalledAppsListView: View {
    @Environment(\.dismiss) private var dismiss

    let mode: InstalledAppsListMode
    let onSelectApp: (String, String) -> Void
    let showDoneButton: Bool
    let onImportPairingFile: (() -> Void)?
    let isJITOperationInFlight: Bool
    /// When false, assumes an outer NavigationStack (e.g. Tools push).
    let embedsNavigation: Bool

    @StateObject private var viewModel = InstalledAppsViewModel()

    @AppStorage("recentApps") private var recentApps: [String] = []
    @AppStorage("favoriteApps") private var favoriteApps: [String] = []
    @AppStorage("loadAppIconsOnJIT") private var loadAppIconsOnJIT = true
    @AppStorage("pinnedSystemApps") private var pinnedSystemApps: [String] = []
    @AppStorage("pinnedSystemAppNames") private var pinnedSystemAppNames: [String: String] = [:]

    @State private var launchingBundles: Set<String> = []
    @State private var toast: StatusToast?
    @State private var searchText = ""
    @State private var prefetchedBundleIDs: Set<String> = []
    @State private var favoriteBundleSet: Set<String> = []

    private static let iconPrefetchLimit = 24

    init(
        mode: InstalledAppsListMode = .jit,
        onSelectApp: @escaping (String, String) -> Void,
        showDoneButton: Bool = true,
        onImportPairingFile: (() -> Void)? = nil,
        isJITOperationInFlight: Bool = false,
        embedsNavigation: Bool = true
    ) {
        self.mode = mode
        self.onSelectApp = onSelectApp
        self.showDoneButton = showDoneButton
        self.onImportPairingFile = onImportPairingFile
        self.isJITOperationInFlight = isJITOperationInFlight
        self.embedsNavigation = embedsNavigation
    }

    var body: some View {
        Group {
            if embedsNavigation {
                NavigationStack {
                    listRoot
                }
            } else {
                listRoot
            }
        }
        .statusToast($toast)
        .onAppear {
            favoriteBundleSet = Set(favoriteApps)
            refreshIconPrefetch()
        }
        .onChange(of: favoriteApps) { _, newValue in
            favoriteBundleSet = Set(newValue)
            handleFavoritesChange()
        }
        .onChange(of: recentApps) { _, _ in
            prefetchPriorityIcons()
            syncLibraryPreferences()
        }
        .onChange(of: pinnedSystemApps) { _, _ in
            prefetchPriorityIcons()
            syncLibraryPreferences()
        }
        .onChange(of: pinnedSystemAppNames) { _, _ in syncLibraryPreferences() }
        .onChange(of: viewModel.isLoading) { _, isLoading in
            handleLoadingChange(isLoading)
        }
        .onReceive(NotificationCenter.default.publisher(for: .pairingFileImported)) { _ in
            viewModel.refreshAppLists()
        }
    }

    private var listRoot: some View {
        listContent
            .navigationTitle(mode.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: mode.searchPrompt
            )
            .toolbar {
                leadingToolbarItem
                trailingToolbarItem
            }
    }

    private var debuggableSnapshot: DebuggableAppListSnapshot {
        let query = InstalledAppListItem.normalized(searchText)
        let filteredApps = query.isEmpty
            ? viewModel.debuggableItems
            : viewModel.debuggableItems.filter { $0.matches(query) }
        let filteredBundleIDs = Set(filteredApps.map(\.bundleID))
        let favoriteBundles = favoriteApps.filter { filteredBundleIDs.contains($0) }
        let recentBundles = recentApps.filter {
            filteredBundleIDs.contains($0) && !favoriteBundles.contains($0)
        }
        let featuredBundleIDs = Set(favoriteBundles).union(recentBundles)

        return DebuggableAppListSnapshot(
            apps: filteredApps.filter { !featuredBundleIDs.contains($0.bundleID) },
            hasResults: !filteredApps.isEmpty,
            favoriteBundles: favoriteBundles,
            recentBundles: recentBundles,
            searchIsActive: !query.isEmpty
        )
    }

    private var launchSnapshot: LaunchAppListSnapshot {
        let query = InstalledAppListItem.normalized(searchText)
        let filteredApps = query.isEmpty
            ? viewModel.launchItems
            : viewModel.launchItems.filter { $0.matches(query) }

        return LaunchAppListSnapshot(
            apps: filteredApps,
            searchIsActive: !query.isEmpty
        )
    }

    @ToolbarContentBuilder
    private var leadingToolbarItem: some ToolbarContent {
        if let onImportPairingFile {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: onImportPairingFile) {
                    Image(systemName: "doc.badge.plus")
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var trailingToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            if showDoneButton {
                Button("Done") {
                    dismiss()
                }
                .fontWeight(.semibold)
            } else {
                Button {
                    viewModel.refreshAppLists()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(viewModel.isLoading)
            }
        }
    }

    @ViewBuilder
    private var listContent: some View {
        switch mode {
        case .jit:
            debuggableAppsList
        case .launch:
            launchAppsList
        }
    }

    private var debuggableAppsList: some View {
        let snapshot = debuggableSnapshot

        return List {
            errorSection

            if viewModel.isLoading && !snapshot.hasResults {
                LoadingAppListState(title: "Finding JIT-eligible apps…")
            } else if !snapshot.hasResults {
                EmptyAppListState(
                    systemImage: snapshot.searchIsActive ? "text.magnifyingglass" : "magnifyingglass",
                    title: snapshot.searchIsActive ? "No matching apps".localized : "No JIT Apps Found".localized,
                    message: snapshot.searchIsActive
                        ? "Try a different name or bundle identifier.".localized
                        : "StikDebug can only connect to apps with the \"get-task-allow\" entitlement.".localized
                )
            } else {
                debuggableAppSections(snapshot: snapshot)
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { viewModel.refreshAppLists() }
    }

    private var launchAppsList: some View {
        let snapshot = launchSnapshot

        return List {
            errorSection

            if viewModel.isLoading && snapshot.apps.isEmpty {
                LoadingAppListState(title: "Finding installed apps…")
            } else if snapshot.apps.isEmpty {
                EmptyAppListState(
                    systemImage: "magnifyingglass",
                    title: snapshot.searchIsActive ? "No matches".localized : "No Apps Found".localized,
                    message: snapshot.searchIsActive
                        ? "Try another name or bundle identifier.".localized
                        : "Once your device pairing file is imported and CoreDevice is connected, all apps will appear here.".localized
                )
            } else {
                launchAppSection(snapshot: snapshot)
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { viewModel.refreshAppLists() }
    }

    @ViewBuilder
    private var errorSection: some View {
        if let error = viewModel.lastError {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                    Button("Try Again") {
                        viewModel.refreshAppLists()
                    }
                    .font(.footnote.weight(.semibold))
                    .disabled(viewModel.isLoading)
                }
            }
        }
    }

    @ViewBuilder
    private func debuggableAppSections(snapshot: DebuggableAppListSnapshot) -> some View {
        if !snapshot.favoriteBundles.isEmpty {
            Section(String(format: "Favorites (%d/%d)".localized, snapshot.favoriteBundles.count, AppLibraryPreferences.maxFavorites)) {
                ForEach(snapshot.favoriteBundles, id: \.self) { bundleID in
                    debugAppRow(
                        bundleID: bundleID,
                        appName: viewModel.displayName(for: bundleID) ?? fallbackReadableName(from: bundleID)
                    )
                }
            }
        }

        if !snapshot.recentBundles.isEmpty {
            Section("Recents".localized) {
                ForEach(snapshot.recentBundles, id: \.self) { bundleID in
                    debugAppRow(
                        bundleID: bundleID,
                        appName: viewModel.displayName(for: bundleID) ?? fallbackReadableName(from: bundleID)
                    )
                }
            }
        }

        if !snapshot.apps.isEmpty {
            Section("JIT Eligible Apps".localized) {
                ForEach(snapshot.apps) { app in
                    debugAppRow(bundleID: app.bundleID, appName: app.name)
                }
            }
        }
    }

    private func launchAppSection(snapshot: LaunchAppListSnapshot) -> some View {
        Section("All Apps".localized) {
            ForEach(snapshot.apps) { app in
                let isPinned = pinnedSystemApps.contains(app.bundleID)

                LaunchAppRow(
                    bundleID: app.bundleID,
                    appName: app.name,
                    isLaunching: launchingBundles.contains(app.bundleID)
                ) {
                    startLaunching(bundleID: app.bundleID, appName: app.name)
                }
                .overlay(alignment: .topTrailing) {
                    if isPinned {
                        Image(systemName: "star.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.yellow)
                            .padding(6)
                            .accessibilityHidden(true)
                    }
                }
                .contextMenu {
                    Button((isPinned ? "Remove from Home" : "Add to Home").localized,
                           systemImage: isPinned ? "star.slash" : "star") {
                        toggleSystemPin(bundleID: app.bundleID, appName: app.name)
                    }
                    Button("Copy Bundle ID".localized, systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = app.bundleID
                        Haptics.light()
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button {
                        toggleSystemPin(bundleID: app.bundleID, appName: app.name)
                    } label: {
                        Label((isPinned ? "Unpin" : "Pin").localized, systemImage: "star")
                    }
                    .tint(.yellow)
                }
            }
        }
    }

    private func debugAppRow(bundleID: String, appName: String) -> some View {
        AppButton(
            bundleID: bundleID,
            appName: appName,
            isFavorite: favoriteBundleSet.contains(bundleID),
            favoriteCount: favoriteApps.count,
            recentApps: $recentApps,
            favoriteApps: $favoriteApps,
            onSelectApp: onSelectApp,
            isPerformingPrimaryAction: isJITOperationInFlight
        )
    }

    private func refreshIconPrefetch() {
        prefetchedBundleIDs.removeAll()
        prefetchPriorityIcons()
    }

    private func handleLoadingChange(_ isLoading: Bool) {
        if isLoading {
            prefetchedBundleIDs.removeAll()
        } else {
            prefetchPriorityIcons()
            syncLibraryPreferences()
        }
    }

    private func prefetchPriorityIcons(limit: Int = Self.iconPrefetchLimit) {
        guard loadAppIconsOnJIT else {
            return
        }

        var priorityBundleIDs: [String] = []
        var seenBundleIDs = Set<String>()

        func appendUnique<S: Sequence>(_ bundleIDs: S) where S.Element == String {
            guard priorityBundleIDs.count < limit else { return }

            for bundleID in bundleIDs {
                guard seenBundleIDs.insert(bundleID).inserted else { continue }
                priorityBundleIDs.append(bundleID)
                if priorityBundleIDs.count >= limit { break }
            }
        }

        switch mode {
        case .jit:
            appendUnique(favoriteApps)
            appendUnique(recentApps)
            appendUnique(viewModel.debuggableItems.map(\.bundleID))
        case .launch:
            appendUnique(pinnedSystemApps)
            appendUnique(viewModel.launchItems.map(\.bundleID))
        }

        let bundleIDsToPrefetch = priorityBundleIDs.filter { !prefetchedBundleIDs.contains($0) }
        guard !bundleIDsToPrefetch.isEmpty else {
            return
        }

        prefetchedBundleIDs.formUnion(bundleIDsToPrefetch)
        AppIconRepository.prefetch(bundleIDs: bundleIDsToPrefetch)
    }

    private func startLaunching(bundleID: String, appName: String) {
        guard !launchingBundles.contains(bundleID) else {
            return
        }

        launchingBundles.insert(bundleID)
        Haptics.selection()
        AccessibilityAnnouncer.announce(String(format: "Launching %@".localized, appName))

        viewModel.launchWithoutDebug(bundleID: bundleID) { success in
            launchingBundles.remove(bundleID)

            let message = success
                ? String(format: "Launch request sent for %@".localized, appName)
                : String(format: "Launch failed for %@".localized, appName)

            if success {
                Haptics.light()
            }

            AccessibilityAnnouncer.announce(message)
            toast = success ? .success(message) : .failure(message)
        }
    }

    private func toggleSystemPin(bundleID: String, appName: String) {
        Haptics.light()

        if let index = pinnedSystemApps.firstIndex(of: bundleID) {
            pinnedSystemApps.remove(at: index)
            pinnedSystemAppNames.removeValue(forKey: bundleID)
        } else {
            pinnedSystemApps.removeAll { $0 == bundleID }
            pinnedSystemApps.insert(bundleID, at: 0)
            pinnedSystemAppNames[bundleID] = appName

            if pinnedSystemApps.count > AppLibraryPreferences.maxSystemPins {
                let surplus = Array(pinnedSystemApps.suffix(from: AppLibraryPreferences.maxSystemPins))
                for bundleID in surplus {
                    pinnedSystemAppNames.removeValue(forKey: bundleID)
                }
                pinnedSystemApps = Array(pinnedSystemApps.prefix(AppLibraryPreferences.maxSystemPins))
            }
        }
    }

    private func handleFavoritesChange() {
        let cappedFavorites = Array(favoriteApps.prefix(AppLibraryPreferences.maxFavorites))
        guard favoriteApps == cappedFavorites else {
            favoriteApps = cappedFavorites
            return
        }

        prefetchPriorityIcons()
        syncLibraryPreferences()
    }

    private func syncLibraryPreferences() {
        AppLibraryPreferences.sync(
            recentApps: recentApps,
            favoriteApps: favoriteApps,
            pinnedSystemApps: pinnedSystemApps,
            pinnedSystemAppNames: pinnedSystemAppNames,
            displayName: { bundleID in
                viewModel.displayName(for: bundleID) ?? fallbackReadableName(from: bundleID)
            }
        )
    }

    private func fallbackReadableName(from bundleID: String) -> String {
        let components = bundleID.split(separator: ".")
        if let lastComponent = components.last {
            let cleaned = lastComponent.replacingOccurrences(of: "_", with: " ")
            let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed.capitalized
            }
        }

        return bundleID
    }
}

private extension InstalledAppsListMode {
    var navigationTitle: String {
        switch self {
        case .jit:
            return "JIT"
        case .launch:
            return "Launch Apps".localized
        }
    }

    var searchPrompt: String {
        switch self {
        case .jit:
            return "Search apps or bundle ID".localized
        case .launch:
            return "Search".localized
        }
    }
}

private struct DebuggableAppListSnapshot {
    let apps: [InstalledAppListItem]
    let hasResults: Bool
    let favoriteBundles: [String]
    let recentBundles: [String]
    let searchIsActive: Bool
}

private struct LaunchAppListSnapshot {
    let apps: [InstalledAppListItem]
    let searchIsActive: Bool
}

private struct EmptyAppListState: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        Section {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)

                Text(title)
                    .font(.headline)

                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .listRowBackground(Color.clear)
        }
    }
}

private struct LoadingAppListState: View {
    let title: String

    var body: some View {
        Section {
            HStack(spacing: 12) {
                ProgressView()
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 18)
            .listRowBackground(Color.clear)
        }
    }
}

struct InstalledAppsListView_Previews: PreviewProvider {
    static var previews: some View {
        InstalledAppsListView(mode: .jit) { _, _ in }
            .environment(\.colorScheme, .dark)
    }
}
