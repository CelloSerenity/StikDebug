//
//  DeviceConnectionContext.swift
//  StikDebug
//
//  Created by Stephen.
//

import Foundation
import Network

struct DeviceConnectionInspection {
    let productType: String
    let productVersion: String
    let hasTXM: Bool
}

enum DeviceConnectionContext {
    static let defaultTargetIPAddress = "10.7.0.1"
    static let tunnelPort: UInt16 = 49152

    static var targetIPAddress: String {
        DeviceProfileStore.selectedProfile().ipAddress
    }

    static func isReachable(_ profile: DeviceProfile, timeout: TimeInterval = 2) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    try requireReachable(profile, timeout: timeout)
                    continuation.resume(returning: true)
                } catch {
                    continuation.resume(returning: false)
                }
            }
        }
    }

    static func requireReachable(_ profile: DeviceProfile, timeout: TimeInterval = 3) throws {
        guard let port = NWEndpoint.Port(rawValue: tunnelPort) else {
            throw connectionError(for: profile)
        }

        let connection = NWConnection(
            host: NWEndpoint.Host(profile.ipAddress),
            port: port,
            using: .tcp
        )
        let queue = DispatchQueue(label: "com.stikdebug.tunnel-reachability")
        let semaphore = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var completed = false
        var connectionFailure: Error?

        connection.stateUpdateHandler = { state in
            let result: Error?
            switch state {
            case .ready:
                result = nil
            case .failed:
                result = connectionError(for: profile)
            default:
                return
            }

            lock.lock()
            if !completed {
                completed = true
                connectionFailure = result
                semaphore.signal()
            }
            lock.unlock()
        }

        connection.start(queue: queue)
        let waitResult = semaphore.wait(timeout: .now() + timeout)

        lock.lock()
        if waitResult == .timedOut, !completed {
            completed = true
            connectionFailure = connectionError(for: profile)
        }
        let failure = connectionFailure
        lock.unlock()

        connection.stateUpdateHandler = nil
        connection.cancel()

        if let failure {
            throw failure
        }
    }

    private static func connectionError(for profile: DeviceProfile) -> NSError {
        NSError(
            domain: "StikDebug.Tunnel",
            code: -19,
            userInfo: [
                NSLocalizedDescriptionKey: "Could not reach \(profile.name) at \(profile.ipAddress):\(tunnelPort) before the connection timeout."
            ]
        )
    }
}
