
import SwiftUI
import SwiftData
import PhotosUI

struct TableView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var lm: LocalizationManager
    @EnvironmentObject private var sessionManager: AppSessionManager
    @Query(sort: \RestaurantTable.tableNumber) private var tables: [RestaurantTable]
    
    @Binding var selectedTab: MainDashboardView.DashboardTab
    @Binding var activeSession: TableSession?
    @Binding var columnVisibility: NavigationSplitViewVisibility
    
    @State private var selectedTable: RestaurantTable?
    @State private var showingDetailSheet = false
    @State private var showingAddTableSheet = false
    @State private var isEditingLayout = false
    @State private var draggedTableId: UUID?
    @State private var dragTranslation: CGSize = .zero
    @State private var activeDraggingTableId: UUID? = nil
    @State private var selectedFloor: Int = 1
    @State private var selectedZone: String = "All"
    @State private var zoomScale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @State private var activePanOffset: CGSize = .zero
    @State private var isMovementLocked: Bool = false
    @State private var gestureScale: CGFloat = 1.0
    @State private var focusTableId: UUID? = nil
    @State private var bounceTableId: UUID? = nil
    @State private var headerWidth: CGFloat = 0
    @ObservedObject private var syncEngine = SyncEngine.shared
    
    @Query(filter: #Predicate<RegisterSession> { $0.closedAt == nil && !$0.isDeleted })
    private var activeRegisterSessions: [RegisterSession]
    @State private var showNoActiveShiftAlert = false
    
    @Query(sort: \FloorPlanImage.floor) private var floorPlanImages: [FloorPlanImage]
    @Query(sort: \TableLayoutPreset.name) private var layoutPresets: [TableLayoutPreset]
    @State private var showingSavePresetAlert = false
    @State private var presetNameInput = ""
    
    @AppStorage("logged_in_email") private var loggedInEmail = "owner@alphapos.com"
    @State private var isLayoutManagerAuthorized = false
    // MARK: - Layout & View Mode
    @AppStorage("table_layout_mode") private var layoutModeRaw: String = "canvas"
    @AppStorage("table_view_mode") private var tableViewModeRaw: String = "map"
    // MARK: - Dynamic Floors
    @AppStorage("table_floors_json") private var floorsJson: String = FloorData.defaultFloors.jsonString
    private var floors: [FloorData] { floorsJson.asFloorDataArray }
    // Floor edit state
    @State private var showingAddFloorAlert = false
    @State private var showingRenameFloorAlert = false
    @State private var renamingFloorId: Int? = nil
    @State private var floorNameInput: String = ""
    @State private var showingRemoveFloorConfirm = false
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var cachedFloorPlanImage: UIImage? = nil
    @State private var showingManagerPinSheet = false
    @State private var showingBatchQRSheet = false
    @State private var pendingAuthAction: AuthAction? = nil
    
    enum AuthAction {
        case toggleEditLayout(Bool)
        case addTable
        case resetTables
    }
    
    var body: some View {
        // Outer GeometryReader วัด available width ก่อน render header
        GeometryReader { outerGeo in
            let isLandscape = outerGeo.size.width > outerGeo.size.height
            ZStack {
                Color.appBackground.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Responsive Header — ใช้ outerGeo.size.width แทน headerWidth
                    Group {
                        if outerGeo.size.width < 960 {
                            compactHeader(showsSidebarButton: isLandscape, width: outerGeo.size.width)
                        } else {
                            wideHeader(showsSidebarButton: isLandscape)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, isLandscape ? 6 : 10)
                    .frame(maxWidth: .infinity)
                    .background(Color.appSurface)
                    .overlay(
                        Divider().background(Color.appDivider),
                        alignment: .bottom
                    )
                    
                    // Floor Plan Canvas with Floating Panel Overlaid
                    ZStack(alignment: .bottomTrailing) {
                        if isListView {
                            tableListView
                        } else {
                            VStack(spacing: 0) {
                                // Grid/Canvas + Add Table toolbar (only in edit mode, map view)
                                if isEditingLayout {
                                    HStack(spacing: 12) {
                                        // Grid / Canvas segmented toggle
                                        HStack(spacing: 2) {
                                            ForEach([("square.grid.2x2", "grid", "table_layout_mode_grid"),
                                                     ("rectangle.on.rectangle.angled", "canvas", "table_layout_mode_canvas")],
                                                    id: \.1) { icon, mode, key in
                                                Button(action: {
                                                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                                                        layoutModeRaw = mode
                                                        APHaptic.trigger()
                                                    }
                                                }) {
                                                    Image(systemName: icon)
                                                        .font(.system(size: 14, weight: .semibold))
                                                        .foregroundColor(layoutModeRaw == mode ? .white : .textSecondary)
                                                        .frame(width: 34, height: 30)
                                                        .background(layoutModeRaw == mode ? Color.appAccent : Color.clear)
                                                        .cornerRadius(6)
                                                }
                                                .buttonStyle(.plain)
                                                .accessibilityLabel(key.t)
                                            }
                                        }
                                        .padding(2)
                                        .background(Color.appSurfaceHigh)
                                        .cornerRadius(8)
                                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appBorderSubtle, lineWidth: 1))

                                        Divider()
                                            .frame(width: 1, height: 20)
                                            .background(Color.appDivider)

                                        // Floor Management Actions
                                        HStack(spacing: 8) {
                                            // Add Floor
                                            Button(action: { showingAddFloorAlert = true }) {
                                                HStack(spacing: 4) {
                                                    Image(systemName: "plus")
                                                        .font(.system(size: 10, weight: .bold))
                                                    Text("table_floor_add_btn".t)
                                                        .font(.system(size: 11, weight: .semibold))
                                                }
                                                .foregroundColor(.appAccent)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(Color.appAccent.opacity(0.1))
                                                .cornerRadius(8)
                                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appAccent.opacity(0.3), lineWidth: 1))
                                            }
                                            .buttonStyle(.plain)

                                            // Remove Floor
                                            if floors.count > 1 {
                                                Button(action: { showingRemoveFloorConfirm = true }) {
                                                    HStack(spacing: 4) {
                                                        Image(systemName: "trash")
                                                            .font(.system(size: 10, weight: .bold))
                                                        Text("table_floor_remove_btn".t)
                                                            .font(.system(size: 11, weight: .semibold))
                                                    }
                                                    .foregroundColor(.appRose)
                                                    .padding(.horizontal, 10)
                                                    .padding(.vertical, 6)
                                                    .background(Color.appRose.opacity(0.08))
                                                    .cornerRadius(8)
                                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appRose.opacity(0.3), lineWidth: 1))
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }

                                        Divider()
                                            .frame(width: 1, height: 20)
                                            .background(Color.appDivider)

                                        layoutPresetsToolbar

                                        Spacer()

                                        // Add Table button
                                        Button(action: { checkManagerPermission(for: .addTable) }) {
                                            HStack(spacing: 5) {
                                                Image(systemName: "plus")
                                                    .font(.system(size: 12, weight: .bold))
                                                Text("table_add_new_title".t)
                                                    .font(.system(size: 13, weight: .semibold))
                                            }
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 8)
                                            .background(Color.appAccent)
                                            .cornerRadius(9)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(Color.appSurface)
                                    .overlay(Divider().background(Color.appDivider), alignment: .bottom)
                                }
                                floorPlanCanvas
                            }
                        }
                        
                        if !isListView {
                            floatingControlsPanel
                                .padding(20)
                        }
                        
                        if !syncEngine.activeRequests.isEmpty {
                            activeRequestsOverlay
                        }
                    }
                }
            }
            .navigationTitle("tab_tables".t)
        .apNavBar()
        .onAppear { loadCachedFloorPlanImage() }
        .onChange(of: selectedFloor) { loadCachedFloorPlanImage() }
        .onChange(of: floorPlanImages) { loadCachedFloorPlanImage() }
            #if os(iOS) || os(visionOS)
            // The custom controls already act as this screen's header. In
            // landscape, hiding the duplicate navigation title recovers the
            // vertical space while the safe area still protects system UI.
            .toolbar(isLandscape ? .hidden : .visible, for: .navigationBar)
            #endif
            .sheet(item: $selectedTable) { table in
                TableDetailView(table: table, selectedTab: $selectedTab, posTableSession: $activeSession)
            }
            .alert("Cash Drawer is Locked", isPresented: $showNoActiveShiftAlert) {
                Button("go_to_cash_drawer".t) {
                    selectedTab = .cashDrawer
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("pos_shift_required_hint".t)
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
            .fullScreenCover(isPresented: $showingBatchQRSheet) {
                BatchQRCodePrintView(tables: tables)
            }
        } // end GeometryReader
    }
    
    @ViewBuilder
    private var floorPlanCanvas: some View {
        let floorTables = tables.filter { ($0.floor ?? 1) == selectedFloor && !$0.isDeleted }
        
        GeometryReader { viewport in
            ZStack(alignment: .topLeading) {

                // Large canvas content (grid + tables)
                ZStack(alignment: .topLeading) {
                    // Floor Plan background image (behind grid & tables)
                    if let img = cachedFloorPlanImage {
                        let bgScale = activeFloorPlanImage?.scale ?? 1.0
                        let bgOffsetX = activeFloorPlanImage?.offsetX ?? 0.0
                        let bgOffsetY = activeFloorPlanImage?.offsetY ?? 0.0
                        
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 1500 * bgScale, height: 1200 * bgScale)
                            .offset(x: bgOffsetX, y: bgOffsetY)
                            .clipped()
                            .opacity(0.35)
                            .allowsHitTesting(false)
                    }

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
                        let gridOpacity: CGFloat = isGridMode ? 0.25 : 0.12
                        context.stroke(path, with: .color(Color.appDivider.opacity(gridOpacity)), lineWidth: isGridMode ? 0.8 : 0.6)
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
                                    if activeRegisterSessions.isEmpty {
                                        showNoActiveShiftAlert = true
                                        return
                                    }
                                    let leader = table.joinedParent ?? table
                                    if let session = leader.sessions.first(where: { $0.isActive }) {
                                        if Calendar.current.isDateInToday(session.startedAt) {
                                            activeSession = session
                                            selectedTab = .pos
                                            APHaptic.trigger()
                                        } else {
                                            // Close stale session
                                            session.isActive = false
                                            session.endedAt = Date()
                                            session.isSynced = false
                                            session.updatedAt = Date()
                                            
                                            let tNum = leader.tableNumber
                                            Task {
                                                _ = try? await NetworkManager.shared.closeTableSession(tableNumber: tNum)
                                            }
                                            
                                            // Auto-start vacant table session
                                            let newSession = TableSession(sessionToken: UUID().uuidString, startedAt: Date(), isActive: true, table: leader, guestCount: leader.capacity)
                                            modelContext.insert(newSession)
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
                                            
                                            activeSession = newSession
                                            selectedTab = .pos
                                            APHaptic.trigger()
                                            
                                            Task {
                                                await SyncEngine.shared.syncAll(modelContext: modelContext)
                                            }
                                        }
                                    } else {
                                        // Auto-start vacant table session
                                        let newSession = TableSession(sessionToken: UUID().uuidString, startedAt: Date(), isActive: true, table: leader, guestCount: leader.capacity)
                                        modelContext.insert(newSession)
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
                                        
                                        activeSession = newSession
                                        selectedTab = .pos
                                        APHaptic.trigger()
                                        
                                        Task {
                                            await SyncEngine.shared.syncAll(modelContext: modelContext)
                                        }
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
                        .opacity(selectedZone == "All" || table.zone == selectedZone ? 1.0 : 0.25)
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedZone)
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
            .overlay(
                Group {
                    if isEditingLayout && activeFloorPlanImage != nil {
                        bgImageAdjustmentsPanel
                            .padding(16)
                    }
                },
                alignment: .bottomLeading
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
    
    private var floatingControlsPanel: some View {
        VStack(spacing: 12) {
            // Floor Plan upload button (visible only in edit mode)
            floorPlanUploadButton

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
                .accessibilityLabel("Add new table")
                
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

    // MARK: - Table List View
    @ViewBuilder
    private var tableListView: some View {
        let floorTables = tables.filter { ($0.floor ?? 1) == selectedFloor && !$0.isDeleted }
        let sortedTables = floorTables.sorted { $0.tableNumber < $1.tableNumber }
        let availableCount  = floorTables.filter { $0.status.lowercased() == "vacant" }.count
        let occupiedCount   = floorTables.filter { $0.status.lowercased() == "occupied" }.count
        let reservedCount   = floorTables.filter { $0.status.lowercased() == "reserved" }.count
        let withOrdersCount = floorTables.filter { !$0.sessions.filter({ $0.isActive }).isEmpty }.count
        let totalSeats      = floorTables.reduce(0) { $0 + $1.capacity }

        ZStack {
            Color.appBackground.ignoresSafeArea()
            VStack(spacing: 0) {

                // ── Floor underline tabs ──
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(floors) { floor in
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedFloor = floor.id
                                    APHaptic.trigger()
                                }
                            }) {
                                VStack(spacing: 0) {
                                    Text(floor.name)
                                        .font(.system(size: 14, weight: selectedFloor == floor.id ? .bold : .regular))
                                        .foregroundColor(selectedFloor == floor.id ? .appAccent : .textSecondary)
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 12)
                                    Rectangle()
                                        .fill(selectedFloor == floor.id ? Color.appAccent : Color.clear)
                                        .frame(height: 2)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .background(Color.appSurface)
                .overlay(Divider().background(Color.appDivider), alignment: .bottom)

                // ── Summary bar ──
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        listSummaryChip(text: String(format: "table_list_total".t, floorTables.count), color: .textSecondary)
                        listSummaryChip(text: String(format: "table_list_available".t, availableCount), color: .appTeal, dot: true)
                        listSummaryChip(text: String(format: "table_list_occupied".t, occupiedCount), color: .appRose, dot: true)
                        listSummaryChip(text: String(format: "table_list_reserved".t, reservedCount), color: .appAmber, dot: true)
                        listSummaryChip(text: String(format: "table_list_with_orders".t, withOrdersCount), color: .appAccent)
                        listSummaryChip(text: String(format: "table_list_total_seats".t, totalSeats), color: .textSecondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .background(Color.appSurface)
                .overlay(Divider().background(Color.appDivider), alignment: .bottom)

                if floorTables.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "tablecells")
                            .font(.system(size: 48))
                            .foregroundColor(.textTertiary)
                        Text("table_empty_canvas_title".t)
                            .font(.headline)
                            .foregroundColor(.textSecondary)
                    }
                    Spacer()
                } else {
                    // ── Tip ──
                    HStack {
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundColor(.textTertiary)
                        Text("table_list_tip".t)
                            .font(.caption)
                            .foregroundColor(.textTertiary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                    // ── Column headers ──
                    HStack(spacing: 0) {
                        Spacer().frame(width: 48)
                        Text("table_list_col_table".t)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("table_list_col_seats".t)
                            .frame(width: 60, alignment: .center)
                        Text("table_list_col_shape".t)
                            .frame(width: 100, alignment: .center)
                        Text("table_list_col_status".t)
                            .frame(width: 110, alignment: .center)
                        Text("table_list_col_qr".t)
                            .frame(width: 90, alignment: .center)
                        Text("table_list_col_total".t)
                            .frame(width: 80, alignment: .trailing)
                    }
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.textTertiary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Color.appSurfaceHigh)

                    Divider().background(Color.appDivider)

                    // ── Table rows ──
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(sortedTables) { table in
                                listTableRow(table)
                                Divider().background(Color.appDivider).padding(.leading, 16)
                            }
                        }
                    }
                    .background(Color.appSurface)
                }
            }
        }
    }

    private func listSummaryChip(text: String, color: Color, dot: Bool = false) -> some View {
        HStack(spacing: 5) {
            if dot {
                Circle().fill(color).frame(width: 7, height: 7)
            }
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.textSecondary)
        }
    }

    @ViewBuilder
    private func listTableRow(_ table: RestaurantTable) -> some View {
        let activeSession = table.sessions.last(where: { $0.isActive })
        Button(action: {
            selectedTable = table
            showingDetailSheet = true
        }) {
            HStack(spacing: 0) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.appSurfaceHigh)
                        .frame(width: 32, height: 32)
                    Image(systemName: "chair.lounge")
                        .font(.system(size: 14))
                        .foregroundColor(.textSecondary)
                }
                .frame(width: 48, alignment: .center)

                // Table name
                VStack(alignment: .leading, spacing: 1) {
                    Text(table.tableNumber)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.textPrimary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Seats
                Text("\(table.capacity)")
                    .font(.system(size: 14))
                    .foregroundColor(.textSecondary)
                    .frame(width: 60, alignment: .center)

                // Shape badge
                Text(shapeLabel(table.tableShape))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.appSurfaceHigh)
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorderSubtle, lineWidth: 1))
                    .frame(width: 100, alignment: .center)

                // Status badge
                listStatusBadge(status: table.status)
                    .frame(width: 110, alignment: .center)

                // QR actions
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 14))
                        .foregroundColor(.textSecondary)
                    Image(systemName: "qrcode")
                        .font(.system(size: 14))
                        .foregroundColor(.textSecondary)
                }
                .frame(width: 90, alignment: .center)

                // Total
                if let session = activeSession {
                    Text(String(format: "%.0f", session.totalAmount))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.appAccent)
                        .frame(width: 80, alignment: .trailing)
                } else {
                    Text("—")
                        .font(.system(size: 13))
                        .foregroundColor(.textTertiary)
                        .frame(width: 80, alignment: .trailing)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.appSurface)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func shapeLabel(_ shape: String) -> String {
        switch shape {
        case "circle":    return "table_shape_circle".t
        case "oval":      return "table_shape_oval".t
        case "square":    return "table_shape_square".t
        default:          return "table_shape_rectangle".t
        }
    }

    @ViewBuilder
    private func listStatusBadge(status: String) -> some View {
        let (label, bg, fg): (String, Color, Color) = {
            switch status.lowercased() {
            case "occupied":  return ("table_status_occupied".t,  Color.appRose.opacity(0.15),  .appRose)
            case "reserved":  return ("table_status_reserved".t,  Color.appAmber.opacity(0.15), .appAmber)
            case "cleaning":  return ("table_status_cleaning".t,  Color.appAccent.opacity(0.15),.appAccent)
            default:          return ("table_status_available".t, Color.appTeal.opacity(0.15),  .appTeal)
            }
        }()
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(fg)
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(fg.opacity(0.7))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(bg)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(fg.opacity(0.3), lineWidth: 1))
    }

    // MARK: - Floor Plan Upload Button (shown in edit mode)
    @ViewBuilder
    private var floorPlanUploadButton: some View {  // floorPlanUploadButton body
        if isEditingLayout {
            VStack(spacing: 0) {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Image(systemName: currentFloorPlanImagePath.isEmpty ? "photo.badge.plus" : "photo.badge.checkmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(currentFloorPlanImagePath.isEmpty ? .textPrimary : .appAccent)
                        .frame(width: 44, height: 44)
                }
                .onChange(of: selectedPhotoItem) { _, newItem in
                    guard let newItem else { return }
                    Task {
                        if let data = try? await newItem.loadTransferable(type: Data.self),
                           let uiImage = UIImage(data: data) {
                            let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                            let filename = "floor_plan_\(selectedFloor)_\(Int(Date().timeIntervalSince1970)).jpg"
                            let fileURL = docsURL.appendingPathComponent(filename)
                            if let jpegData = uiImage.jpegData(compressionQuality: 0.85) {
                                try? jpegData.write(to: fileURL)
                                saveFloorPlanImage(filename: filename)
                                
                                // Upload to Storage in background
                                Task.detached {
                                    do {
                                        _ = try await NetworkManager.shared.uploadFloorPlanMedia(data: jpegData, fileName: filename)
                                    } catch {
                                        print("Failed to upload floor plan image to storage: \(error)")
                                    }
                                }
                                
                                await MainActor.run {
                                    cachedFloorPlanImage = uiImage
                                    selectedPhotoItem = nil
                                }
                            }
                        }
                    }
                }

                if floorPlanImages.first(where: { $0.floor == selectedFloor && !$0.isDeleted }) != nil {
                    Divider().background(Color.appDivider).frame(width: 32)
                    Button(action: { removeFloorPlanImage() }) {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.appRose)
                            .frame(width: 44, height: 36)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Color.appSurface.opacity(0.88))
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorderSubtle, lineWidth: 1))
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
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }
    
    private var zones: [String] {
        let floorTables = tables.filter { ($0.floor ?? 1) == selectedFloor && !$0.isDeleted }
        let uniqueZones = Set(floorTables.compactMap { $0.zone }).filter { !$0.isEmpty }
        return ["All"] + Array(uniqueZones).sorted()
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
        
        let clampedX = min(max(newX, minX), maxX)
        let clampedY = min(max(newY, minY), maxY)

        let finalPosition = CGPoint(x: clampedX, y: clampedY)
        
        // Reset dragging state completely before updating position
        // to avoid visual jump caused by animating dragTranslation to zero
        // while the base offset changes simultaneously
        activeDraggingTableId = nil
        draggedTableId = nil
        dragTranslation = .zero
        
        updateTablePosition(table, newPosition: finalPosition)
        APHaptic.trigger()

        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }
    
    private func seedSampleTables() {
        SampleDataSeeder.seedTables(modelContext: modelContext)
    }
    
    private func checkManagerPermission(for action: AuthAction) {
        if sessionManager.can(.managerOverride) || isLayoutManagerAuthorized {
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
    
    // MARK: - Premium Redesigned Header Elements

    // MARK: - Computed Mode Helpers
    private var isGridMode: Bool { layoutModeRaw == "grid" }
    private var isListView: Bool { tableViewModeRaw == "list" }

    private var currentFloorPlanImagePath: String {
        floorPlanImages.first(where: { $0.floor == selectedFloor && !$0.isDeleted })?.resolvedImagePath ?? ""
    }

    private func saveFloorPlanImage(filename: String) {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? "unknown"
        if let existing = floorPlanImages.first(where: { $0.floor == selectedFloor }) {
            existing.imageFilename = filename
            existing.isDeleted = false
            existing.isSynced = false
            existing.updatedAt = Date()
        } else {
            let newItem = FloorPlanImage(
                merchantId: merchantId,
                floor: selectedFloor,
                imageFilename: filename
            )
            modelContext.insert(newItem)
        }
        try? modelContext.save()
        Task { await SyncEngine.shared.syncAll(modelContext: modelContext) }
    }

    private func removeFloorPlanImage() {
        guard let existing = floorPlanImages.first(where: { $0.floor == selectedFloor }) else { return }

        // 1. Remove local file from disk if it exists
        if let path = existing.resolvedImagePath, FileManager.default.fileExists(atPath: path) {
            try? FileManager.default.removeItem(atPath: path)
        }

        // 2. Clear in-memory cached image
        cachedFloorPlanImage = nil

        // 3. Create unmanaged copy for background remote deletion sync
        let unmanagedCopy = FloorPlanImage(
            id: existing.id,
            merchantId: existing.merchantId,
            floor: existing.floor,
            imageFilename: existing.imageFilename,
            updatedAt: Date(),
            isSynced: false,
            isDeleted: true
        )

        // 4. Delete from local database context immediately
        modelContext.delete(existing)
        try? modelContext.save()

        // 5. Sync deletion to remote database
        Task {
            _ = try? await NetworkManager.shared.uploadFloorPlanImage(floorPlan: unmanagedCopy)
        }
    }


    private func loadCachedFloorPlanImage() {
        if let floorPlan = activeFloorPlanImage, !floorPlan.imageFilename.isEmpty {
            if let path = floorPlan.resolvedImagePath, let uiImage = UIImage(contentsOfFile: path) {
                cachedFloorPlanImage = uiImage
            } else {
                // If not found locally, try to download from Storage
                Task {
                    do {
                        let data = try await NetworkManager.shared.downloadFloorPlanMedia(fileName: floorPlan.imageFilename)
                        if let downloadedImage = UIImage(data: data) {
                            // Save locally for future use
                            let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                            let fileURL = docsURL.appendingPathComponent(floorPlan.imageFilename)
                            try? data.write(to: fileURL)
                            
                            await MainActor.run {
                                self.cachedFloorPlanImage = downloadedImage
                            }
                        }
                    } catch {
                        print("Failed to download floor plan image: \(error)")
                        await MainActor.run {
                            self.cachedFloorPlanImage = nil
                        }
                    }
                }
            }
        } else {
            cachedFloorPlanImage = nil
        }
    }

    // MARK: - Floor Plan Background Adjustments Helpers
    private var activeFloorPlanImage: FloorPlanImage? {
        floorPlanImages.first(where: { $0.floor == selectedFloor && !$0.isDeleted })
    }

    private var bgScaleBinding: Binding<Double> {
        Binding(
            get: { activeFloorPlanImage?.scale ?? 1.0 },
            set: { newValue in
                if let img = activeFloorPlanImage {
                    img.scale = newValue
                    img.isSynced = false
                    img.updatedAt = Date()
                    try? modelContext.save()
                }
            }
        )
    }

    private var bgOffsetXBinding: Binding<Double> {
        Binding(
            get: { activeFloorPlanImage?.offsetX ?? 0.0 },
            set: { newValue in
                if let img = activeFloorPlanImage {
                    img.offsetX = newValue
                    img.isSynced = false
                    img.updatedAt = Date()
                    try? modelContext.save()
                }
            }
        )
    }

    private var bgOffsetYBinding: Binding<Double> {
        Binding(
            get: { activeFloorPlanImage?.offsetY ?? 0.0 },
            set: { newValue in
                if let img = activeFloorPlanImage {
                    img.offsetY = newValue
                    img.isSynced = false
                    img.updatedAt = Date()
                    try? modelContext.save()
                }
            }
        )
    }

    // MARK: - Table Layout Presets (Templates) Operations
    private func saveLayoutPreset(name: String) {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? "default_merchant"
        let branchId = UserDefaults.standard.string(forKey: "active_branch_id") ?? "default_branch"
        
        let floorTables = tables.filter { ($0.floor ?? 1) == selectedFloor && !$0.isDeleted }
        let items = floorTables.map { table in
            TableLayoutItem(
                id: table.id,
                tableNumber: table.tableNumber,
                capacity: table.capacity,
                tableShape: table.tableShape,
                positionX: table.positionX,
                positionY: table.positionY,
                zone: table.zone
            )
        }
        
        guard let data = try? JSONEncoder().encode(items),
              let json = String(data: data, encoding: .utf8) else { return }
        
        let bgImage = activeFloorPlanImage
        let bgFilename = bgImage?.imageFilename
        let bgScale = bgImage?.scale ?? 1.0
        let bgOffsetX = bgImage?.offsetX ?? 0.0
        let bgOffsetY = bgImage?.offsetY ?? 0.0
        
        if let existing = layoutPresets.first(where: {
            $0.floor == selectedFloor &&
            $0.name.lowercased() == name.lowercased() &&
            $0.branchId == branchId &&
            $0.merchantId == merchantId &&
            !$0.isDeleted
        }) {
            existing.tableLayoutJson = json
            existing.bgImageFilename = bgFilename
            existing.bgImageScale = bgScale
            existing.bgImageOffsetX = bgOffsetX
            existing.bgImageOffsetY = bgOffsetY
            existing.updatedAt = Date()
            existing.isSynced = false
        } else {
            let preset = TableLayoutPreset(
                merchantId: merchantId,
                branchId: branchId,
                floor: selectedFloor,
                name: name,
                bgImageFilename: bgFilename,
                bgImageScale: bgScale,
                bgImageOffsetX: bgOffsetX,
                bgImageOffsetY: bgOffsetY,
                tableLayoutJson: json
            )
            modelContext.insert(preset)
        }
        
        try? modelContext.save()
        APHaptic.trigger()
        
        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }

    private func applyLayoutPreset(_ preset: TableLayoutPreset) {
        let currentMerchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? "default_merchant"
        let currentBranchId = UserDefaults.standard.string(forKey: "active_branch_id") ?? "default_branch"
        
        // Security check
        guard preset.merchantId == currentMerchantId && preset.branchId == currentBranchId else {
            print("Security boundary breach: layout preset merchant/branch mismatch")
            return
        }
        
        guard let data = preset.tableLayoutJson.data(using: .utf8),
              let items = try? JSONDecoder().decode([TableLayoutItem].self, from: data) else { return }
        
        // Apply background image transform
        let currentBg = activeFloorPlanImage
        if let newFilename = preset.bgImageFilename {
            if let bg = currentBg {
                bg.imageFilename = newFilename
                bg.scale = preset.bgImageScale
                bg.offsetX = preset.bgImageOffsetX
                bg.offsetY = preset.bgImageOffsetY
                bg.updatedAt = Date()
                bg.isSynced = false
            } else {
                let newBg = FloorPlanImage(
                    merchantId: currentMerchantId,
                    floor: selectedFloor,
                    imageFilename: newFilename,
                    scale: preset.bgImageScale,
                    offsetX: preset.bgImageOffsetX,
                    offsetY: preset.bgImageOffsetY
                )
                modelContext.insert(newBg)
            }
        } else {
            if let bg = currentBg {
                bg.isDeleted = true
                bg.isSynced = false
                bg.updatedAt = Date()
            }
        }
        
        loadCachedFloorPlanImage()
        
        // Rearrange tables
        let floorTables = tables.filter { ($0.floor ?? 1) == selectedFloor && !$0.isDeleted }
        var matchedTableNumbers = Set<String>()
        
        for item in items {
            matchedTableNumbers.insert(item.tableNumber)
            if let existingTable = floorTables.first(where: { $0.tableNumber == item.tableNumber }) {
                existingTable.positionX = item.positionX
                existingTable.positionY = item.positionY
                existingTable.capacity = item.capacity
                existingTable.tableShape = item.tableShape
                existingTable.isRound = item.tableShape == "circle" || item.tableShape == "oval"
                existingTable.zone = item.zone
                existingTable.updatedAt = Date()
                existingTable.isSynced = false
            } else {
                let newTable = RestaurantTable(
                    tableNumber: item.tableNumber,
                    capacity: item.capacity,
                    tableShape: item.tableShape,
                    positionX: item.positionX,
                    positionY: item.positionY,
                    floor: selectedFloor,
                    zone: item.zone
                )
                modelContext.insert(newTable)
            }
        }
        
        for table in floorTables {
            if !matchedTableNumbers.contains(table.tableNumber) {
                table.isDeleted = true
                table.isSynced = false
                table.updatedAt = Date()
            }
        }
        
        try? modelContext.save()
        APHaptic.trigger()
        
        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }

    private func deleteLayoutPreset(_ preset: TableLayoutPreset) {
        let currentMerchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? "default_merchant"
        let currentBranchId = UserDefaults.standard.string(forKey: "active_branch_id") ?? "default_branch"
        
        // Security check
        guard preset.merchantId == currentMerchantId && preset.branchId == currentBranchId else { return }
        
        preset.isDeleted = true
        preset.updatedAt = Date()
        preset.isSynced = false
        
        try? modelContext.save()
        APHaptic.trigger()
        
        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }

    @ViewBuilder
    private func modernStatusWidget(showLabels: Bool) -> some View {
        HStack(spacing: showLabels ? 14 : 8) {
            modernStatusDot(color: .appTeal, label: "table_status_vacant".t, count: countTables(status: "vacant"), showLabel: showLabels)
            modernStatusDot(color: .appRose, label: "table_status_occupied".t, count: countTables(status: "occupied"), showLabel: showLabels)
            modernStatusDot(color: .appAmber, label: "table_status_reserved".t, count: countTables(status: "reserved"), showLabel: showLabels)
            modernStatusDot(color: .appAccent, label: "table_status_cleaning".t, count: countTables(status: "cleaning"), showLabel: showLabels)
        }
        .padding(.horizontal, showLabels ? 16 : 10)
        .padding(.vertical, 7)
        .background(Color.appSurfaceHigh.opacity(0.6))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.appBorderSubtle, lineWidth: 1)
        )
    }
    
    private func modernStatusDot(color: Color, label: String, count: Int, showLabel: Bool) -> some View {
        HStack(spacing: 4) {
            Text("\(count)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(color)
                .clipShape(Capsule())
                .scaleEffect(count > 0 ? 1.08 : 1.0)
                .animation(.spring(response: 0.25, dampingFraction: 0.6), value: count)
            
            if showLabel {
                Text(label)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.textSecondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    // MARK: - Floor Pill Tabs + Management Buttons
    @ViewBuilder
    private var floorTabsBar: some View {
        HStack(spacing: 0) {
            // Pill tabs scrollable
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(floors) { floor in
                        floorTab(floor: floor)
                    }
                }
                .padding(3)
            }
            .background(Color.appSurfaceHigh.opacity(0.5))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.appBorderSubtle, lineWidth: 1)
            )
        }
        .alert("table_floor_add_btn".t, isPresented: $showingAddFloorAlert) {
            TextField("table_floor_new_name".t, text: $floorNameInput)
            Button("table_create_btn".t) {
                let nextId = (floors.map(\.id).max() ?? 0) + 1
                let name = floorNameInput.isEmpty
                    ? String(format: "table_floor_new_name".t, nextId)
                    : floorNameInput
                var updated = floors
                updated.append(FloorData(id: nextId, name: name))
                floorsJson = updated.jsonString
                selectedFloor = nextId
                floorNameInput = ""
                APHaptic.trigger()
            }
            Button("cancel".t, role: .cancel) { floorNameInput = "" }
        }
        .confirmationDialog("table_floor_remove_confirm".t, isPresented: $showingRemoveFloorConfirm, titleVisibility: .visible) {
            Button("table_floor_remove_btn".t, role: .destructive) {
                // soft-delete tables on this floor
                let floorTables = tables.filter { ($0.floor ?? 1) == selectedFloor && !$0.isDeleted }
                for t in floorTables {
                    t.isDeleted = true
                    t.isSynced = false
                    t.updatedAt = Date()
                }
                try? modelContext.save()
                // remove floor from list
                var updated = floors.filter { $0.id != selectedFloor }
                floorsJson = updated.jsonString
                selectedFloor = updated.first?.id ?? 1
            }
            Button("cancel".t, role: .cancel) { }
        }
        // Rename alert
        .alert("table_floor_rename_title".t, isPresented: $showingRenameFloorAlert) {
            TextField("", text: $floorNameInput)
            Button("ok_btn".t) {
                if let fid = renamingFloorId, !floorNameInput.isEmpty {
                    var updated = floors
                    if let idx = updated.firstIndex(where: { $0.id == fid }) {
                        updated[idx].name = floorNameInput
                        floorsJson = updated.jsonString
                    }
                }
                renamingFloorId = nil
                floorNameInput = ""
            }
            Button("cancel".t, role: .cancel) { renamingFloorId = nil; floorNameInput = "" }
        }
    }

    private func floorTab(floor: FloorData) -> some View {
        let isSelected = selectedFloor == floor.id
        return Button(action: {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                selectedFloor = floor.id
                selectedZone = "All"
                APHaptic.trigger()
            }
        }) {
            VStack(spacing: 2) {
                HStack(spacing: 4) {
                    Text(floor.name)
                        .font(.system(size: 12, weight: isSelected ? .bold : .semibold))
                        .foregroundColor(isSelected ? Color.appAccent : .textSecondary)
                    
                    if isEditingLayout {
                        Button(action: {
                            renamingFloorId = floor.id
                            floorNameInput = floor.name
                            showingRenameFloorAlert = true
                        }) {
                            Image(systemName: "pencil")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(isSelected ? Color.appAccent.opacity(0.8) : .textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, isEditingLayout ? 4 : 6)
                
                // Bottom blue indicator matching Figure 3
                Capsule()
                    .fill(isSelected ? Color.appAccent : Color.clear)
                    .frame(width: 18, height: 3)
            }
            .background(
                isSelected ? Color.appAccent.opacity(0.08) : Color.clear
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Table Layout Presets UI Components
    private var activePresets: [TableLayoutPreset] {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? "default_merchant"
        let branchId = UserDefaults.standard.string(forKey: "active_branch_id") ?? "default_branch"
        return layoutPresets.filter {
            $0.floor == selectedFloor &&
            $0.merchantId == merchantId &&
            $0.branchId == branchId &&
            !$0.isDeleted
        }
    }

    @ViewBuilder
    private var layoutPresetsToolbar: some View {
        HStack(spacing: 8) {
            Text("table_presets_title".t)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.textSecondary)
            
            // Dropdown menu to select a preset
            Menu {
                if activePresets.isEmpty {
                    Text("No templates saved")
                } else {
                    ForEach(activePresets) { preset in
                        Button(action: {
                            applyLayoutPreset(preset)
                        }) {
                            Text(preset.name)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text("Select Template...")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                        .foregroundColor(.textSecondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.appSurfaceHigh)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.appBorderSubtle, lineWidth: 1))
            }
            .buttonStyle(.plain)

            // Save layout preset button
            Button(action: {
                showingSavePresetAlert = true
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .bold))
                    Text("table_presets_save_alert".t)
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.appAccent)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            
            // Delete active presets (if any exist, let them delete)
            if !activePresets.isEmpty {
                Menu {
                    ForEach(activePresets) { preset in
                        Button(role: .destructive, action: {
                            deleteLayoutPreset(preset)
                        }) {
                            Label("Delete \(preset.name)", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.appRose)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color.appRose.opacity(0.1))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .alert("table_presets_save_alert".t, isPresented: $showingSavePresetAlert) {
            TextField("table_presets_enter_name".t, text: $presetNameInput)
            Button("ok_btn".t) {
                if !presetNameInput.isEmpty {
                    saveLayoutPreset(name: presetNameInput)
                }
                presetNameInput = ""
            }
            Button("cancel".t, role: .cancel) { presetNameInput = "" }
        }
    }

    // MARK: - Resizable Background Adjustments Panel UI
    @ViewBuilder
    private var bgImageAdjustmentsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "photo.artframe")
                    .foregroundColor(.appAccent)
                    .font(.system(size: 13, weight: .bold))
                Text("table_bg_adjust_title".t)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.textPrimary)
                Spacer()
                Button(action: {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                        if let bg = activeFloorPlanImage {
                            bg.scale = 1.0
                            bg.offsetX = 0.0
                            bg.offsetY = 0.0
                            bg.updatedAt = Date()
                            bg.isSynced = false
                            try? modelContext.save()
                        }
                    }
                    APHaptic.trigger()
                }) {
                    Text("reset".t)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.appRose)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.appRose.opacity(0.1))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 2)
            
            // Zoom/Scale Slider
            HStack(spacing: 8) {
                Text("table_bg_scale_label".t)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.textSecondary)
                    .frame(width: 45, alignment: .leading)
                Slider(value: bgScaleBinding, in: 0.5...3.0, step: 0.05)
                    .tint(.appAccent)
                Text(String(format: "%.1fx", activeFloorPlanImage?.scale ?? 1.0))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(.textPrimary)
                    .frame(width: 35, alignment: .trailing)
            }
            
            // Offset X Slider
            HStack(spacing: 8) {
                Text("table_bg_x_label".t)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.textSecondary)
                    .frame(width: 45, alignment: .leading)
                Slider(value: bgOffsetXBinding, in: -800...800, step: 5)
                    .tint(.appAccent)
                Text("\(Int(activeFloorPlanImage?.offsetX ?? 0.0)) px")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(.textPrimary)
                    .frame(width: 45, alignment: .trailing)
            }
            
            // Offset Y Slider
            HStack(spacing: 8) {
                Text("table_bg_y_label".t)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.textSecondary)
                    .frame(width: 45, alignment: .leading)
                Slider(value: bgOffsetYBinding, in: -800...800, step: 5)
                    .tint(.appAccent)
                Text("\(Int(activeFloorPlanImage?.offsetY ?? 0.0)) px")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(.textPrimary)
                    .frame(width: 45, alignment: .trailing)
            }
        }
        .padding(12)
        .frame(width: 280)
        .background(Color.appSurface.opacity(0.92))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 5)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.appBorderSubtle, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var customFloorPicker: some View {
        let currentFloorName = floors.first(where: { $0.id == selectedFloor })?.name ?? "Floor \(selectedFloor)"
        Menu {
            ForEach(floors) { floor in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedFloor = floor.id
                        selectedZone = "All"
                        APHaptic.trigger()
                    }
                } label: {
                    if selectedFloor == floor.id {
                        Label(floor.name, systemImage: "checkmark")
                    } else {
                        Text(floor.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "building.2")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.appAccent)
                Text(currentFloorName)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.textPrimary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.textSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.appSurfaceHigh.opacity(0.6))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.appBorderSubtle, lineWidth: 1)
            )
        }
        .alert("table_floor_add_btn".t, isPresented: $showingAddFloorAlert) {
            TextField("table_floor_new_name".t, text: $floorNameInput)
            Button("table_create_btn".t) {
                let nextId = (floors.map(\.id).max() ?? 0) + 1
                let name = floorNameInput.isEmpty
                    ? String(format: "table_floor_new_name".t, nextId)
                    : floorNameInput
                var updated = floors
                updated.append(FloorData(id: nextId, name: name))
                floorsJson = updated.jsonString
                selectedFloor = nextId
                floorNameInput = ""
                APHaptic.trigger()
            }
            Button("cancel".t, role: .cancel) { floorNameInput = "" }
        }
        .confirmationDialog("table_floor_remove_confirm".t, isPresented: $showingRemoveFloorConfirm, titleVisibility: .visible) {
            Button("table_floor_remove_btn".t, role: .destructive) {
                // soft-delete tables on this floor
                let floorTables = tables.filter { ($0.floor ?? 1) == selectedFloor && !$0.isDeleted }
                for t in floorTables {
                    t.isDeleted = true
                    t.isSynced = false
                    t.updatedAt = Date()
                }
                try? modelContext.save()
                // remove floor from list
                var updated = floors.filter { $0.id != selectedFloor }
                floorsJson = updated.jsonString
                selectedFloor = updated.first?.id ?? 1
            }
            Button("cancel".t, role: .cancel) { }
        }
        .alert("table_floor_rename_title".t, isPresented: $showingRenameFloorAlert) {
            TextField("", text: $floorNameInput)
            Button("ok_btn".t) {
                if let fid = renamingFloorId, !floorNameInput.isEmpty {
                    var updated = floors
                    if let idx = updated.firstIndex(where: { $0.id == fid }) {
                        updated[idx].name = floorNameInput
                        floorsJson = updated.jsonString
                    }
                }
                renamingFloorId = nil
                floorNameInput = ""
            }
            Button("cancel".t, role: .cancel) { renamingFloorId = nil; floorNameInput = "" }
        }
    }

    @ViewBuilder
    private var customZonePicker: some View {
        let activeZones = zones
        if activeZones.count > 1 {
            Menu {
                ForEach(activeZones, id: \.self) { zone in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedZone = zone
                            APHaptic.trigger()
                        }
                    } label: {
                        if selectedZone == zone {
                            Label("table_zone_\(zone.lowercased())".t, systemImage: "checkmark")
                        } else {
                            Text("table_zone_\(zone.lowercased())".t)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text("table_zone_\(selectedZone.lowercased())".t)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.textPrimary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.textSecondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.appSurfaceHigh.opacity(0.6))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.appBorderSubtle, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("table_zone_\(selectedZone.lowercased())".t)
            .transition(.opacity.combined(with: .scale))
        }
    }

    @ViewBuilder
    private var quickActionsBar: some View {
        HStack(spacing: 4) {
            findTableCompactButton
            
            Divider()
                .frame(width: 1, height: 16)
                .background(Color.appBorderSubtle)
                .padding(.horizontal, 2)
            
            printQRCodesCompactButton
            
            Divider()
                .frame(width: 1, height: 16)
                .background(Color.appBorderSubtle)
                .padding(.horizontal, 2)
            
            lockPanZoomCompactButton
            
            Divider()
                .frame(width: 1, height: 16)
                .background(Color.appBorderSubtle)
                .padding(.horizontal, 2)
            
            editLayoutSwitchCompactButton

            Divider()
                .frame(width: 1, height: 16)
                .background(Color.appBorderSubtle)
                .padding(.horizontal, 2)

            // List / Map toggle
            Button(action: {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                    tableViewModeRaw = (tableViewModeRaw == "map") ? "list" : "map"
                    APHaptic.trigger()
                }
            }) {
                Image(systemName: tableViewModeRaw == "map" ? "list.bullet" : "map")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.textPrimary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(tableViewModeRaw == "map" ? "table_view_mode_list".t : "table_view_mode_map".t)

            Divider()
                .frame(width: 1, height: 16)
                .background(Color.appBorderSubtle)
                .padding(.horizontal, 2)

            // Grid / Canvas toggle (only in map view)
            if !isListView {
                Button(action: {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                        layoutModeRaw = isGridMode ? "canvas" : "grid"
                        APHaptic.trigger()
                    }
                }) {
                    Image(systemName: isGridMode ? "rectangle.on.rectangle.angled" : "square.grid.2x2")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(isGridMode ? .appAccent : .textPrimary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isGridMode ? "table_layout_mode_canvas".t : "table_layout_mode_grid".t)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.appSurfaceHigh.opacity(0.6))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.appBorderSubtle, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var findTableCompactButton: some View {
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
                        Text(LocalizationManager.shared.t("table_find_item_template", table.tableNumber, table.capacity))
                    }
                }
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(isMovementLocked ? .textSecondary.opacity(0.4) : .appAccent)
                    .frame(width: 32, height: 32)
                    .background(Color.clear)
                    .contentShape(Rectangle())
            }
            .disabled(isMovementLocked)
        }
    }

    @ViewBuilder
    private var printQRCodesCompactButton: some View {
        Button(action: {
            showingBatchQRSheet = true
            APHaptic.trigger()
        }) {
            Image(systemName: "qrcode")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.textPrimary)
                .frame(width: 32, height: 32)
                .background(Color.clear)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var lockPanZoomCompactButton: some View {
        Button(action: {
            isMovementLocked.toggle()
            APHaptic.trigger()
        }) {
            Image(systemName: isMovementLocked ? "lock.fill" : "lock.open.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(isMovementLocked ? .appRose : .textSecondary)
                .frame(width: 32, height: 32)
                .background(isMovementLocked ? Color.appRose.opacity(0.12) : Color.clear)
                .cornerRadius(6)
                .scaleEffect(isMovementLocked ? 1.05 : 1.0)
                .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isMovementLocked)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var editLayoutSwitchCompactButton: some View {
        Button(action: {
            let currentEdit = isEditingLayout
            if !currentEdit {
                checkManagerPermission(for: .toggleEditLayout(true))
            } else {
                isEditingLayout = false
                Task {
                    await SyncEngine.shared.syncAll(modelContext: modelContext)
                }
            }
            APHaptic.trigger()
        }) {
            Image(systemName: isEditingLayout ? "pencil.and.outline" : "pencil")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(isEditingLayout ? .appAccent : .textSecondary)
                .frame(width: 32, height: 32)
                .background(isEditingLayout ? Color.appAccent.opacity(0.12) : Color.clear)
                .cornerRadius(6)
                .scaleEffect(isEditingLayout ? 1.05 : 1.0)
                .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isEditingLayout)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isEditingLayout ? "table_exit_edit_mode_acc".t : "table_enter_edit_mode_acc".t)
    }

    @ViewBuilder
    private func compactHeader(showsSidebarButton: Bool, width: CGFloat) -> some View {
        VStack(spacing: 8) {
            if width < 600 {
                // iPhone Layout:
                // Row 1: Sidebar Toggle + Status Badges (no labels) + Quick Actions
                HStack(spacing: 0) {
                    if showsSidebarButton {
                        sidebarToggleButton
                        Spacer(minLength: 8)
                    }
                    modernStatusWidget(showLabels: false)
                        .layoutPriority(1)
                    Spacer(minLength: 8)
                    quickActionsBar
                        .layoutPriority(1)
                }
                
                // Row 2: Floor & Zone Pickers (Horizontal Scroll)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        customFloorPicker
                        customZonePicker
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 1)
                }
            } else {
                // iPad Portrait / Landscape with Sidebar Open Layout:
                // Row 1: Sidebar Toggle + Title + Floor & Zone Pickers + Quick Actions
                HStack(spacing: 0) {
                    if showsSidebarButton {
                        sidebarToggleButton
                        Spacer(minLength: 10)
                    }
                    
                    headerTitleView
                        .layoutPriority(3)
                    
                    Spacer(minLength: 12)
                    
                    HStack(spacing: 12) {
                        customFloorPicker
                        customZonePicker
                    }
                    .layoutPriority(2)
                    
                    Spacer(minLength: 12)
                    
                    quickActionsBar
                        .layoutPriority(1)
                }
                
                // Row 2: Status Badges (Left Aligned, With Labels)
                HStack {
                    modernStatusWidget(showLabels: true)
                    Spacer()
                }
            }
        }
    }

    @ViewBuilder
    private func wideHeader(showsSidebarButton: Bool) -> some View {
        HStack(alignment: .center, spacing: 0) {
            if showsSidebarButton {
                sidebarToggleButton
                Spacer(minLength: 12)
            }

            // ── Left: Page Title & Icon ──
            headerTitleView
                .layoutPriority(3)

            Spacer(minLength: 16)

            // ── Center-Left: Floor + Zone pickers ──
            HStack(spacing: 12) {
                customFloorPicker
                customZonePicker
            }
            .layoutPriority(2)

            Spacer(minLength: 16)

            // ── Center-Right: Status badges ──
            modernStatusWidget(showLabels: true)
                .layoutPriority(1)

            Spacer(minLength: 16)

            // ── Right: Action buttons ──
            quickActionsBar
                .layoutPriority(1)
        }
        .frame(maxWidth: .infinity)
    }

    private var sidebarToggleButton: some View {
        Button {
            APHaptic.trigger()
            withAnimation(.easeInOut(duration: 0.2)) {
                columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
            }
        } label: {
            Image(systemName: "sidebar.left")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.textPrimary)
                .frame(width: 34, height: 34)
                .background(Color.appSurfaceHigh.opacity(0.6))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.appBorderSubtle, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(columnVisibility == .detailOnly ? "Show sidebar" : "Hide sidebar")
    }

    private var headerTitleView: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.appAccent.opacity(0.15))
                    .frame(width: 28, height: 28)
                Image(systemName: "tablecells.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.appAccent)
            }
            Text("table_management_title".t)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.appAccent.opacity(0.06))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.appAccent.opacity(0.15), lineWidth: 1)
        )
    }
    
    // MARK: - Active Service Requests Overlay
    
    @ViewBuilder
    private var activeRequestsOverlay: some View {
        HStack {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "bell.badge.fill")
                        .foregroundColor(.appAccent)
                    Text("table_service_requests_title".t)
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
                Text(LocalizationManager.shared.t("table_number_template", request.tableNumber))
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
    @EnvironmentObject private var lm: LocalizationManager
    @EnvironmentObject private var sessionManager: AppSessionManager
    @Bindable var table: RestaurantTable
    @Environment(\.dismiss) private var dismiss
    
    @Binding var selectedTab: MainDashboardView.DashboardTab
    @Binding var posTableSession: TableSession?
    
    @Query(sort: \RestaurantTable.tableNumber) private var allTables: [RestaurantTable]
    @Query(filter: #Predicate<RegisterSession> { $0.closedAt == nil && !$0.isDeleted })
    private var activeRegisterSessions: [RegisterSession]
    
    @State private var dynamicQRUrl: String = ""
    @State private var showingQRPopover = false
    @State private var editingCapacity = false
    @State private var tempCapacity: String = ""
    @State private var showNoActiveShiftAlert = false
    
    @AppStorage("logged_in_email") private var loggedInEmail = "owner@alphapos.com"
    @State private var showingManagerPinSheet = false
    
    private func deleteTableWithAuth() {
        if sessionManager.can(.managerOverride) {
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
    
    private func updateTableZone(_ newZone: String) {
        table.zone = newZone
        table.isSynced = false
        table.updatedAt = Date()
        try? modelContext.save()
        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }
    
    var activeSession: TableSession? {
        let leader = table.joinedParent ?? table
        if let session = leader.sessions.first(where: { $0.isActive }) {
            if Calendar.current.isDateInToday(session.startedAt) {
                return session
            }
        }
        return nil
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
                            let activeSession = leader.sessions.first(where: { $0.isActive && Calendar.current.isDateInToday($0.startedAt) })
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
                            
                            Text(LocalizationManager.shared.t("table_number_template", table.tableNumber))
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.textPrimary)
                            
                            HStack(spacing: 12) {
                                Label("table_capacity_lbl".t, systemImage: "chair.lounge.fill")
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
                                    
                                    Button("done".t) { editingCapacity = false }
                                        .font(.caption)
                                        .foregroundColor(.appAccent)
                                } else {
                                    Text("\(table.capacity) \("table_seats_sub".t.lowercased())")
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
                            
                            HStack(spacing: 12) {
                                Label("table_zone_lbl".t, systemImage: "rectangle.3.group")
                                    .font(.subheadline)
                                    .foregroundColor(.textSecondary)
                                
                                Menu {
                                    Button("table_zone_indoor".t) { updateTableZone("Indoor") }
                                    Button("table_zone_outdoor".t) { updateTableZone("Outdoor") }
                                    Button("table_zone_rooftop".t) { updateTableZone("Rooftop") }
                                } label: {
                                    HStack(spacing: 4) {
                                        Text("table_zone_\((table.zone ?? "Indoor").lowercased())".t)
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.appAccent)
                                        Image(systemName: "chevron.down")
                                            .font(.caption2)
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
                                Text("table_grouping_title".t)
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.appAccent)
                                    .tracking(1.0)
                                
                                if let parent = table.joinedParent {
                                    HStack {
                                        Label(LocalizationManager.shared.t("table_combined_with_template", parent.tableNumber), systemImage: "link")
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
                                            Text("table_split_btn".t)
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
                                            Text(LocalizationManager.shared.t("table_combined_group_template", table.tableNumber) + " + " + table.joinedChildren.map { "T\($0.tableNumber)" }.joined(separator: ", "))
                                                .font(.caption)
                                                .foregroundColor(.textPrimary)
                                            
                                            ForEach(table.joinedChildren) { child in
                                                HStack {
                                                    Label(LocalizationManager.shared.t("table_number_template", child.tableNumber), systemImage: "link")
                                                        .font(.caption)
                                                        .foregroundColor(.textSecondary)
                                                    Spacer()
                                                    Button("table_split_btn".t) {
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
                                                        Text(LocalizationManager.shared.t("table_find_item_template", targetTable.tableNumber, targetTable.capacity))
                                                    }
                                                }
                                            } label: {
                                                HStack {
                                                    Image(systemName: "plus.circle")
                                                    Text("table_combine_with_btn".t)
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
                                            Text("table_no_vacant_combine_hint".t)
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
                                    Text("table_active_dining_session".t)
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundColor(.appAccent)
                                        .tracking(1.0)
                                    
                                    HStack(spacing: 12) {
                                        Label("table_started_at_lbl".t, systemImage: "clock")
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
                                            if activeRegisterSessions.isEmpty {
                                                showNoActiveShiftAlert = true
                                                return
                                            }
                                            posTableSession = session
                                            selectedTab = .pos
                                            dismiss()
                                        }) {
                                            Text("table_place_order_btn".t)
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
                                            Text("table_checkout_btn".t)
                                                .frame(maxWidth: .infinity)
                                        }
                                        .apGradientButton(gradient: APGradient.destructive, shadow: APShadow.destructiveGlow)
                                    }
                                    .padding(.top, 4)
                                } else {
                                    Text("table_actions_title".t)
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundColor(.appAccent)
                                        .tracking(1.0)
                                    
                                    VStack(spacing: 10) {
                                        Button(action: {
                                            if activeRegisterSessions.isEmpty {
                                                showNoActiveShiftAlert = true
                                                return
                                            }
                                            startNewSession()
                                        }) {
                                            Text("table_start_session_btn".t)
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
                                                Text("table_reserve_btn".t)
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
                                                Text("table_vacant_btn".t)
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
                                                Text("table_delete_btn".t)
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
            .navigationTitle("table_details_title".t)
            .apNavBar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("close_btn".t) { dismiss() }
                        .foregroundColor(.textPrimary)
                }
            }
            .alert("table_qr_sim_title".t, isPresented: $showingQRPopover) {
                Button("done".t, role: .cancel) { }
            } message: {
                Text(LocalizationManager.shared.t("table_qr_sim_message_template", table.tableNumber, dynamicQRUrl))
            }
            .sheet(isPresented: $showingManagerPinSheet) {
                ManagerPINVerificationSheet(
                    isPresented: $showingManagerPinSheet,
                    onSuccess: {
                        performDelete()
                    }
                )
            }
            .alert("Cash Drawer is Locked", isPresented: $showNoActiveShiftAlert) {
                Button("go_to_cash_drawer".t) {
                    selectedTab = .cashDrawer
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("pos_shift_required_hint".t)
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
    TableView(selectedTab: .constant(.tables), activeSession: .constant(nil), columnVisibility: .constant(.all))
        .modelContainer(for: [RestaurantTable.self, TableSession.self], inMemory: true)
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Redesigned Dynamic Restaurant Table Component
// ─────────────────────────────────────────────────────────────────────────────

struct DynamicTableLayoutView: View {
    let tableNumber: String
    let capacity: Int
    var isRound: Bool = false
    let status: String
    let isEditingLayout: Bool
    let isDragging: Bool
    let isSelected: Bool
    let statusColor: Color
    var joinedParentNumber: String? = nil
    var isGroupLeader: Bool = false
    var itemCount: Int = 0
    var table: RestaurantTable? = nil

    // Seat dimensions
    private let chairWidth: CGFloat = 24
    private let chairHeight: CGFloat = 13
    private let chairCornerRadius: CGFloat = 4.0
    private let chairGap: CGFloat = 6
    private let roundTableMinDiam: CGFloat = 82
    private let roundTableChairRadiusFactor: CGFloat = 18


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
    
    @ViewBuilder
    var body: some View {
        if isRound {
            roundLayout
        } else {
            rectangularLayout
        }
    }

    // ── Round Table Layout ──
    private var roundLayout: some View {
        let tableDiam = max(roundTableMinDiam, CGFloat(capacity) * roundTableChairRadiusFactor + 30)
        let chairRadius = tableDiam / 2 + chairHeight / 2 + chairGap
        let effectiveCount = max(capacity, 1)

        return ZStack {
            tableContent
                .frame(width: tableDiam, height: tableDiam)
                .background(
                    Circle()
                        .fill(Color.appSurface)
                        .overlay(Circle().stroke(
                            isSelected ? Color.appAccent : (isDragging ? statusColor.opacity(0.8) : Color.appBorderSubtle),
                            lineWidth: isSelected ? 2.5 : (isDragging ? 2.0 : 1.2)
                        ))
                )
                .overlay(itemBadge)
                .shadow(
                    color: isSelected ? Color.appAccent.opacity(0.4) : (isDragging ? statusColor.opacity(0.4) : Color.black.opacity(0.12)),
                    radius: isSelected ? 14 : (isDragging ? 12 : 5),
                    x: 0,
                    y: isSelected ? 4 : (isDragging ? 8 : 2)
                )
                .scaleEffect(isSelected ? 1.05 : 1.0)
                .animation(.spring(response: 0.35, dampingFraction: 0.78), value: isSelected)

            ForEach(0..<effectiveCount, id: \.self) { idx in
                let angle = 2 * .pi * CGFloat(idx) / CGFloat(effectiveCount) - .pi / 2
                chairView(width: chairWidth, height: chairHeight, side: .top)
                    .rotationEffect(.radians(Double(angle + .pi / 2)))
                    .offset(
                        x: chairRadius * cos(angle),
                        y: chairRadius * sin(angle)
                    )
            }
        }
    }

    // ── Rectangular Table Layout ──
    private var rectangularLayout: some View {
        let leftCount = capacity >= 3 ? 1 : 0
        let rightCount = capacity >= 4 ? 1 : 0
        let remaining = capacity - leftCount - rightCount
        let topCount = (remaining + 1) / 2
        let bottomCount = remaining / 2
        
        let tableWidth = max(76, CGFloat(max(topCount, bottomCount)) * 40 + 20)
        let tableHeight: CGFloat = 70
        
        return ZStack {
            tableContent
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
                .overlay(itemBadge)
                .shadow(
                    color: isSelected ? Color.appAccent.opacity(0.4) : (isDragging ? statusColor.opacity(0.4) : Color.black.opacity(0.12)),
                    radius: isSelected ? 14 : (isDragging ? 12 : 5),
                    x: 0,
                    y: isSelected ? 4 : (isDragging ? 8 : 2)
                )
                .scaleEffect(isSelected ? 1.05 : 1.0)
                .animation(.spring(response: 0.35, dampingFraction: 0.78), value: isSelected)
            
            if leftCount > 0 {
                chairView(width: chairHeight, height: chairWidth, side: .left)
                    .offset(x: -(tableWidth / 2 + chairHeight / 2 + chairGap), y: 0)
            }

            if rightCount > 0 {
                chairView(width: chairHeight, height: chairWidth, side: .right)
                    .offset(x: tableWidth / 2 + chairHeight / 2 + chairGap, y: 0)
            }

            if topCount > 0 {
                ForEach(0..<topCount, id: \.self) { idx in
                    let offset = xOffsetForIndex(idx, count: topCount, totalWidth: tableWidth)
                    chairView(width: chairWidth, height: chairHeight, side: .top)
                        .offset(x: offset, y: -(tableHeight / 2 + chairHeight / 2 + chairGap))
                }
            }

            if bottomCount > 0 {
                ForEach(0..<bottomCount, id: \.self) { idx in
                    let offset = xOffsetForIndex(idx, count: bottomCount, totalWidth: tableWidth)
                    chairView(width: chairWidth, height: chairHeight, side: .bottom)
                        .offset(x: offset, y: tableHeight / 2 + chairHeight / 2 + chairGap)
                }
            }
        }
    }

    // Shared table content (label, status, elapsed, link info)
    private var tableContent: some View {
        VStack(spacing: 4) {
            Text(formattedTableNumber)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.textPrimary)
                .lineLimit(1)
            
            Text("table_status_\(status.lowercased())".t.uppercased())
                .font(.system(size: 8, weight: .heavy))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .foregroundColor(statusColor)
                .background(statusColor.opacity(0.12))
                .cornerRadius(4)

            if status.lowercased() == "occupied", let table = table {
                let elapsedMin = table.elapsedMinutes
                Text("\(elapsedMin) \("time_minutes".t.lowercased())")
                    .padding(.vertical, 1)
                    .padding(.horizontal, 3)
                    .background(Color.appSurfaceHigh.opacity(0.6))
                    .cornerRadius(2)
                    .font(.system(size: 7, weight: .semibold, design: .monospaced))
                    .foregroundColor(.textSecondary)
            }

            if isEditingLayout {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 8))
                    .foregroundColor(.appAccent)
            }
            
            if let parent = joinedParentNumber {
                HStack(spacing: 2) {
                    Image(systemName: "link")
                        .font(.system(size: 6))
                    Text(LocalizationManager.shared.t("table_joined_to_template", parent))
                        .font(.system(size: 6, weight: .bold))
                }
                .foregroundColor(.textSecondary)
                .padding(.top, 1)
            } else if isGroupLeader {
                HStack(spacing: 2) {
                    Image(systemName: "link")
                        .font(.system(size: 6))
                    Text("table_leader_badge".t)
                        .font(.system(size: 6, weight: .bold))
                }
                .foregroundColor(.appTeal)
                .padding(.top, 1)
            }
        }
    }

    // Item count badge (top-right)
    @ViewBuilder
    private var itemBadge: some View {
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
        ChairShapeView(side: ChairShapeView.Side(side), color: statusColor)
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
        let activeSession = leader.sessions.first(where: { $0.isActive && Calendar.current.isDateInToday($0.startedAt) })
        let itemCount = activeSession?.orders.reduce(0) { total, order in
            total + order.items.reduce(0) { subtotal, item in subtotal + item.quantity }
        } ?? 0
        
        DynamicTableLayoutView(
            tableNumber: table.tableNumber,
            capacity: table.capacity,
            isRound: table.isRound,
            status: table.status,
            isEditingLayout: isEditingLayout,
            isDragging: isDragging,
            isSelected: isSelected,
            statusColor: statusCol,
            joinedParentNumber: table.joinedParent?.tableNumber,
            isGroupLeader: !table.joinedChildren.isEmpty,
            itemCount: itemCount,
            table: table
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
        .accessibilityLabel("Table \(table.tableNumber), \(table.status), \(table.capacity) guests")
        .accessibilityHint("Double-tap to open table")
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
        
        let tableDragGesture = DragGesture(minimumDistance: 2, coordinateSpace: .global)
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
    @EnvironmentObject private var lm: LocalizationManager
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.grid.3x3.fill")
                .font(.system(size: 44))
                .foregroundColor(.textTertiary)
            Text("table_empty_canvas_title".t)
                .font(.headline)
                .foregroundColor(.textSecondary)
            Text("table_empty_canvas_subtitle".t)
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
