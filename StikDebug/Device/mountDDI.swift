//
//  mountDDI.swift
//  StikDebug
//
//  Created by Stossy11 on 29/03/2025.
//

import Foundation

typealias RpPairingFileHandle = OpaquePointer
typealias AdapterHandle = OpaquePointer
typealias RsdHandshakeHandle = OpaquePointer
typealias ImageMounterHandle = OpaquePointer
typealias LockdowndClientHandle = OpaquePointer

enum MountCheckResult {
    case mounted
    case notMounted
    case unreachable
}

func isMounted() -> Bool {
    return checkMountStatus() == .mounted
}

func checkMountStatus() -> MountCheckResult {
    do {
        return try JITEnableContext.shared.isDeveloperDiskImageMounted() ? .mounted : .notMounted
    } catch {
        return .unreachable
    }
}

func mountDeveloperDiskImage(from directoryPath: String) -> String? {
    do {
        try JITEnableContext.shared.installCryptexDDI(from: directoryPath)
    } catch {
        return error.localizedDescription
    }
    return nil
}
