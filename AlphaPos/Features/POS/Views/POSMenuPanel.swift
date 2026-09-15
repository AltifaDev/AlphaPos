import SwiftUI

/// Visual boundary for the catalogue side of POS.
/// The catalogue state and item actions remain injected by `POSView`.
struct POSMenuPanel<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity)
            .background(POSReferencePalette.background)
    }
}
