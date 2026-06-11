import Foundation
import Observation

struct InAppNotificationItem: Identifiable {
    let id = UUID()
    let title: String
    let body: String
    let type: InAppNotificationType
}

enum InAppNotificationType {
    case order
    case table
    case request
    case system
}

@Observable
final class InAppNotificationManager {
    static let shared = InAppNotificationManager()

    var currentItem: InAppNotificationItem?

    func show(title: String, body: String, type: InAppNotificationType = .system) {
        let item = InAppNotificationItem(title: title, body: body, type: type)
        Task { @MainActor in
            currentItem = item
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if currentItem?.id == item.id {
                currentItem = nil
            }
        }
    }

}