import Foundation
import CryptoKit

struct SecurityHelper {
    /// SHA256 hashing.
    /// NOTE: For production use, replace with bcrypt/argon2 with salt.
    /// SHA256 is too fast for password storage and vulnerable to rainbow tables.
    static func sha256(_ value: String) -> String {
        let inputData = Data(value.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// SHA256 hash with a salt.
    /// NOTE: For production use, replace with bcrypt/argon2.
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
    
    /// Verify a value against a SHA256 hash using constant-time comparison.
    static func verify(value: String, againstHash hash: String) -> Bool {
        return constantTimeCompare(sha256(value), hash)
    }
    
    /// Verify with salt using constant-time comparison.
    static func verify(value: String, salt: String, againstHash hash: String) -> Bool {
        return constantTimeCompare(sha256(value, salt: salt), hash)
    }
}
