import UIKit

/// Opens an app only. A successful result is never proof of payment.
@MainActor
enum ExternalAppLauncher {
    // Tung Ngern's public launch scheme has not been verified. Use Apple's
    // documented Shortcuts launcher instead of guessing a third-party scheme.
    // The device needs a shortcut named "เปิดถุงเงิน" with Open App → ถุงเงิน.
    // Success means Shortcuts opened, not that its action or a payment succeeded.
    static var tungNgernURL: URL {
        shortcutURL(named: "เปิดถุงเงิน")
    }

    static func shortcutURL(named name: String) -> URL {
        var components = URLComponents()
        components.scheme = "shortcuts"
        components.host = "run-shortcut"
        components.queryItems = [URLQueryItem(name: "name", value: name)]
        return components.url!
    }

    static func open(_ url: URL, completion: @escaping (Bool) -> Void) {
        let options: [UIApplication.OpenExternalURLOptionsKey: Any] =
            ["http", "https"].contains(url.scheme?.lowercased() ?? "")
            ? [.universalLinksOnly: true] : [:]
        UIApplication.shared.open(url, options: options) { opened in
            DispatchQueue.main.async { completion(opened) }
        }
    }
}
