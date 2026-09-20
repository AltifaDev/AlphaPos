// DesignSystem.swift
// AlphaPos — Centralised Design Token Library
//
// All colours, gradients, shadows, typography scales, and
// spacing constants are defined here. Views must reference
// tokens from this file instead of hardcoding values.

import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - App Theme Enum
// ─────────────────────────────────────────────────────────────────────────────

enum AppTheme: String, CaseIterable, Identifiable {
    case light  = "light"
    case dark   = "dark"
    case system = "system"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .light:  return "Light Mode"
        case .dark:   return "Antigravity Dark"
        case .system: return "System (Auto)"
        }
    }
}

#if os(iOS) || os(tvOS)
import UIKit
extension UIColor {
    convenience init(hex: String) {
        let h = hex.trimmingCharacters(in: .alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: h).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch h.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255)
    }
}
#elseif os(macOS)
import AppKit
extension NSColor {
    convenience init(hex: String) {
        let h = hex.trimmingCharacters(in: .alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: h).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch h.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255)
    }
}
#endif


// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Colour Palette
// ─────────────────────────────────────────────────────────────────────────────

extension Color {

    static var currentTheme: AppTheme {
        let saved = UserDefaults.standard.string(forKey: "app_theme") ?? AppTheme.dark.rawValue
        return AppTheme(rawValue: saved) ?? .dark
    }

    static func resolveColor(lightHex: String, darkHex: String) -> Color {
        #if os(iOS)
        return Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .light ? UIColor(hex: lightHex) : UIColor(hex: darkHex)
        })
        #elseif os(macOS)
        return Color(NSColor(name: nil) { appearance in
            appearance.name.rawValue.contains("Dark") ? NSColor(hex: darkHex) : NSColor(hex: lightHex)
        })
        #else
        return currentTheme == .light ? Color(hex: lightHex) : Color(hex: darkHex)
        #endif
    }

    // ── Backgrounds ──────────────────────────────────────────────────────────
    /// Main app background — deepest layer
    static var appBackground: Color {
        resolveColor(lightHex: "F3F4F6", darkHex: "111115") // slate-100 / Antigravity deep Space grey-black
    }
    /// Card / panel surface — one level above background
    static var appSurface: Color {
        resolveColor(lightHex: "FFFFFF", darkHex: "18181E") // white / Antigravity dark grey surface
    }
    /// Elevated element (popover, modal card header)
    static var appSurfaceHigh: Color {
        resolveColor(lightHex: "E5E7EB", darkHex: "212128") // slate-200 / Antigravity elevated surface
    }

    // ── Accent ───────────────────────────────────────────────────────────────
    /// Primary Royal Blue accent
    static var appAccent: Color {
        resolveColor(lightHex: "2D71F8", darkHex: "2D71F8")
    }
    /// Secondary Elf Green accent (used for positive/receive indicators)
    static var appTeal: Color {
        resolveColor(lightHex: "146C5C", darkHex: "48C9B0")
    }
    /// Green / Teal accent alias for success indicators
    static var appGreen: Color {
        appTeal
    }
    /// Destructive Coral Red (waste, clock-out, danger)
    static var appRose: Color {
        resolveColor(lightHex: "FC444A", darkHex: "FC444A")
    }
    /// Warning amber
    static var appAmber: Color {
        resolveColor(lightHex: "9A5B00", darkHex: "FBBF24")
    }
    /// Indigo (overstock, inventory analytics, max level indicator)
    static var appIndigo: Color {
        resolveColor(lightHex: "4338CA", darkHex: "6366F1")
    }
    /// Purple accent
    static var appPurple: Color {
        resolveColor(lightHex: "6D28D9", darkHex: "8B5CF6")
    }

    // ── Text ─────────────────────────────────────────────────────────────────
    static var textPrimary: Color {
        resolveColor(lightHex: "111827", darkHex: "FFFFFF")
    }
    static var textSecondary: Color {
        resolveColor(lightHex: "4B5563", darkHex: "9CA3AF")
    }
    static var textTertiary: Color {
        resolveColor(lightHex: "6B7280", darkHex: "A8AFBD")
    }

    // ── Borders / Dividers ───────────────────────────────────────────────────
    static var appDivider: Color {
        resolveColor(lightHex: "E5E7EB", darkHex: "7A7A8A")
    }
    static var appBorderSubtle: Color {
        #if os(iOS)
        return Color(UIColor { traitCollection in
            let theme = currentTheme
            let isLight = theme == .light || (theme == .system && traitCollection.userInterfaceStyle == .light)
            return isLight ? UIColor.black.withAlphaComponent(0.12) : UIColor.white.withAlphaComponent(0.28)
        })
        #elseif os(macOS)
        return Color(NSColor(name: nil) { appearance in
            let theme = currentTheme
            let isLight = theme == .light || (theme == .system && !appearance.name.rawValue.contains("Dark"))
            return isLight ? NSColor.black.withAlphaComponent(0.12) : NSColor.white.withAlphaComponent(0.28)
        })
        #else
        return currentTheme == .light ? Color.black.opacity(0.12) : Color.white.opacity(0.28)
        #endif
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Hex Initialiser Helper
// ─────────────────────────────────────────────────────────────────────────────

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: .alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: h).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch h.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255,
                  blue: Double(b) / 255, opacity: Double(a) / 255)
    }

    /// Fallback to hex colour when no named asset exists in the catalogue.
    func fallback(hex: String) -> Color { self == .clear ? Color(hex: hex) : self }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Gradient Library
