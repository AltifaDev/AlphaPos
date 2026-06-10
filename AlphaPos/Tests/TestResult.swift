// TestResult.swift
// AlphaPos — Phase 4: Unit Testing Suite
//
// Shared result type used by every test suite.
// Kept in the Tests/ folder so it compiles together with all suites.

import Foundation

/// A lightweight pass / fail result returned by every individual test.
enum TestResult {
    case success(String)           // associated value: test name
    case failure(String, String)   // test name, failure message

    var testName: String {
        switch self {
        case .success(let name), .failure(let name, _): return name
        }
    }

    var isPassed: Bool {
        if case .success = self { return true }
        return false
    }
}
