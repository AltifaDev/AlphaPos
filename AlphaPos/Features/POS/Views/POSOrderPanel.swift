import SwiftUI

enum POSReferencePalette {
    static let accent = Color(hex: "385B6D")
    // These colors used to be fixed light values, which left the product
    // workspace, order list and checkout area white while the rest of the app
    // was in dark mode. Use the app's semantic layers so the complete POS
    // follows the selected/system appearance and retains accessible contrast.
    static var background: Color { .appBackground }
    static var subtle: Color { .appSurfaceHigh }
    static var secondaryText: Color { .textSecondary }
}

/// Structural shell for the right-hand order rail.
///
/// Business state and actions remain owned by `POSView`; this view only owns
/// presentation, sizing and entry transitions. That boundary lets the order
/// rail be redesigned without coupling it to checkout persistence.
struct POSOrderPanel<UpperContent: View, LowerContent: View>: View {
    let isPresented: Bool
    @ViewBuilder let upperContent: () -> UpperContent
    @ViewBuilder let lowerContent: () -> LowerContent

    var body: some View {
        VStack(spacing: 0) {
            upperContent()
                .offset(x: isPresented ? 0 : 80)
                .opacity(isPresented ? 1 : 0)

            lowerContent()
                .offset(y: isPresented ? 0 : 60)
                .opacity(isPresented ? 1 : 0)
        }
        // Preserve the existing 30/70 order-to-product workspace ratio.
        .frame(width: 370)
        .background(Color.appSurface)
        .overlay(
            Rectangle()
                .fill(Color.appDivider)
                .frame(width: 1),
            alignment: .leading
        )
    }
}