// ─────────────────────────────────────────────────────────────────────────────

enum APGradient {

    /// Primary Royal Blue → Sky Blue CTA gradient
    static var accent: LinearGradient {
        LinearGradient(
            colors: [Color.appAccent, Color.appAccent],
            startPoint: .leading, endPoint: .trailing
        )
    }

    /// Green → teal (positive action, clock-in, receive stock)
    static var positive: LinearGradient {
        LinearGradient(
            colors: [Color.appTeal, Color.appTeal],
            startPoint: .leading, endPoint: .trailing
        )
    }

    /// Rose → orange (destructive, clock-out, waste)
    static var destructive: LinearGradient {
        LinearGradient(
            colors: [Color.appRose, Color.appRose],
            startPoint: .leading, endPoint: .trailing
        )
    }

    /// Amber → yellow (warning, low stock)
    static var warning: LinearGradient {
        LinearGradient(
            colors: [Color.appRose, Color.appRose],
            startPoint: .leading, endPoint: .trailing
        )
    }

    /// Sidebar gradient
    static var sidebar: LinearGradient {
        LinearGradient(
            colors: [
                Color.resolveColor(lightHex: "F3F4F6", darkHex: "0C0D12"),
                Color.resolveColor(lightHex: "E5E7EB", darkHex: "08090C")
            ],
            startPoint: .top, endPoint: .bottom
        )
    }

