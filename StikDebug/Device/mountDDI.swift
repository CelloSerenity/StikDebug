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
        return try JITEnableContext.shared.isCryptexDDIInstalled() ? .mounted : .notMounted
    } catch {
        return .unreachable
    }
}

func installCryptexDDI(from directoryPath: String) -> String? {
    do {
        try JITEnableContext.shared.installCryptexDDI(from: directoryPath)
    } catch {
        LogManager.shared.addErrorLog("Failed to install DDI cryptex: \(error.localizedDescription)")
        return error.localizedDescription
    }
    return nil
}
