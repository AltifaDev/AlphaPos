
import SwiftUI
import SwiftData

struct TableView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RestaurantTable.tableNumber) private var tables: [RestaurantTable]
    
    @Binding var selectedTab: MainDashboardView.DashboardTab
    @Binding var activeSession: TableSession?
    
    @State private var selectedTable: RestaurantTable?
    @State private var showingDetailSheet = false
    @State private var showingAddTableSheet = false
    @State private var isEditingLayout = false
    @State private var draggedTableId: UUID?
    @State private var dragTranslation: CGSize = .zero
    @State private var activeDraggingTableId: UUID? = nil
    @State private var selectedFloor: Int = 1
    @State private var zoomScale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @State private var activePanOffset: CGSize = .zero
    @State private var isMovementLocked: Bool = false
    @State private var gestureScale: CGFloat = 1.0
    @State private var focusTableId: UUID? = nil
    @State private var bounceTableId: UUID? = nil
    @State private var headerWidth: CGFloat = 0
    @ObservedObject private var syncEngine = SyncEngine.shared
    
    @AppStorage("logged_in_email") private var loggedInEmail = "owner@alphapos.com"
    @State private var isLayoutManagerAuthorized = false
    @State private var showingManagerPinSheet = false
    @State private var showingBatchQRSheet = false
    @State private var pendingAuthAction: AuthAction? = nil
    
    enum AuthAction {
        case toggleEditLayout(Bool)
        case addTable
        case resetTables
    }
    
    var body: some View {
        ZStack {
                Color.appBackground.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Responsive Header
                    Group {
                        if headerWidth == 0 || headerWidth < 960 {
                            compactHeader
                        } else {
                            wideHeader
                        }
                    }
                    .padding()
                    .background(Color.appSurface)
                    .background(
                        GeometryReader { geo in
                            Color.clear
                                .onAppear {
                                    headerWidth = geo.size.width
                                }
                                .onChange(of: geo.size.width) { _, newWidth in
                                    headerWidth = newWidth
                                }
                        }
                    )
                    .overlay(
                        Divider().background(Color.appDivider),
                        alignment: .bottom
                    )
                    
                    // Floor Plan Canvas with Floating Panel Overlaid
                    ZStack(alignment: .bottomTrailing) {
                        floorPlanCanvas
                        
                        floatingControlsPanel
                            .padding(20)
                        
                        if !syncEngine.activeRequests.isEmpty {
                            activeRequestsOverlay
                        }
                    }
                }
            }
            .navigationTitle("Table Management")
            .apNavBar()
            .sheet(item: $selectedTable) { table in
                TableDetailView(table: table, selectedTab: $selectedTab, posTableSession: $activeSession)
            }
            .sheet(isPresented: $showingAddTableSheet) {
                AddTableSheet(isPresented: $showingAddTableSheet, modelContext: modelContext, defaultFloor: selectedFloor)
            }
            .sheet(isPresented: $showingManagerPinSheet) {
                ManagerPINVerificationSheet(
                    isPresented: $showingManagerPinSheet,
                    onSuccess: {
                        if let action = pendingAuthAction {
                            performAuthAction(action)
                        }
                        pendingAuthAction = nil
                    },
                    onDismiss: {
                        pendingAuthAction = nil
                    }
                )
            }
            .sheet(isPresented: $showingBatchQRSheet) {
                BatchQRCodePrintView(tables: tables)
            }
    }
    
    @ViewBuilder
    private var floorPlanCanvas: some View {
        let floorTables = tables.filter { ($0.floor ?? 1) == selectedFloor && !$0.isDeleted }
        
        GeometryReader { viewport in
            ZStack(alignment: .topLeading) {

                // Large canvas content (grid + tables)
                ZStack(alignment: .topLeading) {
                    // Grid lines overlay on background
                    Canvas { context, size in
                        let gridSize: CGFloat = 20
                        let path = Path { path in
                            for x in stride(from: 0, to: 1500, by: gridSize) {
                                path.move(to: CGPoint(x: x, y: 0))
                                path.addLine(to: CGPoint(x: x, y: 1200))
                            }
                            for y in stride(from: 0, to: 1200, by: gridSize) {
                                path.move(to: CGPoint(x: 0, y: y))
                                path.addLine(to: CGPoint(x: 1500, y: y))
                            }
                        }
                        context.stroke(path, with: .color(Color.appDivider.opacity(0.12)), lineWidth: 0.6)
                    }
                    .frame(width: 1500, height: 1200)
                    .allowsHitTesting(false)
                    
                    // Render filtered tables
                    ForEach(floorTables) { table in
                        InteractiveTableCardWrapper(
                            table: table,
                            isEditingLayout: isEditingLayout,
                            activeDraggingTableId: activeDraggingTableId,
                            selectedTableId: selectedTable?.id,
                            dragTranslation: dragTranslation,
                            zoomScale: zoomScale,
                            isBouncing: bounceTableId == table.id,
                            onTap: {
                                if !isEditingLayout {
                                    let leader = table.joinedParent ?? table
                                    if let session = leader.sessions.first(where: { $0.isActive }) {
                                        activeSession = session
                                        selectedTab = .pos
                                        APHaptic.trigger()
                                    } else {
                                        // Auto-start vacant table session
                                        let newSession = TableSession(sessionToken: UUID().uuidString, startedAt: Date(), isActive: true, table: leader, guestCount: leader.capacity)
                                        modelContext.insert(newSession)
                                        leader.sessions.append(newSession)
                                        leader.status = "occupied"
                                        for child in leader.joinedChildren {
                                            child.status = "occupied"
                                        }
                                        leader.updatedAt = Date()
                                        for child in leader.joinedChildren {
                                            child.updatedAt = Date()
                                        }
                                        try? modelContext.save()
                                        
                                        activeSession = newSession
                                        selectedTab = .pos
                                        APHaptic.trigger()
                                    }
                                }
                            },
                            onLongPress: {
                                if !isEditingLayout {
                                    selectedTable = table
                                    showingDetailSheet = true
                                    APHaptic.trigger()
                                }
                            },
                            onDragChanged: { val in handleDragChanged(value: val, for: table) },
                            onDragEnded: { val in handleDragEnded(value: val, for: table) }
                        )
                    }
                }
                .frame(width: 1500, height: 1200)
                .background(Color.appSurface) // Unified workspace board background
                .scaleEffect(zoomScale * gestureScale, anchor: .topLeading)
                .offset(CGSize(width: panOffset.width + activePanOffset.width, height: panOffset.height + activePanOffset.height))
            }
            .frame(width: viewport.size.width, height: viewport.size.height, alignment: .topLeading)
            .background(Color.appSurface) // Matches canvas surface and creates a seamless infinite board look
            .contentShape(Rectangle()) // Confine touch gestures strictly to the visible viewport
            .onTapGesture {
                withAnimation {
                    selectedTable = nil
                }
            }
            .gesture(
                (!isMovementLocked && activeDraggingTableId == nil) ?
                DragGesture(minimumDistance: 8) // Keep minimum distance threshold to allow taps to pass through
                    .onChanged { value in
                        activePanOffset = value.translation
                    }
                    .onEnded { value in
                        panOffset.width += value.translation.width
                        panOffset.height += value.translation.height
                        activePanOffset = .zero
                    }
                : nil
            )
            .gesture(
                !isMovementLocked ?
                MagnificationGesture()
                    .onChanged { value in
                        gestureScale = value
                    }
                    .onEnded { value in
                        zoomScale = min(1.5, max(0.5, zoomScale * value))
                        gestureScale = 1.0
                    }
                : nil
            )
            .onChange(of: focusTableId) { _, id in
                guard let id = id,
                      let table = floorTables.first(where: { $0.id == id }) else { return }
                
                // Calculate precise middle of the table card
                let tableSize = getTableSize(capacity: table.capacity)
                let targetX = CGFloat(table.positionX) + 16 + tableSize.width / 2
                let targetY = CGFloat(table.positionY) + 16 + tableSize.height / 2
                
                let vw = viewport.size.width
                let vh = viewport.size.height
                
                guard vw > 10 && vh > 10 else { return }
                
                let centerX = vw / 2.0
                let centerY = vh / 2.0
                let targetZoom: CGFloat = 1.2
                
                let newPanOffset = CGSize(
                    width: centerX - (targetX * targetZoom),
                    height: centerY - (targetY * targetZoom)
                )
                

                
                // Smooth camera slide animation
                withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) {
                    zoomScale = targetZoom
                    panOffset = newPanOffset
                    gestureScale = 1.0
                    activePanOffset = .zero
                }
                
                // Trigger a short spring bounce/pop animation just as the camera arrives
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.45)) {
                        bounceTableId = id
                    }
                    
                    // Return to normal scale smoothly
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            if bounceTableId == id {
                                bounceTableId = nil
                            }
                        }
                    }
                }
                
                APHaptic.trigger()
                
                DispatchQueue.main.async {
                    focusTableId = nil
                }
            }
            .overlay(
                Group {
                    if floorTables.isEmpty {
                        EmptyCanvasOverlayView()
                    }
                }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
    
    private var floatingControlsPanel: some View {
        VStack(spacing: 12) {
            // Zoom Container
            VStack(spacing: 0) {
                // Zoom In
                Button(action: {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                        zoomScale = min(1.5, zoomScale + 0.1)
                    }
                }) {
                    Image(systemName: "plus.magnifyingglass")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(isMovementLocked ? .textTertiary : .textPrimary)
                        .frame(width: 44, height: 44)
                }
                .disabled(isMovementLocked)
                
                Divider()
                    .background(Color.appDivider)
                    .frame(width: 32)
                
                // Zoom scale Reset
                Button(action: {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                        zoomScale = 1.0
                        panOffset = .zero
                        activePanOffset = .zero
                    }
                }) {
                    Text("\(Int(zoomScale * 100))%")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(isMovementLocked ? .textTertiary : .appAccent)
                        .frame(width: 44, height: 40)
                }
                .disabled(isMovementLocked)
                
                Divider()
                    .background(Color.appDivider)
                    .frame(width: 32)
                
                // Zoom Out
                Button(action: {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                        zoomScale = max(0.5, zoomScale - 0.1)
                    }
                }) {
                    Image(systemName: "minus.magnifyingglass")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(isMovementLocked ? .textTertiary : .textPrimary)
                        .frame(width: 44, height: 44)
                }
                .disabled(isMovementLocked)
            }
            .background(Color.appSurface.opacity(0.88))
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.appBorderSubtle, lineWidth: 1)
            )
            
            // Action buttons
            VStack(spacing: 0) {
                // Add Table
                Button(action: { checkManagerPermission(for: .addTable) }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(APGradient.positive)
                        .clipShape(Circle())
                        .padding(4)
                }
                
                Divider()
                    .background(Color.appDivider)
                    .frame(width: 32)
                
                // Reset/Seed Button
                Button(action: { checkManagerPermission(for: .resetTables) }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.textSecondary)
                        .frame(width: 44, height: 44)
                }
            }
            .background(Color.appSurface.opacity(0.88))
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.appBorderSubtle, lineWidth: 1)
            )
        }
    }
    

    
    private func statusDot(color: Color, label: String, count: Int) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text("\(label): \(count)")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(.textSecondary)
        }
    }
    
    private func countTables(status: String) -> Int {
        tables.filter { ($0.floor ?? 1) == selectedFloor && $0.status.lowercased() == status.lowercased() && !$0.isDeleted }.count
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
    
    private func updateTablePosition(_ table: RestaurantTable, newPosition: CGPoint) {
        table.positionX = newPosition.x
        table.positionY = newPosition.y
        table.isSynced = false
        table.updatedAt = Date()
        try? modelContext.save()
        draggedTableId = nil
    }
    
    private func handleDragChanged(value: DragGesture.Value, for table: RestaurantTable) {
        if activeDraggingTableId != table.id {
            activeDraggingTableId = table.id
            draggedTableId = table.id
            APHaptic.trigger()
        }
        let tableSize = getTableSize(capacity: table.capacity)
        let posX = CGFloat(table.positionX)
        let posY = CGFloat(table.positionY)
        let newX = posX + value.translation.width / zoomScale
        let newY = posY + value.translation.height / zoomScale
        
        let minX: CGFloat = 16
        let maxX: CGFloat = 1500 - tableSize.width - 16
        let minY: CGFloat = 16
        let maxY: CGFloat = 1200 - tableSize.height - 16
        
        let clampedX = min(max(newX, minX), maxX)
        let clampedY = min(max(newY, minY), maxY)
        
        let dragW = (clampedX - posX) * zoomScale
        let dragH = (clampedY - posY) * zoomScale
        
        withAnimation(.interactiveSpring(response: 0.22, dampingFraction: 0.82, blendDuration: 0)) {
            dragTranslation = CGSize(width: dragW, height: dragH)
        }
    }
    
    private func handleDragEnded(value: DragGesture.Value, for table: RestaurantTable) {
        let tableSize = getTableSize(capacity: table.capacity)
        let posX = CGFloat(table.positionX)
        let posY = CGFloat(table.positionY)
        let newX = posX + value.translation.width / zoomScale
        let newY = posY + value.translation.height / zoomScale
        
        let minX: CGFloat = 16
        let maxX: CGFloat = 1500 - tableSize.width - 16
        let minY: CGFloat = 16
        let maxY: CGFloat = 1200 - tableSize.height - 16
        
        let finalPosition = CGPoint(
            x: min(max(newX, minX), maxX),
            y: min(max(newY, minY), maxY)
        )
        updateTablePosition(table, newPosition: finalPosition)
        
        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
            activeDraggingTableId = nil
            draggedTableId = nil
            dragTranslation = .zero
        }
        APHaptic.trigger()
    }
    
    private func seedSampleTables() {
        SampleDataSeeder.seedTables(modelContext: modelContext)
    }
    
    private func checkManagerPermission(for action: AuthAction) {
        let email = loggedInEmail.lowercased()
        let isAuthorizedRole = email.contains("owner") || email.contains("manager") || email.contains("admin")
        
        if isAuthorizedRole || isLayoutManagerAuthorized {
            performAuthAction(action)
        } else {
            pendingAuthAction = action
            showingManagerPinSheet = true
        }
    }
    
    private func performAuthAction(_ action: AuthAction) {
        switch action {
        case .toggleEditLayout(let newValue):
            isLayoutManagerAuthorized = true
            isEditingLayout = newValue
        case .addTable:
            isLayoutManagerAuthorized = true
            showingAddTableSheet = true
        case .resetTables:
            isLayoutManagerAuthorized = true
            seedSampleTables()
            Task {
                await SyncEngine.shared.syncAll(modelContext: modelContext)
            }
        }
    }
    
    private var editLayoutBinding: Binding<Bool> {
        Binding(
            get: { isEditingLayout },
            set: { newValue in
                if newValue {
                    checkManagerPermission(for: .toggleEditLayout(true))
                } else {
                    isEditingLayout = false
                    Task {
                        await SyncEngine.shared.syncAll(modelContext: modelContext)
                    }
                }
            }
        )
    }
    
    private func getTableSize(capacity: Int) -> CGSize {
        let leftCount = capacity >= 3 ? 1 : 0
        let rightCount = capacity >= 4 ? 1 : 0
        let remaining = capacity - leftCount - rightCount
        let topCount = (remaining + 1) / 2
        let bottomCount = remaining / 2
        
        let tableWidth = max(76, CGFloat(max(topCount, bottomCount)) * 40 + 20)
        let tableHeight: CGFloat = 70
        return CGSize(width: tableWidth, height: tableHeight)
    }
    
    // MARK: - Header Layout Components
    
    @ViewBuilder
    private var headerTitleAndStatus: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Table Management")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.textPrimary)
            
            // Compact Status Summary
            HStack(spacing: 8) {
                statusDot(color: .appTeal, label: "Vacant", count: countTables(status: "vacant"))
                statusDot(color: .appRose, label: "Occupied", count: countTables(status: "occupied"))
                statusDot(color: .appAmber, label: "Reserved", count: countTables(status: "reserved"))
                statusDot(color: .appAccent, label: "Cleaning", count: countTables(status: "cleaning"))
            }
        }
    }
    
    @ViewBuilder
    private var findTableButton: some View {
        let activeTables = tables.filter { !$0.isDeleted && ($0.floor ?? 1) == selectedFloor }
        if !activeTables.isEmpty {
            Menu {
                ForEach(activeTables) { table in
                    Button(action: {
                        let tableFloor = table.floor ?? 1
                        if tableFloor != selectedFloor {
                            selectedFloor = tableFloor
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                focusTableId = table.id
                            }
                        } else {
                            focusTableId = table.id
                        }
                    }) {
                        Text("Table \(table.tableNumber) (\(table.capacity) Seats)")
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(isMovementLocked ? .textSecondary.opacity(0.6) : .appAccent)
                    Text("Find Table")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(isMovementLocked ? .textSecondary.opacity(0.6) : .textPrimary)
                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundColor(isMovementLocked ? .textSecondary.opacity(0.4) : .textSecondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.appSurfaceHigh)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isMovementLocked ? Color.appBorderSubtle.opacity(0.5) : Color.appBorderSubtle, lineWidth: 1)
                )
                .opacity(isMovementLocked ? 0.5 : 1.0)
            }
            .disabled(isMovementLocked)
        }
    }
    
    @ViewBuilder
    private var floorPicker: some View {
        Picker("Floor", selection: $selectedFloor) {
            Text("1st Floor").tag(1)
            Text("2nd Floor").tag(2)
            Text("3rd Floor").tag(3)
        }
        .pickerStyle(.segmented)
        .frame(width: 280)
    }
    
    @ViewBuilder
    private var lockPanZoomButton: some View {
        Button(action: {
            isMovementLocked.toggle()
            APHaptic.trigger()
        }) {
            HStack(spacing: 6) {
                Image(systemName: isMovementLocked ? "lock.fill" : "lock.open.fill")
                    .foregroundColor(isMovementLocked ? .appRose : .textSecondary)
                Text(isMovementLocked ? "Locked" : "Lock Pan/Zoom")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isMovementLocked ? Color.appRose.opacity(0.1) : Color.appSurfaceHigh)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isMovementLocked ? Color.appRose.opacity(0.2) : Color.appBorderSubtle, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private var editLayoutSwitch: some View {
        HStack(spacing: 6) {
            Toggle("Edit Layout", isOn: editLayoutBinding)
                .toggleStyle(SwitchToggleStyle(tint: .appAccent))
                .labelsHidden()
            Text("Edit Layout")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.textSecondary)
        }
    }

    @ViewBuilder
    private var printQRCodesButton: some View {
        Button(action: {
            showingBatchQRSheet = true
            APHaptic.trigger()
        }) {
            HStack(spacing: 6) {
                Image(systemName: "qrcode")
                    .foregroundColor(.appAccent)
                Text("Print QR Codes")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.appSurfaceHigh)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.appBorderSubtle, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private var compactHeader: some View {
        VStack(spacing: 12) {
            HStack {
                headerTitleAndStatus
                Spacer()
                printQRCodesButton
                findTableButton
            }
            HStack {
                floorPicker
                Spacer()
                HStack(spacing: 16) {
                    lockPanZoomButton
                    editLayoutSwitch
                }
            }
        }
    }
    
    @ViewBuilder
    private var wideHeader: some View {
        HStack(spacing: 16) {
            headerTitleAndStatus
            Spacer()
            printQRCodesButton
            findTableButton
            floorPicker
            lockPanZoomButton
            editLayoutSwitch
        }
    }
    
    // MARK: - Active Service Requests Overlay
    
    @ViewBuilder
    private var activeRequestsOverlay: some View {
        HStack {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "bell.badge.fill")
                        .foregroundColor(.appAccent)
                    Text("Service Requests")
                        .font(.headline)
                        .foregroundColor(.textPrimary)
                }
                .padding(.bottom, 4)
                
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(syncEngine.activeRequests) { request in
                            serviceRequestRow(request)
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
            .padding()
            .background(Color.appSurface.opacity(0.95))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.appBorderSubtle, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
            .frame(width: 280)
            
            Spacer()
        }
        .padding(.top, 20)
        .padding(.leading, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    
    @ViewBuilder
    private func serviceRequestRow(_ request: ServiceRequest) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Table \(request.tableNumber)")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.textPrimary)
                Text(request.requestType)
                    .font(.caption)
                    .foregroundColor(.textSecondary)
            }
            Spacer()
            Button(action: {
                resolveRequest(request)
            }) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.appAccent)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(10)
        .background(Color.appSurfaceHigh)
        .cornerRadius(10)
    }
    
    private func resolveRequest(_ request: ServiceRequest) {
        Task {
            let success = try? await NetworkManager.shared.resolveServiceRequest(id: request.id)
            if success == true {
                await SyncEngine.shared.syncServiceRequests()
            }
        }
    }
}