    /// Card inner shimmer overlay (very subtle)
    static var cardShimmer: LinearGradient {
        let startColor = Color.resolveColor(lightHex: "FFFFFF", darkHex: "FFFFFF").opacity(Color.currentTheme == .light ? 0.01 : 0.04)
        return LinearGradient(
            colors: [startColor, Color.clear],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Shadow Presets
// ─────────────────────────────────────────────────────────────────────────────

struct APShadow {
    let color:  Color
    let radius: CGFloat
    let x:      CGFloat
    let y:      CGFloat

    /// Soft ambient card shadow
    static var card: APShadow {
        #if os(iOS)
        let shadowColor = UIColor { traitCollection in
            let theme = Color.currentTheme
            let isLight = theme == .light || (theme == .system && traitCollection.userInterfaceStyle == .light)
            return isLight ? UIColor.black.withAlphaComponent(0.08) : UIColor.black.withAlphaComponent(0.45)
        }
        return APShadow(color: Color(shadowColor), radius: 12, x: 0, y: 6)
        #elseif os(macOS)
        let shadowColor = NSColor(name: nil) { appearance in
            let theme = Color.currentTheme
            let isLight = theme == .light || (theme == .system && !appearance.name.rawValue.contains("Dark"))
            return isLight ? NSColor.black.withAlphaComponent(0.08) : NSColor.black.withAlphaComponent(0.45)
        }
        return APShadow(color: Color(shadowColor), radius: 12, x: 0, y: 6)
        #else
        let isLight = Color.currentTheme == .light
        return APShadow(color: .black.opacity(isLight ? 0.08 : 0.45), radius: 12, x: 0, y: 6)
        #endif
    }

    /// Stronger lift shadow (e.g. modal sheet)
    static var lift: APShadow {
        #if os(iOS)
        let shadowColor = UIColor { traitCollection in
            let theme = Color.currentTheme
            let isLight = theme == .light || (theme == .system && traitCollection.userInterfaceStyle == .light)
            return isLight ? UIColor.black.withAlphaComponent(0.15) : UIColor.black.withAlphaComponent(0.65)
        }
        return APShadow(color: Color(shadowColor), radius: 24, x: 0, y: 12)
        #elseif os(macOS)
        let shadowColor = NSColor(name: nil) { appearance in
            let theme = Color.currentTheme
            let isLight = theme == .light || (theme == .system && !appearance.name.rawValue.contains("Dark"))
            return isLight ? NSColor.black.withAlphaComponent(0.15) : NSColor.black.withAlphaComponent(0.65)
        }
        return APShadow(color: Color(shadowColor), radius: 24, x: 0, y: 12)
        #else
        let isLight = Color.currentTheme == .light
        return APShadow(color: .black.opacity(isLight ? 0.15 : 0.65), radius: 24, x: 0, y: 12)
        #endif
    }

    /// Accent glow for selected / active elements
    static var glow: APShadow {
        APShadow(color: Color.appAccent.opacity(0.35), radius: 16, x: 0, y: 0)
    }
    /// Positive glow (clock-in, receive)
    static var positiveGlow: APShadow {
        APShadow(color: Color.appTeal.opacity(0.35), radius: 16, x: 0, y: 0)
    }
    /// Destructive glow (clock-out, waste)
    static var destructiveGlow: APShadow {
        APShadow(color: Color.appRose.opacity(0.35), radius: 16, x: 0, y: 0)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Spacing Scale
// ─────────────────────────────────────────────────────────────────────────────

enum APSpacing {
    static let xs:  CGFloat = 4
    static let sm:  CGFloat = 8
    static let md:  CGFloat = 16
    static let lg:  CGFloat = 24
    static let xl:  CGFloat = 32
    static let xxl: CGFloat = 48
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Corner Radius Scale
// ─────────────────────────────────────────────────────────────────────────────

enum APRadius {
    static let sm:  CGFloat = 8
    static let md:  CGFloat = 12
    static let lg:  CGFloat = 16
    static let xl:  CGFloat = 24
    static let pill: CGFloat = 100
}

// MARK: - Platform chrome

/// Values for navigation and control chrome. Content cards intentionally keep
/// using opaque surfaces: Liquid Glass belongs above content, not behind every
/// piece of content on screen.
enum APChrome {
    static let controlCornerRadius: CGFloat = 14
    static let sidebarCornerRadius: CGFloat = 26
    static let selectedTintOpacity: Double = 0.14
    static let hoverTintOpacity: Double = 0.07
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Reusable View Modifiers
// ─────────────────────────────────────────────────────────────────────────────

/// Standard dark card surface
struct APCardStyle: ViewModifier {
    var padding: CGFloat = APSpacing.md

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: APRadius.lg, style: .continuous)
                    .fill(Color.appSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: APRadius.lg, style: .continuous)
                            .fill(APGradient.cardShimmer)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: APRadius.lg, style: .continuous)
                            .stroke(Color.appBorderSubtle, lineWidth: 1)
                    )
            )
            .shadow(color: APShadow.card.color,
                    radius: APShadow.card.radius,
                    x: APShadow.card.x,
                    y: APShadow.card.y)
    }
}

/// Full-width gradient CTA button style
struct APGradientButton: ViewModifier {
    var gradient: LinearGradient = APGradient.accent
    var shadow:   APShadow       = APShadow.glow
    var disabled: Bool           = false

    func body(content: Content) -> some View {
        content
            .font(.headline)
            .fontWeight(.bold)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, APSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: APRadius.md, style: .continuous)
                    .fill(AnyShapeStyle(disabled ? AnyShapeStyle(Color.appSurface) : AnyShapeStyle(gradient)))
            )
            .shadow(color: disabled ? .clear : shadow.color,
                    radius: shadow.radius,
                    x: shadow.x, y: shadow.y)
            .opacity(disabled ? 0.45 : 1.0)
    }
}

/// Pill-shaped category/status chip
struct APChipStyle: ViewModifier {
    var selected: Bool
    var selectedGradient: LinearGradient = APGradient.accent

