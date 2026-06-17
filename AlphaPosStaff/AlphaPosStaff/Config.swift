import Foundation

struct AppConfig {
    static var supabaseURL: URL {
        requiredURL(requiredConfigValue("SUPABASE_URL"), name: "SUPABASE_URL")
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

    static var defaultMerchantId: String {
        requiredConfigValue("DEFAULT_MERCHANT_ID")
    }

    static var defaultDeviceSecret: String {
        requiredConfigValue("DEFAULT_DEVICE_SECRET")
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
        guard let url = URL(string: value) else {
            fatalError("Invalid AlphaPosStaff configuration URL for \(name): \(value)")
        }
        return url
    }
}
