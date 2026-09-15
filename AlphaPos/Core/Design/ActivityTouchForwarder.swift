import SwiftUI
import UIKit

/// Forwards touch activity without claiming the hit — safe for idle timeout tracking.
/// Unlike `DragGesture(minimumDistance: 0)`, this does not cancel Buttons / toolbar taps.
struct ActivityTouchForwarder: UIViewRepresentable {
    let onTouch: () -> Void

    func makeUIView(context: Context) -> TouchForwardingView {
        let view = TouchForwardingView()
        view.onTouch = onTouch
        view.isUserInteractionEnabled = true
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: TouchForwardingView, context: Context) {
        uiView.onTouch = onTouch
    }
}

final class TouchForwardingView: UIView {
    var onTouch: (() -> Void)?
    private var lastForwardedAt: TimeInterval = 0

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // Observe the touch, then return nil so the real control underneath receives it.
        if event != nil {
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastForwardedAt >= 0.5 {
                lastForwardedAt = now
                DispatchQueue.main.async { [weak self] in
                    self?.onTouch?()
                }
            }
        }
        return nil
    }
}