    func body(content: Content) -> some View {
        content
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundColor(selected ? .white : .textSecondary)
            .padding(.horizontal, APSpacing.md)
            .padding(.vertical, APSpacing.sm)
            .background(
                Capsule(style: .continuous)
                    .fill(selected ? AnyShapeStyle(selectedGradient) : AnyShapeStyle(Color.appSurface))
                    .overlay(
                        Capsule()
                            .stroke(selected ? Color.clear : Color.appBorderSubtle, lineWidth: 1)
                    )
            )
            .shadow(color: selected ? Color.appAccent.opacity(0.4) : .clear,
                    radius: 8, x: 0, y: 0)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - View Extensions (convenience)
// ─────────────────────────────────────────────────────────────────────────────

/// Uniform Settings typography — all labels/body text use 12pt.
enum APSettingsType {
    static let pointSize: CGFloat = 12
    static var font: Font { .system(size: pointSize) }
    static var semibold: Font { .system(size: pointSize, weight: .semibold) }
    static var bold: Font { .system(size: pointSize, weight: .bold) }
}

extension View {
    /// Applies a 12pt default font environment for Settings panels.
    func apSettingsTypography() -> some View {
        environment(\.font, APSettingsType.font)
    }

    func apCard(padding: CGFloat = APSpacing.md) -> some View {
        modifier(APCardStyle(padding: padding))
    }

    /// Native Liquid Glass (iOS/iPadOS 26+) with material fallback for earlier OS versions.
    @ViewBuilder
    func apLiquidGlass<S: Shape>(
        tint: Color? = nil,
        interactive: Bool = false,
        allowNativeOnPad: Bool = true,
        in shape: S
    ) -> some View {
        // Keep the rendering path native on iPadOS 26+ as well. The system
        // owns the refraction, translucency, shadows, and GPU compositing;
        // older OS versions use the lightweight material fallback below.
        if #available(iOS 26.0, *),
           UIDevice.current.userInterfaceIdiom != .pad || allowNativeOnPad {
            self.glassEffect(.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            self.apChromeSurface(tint: tint, in: shape)
        }
    }

    /// A restrained selected-control treatment that picks up the refreshed
    /// Liquid Glass rendering automatically when built with the iOS 27 SDK.
    @ViewBuilder
    func apSelectedChrome<S: Shape>(
        tint: Color,
        in shape: S
    ) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(
                .regular.tint(tint.opacity(APChrome.selectedTintOpacity)).interactive(),
                in: shape
            )
        } else {
            self.apChromeSurface(
                tint: tint.opacity(APChrome.selectedTintOpacity),
                in: shape
            )
        }
    }

    /// Material chrome that never uses `glassEffect`.
    /// Prefer this for Menu labels and other controls that must not participate in
    /// Liquid Glass morph layout (Menu + glassEffect is a known iOS 26 footgun).
    func apChromeSurface<S: Shape>(tint: Color? = nil, usesMaterial: Bool = true, in shape: S) -> some View {
        self
            .background {
                ZStack {
                    shape.fill(Color.appSurface)
                    if let tint {
                        shape.fill(tint)
                    }
                    if usesMaterial {
                        shape.fill(.ultraThinMaterial)
                    }
                }
            }
            .overlay(shape.stroke(Color.appBorderSubtle, lineWidth: 1))
    }

    /// System Liquid Glass button styles on iOS 26, with native bordered fallbacks.
    @ViewBuilder
    func apGlassButton(prominent: Bool = false, tint: Color? = nil) -> some View {
        if #available(iOS 26.0, *) {
            if prominent {
                self.buttonStyle(.glassProminent).tint(tint)
            } else {
                self.buttonStyle(.glass).tint(tint)
            }
        } else if prominent {
            self.buttonStyle(.borderedProminent).tint(tint)
        } else {
            self.buttonStyle(.bordered).tint(tint)
        }
    }

    func apGradientButton(
        gradient: LinearGradient = APGradient.accent,
        shadow:   APShadow       = APShadow.glow,
        disabled: Bool           = false
    ) -> some View {
        modifier(APGradientButton(gradient: gradient, shadow: shadow, disabled: disabled))
    }

    func apChip(selected: Bool, gradient: LinearGradient = APGradient.accent) -> some View {
        modifier(APChipStyle(selected: selected, selectedGradient: gradient))
    }

    /// Cross-platform navigation bar styling.
    /// On iOS: sets inline title display mode + toolbar background + toolbar scheme.
    /// On macOS: no-op (these APIs are unavailable).
    func apNavBar(background: Color = Color.appBackground) -> some View {
        modifier(APNavBarModifier(background: background))
    }

    /// Dynamic preferred color scheme helper based on user theme setting
    func apColorScheme() -> some View {
        modifier(APColorSchemeModifier())
    }
}

/// Cross-platform navigation bar modifier
struct APNavBarModifier: ViewModifier {
    let background: Color
    @AppStorage("app_theme") private var appTheme = AppTheme.dark.rawValue
    @Environment(\.colorScheme) private var systemColorScheme
    
    private var resolvedColorScheme: ColorScheme {
        if appTheme == AppTheme.dark.rawValue {
            return .dark
        } else if appTheme == AppTheme.light.rawValue {
            return .light
        } else {
            return systemColorScheme
        }
    }
    
    func body(content: Content) -> some View {
        #if os(iOS) || os(visionOS)
        content
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(background, for: .navigationBar)
            .toolbarColorScheme(resolvedColorScheme, for: .navigationBar)
            .navigationBarBackButtonHidden(true)
        #else
        content
        #endif
    }
}