// MARK: - Table Detail / Action View

struct TableDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var table: RestaurantTable
    @Environment(\.dismiss) private var dismiss
    
    @Binding var selectedTab: MainDashboardView.DashboardTab
    @Binding var posTableSession: TableSession?
    
    @Query(sort: \RestaurantTable.tableNumber) private var allTables: [RestaurantTable]
    
    @State private var dynamicQRUrl: String = ""
    @State private var showingQRPopover = false
    @State private var editingCapacity = false
    @State private var tempCapacity: String = ""
    
    @AppStorage("logged_in_email") private var loggedInEmail = "owner@alphapos.com"
    @State private var showingManagerPinSheet = false
    
    private func deleteTableWithAuth() {
        let email = loggedInEmail.lowercased()
        let isAuthorizedRole = email.contains("owner") || email.contains("manager") || email.contains("admin")
        
        if isAuthorizedRole {
            performDelete()
        } else {
            showingManagerPinSheet = true
        }
    }
    
    private func performDelete() {
        modelContext.delete(table)
        try? modelContext.save()
        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
        dismiss()
    }
    
    var activeSession: TableSession? {
        let leader = table.joinedParent ?? table
        return leader.sessions.first(where: { $0.isActive })
    }
    
    private func updateGroupStatus(_ newStatus: String) {
        let leader = table.joinedParent ?? table
        leader.status = newStatus
        leader.isSynced = false
        for child in leader.joinedChildren {
            child.status = newStatus
            child.isSynced = false
        }
        leader.updatedAt = Date()
        for child in leader.joinedChildren {
            child.updatedAt = Date()
        }
        
        if newStatus == "vacant" {
            // Close any active sessions
            if let activeSession = leader.sessions.first(where: { $0.isActive }) {
                activeSession.isActive = false
                activeSession.endedAt = Date()
                activeSession.isSynced = false
                activeSession.updatedAt = Date()
            }
            for child in leader.joinedChildren {
                if let activeSession = child.sessions.first(where: { $0.isActive }) {
                    activeSession.isActive = false
                    activeSession.endedAt = Date()
                    activeSession.isSynced = false
                    activeSession.updatedAt = Date()
                }
            }
        }
        
        try? modelContext.save()
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    HStack(alignment: .top, spacing: 0) {
                        
                        // LEFT PANEL: Visual Table Preview
                        VStack(spacing: 16) {
                            let leader = table.joinedParent ?? table
                            let activeSession = leader.sessions.first(where: { $0.isActive })
                            let itemCount = activeSession?.orders.reduce(0) { total, order in
                                total + order.items.reduce(0) { subtotal, item in subtotal + item.quantity }
                            } ?? 0
                            
                            DynamicTableLayoutView(
                                tableNumber: table.tableNumber,
                                capacity: table.capacity,
                                status: table.status,
                                isEditingLayout: false,
                                isDragging: false,
                                isSelected: false,
                                statusColor: statusColor(table.status),
                                itemCount: itemCount
                            )
                            .padding(16)
                            .frame(height: 140)
                            
                            Text("Table \(table.tableNumber)")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.textPrimary)
                            
                            HStack(spacing: 12) {
                                Label("Capacity:", systemImage: "chair.lounge.fill")
                                    .font(.subheadline)
                                    .foregroundColor(.textSecondary)
                                
                                if editingCapacity {
                                    HStack(spacing: 0) {
                                        Button(action: {
                                            if table.capacity > 1 {
                                                table.capacity -= 1
                                                table.isSynced = false
                                                table.updatedAt = Date()
                                                try? modelContext.save()
                                                Task {
                                                    await SyncEngine.shared.syncAll(modelContext: modelContext)
                                                }
                                            }
                                        }) {
                                            Image(systemName: "minus.circle.fill")
                                                .font(.system(size: 18))
                                                .foregroundColor(.appAccent)
                                        }
                                        
                                        Text("\(table.capacity)")
                                            .font(.headline)
                                            .foregroundColor(.textPrimary)
                                            .frame(width: 30)
                                        
                                        Button(action: {
                                            if table.capacity < 20 {
                                                table.capacity += 1
                                                table.isSynced = false
                                                table.updatedAt = Date()
                                                try? modelContext.save()
                                                Task {
                                                    await SyncEngine.shared.syncAll(modelContext: modelContext)
                                                }
                                            }
                                        }) {
                                            Image(systemName: "plus.circle.fill")
                                                .font(.system(size: 18))
                                                .foregroundColor(.appAccent)
                                        }
                                    }
                                    
                                    Button("Done") { editingCapacity = false }
                                        .font(.caption)
                                        .foregroundColor(.appAccent)
                                } else {
                                    Text("\(table.capacity) Seats")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.textPrimary)
                                    
                                    Button(action: { editingCapacity = true }) {
                                        Image(systemName: "pencil.circle.fill")
                                            .font(.system(size: 16))
                                            .foregroundColor(.appAccent)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 24)
                        .padding(.horizontal, 16)
                        .frame(width: 250)
                        
                        // VERTICAL DIVIDER
                        Divider()
                            .background(Color.appBorderSubtle)
                            .padding(.vertical, 16)
                        
                        // RIGHT PANEL: Actions & Grouping
                        VStack(spacing: 16) {
                            
                            // 1. Table Grouping Section
                            VStack(alignment: .leading, spacing: 8) {
                                Text("TABLE GROUPING")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.appAccent)
                                    .tracking(1.0)
                                
                                if let parent = table.joinedParent {
                                    HStack {
                                        Label("Combined with Table \(parent.tableNumber)", systemImage: "link")
                                            .font(.subheadline)
                                            .foregroundColor(.textPrimary)
                                        Spacer()
                                        Button(action: {
                                            table.joinedParent = nil
                                            table.isSynced = false
                                            table.status = "vacant"
                                            table.updatedAt = Date()
                                            try? modelContext.save()
                                            Task {
                                                await SyncEngine.shared.syncAll(modelContext: modelContext)
                                            }
                                        }) {
                                            Text("Split")
                                                .font(.caption)
                                                .fontWeight(.bold)
                                                .foregroundColor(.appRose)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(Color.appRose.opacity(0.12))
                                                .cornerRadius(8)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                    .padding(8)
                                    .background(Color.appSurfaceHigh)
                                    .cornerRadius(APRadius.md)
                                } else {
                                    VStack(alignment: .leading, spacing: 6) {
                                        if !table.joinedChildren.isEmpty {
                                            Text("Combined Group: Table \(table.tableNumber) + " + table.joinedChildren.map { "T\($0.tableNumber)" }.joined(separator: ", "))
                                                .font(.caption)
                                                .foregroundColor(.textPrimary)
                                            
                                            ForEach(table.joinedChildren) { child in
                                                HStack {
                                                    Label("Table \(child.tableNumber)", systemImage: "link")
                                                        .font(.caption)
                                                        .foregroundColor(.textSecondary)
                                                    Spacer()
                                                    Button("Split") {
                                                        child.joinedParent = nil
                                                        child.status = "vacant"
                                                        child.isSynced = false
                                                        child.updatedAt = Date()
                                                        try? modelContext.save()
                                                        Task {
                                                            await SyncEngine.shared.syncAll(modelContext: modelContext)
                                                        }
                                                    }
                                                    .font(.caption)
                                                    .foregroundColor(.appRose)
                                                }
                                            }
                                            Divider().background(Color.appDivider).padding(.vertical, 2)
                                        }
                                        
                                        let floorTables = allTables.filter { ($0.floor ?? 1) == (table.floor ?? 1) && !$0.isDeleted && $0.id != table.id }
                                        let availableToJoin = floorTables.filter { $0.joinedParent == nil && $0.joinedChildren.isEmpty && $0.status == "vacant" }
                                        
                                        if !availableToJoin.isEmpty {
                                            Menu {
                                                ForEach(availableToJoin) { targetTable in
                                                    Button(action: {
                                                        targetTable.joinedParent = table
                                                        targetTable.status = table.status
                                                        targetTable.isSynced = false
                                                        targetTable.updatedAt = Date()
                                                        try? modelContext.save()
                                                        Task {
                                                            await SyncEngine.shared.syncAll(modelContext: modelContext)
                                                        }
                                                    }) {
                                                        Text("Table \(targetTable.tableNumber) (\(targetTable.capacity) Seats)")
                                                    }
                                                }
                                            } label: {
                                                HStack {
                                                    Image(systemName: "plus.circle")
                                                    Text("Combine with Table...")
                                                    Spacer()
                                                    Image(systemName: "chevron.down").font(.caption)
                                                }
                                                .font(.subheadline)
                                                .foregroundColor(.appAccent)
                                                .padding(10)
                                                .background(Color.appSurfaceHigh)
                                                .cornerRadius(APRadius.md)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: APRadius.md)
                                                        .stroke(Color.appBorderSubtle, lineWidth: 1)
                                                )
                                            }
                                        } else {
                                            Text("No other vacant tables to combine with.")
                                                .font(.caption2)
                                                .foregroundColor(.textTertiary)
                                                .padding(.vertical, 2)
                                        }
                                    }
                                }
                            }
                            
                            Divider().background(Color.appDivider).padding(.vertical, 2)
                            
                            // 2. Active Session / Status Actions Panel
                            VStack(alignment: .leading, spacing: 8) {
                                if let session = activeSession {
                                    Text("ACTIVE DINING SESSION")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundColor(.appAccent)
                                        .tracking(1.0)
                                    
                                    HStack(spacing: 12) {
                                        Label("Started At:", systemImage: "clock")
                                            .font(.subheadline)
                                            .foregroundColor(.textSecondary)
                                        Spacer()
                                        Text(session.startedAt, style: .time)
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.textPrimary)
                                    }
                                    .padding(8)
                                    .background(Color.appSurfaceHigh)
                                    .cornerRadius(APRadius.sm)
                                    
                                    // QR Code Link Row
                                    HStack(spacing: 8) {
                                        Text("https://alphapos.altifadev.workers.dev/?table=\(table.tableNumber)&token=\(session.sessionToken.prefix(8))")
                                            .font(.system(.caption2, design: .monospaced))
                                            .foregroundColor(.appAccent)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                            .padding(8)
                                            .background(Color.appSurfaceHigh)
                                            .cornerRadius(APRadius.sm)
                                        
                                        Button(action: {
                                            dynamicQRUrl = "https://alphapos.altifadev.workers.dev/?table=\(table.tableNumber)&token=\(session.sessionToken)"
                                            showingQRPopover = true
                                        }) {
                                            Image(systemName: "qrcode")
                                                .font(.subheadline)
                                                .padding(8)
                                                .background(Color.appAccent)
                                                .foregroundColor(.white)
                                                .cornerRadius(APRadius.sm)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                    
                                    // Session Action Buttons (Placed Side-by-Side to Fit Height)
                                    HStack(spacing: 12) {
                                        Button(action: {
                                            posTableSession = session
                                            selectedTab = .pos
                                            dismiss()
                                        }) {
                                            Text("Place Order")
                                                .frame(maxWidth: .infinity)
                                        }
                                        .apGradientButton(gradient: APGradient.accent, shadow: APShadow.glow)
                                        
                                        Button(action: {
                                            let tableNum = table.tableNumber
                                            Task {
                                                _ = try? await NetworkManager.shared.closeTableSession(tableNumber: tableNum)
                                            }
                                            
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
                                            updateGroupStatus("cleaning")
                                            dismiss()
                                        }) {
                                            Text("Check Out")
                                                .frame(maxWidth: .infinity)
                                        }
                                        .apGradientButton(gradient: APGradient.destructive, shadow: APShadow.destructiveGlow)
                                    }
                                    .padding(.top, 4)
                                } else {
                                    Text("TABLE ACTIONS")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundColor(.appAccent)
                                        .tracking(1.0)
                                    
                                    VStack(spacing: 10) {
                                        Button(action: startNewSession) {
                                            Text("Start Session")
                                                .frame(maxWidth: .infinity)
                                        }
                                        .apGradientButton(gradient: APGradient.positive, shadow: APShadow.positiveGlow)
                                        
                                        HStack(spacing: 12) {
                                            Button(action: {
                                                updateGroupStatus("reserved")
                                                Task {
                                                    await SyncEngine.shared.syncAll(modelContext: modelContext)
                                                }
                                                dismiss()
                                            }) {
                                                Text("Reserve")
                                                    .font(.headline)
                                                    .foregroundColor(.textPrimary)
                                                    .frame(maxWidth: .infinity)
                                                    .padding(.vertical, 12)
                                                    .background(Color.appSurfaceHigh)
                                                    .cornerRadius(APRadius.md)
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: APRadius.md)
                                                            .stroke(Color.appBorderSubtle, lineWidth: 1)
                                                    )
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                            
                                            Button(action: {
                                                updateGroupStatus("vacant")
                                                Task {
                                                    await SyncEngine.shared.syncAll(modelContext: modelContext)
                                                }
                                                dismiss()
                                            }) {
                                                Text("Vacant")
                                                    .font(.headline)
                                                    .foregroundColor(.textPrimary)
                                                    .frame(maxWidth: .infinity)
                                                    .padding(.vertical, 12)
                                                    .background(Color.appSurfaceHigh)
                                                    .cornerRadius(APRadius.md)
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: APRadius.md)
                                                            .stroke(Color.appBorderSubtle, lineWidth: 1)
                                                    )
                                            }
                                        }
                                        
                                        Button(action: {
                                            deleteTableWithAuth()
                                        }) {
                                            HStack {
                                                Image(systemName: "trash.fill")
                                                Text("Delete Table")
                                            }
                                            .font(.headline)
                                            .foregroundColor(.white)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12)
                                            .background(Color.appRose)
                                            .cornerRadius(APRadius.md)
                                            .shadow(color: Color.appRose.opacity(0.3), radius: 6, x: 0, y: 3)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                        .padding(.top, 8)
                                    }
                                }
                            }
                        }
                        .padding(24)
                        .frame(maxWidth: .infinity)
                    }
                    .background(Color.appSurface)
                    .cornerRadius(APRadius.lg)
                    .overlay(
                        RoundedRectangle(cornerRadius: APRadius.lg)
                            .stroke(Color.appBorderSubtle, lineWidth: 1)
                    )
                    .padding(24)
                }
            }
            .navigationTitle("Table Details")
            .apNavBar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundColor(.textPrimary)
                }
            }
            .alert("Dynamic QR Code Simulation", isPresented: $showingQRPopover) {
                Button("Done", role: .cancel) { }
            } message: {
                Text("This URL allows customers seated at Table \(table.tableNumber) to order direct-to-kitchen:\n\n\(dynamicQRUrl)\n\n(Only valid while this session remains open.)")
            }
            .sheet(isPresented: $showingManagerPinSheet) {
                ManagerPINVerificationSheet(
                    isPresented: $showingManagerPinSheet,
                    onSuccess: {
                        performDelete()
                    }
                )
            }
        }
    }
    
    private func startNewSession() {
        let leader = table.joinedParent ?? table
        let newSession = TableSession(sessionToken: UUID().uuidString, startedAt: Date(), isActive: true, table: leader, guestCount: leader.capacity)
        leader.sessions.append(newSession)
        
        leader.status = "occupied"
        leader.isSynced = false
        for child in leader.joinedChildren {
            child.status = "occupied"
            child.isSynced = false
        }
        leader.updatedAt = Date()
        for child in leader.joinedChildren {
            child.updatedAt = Date()
        }
        try? modelContext.save()
        
        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
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
}

