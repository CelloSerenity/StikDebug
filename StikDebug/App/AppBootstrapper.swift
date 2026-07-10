//
//  AppBootstrapper.swift
//  StikDebug
//

import Foundation
import ObjectiveC.runtime
import UIKit

enum AppBootstrapper {
    static func configure() {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        UserDefaults.standard.register(defaults: [
            UserDefaults.Keys.enableAdvancedOptions: os.majorVersion >= 19,
            UserDefaults.Keys.txmOverride: false,
            UserDefaults.Keys.confirmExternalJITRequests: true,
            // ImmortalizerJailed preference key (floating hourglass button).
            "immortalized": false
        ])

        // UIKit document picker asCopy: workaround.
        let fixed = NSSelectorFromString("fix_initForOpeningContentTypes:asCopy:")
        let original = #selector(UIDocumentPickerViewController.init(forOpeningContentTypes:asCopy:))
        if let fixedMethod = class_getInstanceMethod(UIDocumentPickerViewController.self, fixed),
           let originalMethod = class_getInstanceMethod(UIDocumentPickerViewController.self, original) {
            method_exchangeImplementations(originalMethod, fixedMethod)
        }
    }
}
