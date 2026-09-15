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
            test_authServerMessage(),
            test_authServerMessageFallback(),
            test_pin_verification(),
            test_lockout_persistence(),
            test_ownerAlwaysHasSensitiveFinancialPermissions(),
            test_managerDoesNotReceiveSensitiveFinancialPermissionsByDefault(),
            test_managerCanBeGrantedSensitiveFinancialPermissions(),
            test_permissionPolicyFailClosed(),
            test_operationalPresetsDoNotGrantAdministration()
        ]
    }

    private static func test_ownerAlwaysHasSensitiveFinancialPermissions() -> TestResult {
        let name = #function
        let permissions = PermissionPolicyCore.permissionKeys(
            roleName: "Store Owner",
            explicitCSV: "dashboard.view",
            allKeys: testPermissionKeys
        )
        guard permissions.contains("profit_analytics.view"), permissions.contains("product_costs.view") else {
            return .failure(name, "Owner must retain sensitive financial access even with a legacy permission list.")
        }
        return .success(name)
    }

    private static func test_managerDoesNotReceiveSensitiveFinancialPermissionsByDefault() -> TestResult {
        let name = #function
        let permissions = PermissionPolicyCore.defaultPermissionKeys(roleName: "Store Manager", allKeys: testPermissionKeys)
        guard !permissions.contains("profit_analytics.view"), !permissions.contains("product_costs.view") else {
            return .failure(name, "Manager must require an explicit grant for profit and product-cost data.")
        }
        return .success(name)
    }

    private static func test_managerCanBeGrantedSensitiveFinancialPermissions() -> TestResult {
        let name = #function
        let permissions = PermissionPolicyCore.permissionKeys(
            roleName: "Store Manager",
            explicitCSV: "dashboard.view,profit_analytics.view,product_costs.view",
            allKeys: testPermissionKeys
        )
        guard permissions.contains("profit_analytics.view"), permissions.contains("product_costs.view") else {
            return .failure(name, "Explicit manager financial grants must be honored.")
        }
        return .success(name)
    }

    private static let testPermissionKeys: Set<String> = [
        "pos.sell", "discount.apply", "cash_drawer.open", "dashboard.view",
        "organization.manage", "profit_analytics.view", "product_costs.view",
        "staff_permissions.manage", "staff.manage", "payroll.manage", "settings.manage",
        "device.manage", "payments.manage", "inventory.adjust", "inventory.approve",
        "promotions.manage", "expenses.manage", "accounting.view", "inventory.receive"
    ]

    private static func test_permissionPolicyFailClosed() -> TestResult {
        for role in ["unknown", "assistant administrator", "cashier admin trainee", "owner assistant"] {
            guard PermissionPolicyCore.defaultPermissionKeys(roleName: role, allKeys: testPermissionKeys).isEmpty else {
                return .failure(#function, "Unknown or substring-matched role gained permissions: \(role)")
            }
        }
        for policy in ["none", "invalid.permission"] {
            guard PermissionPolicyCore.permissionKeys(roleName: "Cashier", explicitCSV: policy, allKeys: testPermissionKeys).isEmpty else {
                return .failure(#function, "Explicit deny/invalid policy fell back to cashier access")
            }
        }
        guard PermissionPolicyCore.defaultPermissionKeys(roleName: " Cashier ", allKeys: testPermissionKeys).contains("pos.sell") else {
            return .failure(#function, "Known exact alias no longer works")
        }
        return .success(#function)
    }

    private static func test_operationalPresetsDoNotGrantAdministration() -> TestResult {
        let sensitive: Set<String> = ["staff_permissions.manage", "staff.manage", "payroll.manage", "settings.manage", "device.manage", "payments.manage", "inventory.adjust", "inventory.approve", "promotions.manage", "expenses.manage", "accounting.view"]
        for role in ["Manager", "Supervisor", "Cashier"] {
            let keys = PermissionPolicyCore.defaultPermissionKeys(roleName: role, allKeys: testPermissionKeys)
            guard keys.isDisjoint(with: sensitive) else {
                return .failure(#function, "Operational role received implicit sensitive permission: \(role)")
            }
        }
        let cashier = PermissionPolicyCore.defaultPermissionKeys(roleName: "Cashier", allKeys: testPermissionKeys)
        guard !cashier.contains("inventory.receive"), !cashier.contains("discount.apply"), !cashier.contains("dashboard.view") else {
            return .failure(#function, "Cashier received broad stock, discount or KPI access")
        }
        return .success(#function)
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

    private static func test_authServerMessage() -> TestResult {
        let name = #function
        let data = Data(#"{"msg":"User already registered"}"#.utf8)
        let message = SecurityHelper.serverMessage(from: data, fallback: "Sign up failed")
        return message == "User already registered"
            ? .success(name)
            : .failure(name, "Expected Supabase message, got \(message)")
    }

    private static func test_authServerMessageFallback() -> TestResult {
        let name = #function
        let message = SecurityHelper.serverMessage(from: Data("not-json".utf8), fallback: "Sign up failed")
        return message == "Sign up failed"
            ? .success(name)
            : .failure(name, "Expected fallback message, got \(message)")
    }

    /// Lockout state must live in this-device-only Keychain storage rather than
    /// resettable UserDefaults.
    private static func test_lockout_persistence() -> TestResult {
        let name = #function
        let subject = "security-test-\(UUID().uuidString)"
        defer { KeychainManager.shared.clearPinAttempts(subjectId: subject) }
        _ = KeychainManager.shared.recordFailedPinAttempt(
            subjectId: subject,
            maxAttempts: 1,
            lockoutMinutes: 5
        )
        let restored = KeychainManager.shared.pinAttemptState(subjectId: subject)
        guard restored.attempts == 1, let lockedUntil = restored.lockedUntil, lockedUntil > Date() else {
            return .failure(name, "Keychain lockout state did not persist")
        }
        return .success(name)
    }
}
