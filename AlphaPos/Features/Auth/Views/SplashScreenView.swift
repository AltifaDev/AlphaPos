import SwiftUI

struct SplashScreenView: View {
    let statusText: String

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()

            LoopingVideoPlayer(videoName: "PosVid")
                // ponytail: crop the watermarked lower edge; replace the source video if its framing changes.
                .scaleEffect(1.12, anchor: .top)
                .ignoresSafeArea()
                .accessibilityHidden(true)

            HStack(spacing: 10) {
                ProgressView()
                    .tint(.white)
                Text(statusText)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.black.opacity(0.45), in: Capsule())
            .padding(.bottom, 28)
        }
        .clipped()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("AlphaPos, \(statusText)")
    }
}
