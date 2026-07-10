//
//  LaunchAppsView.swift
//  StikDebug
//

import SwiftUI

/// Tools entry point for launching installed apps without attaching JIT.
struct LaunchAppsView: View {
    var body: some View {
        InstalledAppsListView(
            mode: .launch,
            onSelectApp: { _, _ in },
            showDoneButton: false,
            embedsNavigation: false
        )
    }
}

#Preview {
    NavigationStack {
        LaunchAppsView()
    }
}
