import Foundation

/// Lightweight floor descriptor stored as JSON in AppStorage.
/// Supports dynamic add/remove/rename floors without SwiftData migration.
struct FloorData: Codable, Identifiable, Equatable {
    var id: Int          // floor number (1-based, stable key for table.floor)
    var name: String     // display name, e.g. "Floor 1", "Rooftop"

    static let defaultFloors: [FloorData] = [
        FloorData(id: 1, name: "Floor 1"),
        FloorData(id: 2, name: "Floor 2"),
        FloorData(id: 3, name: "Floor 3")
    ]
}

// MARK: - AppStorage helper
extension Array where Element == FloorData {
    /// Encode to JSON string for AppStorage
    var jsonString: String {
        (try? String(data: JSONEncoder().encode(self), encoding: .utf8)) ?? "[]"
    }
}

extension String {
    /// Decode JSON string back to [FloorData]
    var asFloorDataArray: [FloorData] {
        guard let data = self.data(using: .utf8),
              let floors = try? JSONDecoder().decode([FloorData].self, from: data),
              !floors.isEmpty else {
            return FloorData.defaultFloors
        }
        return floors.sorted { $0.id < $1.id }
    }
}
