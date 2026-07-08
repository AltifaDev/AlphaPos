// SecurityTests.swift
// AlphaPos — Phase 4: Unit Testing Suite (Enhanced)
//
// Tests the SecurityHelper utility:
//   - SHA-256 output format (64 hex chars)
//   - Determinism: same input → same hash
//   - Constant-time comparison
//   - Salted hashing
//   - Empty string / known vectors
//   - verify() helper — positive and negative cases

import Foundation
import CryptoKit

enum SecurityTests {

    static func runAll() -> [TestResult] {
        [
            test_sha256_outputIs64HexChars(),
            test_sha256_isDeterministic(),
            test_sha256_differentInputsDifferentHashes(),
            test_sha256_emptyString(),
            test_sha256_knownVector(),
            test_constantTimeCompare_equal(),
            test_constantTimeCompare_unequal(),
            test_constantTimeCompare_differentLengths(),
            test_constantTimeCompare_emptyStrings(),
            test_sha256_withSalt(),
            test_verify_correctPasswordReturnsTrue(),
            test_verify_wrongPasswordReturnsFalse(),
            test_verify_hashMismatchReturnsFalse(),
            test_verify_withSalt(),
            test_pin_verification(),
            test_lockout_persistence()
        ]
    }

    /// Tests PIN verification matching algorithms (SHA256 hashed).
    private static func test_pin_verification() -> TestResult {
        let name = #function
        let enteredPin = "1234"
        let hashedPin = SecurityHelper.sha256(enteredPin)

        // Hashed check
        let isHashedMatch = SecurityHelper.verify(value: enteredPin, againstHash: hashedPin)

        guard isHashedMatch else {
            return .failure(name, "PIN validation failed")
        }
        return .success(name)
    }

    // MARK: - SHA-256 tests

    /// Output must be exactly 64 lowercase hex characters.
    private static func test_sha256_outputIs64HexChars() -> TestResult {
        let name = #function
        let hash = SecurityHelper.sha256("AlphaPos")
        guard hash.count == 64 else {
            return .failure(name, "Expected 64 chars, got \(hash.count)")
        }
        let allHex = hash.allSatisfy { "0123456789abcdef".contains($0) }
        return allHex
            ? .success(name)
            : .failure(name, "Non-hex characters found in hash: \(hash)")
    }

    /// The same input must always produce the same hash.
    private static func test_sha256_isDeterministic() -> TestResult {
        let name = #function
        let password = "SuperSecret123!"
        let h1 = SecurityHelper.sha256(password)
        let h2 = SecurityHelper.sha256(password)
        return h1 == h2
            ? .success(name)
            : .failure(name, "Hash not deterministic: '\(h1)' ≠ '\(h2)'")
    }

    /// Two different inputs must produce different hashes.
    private static func test_sha256_differentInputsDifferentHashes() -> TestResult {
        let name = #function
        let h1 = SecurityHelper.sha256("password")
        let h2 = SecurityHelper.sha256("Password")
        return h1 != h2
            ? .success(name)
            : .failure(name, "Collision detected")
    }

    /// The empty-string hash must equal the well-known SHA-256 value.
    private static func test_sha256_emptyString() -> TestResult {
        let name = #function
        let expected = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        let actual   = SecurityHelper.sha256("")
        return actual == expected
            ? .success(name)
            : .failure(name, "Empty-string hash mismatch\n  expected: \(expected)\n  actual  : \(actual)")
    }

    /// NIST known-answer test: SHA-256("abc").
    private static func test_sha256_knownVector() -> TestResult {
        let name = #function
        let expected = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        let actual   = SecurityHelper.sha256("abc")
        return actual == expected
            ? .success(name)
            : .failure(name, "Known-vector mismatch\n  expected: \(expected)\n  actual  : \(actual)")
    }

    // MARK: - Constant-time comparison tests

    private static func test_constantTimeCompare_equal() -> TestResult {
        let name = #function
        let result = SecurityHelper.constantTimeCompare("hello", "hello")
        return result
            ? .success(name)
            : .failure(name, "constantTimeCompare returned false for equal strings")
    }

