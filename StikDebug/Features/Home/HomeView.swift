//
//  HomeView.swift
//  StikDebug
//
//  Created by Stephen on 3/26/25.
//

import SwiftUI

/// JIT tool — enable Just-In-Time for eligible installed apps.
struct HomeView: View {
    @AppStorage("bundleID") private var bundleID: String = ""
    @ObservedObject private var pairingImport = PairingFileImportCoordinator.shared
    @ObservedObject private var viewModel = HomeViewModel.shared

    var body: some View {
        InstalledAppsListView(
            mode: .jit,
            onSelectApp: { selectedBundle, selectedName in
                bundleID = selectedBundle
                Haptics.medium()
                viewModel.startJIT(bundleID: selectedBundle, displayName: selectedName)
            },
            showDoneButton: false,
            onImportPairingFile: { pairingImport.requestImport() },
            isJITOperationInFlight: viewModel.isJITOperationInFlight,
            embedsNavigation: false
        )
    }
}

#Preview {
    NavigationStack {
        HomeView()
    }
}
