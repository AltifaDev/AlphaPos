import Foundation

func testElapsedMinutes(startedAtStr: String) -> Int {
    var cleanedString = startedAtStr
    if let dotIndex = cleanedString.firstIndex(of: ".") {
        let suffix = cleanedString[dotIndex...]
        if let tzIndex = suffix.firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" }) {
            let start = cleanedString[..<dotIndex]
            let end = suffix[tzIndex...]
            cleanedString = String(start + end)
        }
    }
    
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    if let date = formatter.date(from: cleanedString) {
        print("SUCCESS parsed in elapsedMinutes: \(date)")
        return Int(Date().timeIntervalSince(date) / 60)
    } else {
        print("FAILED to parse in elapsedMinutes: '\(cleanedString)'")
        return 0
    }
}

let input = "2026-06-12 17:22:57.192928+00"
let result = testElapsedMinutes(startedAtStr: input)
print("Result: \(result)")
