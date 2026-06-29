import AVFoundation
import AVKit
import SwiftUI

// MARK: - LoopingVideoPlayer
// ─────────────────────────────────────────────────────────────────────────────
// Shared component: เล่นวิดีโอ loop อัตโนมัติ ไม่มีเสียง
// ใช้ AVQueuePlayer + AVPlayerLooper (Apple recommended pattern)
//
// Usage — from Bundle resource:
//   LoopingVideoPlayer(videoName: "staff_lock_bg", videoExtension: "mp4")
//
// Usage — from URL:
//   LoopingVideoPlayer(url: someURL)
// ─────────────────────────────────────────────────────────────────────────────

struct LoopingVideoPlayer: UIViewRepresentable {

    private let url: URL?

    // Convenience init: Bundle resource name + extension
    init(videoName: String, videoExtension: String = "mp4") {
        self.url = Bundle.main.url(forResource: videoName, withExtension: videoExtension)
    }

    // Direct URL init
    init(url: URL) {
        self.url = url
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        if let url {
            context.coordinator.configure(url: url, in: view)
        }
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        if let url {
            context.coordinator.configure(url: url, in: uiView)
        }
    }

    // MARK: - Coordinator

    final class Coordinator {
        private var currentURL: URL?
        private var player: AVQueuePlayer?
        private var looper: AVPlayerLooper?

        func configure(url: URL, in view: PlayerContainerView) {
            guard currentURL != url else { return }
            currentURL = url

            let item = AVPlayerItem(url: url)
            let player = AVQueuePlayer()
            player.automaticallyWaitsToMinimizeStalling = false
            player.isMuted = true
            player.actionAtItemEnd = .none
            looper = AVPlayerLooper(player: player, templateItem: item)
            self.player = player

            view.playerLayer.player = player
            player.play()
        }
    }

    // MARK: - PlayerContainerView

    final class PlayerContainerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }

        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

        override init(frame: CGRect) {
            super.init(frame: frame)
            playerLayer.videoGravity = .resizeAspectFill
            backgroundColor = .black
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            playerLayer.videoGravity = .resizeAspectFill
            backgroundColor = .black
        }
    }
}
