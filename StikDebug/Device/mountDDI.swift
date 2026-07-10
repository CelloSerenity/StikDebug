//
//  mountDDI.swift
//  StikDebug
//
//  Created by Stossy11 on 29/03/2025.
//

import Foundation

func progressCallback(progress: size_t, total: size_t, context: UnsafeMutableRawPointer?) {
    MountingProgress.shared.updateProgress(progress: progress, total: total, context: context)
}

func isMounted() -> Bool {
    do {
        return try JITEnableContext.shared.getMountedDeviceCount() > 0
    } catch {
        return false
    }
}

func mountPersonalDDI(imagePath: String, trustcachePath: String, manifestPath: String) -> String? {
    do {
        try JITEnableContext.shared.mountPersonalDDI(
            withImagePath: imagePath,
            trustcachePath: trustcachePath,
            manifestPath: manifestPath
        )
        return nil
    } catch {
        LogManager.shared.addErrorLog("Failed to mount DDI: \(error.localizedDescription)")
        return error.localizedDescription
    }
}
