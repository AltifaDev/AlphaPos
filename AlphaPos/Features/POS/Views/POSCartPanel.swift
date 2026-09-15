import SwiftUI

/// Visual boundary for the order/cart side of POS.
/// Cart mutations continue to be owned by `POSViewModel`.
struct POSCartPanel<UpperContent: View, LowerContent: View>: View {
    let isPresented: Bool
    @ViewBuilder let upperContent: () -> UpperContent
    @ViewBuilder let lowerContent: () -> LowerContent

    var body: some View {
        POSOrderPanel(isPresented: isPresented) {
            upperContent()
        } lowerContent: {
            lowerContent()
        }
    }
}
