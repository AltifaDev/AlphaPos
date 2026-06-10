import SwiftUI
import UIKit

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )
        
        // Setup popover presentation controller for iPad
        if let popover = controller.popoverPresentationController {
            popover.sourceView = UIView() // Will present in center or from active anchor
            popover.permittedArrowDirections = []
        }
        
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