/// Dynamically resolves and applies the preferred color scheme
struct APColorSchemeModifier: ViewModifier {
    @AppStorage("app_theme") private var appTheme = AppTheme.dark.rawValue
    @Environment(\.colorScheme) private var systemColorScheme
    
    private var resolvedColorScheme: ColorScheme {
        if appTheme == AppTheme.dark.rawValue {
            return .dark
        } else if appTheme == AppTheme.light.rawValue {
            return .light
        } else {
            return systemColorScheme
        }
    }
    
    func body(content: Content) -> some View {
        content
            .preferredColorScheme(resolvedColorScheme)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Status / Type Badge Helper
// ─────────────────────────────────────────────────────────────────────────────

struct APBadge: View {
    let text:  String
    let color: Color
    var icon:  String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.caption2) }
            Text(text).font(.caption2).fontWeight(.bold)
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.15))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(color.opacity(0.3), lineWidth: 0.5))
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Haptic Feedback Helper
// ─────────────────────────────────────────────────────────────────────────────

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct APHaptic {
    #if os(iOS)
    @MainActor private static let impactLight = UIImpactFeedbackGenerator(style: .light)
    @MainActor private static let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    @MainActor private static let selectionGen = UISelectionFeedbackGenerator()
    @MainActor private static let notificationGen = UINotificationFeedbackGenerator()
    #endif

    static func trigger() {
        #if os(iOS)
        if Thread.isMainThread {
            impactMedium.prepare()
            impactMedium.impactOccurred()
        } else {
            DispatchQueue.main.async {
                impactMedium.prepare()
                impactMedium.impactOccurred()
            }
        }
        #elseif os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
        #endif
    }

    /// Fire-and-forget feedback for high-frequency controls (keypads, scanners).
    /// Queueing it after the state mutation keeps the tap handler/frame free.
    static func nonBlockingTrigger() {
        #if os(iOS)
        DispatchQueue.main.async {
            guard !UIAccessibility.isReduceMotionEnabled else { return }
            selectionGen.selectionChanged()
        }
        #elseif os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        #endif
    }

    static func selection() {
        #if os(iOS)
        if Thread.isMainThread {
            selectionGen.prepare()
            selectionGen.selectionChanged()
        } else {
            DispatchQueue.main.async {
                selectionGen.prepare()
                selectionGen.selectionChanged()
            }
        }
        #elseif os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
        #endif
    }

    static func error() {
        #if os(iOS)
        if Thread.isMainThread {
            notificationGen.prepare()
            notificationGen.notificationOccurred(.error)
        } else {
            DispatchQueue.main.async {
                notificationGen.prepare()
                notificationGen.notificationOccurred(.error)
            }
        }
        #elseif os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
        #endif
    }

    static func success() {
        #if os(iOS)
        if Thread.isMainThread {
            notificationGen.prepare()
            notificationGen.notificationOccurred(.success)
        } else {
            DispatchQueue.main.async {
                notificationGen.prepare()
                notificationGen.notificationOccurred(.success)
            }
        }
        #elseif os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
        #endif
    }
}

/// Audible feedback for the order-detail controls.
enum APNativeOrderSound {
    static func buttonTap() {
        guard APSoundEffect.isEnabled else { return }
        APSoundManager.shared.playTap()
    }

    static func printer(isEnabled: Bool) {
        guard APSoundEffect.isEnabled else { return }
        APSoundManager.shared.playPrinterToggle(isEnabled: isEnabled)
    }
}

/// Adds native click feedback to every SwiftUI Button inside Order Detail.
struct APNativeOrderButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed { APNativeOrderSound.buttonTap() }
            }
    }
}

/// Adds the same native click to controls that must keep an Apple-provided
/// button style (for example Liquid Glass). Applying this to the styled Button
/// avoids replacing its visual style while still covering the tap.
private struct APNativeOrderTapSoundModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.simultaneousGesture(
            TapGesture().onEnded { APNativeOrderSound.buttonTap() }
        )
    }
}

extension View {
    func apNativeOrderTapSound() -> some View {
        modifier(APNativeOrderTapSoundModifier())
    }
}

/// Feedback for high-frequency numeric input. Keep this haptic-only: scheduling
/// AudioServicesPlaySystemSound for every rapid tap can queue audio service work
/// faster than it is consumed and makes keypad latency progressively worse.
enum APNativeKeypadFeedback {
    static func tap() {
        #if os(iOS)
        APHaptic.nonBlockingTrigger()
        #endif
    }
}

