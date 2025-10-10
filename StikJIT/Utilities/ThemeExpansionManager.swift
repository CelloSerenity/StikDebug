import Foundation
import StoreKit
import SwiftUI

enum CustomThemeStyle: String, Codable, CaseIterable, Identifiable {
    case staticGradient
    case animatedGradient
    case blobs
    case particles

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .staticGradient:   return "Static Gradient"
        case .animatedGradient: return "Animated Gradient"
        case .blobs:            return "Floating Blobs"
        case .particles:        return "Particle Field"
        }
    }
}

struct CustomTheme: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var style: CustomThemeStyle
    var colorHexes: [String]
    var preferredColorSchemeRaw: String?

    init(id: UUID = UUID(),
         name: String,
         style: CustomThemeStyle,
         colorHexes: [String],
         preferredColorScheme: ColorScheme?) {
        self.id = id
        self.name = name
        self.style = style
        self.colorHexes = colorHexes
        self.preferredColorSchemeRaw = preferredColorScheme.map { $0 == .dark ? "dark" : "light" }
    }

    var preferredColorScheme: ColorScheme? {
        switch preferredColorSchemeRaw {
        case "light": return .light
        case "dark":  return .dark
        default:        return nil
        }
    }

    var gradientColors: [Color] {
        colorHexes.compactMap { Color(hex: $0) }
    }

    func updating(name: String? = nil,
                  style: CustomThemeStyle? = nil,
                  colors: [String]? = nil,
                  preferredColorScheme: ColorScheme?? = nil) -> CustomTheme {
        CustomTheme(id: id,
                    name: name ?? self.name,
                    style: style ?? self.style,
                    colorHexes: colors ?? self.colorHexes,
                    preferredColorScheme: preferredColorScheme ?? self.preferredColorScheme)
    }
}

// MARK: - Distribution detection (receipt-based)

enum DistributorType: String {
    case appStore
    case testFlight
    case other
}

@MainActor
final class ThemeExpansionManager: ObservableObject {
    static let productIdentifier = "SD_Theme_Expansion"

    @Published private(set) var hasThemeExpansion = false
    @Published private(set) var themeExpansionProduct: Product?
    @Published private(set) var isProcessing = false
    @Published var lastError: String?
    @Published private(set) var customThemes: [CustomTheme] = []

    // New: distribution awareness
    @Published private(set) var distributor: DistributorType
    var isAppStoreBuild: Bool { distributor == .appStore }

    private var updatesTask: Task<Void, Never>?
    private let isPreviewInstance: Bool
    private let customThemesKey = "ThemeExpansion.CustomThemes"

