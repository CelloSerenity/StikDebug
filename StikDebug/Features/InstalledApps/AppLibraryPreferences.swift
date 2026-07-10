//
//  AppLibraryPreferences.swift
//  StikDebug
//

import Foundation
import WidgetKit

enum AppLibraryPreferences {
    static let maxFavorites = 4
    static let maxRecents = 3
    static let maxSystemPins = 8

    static func sync(
        recentApps: [String],
        favoriteApps: [String],
        pinnedSystemApps: [String],
        pinnedSystemAppNames: [String: String],
        displayName: (String) -> String
    ) {
        let defaults = UserDefaults(suiteName: ScriptStore.favoriteAppNamesSuiteName) ?? .standard
        let favoriteNames = Dictionary(uniqueKeysWithValues: favoriteApps.map { bundleID in
            (bundleID, displayName(bundleID))
        })

        var didChange = false
        didChange = set(recentApps, forKey: "recentApps", in: defaults) || didChange
        didChange = set(favoriteApps, forKey: "favoriteApps", in: defaults) || didChange
        didChange = set(pinnedSystemApps, forKey: "pinnedSystemApps", in: defaults) || didChange
        didChange = set(pinnedSystemAppNames, forKey: "pinnedSystemAppNames", in: defaults) || didChange
        didChange = set(favoriteNames, forKey: ScriptStore.favoriteAppNamesKey, in: defaults) || didChange

        if didChange {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    @discardableResult
    private static func set(_ value: Any, forKey key: String, in defaults: UserDefaults) -> Bool {
        let existing = defaults.object(forKey: key) as? NSObject
        let next = value as? NSObject
        guard existing != next else {
            return false
        }

        defaults.set(value, forKey: key)
        return true
    }
}
