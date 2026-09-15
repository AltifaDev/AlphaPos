import SwiftUI
import SwiftData

// MARK: - TableShapeOption
enum TableShapeOption: String, CaseIterable, Identifiable {
    case rectangle, square, circle, oval
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .rectangle: return "rectangle"
        case .square: return "square"
        case .circle: return "circle"
        case .oval: return "oval"
        }
    }
    var labelKey: String { "table_shape_\(rawValue)" }
}

struct AddTableSheet: View {
    @Binding var isPresented: Bool
    @EnvironmentObject private var lm: LocalizationManager
    let modelContext: ModelContext
    @Query(sort: \FloorData.sortOrder) private var allFloors: [FloorData]
    
    @State private var tableNumber: String = ""
    @State private var createsMultipleTables = false
    @State private var tableCount = 10
    @State private var startingNumber = 1
    @State private var padsTableNumber = true
    @State private var capacity: Int = 2
    @State private var selectedStatus: String = "vacant"
    @State private var selectedShape: TableShapeOption = .rectangle
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var selectedFloor: Int
    @State private var selectedZone: String = "Indoor"
    let defaultFloor: Int

    private var floors: [FloorData] {
        let branchKey = (BranchContext.shared.activeBranchIDString).lowercased()
        let candidates = allFloors
            .filter { $0.branchId.lowercased() == branchKey && $0.isActive && !$0.isDeleted }
            .sorted {
                if $0.floorNumber == $1.floorNumber, $0.isSynced != $1.isSynced {
                    return $0.isSynced
                }
                return $0.sortOrder == $1.sortOrder
                    ? $0.floorNumber < $1.floorNumber
                    : $0.sortOrder < $1.sortOrder
            }
        var seenFloorNumbers = Set<Int>()
        return candidates.filter { seenFloorNumbers.insert($0.floorNumber).inserted }
    }
    
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
                        Text("table_add_new_title".t)
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
                            Picker("", selection: $createsMultipleTables) {
                                Text(lm.languageCode == "th" ? "โต๊ะเดียว" : "Single table").tag(false)
                                Text(lm.languageCode == "th" ? "หลายโต๊ะ" : "Multiple tables").tag(true)
                            }
                            .pickerStyle(.segmented)

                            // Table Number Section
                            VStack(alignment: .leading, spacing: 8) {
                                Label(
                                    createsMultipleTables
                                        ? (lm.languageCode == "th" ? "คำนำหน้าชื่อโต๊ะ" : "Table name prefix")
                                        : "table_number_name_lbl".t,
                                    systemImage: "tablecells"
                                )
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.textPrimary)
                                
                                TextField("table_number_name_placeholder".t, text: $tableNumber)
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
                                
                                Text(
                                    createsMultipleTables
                                        ? (lm.languageCode == "th" ? "เช่น T-, โต๊ะ หรือ Table " : "For example: T-, Table, or Patio ")
                                        : "table_number_name_hint".t
                                )
                                    .font(.caption)
                                    .foregroundColor(.textTertiary)