    init(previewUnlocked: Bool = false) {
        self.isPreviewInstance = previewUnlocked
        self.distributor = ThemeExpansionManager.detectDistributor()
        self.hasThemeExpansion = previewUnlocked
        loadCustomThemes()

        if previewUnlocked && customThemes.isEmpty {
            customThemes = [
                CustomTheme(name: "Vapor Trail",
                            style: .animatedGradient,
                            colorHexes: ["#FF00E0", "#00D0FF", "#7A00FF"],
                            preferredColorScheme: .dark)
            ]
        }

        guard !previewUnlocked else { return }

        // Only wire StoreKit listeners if this is an App Store build
        if isAppStoreBuild {
            updatesTask = Task { [weak self] in
                guard let self else { return }
                for await result in StoreKit.Transaction.updates {
                    await self.handle(transactionResult: result)
                }
            }

            Task { await refreshEntitlements() }
        } else {
            // Non–App Store builds cannot purchase yet; keep everything locked and quiet
            self.hasThemeExpansion = false
            self.themeExpansionProduct = nil
            self.lastError = nil
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    // MARK: - Public API

    func refreshEntitlements() async {
        guard !isPreviewInstance else { return }
        guard isAppStoreBuild else { return } // No-op outside App Store

        isProcessing = true
        defer { isProcessing = false }
        do {
            lastError = nil
            let products = try await Product.products(for: [Self.productIdentifier])
            themeExpansionProduct = products.first

            if products.isEmpty {
                #if targetEnvironment(simulator)
                lastError = """
                No products found for.
                """
                #else
                lastError = """
                No products found for.
                """
                #endif
            }

            // Recompute entitlement from current entitlements
            hasThemeExpansion = await isEntitledToThemeExpansion()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func restorePurchases() async {
        guard !isPreviewInstance else { return }
        guard isAppStoreBuild else {
            lastError = "Theme Expansion is coming soon on this store."
            return
        }
        isProcessing = true
        defer { isProcessing = false }
        do {
            lastError = nil
            try await AppStore.sync()
            hasThemeExpansion = await isEntitledToThemeExpansion()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func purchaseThemeExpansion() async {
        guard !isPreviewInstance else { return }
        guard isAppStoreBuild else {
            lastError = "Theme Expansion is coming soon on this store."
            return
        }

        let product: Product
        if let cached = themeExpansionProduct {
            product = cached
        } else {
            do {
                let products = try await Product.products(for: [Self.productIdentifier])
                if let first = products.first {
                    themeExpansionProduct = first
                    product = first
                } else {
                    #if targetEnvironment(simulator)
                    lastError = """
                    Theme Expansion isn’t available.
                    """
                    #else
                    lastError = """
                    Theme Expansion isn’t available.
                    """
                    #endif
                    return
                }
            } catch {
                lastError = error.localizedDescription
                return
            }
        }

        isProcessing = true
        defer { isProcessing = false }

        do {
            lastError = nil
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                await handle(transactionResult: verification)
            case .pending:
                lastError = "Purchase pending. You'll be notified when it's complete."
            case .userCancelled:
                break
            @unknown default:
                lastError = "Purchase failed due to an unknown error."
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func resolvedAccentColor(from hex: String) -> Color {
        guard hasThemeExpansion, !hex.isEmpty, let custom = Color(hex: hex) else { return .blue }
        return custom
    }

    func resolvedTheme(from rawValue: String) -> AppTheme {
        guard let theme = AppTheme(rawValue: rawValue), hasThemeExpansion || theme == .system else {
            return .system
        }
        return theme
    }

    func backgroundStyle(for identifier: String) -> BackgroundStyle {
        if hasThemeExpansion, let custom = customTheme(for: identifier) {
            let colors = normalizedColors(from: custom.colorHexes)
            switch custom.style {
            case .staticGradient:
                return .staticGradient(colors: colors)
            case .animatedGradient:
                return .animatedGradient(colors: colors, speed: 0.08)
            case .blobs:
                return .blobs(colors: colors, background: colors)
            case .particles:
                return .particles(particle: colors.first ?? .white, background: colors)
            }
        }

        if let theme = AppTheme(rawValue: identifier), (hasThemeExpansion || theme == .system) {
            return theme.backgroundStyle
        }

        return AppTheme.system.backgroundStyle
    }

    func preferredColorScheme(for identifier: String) -> ColorScheme? {
        if hasThemeExpansion, let custom = customTheme(for: identifier) {
            return custom.preferredColorScheme
        }
        if let theme = AppTheme(rawValue: identifier), (hasThemeExpansion || theme == .system) {
            return theme.preferredColorScheme
        }
        return nil
    }

    func customThemeIdentifier(for theme: CustomTheme) -> String {
        "custom:\(theme.id.uuidString)"
    }

    func isCustomThemeIdentifier(_ identifier: String) -> Bool {
        identifier.hasPrefix("custom:")
    }

    func customTheme(for identifier: String) -> CustomTheme? {
        guard isCustomThemeIdentifier(identifier) else { return nil }
        let idString = identifier.replacingOccurrences(of: "custom:", with: "")
        guard let uuid = UUID(uuidString: idString) else { return nil }
        return customThemes.first { $0.id == uuid }
    }

    func upsert(customTheme: CustomTheme) {
        guard hasThemeExpansion || isPreviewInstance else { return }
        var sanitized = customTheme
        sanitized.colorHexes = sanitize(hexes: sanitized.colorHexes)

        if let index = customThemes.firstIndex(where: { $0.id == sanitized.id }) {
            customThemes[index] = sanitized
        } else {
            customThemes.append(sanitized)
        }
        saveCustomThemes()
    }

    func delete(customTheme: CustomTheme) {
        customThemes.removeAll { $0.id == customTheme.id }
        saveCustomThemes()
    }

    // MARK: - Persistence

    private func loadCustomThemes() {
        guard let data = UserDefaults.standard.data(forKey: customThemesKey),
              let decoded = try? JSONDecoder().decode([CustomTheme].self, from: data) else {
            return
        }
        customThemes = decoded
    }

    private func saveCustomThemes() {
        guard let data = try? JSONEncoder().encode(customThemes) else { return }
        UserDefaults.standard.set(data, forKey: customThemesKey)
    }

    private func sanitize(hexes: [String]) -> [String] {
        let cleaned = hexes.filter { !$0.isEmpty }
        if cleaned.count >= 2 { return cleaned }
        if let first = cleaned.first {
            return [first, first]
        }
        return ["#1C1F3A", "#3E4C7C"]
    }

    private func normalizedColors(from hexes: [String]) -> [Color] {
        let colors = hexes.compactMap { Color(hex: $0) }
        if colors.count >= 2 { return colors }
        if let first = colors.first { return [first, first.opacity(0.65)] }
        return [Color.blue, Color.purple]
    }

    // MARK: - StoreKit plumbing

    private func handle(transactionResult: VerificationResult<StoreKit.Transaction>, finishTransaction: Bool = true) async {
        switch transactionResult {
        case .verified(let transaction):
            if transaction.productID == Self.productIdentifier {
                hasThemeExpansion = (transaction.revocationDate == nil)
                lastError = nil
            }
            if finishTransaction {
                await transaction.finish()
            }
        case .unverified(_, let error):
            lastError = error.localizedDescription
        }
    }

    private func isEntitledToThemeExpansion() async -> Bool {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, transaction.productID == Self.productIdentifier {
                return transaction.revocationDate == nil
            }
        }
        return false
    }

    // MARK: - Distributor detection helper

    private static func detectDistributor() -> DistributorType {
        guard let receiptURL = Bundle.main.appStoreReceiptURL else {
            return .other
        }
        let path = receiptURL.path
        if FileManager.default.fileExists(atPath: path) {
            // TestFlight builds use "sandboxReceipt"
            return receiptURL.lastPathComponent == "sandboxReceipt" ? .testFlight : .appStore
        } else {
            return .other
        }
    }
}

#if DEBUG
extension ThemeExpansionManager {
    static func previewUnlocked() -> ThemeExpansionManager {
        ThemeExpansionManager(previewUnlocked: true)
    }

    static func previewLocked() -> ThemeExpansionManager {
        ThemeExpansionManager(previewUnlocked: false)
    }
}
#endif

// MARK: - Environment support

private struct ThemeExpansionEnvironmentKey: EnvironmentKey {
    static let defaultValue: ThemeExpansionManager? = nil
}

extension EnvironmentValues {
    var themeExpansionManager: ThemeExpansionManager? {
        get { self[ThemeExpansionEnvironmentKey.self] }
        set { self[ThemeExpansionEnvironmentKey.self] = newValue }
    }
}

extension View {
    func themeExpansionManager(_ manager: ThemeExpansionManager) -> some View {
        environment(\.themeExpansionManager, manager)
    }
}
