import Foundation

struct AppConfig {
    let supabaseURL: URL
    let supabaseAnonKey: String
    let defaultMerchantId: String
    let localServerURL: String
    let isProduction: Bool

    var supabaseRestURL: URL { URL(string: supabaseURL.absoluteString + "/rest/v1")! }
    var supabaseRealtimeURL: URL { URL(string: supabaseURL.absoluteString + "/realtime/v1")! }

    static let shared: AppConfig = {
        let defaultKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNkbXRraXhycWttd2Nwd29pc3JnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA4NDIxNjAsImV4cCI6MjA5NjQxODE2MH0.rjLwVE0ShXIFoT0k982XO_lVCQMsA4uTKMW1Su-NUws"
        let defaultMerchant = "163350b0-056d-4d5e-b5d4-24e7aac5ab6d"
        
        let envURL = ProcessInfo.processInfo.environment["SUPABASE_URL"]
        let finalEnvURL = (envURL == nil || envURL!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            ? "https://sdmtkixrqkmwcpwoisrg.supabase.co"
            : envURL!
            
        let envKey = ProcessInfo.processInfo.environment["SUPABASE_ANON_KEY"]
        let finalEnvKey = (envKey == nil || envKey!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            ? defaultKey
            : envKey!
            
        let envMerchant = ProcessInfo.processInfo.environment["DEFAULT_MERCHANT_ID"]
        let finalEnvMerchant = (envMerchant == nil || envMerchant!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            ? defaultMerchant
            : envMerchant!
            
        let envLocalURL = ProcessInfo.processInfo.environment["LOCAL_SERVER_URL"]
        let finalEnvLocalURL = (envLocalURL == nil || envLocalURL!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            ? "http://127.0.0.1:8080"
            : envLocalURL!

        guard let path = Bundle.main.path(forResource: "Config", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path) as? [String: Any]
        else {
            return AppConfig(
                supabaseURL: URL(string: finalEnvURL)!,
                supabaseAnonKey: finalEnvKey,
                defaultMerchantId: finalEnvMerchant,
                localServerURL: finalEnvLocalURL,
                isProduction: ProcessInfo.processInfo.environment["ALPHAPOS_ENV"] == "production"
            )
        }
        
        let plistURL = dict["SUPABASE_URL"] as? String
        let finalPlistURL = (plistURL == nil || plistURL!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            ? "https://sdmtkixrqkmwcpwoisrg.supabase.co"
            : plistURL!
            
        let plistKey = dict["SUPABASE_ANON_KEY"] as? String
        let finalPlistKey = (plistKey == nil || plistKey!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            ? defaultKey
            : plistKey!
            
        let plistMerchant = dict["DEFAULT_MERCHANT_ID"] as? String
        let finalPlistMerchant = (plistMerchant == nil || plistMerchant!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            ? defaultMerchant
            : plistMerchant!
            
        let plistLocalURL = dict["LOCAL_SERVER_URL"] as? String
        let finalPlistLocalURL = (plistLocalURL == nil || plistLocalURL!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            ? "http://127.0.0.1:8080"
            : plistLocalURL!

        return AppConfig(
            supabaseURL: URL(string: finalPlistURL)!,
            supabaseAnonKey: finalPlistKey,
            defaultMerchantId: finalPlistMerchant,
            localServerURL: finalPlistLocalURL,
            isProduction: dict["ALPHAPOS_ENV"] as? String == "production"
        )
    }()
}
