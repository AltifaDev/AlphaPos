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

    /// Dynamic color helper resolving light/dark hex using native platform providers
    static func resolveColor(lightHex: String, darkHex: String) -> Color {
        #if os(iOS)
        return Color(UIColor { traitCollection in
            let theme = currentTheme
            if theme == .light {
                return UIColor(hex: lightHex)
            } else if theme == .dark {
                return UIColor(hex: darkHex)
            } else {
                return traitCollection.userInterfaceStyle == .light ? UIColor(hex: lightHex) : UIColor(hex: darkHex)
            }
        })
        #elseif os(macOS)
        return Color(NSColor(name: nil) { appearance in
            let theme = currentTheme
            if theme == .light {
                return NSColor(hex: lightHex)
            } else if theme == .dark {
                return NSColor(hex: darkHex)
            } else {
                let isDark = appearance.name.rawValue.contains("Dark")
                return isDark ? NSColor(hex: darkHex) : NSColor(hex: lightHex)
            }
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
        resolveColor(lightHex: "1C8370", darkHex: "1C8370")
    }
    /// Destructive Coral Red (waste, clock-out, danger)
    static var appRose: Color {
        resolveColor(lightHex: "FC444A", darkHex: "FC444A")
    }
    /// Warning amber
    static var appAmber: Color {
        resolveColor(lightHex: "FC444A", darkHex: "FC444A")
    }

    // ── Text ─────────────────────────────────────────────────────────────────
    static var textPrimary: Color {
        resolveColor(lightHex: "111827", darkHex: "FFFFFF")
    }
    static var textSecondary: Color {
        resolveColor(lightHex: "4B5563", darkHex: "9CA3AF")
    }
    static var textTertiary: Color {
        resolveColor(lightHex: "9CA3AF", darkHex: "4B5563")
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
            return isLight ? UIColor.black.withAlphaComponent(0.04) : UIColor.white.withAlphaComponent(0.20)
        })
        #elseif os(macOS)
        return Color(NSColor(name: nil) { appearance in
            let theme = currentTheme
            let isLight = theme == .light || (theme == .system && !appearance.name.rawValue.contains("Dark"))
            return isLight ? NSColor.black.withAlphaComponent(0.04) : NSColor.white.withAlphaComponent(0.20)
        })
        #else
        return currentTheme == .light ? Color.black.opacity(0.04) : Color.white.opacity(0.20)
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

extension View {
    func apCard(padding: CGFloat = APSpacing.md) -> some View {
        modifier(APCardStyle(padding: padding))
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
    static func trigger() {
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
        #elseif os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
        #endif
    }
}
