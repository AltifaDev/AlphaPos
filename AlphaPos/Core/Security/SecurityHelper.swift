import Foundation
import CryptoKit

struct SecurityHelper {
    nonisolated private static let hexDigits = Array("0123456789abcdef".utf8)

    /// Produces the same lowercase hex as String(format:), without invoking the
    /// formatter for every byte on every key-stretching round.
    nonisolated private static func hexString<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 {
        var output = [UInt8]()
        output.reserveCapacity(64)
        for byte in digest {
            output.append(hexDigits[Int(byte >> 4)])
            output.append(hexDigits[Int(byte & 0x0f)])
        }
        return String(decoding: output, as: UTF8.self)
    }

    /// Iterations for PIN key-stretching.
    /// 4-digit PINs have only 10,000 possible values — 10,000 iterations adds
    /// meaningful resistance against offline brute-force while keeping verify < 5ms
    /// on iPhone/iPad (600K was causing ~300ms UI freeze on main thread).
    private static let hashIterations = 10_000
    
    /// Generates a cryptographically random salt string.
    static func generateSalt(length: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
    }
    
    /// Iterated SHA256 hashing (key stretching) with salt.
    /// Uses multiple rounds to slow down brute-force / rainbow table attacks.
    /// Format for storage: "iter:<n>:<salt_b64>:<hash_hex>"
    static func hashPIN(_ pin: String, salt: String? = nil) -> String {
        let actualSalt = salt ?? generateSalt()
        var hash = actualSalt + pin
        for _ in 0..<hashIterations {
            let inputData = Data(hash.utf8)
            let digested = SHA256.hash(data: inputData)
            hash = hexString(digested)
        }
        return "iter:\(hashIterations):\(actualSalt):\(hash)"
    }
    
    /// Verifies a PIN against a stored hash string.
    nonisolated static func verifyPIN(_ pin: String, against storedHash: String) -> Bool {
        // Support legacy SHA256-only format (no salt, no iterations)
        if !storedHash.hasPrefix("iter:") {
            let inputData = Data(pin.utf8)
            let hashed = SHA256.hash(data: inputData)
            let legacyHash = hexString(hashed)
            return constantTimeCompare(legacyHash, storedHash)
        }
        
        // New format: iter:<n>:<salt_b64>:<hash_hex>
        let parts = storedHash.split(separator: ":", maxSplits: 3, omittingEmptySubsequences: false)
        guard parts.count == 4,
              let iterations = Int(parts[1]) else { return false }
        let salt = String(parts[2])
        let expectedHash = String(parts[3])
        
        var hash = salt + pin
        for _ in 0..<iterations {
            let inputData = Data(hash.utf8)
            let digested = SHA256.hash(data: inputData)
            hash = hexString(digested)
        }
        return constantTimeCompare(hash, expectedHash)
    }
    
    /// SHA256 hashing (legacy, kept for backward compatibility).
    static func sha256(_ value: String) -> String {
        let inputData = Data(value.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hexString(hashed)
    }
    
    /// SHA256 hash with a salt (legacy).
    static func sha256(_ value: String, salt: String) -> String {
        return sha256(salt + value)
    }
    
    /// Constant-time comparison to prevent timing attacks.
    nonisolated static func constantTimeCompare(_ a: String, _ b: String) -> Bool {
        guard a.count == b.count else { return false }
        let aBytes = [UInt8](a.utf8)
        let bBytes = [UInt8](b.utf8)
        var result: UInt8 = 0
        for i in 0..<aBytes.count {
            result |= aBytes[i] ^ bBytes[i]
        }
        return result == 0
    }
    
    /// Verify a value against a SHA256 hash using constant-time comparison (legacy).
    static func verify(value: String, againstHash hash: String) -> Bool {
        return constantTimeCompare(sha256(value), hash)
    }
    
    /// Verify with salt using constant-time comparison (legacy).
    static func verify(value: String, salt: String, againstHash hash: String) -> Bool {
        return constantTimeCompare(sha256(value, salt: salt), hash)
    }
}
