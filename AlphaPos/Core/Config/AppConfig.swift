import Foundation

struct AppConfig {
    let supabaseURL: URL
    let supabaseAnonKey: String
    let defaultMerchantId: String
    let defaultDeviceSecret: String
    let localServerURL: String
    let isProduction: Bool

    var supabaseRestURL: URL { URL(string: supabaseURL.absoluteString + "/rest/v1")! }
    var supabaseRealtimeURL: URL { URL(string: supabaseURL.absoluteString + "/realtime/v1")! }
    var edgeFunctionURL: URL { URL(string: supabaseURL.absoluteString + "/functions/v1")! }

    static let shared: AppConfig = {
        let env = ProcessInfo.processInfo.environment
        let plist = loadConfigPlist()
        let isProduction = plistValue("ALPHAPOS_ENV", in: plist) == "production"
            || env["ALPHAPOS_ENV"] == "production"

        let plistSupabaseURL = plistValue("SUPABASE_URL", in: plist) ?? env["SUPABASE_URL"]
        let plistLocalServerURL = plistValue("LOCAL_SERVER_URL", in: plist) ?? env["LOCAL_SERVER_URL"]
        
        let supabaseURLString: String
        if let overriddenURL = UserDefaults.standard.string(forKey: "dynamic_supabase_url"), !overriddenURL.isEmpty {
            supabaseURLString = overriddenURL
        } else {
            supabaseURLString = requiredConfigValue(plistSupabaseURL, name: "SUPABASE_URL")
        }
        
        let localServerURLString: String
        if let overriddenLocalURL = UserDefaults.standard.string(forKey: "dynamic_local_server_url"), !overriddenLocalURL.isEmpty {
            localServerURLString = overriddenLocalURL
        } else {
            localServerURLString = plistLocalServerURL ?? "https://alphapos.altifadev.workers.dev"
        }

        return AppConfig(
            supabaseURL: requiredURL(supabaseURLString, name: "SUPABASE_URL"),
            supabaseAnonKey: requiredConfigValue(
                plistValue("SUPABASE_ANON_KEY", in: plist) ?? env["SUPABASE_ANON_KEY"],
                name: "SUPABASE_ANON_KEY"
            ),
            defaultMerchantId: requiredConfigValue(
                plistValue("DEFAULT_MERCHANT_ID", in: plist) ?? env["DEFAULT_MERCHANT_ID"],
                name: "DEFAULT_MERCHANT_ID"
            ),
            defaultDeviceSecret: requiredConfigValue(
                plistValue("DEFAULT_DEVICE_SECRET", in: plist) ?? env["DEFAULT_DEVICE_SECRET"],
                name: "DEFAULT_DEVICE_SECRET"
            ),
            localServerURL: localServerURLString,
            isProduction: isProduction
        )
    }()

    private static func loadConfigPlist() -> [String: Any] {
        guard let path = Bundle.main.path(forResource: "Config", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path) as? [String: Any] else {
            return [:]
        }
        return dict
    }

    private static func plistValue(_ key: String, in plist: [String: Any]) -> String? {
        nonEmpty(plist[key] as? String)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              !trimmed.contains("your-") else {
            return nil
        }
        return trimmed
    }

    private static func requiredConfigValue(_ value: String?, name: String) -> String {
        guard let value = nonEmpty(value) else {
            fatalError("Missing required AlphaPos configuration value: \(name). Add it to Config.plist or the app environment.")
        }
        return value
    }

    private static func requiredURL(_ value: String, name: String) -> URL {
        guard let url = URL(string: value) else {
            fatalError("Invalid AlphaPos configuration URL for \(name): \(value)")
        }
        return url
    }
}
