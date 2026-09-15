import Foundation

struct StaffSubscriptionAccess: Decodable {
    let merchantID: UUID
    let reason: String

    enum CodingKeys: String, CodingKey {
        case merchantID = "merchant_id"
        case reason
    }

    var isAllowed: Bool { reason == "allowed" }

    func message(thai: Bool) -> (title: String, body: String) {
        // Staff devices should not expose billing, plan, or trial details.
        // Those details belong in the owner's subscription screen on the main iPad.
        return thai
            ? ("ร้านค้ายังไม่พร้อมใช้งาน", "กรุณาแจ้งเจ้าของร้านหรือผู้ดูแลระบบให้ตรวจสอบสิทธิ์การใช้งานบนเครื่องหลัก แล้วกดลองใหม่")
            : ("Store access unavailable", "Ask the store owner or administrator to check access on the main device, then try again.")
    }
}
