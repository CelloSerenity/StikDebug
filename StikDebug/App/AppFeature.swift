//
//  AppFeature.swift
//  StikDebug
//

import SwiftUI

enum AppFeature: String, CaseIterable, Identifiable {
    case tools
    case settings
    case jit
    case scripts
    case console
    case deviceInfo = "deviceinfo"
    case profiles
    case processes
    case location
    case launchApps = "launchapps"

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .tools:
            return "Home"
        case .settings:
            return "Settings"
        case .jit:
            return "JIT"
        case .scripts:
            return "Scripts"
        case .console:
            return "Console"
        case .deviceInfo:
            return "Device Info"
        case .profiles:
            return "App Expiry"
        case .processes:
            return "Processes"
        case .location:
            return "Location"
        case .launchApps:
            return "Launch Apps"
        }
    }

    var detail: String {
        switch self {
        case .tools:
            return "Access device tools"
        case .settings:
            return "Configure StikDebug"
        case .jit:
            return "Enable JIT for eligible apps"
        case .scripts:
            return "Manage and run JS scripts"
        case .console:
            return "Live device logs"
        case .deviceInfo:
            return "View detailed device metadata"
        case .profiles:
            return "Check app expiration dates"
        case .processes:
            return "Inspect running apps"
        case .location:
            return "Simulate GPS location"
        case .launchApps:
            return "Launch installed apps without JIT"
        }
    }

    var toolTitle: String {
        switch self {
        case .location:
            return "Location Simulation"
        default:
            return title
        }
    }

    var systemImage: String {
        switch self {
        case .tools:
            return "house.fill"
        case .settings:
            return "gearshape.fill"
        case .jit:
            return "bolt.fill"
        case .scripts:
            return "scroll"
        case .console:
            return "terminal"
        case .deviceInfo:
            return "iphone.and.arrow.forward"
        case .profiles:
            return "calendar.badge.clock"
        case .processes:
            return "rectangle.stack.person.crop"
        case .location:
            return "location"
        case .launchApps:
            return "arrow.up.forward.app"
        }
    }

    /// Section grouping on the tools hub (excludes tab-only cases).
    var toolSection: ToolHubSection? {
        switch self {
        case .jit:
            return .featured
        case .launchApps, .scripts:
            return .apps
        case .console, .processes:
            return .diagnostics
        case .deviceInfo, .profiles, .location:
            return .device
        case .tools, .settings:
            return nil
        }
    }

    /// Distinct badge color per tool so sections scan quickly.
    var hubPalette: HubPalette {
        switch self {
        case .jit: return .orange
        case .launchApps: return .blue
        case .scripts: return .purple
        case .console: return .green
        case .deviceInfo: return .indigo
        case .profiles: return .pink
        case .processes: return .teal
        case .location: return .cyan
        case .tools, .settings: return .gray
        }
    }

    @ViewBuilder
    var destination: some View {
        switch self {
        case .tools:
            ToolsView()
        case .settings:
            SettingsView()
        case .jit:
            HomeView()
        case .scripts:
            ScriptListView()
        case .console:
            ConsoleLogsView()
        case .deviceInfo:
            DeviceInfoView()
        case .profiles:
            ProfileView()
        case .processes:
            ProcessInspectorView()
        case .location:
            LocationSimulationView()
        case .launchApps:
            LaunchAppsView()
        }
    }
}

enum ToolHubSection: Int, CaseIterable, Identifiable {
    case featured
    case apps
    case diagnostics
    case device

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .featured:
            return "Debugging"
        case .apps:
            return "Apps & Scripts"
        case .diagnostics:
            return "Diagnostics"
        case .device:
            return "Device"
        }
    }

    var tools: [AppFeature] {
        AppFeature.toolList.filter { $0.toolSection == self }
    }
}

extension AppFeature {
    /// Primary tab bar destinations.
    static let mainTabs: [AppFeature] = [.tools, .settings]

    /// Tools list (JIT first as the primary capability).
    static let toolList: [AppFeature] = [
        .jit,
        .launchApps,
        .scripts,
        .console,
        .deviceInfo,
        .profiles,
        .processes,
        .location
    ]
}
