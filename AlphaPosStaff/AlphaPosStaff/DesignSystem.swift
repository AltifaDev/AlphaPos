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
        let saved = UserDefaults.standard.string(forKey: "app_theme") ?? AppTheme.light.rawValue
        return AppTheme(rawValue: saved) ?? .light
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
        resolveColor(lightHex: "F59E0B", darkHex: "FF9F0A")
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
            colors: [Color(hex: "2D71F8").opacity(0.82), Color(hex: "5BA4FF").opacity(0.68)],
            startPoint: .topLeading, endPoint: .bottomTrailing
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
    @AppStorage("app_theme") private var appTheme = AppTheme.light.rawValue
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
    @AppStorage("app_theme") private var appTheme = AppTheme.light.rawValue
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

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Aurora Background (Flowing Gradient Waves)
// ─────────────────────────────────────────────────────────────────────────────

struct AuroraBackground: View {
    @State private var t1: Float = 0
    @State private var t2: Float = 0
    @State private var t3: Float = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let date = timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let w = size.width
                let h = size.height

                // Layer 1 — large warm wave (top)
                var path1 = Path()
                path1.move(to: CGPoint(x: 0, y: h * 0.15))
                path1.addCurve(
                    to: CGPoint(x: w, y: h * 0.25),
                    control1: CGPoint(x: w * 0.3, y: h * 0.05 + CGFloat(sin(date * 0.3)) * 30),
                    control2: CGPoint(x: w * 0.7, y: h * 0.35 + CGFloat(cos(date * 0.25)) * 25)
                )
                path1.addLine(to: CGPoint(x: w, y: h * 0.55))
                path1.addCurve(
                    to: CGPoint(x: 0, y: h * 0.45),
                    control1: CGPoint(x: w * 0.65, y: h * 0.65 + CGFloat(sin(date * 0.2)) * 20),
                    control2: CGPoint(x: w * 0.35, y: h * 0.3 + CGFloat(cos(date * 0.35)) * 18)
                )
                path1.closeSubpath()

                ctx.fill(path1, with: .color(
                    Color(red: 0.18, green: 0.44, blue: 0.97).opacity(0.07)
                ))

                // Layer 2 — violet wave (middle)
                var path2 = Path()
                path2.move(to: CGPoint(x: 0, y: h * 0.35))
                path2.addCurve(
                    to: CGPoint(x: w, y: h * 0.5),
                    control1: CGPoint(x: w * 0.25, y: h * 0.25 + CGFloat(cos(date * 0.22)) * 35),
                    control2: CGPoint(x: w * 0.75, y: h * 0.6 + CGFloat(sin(date * 0.28)) * 28)
                )
                path2.addLine(to: CGPoint(x: w, y: h * 0.75))
                path2.addCurve(
                    to: CGPoint(x: 0, y: h * 0.65),
                    control1: CGPoint(x: w * 0.7, y: h * 0.85 + CGFloat(cos(date * 0.18)) * 22),
                    control2: CGPoint(x: w * 0.3, y: h * 0.5 + CGFloat(sin(date * 0.32)) * 20)
                )
                path2.closeSubpath()

                ctx.fill(path2, with: .color(
                    Color(red: 0.65, green: 0.55, blue: 0.98).opacity(0.06)
                ))

                // Layer 3 — teal accent wave (bottom)
                var path3 = Path()
                path3.move(to: CGPoint(x: 0, y: h * 0.55))
                path3.addCurve(
                    to: CGPoint(x: w, y: h * 0.7),
                    control1: CGPoint(x: w * 0.35, y: h * 0.45 + CGFloat(sin(date * 0.26)) * 28),
                    control2: CGPoint(x: w * 0.65, y: h * 0.8 + CGFloat(cos(date * 0.2)) * 24)
                )
                path3.addLine(to: CGPoint(x: w, y: h))
                path3.addLine(to: CGPoint(x: 0, y: h))
                path3.closeSubpath()

                ctx.fill(path3, with: .color(
                    Color(red: 0.11, green: 0.51, blue: 0.44).opacity(0.05)
                ))
            }
        }
        .ignoresSafeArea()
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Shimmer Effect (for gradient text / borders)
// ─────────────────────────────────────────────────────────────────────────────

struct ShimmerEffect: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: max(0, phase - 0.3)),
                            .init(color: .white.opacity(0.35), location: phase),
                            .init(color: .clear, location: min(1, phase + 0.3))
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .blendMode(.overlay)
                }
            )
            .clipped()
            .onAppear {
                withAnimation(.linear(duration: 2.5).repeatForever(autoreverses: false)) {
                    phase = 2
                }
            }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Glass Morphism Card
// ─────────────────────────────────────────────────────────────────────────────

struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 28
    var opacity: Double = 0.65
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .opacity(opacity)

                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.08),
                                    Color.white.opacity(0.02)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.18),
                                    Color.white.opacity(0.05)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.8
                        )
                }
            )
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Rotating Gradient Ring (Avatar Border)
// ─────────────────────────────────────────────────────────────────────────────

struct PremiumRotatingRing: View {
    let size: CGFloat
    var lineWidth: CGFloat = 3.5
    @State private var rotation: Double = 0

