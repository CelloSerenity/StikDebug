import Foundation

struct DeviceProfile: Codable, Hashable, Identifiable {
    let id: String
    var name: String
    var ipAddress: String
    var runScripts: Bool
    var txmDetected: Bool?

    init(
        id: String,
        name: String,
        ipAddress: String,
        runScripts: Bool = DeviceProfileStore.defaultRunScripts,
        txmDetected: Bool? = nil
    ) {
        self.id = id
        self.name = name
        self.ipAddress = ipAddress
        self.runScripts = runScripts
        self.txmDetected = txmDetected
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case ipAddress
        case runScripts
        case txmDetected
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        ipAddress = try container.decode(String.self, forKey: .ipAddress)
        runScripts = try container.decodeIfPresent(Bool.self, forKey: .runScripts) ?? DeviceProfileStore.defaultRunScripts
        txmDetected = try container.decodeIfPresent(Bool.self, forKey: .txmDetected)
    }

    var isLocal: Bool {
        id == DeviceProfileStore.localProfileID
    }
}

enum DeviceProfileStore {
    static let localProfileID = "local"
    static var defaultRunScripts: Bool {
        ProcessInfo.processInfo.hasDetectedTXM || UserDefaults.standard.bool(forKey: UserDefaults.Keys.txmOverride)
    }

    static let localProfile = DeviceProfile(
        id: localProfileID,
        name: "Local",
        ipAddress: DeviceConnectionContext.defaultTargetIPAddress,
        runScripts: defaultRunScripts,
        txmDetected: ProcessInfo.processInfo.hasDetectedTXM
    )

    static func profiles(defaults: UserDefaults = .standard) -> [DeviceProfile] {
        guard let data = defaults.data(forKey: UserDefaults.Keys.deviceProfiles),
              let storedProfiles = try? JSONDecoder().decode([DeviceProfile].self, from: data) else {
            return [localProfile]
        }

        let storedLocal = storedProfiles.first(where: { $0.id == localProfileID })
        let local = DeviceProfile(
            id: localProfileID,
            name: "Local",
            ipAddress: DeviceConnectionContext.defaultTargetIPAddress,
            runScripts: storedLocal?.runScripts ?? defaultRunScripts,
            txmDetected: ProcessInfo.processInfo.hasDetectedTXM
        )
        var seenIDs = Set<String>()
        let remoteProfiles = storedProfiles.compactMap { profile -> DeviceProfile? in
            let name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let ipAddress = profile.ipAddress.trimmingCharacters(in: .whitespacesAndNewlines)
            guard profile.id != localProfileID,
                  UUID(uuidString: profile.id) != nil,
                  !name.isEmpty,
                  !ipAddress.isEmpty,
                  seenIDs.insert(profile.id).inserted else {
                return nil
            }
            return DeviceProfile(
                id: profile.id,
                name: name,
                ipAddress: ipAddress,
                runScripts: profile.runScripts,
                txmDetected: profile.txmDetected
            )
        }
        return [local] + remoteProfiles
    }

    static func selectedProfileID(defaults: UserDefaults = .standard) -> String {
        let selectedID = defaults.string(forKey: UserDefaults.Keys.selectedDeviceProfileID) ?? localProfileID
        return profiles(defaults: defaults).contains(where: { $0.id == selectedID }) ? selectedID : localProfileID
    }

    static func selectedProfile(defaults: UserDefaults = .standard) -> DeviceProfile {
        let selectedID = selectedProfileID(defaults: defaults)
        return profiles(defaults: defaults).first(where: { $0.id == selectedID }) ?? localProfile
    }

    @discardableResult
    static func addProfile(
        name: String,
        ipAddress: String,
        runScripts: Bool = defaultRunScripts,
        txmDetected: Bool? = nil,
        defaults: UserDefaults = .standard
    ) -> DeviceProfile {
        let profile = DeviceProfile(
            id: UUID().uuidString,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            ipAddress: ipAddress.trimmingCharacters(in: .whitespacesAndNewlines),
            runScripts: runScripts,
            txmDetected: txmDetected
        )
        var currentProfiles = profiles(defaults: defaults)
        currentProfiles.append(profile)
        save(currentProfiles, defaults: defaults)
        select(profile.id, defaults: defaults)
        return profile
    }

    static func update(_ profile: DeviceProfile, defaults: UserDefaults = .standard) {
        var currentProfiles = profiles(defaults: defaults)
        guard let index = currentProfiles.firstIndex(where: { $0.id == profile.id }) else { return }
        currentProfiles[index] = profile.isLocal
            ? DeviceProfile(
                id: localProfileID,
                name: "Local",
                ipAddress: DeviceConnectionContext.defaultTargetIPAddress,
                runScripts: profile.runScripts,
                txmDetected: ProcessInfo.processInfo.hasDetectedTXM
            )
            : profile
        save(currentProfiles, defaults: defaults)
    }

    static func delete(_ profileID: String, defaults: UserDefaults = .standard) {
        guard profileID != localProfileID else { return }
        let wasSelected = selectedProfileID(defaults: defaults) == profileID
        save(profiles(defaults: defaults).filter { $0.id != profileID }, defaults: defaults)
        if wasSelected {
            select(localProfileID, defaults: defaults)
        }
    }

    static func select(_ profileID: String, defaults: UserDefaults = .standard) {
        let validID = profiles(defaults: defaults).contains(where: { $0.id == profileID }) ? profileID : localProfileID
        defaults.set(validID, forKey: UserDefaults.Keys.selectedDeviceProfileID)
    }

    static func activate(_ profileID: String) {
        select(profileID)
        let selectedID = selectedProfileID()
        LocationSimulationCommandQueue.shared.async {
            reset_location_simulation()
        }
        MountingProgress.shared.resetMountStatus()
        TunnelManager.shared.selectedDeviceDidChange()
        BackgroundAudioManager.shared.selectedDeviceDidChange()
        BackgroundLocationManager.shared.selectedDeviceDidChange()
        NotificationCenter.default.post(name: .pairingFileImported, object: nil)
        if PairingFileStore.hasPairingFile(for: selectedID) {
            startTunnelInBackground()
        }
    }

    static func activateLocalForExternalRequest() {
        guard selectedProfileID() != localProfileID else { return }
        activate(localProfileID)
    }

    static func isValidIPv4Address(_ address: String) -> Bool {
        let components = address.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 4 else { return false }
        return components.allSatisfy { component in
            guard !component.isEmpty, component.allSatisfy(\.isNumber), let value = Int(component) else { return false }
            return (0...255).contains(value)
        }
    }

    private static func save(_ profiles: [DeviceProfile], defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        defaults.set(data, forKey: UserDefaults.Keys.deviceProfiles)
    }
}