    private static func test_constantTimeCompare_unequal() -> TestResult {
        let name = #function
        let result = SecurityHelper.constantTimeCompare("hello", "world")
        return !result
            ? .success(name)
            : .failure(name, "constantTimeCompare returned true for unequal strings")
    }

    private static func test_constantTimeCompare_differentLengths() -> TestResult {
        let name = #function
        let result = SecurityHelper.constantTimeCompare("short", "very long string here")
        return !result
            ? .success(name)
            : .failure(name, "constantTimeCompare returned true for different lengths")
    }

    private static func test_constantTimeCompare_emptyStrings() -> TestResult {
        let name = #function
        let result = SecurityHelper.constantTimeCompare("", "")
        return result
            ? .success(name)
            : .failure(name, "constantTimeCompare returned false for empty strings")
    }

    // MARK: - Salted hash tests

    private static func test_sha256_withSalt() -> TestResult {
        let name = #function
        let hash1 = SecurityHelper.sha256("password", salt: "salt1")
        let hash2 = SecurityHelper.sha256("password", salt: "salt2")
        let hash3 = SecurityHelper.sha256("password", salt: "salt1")

        guard hash1.count == 64 else {
            return .failure(name, "Salted hash length should be 64")
        }
        guard hash1 != hash2 else {
            return .failure(name, "Different salts should produce different hashes")
        }
        guard hash1 == hash3 else {
            return .failure(name, "Same salt + password should produce same hash")
        }
        return .success(name)
    }

    // MARK: - verify() tests

    /// verify() must return true when the value matches the stored hash.
    private static func test_verify_correctPasswordReturnsTrue() -> TestResult {
        let name   = #function
        let plain  = "manager2024"
        let stored = SecurityHelper.sha256(plain)
        return SecurityHelper.verify(value: plain, againstHash: stored)
            ? .success(name)
            : .failure(name, "verify() returned false for a correct password")
    }

    /// verify() must return false for a wrong password.
    private static func test_verify_wrongPasswordReturnsFalse() -> TestResult {
        let name   = #function
        let plain  = "manager2024"
        let stored = SecurityHelper.sha256(plain)
        return !SecurityHelper.verify(value: "wrong_password", againstHash: stored)
            ? .success(name)
            : .failure(name, "verify() returned true for an incorrect password")
    }

    /// verify() must return false when the hash string itself is corrupted.
    private static func test_verify_hashMismatchReturnsFalse() -> TestResult {
        let name        = #function
        let corruptHash = "0000000000000000000000000000000000000000000000000000000000000000"
        return !SecurityHelper.verify(value: "anyValue", againstHash: corruptHash)
            ? .success(name)
            : .failure(name, "verify() returned true against a zeroed-out hash")
    }

    /// verify() with salt must work correctly.
    private static func test_verify_withSalt() -> TestResult {
        let name = #function
        let password = "secret123"
        let salt = "myAppSalt"
        let hash = SecurityHelper.sha256(password, salt: salt)

        let verifyPass = SecurityHelper.verify(value: password, salt: salt, againstHash: hash)
        let verifyFail = SecurityHelper.verify(value: "wrong", salt: salt, againstHash: hash)

        guard verifyPass else {
            return .failure(name, "verify with salt failed for correct password")
        }
        guard !verifyFail else {
            return .failure(name, "verify with salt passed for wrong password")
        }
        return .success(name)
    }

    /// Verifies that saving a lockout timestamp persists across View resets (simulated via UserDefaults).
    private static func test_lockout_persistence() -> TestResult {
        let name = #function
        let testTime = Date().addingTimeInterval(300).timeIntervalSince1970
        UserDefaults.standard.set(testTime, forKey: "staff_lockout_until_time")

        let retrievedTime = UserDefaults.standard.double(forKey: "staff_lockout_until_time")
        guard retrievedTime == testTime else {
            UserDefaults.standard.removeObject(forKey: "staff_lockout_until_time")
            return .failure(name, "Persisted lockout time mismatch (lockout can be bypassed)")
        }

        UserDefaults.standard.removeObject(forKey: "staff_lockout_until_time")
        return .success(name)
    }
}
