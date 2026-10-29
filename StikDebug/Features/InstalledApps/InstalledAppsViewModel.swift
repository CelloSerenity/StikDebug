//
//  InstalledAppsViewModel.swift
//  StikDebug
//

import Combine
import Foundation

final class InstalledAppsViewModel: ObservableObject {
    private static let hasReadAppsThisSession = CurrentValueSubject<Bool, Never>(false)

    @Published private(set) var debuggableApps: [String: String] = [:]
    @Published private(set) var nonDebuggableApps: [String: String] = [:]
    @Published private(set) var systemApps: [String: String] = [:]
    @Published private(set) var debuggableItems: [InstalledAppListItem] = []
    @Published private(set) var launchItems: [InstalledAppListItem] = []
    @Published private(set) var hasReadApps = false
    @Published private(set) var isLoading = false
    @Published private(set) var hasConfirmedAppList = false
    @Published private(set) var isConnected = false
    @Published private(set) var lastError: String?

    private let workQueue = DispatchQueue(label: "com.stik.installedApps", qos: .userInitiated)
    private let cache = UserDefaults(suiteName: ScriptStore.favoriteAppNamesSuiteName) ?? .standard
    private let cacheKeyDebuggable = "cachedDebuggableApps"
    private let cacheKeyNonDebuggable = "cachedNonDebuggableApps"
    private let cacheKeySystem = "cachedSystemApps"
    private var cancellables: Set<AnyCancellable> = []
    private var refreshInProgress = false
    private var refreshPending = false
    private var connectionGeneration = 0

    init() {
        loadCachedApps()
        Self.hasReadAppsThisSession
            .assign(to: &$hasReadApps)
        TunnelManager.shared.$lastError
            .sink { error in
                if error != nil {
                    Self.hasReadAppsThisSession.send(false)
                }
            }
            .store(in: &cancellables)
        TunnelManager.shared.$isConnected
            .removeDuplicates()
            .sink { [weak self] connected in
                guard let self else { return }
                self.connectionGeneration += 1
                self.isConnected = connected
                self.hasConfirmedAppList = false
                if connected {
                    self.refreshAppLists()
                }
            }
            .store(in: &cancellables)
    }

    func refreshAppLists() {
        guard !refreshInProgress else {
            refreshPending = true
            return
        }

        refreshInProgress = true
        let generation = connectionGeneration
        hasConfirmedAppList = false
        isLoading = true
        lastError = nil

        workQueue.async { [weak self] in
            guard let self else { return }

            do {
                let debuggable = try JITEnableContext.shared.getAppList()
                let allApps = try JITEnableContext.shared.getAllApps()
                let hiddenSystem = (try? JITEnableContext.shared.getHiddenSystemApps()) ?? [:]
                let classifiedApps = Self.classifyApps(
                    allApps: allApps,
                    debuggable: debuggable,
                    hiddenSystem: hiddenSystem
                )
                self.cacheApps(
                    debuggable: debuggable,
                    nonDebuggable: classifiedApps.nonDebuggable,
                    system: classifiedApps.system
                )

                DispatchQueue.main.async {
                    guard self.connectionGeneration == generation else {
                        self.finishRefresh()
                        return
                    }
                    self.hasConfirmedAppList = self.isConnected
                    if self.isConnected {
                        Self.hasReadAppsThisSession.send(true)
                    }
                    self.apply(
                        debuggable: debuggable,
                        nonDebuggable: classifiedApps.nonDebuggable,
                        system: classifiedApps.system
                    )
                    self.finishRefresh()
                }
            } catch {
                DispatchQueue.main.async {
                    guard self.connectionGeneration == generation else {
                        self.finishRefresh()
                        return
                    }
                    self.lastError = "Code \((error as NSError).code): \(error.localizedDescription)"
                    Self.hasReadAppsThisSession.send(false)
                    self.finishRefresh()
                }
            }
        }
    }

    private func finishRefresh() {
        refreshInProgress = false
        isLoading = false

        guard refreshPending else { return }
        refreshPending = false
        refreshAppLists()
    }

    func displayName(for bundleID: String) -> String? {
        debuggableApps[bundleID] ?? systemApps[bundleID] ?? nonDebuggableApps[bundleID]
    }

    func launchWithoutDebug(bundleID: String, completion: @escaping (Bool) -> Void) {
        workQueue.async {
            let success = JITEnableContext.shared.launchAppWithoutDebug(bundleID, logger: nil)
            DispatchQueue.main.async {
                completion(success)
            }
        }
    }

    private func loadCachedApps() {
        let cachedDebuggable = decode(cacheKeyDebuggable)
        let cachedNonDebuggable = decode(cacheKeyNonDebuggable)
        let cachedSystem = decode(cacheKeySystem)

        if !cachedDebuggable.isEmpty || !cachedNonDebuggable.isEmpty || !cachedSystem.isEmpty {
            apply(debuggable: cachedDebuggable, nonDebuggable: cachedNonDebuggable, system: cachedSystem)
        }
    }

    private func apply(debuggable: [String: String], nonDebuggable: [String: String], system: [String: String]) {
        debuggableApps = debuggable
        nonDebuggableApps = nonDebuggable
        systemApps = system
        debuggableItems = InstalledAppListItem.sorted(from: debuggable)
        launchItems = InstalledAppListItem.sorted(from: Self.launchApps(debuggable: debuggable, nonDebuggable: nonDebuggable, system: system))
    }

    private func cacheApps(debuggable: [String: String], nonDebuggable: [String: String], system: [String: String]) {
        cache.set(encode(debuggable), forKey: cacheKeyDebuggable)
        cache.set(encode(nonDebuggable), forKey: cacheKeyNonDebuggable)
        cache.set(encode(system), forKey: cacheKeySystem)
    }

    private func decode(_ key: String) -> [String: String] {
        guard let data = cache.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private func encode(_ value: [String: String]) -> Data? {
        try? JSONEncoder().encode(value)
    }

    private static func classifyApps(
        allApps: [String: String],
        debuggable: [String: String],
        hiddenSystem: [String: String]
    ) -> (nonDebuggable: [String: String], system: [String: String]) {
        var nonDebuggable: [String: String] = [:]
        var system: [String: String] = [:]

        for (bundleID, name) in allApps where debuggable[bundleID] == nil {
            if let hiddenName = hiddenSystem[bundleID] {
                system[bundleID] = hiddenName
            } else {
                nonDebuggable[bundleID] = name
            }
        }

        for (bundleID, name) in hiddenSystem where system[bundleID] == nil && debuggable[bundleID] == nil {
            system[bundleID] = name
        }

        return (nonDebuggable, system)
    }

    private static func launchApps(debuggable: [String: String], nonDebuggable: [String: String], system: [String: String]) -> [String: String] {
        var combined = debuggable.merging(nonDebuggable) { _, name in name }
        for (bundleID, name) in system {
            combined[bundleID] = name
        }
        return combined
    }
}