#if canImport(AVFoundation)
import AVFoundation
#endif
#if canImport(AudioToolbox)
import AudioToolbox
#endif

/// High-volume, high-clarity sound engine for POS operations.
/// Plays pure synthesized PCM audio waveforms through AVAudioPlayer with maximum speaker routing.
final class APSoundManager {
    static let shared = APSoundManager()

    private var tapPlayer: AVAudioPlayer?
    private var paymentPlayer: AVAudioPlayer?
    private var removePlayer: AVAudioPlayer?
    private var alertPlayer: AVAudioPlayer?
    private var printerOnPlayer: AVAudioPlayer?
    private var printerOffPlayer: AVAudioPlayer?

    private init() {
        // AVAudioSession activation can block while the system audio route is
        // changing. Never perform it during view construction on the main
        // thread; keypad taps must remain independent from audio setup.
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.configureAudioSession()
        }
        preparePlayers()
    }

    func configureAudioSession() {
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .default,
                options: [.mixWithOthers]
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("APSoundManager audio session configuration: \(error)")
        }
        #endif
    }

    func preparePlayers() {
        // 1. Crisp high-frequency scanner beep (1900 Hz, punchy 0.05s)
        let tapData = generateWAV(duration: 0.055, sampleRate: 44100) { t in
            let freq = 1900.0
            let envelope = min(1.0, t / 0.003) * max(0.0, 1.0 - (t / 0.055))
            return sin(2.0 * .pi * freq * t) * envelope * 0.98
        }
        tapPlayer = try? AVAudioPlayer(data: tapData)
        tapPlayer?.prepareToPlay()

        // 2. Signature Cash Register "Cha-Ching! 🪙" (Custom bundle file if available, otherwise synthesized)
        if let fileURL = Bundle.main.url(forResource: "cash_register", withExtension: "wav")
            ?? Bundle.main.url(forResource: "cash_register", withExtension: "mp3")
            ?? Bundle.main.url(forResource: "cash_register", withExtension: "m4a") {
            paymentPlayer = try? AVAudioPlayer(contentsOf: fileURL)
        } else {
            let paymentData = generateCashRegisterChaChingWAV()
            paymentPlayer = try? AVAudioPlayer(data: paymentData)
        }
        paymentPlayer?.prepareToPlay()

        // 3. Subtle downwards tap for removing items
        let removeData = generateWAV(duration: 0.045, sampleRate: 44100) { t in
            let freq = 520.0 - (t / 0.045) * 200.0
            let envelope = max(0.0, 1.0 - (t / 0.045))
            return sin(2.0 * .pi * freq * t) * envelope * 0.85
        }
        removePlayer = try? AVAudioPlayer(data: removeData)
        removePlayer?.prepareToPlay()

        // 4. Alert / warning double beep
        let alertData = generateWAV(duration: 0.16, sampleRate: 44100) { t in
            let isFirst = t < 0.07
            let isSecond = t > 0.09 && t < 0.16
            guard isFirst || isSecond else { return 0.0 }
            let subT = isFirst ? t : (t - 0.09)
            let env = max(0.0, 1.0 - (subT / 0.07))
            return sin(2.0 * .pi * 380.0 * subT) * env * 0.95
        }
        alertPlayer = try? AVAudioPlayer(data: alertData)
        alertPlayer?.prepareToPlay()

        // Dedicated loud tones for the printer toggle. System sound IDs are
        // volume-limited on iPad and can remain too quiet at maximum volume.
        let printerOnData = generateWAV(duration: 0.20, sampleRate: 44100) { t in
            let envelope = min(1.0, t / 0.008) * max(0.0, 1.0 - (t / 0.20))
            return (sin(2.0 * .pi * 880.0 * t) * 0.72
                + sin(2.0 * .pi * 1320.0 * t) * 0.28) * envelope
        }
        printerOnPlayer = try? AVAudioPlayer(data: printerOnData)
        printerOnPlayer?.prepareToPlay()

        let printerOffData = generateWAV(duration: 0.20, sampleRate: 44100) { t in
            let envelope = min(1.0, t / 0.008) * max(0.0, 1.0 - (t / 0.20))
            return (sin(2.0 * .pi * 440.0 * t) * 0.72
                + sin(2.0 * .pi * 660.0 * t) * 0.28) * envelope
        }
        printerOffPlayer = try? AVAudioPlayer(data: printerOffData)
        printerOffPlayer?.prepareToPlay()
    }

    private func generateCashRegisterChaChingWAV() -> Data {
        let sampleRate = 44100.0
        let duration = 0.70

        // Coin clinks and bell strikes
        let components: [(start: Double, freq: Double, decay: Double, amp: Double, harmonic: Double)] = [
            // "Cha-" mechanical latch release
            (0.00, 880.0,  35.0, 0.45, 0.3),
            (0.02, 1450.0, 28.0, 0.50, 0.4),
            // "-Ching!" primary crystal bronze bell
            (0.05, 2637.0, 5.0,  0.75, 0.4), // E7 bell
            (0.06, 3136.0, 6.2,  0.55, 0.3), // G7 bell
            (0.05, 5274.0, 7.5,  0.30, 0.2), // E8 overtone
            // Coin jingles in drawer
            (0.08, 4186.0, 16.0, 0.40, 0.2), // Coin 1
            (0.13, 3729.0, 18.0, 0.35, 0.2), // Coin 2
            (0.19, 4698.0, 20.0, 0.25, 0.1)  // Coin 3
        ]

        return generateWAV(duration: duration, sampleRate: Int(sampleRate)) { t in
            var sample = 0.0
            for comp in components where t >= comp.start {
                let noteT = t - comp.start
                let env = exp(-noteT * comp.decay)
                let wave = sin(2.0 * .pi * comp.freq * noteT) + comp.harmonic * sin(2.0 * .pi * (comp.freq * 2.0) * noteT)
                sample += wave * env * comp.amp
            }
            return max(-1.0, min(1.0, sample * 0.90))
        }
    }

    private func generateWAV(duration: Double, sampleRate: Int, generator: (Double) -> Double) -> Data {
        let numSamples = Int(duration * Double(sampleRate))
        let numChannels: Int16 = 1
        let bitsPerSample: Int16 = 16
        let byteRate = Int32(sampleRate * Int(numChannels) * Int(bitsPerSample / 8))
        let blockAlign = Int16(numChannels * (bitsPerSample / 8))
        let subchunk2Size = Int32(numSamples * Int(numChannels) * Int(bitsPerSample / 8))
        let chunkSize = 36 + subchunk2Size

        var data = Data()
        data.append(contentsOf: "RIFF".utf8)
        data.append(contentsOf: withUnsafeBytes(of: chunkSize.littleEndian) { Array($0) })
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        let subchunk1Size: Int32 = 16
        let audioFormat: Int16 = 1
        data.append(contentsOf: withUnsafeBytes(of: subchunk1Size.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: audioFormat.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: numChannels.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: Int32(sampleRate).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })
        data.append(contentsOf: "data".utf8)
        data.append(contentsOf: withUnsafeBytes(of: subchunk2Size.littleEndian) { Array($0) })

        for i in 0..<numSamples {
            let t = Double(i) / Double(sampleRate)
            let val = max(-1.0, min(1.0, generator(t)))
            let sample16 = Int16(val * 32767.0)
            data.append(contentsOf: withUnsafeBytes(of: sample16.littleEndian) { Array($0) })
        }
        return data
    }

    func playTap() {
        guard APSoundEffect.isEnabled else { return }
        play(player: tapPlayer)
    }

    func playPrinterToggle(isEnabled: Bool) {
        guard APSoundEffect.isEnabled else { return }
        play(player: isEnabled ? printerOnPlayer : printerOffPlayer)
    }

    func playPaymentSuccess() {
        guard APSoundEffect.isEnabled else { return }
        // Keep the established payment-success playback path unchanged.
        paymentPlayer?.currentTime = 0
        paymentPlayer?.volume = Float(APSoundEffect.volume)
        paymentPlayer?.play()
    }

    func playItemRemoved() {
        guard APSoundEffect.isEnabled else { return }
        play(player: removePlayer)
    }

    func playAlert() {
        guard APSoundEffect.isEnabled else { return }
        play(player: alertPlayer)
    }

    private func play(player: AVAudioPlayer?) {
        guard let player else { return }
        // AVAudioPlayer must be driven on the main actor. Restarting the
        // prepared player also makes rapid POS taps deterministic on iPad.
        DispatchQueue.main.async {
            player.stop()
            player.currentTime = 0
            player.volume = Float(APSoundEffect.volume)
            player.play()
        }
    }
}

