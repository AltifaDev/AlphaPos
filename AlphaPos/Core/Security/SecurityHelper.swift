import Foundation
import CryptoKit

struct SecurityHelper {
    /// Number of PBKDF2-like iterations to slow down brute-force attacks.
    /// OWASP 2023 recommends 600,000 iterations for SHA256.
    private static let hashIterations = 600_000
    
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
            hash = digested.compactMap { String(format: "%02x", $0) }.joined()
        }
        return "iter:\(hashIterations):\(actualSalt):\(hash)"
    }
    
    /// Verifies a PIN against a stored hash string.
    static func verifyPIN(_ pin: String, against storedHash: String) -> Bool {
        // Support legacy SHA256-only format (no salt, no iterations)
        if !storedHash.hasPrefix("iter:") {
            let inputData = Data(pin.utf8)
            let hashed = SHA256.hash(data: inputData)
            let legacyHash = hashed.compactMap { String(format: "%02x", $0) }.joined()
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
            hash = digested.compactMap { String(format: "%02x", $0) }.joined()
        }
        return constantTimeCompare(hash, expectedHash)
    }
    
    /// SHA256 hashing (legacy, kept for backward compatibility).
    static func sha256(_ value: String) -> String {
        let inputData = Data(value.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    /// SHA256 hash with a salt (legacy).
    static func sha256(_ value: String, salt: String) -> String {
        return sha256(salt + value)
    }
    
    /// Constant-time comparison to prevent timing attacks.
    static func constantTimeCompare(_ a: String, _ b: String) -> Bool {
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
