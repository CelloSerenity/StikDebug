//
//  ProcessInfo+TXM.swift
//  StikDebug
//

import Foundation

public extension ProcessInfo {
    var hasTXM: Bool {
        DeviceProfileStore.selectedProfile().runScripts
    }

    var hasDetectedTXM: Bool {
        ProcessInfo.hasTXMSupport(
            osMajorVersion: operatingSystemVersion.majorVersion,
            hardwareIdentifier: hardwareIdentifier()
        )
    }

    var isTXMOverridden: Bool {
        hasTXM && !hasDetectedTXM
    }

    internal static func hasTXMSupport(
        osMajorVersion: Int,
        hardwareIdentifier: String
    ) -> Bool {
        guard osMajorVersion >= 26 else { return false }

        let firstTXM = 14.2
        let iPadTXM = 14.5
        let appleTVTXM = 14.1

        guard let ver = ProcessInfo.processInfo.deviceVersion(from: hardwareIdentifier) else {
            return false
        }

        if hardwareIdentifier.hasPrefix("AppleTV") {
            return ver >= appleTVTXM
        }

        if osMajorVersion >= 27 {
            return hardwareIdentifier != "iPad8,11" && hardwareIdentifier != "iPad8,12"
        }

        if hardwareIdentifier.hasPrefix("iPad") {
            return ver >= iPadTXM
        }

        return ver >= firstTXM
    }

    func deviceVersion(from identifier: String) -> Double? {
        let iPhonePattern = #"iPhone(\d+),(\d+)"#
        let iPadPattern = #"iPad(\d+),(\d+)"#
        let appleTVPattern = #"AppleTV(\d+),(\d+)"#

        let extractVersion: (_ pattern: String) -> Double? = { pattern in
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(
                    in: identifier,
                    range: NSRange(identifier.startIndex..., in: identifier)
                  ),
                  let majorRange = Range(match.range(at: 1), in: identifier),
                  let minorRange = Range(match.range(at: 2), in: identifier),
                  let major = Double(identifier[majorRange]),
                  let minor = Double(identifier[minorRange])
            else {
                return nil
            }

            let divisor = pow(10.0, Double(String(Int(minor)).count))
            return major + (minor / divisor)
        }

        return extractVersion(iPhonePattern) ?? extractVersion(iPadPattern) ?? extractVersion(appleTVPattern)
    }

    private func hardwareIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)

        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
    }
}