/// Native iPadOS sound effects for POS operations with loud volume and high clarity.
struct APSoundEffect {
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "enable_pos_sound_effects") as? Bool ?? true
    }

    static var volume: Double {
        UserDefaults.standard.object(forKey: "pos_sound_volume") as? Double ?? 1.0
    }

    /// Instantiate and prepare the reusable players before a high-frequency
    /// control receives its first tap. This keeps player construction out of
    /// the keypad action and avoids a first-key frame hitch.
    static func prepare() {
        guard isEnabled else { return }
        _ = APSoundManager.shared
    }

    /// Plays a short crisp high-volume beep when tapping/adding items or scanning barcodes
    static func itemTap() {
        APSoundManager.shared.playTap()
    }

    /// Native short keypad click. System sound avoids creating/activating an
    /// audio session for every digit and stays responsive on iPad.
    static func keypadTap() {
        APSoundManager.shared.playTap()
    }

    /// Plays a loud, rich cashier bell chime when checkout/payment succeeds
    static func paymentSuccess() {
        APSoundManager.shared.playPaymentSuccess()
    }

    /// Plays a subtle confirmation when modifying or decreasing quantity
    static func itemRemoved() {
        APSoundManager.shared.playItemRemoved()
    }

    /// Plays an error/warning alert tone
    static func alert() {
        APSoundManager.shared.playAlert()
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - UIImage Extensions for QR Code Customisation
// ─────────────────────────────────────────────────────────────────────────────

#if canImport(UIKit)
import UIKit

extension UIImage {
    /// Tints the black pixels of the image with a target color
    func tinted(with color: UIColor) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        defer { UIGraphicsEndImageContext() }
        guard let context = UIGraphicsGetCurrentContext(), let cgImage = cgImage else { return nil }
        
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1.0, y: -1.0)
        
        let rect = CGRect(origin: .zero, size: size)
        context.setBlendMode(.normal)
        context.draw(cgImage, in: rect)
        
        context.setBlendMode(.sourceIn)
        color.setFill()
        context.fill(rect)
        
        return UIGraphicsGetImageFromCurrentImageContext()
    }
    
    /// Overlays a system icon in a white bordered card in the center of the image
    func overlayLogo(systemIconName: String, tintColor: UIColor) -> UIImage {
        let size = self.size
        UIGraphicsBeginImageContextWithOptions(size, false, self.scale)
        defer { UIGraphicsEndImageContext() }
        
        self.draw(in: CGRect(origin: .zero, size: size))
        
        let centerSize = size.width * 0.22
        let centerRect = CGRect(
            x: (size.width - centerSize) / 2,
            y: (size.height - centerSize) / 2,
            width: centerSize,
            height: centerSize
        )
        
        let path = UIBezierPath(roundedRect: centerRect, cornerRadius: centerSize * 0.25)
        UIColor.white.setFill()
        path.fill()
        
        tintColor.setStroke()
        path.lineWidth = size.width * 0.012
        path.stroke()
        
        let iconSize = centerSize * 0.65
        let iconRect = CGRect(
            x: (size.width - iconSize) / 2,
            y: (size.height - iconSize) / 2,
            width: iconSize,
            height: iconSize
        )
        
        if let iconImage = UIImage(systemName: systemIconName)?
            .withTintColor(tintColor, renderingMode: .alwaysOriginal) {
            iconImage.draw(in: iconRect)
        }
        
        return UIGraphicsGetImageFromCurrentImageContext() ?? self
    }
}
#endif

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Rolling Number Animation
// ─────────────────────────────────────────────────────────────────────────────