#Preview {
    TableView(selectedTab: .constant(.tables), activeSession: .constant(nil))
        .modelContainer(for: [RestaurantTable.self, TableSession.self], inMemory: true)
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Redesigned Dynamic Restaurant Table Component
// ─────────────────────────────────────────────────────────────────────────────

struct DynamicTableLayoutView: View {
    let tableNumber: String
    let capacity: Int
    let status: String
    let isEditingLayout: Bool
    let isDragging: Bool
    let isSelected: Bool
    let statusColor: Color
    var joinedParentNumber: String? = nil
    var isGroupLeader: Bool = false
    var itemCount: Int = 0
    
    // Seat dimensions
    private let chairWidth: CGFloat = 18
    private let chairHeight: CGFloat = 9
    private let chairCornerRadius: CGFloat = 3.5
    
    private var formattedTableNumber: String {
        let trimmed = tableNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return ""
        }
        if trimmed.allSatisfy({ $0.isNumber }) {
            return "T\(trimmed)"
        }
        return trimmed
    }
    
    var body: some View {
        // Dynamic seat counts calculation around the 4 sides
        let leftCount = capacity >= 3 ? 1 : 0
        let rightCount = capacity >= 4 ? 1 : 0
        let remaining = capacity - leftCount - rightCount
        let topCount = (remaining + 1) / 2
        let bottomCount = remaining / 2
        
        // Table size stretches dynamically depending on the top/bottom seats count
        let tableWidth = max(76, CGFloat(max(topCount, bottomCount)) * 40 + 20)
        let tableHeight: CGFloat = 70
        
        ZStack {
            // 1. Table surface card in the center
            VStack(spacing: 4) {
                // Table Label
                Text(formattedTableNumber)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
                
                // Status badge
                Text(status.uppercased())
                    .font(.system(size: 8, weight: .heavy))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .foregroundColor(statusColor)
                    .background(statusColor.opacity(0.12))
                    .cornerRadius(4)
                
                if isEditingLayout {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 8))
                        .foregroundColor(.appAccent)
                }
                
                if let parent = joinedParentNumber {
                    HStack(spacing: 2) {
                        Image(systemName: "link")
                            .font(.system(size: 6))
                        Text("Joined to \(parent)")
                            .font(.system(size: 6, weight: .bold))
                    }
                    .foregroundColor(.textSecondary)
                    .padding(.top, 1)
                } else if isGroupLeader {
                    HStack(spacing: 2) {
                        Image(systemName: "link")
                            .font(.system(size: 6))
                        Text("Leader")
                            .font(.system(size: 6, weight: .bold))
                    }
                    .foregroundColor(.appTeal)
                    .padding(.top, 1)
                }
            }
            .frame(width: tableWidth, height: tableHeight)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.appSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(
                                isSelected ? Color.appAccent : (isDragging ? statusColor.opacity(0.8) : Color.appBorderSubtle),
                                lineWidth: isSelected ? 2.5 : (isDragging ? 2.0 : 1.2)
                            )
                    )
            )
            .overlay(
                Group {
                    if itemCount > 0 {
                        VStack {
                            HStack {
                                Spacer()
                                Text("\(itemCount)")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color.appAccent)
                                    .clipShape(Capsule())
                                    .shadow(color: .black.opacity(0.3), radius: 2)
                                    .offset(x: 4, y: -4)
                            }
                            Spacer()
                        }
                    }
                }
            )
            .shadow(
                color: isSelected ? Color.appAccent.opacity(0.4) : (isDragging ? statusColor.opacity(0.4) : Color.black.opacity(0.12)),
                radius: isSelected ? 14 : (isDragging ? 12 : 5),
                x: 0,
                y: isSelected ? 4 : (isDragging ? 8 : 2)
            )
            .scaleEffect(isSelected ? 1.05 : 1.0)
            .animation(.spring(response: 0.35, dampingFraction: 0.78), value: isSelected)
            
            // 2. Dynamic Chairs layout
            // Left chair
            if leftCount > 0 {
                chairView(width: chairHeight, height: chairWidth, side: .left)
                    .offset(x: -(tableWidth / 2 + chairHeight / 2 + 3), y: 0)
            }
            
            // Right chair
            if rightCount > 0 {
                chairView(width: chairHeight, height: chairWidth, side: .right)
                    .offset(x: tableWidth / 2 + chairHeight / 2 + 3, y: 0)
            }
            
            // Top chairs
            if topCount > 0 {
                ForEach(0..<topCount, id: \.self) { idx in
                    let offset = xOffsetForIndex(idx, count: topCount, totalWidth: tableWidth)
                    chairView(width: chairWidth, height: chairHeight, side: .top)
                        .offset(x: offset, y: -(tableHeight / 2 + chairHeight / 2 + 3))
                }
            }
            
            // Bottom chairs
            if bottomCount > 0 {
                ForEach(0..<bottomCount, id: \.self) { idx in
                    let offset = xOffsetForIndex(idx, count: bottomCount, totalWidth: tableWidth)
                    chairView(width: chairWidth, height: chairHeight, side: .bottom)
                        .offset(x: offset, y: tableHeight / 2 + chairHeight / 2 + 3)
                }
            }
        }
    }
    
    private func xOffsetForIndex(_ idx: Int, count: Int, totalWidth: CGFloat) -> CGFloat {
        if count == 1 {
            return 0
        }
        let availableWidth = totalWidth - 22 // leaving margin at the corners
        let step = availableWidth / CGFloat(count - 1)
        return -availableWidth / 2 + CGFloat(idx) * step
    }
    
    enum ChairSide {
        case top, bottom, left, right
    }
    
    @ViewBuilder
    private func chairView(width: CGFloat, height: CGFloat, side: ChairSide) -> some View {
        ZStack {
            // Chair cushion body
            RoundedRectangle(cornerRadius: chairCornerRadius, style: .continuous)
                .fill(statusColor.opacity(0.25))
                .overlay(
                    RoundedRectangle(cornerRadius: chairCornerRadius, style: .continuous)
                        .stroke(statusColor.opacity(0.8), lineWidth: 1)
                )
            
            // Micro backrest line for modern architectural look
            backrestLine(side: side)
        }
        .frame(width: width, height: height)
    }
    
    @ViewBuilder
    private func backrestLine(side: ChairSide) -> some View {
        switch side {
        case .top:
            VStack {
                Rectangle()
                    .fill(statusColor)
                    .frame(height: 1.5)
                Spacer()
            }
        case .bottom:
            VStack {
                Spacer()
                Rectangle()
                    .fill(statusColor)
                    .frame(height: 1.5)
            }
        case .left:
            HStack {
                Rectangle()
                    .fill(statusColor)
                    .frame(width: 1.5)
                Spacer()
            }
        case .right:
            HStack {
                Spacer()
                Rectangle()
                    .fill(statusColor)
                    .frame(width: 1.5)
            }
        }
    }
}

