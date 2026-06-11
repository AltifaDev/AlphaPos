import SwiftUI
import SwiftData
import Combine

// MARK: - Advanced Usage Examples for the New Table Management System

/// Example 1: Creating TableView with Custom Styling
/// Shows how to integrate TableView into your dashboard
struct DashboardIntegration: View {
    @State private var selectedTab: MainDashboardView.DashboardTab = .tables
    @State private var activeSession: TableSession?
    
    var body: some View {
        TabView(selection: $selectedTab) {
            TableView(selectedTab: $selectedTab, activeSession: $activeSession)
                .tabItem {
                    Label("Tables", systemImage: "square.grid.2x2")
                }
                .tag(MainDashboardView.DashboardTab.tables)
        }
    }
}

/// Example 2: Programmatically Creating Tables
/// Helper function to batch create tables
func createRestaurantLayout(modelContext: ModelContext) {
    let mockLayout: [(number: String, capacity: Int, x: Double, y: Double)] = [
        // Front section
        ("1", 2, 20, 20),
        ("2", 2, 150, 20),
        ("3", 4, 280, 20),
        ("4", 4, 410, 20),
        
        // Middle section
        ("5", 4, 20, 150),
        ("6", 6, 150, 150),
        ("7", 6, 280, 150),
        ("8", 8, 410, 150),
        
        // Back section  
        ("VIP 1", 10, 20, 280),
        ("VIP 2", 10, 150, 280),
        
        // Bar seating
        ("BAR 1", 1, 280, 280),
        ("BAR 2", 1, 310, 280),
        ("BAR 3", 1, 340, 280),
    ]
    
    for layout in mockLayout {
        let table = RestaurantTable(
            tableNumber: layout.number,
            capacity: layout.capacity,
            status: "vacant",
            qrCodeIdentifier: "table_\(layout.number)_hash",
            positionX: layout.x,
            positionY: layout.y
        )
        modelContext.insert(table)
    }
}

/// Example 3: Querying Tables by Various Criteria
extension RestaurantTable {
    /// Get all occupied tables for current service
    @MainActor
    static func activeSessionTables(modelContext: ModelContext) -> [RestaurantTable] {
        let descriptor = FetchDescriptor<RestaurantTable>(
            predicate: #Predicate { $0.status == "occupied" && !$0.isDeleted }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }
    
    /// Get available tables with minimum capacity
    @MainActor
    static func availableTablesForParty(size: Int, modelContext: ModelContext) -> [RestaurantTable] {
        let descriptor = FetchDescriptor<RestaurantTable>(
            predicate: #Predicate { 
                $0.status == "vacant" && $0.capacity >= size && !$0.isDeleted 
            },
            sortBy: [SortDescriptor(\RestaurantTable.capacity)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }
}

/// Example 4: Custom Table Card Component
struct CustomTableCard: View {
    let table: RestaurantTable
    let isSelected: Bool
    let isInEditMode: Bool
    
    var body: some View {
        VStack(spacing: 6) {
            // Status indicator
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                
                Spacer()
                
                Text("\(table.capacity)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.appSurfaceHigh)
                    .cornerRadius(3)
            }
            
            // Table name
            Text("T\(table.tableNumber)")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.textPrimary)
            
            // Status badge
            Text(table.status.prefix(3).uppercased())
                .font(.system(size: 8, weight: .heavy))
                .foregroundColor(.white)
                .padding(.vertical, 2)
                .padding(.horizontal, 4)
                .background(statusColor)
                .cornerRadius(2)
            
            if isInEditMode {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 8))
                    .foregroundColor(.appAccent)
            }
        }
        .padding(8)
        .background(isSelected ? Color.appSurfaceHigh : Color.appSurface)
        .cornerRadius(APRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: APRadius.md)
                .stroke(isSelected ? statusColor : Color.appBorderSubtle, lineWidth: isSelected ? 2 : 1)
        )
    }
    
    private var statusColor: Color {
        switch table.status.lowercased() {
        case "vacant": return .appTeal
        case "occupied": return .appRose
        case "reserved": return .appAmber
        case "cleaning": return .appAccent
        default: return .textSecondary
        }
    }
}

/// Example 5: Layout Analytics
struct TableLayoutAnalytics {
    let tables: [RestaurantTable]
    
    var occupancyRate: Double {
        guard tables.count > 0 else { return 0 }
        let occupied = tables.filter { $0.status == "occupied" }.count
        return Double(occupied) / Double(tables.count)
    }
    
    var totalCapacity: Int {
        tables.reduce(0) { $0 + $1.capacity }
    }
    
    var averageTableSize: Double {
        guard tables.count > 0 else { return 0 }
        return Double(totalCapacity) / Double(tables.count)
    }
    
