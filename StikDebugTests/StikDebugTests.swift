//
//  StikDebugTests.swift
//  StikDebugTests
//
//  Created by Stephen on 3/26/25.
//

import Foundation
import Testing
@testable import StikDebug

struct StikDebugTests {

    @Test func txmDetectionUsesProductTypeThresholds() async throws {
        #expect(!ProcessInfo.hasTXMSupport(osMajorVersion: 26, hardwareIdentifier: "iPhone14,1"))
        #expect(ProcessInfo.hasTXMSupport(osMajorVersion: 26, hardwareIdentifier: "iPhone14,2"))
        #expect(!ProcessInfo.hasTXMSupport(osMajorVersion: 26, hardwareIdentifier: "iPad14,4"))
        #expect(ProcessInfo.hasTXMSupport(osMajorVersion: 26, hardwareIdentifier: "iPad14,5"))
        #expect(!ProcessInfo.hasTXMSupport(osMajorVersion: 25, hardwareIdentifier: "AppleTV15,1"))
        #expect(!ProcessInfo.hasTXMSupport(osMajorVersion: 26, hardwareIdentifier: "AppleTV14,0"))
        #expect(ProcessInfo.hasTXMSupport(osMajorVersion: 26, hardwareIdentifier: "AppleTV14,1"))
        #expect(ProcessInfo.hasTXMSupport(osMajorVersion: 26, hardwareIdentifier: "AppleTV14,2"))
        #expect(ProcessInfo.hasTXMSupport(osMajorVersion: 26, hardwareIdentifier: "AppleTV15,1"))
        #expect(!ProcessInfo.hasTXMSupport(osMajorVersion: 27, hardwareIdentifier: "iPad8,11"))
        #expect(ProcessInfo.hasTXMSupport(osMajorVersion: 27, hardwareIdentifier: "iPhone13,1"))
    }

    @Test func deviceVersionParsesSupportedIdentifiers() async throws {
        #expect(ProcessInfo.processInfo.deviceVersion(from: "iPhone14,2") == 14.2)
        #expect(ProcessInfo.processInfo.deviceVersion(from: "iPad14,5") == 14.5)
        #expect(ProcessInfo.processInfo.deviceVersion(from: "AppleTV14,1") == 14.1)
        #expect(ProcessInfo.processInfo.deviceVersion(from: "Mac14,2") == nil)
    }

    @Test func deviceProfilesAlwaysIncludeLocalProfile() {
        let suiteName = "DeviceProfiles-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let profiles = DeviceProfileStore.profiles(defaults: defaults)

        #expect(profiles == [DeviceProfileStore.localProfile])
        #expect(profiles[0].ipAddress == "10.7.0.1")
        #expect(DeviceProfileStore.selectedProfile(defaults: defaults).isLocal)
    }

    @Test func deviceProfilesPersistAndSelectAnyNumberOfDevices() {
        let suiteName = "DeviceProfiles-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = DeviceProfileStore.addProfile(
            name: "Office",
            ipAddress: "192.168.1.20",
            runScripts: true,
            txmDetected: true,
            defaults: defaults
        )
        let second = DeviceProfileStore.addProfile(
            name: "Lab",
            ipAddress: "172.16.0.4",
            runScripts: false,
            txmDetected: false,
            defaults: defaults
        )

        #expect(DeviceProfileStore.profiles(defaults: defaults).count == 3)
        #expect(DeviceProfileStore.selectedProfile(defaults: defaults) == second)
        #expect(first.txmDetected == true)
        #expect(first.runScripts)
        #expect(second.txmDetected == false)
        #expect(!second.runScripts)

        DeviceProfileStore.select(first.id, defaults: defaults)
        #expect(DeviceProfileStore.selectedProfile(defaults: defaults) == first)
    }

    @Test func deletingSelectedDeviceReturnsToLocalProfile() {
        let suiteName = "DeviceProfiles-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let profile = DeviceProfileStore.addProfile(name: "Remote", ipAddress: "10.0.0.2", defaults: defaults)
        DeviceProfileStore.delete(profile.id, defaults: defaults)

        #expect(DeviceProfileStore.profiles(defaults: defaults) == [DeviceProfileStore.localProfile])
        #expect(DeviceProfileStore.selectedProfile(defaults: defaults).isLocal)
    }

    @Test func deviceProfileIPv4Validation() {
        #expect(DeviceProfileStore.isValidIPv4Address("10.7.0.1"))
        #expect(DeviceProfileStore.isValidIPv4Address("192.168.1.255"))
        #expect(!DeviceProfileStore.isValidIPv4Address("192.168.1"))
        #expect(!DeviceProfileStore.isValidIPv4Address("192.168.1.256"))
        #expect(!DeviceProfileStore.isValidIPv4Address("device.local"))
    }

}
