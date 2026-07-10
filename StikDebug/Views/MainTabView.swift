//
//  MainTabView.swift
//  StikDebug
//
//  Created by Stephen on 3/27/25.
//

import SwiftUI
import Foundation

private enum ExternalLocationAction: Identifiable {
    case simulate(URL, Double, Double)
    case clear

    var id: String {
        switch self {
        case .simulate(let url, _, _):
            return "simulate-\(url.absoluteString)"
        case .clear:
            return "clear-location"
        }
    }

    var title: String {
        switch self {
        case .simulate:
            return "Simulate Location?"
        case .clear:
            return "Clear Location?"
        }
    }

    var message: String {
        switch self {
        case .simulate(_, let latitude, let longitude):
            return String(format: "An external link wants to set the simulated location to %.6f, %.6f.", latitude, longitude)
        case .clear:
            return "An external link wants to clear the simulated location."
        }
    }

    var confirmationTitle: String {
        switch self {
        case .simulate:
            return "Set Location"
        case .clear:
            return "Clear Location"
        }
    }
}

struct MainTabView: View {
    @AppStorage(UserDefaults.Keys.primaryTabSelection) private var selection: String = AppFeature.tools.id
    @StateObject private var pairingImport = PairingFileImportCoordinator.shared
    @ObservedObject private var jitViewModel = HomeViewModel.shared
    @State private var detachedFeature: AppFeature?
    @State private var pendingLocationAction: ExternalLocationAction?

