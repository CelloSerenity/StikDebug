//
//  StatusToast.swift
//  StikDebug
//

import SwiftUI

/// Lightweight bottom toast used for short-lived success / failure / progress feedback.
struct StatusToast: Identifiable, Equatable {
    let id: UUID
    let message: String
    let isError: Bool
    let isWorking: Bool

    init(message: String, isError: Bool = false, isWorking: Bool = false, id: UUID = UUID()) {
        self.id = id
        self.message = message
        self.isError = isError
        self.isWorking = isWorking
    }

    static func working(_ message: String) -> StatusToast {
        StatusToast(message: message, isError: false, isWorking: true)
    }

    static func success(_ message: String) -> StatusToast {
        StatusToast(message: message, isError: false, isWorking: false)
    }

    static func failure(_ message: String) -> StatusToast {
        StatusToast(message: message, isError: true, isWorking: false)
    }
}

struct StatusToastBanner: View {
    let toast: StatusToast

    var body: some View {
        HStack(spacing: 10) {
            if toast.isWorking {
                ProgressView()
                    .controlSize(.small)
            } else if toast.isError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .imageScale(.small)
            }

            Text(toast.message)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Capsule().fill(.ultraThinMaterial))
        .foregroundStyle(toast.isError ? Color.red : Color.primary)
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        .padding(.horizontal, 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(toast.message)
        .accessibilityAddTraits(toast.isWorking ? [] : .isStaticText)
    }
}

struct StatusToastOverlay: ViewModifier {
    @Binding var toast: StatusToast?
    var bottomPadding: CGFloat = 40
    var autoDismiss: TimeInterval = 3.0

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let toast {
                    StatusToastBanner(toast: toast)
                        .padding(.bottom, bottomPadding)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .id(toast.id)
                }
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.86), value: toast?.id)
            .onChange(of: toast?.id) { _, newID in
                guard let newID, let current = toast, !current.isWorking else { return }
                let dismissAfter = autoDismiss
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: UInt64(dismissAfter * 1_000_000_000))
                    if toast?.id == newID {
                        withAnimation {
                            toast = nil
                        }
                    }
                }
            }
    }
}

extension View {
    func statusToast(_ toast: Binding<StatusToast?>, bottomPadding: CGFloat = 40) -> some View {
        modifier(StatusToastOverlay(toast: toast, bottomPadding: bottomPadding))
    }
}