    var statusBreakdown: [String: Int] {
        var breakdown: [String: Int] = [:]
        for table in tables {
            breakdown[table.status, default: 0] += 1
        }
        return breakdown
    }
    
    /// Estimate wait time based on current occupancy
    func estimatedWaitTime() -> String {
        let rate = occupancyRate
        if rate < 0.5 {
            return "No wait"
        } else if rate < 0.75 {
            return "10-15 min"
        } else if rate < 0.9 {
            return "20-30 min"
        } else {
            return "45+ min"
        }
    }
}

/// Example 6: Session Management Helper
struct TableSessionManager {
    static func openNewSession(for table: inout RestaurantTable, in modelContext: ModelContext) {
        let session = TableSession(
            sessionToken: UUID().uuidString,
            startedAt: Date(),
            isActive: true,
            table: table
        )
        table.sessions.append(session)
        table.status = "occupied"
        table.updatedAt = Date()
        try? modelContext.save()
    }
    
    static func closeSession(_ session: TableSession, for table: inout RestaurantTable, in modelContext: ModelContext) {
        // Mark preparing/ready orders and cooking items as served when checked out
        for order in session.orders {
            if order.status == "preparing" || order.status == "ready" {
                order.status = "served"
                order.isSynced = false
                order.updatedAt = Date()
                
                for item in order.items {
                    if item.status == "cooking" {
                        item.status = "served"
                        item.isSynced = false
                        item.updatedAt = Date()
                    }
                }
            }
        }
        session.isActive = false
        session.endedAt = Date()
        table.status = "cleaning"
        table.updatedAt = Date()
        try? modelContext.save()
    }
    
    static func moveToNextStatus(for table: inout RestaurantTable, in modelContext: ModelContext) {
        let nextStatus: String
        switch table.status.lowercased() {
        case "cleaning":
            nextStatus = "vacant"
        case "reserved":
            nextStatus = "vacant"
        default:
            nextStatus = "vacant"
        }
        table.status = nextStatus
        table.updatedAt = Date()
        try? modelContext.save()
    }
}

/// Example 7: Position Snapping and Grid Alignment
struct GridAlignmentHelper {
    static let gridSize: Double = 70.0 // Adjust based on canvas size
    
    static func snapToGrid(_ position: CGPoint) -> CGPoint {
        let snappedX = (position.x / gridSize).rounded() * gridSize
        let snappedY = (position.y / gridSize).rounded() * gridSize
        return CGPoint(x: snappedX, y: snappedY)
    }
    
    static func validatePosition(_ position: CGPoint, canvasSize: CGSize) -> CGPoint {
        let x = max(0, min(position.x, canvasSize.width - 120))
        let y = max(0, min(position.y, canvasSize.height - 120))
        return CGPoint(x: x, y: y)
    }
}

/// Example 8: Export Layout Configuration
struct LayoutExporter {
    static func exportAsJSON(tables: [RestaurantTable]) -> String? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        let layout = LayoutConfiguration(
            timestamp: Date(),
            tables: tables.map { table in
                TableLayout(
                    tableNumber: table.tableNumber,
                    capacity: table.capacity,
                    positionX: table.positionX,
                    positionY: table.positionY,
                    status: table.status
                )
            }
        )
        
        if let data = try? encoder.encode(layout),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        return nil
    }
}

struct LayoutConfiguration: Codable {
    let timestamp: Date
    let tables: [TableLayout]
}

struct TableLayout: Codable {
    let tableNumber: String
    let capacity: Int
    let positionX: Double
    let positionY: Double
    let status: String
}

/// Example 9: Search and Filter Tables
class TableSearchViewModel: ObservableObject {
    @Published var searchText: String = ""
    @Published var selectedStatus: String? = nil
    @Published var minCapacity: Int = 1
    
    let allTables: [RestaurantTable]
    
    init(allTables: [RestaurantTable]) {
        self.allTables = allTables
    }
    
    var filteredTables: [RestaurantTable] {
        var filtered = allTables
        
        // Search by table number
        if !searchText.isEmpty {
            filtered = filtered.filter { $0.tableNumber.localizedCaseInsensitiveContains(searchText) }
        }
        
        // Filter by status
        if let status = selectedStatus {
            filtered = filtered.filter { $0.status.lowercased() == status.lowercased() }
        }
        
        // Filter by capacity
        filtered = filtered.filter { $0.capacity >= minCapacity }
        
        return filtered.sorted { $0.tableNumber < $1.tableNumber }
    }
}

#Preview {
    CustomTableCard(
        table: RestaurantTable(
            tableNumber: "1",
            capacity: 4,
            status: "occupied",
            qrCodeIdentifier: "t1_hash"
        ),
        isSelected: false,
        isInEditMode: false
    )
}