struct InteractiveTableCard: View {
    let table: RestaurantTable
    let isEditingLayout: Bool
    let isDragging: Bool
    let isSelected: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void
    
    private func statusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "vacant": return .appTeal
        case "occupied": return .appRose
        case "reserved": return .appAmber
        case "cleaning": return .appAccent
        default: return .textSecondary
        }
    }
    
    var body: some View {
        let statusCol = statusColor(table.status)
        let leader = table.joinedParent ?? table
        let activeSession = leader.sessions.first(where: { $0.isActive })
        let itemCount = activeSession?.orders.reduce(0) { total, order in
            total + order.items.reduce(0) { subtotal, item in subtotal + item.quantity }
        } ?? 0
        
        DynamicTableLayoutView(
            tableNumber: table.tableNumber,
            capacity: table.capacity,
            status: table.status,
            isEditingLayout: isEditingLayout,
            isDragging: isDragging,
            isSelected: isSelected,
            statusColor: statusCol,
            joinedParentNumber: table.joinedParent?.tableNumber,
            isGroupLeader: !table.joinedChildren.isEmpty,
            itemCount: itemCount
        )
        // Pad the table by 16px to ensure chairs don't clip and remain fully visible and interactable
        .padding(16)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
        .onLongPressGesture {
            onLongPress()
        }
    }
}