public struct APRollingNumberModifier: ViewModifier {
    let value: Double?
    let text: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(value: Double) {
        self.value = value
        self.text = nil
    }

    public init(text: String) {
        self.value = nil
        self.text = text
    }

    @ViewBuilder
    public func body(content: Content) -> some View {
        if let text = text {
            content
                .monospacedDigit()
                .contentTransition(
                    reduceMotion ? .opacity : .numericText()
                )
                .animation(
                    reduceMotion ? .easeOut(duration: 0.10) : .snappy(duration: 0.14, extraBounce: 0.0),
                    value: text
                )
        } else if let value = value {
            content
                .monospacedDigit()
                .contentTransition(
                    reduceMotion ? .opacity : .numericText(value: value)
                )
                .animation(
                    reduceMotion ? .easeOut(duration: 0.10) : .snappy(duration: 0.14, extraBounce: 0.0),
                    value: value
                )
        } else {
            content
        }
    }
}

extension View {
    /// Applies a butter-smooth rolling number animation for numeric values.
    /// Enforces `.monospacedDigit()` to prevent width thrashing, layout re-evaluations, and frame stutter.
    public func apRollingNumber(value: Double) -> some View {
        modifier(APRollingNumberModifier(value: value))
    }

    /// Overload for string-based numeric inputs (e.g. live keypad typing)
    public func apRollingNumber(text: String) -> some View {
        modifier(APRollingNumberModifier(text: text))
    }

    /// Centralized alias for backward compatibility across the codebase
    public func posRollingNumber(value: Double) -> some View {
        modifier(APRollingNumberModifier(value: value))
    }
}
