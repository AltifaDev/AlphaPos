import SwiftUI

/// Native iOS workspace handoff shown while the authenticated dashboard is
/// being materialized. `ProgressView` supplies the system loading animation;
/// there is intentionally no custom spinner, timer, or drawing here.
struct WorkspaceTransitionOverlay: View {
    let message: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.24)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)

                Text(message)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
        .allowsHitTesting(true)
    }
}
