import Foundation
import Combine

@MainActor
public final class NetworkTimeService: ObservableObject {
    public static let shared = NetworkTimeService()

    @Published public private(set) var timeOffset: TimeInterval = 0.0
    @Published public private(set) var isSynced: Bool = false

    private init() {
        Task {
            await syncWithServer()
        }
    }

    /// Synchronizes client clock with the Supabase backend server using HTTP Date header.
    public func syncWithServer() async {
        let supabaseURLString = AppConfig.shared.supabaseURL.absoluteString
        guard let url = URL(string: supabaseURLString) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               let dateString = httpResponse.value(forHTTPHeaderField: "Date") {

                // HTTP Date format: "EEE, dd MMM yyyy HH:mm:ss zzz" (RFC 1123)
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = TimeZone(secondsFromGMT: 0)
                formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"

                if let serverDate = formatter.date(from: dateString) {
                    let offset = serverDate.timeIntervalSince(Date())
                    self.timeOffset = offset
                    self.isSynced = true
                    #if DEBUG
                    print("NetworkTimeService: Synced with server. Clock offset: \(offset) seconds.")
                    #endif
                }
            }
        } catch {
            #if DEBUG
            print("NetworkTimeService: Failed to sync time with server: \(error.localizedDescription)")
            #endif
        }
    }

    /// Returns the current server-aligned network Date.
    public var currentNetworkDate: Date {
        return Date().addingTimeInterval(timeOffset)
    }
}