    var body: some View {
        ZStack {
            // Base ring (subtle)
            Circle()
                .stroke(Color.white.opacity(0.1), lineWidth: lineWidth)

            // Rotating gradient arc
            Circle()
                .trim(from: 0, to: 0.35)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            Color(red: 0.18, green: 0.44, blue: 0.97),
                            Color(red: 0.36, green: 0.64, blue: 1.0),
                            Color(red: 0.65, green: 0.55, blue: 0.98),
                            Color(red: 0.18, green: 0.44, blue: 0.97)
                        ]),
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )

            // Second arc (offset, slower)
            Circle()
                .trim(from: 0.5, to: 0.7)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            Color(red: 0.65, green: 0.55, blue: 0.98),
                            Color(red: 0.36, green: 0.64, blue: 1.0).opacity(0.3),
                            Color(red: 0.65, green: 0.55, blue: 0.98)
                        ]),
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: lineWidth * 0.6, lineCap: .round)
                )
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(rotation))
        .onAppear {
            withAnimation(.linear(duration: 5).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Premium Employee Avatar
// ─────────────────────────────────────────────────────────────────────────────

struct PremiumEmployeeAvatar: View {
    let initials: String
    let index: Int
    var size: CGFloat = 110
    var isPressed: Bool = false

    @State private var appeared = false
    @State private var pulseScale: CGFloat = 1.0
    @State private var glowOpacity: Double = 0.0

    private var entryDelay: Double { Double(index) * 0.15 }

    var body: some View {
        ZStack {
            // Layer 0: Ambient glow (breathes)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.18, green: 0.44, blue: 0.97).opacity(0.25),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: size * 0.3,
                        endRadius: size * 0.8
                    )
                )
                .frame(width: size * 1.6, height: size * 1.6)
                .scaleEffect(pulseScale)
                .opacity(glowOpacity)

            // Layer 1: Outer rotating ring
            PremiumRotatingRing(size: size + 16, lineWidth: 3.5)
                .opacity(appeared ? 1 : 0)

            // Layer 2: Glass circle backing
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: size + 4, height: size + 4)
                .opacity(appeared ? 0.6 : 0)

            // Layer 3: Main gradient circle
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.18, green: 0.44, blue: 0.97),
                            Color(red: 0.36, green: 0.64, blue: 1.0),
                            Color(red: 0.25, green: 0.52, blue: 0.96)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
                .shadow(
                    color: Color(red: 0.18, green: 0.44, blue: 0.97).opacity(0.4),
                    radius: 20, x: 0, y: 8
                )

            // Layer 4: Glass highlight (top reflection)
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.25),
                            Color.white.opacity(0.05),
                            .clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .center
                    )
                )
                .frame(width: size, height: size)
                .offset(y: -size * 0.08)

            // Layer 5: Initials
            Text(initials)
                .font(.system(size: size * 0.34, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
        }
        .scaleEffect(isPressed ? 0.88 : (appeared ? 1.0 : 0.3))
        .opacity(appeared ? 1 : 0)
        .onAppear {
            // Staggered spring entry
            DispatchQueue.main.asyncAfter(deadline: .now() + entryDelay) {
                withAnimation(.spring(response: 0.7, dampingFraction: 0.6)) {
                    appeared = true
                }
            }
            // Breathing glow
            withAnimation(
                .easeInOut(duration: 3.0)
                .repeatForever(autoreverses: true)
                .delay(entryDelay + 0.5)
            ) {
                pulseScale = 1.15
                glowOpacity = 1.0
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Floating Particle Stars
// ─────────────────────────────────────────────────────────────────────────────

struct FloatingStarField: View {
    let count: Int = 18
    @State private var stars: [(x: CGFloat, y: CGFloat, size: CGFloat, opacity: Double, speed: Double)] = []
    @State private var animTick = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                for i in 0..<stars.count {
                    let s = stars[i]
                    let ox = sin(t * s.speed + Double(i)) * 15
                    let oy = cos(t * s.speed * 0.7 + Double(i) * 1.3) * 12
                    let flicker = 0.5 + 0.5 * sin(t * s.speed * 2 + Double(i) * 0.8)
                    let pt = CGPoint(x: s.x + ox, y: s.y + oy)

                    let path = Path(ellipseIn: CGRect(
                        x: pt.x - s.size / 2,
                        y: pt.y - s.size / 2,
                        width: s.size,
                        height: s.size
                    ))

                    ctx.fill(path, with: .color(
                        Color.white.opacity(s.opacity * flicker)
                    ))
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            initStars()
        }
    }

    private func initStars() {
        var result: [(x: CGFloat, y: CGFloat, size: CGFloat, opacity: Double, speed: Double)] = []
        for _ in 0..<count {
            result.append((
                x: CGFloat.random(in: 20...380),
                y: CGFloat.random(in: 50...750),
                size: CGFloat.random(in: 2...5),
                opacity: Double.random(in: 0.15...0.45),
                speed: Double.random(in: 0.15...0.4)
            ))
        }
        stars = result
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Animated Gradient Title Text
// ─────────────────────────────────────────────────────────────────────────────

struct GradientTitleText: View {
    let text: String
    @State private var phase: CGFloat = 0

    var body: some View {
        Text(text)
            .font(.system(size: 32, weight: .black, design: .rounded))
            .foregroundStyle(
                LinearGradient(
                    colors: [
                        Color(red: 0.18, green: 0.44, blue: 0.97),
                        Color(red: 0.36, green: 0.64, blue: 1.0),
                        Color(red: 0.65, green: 0.55, blue: 0.98),
                        Color(red: 0.18, green: 0.44, blue: 0.97)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: max(0, phase - 0.3)),
                            .init(color: .white.opacity(0.4), location: phase),
                            .init(color: .clear, location: min(1, phase + 0.3))
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .blendMode(.softLight)
                }
            )
            .clipped()
            .onAppear {
                withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                    phase = 2
                }
            }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Glass Pill Badge
// ─────────────────────────────────────────────────────────────────────────────

struct GlassPillBadge: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(text)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
        }
        .foregroundColor(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 0.8)
                )
        )
    }
}
