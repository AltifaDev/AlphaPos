# AlphaPos — iOS & iPadOS 27 Design Adoption

Updated: 6 August 2026

## Naming

Golden Gate is the product name for macOS 27. iOS 27 and iPadOS 27 share the
same refreshed Liquid Glass design language, but aren't themselves named
Golden Gate.

## Direction for AlphaPos

- Treat navigation, toolbars, floating controls, and selections as the chrome
  layer. This is where Liquid Glass belongs.
- Keep orders, totals, inventory values, forms, and reports in the content
  layer on stable opaque surfaces for fast scanning and reliable contrast.
- Prefer native SwiftUI navigation and controls so the iOS 27 appearance,
  accessibility settings, tint slider, pointer behavior, and future refinements
  arrive automatically.
- Use restrained semantic tint. Color communicates state or module identity;
  it isn't decorative glass applied to every card.
- Preserve resizability on iPad. Important actions must remain reachable when
  the app is narrow, tiled, or the sidebar is hidden.
- Keep the deployment target at iOS/iPadOS 26.0 and retain availability fallbacks
  for older SDK/runtime combinations where the shared code is reused.

## Implemented first pass

- Added centralized chrome tokens to `Core/Design/DesignSystem.swift`.
- Added `apSelectedChrome(tint:in:)`, using interactive Liquid Glass on iOS and
  iPadOS 26+ and a material fallback on earlier releases.
- Changed the dashboard sidebar from a decorative gradient to a quiet material
  navigation layer with a subtle content separator.
- Changed selected sidebar rows to tinted interactive glass and hover rows to
  a lightweight tint, reducing heavy fills and glow.
- Migrated POS payment cards and semantic status cards to native Liquid Glass;
  operational data tables remain opaque where stable contrast is more useful.

## Next passes

1. Move repeated floating toolbar buttons to `apGlassButton` and group related
   actions with native toolbar spacing.
2. Audit every screen at compact and regular widths, prioritizing POS, Tables,
   Kitchen, and Inventory.
3. Audit Dynamic Type, Increase Contrast, Reduce Transparency, Reduce Motion,
   keyboard navigation, pointer targets, and VoiceOver labels.
4. Replace custom menu chrome with native `Menu` where behavior is equivalent.
5. Validate contrast and latency on real iPads before widening adoption.

## Primary references

- Apple Human Interface Guidelines: https://developer.apple.com/design/human-interface-guidelines
- Apple sidebars guidance: https://developer.apple.com/design/human-interface-guidelines/sidebars
- Apple materials guidance: https://developer.apple.com/design/human-interface-guidelines/materials
- WWDC26 — What's new in SwiftUI: https://developer.apple.com/videos/play/wwdc2026/269/
- Apple Design Resources: https://developer.apple.com/design/resources/
