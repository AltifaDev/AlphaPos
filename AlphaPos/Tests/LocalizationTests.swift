// LocalizationTests.swift
// AlphaPos — Phase 4: Unit Testing Suite
//
// Tests LocalizationManager translation interpolation and type safety.

import Foundation

enum LocalizationTests {
    
    static func runAll() -> [TestResult] {
        [
            test_translate_fallback(),
            test_t_noArgs(),
            test_t_intArg(),
            test_t_doubleArg(),
            test_t_stringArg(),
            test_t_mixedArgs(),
            test_t_missingArgs(),
            test_t_extraArgs()
        ]
    }
    
    private static func test_translate_fallback() -> TestResult {
        let name = #function
        let lm = LocalizationManager.shared
        
        // Save current language
        let originalLanguage = lm.currentLanguage
        lm.currentLanguage = .english
        
        let tabTables = lm.translate("tab_tables")
        if tabTables != "Tables" {
            lm.currentLanguage = originalLanguage
            return .failure(name, "Expected translation 'Tables', got '\(tabTables)'")
        }
        
        // Test fallback to English for non-existent translation in current language
        lm.currentLanguage = .thai
        let fallbackVal = lm.translate("cloud_engine_ver") // "Cloud Engine v2.1"
        if fallbackVal != "Cloud Engine v2.1" {
            lm.currentLanguage = originalLanguage
            return .failure(name, "Expected fallback translation 'Cloud Engine v2.1', got '\(fallbackVal)'")
        }
        
        // Restore language
        lm.currentLanguage = originalLanguage
        return .success(name)
    }
    
    private static func test_t_noArgs() -> TestResult {
        let name = #function
        let lm = LocalizationManager.shared
        let originalLanguage = lm.currentLanguage
        lm.currentLanguage = .english
        
        let val = lm.t("tab_pos")
        lm.currentLanguage = originalLanguage
        
        return val == "Orders" ? .success(name) : .failure(name, "Expected 'Orders', got '\(val)'")
    }
    
    private static func test_t_intArg() -> TestResult {
        let name = #function
        let lm = LocalizationManager.shared
        let originalLanguage = lm.currentLanguage
        lm.currentLanguage = .english
        
        // food_cost_template: "Food Cost: %@%%"
        let val = lm.t("food_cost_template", Int(35))
        lm.currentLanguage = originalLanguage
        
        return val == "Food Cost: 35%" ? .success(name) : .failure(name, "Expected 'Food Cost: 35%', got '\(val)'")
    }
    
    private static func test_t_doubleArg() -> TestResult {
        let name = #function
        let lm = LocalizationManager.shared
        let originalLanguage = lm.currentLanguage
        lm.currentLanguage = .english
        
        // available_balance_template: "Available: ฿%@"
        let val = lm.t("available_balance_template", Double(150.75))
        lm.currentLanguage = originalLanguage
        
        return val == "Available: ฿150.75" ? .success(name) : .failure(name, "Expected 'Available: ฿150.75', got '\(val)'")
    }
    
    private static func test_t_stringArg() -> TestResult {
        let name = #function
        let lm = LocalizationManager.shared
        let originalLanguage = lm.currentLanguage
        lm.currentLanguage = .english
        
        // table_number_template: "Table %@"
        let val = lm.t("table_number_template", "5")
        lm.currentLanguage = originalLanguage
        
        return val == "Table 5" ? .success(name) : .failure(name, "Expected 'Table 5', got '\(val)'")
    }
    
    private static func test_t_mixedArgs() -> TestResult {
        let name = #function
        let lm = LocalizationManager.shared
        let originalLanguage = lm.currentLanguage
        lm.currentLanguage = .english
        
        // loyalty_visits_spend_template: "%@ visits · ฿%@ spent"
        let val = lm.t("loyalty_visits_spend_template", Int(10), Double(2500.5))
        lm.currentLanguage = originalLanguage
        
        return val == "10 visits · ฿2500.5 spent" ? .success(name) : .failure(name, "Expected '10 visits · ฿2500.5 spent', got '\(val)'")
    }
    
    private static func test_t_missingArgs() -> TestResult {
        let name = #function
        let lm = LocalizationManager.shared
        let originalLanguage = lm.currentLanguage
        lm.currentLanguage = .english
        
        // loyalty_visits_spend_template: "%@ visits · ฿%@ spent"
        let val = lm.t("loyalty_visits_spend_template", Int(10))
        lm.currentLanguage = originalLanguage
        
        return val == "10 visits · ฿ spent" ? .success(name) : .failure(name, "Expected '10 visits · ฿ spent', got '\(val)'")
    }
    
    private static func test_t_extraArgs() -> TestResult {
        let name = #function
        let lm = LocalizationManager.shared
        let originalLanguage = lm.currentLanguage
        lm.currentLanguage = .english
        
        // table_number_template: "Table %@"
        let val = lm.t("table_number_template", "5", "extra", 123)
        lm.currentLanguage = originalLanguage
        
        return val == "Table 5" ? .success(name) : .failure(name, "Expected 'Table 5', got '\(val)'")
    }
}
