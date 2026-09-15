import Foundation

struct AppConfig {
    static var supabaseURL: URL {
        if let overriddenURL = UserDefaults.standard.string(forKey: "dynamic_supabase_url"),
           !overriddenURL.isEmpty,
           !isInvalidSupabaseURL(overriddenURL) {
            return requiredURL(overriddenURL, name: "SUPABASE_URL")
        }
        return requiredURL(requiredConfigValue("SUPABASE_URL"), name: "SUPABASE_URL")
    }

    static func isInvalidSupabaseURL(_ value: String) -> Bool {
        guard let host = URL(string: value)?.host?.lowercased() else { return false }
        return host != "api.alphaposweb.com"
    }

    static var supabaseAnonKey: String {
        requiredConfigValue("SUPABASE_ANON_KEY")
    }

    static var supabaseRestURL: URL {
        URL(string: supabaseURL.absoluteString + "/rest/v1")!
    }

    static var supabaseRealtimeURL: URL {
        URL(string: supabaseURL.absoluteString + "/realtime/v1")!
    }

    static var edgeFunctionURL: URL {
        URL(string: supabaseURL.absoluteString + "/functions/v1")!
    }

    private static func requiredConfigValue(_ key: String) -> String {
        guard let value = configValue(key) else {
            fatalError("Missing required AlphaPosStaff configuration value: \(key). Add it to Config.plist, Info.plist, or the app environment.")
        }
        return value
    }

    private static func configValue(_ key: String) -> String? {
        nonEmpty(configPlistValue(key))
            ?? nonEmpty(Bundle.main.infoDictionary?[key] as? String)
            ?? nonEmpty(ProcessInfo.processInfo.environment[key])
    }

    private static func configPlistValue(_ key: String) -> String? {
        guard let path = Bundle.main.path(forResource: "Config", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path) as? [String: Any] else {
            return nil
        }
        return dict[key] as? String
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              !trimmed.contains("your-") else {
            return nil
        }
        return trimmed
    }

    private static func requiredURL(_ value: String, name: String) -> URL {
        guard let url = URL(string: value), let host = url.host else {
            fatalError("Invalid AlphaPosStaff configuration URL for \(name): \(value)")
        }
        if name == "SUPABASE_URL" && (host == "supabase.co" || host.hasSuffix(".supabase.co")) {
            fatalError("AlphaPosStaff requires the self-hosted Supabase VPS. Supabase Cloud URLs are not allowed.")
        }
        return url
    }
}
