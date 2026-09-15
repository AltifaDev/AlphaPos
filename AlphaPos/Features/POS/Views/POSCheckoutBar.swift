import SwiftUI

/// Layout boundary for checkout and send-to-kitchen actions.
/// Payment selection and checkout handlers are injected by `POSView`.
struct POSCheckoutBar<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, APSpacing.md)
            .padding(.bottom, 12)
            .padding(.top, 10)
            .background(Color.appSurface)
    }
}
