//
//  IconsFetcher.swift
//  Dont change the name of the actual file (it will break stuff)
//  StikDebug
//
//  Created by neoarz on 3/28/25.
//

import Foundation

enum AppStoreIconFetcher {
    private static let queue = DispatchQueue(label: "com.stik.stikdebug.iconFetchQueue", qos: .utility)

    static func getIconData(for bundleID: String, completion: @escaping (Data?) -> Void) {
        queue.async {
            completion(try? JITEnableContext.shared.getAppIconData(withBundleId: bundleID))
        }
    }
}
