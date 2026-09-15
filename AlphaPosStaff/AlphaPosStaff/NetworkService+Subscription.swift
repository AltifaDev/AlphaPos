import Foundation

extension NetworkService {
    /// The server evaluates expiry using its own clock and the authenticated tenant.
    func fetchStaffSubscriptionAccess() async throws -> StaffSubscriptionAccess {
        let data = try await sendSupabaseRequest(
            method: "POST", endpoint: "rpc/get_staff_subscription_access", payload: [:]
        )
        let rows: [StaffSubscriptionAccess]
        do {
            rows = try JSONDecoder().decode([StaffSubscriptionAccess].self, from: data)
        } catch {
            throw NetworkError.invalidResponse
        }
        guard rows.count == 1 else { throw NetworkError.invalidResponse }
        return rows[0]
    }
}
