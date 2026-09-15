import Foundation
import Testing
@testable import AlphaPosStaff

@Suite("Staff session and offline contracts", .serialized)
struct SessionAndOfflineContractTests {
    @Test func employeeIdentityUsesOneCanonicalKey() {
        StaffSessionContext.setEmployee(id: "ABCDEF", name: "Test Staff")
        #expect(StaffSessionContext.employeeId == "abcdef")
        #expect(UserDefaults.standard.string(forKey: "employee_id") == nil)
        StaffSessionContext.clearEmployee()
        #expect(StaffSessionContext.employeeId.isEmpty)
    }

    @Test func queuedOrderFailureStateSurvivesEncoding() throws {
        let order = QueuedOrder(
            orderNumber: "OFFLINE-1", tableNumber: "QUICK", total: 100,
            itemsPayload: [["id": UUID().uuidString, "name": "Tea", "quantity": 1, "price": 100]],
            retryCount: 5, lastError: "timeout", requiresManualRetry: true
        )
        let decoded = try JSONDecoder().decode(QueuedOrder.self, from: JSONEncoder().encode(order))
        #expect(decoded.requiresManualRetry)
        #expect(decoded.lastError == "timeout")
        #expect(decoded.id == order.id)
    }
}
