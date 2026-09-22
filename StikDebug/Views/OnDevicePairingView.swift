import SwiftUI

struct OnDevicePairingView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var service: OnDevicePairingService
    @State private var appleTVPIN = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                content
                    .frame(maxWidth: 360)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .navigationTitle("Pair a Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        service.cancel()
                        dismiss()
                    }
                }
            }
        }
        .interactiveDismissDisabled(service.phase.isRunning)
        .onAppear {
            service.start()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch service.phase {
        case .idle, .discovering:
            VStack(alignment: .leading, spacing: 20) {
                Label("iPhone or iPad", systemImage: "iphone.gen3")
                    .font(.headline)
                if #available(iOS 27.0, *) {
                    Text("This device: Open Settings › Privacy & Security › Developer Mode, then tap Pair with StikDebug. StikDebug stays active in the background and sends the code as a notification.")
                }
                Text("Another iPhone or iPad (iOS/iPadOS 27+): Open its pairing screen and choose StikDebug. Keep this screen open to see the code.")

                Divider()

                Label("Apple TV", systemImage: "appletv")
                    .font(.headline)
                Text("On Apple TV (tvOS 11+), open Settings › Remotes and Devices › Remote App and Devices, then select it below.")
                if service.appleTVDevices.isEmpty {
                    ProgressView("Searching for Apple TVs…")
                } else {
                    ForEach(service.appleTVDevices) { device in
                        Button {
                            service.pairAppleTV(device)
                        } label: {
                            Label(device.name, systemImage: "appletv")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                Text("StikDebug is available for phone pairing while this screen is open.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .waiting:
            VStack(spacing: 16) {
                ProgressView()
                Text(service.mode == .appleTV
                     ? "Pairing with \(service.selectedAppleTVName ?? "Apple TV")…"
                     : "Confirming the iPhone or iPad pairing…")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Button("Cancel", role: .cancel) {
                    service.cancel()
                }
            }

        case .pin(let pin):
            VStack(spacing: 16) {
                Text(service.mode == .localDevice
                     ? "Enter this code in Settings on this device"
                     : "Enter this code on the other device")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text(pin)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .tracking(6)
                    .textSelection(.enabled)
                ProgressView()
                Button("Cancel", role: .cancel) {
                    service.cancel()
                }
            }

        case .appleTVPIN:
            VStack(spacing: 16) {
                Text("Enter the code shown on \(service.selectedAppleTVName ?? "Apple TV")")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                TextField("Six-digit code", text: $appleTVPIN)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .onChange(of: appleTVPIN) { _, newValue in
                        appleTVPIN = String(newValue.filter { $0 >= "0" && $0 <= "9" }.prefix(6))
                    }
                Button("Pair") {
                    service.submitAppleTVPIN(appleTVPIN)
                    appleTVPIN = ""
                }
                .buttonStyle(.borderedProminent)
                .disabled(appleTVPIN.count != 6)
                Button("Cancel", role: .cancel) {
                    service.cancel()
                }
            }

        case .success(let name, let model, let isLocal):
            VStack(spacing: 14) {
                Label("Pairing Complete", systemImage: "checkmark.seal.fill")
                    .font(.title3.bold())
                    .foregroundStyle(.green)
                if !name.isEmpty || !model.isEmpty {
                    Text([name, model].filter { !$0.isEmpty }.joined(separator: " · "))
                        .foregroundStyle(.secondary)
                }
                Text(isLocal
                     ? "This device's pairing file is saved in StikDebug. You can also export it."
                     : "This pairing file is ready to export. StikDebug's active pairing file was not changed.")
                    .multilineTextAlignment(.center)
                if let exportURL = service.exportURL {
                    ShareLink(
                        item: exportURL,
                        preview: SharePreview("pairingFile.plist", image: Image(systemName: "doc"))
                    ) {
                        Label("Export pairingFile.plist", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)
                }
                Button("Done") {
                    dismiss()
                }
            }

        case .failed(let message):
            VStack(spacing: 14) {
                Label("Pairing Failed", systemImage: "xmark.octagon.fill")
                    .font(.title3.bold())
                    .foregroundStyle(.red)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                Button("Try Again") {
                    service.reset()
                    service.start()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}
