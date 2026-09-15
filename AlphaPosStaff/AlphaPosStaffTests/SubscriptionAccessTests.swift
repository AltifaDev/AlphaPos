import Foundation
import Testing
@testable import AlphaPosStaff

@Suite("Subscription access")
struct SubscriptionAccessTests {
    @Test func onlyExplicitServerAllowanceGrantsAccess() throws {
        for reason in ["allowed", "trial_expired", "expired", "pending_payment", "plan_not_supported", "inactive", "invalid_subscription", "", "future_status"] {
            let value = StaffSubscriptionAccess(merchantID: UUID(), reason: reason)
            #expect(value.isAllowed == (reason == "allowed"))
        }
    }

    @Test func staffMessageDoesNotExposeBillingStatus() {
        let value = StaffSubscriptionAccess(merchantID: UUID(), reason: "pending_payment")
        #expect(value.message(thai: true).title == "ร้านค้ายังไม่พร้อมใช้งาน")
        #expect(value.message(thai: true).body.contains("เจ้าของร้าน"))
        #expect(value.message(thai: false).title == "Store access unavailable")
        #expect(!value.message(thai: false).body.localizedCaseInsensitiveContains("payment"))
    }

    @Test func serverContractRequiresTenantAndReason() throws {
        let decoder = JSONDecoder()
        let data = Data(#"{"merchant_id":"163350b0-056d-4d5e-b5d4-24e7aac5ab6d","reason":"allowed"}"#.utf8)
        #expect(try decoder.decode(StaffSubscriptionAccess.self, from: data).isAllowed)
        for json in [#"{"reason":"allowed"}"#, #"{"merchant_id":"163350b0-056d-4d5e-b5d4-24e7aac5ab6d"}"#, #"{"merchant_id":"invalid","reason":"allowed"}"#] {
            #expect(throws: (any Error).self) {
                try decoder.decode(StaffSubscriptionAccess.self, from: Data(json.utf8))
            }
        }
    }
}
