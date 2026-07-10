//
//  InstalledAppsViewModel.swift
//  StikDebug
//

import Combine
import Foundation

final class InstalledAppsViewModel: ObservableObject {
    @Published private(set) var debuggableApps: [String: String] = [:]
    @Published private(set) var nonDebuggableApps: [String: String] = [:]
    @Published private(set) var systemApps: [String: String] = [:]
    @Published private(set) var debuggableItems: [InstalledAppListItem] = []
    @Published private(set) var launchItems: [InstalledAppListItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?

    private let workQueue = DispatchQueue(label: "com.stik.installedApps", qos: .userInitiated)
    private let cache = UserDefaults(suiteName: ScriptStore.favoriteAppNamesSuiteName) ?? .standard
    private let cacheKeyDebuggable = "cachedDebuggableApps"
    private let cacheKeyNonDebuggable = "cachedNonDebuggableApps"
    private let cacheKeySystem = "cachedSystemApps"
    private var refreshRequestedWhileLoading = false

    init() {
        loadCachedApps()
        refreshAppLists()
    }

    func refreshAppLists() {
        guard !isLoading else {
            refreshRequestedWhileLoading = true
            return
        }

        isLoading = true
        lastError = nil

        workQueue.async { [weak self] in
            guard let self else { return }

            let result: Result<InstalledAppInventory, Error>
            do {
                let inventory = try JITEnableContext.shared.getInstalledAppInventory()
                self.cacheApps(
                    debuggable: inventory.debuggable,
                    nonDebuggable: inventory.nonDebuggable,
                    system: inventory.system
                )
                result = .success(inventory)
            } catch {
                result = .failure(error)
            }

            DispatchQueue.main.async {
                self.finishRefresh(result)
            }
        }
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
        launchItems = InstalledAppListItem.sorted(from: Self.launchApps(nonDebuggable: nonDebuggable, system: system))
    }

    private func finishRefresh(_ result: Result<InstalledAppInventory, Error>) {
        switch result {
        case .success(let inventory):
            apply(
                debuggable: inventory.debuggable,
                nonDebuggable: inventory.nonDebuggable,
                system: inventory.system
            )
        case .failure(let error):
            lastError = error.localizedDescription
        }

        isLoading = false

        if refreshRequestedWhileLoading {
            refreshRequestedWhileLoading = false
            refreshAppLists()
        }
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

    private static func launchApps(nonDebuggable: [String: String], system: [String: String]) -> [String: String] {
        var combined = nonDebuggable
        for (bundleID, name) in system {
            combined[bundleID] = name
        }
        return combined
    }
}
