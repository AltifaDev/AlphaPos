import Foundation

/// Canonical restaurant positions based on ISCO-08 food-service groups and
/// O*NET food preparation/service occupations, adapted to AlphaPos RBAC.
enum RestaurantRoleCatalog {
    struct Definition: Identifiable {
        let id: String
        let name: String
        let description: String
        let permissionRole: String
        let aliases: Set<String>
    }

    static let definitions: [Definition] = [
        .init(id: "manager", name: "Restaurant Manager", description: "Directs restaurant operations, staffing, service, inventory, and financial controls.", permissionRole: "manager", aliases: ["restaurant manager", "store manager", "branch manager", "manager", "ผู้จัดการร้าน", "ผู้จัดการสาขา", "ผู้จัดการ"]),
        .init(id: "supervisor", name: "Shift Supervisor", description: "Supervises a service shift and handles operational exceptions.", permissionRole: "supervisor", aliases: ["shift supervisor", "shift lead", "supervisor", "lead", "หัวหน้ากะ"]),
        .init(id: "cashier", name: "Cashier", description: "Operates the point of sale and handles customer payments.", permissionRole: "cashier", aliases: ["cashier", "แคชเชียร์"]),
        .init(id: "server", name: "Server", description: "Takes orders and provides table service to guests.", permissionRole: "waiter", aliases: ["server", "waiter", "waitress", "waitstaff", "service staff", "staff", "พนักงานเสิร์ฟ", "บริกร"]),
        .init(id: "host", name: "Host / Hostess", description: "Greets guests and manages seating and reservations.", permissionRole: "host", aliases: ["host", "hostess", "host / hostess", "reception", "พนักงานต้อนรับ"]),
        .init(id: "head-chef", name: "Head Chef", description: "Leads kitchen production, food quality, and kitchen workflow.", permissionRole: "kitchen", aliases: ["head chef", "executive chef", "chef", "หัวหน้าเชฟ", "เชฟ"]),
        .init(id: "cook", name: "Cook", description: "Prepares and cooks restaurant menu items.", permissionRole: "kitchen", aliases: ["cook", "line cook", "kitchen staff", "kitchen", "พ่อครัว", "แม่ครัว", "พนักงานครัว"]),
        .init(id: "bartender", name: "Bartender", description: "Prepares and serves alcoholic and non-alcoholic beverages.", permissionRole: "cashier", aliases: ["bartender", "บาร์เทนเดอร์"]),
        .init(id: "barista", name: "Barista", description: "Prepares and serves coffee and other café beverages.", permissionRole: "cashier", aliases: ["barista", "บาริสต้า"]),
        .init(id: "food-prep", name: "Food Preparation Worker", description: "Prepares ingredients and supports food production.", permissionRole: "kitchen", aliases: ["food preparation worker", "food prep", "prep cook", "พนักงานเตรียมอาหาร"]),
        .init(id: "busser", name: "Busser / Dining Attendant", description: "Clears and resets tables and supports dining-room service.", permissionRole: "waiter", aliases: ["busser", "dining attendant", "busser / dining attendant", "ผู้ช่วยพนักงานเสิร์ฟ"]),
        .init(id: "dishwasher", name: "Dishwasher", description: "Cleans cookware, tableware, and kitchen service equipment.", permissionRole: "kitchen", aliases: ["dishwasher", "พนักงานล้างจาน"])
    ]

    static func definition(for roleName: String) -> Definition? {
        let key = normalizedName(roleName)
        return definitions.first { $0.aliases.contains(key) }
    }

    static func canonicalName(for roleName: String) -> String {
        definition(for: roleName)?.name ?? roleName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func deduplicationKey(for roleName: String) -> String {
        definition(for: roleName)?.id ?? normalizedName(roleName)
    }

    static func sortIndex(for roleName: String) -> Int {
        guard let id = definition(for: roleName)?.id,
              let index = definitions.firstIndex(where: { $0.id == id }) else {
            return definitions.count
        }
        return index
    }

    private static func normalizedName(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
