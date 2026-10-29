import SwiftUI

struct DeviceConnectionStatusView: View {
    @ObservedObject private var tunnel = TunnelManager.shared
    var isReadingApps = false
    var hasConfirmedApps = true
    var errorMessage: String?

    private var isWorking: Bool { tunnel.isStarting || isReadingApps }

    private var title: String {
        if tunnel.isStarting { return "Connecting…" }
        if !tunnel.isConnected { return "Device not connected" }
        if isReadingApps { return "Connecting…" }
        if errorMessage != nil { return "Connection error" }
        if !hasConfirmedApps { return "App list unavailable" }
        return "Device connected"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if isWorking {
                ProgressView()
            } else {
                Image(systemName: tunnel.isConnected && errorMessage == nil ? "checkmark.circle" : "exclamationmark.circle")
                    .foregroundStyle(tunnel.isConnected && errorMessage == nil ? .green : .orange)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                if !isWorking, let detail = tunnel.lastError.map({ "Code \($0.code): \($0.localizedDescription)" }) ?? errorMessage {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 0)
        }
    }
}
