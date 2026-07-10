//
//  ImmortalizerBridge.swift
//  StikDebug
//
//  Thin bridge to ImmortalizerJailed (https://github.com/sergealagon/ImmortalizerJailed).
//

import Foundation

enum ImmortalizerBridge {
    /// Matches the Darwin notification posted by ImmortalizerJailed when prefs change.
    private static let preferenceNotification = "com.sergy.immortalizerjailed.updateprefs" as CFString

    static func notifyPreferenceChanged() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(preferenceNotification),
            nil,
            nil,
            true
        )
    }
}
