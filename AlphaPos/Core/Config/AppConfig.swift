import Foundation

struct AppConfig {
    let supabaseURL: URL
    let supabaseAnonKey: String
    let localServerURL: String
    let isProduction: Bool
    let turnstileSiteKey: String

    var supabaseRestURL: URL { URL(string: supabaseURL.absoluteString + "/rest/v1")! }
    var supabaseRealtimeURL: URL { URL(string: supabaseURL.absoluteString + "/realtime/v1")! }
    var edgeFunctionURL: URL { URL(string: supabaseURL.absoluteString + "/functions/v1")! }

    static func isInvalidSupabaseURL(_ value: String) -> Bool {
        guard let host = URL(string: value)?.host?.lowercased() else { return false }
        return host != "api.alphaposweb.com"
    }

    static func migrateSupabaseURLIfNeeded(plistSupabaseURL: String? = nil) {
        let key = "dynamic_supabase_url"
        guard let stored = UserDefaults.standard.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !stored.isEmpty,
              isInvalidSupabaseURL(stored) else {
            return
        }
        let fallback = plistSupabaseURL
            ?? plistValue("SUPABASE_URL", in: loadConfigPlist())
            ?? "https://api.alphaposweb.com"
        if let trimmed = nonEmpty(fallback) {
            UserDefaults.standard.set(trimmed, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    static let shared: AppConfig = {
        let env = ProcessInfo.processInfo.environment
        let plist = loadConfigPlist()
        let isProduction = plistValue("ALPHAPOS_ENV", in: plist) == "production"
            || env["ALPHAPOS_ENV"] == "production"

        let plistSupabaseURL = plistValue("SUPABASE_URL", in: plist) ?? env["SUPABASE_URL"]
        let plistLocalServerURL = plistValue("LOCAL_SERVER_URL", in: plist) ?? env["LOCAL_SERVER_URL"]

        migrateSupabaseURLIfNeeded(plistSupabaseURL: plistSupabaseURL)
        
        let supabaseURLString = requiredConfigValue(plistSupabaseURL, name: "SUPABASE_URL")
        
        let localServerURLString: String
        if let overriddenLocalURL = UserDefaults.standard.string(forKey: "dynamic_local_server_url"), !overriddenLocalURL.isEmpty {
            localServerURLString = overriddenLocalURL
        } else {
            localServerURLString = plistLocalServerURL ?? "https://sync.alphaposweb.com"
        }

        return AppConfig(
            supabaseURL: requiredURL(supabaseURLString, name: "SUPABASE_URL"),
            supabaseAnonKey: requiredConfigValue(
                plistValue("SUPABASE_ANON_KEY", in: plist) ?? env["SUPABASE_ANON_KEY"],
                name: "SUPABASE_ANON_KEY"
            ),
            localServerURL: localServerURLString,
            isProduction: isProduction,
            turnstileSiteKey: plistValue("TURNSTILE_SITE_KEY", in: plist) ?? env["TURNSTILE_SITE_KEY"] ?? ""
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
        guard let url = URL(string: value), let host = url.host else {
            fatalError("Invalid AlphaPos configuration URL for \(name): \(value)")
        }
        if name == "SUPABASE_URL" && (host == "supabase.co" || host.hasSuffix(".supabase.co")) {
            fatalError("AlphaPos requires the self-hosted Supabase VPS. Supabase Cloud URLs are not allowed.")
        }
        return url
    }
}
