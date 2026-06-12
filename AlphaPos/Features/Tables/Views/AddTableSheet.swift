import SwiftUI
import SwiftData

struct AddTableSheet: View {
    @Binding var isPresented: Bool
    let modelContext: ModelContext
    
    @State private var tableNumber: String = ""
    @State private var capacity: Int = 2
    @State private var selectedStatus: String = "vacant"
    @State private var isRoundTable: Bool = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var selectedFloor: Int
    @State private var selectedZone: String = "Indoor"
    let defaultFloor: Int
    
    init(isPresented: Binding<Bool>, modelContext: ModelContext, defaultFloor: Int = 1) {
        self._isPresented = isPresented
        self.modelContext = modelContext
        self.defaultFloor = defaultFloor
        self._selectedFloor = State(initialValue: defaultFloor)
    }
    
    private let capacityRange = 1...20
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Text("Add New Table")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.textPrimary)
                        Spacer()
                        Button(action: { isPresented = false }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.textSecondary)
                        }
                    }
                    .padding()
                    .background(Color.appSurface)
                    .overlay(Divider().background(Color.appDivider), alignment: .bottom)
                    
                    // Form Content
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            // Table Number Section
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Table Number/Name", systemImage: "tablecells")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.textPrimary)
                                
                                TextField("e.g., 1, A, VIP-1", text: $tableNumber)
                                    .font(.subheadline)
                                    .foregroundColor(.textPrimary)
                                    .tint(.appAccent)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(Color.appSurfaceHigh)
                                    .cornerRadius(APRadius.md)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: APRadius.md)
                                            .stroke(Color.appBorderSubtle, lineWidth: 1)
                                    )
                                
                                Text("Give this table a unique identifier (number or label)")
                                    .font(.caption)
                                    .foregroundColor(.textTertiary)
                            }
                            
                            // Floor Section
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Floor Level", systemImage: "layers")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.textPrimary)
                                
                                Picker("Floor", selection: $selectedFloor) {
                                    Text("1st Floor").tag(1)
                                    Text("2nd Floor").tag(2)
                                    Text("3rd Floor").tag(3)
                                }
                                .pickerStyle(.segmented)
                                
                                Text("Assign which floor this table is located on")
                                    .font(.caption)
                                    .foregroundColor(.textTertiary)
                            }
                            
                            // Zone Section
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Zone", systemImage: "rectangle.3.group")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.textPrimary)
                                
                                Picker("Zone", selection: $selectedZone) {
                                    Text("Indoor").tag("Indoor")
                                    Text("Outdoor").tag("Outdoor")
                                    Text("Rooftop").tag("Rooftop")
                                }
                                .pickerStyle(.segmented)
                                
                                Text("Assign which zone this table belongs to")
                                    .font(.caption)
                                    .foregroundColor(.textTertiary)
                            }

                            // ✨ Table Shape Section
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Table Shape", systemImage: "square.on.circle")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.textPrimary)

                                HStack(spacing: 12) {
                                    ForEach([false, true], id: \.self) { round in
                                        Button(action: { isRoundTable = round }) {
                                            HStack(spacing: 8) {
                                                Image(systemName: round ? "circle" : "rectangle")
                                                    .font(.system(size: 18))
                                                Text(round ? "Round" : "Rectangle")
                                                    .font(.subheadline).fontWeight(.semibold)
                                            }
                                            .foregroundColor(isRoundTable == round ? .white : .textSecondary)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 10)
                                            .background(isRoundTable == round ? Color.appAccent : Color.appSurfaceHigh)
                                            .cornerRadius(APRadius.md)
                                            .overlay(RoundedRectangle(cornerRadius: APRadius.md)
                                                .stroke(isRoundTable == round ? Color.appAccent : Color.appBorderSubtle, lineWidth: 1))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }

                            // Capacity Section with Stepper
                            VStack(alignment: .leading, spacing: 16) {
                                Label("Number of Seats", systemImage: "chair.lounge.fill")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.textPrimary)
                                
                                HStack(spacing: 16) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Seats")
                                            .font(.caption)
                                            .foregroundColor(.textSecondary)
                                        
                                        HStack(spacing: 0) {
                                            Button(action: { if capacity > 1 { capacity -= 1 } }) {
                                                Image(systemName: "minus.circle.fill")
                                                    .font(.system(size: 24))
                                                    .foregroundColor(.appAccent)
                                                    .frame(width: 44, height: 44)
                                            }
                                            .buttonStyle(.plain)
                                            
                                            Text("\(capacity)")
                                                .font(.system(size: 32, weight: .bold))
                                                .foregroundColor(.textPrimary)
                                                .frame(maxWidth: .infinity)
                                            
                                            Button(action: { if capacity < 20 { capacity += 1 } }) {
                                                Image(systemName: "plus.circle.fill")
                                                    .font(.system(size: 24))
                                                    .foregroundColor(.appAccent)
                                                    .frame(width: 44, height: 44)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        .background(Color.appSurface)
                                        .cornerRadius(APRadius.md)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: APRadius.md)
                                                .stroke(Color.appBorderSubtle, lineWidth: 1)
                                        )
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Chair Layout")
                                            .font(.caption)
                                            .foregroundColor(.textSecondary)
                                        
                                        chairVisualization()
                                    }
                                }
                            }
                            
                            // Status Section
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Initial Status", systemImage: "tag.fill")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.textPrimary)
                                
                                HStack(spacing: 8) {
                                    ForEach(["vacant", "reserved", "cleaning"], id: \.self) { status in
                                        Button(action: { selectedStatus = status }) {
                                            Text(status.uppercased())
                                                .font(.caption2)
                                                .fontWeight(.bold)
                                                .foregroundColor(selectedStatus == status ? .white : .textSecondary)
                                                .padding(.vertical, 10)
                                                .padding(.horizontal, 12)
                                                .frame(maxWidth: .infinity)
                                                .background(selectedStatus == status ? statusColor(status) : Color.appSurfaceHigh)
                                                .cornerRadius(APRadius.sm)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: APRadius.sm)
                                                        .stroke(selectedStatus == status ? statusColor(status) : Color.appBorderSubtle, lineWidth: 1)
                                                )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            
                            // Summary Card
                            VStack(spacing: 12) {
                                Text("PREVIEW")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.appAccent)
                                    .tracking(1.0)
                                
                                // Preview table card
                                DynamicTableLayoutView(
                                    tableNumber: tableNumber.isEmpty ? "No." : tableNumber,
                                    capacity: capacity,
                                    isRound: isRoundTable,
                                    status: selectedStatus,
                                    isEditingLayout: false,
                                    isDragging: false,
                                    isSelected: false,
                                    statusColor: statusColor(selectedStatus)
                                )
                                .padding(.vertical, 16)
                            }
                            .padding()
                            .background(Color.appSurfaceHigh)
                            .cornerRadius(APRadius.md)
                        }
                        .padding()
                    }
                    
                    Spacer()
                    
                    // Action Buttons
                    VStack(spacing: 12) {
                        Button(action: addTable) {
                            Text("Create Table")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(APGradient.positive)
                                .cornerRadius(APRadius.md)
                        }
                        
                        Button(action: { isPresented = false }) {
                            Text("Cancel")
                                .font(.headline)
                                .foregroundColor(.textPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.appSurface)
                                .cornerRadius(APRadius.md)
                                .overlay(
                                    RoundedRectangle(cornerRadius: APRadius.md)
                                        .stroke(Color.appBorderSubtle, lineWidth: 1)
                                )
                        }
                    }
                    .padding()
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
        .apColorScheme()
    }
    
    @ViewBuilder
    private func chairVisualization() -> some View {
        let iconSize: CGFloat = 13
        let effectiveCount = max(capacity, 1)

        if isRoundTable {
            let diam: CGFloat = 36
            let radius = diam / 2 + 8

            ZStack {
                Circle()
                    .fill(Color.appSurface)
                    .overlay(Circle().stroke(Color.appBorderSubtle, lineWidth: 1))
                    .frame(width: diam, height: diam)

                ForEach(0..<effectiveCount, id: \.self) { idx in
                    let angle = 2 * .pi * CGFloat(idx) / CGFloat(effectiveCount) - .pi / 2
                    chairIcon(size: iconSize)
                        .rotationEffect(.radians(Double(angle + .pi / 2)))
                        .offset(x: radius * cos(angle), y: radius * sin(angle))
                }
            }
            .padding(8)
            .background(Color.appSurface)
            .cornerRadius(APRadius.sm)
            .overlay(
                RoundedRectangle(cornerRadius: APRadius.sm)
                    .stroke(Color.appBorderSubtle, lineWidth: 1)
            )
        } else {
            let leftCount  = capacity >= 3 ? 1 : 0
            let rightCount = capacity >= 4 ? 1 : 0
            let remaining  = capacity - leftCount - rightCount
            let topCount   = (remaining + 1) / 2
            let botCount   = remaining / 2
            let tableW = max(60, CGFloat(max(topCount, botCount)) * 20 + 16)

            VStack(spacing: 4) {
                if topCount > 0 {
                    HStack(spacing: 4) {
                        ForEach(0..<topCount, id: \.self) { _ in chairIcon(size: iconSize) }
                    }
                }
                HStack(spacing: 6) {
                    if leftCount > 0 { chairIcon(size: iconSize).rotationEffect(.degrees(90)) }
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.appSurface)
                        .overlay(RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.appBorderSubtle, lineWidth: 1))
                        .frame(width: tableW, height: 28)
                    if rightCount > 0 { chairIcon(size: iconSize).rotationEffect(.degrees(-90)) }
                }
                if botCount > 0 {
                    HStack(spacing: 4) {
                        ForEach(0..<botCount, id: \.self) { _ in chairIcon(size: iconSize).rotationEffect(.degrees(180)) }
                    }
                }
            }
            .padding(8)
            .background(Color.appSurface)
            .cornerRadius(APRadius.sm)
            .overlay(
                RoundedRectangle(cornerRadius: APRadius.sm)
                    .stroke(Color.appBorderSubtle, lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private func chairIcon(size: CGFloat = 11) -> some View {
        Image(systemName: "chair.lounge.fill")
            .font(.system(size: size))
            .foregroundColor(.appAccent)
    }
    
    private func statusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "vacant": return .appTeal
        case "occupied": return .appRose
        case "reserved": return .appAmber
        case "cleaning": return .appAccent
        default: return .textSecondary
        }
    }
    
    private func addTable() {
        // Validation
        if tableNumber.trimmingCharacters(in: .whitespaces).isEmpty {
            errorMessage = "Please enter a table number or name"
            showingError = true
            return
        }
        
        if capacity < 1 || capacity > 20 {
            errorMessage = "Capacity must be between 1 and 20 seats"
            showingError = true
            return
        }
        
        // Create and add table
        let newTable = RestaurantTable(
            tableNumber: tableNumber.trimmingCharacters(in: .whitespaces),
            capacity: capacity,
            isRound: isRoundTable,
            status: selectedStatus,
            qrCodeIdentifier: "table_\(UUID().uuidString)",
            positionX: Double.random(in: 20...300),
            positionY: Double.random(in: 20...300),
            floor: selectedFloor,
            zone: selectedZone
        )
        
        modelContext.insert(newTable)
        try? modelContext.save()
        
        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
        
        isPresented = false
    }
}

#Preview {
    let container = try! ModelContainer(for: RestaurantTable.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    return AddTableSheet(
        isPresented: .constant(true),
        modelContext: ModelContext(container)
    )
}