struct InteractiveTableCardWrapper: View {
    let table: RestaurantTable
    let isEditingLayout: Bool
    let activeDraggingTableId: UUID?
    let selectedTableId: UUID?
    let dragTranslation: CGSize
    let zoomScale: CGFloat
    let isBouncing: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void
    let onDragChanged: (DragGesture.Value) -> Void
    let onDragEnded: (DragGesture.Value) -> Void
    
    var body: some View {
        let isDragging = activeDraggingTableId == table.id
        let isSelected = selectedTableId == table.id
        let offset = isDragging ? dragTranslation : .zero
        let scaledOffset = CGSize(
            width: offset.width / zoomScale,
            height: offset.height / zoomScale
        )
        let posX = CGFloat(table.positionX)
        let posY = CGFloat(table.positionY)
        
        let offsetX = posX + scaledOffset.width
        let offsetY = posY + scaledOffset.height
        let scale = isDragging ? 1.06 : (isBouncing ? 1.15 : 1.0)
        let rotationDegrees = isDragging ? 3.0 : 0.0
        let zIndexVal = isDragging ? 100.0 : (isBouncing ? 50.0 : 1.0)
        
        let tableDragGesture = DragGesture(minimumDistance: 2)
            .onChanged(onDragChanged)
            .onEnded(onDragEnded)
            
        InteractiveTableCard(
            table: table,
            isEditingLayout: isEditingLayout,
            isDragging: isDragging,
            isSelected: isSelected,
            onTap: onTap,
            onLongPress: onLongPress
        )
        .offset(x: offsetX, y: offsetY)
        .scaleEffect(scale)
        .rotationEffect(.degrees(rotationDegrees))
        .zIndex(zIndexVal)
        .tableDragGesture(isEditing: isEditingLayout, gesture: AnyGesture(tableDragGesture))
    }
}

struct EmptyCanvasOverlayView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.grid.3x3.fill")
                .font(.system(size: 44))
                .foregroundColor(.textTertiary)
            Text("No Tables on This Floor")
                .font(.headline)
                .foregroundColor(.textSecondary)
            Text("Add a table to begin mapping this floor layout.")
                .font(.caption)
                .foregroundColor(.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(width: 300)
        .padding(24)
        .background(Color.appSurface)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.appBorderSubtle, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
}

// MARK: - View Extension for conditional table drag gesture

extension View {
    @ViewBuilder
    func tableDragGesture(isEditing: Bool, gesture: some Gesture) -> some View {
        if isEditing {
            self.gesture(gesture)
        } else {
            self
        }
    }
}
