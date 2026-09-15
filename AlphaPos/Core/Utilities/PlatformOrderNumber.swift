import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// One source of truth for external sales channels that support their own menu
/// price and fee schedule. Keeping this list centralized prevents the POS,
/// product editor, sync and reports from silently disagreeing about a channel.
enum ExternalSalesChannel {
    static let all = ["GrabFood", "LINE MAN", "ShopeeFood", "Foodpanda", "Robinhood"]
}

/// Government co-payment is a program payment method, not a delivery channel.
enum GovernmentSupportProgram {
    static let thaiChuaThaiPlus = "ไทยช่วยไทย Plus"
    static let enabledSettingsKey = "payment_method_thai_chua_thai_plus_enabled"
    static let governmentRate = 0.60
    static let citizenRate = 0.40

    static func split(total: Double) -> (citizen: Double, government: Double) {
        let safeTotal = max(0, total)
        let citizen = (safeTotal * citizenRate * 100).rounded() / 100
        return (citizen, max(0, (safeTotal - citizen) * 100).rounded() / 100)
    }
}

/// Helpers for manual delivery-platform order IDs (Grab / LINE MAN / etc.).
enum PlatformOrderNumber {
    /// Max stored length matching DB `VARCHAR(80)`.
    static let maxLength = 80

    /// Brand → fixed order-number prefix (e.g. GrabFood → GP-).
    static func prefix(for brand: String?) -> String? {
        switch brand {
        case "GrabFood", "Grab": return "GP-"
        case "LINE MAN": return "LM-"
        case "ShopeeFood": return "SF-"
        case "Foodpanda": return "FP-"
        case "Robinhood": return "RH-"
        default: return nil
        }
    }

    private static let knownPrefixes = ["GP-", "GF-", "LM-", "SF-", "FP-", "RH-"]

    /// Normalize user/clipboard input into a compact platform order id.
    static func normalize(_ raw: String) -> String {
        var text = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{00a0}", with: " ")

        // Prefer an explicit "Order #xyz" / "ออเดอร์ xxx" style token if present.
        if let match = firstMatch(
            in: text,
            pattern: #"(?i)(?:order|ออเดอร์|หมายเลข)\s*[#:：-]?\s*([A-Z0-9][A-Z0-9\-_/]{2,})"#
        ) {
            text = match
        } else if text.contains(where: { $0.isWhitespace || $0.isNewline }) {
            // Clipboard often includes a whole notification sentence — take the
            // longest alphanumerics-with-dash token that looks like an ID.
            let tokens = text.split { $0.isWhitespace || $0.isNewline || ",.;".contains($0) }
                .map(String.init)
                .filter { token in
                    let t = token.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
                    guard t.count >= 4, t.count <= maxLength else { return false }
                    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_/"))
                    return t.unicodeScalars.allSatisfy { allowed.contains($0) }
                        && t.contains(where: { $0.isNumber })
                }
            if let best = tokens.max(by: { $0.count < $1.count }) {
                text = best.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            }
        }

        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if text.count > maxLength {
            text = String(text.prefix(maxLength))
        }
        return text
    }

    /// Strip a known brand prefix (case-insensitive), returning the bare id body.
    static func stripKnownPrefix(_ value: String) -> String {
        let upper = value.uppercased()
        for prefix in knownPrefixes {
            if upper.hasPrefix(prefix.uppercased()) {
                return String(value.dropFirst(prefix.count))
            }
        }
        return value
    }

    /// Ensure the value uses the selected brand prefix (`GP-xxx`, `LM-xxx`, …).
    /// - Empty input → brand prefix only (ready for typing), or empty if no brand.
    /// - Pasted bare numbers → `GP-12345`
    /// - Switching brand rewrites an existing known prefix.
    static func applyBrandPrefix(_ raw: String, brand: String?) -> String {
        let normalized = normalize(raw)
        guard let prefix = prefix(for: brand) else { return normalized }

        let body = stripKnownPrefix(normalized)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_/ "))

        if normalized.isEmpty && body.isEmpty {
            return prefix
        }

        var result = prefix + body
        if result.count > maxLength {
            result = String(result.prefix(maxLength))
        }
        return result
    }

    /// Prefill / rewrite field when the delivery brand changes.
    static func rebrand(_ current: String, to brand: String?) -> String {
        guard prefix(for: brand) != nil else { return current }
        if current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return prefix(for: brand) ?? ""
        }
        return applyBrandPrefix(current, brand: brand)
    }

    /// Soft apply while typing: keep text if it already has the correct prefix.
    static func applyBrandPrefixWhileEditing(_ raw: String, brand: String?) -> String {
        guard let prefix = prefix(for: brand) else {
            return String(raw.prefix(maxLength))
        }
        if raw.uppercased().hasPrefix(prefix.uppercased()) {
            return String(raw.prefix(maxLength))
        }
        return applyBrandPrefix(raw, brand: brand)
    }

    #if canImport(UIKit)
    /// Read clipboard, normalize, and apply brand prefix.
    static func fromPasteboard(brand: String? = nil) -> String? {
        guard let raw = UIPasteboard.general.string,
              !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let value = applyBrandPrefix(raw, brand: brand)
        return value.isEmpty ? nil : value
    }
    #endif

    /// Resolve the header identifier text for receipts (delivery number for delivery orders, queue number for others).
    static func receiptHeaderDisplay(orderType: String, platformOrderNumber: String?, queueNumber: String?) -> String? {
        let isDelivery = orderType.lowercased() == "delivery"
        let cleanPlatform = platformOrderNumber?.trimmingCharacters(in: .whitespacesAndNewlines)
        if isDelivery, let cleanPlatform, !cleanPlatform.isEmpty {
            return cleanPlatform
        }
        let cleanQueue = queueNumber?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let cleanQueue, !cleanQueue.isEmpty {
            return "คิวที่ #\(cleanQueue)"
        }
        return nil
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let capture = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[capture])
    }
}
