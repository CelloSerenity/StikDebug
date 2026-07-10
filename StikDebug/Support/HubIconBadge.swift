//
//  HubIconBadge.swift
//  StikDebug
//

import SwiftUI

/// Curated badge colors for hub list icons.
enum HubPalette: CaseIterable {
    case blue
    case indigo
    case purple
    case pink
    case red
    case orange
    case yellow
    case green
    case mint
    case teal
    case cyan
    case gray

    /// Solid fill for the rounded badge.
    var fill: Color {
        switch self {
        case .blue: return Color(red: 0.20, green: 0.48, blue: 0.96)
        case .indigo: return Color(red: 0.35, green: 0.34, blue: 0.84)
        case .purple: return Color(red: 0.69, green: 0.32, blue: 0.87)
        case .pink: return Color(red: 0.98, green: 0.27, blue: 0.55)
        case .red: return Color(red: 0.95, green: 0.28, blue: 0.27)
        case .orange: return Color(red: 0.98, green: 0.55, blue: 0.12)
        case .yellow: return Color(red: 0.95, green: 0.72, blue: 0.08)
        case .green: return Color(red: 0.22, green: 0.74, blue: 0.38)
        case .mint: return Color(red: 0.12, green: 0.74, blue: 0.68)
        case .teal: return Color(red: 0.18, green: 0.62, blue: 0.70)
        case .cyan: return Color(red: 0.20, green: 0.68, blue: 0.90)
        case .gray: return Color(red: 0.48, green: 0.50, blue: 0.54)
        }
    }
}

enum HubIconStyle {
    /// Solid colorful badge with a light glyph (primary hub look).
    case palette(HubPalette)
    case success
    case warning
    case danger

    fileprivate var fill: Color {
        switch self {
        case .palette(let palette): return palette.fill
        case .success: return HubPalette.green.fill
        case .warning: return HubPalette.orange.fill
        case .danger: return HubPalette.red.fill
        }
    }
}

struct HubIconBadge: View {
    @Environment(\.colorScheme) private var colorScheme

    let systemImage: String
    var style: HubIconStyle = .palette(.blue)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(style.fill.gradient)
                .frame(width: 40, height: 40)
                .shadow(
                    color: style.fill.opacity(colorScheme == .dark ? 0.35 : 0.22),
                    radius: colorScheme == .dark ? 3 : 2,
                    y: 1
                )

            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .symbolRenderingMode(.hierarchical)
                .shadow(color: .black.opacity(0.12), radius: 0.5, y: 0.5)
        }
        .accessibilityHidden(true)
    }
}