                                if createsMultipleTables {
                                    HStack(spacing: 12) {
                                        Stepper(
                                            (lm.languageCode == "th" ? "จำนวน \(tableCount) โต๊ะ" : "\(tableCount) tables"),
                                            value: $tableCount,
                                            in: 2...80
                                        )
                                        Stepper(
                                            (lm.languageCode == "th" ? "เริ่มที่ \(startingNumber)" : "Start at \(startingNumber)"),
                                            value: $startingNumber,
                                            in: 0...999
                                        )
                                    }

                                    Toggle(
                                        lm.languageCode == "th" ? "แสดงเลข 2 หลัก (01, 02…)" : "Use two-digit numbers (01, 02…)",
                                        isOn: $padsTableNumber
                                    )
                                    .font(.caption)

                                    Text(generatedTableNames.prefix(4).joined(separator: ", ") + (tableCount > 4 ? "…" : ""))
                                        .font(.caption)
                                        .foregroundColor(.appAccent)
                                }
                            }
                            
                            // Floor Section
                            VStack(alignment: .leading, spacing: 8) {
                                Label("table_floor_level_lbl".t, systemImage: "layers")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.textPrimary)
                                
                                if floors.count <= 3 {
                                    Picker("Floor", selection: $selectedFloor) {
                                        ForEach(floors) { floor in
                                            Text(floor.name).tag(floor.id)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                } else {
                                    Picker("Floor", selection: $selectedFloor) {
                                        ForEach(floors) { floor in
                                            Text(floor.name).tag(floor.id)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.appSurfaceHigh)
                                    .cornerRadius(APRadius.md)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: APRadius.md)
                                            .stroke(Color.appBorderSubtle, lineWidth: 1)
                                    )
                                }
                                
                                Text("table_floor_level_hint".t)
                                    .font(.caption)
                                    .foregroundColor(.textTertiary)
                            }
                            
                            // Zone Section
                            VStack(alignment: .leading, spacing: 8) {
                                Label("table_zone_lbl".t, systemImage: "rectangle.3.group")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.textPrimary)
                                
                                Picker("Zone", selection: $selectedZone) {
                                    Text("table_zone_indoor".t).tag("Indoor")
                                    Text("table_zone_outdoor".t).tag("Outdoor")
                                    Text("table_zone_rooftop".t).tag("Rooftop")
                                }
                                .pickerStyle(.segmented)
                                
                                Text("table_zone_hint".t)
                                    .font(.caption)
                                    .foregroundColor(.textTertiary)
                            }

                            // ✨ Table Shape Section
                            VStack(alignment: .leading, spacing: 8) {
                                Label("table_shape_lbl".t, systemImage: "square.on.circle")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.textPrimary)

                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                    ForEach(TableShapeOption.allCases) { shape in
                                        Button(action: {
                                            selectedShape = shape
                                            APHaptic.trigger()
                                        }) {
                                            VStack(spacing: 6) {
                                                Image(systemName: shape.icon)
                                                    .font(.system(size: 28, weight: .medium))
                                                    .foregroundColor(selectedShape == shape ? .white : .appAccent)
                                                Text(shape.labelKey.t)
                                                    .font(.caption)
                                                    .fontWeight(.semibold)
                                                    .foregroundColor(selectedShape == shape ? .white : .textSecondary)
                                            }
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 14)
                                            .background(selectedShape == shape ? Color.appAccent : Color.appSurfaceHigh)
                                            .cornerRadius(APRadius.md)
                                            .overlay(RoundedRectangle(cornerRadius: APRadius.md)
                                                .stroke(selectedShape == shape ? Color.appAccent : Color.appBorderSubtle, lineWidth: 1))
                                            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: selectedShape)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }

                            // Capacity Section with Stepper
                            VStack(alignment: .leading, spacing: 16) {
                                Label("table_seats_lbl".t, systemImage: "chair.lounge.fill")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.textPrimary)
                                
                                HStack(spacing: 16) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("table_seats_sub".t)
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
                                        Text("table_chair_layout_lbl".t)
                                            .font(.caption)
                                            .foregroundColor(.textSecondary)
                                        
                                        chairVisualization()
                                    }
                                }
                            }
                            
                            // Status Section
                            VStack(alignment: .leading, spacing: 8) {
                                Label("table_initial_status_lbl".t, systemImage: "tag.fill")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.textPrimary)
                                
                                HStack(spacing: 8) {
                                    ForEach(["vacant", "reserved", "cleaning"], id: \.self) { status in
                                        Button(action: { selectedStatus = status }) {
                                            Text("table_status_\(status.lowercased())".t.uppercased())
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
                                Text("table_preview_lbl".t)
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.appAccent)
                                    .tracking(1.0)
                                
                                // Preview table card
                                DynamicTableLayoutView(
                                    tableNumber: tableNumber.isEmpty
                                        ? "No."
                                        : (createsMultipleTables ? (generatedTableNames.first ?? tableNumber) : tableNumber),
                                    capacity: capacity,
                                    isRound: selectedShape == .circle || selectedShape == .oval,
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
                            Text(
                                createsMultipleTables
                                    ? (lm.languageCode == "th" ? "สร้าง \(tableCount) โต๊ะ" : "Create \(tableCount) tables")
                                    : "table_create_btn".t
                            )
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(APGradient.positive)
                                .cornerRadius(APRadius.md)
                        }
                        
                        Button(action: { isPresented = false }) {
                            Text("cancel".t)
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
            .alert("error".t, isPresented: $showingError) {
                Button("ok_btn".t, role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .onAppear {
                if !floors.contains(where: { $0.id == selectedFloor }) {
                    selectedFloor = floors.first?.id ?? defaultFloor
                }
            }
        }
        .apColorScheme()
    }
    
    @ViewBuilder
    private func chairVisualization() -> some View {
        let iconSize: CGFloat = 13
        let effectiveCount = max(capacity, 1)

        if selectedShape == .circle || selectedShape == .oval {
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

    private var generatedTableNames: [String] {
        let prefix = tableNumber.trimmingCharacters(in: .newlines)
        return (startingNumber..<(startingNumber + tableCount)).map {
            prefix + (padsTableNumber ? String(format: "%02d", $0) : String($0))
        }
    }
    
    private func addTable() {
        // Validation
        let trimmedNumber = tableNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedNumber.isEmpty {
            errorMessage = "table_error_empty_number".t
            showingError = true
            return
        }

        let existingDescriptor = FetchDescriptor<RestaurantTable>(
            predicate: #Predicate<RestaurantTable> { !$0.isDeleted }
        )
        let existing = (try? modelContext.fetch(existingDescriptor)) ?? []
        let names = createsMultipleTables ? generatedTableNames : [trimmedNumber]
        let existingNames = Set(existing.map {
            $0.tableNumber.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        })
        if names.contains(where: { existingNames.contains($0.lowercased()) }) {
            errorMessage = "table_error_duplicate_number".t
            showingError = true
            return
        }
        
        // Table limit check
        if existing.count + names.count > 80 {
            let remaining = max(0, 80 - existing.count)
            errorMessage = lm.languageCode == "th"
                ? "สร้างได้อีกไม่เกิน \(remaining) โต๊ะ เนื่องจากระบบจำกัดไว้ที่ 80 โต๊ะ"
                : "Only \(remaining) more tables can be created because the limit is 80."
            showingError = true
            return
        }
        
        if capacity < 1 || capacity > 20 {
            errorMessage = "table_error_invalid_capacity".t
            showingError = true
            return
        }

        // Keep floor within the configured floor list
        let floorId = floors.contains(where: { $0.id == selectedFloor })
            ? selectedFloor
            : (floors.first?.id ?? defaultFloor)
        
        for (index, name) in names.enumerated() {
            modelContext.insert(RestaurantTable(
                tableNumber: name,
                capacity: capacity,
                tableShape: selectedShape.rawValue,
                status: selectedStatus,
                qrCodeIdentifier: "table_\(UUID().uuidString)",
                positionX: Double(100 + (index % 5) * 160),
                positionY: Double(100 + (index / 5) * 160),
                floor: floorId,
                floorId: floors.first(where: { $0.id == floorId })?.uuid,
                branchId: BranchContext.shared.activeBranchIDString,
                zone: selectedZone
            ))
        }
        modelContext.saveWithLogging(label: #function)
        
        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
        
        isPresented = false
    }
}

#Preview {
    let container = try! ModelContainer(for: RestaurantTable.self, FloorData.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    return AddTableSheet(
        isPresented: .constant(true),
        modelContext: ModelContext(container)
    )
}
