import Foundation

struct AppConfig {
    static var supabaseURL: URL {
        let urlStr = Bundle.main.infoDictionary?["SUPABASE_URL"] as? String
            ?? ProcessInfo.processInfo.environment["SUPABASE_URL"]
            ?? ""
        let finalUrl = urlStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "https://sdmtkixrqkmwcpwoisrg.supabase.co"
            : urlStr
        return URL(string: finalUrl)!
    }

    static var supabaseAnonKey: String {
        let defaultKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNkbXRraXhycWttd2Nwd29pc3JnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA4NDIxNjAsImV4cCI6MjA5NjQxODE2MH0.rjLwVE0ShXIFoT0k982XO_lVCQMsA4uTKMW1Su-NUws"
        let key = Bundle.main.infoDictionary?["SUPABASE_ANON_KEY"] as? String
            ?? ProcessInfo.processInfo.environment["SUPABASE_ANON_KEY"]
            ?? ""
        return key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? defaultKey : key
    }

    static var supabaseRestURL: URL {
        URL(string: supabaseURL.absoluteString + "/rest/v1")!
    }

    static var supabaseRealtimeURL: URL {
        URL(string: supabaseURL.absoluteString + "/realtime/v1")!
    }

    static var defaultMerchantId: String {
        let defaultMerchant = "163350b0-056d-4d5e-b5d4-24e7aac5ab6d"
        let merchant = ProcessInfo.processInfo.environment["DEFAULT_MERCHANT_ID"] ?? ""
        return merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? defaultMerchant : merchant
    }
}