    var body: some View {
        ZStack {
            Color.clear.ignoresSafeArea()

            TabView(selection: $selection) {
                ForEach(AppFeature.mainTabs) { feature in
                    feature.destination
                        .tabItem { Label(feature.title, systemImage: feature.systemImage) }
                        .tag(feature.id)
                }
            }
            .statusToast($jitViewModel.toast)
            .onAppear {
                ensureSelectionIsValid()
                jitViewModel.handleAppear()
            }
            .onOpenURL { url in
                handleURL(url)
            }
            .onReceive(NotificationCenter.default.publisher(for: .intentJSScriptReady)) { notification in
                jitViewModel.handleScriptReady(notification)
            }
            .confirmationDialog(
                pendingLocationAction?.title ?? "External Location Request",
                isPresented: Binding(
                    get: { pendingLocationAction != nil },
                    set: { isPresented in
                        if !isPresented {
                            pendingLocationAction = nil
                        }
                    }
                ),
                titleVisibility: .visible,
                presenting: pendingLocationAction
            ) { action in
                Button(action.confirmationTitle, role: .destructive) {
                    performLocationAction(action)
                    pendingLocationAction = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingLocationAction = nil
                }
            } message: { action in
                Text(action.message)
            }
            .confirmationDialog(
                jitViewModel.pendingExternalURLAction?.title ?? "External Request",
                isPresented: Binding(
                    get: { jitViewModel.pendingExternalURLAction != nil },
                    set: { isPresented in
                        if !isPresented {
                            jitViewModel.pendingExternalURLAction = nil
                        }
                    }
                ),
                titleVisibility: .visible,
                presenting: jitViewModel.pendingExternalURLAction
            ) { action in
                Button(action.confirmationTitle, role: action.role) {
                    jitViewModel.performExternalURLAction(action)
                    jitViewModel.pendingExternalURLAction = nil
                }
                Button("Cancel", role: .cancel) {
                    jitViewModel.pendingExternalURLAction = nil
                }
            } message: { action in
                Text(action.message)
            }
            .sheet(item: $detachedFeature) { feature in
                NavigationStack {
                    feature.destination
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close") {
                                    detachedFeature = nil
                                }
                            }
                        }
                }
            }
            .sheet(item: $jitViewModel.scriptRunModel) { model in
                NavigationStack {
                    RunJSView(model: model)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { jitViewModel.scriptRunModel = nil }
                            }
                        }
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
            .fileImporter(
                isPresented: $pairingImport.isPickerPresented,
                allowedContentTypes: PairingFileStore.supportedContentTypes,
                onCompletion: pairingImport.handlePickerResult
            )
            .onReceive(NotificationCenter.default.publisher(for: .showPairingFilePicker)) { _ in
                selection = AppFeature.tools.id
                pairingImport.requestImport()
            }
        }
    }

    private func ensureSelectionIsValid() {
        let ids = AppFeature.mainTabs.map { $0.id }
        if ids.contains(selection) {
            return
        }
        selection = AppFeature.tools.id
    }

    private func handleURL(_ url: URL) {
        guard let host = url.host()?.lowercased() else { return }

        switch host {
        case "enable-jit", "kill-process", "launch-app":
            jitViewModel.handleExternalURL(url)
        case "simulate-location", "set-location":
            confirmSimulatedLocation(from: url)
        case "location", "location-simulation":
            if URLQueryHelpers.coordinate(from: url) == nil {
                openFeature(id: AppFeature.location.id)
            } else {
                confirmSimulatedLocation(from: url)
            }
        case "clear-location", "stop-location":
            pendingLocationAction = .clear
        case "jit":
            openFeature(id: AppFeature.jit.id)
        case "tools":
            selection = AppFeature.tools.id
        case "settings":
            selection = AppFeature.settings.id
        default:
            // Unknown hosts that look like tools open as detached features when possible.
            if let feature = AppFeature(rawValue: host) {
                openFeature(id: feature.id)
            }
        }
    }

    private func openFeature(id: String) {
        guard let feature = AppFeature(rawValue: id) else {
            return
        }

        if AppFeature.mainTabs.contains(feature) {
            selection = feature.id
        } else {
            detachedFeature = feature
        }
    }

    private func confirmSimulatedLocation(from url: URL) {
        guard let coordinate = URLQueryHelpers.coordinate(from: url) else {
            showAlert(
                title: "Invalid Location URL",
                message: "Use stikdebug://simulate-location?lat=37.3349&lon=-122.0090",
                showOk: true
            )
            return
        }

        guard URLQueryHelpers.coordinateIsValid(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        ) else {
            showAlert(
                title: "Invalid Coordinates",
                message: "Latitude must be between -90 and 90. Longitude must be between -180 and 180.",
                showOk: true
            )
            return
        }

        pendingLocationAction = .simulate(url, coordinate.latitude, coordinate.longitude)
    }

    private func performLocationAction(_ action: ExternalLocationAction) {
        switch action {
        case .simulate(let url, _, _):
            simulateLocation(from: url)
        case .clear:
            clearSimulatedLocation()
        }
    }

    private func simulateLocation(from url: URL) {
        guard let coordinate = URLQueryHelpers.coordinate(from: url),
              URLQueryHelpers.coordinateIsValid(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
              ) else {
            showAlert(
                title: "Invalid Location URL",
                message: "Use stikdebug://simulate-location?lat=37.3349&lon=-122.0090",
                showOk: true
            )
            return
        }

        let pairingFile = PairingFileStore.prepareURL()
        guard FileManager.default.fileExists(atPath: pairingFile.path) else {
            showAlert(
                title: "Pairing File Required",
                message: "Import a pairing file before simulating location from a URL.",
                showOk: true
            )
            return
        }

        LocationSimulationCommandQueue.shared.async {
            let code = simulate_location(
                DeviceConnectionContext.targetIPAddress,
                coordinate.latitude,
                coordinate.longitude,
                pairingFile.path
            )

            DispatchQueue.main.async {
                if code == 0 {
                    LogManager.shared.addInfoLog(
                        String(
                            format: "Simulated location from URL: %.6f, %.6f",
                            coordinate.latitude,
                            coordinate.longitude
                        )
                    )
                } else {
                    showAlert(
                        title: "Location Simulation Failed",
                        message: "Could not simulate location from URL (error \(code)). Make sure the device is connected and the DDI is mounted.",
                        showOk: true
                    )
                }
            }
        }
    }

    private func clearSimulatedLocation() {
        LocationSimulationCommandQueue.shared.async {
            let code = clear_simulated_location()
            DispatchQueue.main.async {
                if code == 0 {
                    LogManager.shared.addInfoLog("Cleared simulated location from URL")
                } else {
                    showAlert(
                        title: "Clear Location Failed",
                        message: "Could not clear simulated location from URL (error \(code)).",
                        showOk: true
                    )
                }
            }
        }
    }
}

struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView()
    }
}
