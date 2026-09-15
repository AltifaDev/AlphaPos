import AVFoundation
import SwiftUI
import UIKit

/// Branded startup experience shown while the staff workspace is being prepared.
/// The system launch screen uses the same background color, so the handoff does
/// not flash white on physical devices.
struct StaffSplashScreenView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var logoIsVisible = false
    @State private var glowScale: CGFloat = 0.88

    var body: some View {
        ZStack {
            Color(red: 0.035, green: 0.055, blue: 0.105)
                .ignoresSafeArea()

            StaffSplashVideoPlayer(videoName: "LoginBG")
                .ignoresSafeArea()
                .accessibilityHidden(true)

            LinearGradient(
                colors: [
                    Color.black.opacity(0.32),
                    Color(red: 0.04, green: 0.08, blue: 0.18).opacity(0.54),
                    Color.black.opacity(0.72)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .accessibilityHidden(true)

            VStack(spacing: 0) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.22))
                        .frame(width: 174, height: 174)
                        .blur(radius: 28)
                        .scaleEffect(glowScale)
                        .accessibilityHidden(true)

                    Image("AppLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 112, height: 112)
                        .accessibilityHidden(true)
                }

                Text("AlphaPos Staff")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, Color(red: 0.58, green: 0.72, blue: 1)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .padding(.top, 8)

                Text("Work smarter. Serve better.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
                    .padding(.top, 8)

                Spacer()

                HStack(spacing: 10) {
                    ProgressView()
                        .tint(.white)

                    Text("Preparing your workspace")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .background(.ultraThinMaterial.opacity(0.82), in: Capsule())
                .overlay {
                    Capsule().stroke(.white.opacity(0.22), lineWidth: 0.7)
                }
                .padding(.bottom, 30)
            }
            .padding(.horizontal, 24)
            .opacity(logoIsVisible ? 1 : 0)
            .scaleEffect(logoIsVisible ? 1 : 0.96)
        }
        .onAppear {
            if reduceMotion {
                logoIsVisible = true
                glowScale = 1
            } else {
                withAnimation(.easeOut(duration: 0.65)) {
                    logoIsVisible = true
                }
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    glowScale = 1.08
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("AlphaPos Staff, preparing your workspace")
    }
}

private struct StaffSplashVideoPlayer: UIViewRepresentable {
    let videoName: String

    func makeUIView(context: Context) -> LoopingPlayerView {
        let view = LoopingPlayerView()
        view.configure(videoName: videoName)
        return view
    }

    func updateUIView(_ uiView: LoopingPlayerView, context: Context) {
        uiView.play()
    }

    static func dismantleUIView(_ uiView: LoopingPlayerView, coordinator: Void) {
        uiView.stop()
    }

    final class LoopingPlayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }

        private var queuePlayer: AVQueuePlayer?
        private var playerLooper: AVPlayerLooper?
        private var foregroundObserver: NSObjectProtocol?

        private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

        func configure(videoName: String) {
            guard let url = Bundle.main.url(forResource: videoName, withExtension: "mp4") else {
                return
            }

            let player = AVQueuePlayer()
            player.isMuted = true
            player.actionAtItemEnd = .none
            playerLayer.videoGravity = .resizeAspectFill
            playerLayer.player = player

            let item = AVPlayerItem(url: url)
            playerLooper = AVPlayerLooper(player: player, templateItem: item)
            queuePlayer = player
            play()

            foregroundObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.willEnterForegroundNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.play()
            }
        }

        func play() {
            queuePlayer?.play()
        }

        func stop() {
            queuePlayer?.pause()
            if let foregroundObserver {
                NotificationCenter.default.removeObserver(foregroundObserver)
            }
            foregroundObserver = nil
            playerLooper = nil
            queuePlayer = nil
            playerLayer.player = nil
        }

        deinit {
            stop()
        }
    }
}
