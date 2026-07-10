//
//  AccessibilityAnnouncer.swift
//  StikDebug
//

import UIKit

enum AccessibilityAnnouncer {
    static func announce(_ message: String) {
        UIAccessibility.post(notification: .announcement, argument: message)
    }
}
