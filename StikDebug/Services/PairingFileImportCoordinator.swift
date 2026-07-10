//
//  PairingFileImportCoordinator.swift
//  StikDebug
//

import Combine
import Foundation

struct PairingImportFeedback: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let isError: Bool
}

/// Owns the pairing-file import side effects so every entry point refreshes the
/// same device state after a file changes.
@MainActor
final class PairingFileImportCoordinator: ObservableObject {
    static let shared = PairingFileImportCoordinator()

    @Published var isPickerPresented = false
    @Published private(set) var feedback: PairingImportFeedback?

    private init() {}

    func requestImport() {
        feedback = nil
        isPickerPresented = true
    }

    func handlePickerResult(_ result: Result<URL, Error>) {
        isPickerPresented = false

        do {
            let url = try result.get()
            try PairingFileStore.importFromPicker(url)

            feedback = PairingImportFeedback(message: "Pairing file imported", isError: false)
            LogManager.shared.addInfoLog("Pairing file imported")
            markTunnelDisconnected()
            startTunnelInBackground()
            NotificationCenter.default.post(name: .pairingFileImported, object: nil)
        } catch {
            let message = "Import failed: \(error.localizedDescription)"
            feedback = PairingImportFeedback(message: message, isError: true)
            LogManager.shared.addErrorLog(message)
            showAlert(title: "Pairing File Import Failed", message: error.localizedDescription, showOk: true)
        }
    }
}
