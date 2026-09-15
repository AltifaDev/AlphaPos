import Foundation
import UIKit

/// Helpers for manual delivery-platform order IDs (Grab / LINE MAN / etc.).
enum PlatformOrderNumber {
    static let maxLength = 80

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

    static func normalize(_ raw: String) -> String {
        var text = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{00a0}", with: " ")

        if let match = firstMatch(
            in: text,
            pattern: #"(?i)(?:order|ออเดอร์|หมายเลข)\s*[#:：-]?\s*([A-Z0-9][A-Z0-9\-_/]{2,})"#
        ) {
            text = match
        } else if text.contains(where: { $0.isWhitespace || $0.isNewline }) {
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

    static func stripKnownPrefix(_ value: String) -> String {
        let upper = value.uppercased()
        for prefix in knownPrefixes {
            if upper.hasPrefix(prefix.uppercased()) {
                return String(value.dropFirst(prefix.count))
            }
        }
        return value
    }

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

    static func rebrand(_ current: String, to brand: String?) -> String {
        guard prefix(for: brand) != nil else { return current }
        if current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return prefix(for: brand) ?? ""
        }
        return applyBrandPrefix(current, brand: brand)
    }

    static func applyBrandPrefixWhileEditing(_ raw: String, brand: String?) -> String {
        guard let prefix = prefix(for: brand) else {
            return String(raw.prefix(maxLength))
        }
        if raw.uppercased().hasPrefix(prefix.uppercased()) {
            return String(raw.prefix(maxLength))
        }
        return applyBrandPrefix(raw, brand: brand)
    }

    static func fromPasteboard(brand: String? = nil) -> String? {
        guard let raw = UIPasteboard.general.string,
              !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let value = applyBrandPrefix(raw, brand: brand)
        return value.isEmpty ? nil : value
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
