
import SwiftUI
import SwiftData
import PhotosUI
import CryptoKit
import UIKit

struct TableView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var lm: LocalizationManager
    @EnvironmentObject private var sessionManager: AppSessionManager
    @Query(sort: \RestaurantTable.tableNumber) private var tables: [RestaurantTable]
    @Query(sort: \FloorData.sortOrder) private var allFloors: [FloorData]
    @Query(sort: \Branch.name) private var allBranches: [Branch]

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
    /// True while pan/pinch is in progress — freezes viewport culling & kills implicit animations for 60fps tracking.
    @State private var isCanvasGesturing: Bool = false
    @State private var isMovementLocked: Bool = false
    @State private var gestureScale: CGFloat = 1.0
    @State private var focusTableId: UUID? = nil
    @State private var bounceTableId: UUID? = nil
    @State private var gridFocusTableId: UUID? = nil
    @State private var gridHighlightedTableId: UUID? = nil
    @State private var headerWidth: CGFloat = 0
    @State private var searchTablesList: [RestaurantTable] = []
    /// Selected table while editing layout (shows resize bounding box + corner handles).
    @State private var layoutSelectedTableId: UUID? = nil
    @State private var layoutSelectedTableIds: Set<UUID> = []
    @State private var activeResizeCorner: TableResizeCorner? = nil
    @State private var liveLayoutScale: CGFloat? = nil
    @State private var liveLayoutOriginDelta: CGSize = .zero

    /// Must match the drawn floor-plan grid spacing (see Canvas grid below).
    private static let layoutGridSize: CGFloat = 20
    /// Soft magnet distance in canvas points (Canvas mode only).
    private static let canvasSnapThreshold: CGFloat = 10
    private static let minLayoutScale: CGFloat = 0.5
    private static let maxLayoutScale: CGFloat = 2.5
    @ObservedObject private var syncEngine = SyncEngine.shared

    @Query(filter: #Predicate<RegisterSession> { $0.closedAt == nil && !$0.isDeleted })
    private var activeRegisterSessions: [RegisterSession]
    @State private var showNoActiveShiftAlert = false
    /// Prevents multiple tap/accessibility events from opening the same table
    /// concurrently while its SwiftData session is being created.
    @State private var openingTableIds: Set<UUID> = []
    @State private var tableOpenError: String?

    @Query(sort: \FloorPlanImage.updatedAt) private var floorPlanImages: [FloorPlanImage]
    @Query(sort: \TableLayoutPreset.name) private var layoutPresets: [TableLayoutPreset]
    @State private var showingSavePresetAlert = false
    @State private var presetNameInput = ""
    @State private var presetOperationError: String?
    @State private var isPresetOperationRunning = false

    @AppStorage("logged_in_email") private var loggedInEmail = "owner@alphapos.com"

    private var activeCashierDisplayName: String {
        let staffName = sessionManager.currentStaffSession?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !staffName.isEmpty { return staffName }
        return UserDefaults.standard.string(forKey: "logged_in_name") ?? "Staff"
    }
    /// Reads UserDefaults override first, then falls back to Config.plist LOCAL_SERVER_URL.
    private var customerWebBaseUrl: String {
        let ud = UserDefaults.standard.string(forKey: "dynamic_customer_web_url") ?? ""
        return ud.isEmpty ? "https://sync.alphaposweb.com" : ud
    }
    @State private var isLayoutManagerAuthorized = false
    // MARK: - Layout & View Mode
    @AppStorage("table_layout_mode") private var layoutModeRaw: String = "canvas"
    @AppStorage("table_view_mode") private var tableViewModeRaw: String = "map"
    // MARK: - Dynamic Floors
    @AppStorage(BranchContext.storageKey) private var activeBranchId = ""
    private var floors: [FloorData] {
        let branchKey = activeBranchId.lowercased()
        let candidates = allFloors
            .filter { !$0.isDeleted && $0.isActive && $0.branchId.lowercased() == branchKey }
            .sorted {
                if $0.floorNumber == $1.floorNumber, $0.isSynced != $1.isSynced {
                    return $0.isSynced
                }
                return $0.sortOrder == $1.sortOrder
                    ? $0.floorNumber < $1.floorNumber
                    : $0.sortOrder < $1.sortOrder
            }

        // UUID strings are case-insensitive. Older builds compared them as raw
        // strings and could create a second local "Floor 1" for the same branch.
        // Keep one canonical area per floor number, preferring the synced area.
        var seenFloorNumbers = Set<Int>()
        return candidates.filter { seenFloorNumbers.insert($0.floorNumber).inserted }
    }
    private var selectedDiningAreaId: UUID? {
        floors.first(where: { $0.floorNumber == selectedFloor })?.uuid
    }
    private var activeDiningAreaIds: Set<UUID> { Set(floors.map(\.uuid)) }

    private func tableBelongsToActiveBranch(_ table: RestaurantTable) -> Bool {
        if !table.branchId.isEmpty { return table.branchId.caseInsensitiveCompare(activeBranchId) == .orderedSame }
        if let floorId = table.floorId { return activeDiningAreaIds.contains(floorId) }
        return true // one-release legacy bridge; repaired on the next sync
    }

    private func tableBelongsToSelectedArea(_ table: RestaurantTable) -> Bool {
        guard let diningAreaId = selectedDiningAreaId else { return false }
        if let floorId = table.floorId { return floorId == diningAreaId }
        return tableBelongsToActiveBranch(table) && (table.floor ?? 1) == selectedFloor
    }
    // Floor edit state
    @State private var showingAddFloorAlert = false
    @State private var showingRenameFloorAlert = false
    @State private var renamingFloorId: Int? = nil
    @State private var floorNameInput: String = ""
    @State private var showingRemoveFloorConfirm = false
    @State private var showingDeleteTableConfirm = false
    @State private var pendingDeletionTableIds: Set<UUID> = []
    @State private var optimisticallyDeletedTableIds: Set<UUID> = []
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var cachedFloorPlanImage: UIImage? = nil
    @State private var floorPlanLoadTask: Task<Void, Never>?
    @State private var showingManagerPinSheet = false
    @State private var showingQuickClearPinSheet = false
    @State private var pendingQuickClearTableId: UUID?
    @State private var showingQuickClearReasonPrompt = false
    @State private var quickClearReasonText = ""
    @State private var quickClearError: String?
    @State private var showingQuickClearVacantConfirm = false
    @State private var pendingVacantClearTable: RestaurantTable? = nil
    @State private var showingBatchQRSheet = false
    @State private var isOpeningBatchQR = false
    @State private var pendingAuthAction: AuthAction? = nil
    // L-1: Waitlist
    @State private var showingWaitlist = false

    private var pendingVacantTableNumber: String {
        (pendingVacantClearTable?.joinedParent ?? pendingVacantClearTable)?.tableNumber ?? ""
    }

    private var isTableOpenErrorPresented: Binding<Bool> {
        Binding(
            get: { tableOpenError != nil },
            set: { if !$0 { tableOpenError = nil } }
        )
    }

    private var isPresetOperationErrorPresented: Binding<Bool> {
        Binding(
            get: { presetOperationError != nil },
            set: { if !$0 { presetOperationError = nil } }
        )
    }

    @ViewBuilder
    private var floorPlanMainContent: some View {
        ZStack(alignment: .bottomTrailing) {
            if isListView {
                VStack(spacing: 0) {
                    if isEditingLayout {
                        gridEditToolbar
                    }
                    tableListView
                }
            } else if isGridMode {
                VStack(spacing: 0) {
                    if isEditingLayout {
                        gridEditToolbar
                    }
                    tableGridView
                }
            } else {
                VStack(spacing: 0) {
                    if isEditingLayout {
                        canvasEditToolbar
                    }
                    floorPlanCanvas
                }
            }

            if !isListView && !isGridMode {
                floatingControlsPanel
                    .padding(20)
            }

            if !activeRequestsForSelectedArea.isEmpty {
                activeRequestsOverlay
            }
        }
    }

    enum AuthAction {
        case toggleEditLayout(Bool)
        case addTable
        case deleteTable
    }

    var body: some View {
        // Outer GeometryReader measures available width before rendering header.
        GeometryReader { outerGeo in
            ZStack {
                Color.appBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    floorPlanMainContent
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("")
            .apNavBar()
            .onAppear(perform: handleTableViewAppear)
            .onReceive(NotificationCenter.default.publisher(for: .openAddFirstTableNotification)) { _ in
                presentPendingAddFirstTableIfNeeded()
            }
            .onChange(of: tables, tableDataDidChange)
            .onChange(of: allBranches) { _, _ in resolveActiveBranchIfNeeded() }
            .onChange(of: selectedFloor) { selectedFloorDidChange() }
            .onChange(of: activeBranchId) { _, _ in activeBranchDidChange() }
            .onChange(of: floorPlanImages) { loadCachedFloorPlanImage() }
            .toolbar(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    tableContextBar
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    if isEditingLayout {
                        headerEditModeBadge
                    } else {
                        modernStatusWidget
                            .layoutPriority(2)
                    }
                    tableActionsMenu
                }
            }
            .sheet(item: $selectedTable) { table in
                TableDetailView(
                    table: table,
                    selectedTab: $selectedTab,
                    posTableSession: $activeSession,
                    allowsDeletion: isEditingLayout
                )
                    .presentationDetents([.height(500), .large])
                    .presentationDragIndicator(.visible)
            }
            .alert("Cash Drawer is Locked", isPresented: $showNoActiveShiftAlert) {
                Button("go_to_cash_drawer".t) {
                    selectedTab = .cashDrawer
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("pos_shift_required_hint".t)
            }
            .alert("ไม่สามารถเปิดโต๊ะได้", isPresented: isTableOpenErrorPresented) {
                Button("ok_btn".t) { tableOpenError = nil }
            } message: {
                Text(tableOpenError ?? "")
            }
            .alert("Template Error", isPresented: isPresetOperationErrorPresented) {
                Button("ok_btn".t) { presetOperationError = nil }
            } message: {
                Text(presetOperationError ?? "")
            }
            .sheet(isPresented: $showingAddTableSheet, onDismiss: {
                if !isEditingLayout { isLayoutManagerAuthorized = false }
            }) {
                AddTableSheet(isPresented: $showingAddTableSheet, modelContext: modelContext, defaultFloor: selectedFloor)
            }
            .confirmationDialog("table_delete_confirm".t, isPresented: $showingDeleteTableConfirm, titleVisibility: .visible) {
                Button("table_delete_btn".t, role: .destructive) {
                    checkManagerPermission(for: .deleteTable)
                }
                Button("cancel".t, role: .cancel) {
                    pendingDeletionTableIds.removeAll()
                }
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
                        pendingDeletionTableIds.removeAll()
                    }
                )
            }
            .sheet(isPresented: $showingQuickClearPinSheet) {
                ManagerPINVerificationSheet(
                    isPresented: $showingQuickClearPinSheet,
                    onSuccess: {
                        guard pendingQuickClearTableId != nil else { return }
                        quickClearReasonText = ""
                        showingQuickClearReasonPrompt = true
                    },
                    onDismiss: {
                        if !showingQuickClearReasonPrompt {
                            pendingQuickClearTableId = nil
                        }
                    }
                )
            }
            .modifier(QuickClearDialogsModifier(
                isVacantConfirmPresented: $showingQuickClearVacantConfirm,
                pendingVacantTableNumber: pendingVacantTableNumber,
                onConfirmVacant: {
                    if let table = pendingVacantClearTable {
                        pendingVacantClearTable = nil
                        performQuickClearVacant(table)
                    }
                },
                onCancelVacant: {
                    pendingVacantClearTable = nil
                },
                isReasonPresented: $showingQuickClearReasonPrompt,
                reason: $quickClearReasonText,
                error: $quickClearError,
                onConfirmVoid: { reason in
                    guard let id = pendingQuickClearTableId,
                          let table = tables.first(where: { $0.id == id }) else { return }
                    pendingQuickClearTableId = nil
                    performQuickVoidAndClear(table, reason: reason)
                },
                onCancelVoid: {
                    pendingQuickClearTableId = nil
                }
            ))
            .fullScreenCover(isPresented: $showingBatchQRSheet, onDismiss: {
                isOpeningBatchQR = false
            }) {
                BatchQRCodePrintView(tables: tables)
            }
            .overlay {
                if isOpeningBatchQR && !showingBatchQRSheet {
                    ZStack {
                        Color.black.opacity(0.28)
                            .ignoresSafeArea()
                        VStack(spacing: 14) {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(1.2)
                                .tint(.appAccent)
                            Text("table_qr_preparing_lbl".t)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.textPrimary)
                        }
                        .padding(.horizontal, 28)
                        .padding(.vertical, 22)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
                    }
                    .transition(.opacity)
                    .allowsHitTesting(true)
                }
            }
            // L-1: Waitlist sheet
            .sheet(isPresented: $showingWaitlist) {
                WaitlistView()
            }
        }
    }

    @ViewBuilder
    private var floorPlanCanvas: some View {
        let floorTables = visibleTablesForSelection
        let canvasSize = getCanvasSize()

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
                        let gridSize = Self.layoutGridSize
                        let path = Path { path in
                            for x in stride(from: 0, to: canvasSize.width, by: gridSize) {
                                path.move(to: CGPoint(x: x, y: 0))
                                path.addLine(to: CGPoint(x: x, y: canvasSize.height))
                            }
                            for y in stride(from: 0, to: canvasSize.height, by: gridSize) {
                                path.move(to: CGPoint(x: 0, y: y))
                                path.addLine(to: CGPoint(x: canvasSize.width, y: y))
                            }
                        }
                        let gridColor = isEditingLayout ? Color.appAccent : Color.appDivider
                        let gridOpacity: CGFloat = isEditingLayout ? 0.28 : (isGridMode ? 0.25 : 0.12)
                        context.stroke(path, with: .color(gridColor.opacity(gridOpacity)), lineWidth: isEditingLayout ? 1 : (isGridMode ? 0.8 : 0.6))
                    }
                    .frame(width: canvasSize.width, height: canvasSize.height)
                    .allowsHitTesting(false)

                    // Render filtered tables with Viewport Culling.
                    // During pan/pinch, skip culling so ForEach does not insert/remove
                    // complex table cards mid-gesture (that churn tanks frame rate).
                    let visibleFloorTables: [RestaurantTable] = {
                        if isCanvasGesturing { return floorTables }
                        return floorTables.filter { table in
                            isTableVisible(
                                table,
                                viewportSize: viewport.size,
                                zoomScale: zoomScale,
                                gestureScale: gestureScale,
                                panOffset: panOffset,
                                activePanOffset: activePanOffset
                            )
                        }
                    }()
                    // C-1 FIX: Wrap each card in .equatable() so SwiftUI skips body
                    // evaluation when InteractiveTableCardWrapper's == returns true.
                    // This means @Query re-renders only reach cards whose data changed.
                    ForEach(visibleFloorTables) { table in
                        InteractiveTableCardWrapper(
                            table: table,
                            isEditingLayout: isEditingLayout,
                            activeDraggingTableId: activeDraggingTableId,
                            selectedTableId: selectedTable?.id,
                            layoutSelectedTableId: layoutSelectedTableId,
                            isMultiSelected: layoutSelectedTableIds.contains(table.id),
                            dragTranslation: dragTranslation,
                            liveLayoutScale: liveLayoutScale,
                            liveLayoutOriginDelta: liveLayoutOriginDelta,
                            activeResizeCorner: activeResizeCorner,
                            canvasZoom: totalCanvasZoom,
                            isBouncing: bounceTableId == table.id,
                            onTap: {
                                if isEditingLayout {
                                    if layoutSelectedTableIds.contains(table.id) {
                                        layoutSelectedTableIds.remove(table.id)
                                        if layoutSelectedTableId == table.id {
                                            layoutSelectedTableId = layoutSelectedTableIds.first
                                        }
                                    } else {
                                        layoutSelectedTableIds.insert(table.id)
                                        layoutSelectedTableId = table.id
                                    }
                                    APHaptic.trigger()
                                    return
                                }
                                openTableForOrdering(table)
                            },
                            onLongPress: {
                                if !isEditingLayout {
                                    selectedTable = table.joinedParent ?? table
                                    showingDetailSheet = true
                                    APHaptic.trigger()
                                }
                            },
                            onClear: { requestQuickClear(table) },
                            onDragChanged: { val in handleDragChanged(value: val, for: table) },
                            onDragEnded: { val in handleDragEnded(value: val, for: table) },
                            onResizeChanged: { corner, val in handleResizeChanged(corner: corner, value: val, for: table) },
                            onResizeEnded: { corner, val in handleResizeEnded(corner: corner, value: val, for: table) }
                        )
                        .equatable()
                    }
                }
                .frame(width: canvasSize.width, height: canvasSize.height)
                .background(isEditingLayout ? Color(red: 0.925, green: 0.95, blue: 1.0) : Color.appSurface)
                .scaleEffect(zoomScale * gestureScale, anchor: .topLeading)
                .offset(CGSize(width: panOffset.width + activePanOffset.width, height: panOffset.height + activePanOffset.height))
                // Kill implicit animations on transform so pan/pinch tracks the finger 1:1.
                .transaction { txn in
                    if isCanvasGesturing || activeDraggingTableId != nil {
                        txn.animation = nil
                    }
                }
            }
            .frame(width: viewport.size.width, height: viewport.size.height, alignment: .topLeading)
            .background(isEditingLayout ? Color(red: 0.925, green: 0.95, blue: 1.0) : Color.appSurface)
            .overlay(alignment: .topTrailing) {
                if isEditingLayout {
                    Label("กำลังแก้ไขผัง", systemImage: "cursorarrow.motionlines")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.appAccent)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .apLiquidGlass(tint: Color.appAccent.opacity(0.14), in: Capsule())
                        .padding(14)
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                if isEditingLayout {
                    Rectangle()
                        .stroke(Color.appAccent.opacity(0.34), lineWidth: 1.5)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle()) // Confine touch gestures strictly to the visible viewport
            .onTapGesture {
                var txn = Transaction()
                txn.animation = nil
                withTransaction(txn) {
                    selectedTable = nil
                }
            }
            .gesture(
                (!isMovementLocked && activeDraggingTableId == nil) ?
                DragGesture(minimumDistance: 8) // Keep minimum distance threshold to allow taps to pass through
                    .onChanged { value in
                        var txn = Transaction()
                        txn.animation = nil
                        withTransaction(txn) {
                            isCanvasGesturing = true
                            activePanOffset = value.translation
                        }
                    }
                    .onEnded { value in
                        var txn = Transaction()
                        txn.animation = nil
                        withTransaction(txn) {
                            panOffset.width += value.translation.width
                            panOffset.height += value.translation.height
                            activePanOffset = .zero
                            isCanvasGesturing = false
                        }
                    }
                : nil
            )
            .gesture(
                !isMovementLocked ?
                MagnificationGesture()
                    .onChanged { value in
                        var txn = Transaction()
                        txn.animation = nil
                        withTransaction(txn) {
                            isCanvasGesturing = true
                            gestureScale = value
                        }
                    }
                    .onEnded { value in
                        var txn = Transaction()
                        txn.animation = nil
                        withTransaction(txn) {
                            zoomScale = min(1.5, max(0.5, zoomScale * value))
                            gestureScale = 1.0
                            isCanvasGesturing = false
                        }
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
                        EmptyCanvasOverlayView {
                            checkManagerPermission(for: .addTable)
                        }
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

        }
    }

    // MARK: - Table Grid View
    private var tableGridView: some View {
        let gridTables = visibleTablesForSelection
            .sorted { $0.tableNumber.localizedStandardCompare($1.tableNumber) == .orderedAscending }

        return ScrollViewReader { proxy in
            ScrollView {
                if gridTables.isEmpty {
                    EmptyCanvasOverlayView {
                        checkManagerPermission(for: .addTable)
                    }
                    .frame(maxWidth: .infinity, minHeight: 480)
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 16)],
                        spacing: 16
                    ) {
                        ForEach(gridTables) { table in
                            Button {
                                if isEditingLayout {
                                    toggleLayoutSelection(table)
                                } else {
                                    openTableForOrdering(table)
                                }
                                APHaptic.trigger()
                            } label: {
                                gridTableCard(
                                    table,
                                    isHighlighted: gridHighlightedTableId == table.id
                                        || layoutSelectedTableIds.contains(table.id)
                                )
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                tableQuickActions(table)
                            }
                            .id(table.id)
                            .accessibilityLabel("Table \(table.tableNumber), \(table.status), \(table.capacity) guests")
                        }
                    }
                    .padding(20)
                }
            }
            .onChange(of: gridFocusTableId) { _, id in
                guard let id, gridTables.contains(where: { $0.id == id }) else { return }
                withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                    proxy.scrollTo(id, anchor: .center)
                    gridHighlightedTableId = id
                }
                APHaptic.trigger()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    withAnimation(.easeOut(duration: 0.25)) {
                        if gridHighlightedTableId == id {
                            gridHighlightedTableId = nil
                        }
                    }
                }
                gridFocusTableId = nil
            }
            .background(isEditingLayout ? Color.appAccent.opacity(0.07) : Color.appBackground)
        }
    }

    private func gridTableCard(_ table: RestaurantTable, isHighlighted: Bool) -> some View {
        let leader = table.joinedParent ?? table
        let effectiveStatus = leader.status
        let color = statusColor(effectiveStatus)
        let activeSession = leader.sessions.last(where: { $0.isActive })
        let zoneName = table.zone.flatMap { $0.isEmpty ? nil : $0 } ?? "table_zone_all".t

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(table.tableNumber)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                if isEditingLayout && layoutSelectedTableIds.contains(table.id) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.appAccent)
                }
                listStatusBadge(status: effectiveStatus)
            }

            HStack(spacing: 14) {
                Label("\(table.capacity)", systemImage: "person.2.fill")
                if effectiveStatus.lowercased() == "occupied" {
                    ElapsedTimeView(table: leader)
                }
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.textSecondary)

            Divider().background(Color.appDivider)

            HStack {
                Text(zoneName)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Text(activeSession.map { String(format: "%.0f", $0.totalAmount) } ?? "—")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(activeSession == nil ? Color.textTertiary : Color.appAccent)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 142, alignment: .topLeading)
        .background(
            isEditingLayout && layoutSelectedTableIds.contains(table.id)
                ? Color.appAccent.opacity(0.08)
                : Color.appSurface,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    isHighlighted ? Color.appAccent : color.opacity(0.28),
                    lineWidth: isHighlighted ? 3 : 1
                )
        )
    }

    // MARK: - Table List View
    @ViewBuilder
    private var tableListView: some View {
        let floorTables = visibleTablesForSelection
        let sortedTables = floorTables.sorted { $0.tableNumber < $1.tableNumber }
        let availableCount  = floorTables.filter { $0.status.lowercased() == "vacant" }.count
        let occupiedCount   = floorTables.filter { $0.status.lowercased() == "occupied" }.count
        let reservedCount   = floorTables.filter { $0.status.lowercased() == "reserved" }.count
        let withOrdersCount = floorTables.filter { !$0.sessions.filter({ $0.isActive }).isEmpty }.count
        let totalSeats      = floorTables.reduce(0) { $0 + $1.capacity }

        ZStack {
            (isEditingLayout ? Color.appAccent.opacity(0.07) : Color.appBackground)
                .ignoresSafeArea()
            VStack(spacing: 0) {

                // ── Floor underline tabs ──
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(floors) { floor in
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectFloor(floor.id)
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
                    EmptyCanvasOverlayView {
                        checkManagerPermission(for: .addTable)
                    }
                    Spacer()
                } else {
                    // ── Tip ──
                    HStack {
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundColor(.textTertiary)
                        Text(isEditingLayout
                             ? "แตะแถวเพื่อเลือกหลายโต๊ะสำหรับจัดการ"
                             : "table_list_tip".t)
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
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
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
        let activeSession = (table.joinedParent ?? table).sessions.last(where: { $0.isActive })
        Button(action: {
            if isEditingLayout {
                toggleLayoutSelection(table)
            } else {
                openTableForOrdering(table)
            }
        }) {
            HStack(spacing: 0) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            isEditingLayout && layoutSelectedTableIds.contains(table.id)
                                ? Color.appAccent.opacity(0.14)
                                : Color.appSurfaceHigh
                        )
                        .frame(width: 32, height: 32)
                    Image(systemName: isEditingLayout && layoutSelectedTableIds.contains(table.id)
                          ? "checkmark.circle.fill"
                          : "chair.lounge")
                        .font(.system(size: 14))
                        .foregroundColor(
                            isEditingLayout && layoutSelectedTableIds.contains(table.id)
                                ? .appAccent
                                : .textSecondary
                        )
                }
                .frame(width: 48, alignment: .center)

                // Table name
                VStack(alignment: .leading, spacing: 1) {
                    Text(table.tableNumber)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
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
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.appSurfaceHigh)
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorderSubtle, lineWidth: 1))
                    .frame(width: 100, alignment: .center)

                // Status badge
                listStatusBadge(status: (table.joinedParent ?? table).status)
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
            .background(
                isEditingLayout && layoutSelectedTableIds.contains(table.id)
                    ? Color.appAccent.opacity(0.06)
                    : Color.appSurface
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .contextMenu {
            tableQuickActions(table)
        }
    }

    private func openTableForOrdering(_ table: RestaurantTable) {
        guard !activeRegisterSessions.isEmpty else {
            showNoActiveShiftAlert = true
            return
        }

        let leader = table.joinedParent ?? table
        let group = [leader] + leader.joinedChildren

        // An active session is the source of truth. A delayed table-status pull
        // can temporarily leave the table marked vacant; refusing to reuse its
        // session here allowed a second tap to create a competing session.
        if let session = group
            .flatMap(\.sessions)
            .filter({
                $0.isActive
                    && !$0.isDeleted
                    && Calendar.current.isDateInToday($0.startedAt)
            })
            .sorted(by: { $0.startedAt > $1.startedAt })
            .first {
            if leader.status != "occupied" {
                for member in group {
                    member.status = "occupied"
                    member.isSynced = false
                    member.updatedAt = Date()
                }
                guard modelContext.saveWithLogging(label: "\(Self.self).openTableForOrdering.repairStatus") else {
                    tableOpenError = "ไม่สามารถบันทึกสถานะโต๊ะ \(leader.tableNumber) ได้ กรุณาลองใหม่"
                    return
                }
            }
            activeSession = session
            selectedTab = .pos
            APHaptic.trigger()
            return
        }

        // SwiftUI can deliver both a gesture and an accessibility activation
        // before the first MainActor task has inserted its session.
        guard openingTableIds.insert(leader.id).inserted else { return }

        Task { @MainActor in
            defer { openingTableIds.remove(leader.id) }

            // Re-check after entering the task. This closes the small scheduling
            // window between the synchronous guard above and session insertion.
            if let existingSession = group
                .flatMap(\.sessions)
                .filter({
                    $0.isActive
                        && !$0.isDeleted
                        && Calendar.current.isDateInToday($0.startedAt)
                })
                .sorted(by: { $0.startedAt > $1.startedAt })
                .first {
                activeSession = existingSession
                selectedTab = .pos
                APHaptic.trigger()
                return
            }

            // Local state may say "vacant" even though the server still owns
            // an active session with open orders. The database correctly
            // refuses both closing that session and creating a second active
            // one. Rehydrate and reuse the remote session before attempting a
            // new open.
            if let remoteSessions = try? await NetworkManager.shared.fetchActiveSessions(),
               let remoteSession = remoteSessions.first(where: { row in
                   guard let remoteNumber = row["tableNumber"] as? String else { return false }
                   return SyncEngine.shared.canonicalTableNumber(remoteNumber)
                       == SyncEngine.shared.canonicalTableNumber(leader.tableNumber)
               }) {
                await SyncEngine.shared.pullActiveSessions(modelContext)
                if let restoredSession = group
                    .flatMap(\.sessions)
                    .filter({ $0.isActive && !$0.isDeleted })
                    .sorted(by: { $0.startedAt > $1.startedAt })
                    .first {
                    activeSession = restoredSession
                    selectedTab = .pos
                    APHaptic.trigger()
                    return
                }

                // pullActiveSessions may intentionally reject an old session
                // based on its date, while the database still keeps it active
                // because it owns open orders. Reattach that authoritative
                // token so the cashier can finish and settle those orders.
                let remoteToken = remoteSession["sessionToken"] as? String
                    ?? remoteSession["session_token"] as? String
                    ?? ""
                guard !remoteToken.isEmpty else {
                    tableOpenError = "พบ session ที่ยังเปิดอยู่ของโต๊ะ \(leader.tableNumber) แต่ไม่มี session token"
                    return
                }

                let restoredSession: TableSession
                if let localMatch = group
                    .flatMap(\.sessions)
                    .first(where: { $0.sessionToken == remoteToken }) {
                    restoredSession = localMatch
                    restoredSession.isActive = true
                    restoredSession.isDeleted = false
                    restoredSession.endedAt = nil
                    restoredSession.isSynced = true
                    restoredSession.updatedAt = Date()
                } else {
                    let remoteId = (remoteSession["id"] as? String)
                        .flatMap(UUID.init(uuidString:)) ?? UUID()
                    let startedAtString = remoteSession["created_at"] as? String
                        ?? remoteSession["started_at"] as? String
                        ?? ""
                    let startedAt = NetworkManager.iso8601.date(from: startedAtString) ?? Date()
                    restoredSession = TableSession(
                        id: remoteId,
                        sessionToken: remoteToken,
                        startedAt: startedAt,
                        isActive: true,
                        table: leader,
                        guestCount: remoteSession["guest_count"] as? Int ?? leader.capacity,
                        cashierName: remoteSession["cashier_name"] as? String ?? activeCashierDisplayName,
                        isSynced: true
                    )
                    modelContext.insert(restoredSession)
                }

                for member in group {
                    member.status = "occupied"
                    member.isSynced = true
                    member.updatedAt = Date()
                }
                guard modelContext.saveWithLogging(label: "\(Self.self).openTableForOrdering.restoreRemote") else {
                    tableOpenError = "ไม่สามารถบันทึก session ที่กู้คืนของโต๊ะ \(leader.tableNumber) ได้"
                    return
                }

                await SyncEngine.shared.pullCustomerOrders(modelContext)
                activeSession = restoredSession
                selectedTab = .pos
                APHaptic.trigger()
                return
            }

            let staleSessions = group
                .flatMap(\.sessions)
                .filter { $0.isActive }
            for session in staleSessions {
                session.isActive = false
                session.endedAt = Date()
                session.isSynced = false
                session.updatedAt = Date()
            }
            if !staleSessions.isEmpty,
               !modelContext.saveWithLogging(label: "\(Self.self).openTableForOrdering.closeStale") {
                tableOpenError = "ไม่สามารถปิด session เดิมของโต๊ะ \(leader.tableNumber) ได้ กรุณาลองใหม่"
                return
            }

            // The device can have no active local session while the server
            // still retains one (for example after an interrupted close).
            // Opening a table that is visibly vacant must close that remote
            // ghost first, otherwise the server's one-active-session-per-table
            // constraint rejects the new session and the KDS ticket vanishes.
            let shouldResetRemoteSession = !staleSessions.isEmpty
                || leader.status.lowercased() == "vacant"
            if shouldResetRemoteSession, !leader.tableNumber.isEmpty {
                _ = try? await NetworkManager.shared.closeTableSession(tableNumber: leader.tableNumber)
            }

            let newSession = TableSession(
                sessionToken: UUID().uuidString,
                startedAt: Date(),
                isActive: true,
                table: leader,
                guestCount: leader.capacity,
                cashierName: activeCashierDisplayName
            )
            modelContext.insert(newSession)
            leader.sessions.append(newSession)
            for member in group {
                member.status = "occupied"
                member.isSynced = false
                member.updatedAt = Date()
            }
            guard modelContext.saveWithLogging(label: "\(Self.self).openTableForOrdering.create") else {
                tableOpenError = "ไม่สามารถสร้าง session สำหรับโต๊ะ \(leader.tableNumber) ได้ กรุณาลองใหม่"
                return
            }

            activeSession = newSession
            selectedTab = .pos
            APHaptic.trigger()

            // Publish the newly-created session immediately. A full sync can
            // spend several seconds pushing unrelated records first; during
            // that window a realtime table pull could still see the server's
            // old vacant state and close this optimistic local session.
            do {
                if try await NetworkManager.shared.uploadTableSession(session: newSession) {
                    newSession.isSynced = true
                    newSession.updatedAt = Date()
                    modelContext.saveWithLogging(label: "\(Self.self).openTableForOrdering.publish")
                }
            } catch {
                // Keep the local session dirty for the regular offline-first
                // sync retry. The cashier can continue taking the order.
                #if DEBUG
                print("TableView [Open Session Publish Error]: \(error.localizedDescription)")
                #endif
            }

            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }

    @ViewBuilder
    private func tableQuickActions(_ table: RestaurantTable) -> some View {
        let leader = table.joinedParent ?? table
        if leader.status.lowercased() != "vacant"
            || leader.sessions.contains(where: { $0.isActive }) {
            Button {
                requestQuickClear(table)
            } label: {
                Label("เคลียร์โต๊ะ", systemImage: "eraser.fill")
            }
        }

        Divider()

        Button {
            selectedTable = table.joinedParent ?? table
            showingDetailSheet = true
        } label: {
            Label("table_details_title".t, systemImage: "info.circle")
        }
    }

    private func requestQuickClear(_ table: RestaurantTable) {
        let leader = table.joinedParent ?? table
        let group = [leader] + leader.joinedChildren
        let hasPayment = group.contains { member in
            member.sessions.contains { session in
                session.isActive && session.orders.contains { order in
                    !order.isDeleted && order.payments.contains {
                        !$0.isDeleted && $0.amount > 0.005
                    }
                }
            }
        }
        guard !hasPayment else {
            quickClearError = "โต๊ะนี้มีรายการชำระเงินแล้ว ไม่สามารถลบออเดอร์ด้วยการเคลียร์โต๊ะได้ กรุณาใช้กระบวนการคืนเงินก่อน"
            APHaptic.trigger()
            return
        }

        let hasTransaction = group.contains { member in
            member.sessions.contains { session in
                session.isActive && session.orders.contains { order in
                    guard !order.isDeleted else { return false }
                    let hasItems = order.items.contains {
                        !$0.isDeleted && $0.status != "cancelled"
                    }
                    let hasPayment = order.payments.contains { !$0.isDeleted }
                    return hasItems || hasPayment || order.total > 0.005
                }
            }
        }

        if hasTransaction {
            pendingQuickClearTableId = table.id
            showingQuickClearPinSheet = true
            APHaptic.trigger()
        } else {
            pendingVacantClearTable = table
            showingQuickClearVacantConfirm = true
            APHaptic.trigger()
        }
    }

    private func performQuickClearVacant(_ table: RestaurantTable) {
        let leader = table.joinedParent ?? table
        let tableNo = leader.tableNumber
        let oldStatus = leader.status
        let employeeId = sessionManager.currentStaffSession?.employeeId
        let staffName = sessionManager.currentStaffSession?.displayName ?? "Staff"

        quickSetStatus("vacant", for: table)

        let log = AuditLog(
            employeeId: employeeId,
            actionType: "table_clear",
            details: "Table \(tableNo) cleared to vacant (previous status: \(oldStatus)) by \(staffName)",
            originalValue: 0,
            newValue: 0
        )
        modelContext.insert(log)
        _ = modelContext.saveWithLogging(label: #function)

        InAppNotificationManager.shared.post(
            InAppNotification(
                type: .serviceRequest,
                title: LocalizationManager.shared.t("table_cleared_ready_title", tableNo),
                body: LocalizationManager.shared.t("table_cleared_ready_body"),
                tableNumber: tableNo,
                dedupeKey: "table_clear_\(leader.id.uuidString)_\(Int(Date().timeIntervalSince1970))"
            )
        )
    }

    private func performQuickVoidAndClear(_ table: RestaurantTable, reason: String) {
        let leader = table.joinedParent ?? table
        let group = [leader] + leader.joinedChildren
        let employeeId = sessionManager.currentStaffSession?.employeeId
        let staffName = sessionManager.currentStaffSession?.displayName ?? "Manager"

        // Re-check after the PIN/reason sheets. A payment may have arrived
        // from another device while the confirmation UI was open.
        let hasPayment = group.contains { member in
            member.sessions.contains { session in
                session.isActive && session.orders.contains { order in
                    !order.isDeleted && order.payments.contains {
                        !$0.isDeleted && $0.amount > 0.005
                    }
                }
            }
        }
        guard !hasPayment else {
            quickClearError = "พบการชำระเงินระหว่างดำเนินการ กรุณาคืนเงินก่อนเคลียร์โต๊ะ"
            return
        }

        for member in group {
            for session in member.sessions where session.isActive {
                for order in session.orders {
                    _ = order.voidUnsettledForTableClear(
                        reason: reason,
                        employeeId: employeeId,
                        in: modelContext
                    )
                }
                session.isActive = false
                session.endedAt = Date()
                session.isSynced = false
                session.updatedAt = Date()
            }
            member.status = "vacant"
            member.isSynced = false
            member.updatedAt = Date()
        }

        if let current = activeSession,
           group.contains(where: { current.table?.id == $0.id }) {
            activeSession = nil
        }

        guard modelContext.saveWithLogging(label: #function) else {
            quickClearError = "ไม่สามารถบันทึกการยกเลิกออเดอร์ได้ โต๊ะยังไม่ถูกเคลียร์"
            return
        }
        APHaptic.trigger()

        let leaderNo = leader.tableNumber
        InAppNotificationManager.shared.post(
            InAppNotification(
                type: .cookingAlert,
                title: LocalizationManager.shared.t("table_void_cleared_title", leaderNo),
                body: "\(reason) · \(staffName)",
                tableNumber: leaderNo,
                dedupeKey: "table_void_\(leader.id.uuidString)_\(Int(Date().timeIntervalSince1970))"
            )
        )

        NotificationStore.shared.postAlert(
            priority: .high,
            category: .orders,
            title: LocalizationManager.shared.t("table_void_cleared_title", leaderNo),
            message: "\(reason) · \(staffName)",
            device: UIDevice.current.name,
            tableNumber: leaderNo
        )

        // syncAll pushes cancelled orders/items before closing table_sessions.
        // This ordering satisfies the server guard that rejects closing a
        // session while it still owns open kitchen orders.
        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }

    private func quickSetStatus(_ status: String, for table: RestaurantTable) {
        let leader = table.joinedParent ?? table
        let group = [leader] + leader.joinedChildren

        // Keep the existing kitchen-ticket guard for the exceptional path.
        guard !group.contains(where: {
            $0.sessions.contains(where: { $0.isActive && $0.hasPendingKitchenTickets })
        }) else {
            selectedTable = table.joinedParent ?? table
            showingDetailSheet = true
            return
        }

        for member in group {
            member.status = status
            member.isSynced = false
            member.updatedAt = Date()
            for session in member.sessions where session.isActive {
                session.terminalizeOpenOrders(.serve, in: modelContext)
                session.isActive = false
                session.endedAt = Date()
                session.isSynced = false
                session.updatedAt = Date()
            }
        }
        if let current = activeSession,
           group.contains(where: { member in
               current.table?.id == member.id
           }) {
            activeSession = nil
        }
        modelContext.saveWithLogging(label: #function)
        APHaptic.trigger()

        let tableNumbers = group.map(\.tableNumber)
        Task {
            for number in tableNumbers where !number.isEmpty {
                _ = try? await NetworkManager.shared.closeTableSession(tableNumber: number)
            }
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
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
                    Task { await importFloorPlanPhoto(newItem) }
                }

                if floorPlanImages.first(where: { $0.diningAreaId == selectedDiningAreaId && !$0.isDeleted }) != nil {
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
        let uniqueZones = Set(tablesOnSelectedFloor.compactMap { normalizedZone($0.zone) })
        return ["All"] + Array(uniqueZones).sorted()
    }

    /// Shared by map, grid and list so the same selection always produces the
    /// same set of tables in every presentation mode.
    private var tablesOnSelectedFloor: [RestaurantTable] {
        tables.filter {
            tableBelongsToSelectedArea($0)
            && !$0.isDeleted
            && !optimisticallyDeletedTableIds.contains($0.id)
        }
    }

    private var visibleTablesForSelection: [RestaurantTable] {
        guard selectedZone != "All" else { return tablesOnSelectedFloor }
        return tablesOnSelectedFloor.filter { normalizedZone($0.zone) == selectedZone }
    }

    /// The table canvas is dining-area scoped. Never place a branch-wide or
    /// stale request over an empty/different area because it implies that the
    /// referenced table exists in the area currently on screen.
    private var activeRequestsForSelectedArea: [ServiceRequest] {
        guard let areaId = selectedDiningAreaId?.uuidString.lowercased() else { return [] }
        let tableIds = Set(tablesOnSelectedFloor.map { $0.id.uuidString.lowercased() })
        return syncEngine.activeRequests.filter { request in
            if let requestAreaId = request.diningAreaId?.lowercased() {
                return requestAreaId == areaId
            }
            if let tableId = request.restaurantTableId?.lowercased() {
                return tableIds.contains(tableId)
            }
            // Legacy unscoped requests remain available in Notification Center,
            // but are unsafe to render on a specific floor plan.
            return false
        }
    }

    private func normalizedZone(_ zone: String?) -> String? {
        guard let value = zone?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }

    private func selectFloor(_ floorId: Int) {
        selectedZone = "All"
        selectedFloor = floorId
    }

    private func handleTableViewAppear() {
        resolveActiveBranchIfNeeded()
        ensureDefaultFloorExists()
        normalizeTableSelection()
        loadCachedFloorPlanImage()
        enforceTableLimit()
        searchTablesList = tables
        presentPendingAddFirstTableIfNeeded()
    }

    /// A freshly onboarded merchant can already have a branch in SwiftData while
    /// `active_branch_id` is still empty. Resolve that state before creating the
    /// default dining area; otherwise newly created tables receive an empty branch
    /// and immediately disappear from the branch-scoped canvas.
    private func resolveActiveBranchIfNeeded() {
        _ = try? BranchContext.shared.bootstrap(in: modelContext, createDefaultIfEmpty: true)
    }

    private func ensureDefaultFloorExists() {
        guard UUID(uuidString: activeBranchId) != nil, floors.isEmpty else { return }
        modelContext.insert(FloorData(
            floorNumber: 1,
            name: lm.languageCode == "th" ? "พื้นที่หลัก" : "Main Area",
            branchId: activeBranchId,
            sortOrder: 0
        ))
        modelContext.saveWithLogging(label: #function)
    }

    private func tableDataDidChange(_ oldTables: [RestaurantTable], _ newTables: [RestaurantTable]) {
        _ = oldTables
        updateSearchTablesList(with: newTables)
        normalizeTableSelection()
    }

    private func selectedFloorDidChange() {
        // A zone belongs to the current floor. Keeping the previous floor's
        // zone can make every table appear to vanish.
        selectedZone = "All"
        zoomScale = 1
        gestureScale = 1
        panOffset = .zero
        activePanOffset = .zero
        focusTableId = nil
        layoutSelectedTableId = nil
        layoutSelectedTableIds.removeAll()
        loadCachedFloorPlanImage()
    }

    private func activeBranchDidChange() {
        // Clear the previous branch synchronously; a slow/offline refresh must
        // never leave its operational queue visible in the new workspace.
        syncEngine.resetNotificationRuntimeState()
        ensureDefaultFloorExists()
        if let firstFloor = floors.first?.floorNumber { selectedFloor = firstFloor }
        normalizeTableSelection()
        loadCachedFloorPlanImage()
        Task { await syncEngine.syncServiceRequests() }
    }

    private func normalizeTableSelection() {
        if !floors.contains(where: { $0.id == selectedFloor }) {
            selectedFloor = floors.first?.id ?? 1
            selectedZone = "All"
            return
        }

        if selectedZone != "All" && !zones.contains(selectedZone) {
            selectedZone = "All"
        }
    }

    private func deleteSelectedDiningArea() {
        guard let diningAreaId = selectedDiningAreaId,
              let floor = floors.first(where: { $0.uuid == diningAreaId }) else { return }
        let scopedTables = tables.filter { tableBelongsToSelectedArea($0) && !$0.isDeleted }
        guard !scopedTables.contains(where: \.joinedGroupHasActiveSession) else {
            presetOperationError = "ไม่สามารถลบพื้นที่ที่มีโต๊ะกำลังใช้งาน กรุณาเคลียร์โต๊ะก่อน"
            return
        }

        let now = Date()
        let nextFloorNumber = floors.first(where: { $0.uuid != diningAreaId })?.floorNumber ?? 1
        scopedTables.forEach { $0.prepareForDeletion(at: now) }
        floorPlanImages.filter { $0.diningAreaId == diningAreaId && !$0.isDeleted }.forEach {
            $0.isDeleted = true; $0.isSynced = false; $0.updatedAt = now
        }
        layoutPresets.filter { $0.diningAreaId == diningAreaId && !$0.isDeleted }.forEach {
            $0.isDeleted = true; $0.isSynced = false; $0.updatedAt = now
        }
        floor.isDeleted = true
        floor.isActive = false
        floor.isSynced = false
        floor.updatedAt = now
        modelContext.saveWithLogging(label: #function)

        layoutSelectedTableId = nil
        layoutSelectedTableIds.removeAll()
        selectFloor(nextFloorNumber)
        Task { await SyncEngine.shared.syncAll(modelContext: modelContext) }
    }

    private func countTables(status: String) -> Int {
        visibleTablesForSelection.filter { $0.status.lowercased() == status.lowercased() }.count
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

    private func getCanvasSize() -> CGSize {
        let floorTables = tables.filter { tableBelongsToSelectedArea($0) && !$0.isDeleted }
        let maxX = floorTables.map { CGFloat($0.positionX) }.max() ?? 1500
        let maxY = floorTables.map { CGFloat($0.positionY) }.max() ?? 1200
        return CGSize(width: max(1500, maxX + 250), height: max(1200, maxY + 250))
    }

    private func isTableVisible(
        _ table: RestaurantTable,
        viewportSize: CGSize,
        zoomScale: CGFloat,
        gestureScale: CGFloat,
        panOffset: CGSize,
        activePanOffset: CGSize
    ) -> Bool {
        let totalZoom = zoomScale * gestureScale
        let totalOffsetX = panOffset.width + activePanOffset.width
        let totalOffsetY = panOffset.height + activePanOffset.height

        let tableSize: CGFloat = 160 // Estimated bounding box size including chairs/padding
        let halfSize = tableSize / 2

        // Calculate the table center in screen space
        let screenCenterX = CGFloat(table.positionX) * totalZoom + totalOffsetX
        let screenCenterY = CGFloat(table.positionY) * totalZoom + totalOffsetY

        // Bounds check
        let minX = screenCenterX - halfSize * totalZoom
        let maxX = screenCenterX + halfSize * totalZoom
        let minY = screenCenterY - halfSize * totalZoom
        let maxY = screenCenterY + halfSize * totalZoom

        return maxX >= 0 && minX <= viewportSize.width &&
               maxY >= 0 && minY <= viewportSize.height
    }

    private func enforceTableLimit() {
        let descriptor = FetchDescriptor<RestaurantTable>(
            predicate: #Predicate<RestaurantTable> { !$0.isDeleted }
        )
        guard let allTables = try? modelContext.fetch(descriptor) else { return }

        if allTables.count > 80 {
            // Sort tables: real tables first, then test tables
            let sortedTables = allTables.sorted { t1, t2 in
                let t1IsTest = t1.tableNumber.hasPrefix("LT-") || t1.tableNumber.hasPrefix("LoadTest-")
                let t2IsTest = t2.tableNumber.hasPrefix("LT-") || t2.tableNumber.hasPrefix("LoadTest-")

                if t1IsTest != t2IsTest {
                    // Real tables first
                    return !t1IsTest && t2IsTest
                }

                // If both are test or both are real, sort by table number
                // Try numeric sort first, fallback to alphabetical
                let cleanT1 = t1.tableNumber.replacingOccurrences(of: "LT-", with: "").replacingOccurrences(of: "LoadTest-", with: "")
                let cleanT2 = t2.tableNumber.replacingOccurrences(of: "LT-", with: "").replacingOccurrences(of: "LoadTest-", with: "")
                if let n1 = Int(cleanT1),
                   let n2 = Int(cleanT2) {
                    return n1 < n2
                }
                return t1.tableNumber.localizedCompare(t2.tableNumber) == .orderedAscending
            }

            // Keep the first 80 tables, mark the rest as deleted
            let tablesToDelete = sortedTables.suffix(from: min(80, sortedTables.count))

            var didChange = false
            for table in tablesToDelete {
                // If the table was never synced to remote (isSynced == false) and has no active session,
                // we can delete it physically. Otherwise soft delete to sync deletion.
                let hasActiveSession = table.sessions.contains(where: { $0.isActive })
                if !table.isSynced && !hasActiveSession {
                    modelContext.delete(table)
                } else {
                    table.isDeleted = true
                    table.isSynced = false
                    table.updatedAt = Date()
                }
                didChange = true
            }

            if didChange {
                modelContext.saveWithLogging(label: #function)
                Task {
                    await SyncEngine.shared.syncAll(modelContext: modelContext)
                }
            }
        }
    }

    private func updateTablePosition(_ table: RestaurantTable, newPosition: CGPoint) {
        table.positionX = newPosition.x
        table.positionY = newPosition.y
        table.isSynced = false
        table.updatedAt = Date()
        modelContext.saveWithLogging(label: #function)
        draggedTableId = nil
    }

    /// Effective zoom applied to the canvas (committed zoom × live pinch).
    private var totalCanvasZoom: CGFloat {
        max(0.01, zoomScale * gestureScale)
    }

    /// Snap position onto the drawn grid.
    /// Grid mode = hard lock. Canvas mode = soft magnet within threshold.
    private func snapToLayoutGrid(_ point: CGPoint) -> CGPoint {
        let g = Self.layoutGridSize
        let nearest = CGPoint(
            x: (point.x / g).rounded() * g,
            y: (point.y / g).rounded() * g
        )
        if isGridMode {
            return nearest
        }
        let threshold = Self.canvasSnapThreshold
        return CGPoint(
            x: abs(point.x - nearest.x) <= threshold ? nearest.x : point.x,
            y: abs(point.y - nearest.y) <= threshold ? nearest.y : point.y
        )
    }

    private func clampedTableOrigin(
        proposedX: CGFloat,
        proposedY: CGFloat,
        tableSize: CGSize,
        canvasSize: CGSize
    ) -> CGPoint {
        let minX: CGFloat = 16
        let maxX: CGFloat = max(minX, canvasSize.width - tableSize.width - 16)
        let minY: CGFloat = 16
        let maxY: CGFloat = max(minY, canvasSize.height - tableSize.height - 16)
        return CGPoint(
            x: min(max(proposedX, minX), maxX),
            y: min(max(proposedY, minY), maxY)
        )
    }

    private func handleDragChanged(value: DragGesture.Value, for table: RestaurantTable) {
        if activeResizeCorner != nil { return }
        if activeDraggingTableId != table.id {
            activeDraggingTableId = table.id
            draggedTableId = table.id
            layoutSelectedTableId = table.id
            layoutSelectedTableIds.insert(table.id)
            APHaptic.trigger()
        }
        let tableSize = getTableCardSize(for: table)
        let posX = CGFloat(table.positionX)
        let posY = CGFloat(table.positionY)
        let zoom = totalCanvasZoom
        let proposed = CGPoint(
            x: posX + value.translation.width / zoom,
            y: posY + value.translation.height / zoom
        )
        let canvasSize = getCanvasSize()
        let clamped = clampedTableOrigin(
            proposedX: proposed.x,
            proposedY: proposed.y,
            tableSize: tableSize,
            canvasSize: canvasSize
        )
        let live = snapToLayoutGrid(clamped)

        var txn = Transaction()
        txn.animation = nil
        withTransaction(txn) {
            dragTranslation = CGSize(width: live.x - posX, height: live.y - posY)
        }
    }

    private func handleDragEnded(value: DragGesture.Value, for table: RestaurantTable) {
        if activeResizeCorner != nil { return }
        let tableSize = getTableCardSize(for: table)
        let posX = CGFloat(table.positionX)
        let posY = CGFloat(table.positionY)
        let zoom = totalCanvasZoom
        let proposed = CGPoint(
            x: posX + value.translation.width / zoom,
            y: posY + value.translation.height / zoom
        )
        let canvasSize = getCanvasSize()
        let clamped = clampedTableOrigin(
            proposedX: proposed.x,
            proposedY: proposed.y,
            tableSize: tableSize,
            canvasSize: canvasSize
        )
        let finalPosition = snapToLayoutGrid(clamped)

        var txn = Transaction()
        txn.animation = nil
        withTransaction(txn) {
            updateTablePosition(table, newPosition: finalPosition)
            activeDraggingTableId = nil
            draggedTableId = nil
            dragTranslation = .zero
        }
        APHaptic.trigger()

        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }

    private func computeResize(
        corner: TableResizeCorner,
        translation: CGSize,
        table: RestaurantTable
    ) -> (scale: CGFloat, originDelta: CGSize) {
        let zoom = totalCanvasZoom
        let startScale = CGFloat(table.resolvedLayoutScale)
        let base = getUnscaledCardSize(capacity: table.capacity)
        let dx = translation.width / zoom
        let dy = translation.height / zoom

        // Uniform scale from the opposite corner (standard image-editor behavior).
        let signedGrowth: CGFloat
        switch corner {
        case .se: signedGrowth = (dx + dy) * 0.5
        case .nw: signedGrowth = (-dx - dy) * 0.5
        case .ne: signedGrowth = (dx - dy) * 0.5
        case .sw: signedGrowth = (-dx + dy) * 0.5
        }

        let startWidth = max(1, base.width * startScale)
        let rawScale = (startWidth + signedGrowth) / base.width
        let newScale = min(Self.maxLayoutScale, max(Self.minLayoutScale, rawScale))

        // Keep opposite corner locked by shifting top-leading origin when scale changes.
        let originDelta: CGSize
        switch corner {
        case .se:
            originDelta = .zero
        case .nw:
            originDelta = CGSize(
                width: base.width * (startScale - newScale),
                height: base.height * (startScale - newScale)
            )
        case .ne:
            originDelta = CGSize(
                width: 0,
                height: base.height * (startScale - newScale)
            )
        case .sw:
            originDelta = CGSize(
                width: base.width * (startScale - newScale),
                height: 0
            )
        }
        return (newScale, originDelta)
    }

    private func handleResizeChanged(corner: TableResizeCorner, value: DragGesture.Value, for table: RestaurantTable) {
        if activeResizeCorner != corner {
            activeResizeCorner = corner
            activeDraggingTableId = nil
            layoutSelectedTableId = table.id
            layoutSelectedTableIds.insert(table.id)
            APHaptic.trigger()
        }
        let result = computeResize(corner: corner, translation: value.translation, table: table)
        var txn = Transaction()
        txn.animation = nil
        withTransaction(txn) {
            liveLayoutScale = result.scale
            liveLayoutOriginDelta = result.originDelta
        }
    }

    private func handleResizeEnded(corner: TableResizeCorner, value: DragGesture.Value, for table: RestaurantTable) {
        let result = computeResize(corner: corner, translation: value.translation, table: table)
        let newOrigin = CGPoint(
            x: CGFloat(table.positionX) + result.originDelta.width,
            y: CGFloat(table.positionY) + result.originDelta.height
        )
        let canvasSize = getCanvasSize()
        let sized = CGSize(
            width: getUnscaledCardSize(capacity: table.capacity).width * result.scale,
            height: getUnscaledCardSize(capacity: table.capacity).height * result.scale
        )
        let clamped = clampedTableOrigin(
            proposedX: newOrigin.x,
            proposedY: newOrigin.y,
            tableSize: sized,
            canvasSize: canvasSize
        )
        let snapped = snapToLayoutGrid(clamped)

        var txn = Transaction()
        txn.animation = nil
        withTransaction(txn) {
            table.layoutScale = Double(result.scale)
            table.positionX = Double(snapped.x)
            table.positionY = Double(snapped.y)
            table.isSynced = false
            table.updatedAt = Date()
            modelContext.saveWithLogging(label: #function)

            activeResizeCorner = nil
            liveLayoutScale = nil
            liveLayoutOriginDelta = .zero
        }
        APHaptic.trigger()

        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }

    private func checkManagerPermission(for action: AuthAction) {
        if isLayoutManagerAuthorized {
            performAuthAction(action)
        } else {
            pendingAuthAction = action
            showingManagerPinSheet = true
        }
    }

    /// Checklist / first-product next step: open Add Table for an empty floor.
    private func presentPendingAddFirstTableIfNeeded() {
        guard StoreSetupChecklist.consumePendingAddFirstTable() else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            checkManagerPermission(for: .addTable)
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
        case .deleteTable:
            isLayoutManagerAuthorized = true
            deleteSelectedLayoutTable()
        }
    }

    private func requestSelectedTableDeletion() {
        guard !layoutSelectedTableIds.isEmpty else { return }
        pendingDeletionTableIds = layoutSelectedTableIds
        showingDeleteTableConfirm = true
    }

    /// Soft-delete all layout-selected tables in one guarded transaction.
    private func deleteSelectedLayoutTable() {
        let idsToDelete = pendingDeletionTableIds.isEmpty
            ? layoutSelectedTableIds
            : pendingDeletionTableIds
        let selectedTables = tables.filter {
            idsToDelete.contains($0.id) && !$0.isDeleted
        }
        guard !selectedTables.isEmpty else {
            pendingDeletionTableIds.removeAll()
            presetOperationError = "ไม่พบโต๊ะที่เลือก กรุณาเลือกโต๊ะแล้วลองอีกครั้ง"
            return
        }

        guard !selectedTables.contains(where: \.joinedGroupHasActiveSession) else {
            pendingDeletionTableIds.removeAll()
            presetOperationError = "ไม่สามารถลบชุดโต๊ะได้ เนื่องจากมีโต๊ะที่กำลังใช้งาน กรุณาเคลียร์โต๊ะก่อน"
            return
        }

        let tableIds = selectedTables.map(\.id)
        optimisticallyDeletedTableIds.formUnion(tableIds)
        for table in selectedTables {
            table.prepareForDeletion()
        }
        modelContext.saveWithLogging(label: #function)

        layoutSelectedTableId = nil
        layoutSelectedTableIds.removeAll()
        pendingDeletionTableIds.removeAll()
        activeResizeCorner = nil
        liveLayoutScale = nil
        liveLayoutOriginDelta = .zero

        Task {
            do {
                let deletedCount = try await NetworkManager.shared.deleteRestaurantTablesOnServer(ids: tableIds)
                guard deletedCount == tableIds.count else {
                    throw NetworkError.invalidResponse
                }
                for table in selectedTables where table.isDeleted {
                    table.isSynced = true
                }
                modelContext.saveWithLogging(label: #function)
            } catch {
                var deletionConfirmed = false
                // A timeout/decoding failure does not prove that the atomic RPC
                // failed; the server may already have committed the deletion.
                // Reconcile the selected rows before changing the optimistic UI.
                if let remoteTables = try? await NetworkManager.shared.fetchRestaurantTables() {
                    let remoteDeletionById: [UUID: Bool] = Dictionary(
                        uniqueKeysWithValues: remoteTables.compactMap { remote in
                            guard
                                let idString = remote["id"] as? String,
                                let id = UUID(uuidString: idString)
                            else { return nil }
                            return (id, remote["is_deleted"] as? Bool ?? false)
                        }
                    )

                    for table in selectedTables {
                        if let isDeletedOnServer = remoteDeletionById[table.id] {
                            table.isDeleted = isDeletedOnServer
                            table.isSynced = true
                            table.updatedAt = Date()
                            if !isDeletedOnServer {
                                optimisticallyDeletedTableIds.remove(table.id)
                            }
                        } else {
                            // No matching server row: keep the local tombstone so
                            // a stale-only local table cannot reappear.
                            table.isDeleted = true
                            table.isSynced = true
                        }
                    }
                    deletionConfirmed = selectedTables.allSatisfy {
                        remoteDeletionById[$0.id] != false
                    }
                } else {
                    // Preserve the pending tombstone for a later retry instead of
                    // resurrecting tables after an ambiguous network failure.
                    for table in selectedTables {
                        table.isDeleted = true
                        table.isSynced = false
                    }
                }
                modelContext.saveWithLogging(label: #function)
                if !deletionConfirmed {
                    presetOperationError = "ลบโต๊ะไม่สำเร็จ: \(error.localizedDescription)"
                }
            }
        }
        APHaptic.trigger()
    }

    private var editLayoutBinding: Binding<Bool> {
        Binding(
            get: { isEditingLayout },
            set: { newValue in
                if newValue {
                    checkManagerPermission(for: .toggleEditLayout(true))
                } else {
                    isEditingLayout = false
                    isLayoutManagerAuthorized = false
                    layoutSelectedTableId = nil
                    layoutSelectedTableIds.removeAll()
                    activeResizeCorner = nil
                    liveLayoutScale = nil
                    liveLayoutOriginDelta = .zero
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

    /// Padded card frame before layoutScale (matches InteractiveTableCard `.padding(16)`).
    private func getUnscaledCardSize(capacity: Int) -> CGSize {
        let core = getTableSize(capacity: capacity)
        return CGSize(width: core.width + 32, height: core.height + 32)
    }

    /// Current on-canvas footprint including live resize preview when active.
    private func getTableCardSize(for table: RestaurantTable) -> CGSize {
        let base = getUnscaledCardSize(capacity: table.capacity)
        let scale: CGFloat
        if layoutSelectedTableId == table.id, let live = liveLayoutScale {
            scale = live
        } else {
            scale = CGFloat(table.resolvedLayoutScale)
        }
        return CGSize(width: base.width * scale, height: base.height * scale)
    }

    // MARK: - Header Layout Components

    // MARK: - Premium Redesigned Header Elements

    private var tableContextBar: some View {
        HStack(spacing: 4) {
            backToLoginButton(isCompact: true)

            Divider()
                .frame(height: 18)

            headerTitleView

            Divider()
                .frame(height: 18)

            customFloorPicker
        }
        .padding(.horizontal, 4)
        .apLiquidGlass(
            tint: isEditingLayout ? Color.appAccent.opacity(0.14) : Color.appAccent.opacity(0.045),
            in: Capsule()
        )
    }

    // MARK: - Computed Mode Helpers
    private var isGridMode: Bool { layoutModeRaw == "grid" }
    private var isListView: Bool { tableViewModeRaw == "list" }

    private var editModeIndicator: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.appAccent)
                .frame(width: 36, height: 36)
                .apLiquidGlass(tint: Color.appAccent.opacity(0.18), in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text("โหมดแก้ไขผังโต๊ะ")
                    .font(.system(size: 14, weight: .bold))
                Text("ลากเพื่อย้าย · แตะเพื่อเลือก · ใช้จุดจับเพื่อปรับขนาด")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.textSecondary)
            }
            if !layoutSelectedTableIds.isEmpty {
                Label("\(layoutSelectedTableIds.count) โต๊ะ", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.appAccent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .apLiquidGlass(tint: Color.appAccent.opacity(0.12), in: Capsule())
            }
        }
        .foregroundColor(.textPrimary)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var canvasEditToolbar: some View {
        Group {
            if #available(iOS 26.0, *) {
                GlassEffectContainer(spacing: 12) {
                    editToolbarContent
                }
            } else {
                editToolbarContent
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(Rectangle().fill(Color.appBorderSubtle).frame(height: 1), alignment: .bottom)
    }

    private var editToolbarContent: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                editModeIndicator
                Spacer(minLength: 16)
                deleteSelectedTablesButton
                addTableButton
                finishEditingButton
            }

            HStack(spacing: 10) {
                Label("มุมมอง", systemImage: "rectangle.3.group")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.textSecondary)
                layoutModePicker

                Divider()
                    .frame(height: 28)

                floorManagementActions
                layoutPresetsToolbar
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private var deleteSelectedTablesButton: some View {
        if !layoutSelectedTableIds.isEmpty {
            Button(action: requestSelectedTableDeletion) {
                Label("ลบโต๊ะ (\(layoutSelectedTableIds.count))", systemImage: "trash")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(height: 34)
            }
            .apGlassButton(tint: .appRose)
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var addTableButton: some View {
        Button(action: { checkManagerPermission(for: .addTable) }) {
            Label("table_add_new_title".t, systemImage: "plus")
                .font(.system(size: 13, weight: .semibold))
                .frame(height: 34)
        }
        .apGlassButton(prominent: true, tint: .appAccent)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var gridEditToolbar: some View {
        canvasEditToolbar
    }

    private func toggleLayoutSelection(_ table: RestaurantTable) {
        if layoutSelectedTableIds.contains(table.id) {
            layoutSelectedTableIds.remove(table.id)
            if layoutSelectedTableId == table.id {
                layoutSelectedTableId = layoutSelectedTableIds.first
            }
        } else {
            layoutSelectedTableIds.insert(table.id)
            layoutSelectedTableId = table.id
        }
    }

    private var finishEditingButton: some View {
        Button {
            isEditingLayout = false
            isLayoutManagerAuthorized = false
            layoutSelectedTableId = nil
            layoutSelectedTableIds.removeAll()
            activeResizeCorner = nil
            liveLayoutScale = nil
            liveLayoutOriginDelta = .zero
            APHaptic.trigger()
        } label: {
            Label("เสร็จสิ้น", systemImage: "checkmark")
                .font(.system(size: 13, weight: .bold))
                .frame(height: 34)
        }
        .apGlassButton(prominent: true, tint: .appTeal)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var floorManagementActions: some View {
        Menu {
            Button(action: { showingAddFloorAlert = true }) {
                Label("table_floor_add_btn".t, systemImage: "plus")
            }

            if floors.count > 1 {
                Button(role: .destructive, action: { showingRemoveFloorConfirm = true }) {
                    Label("table_floor_remove_btn".t, systemImage: "trash")
                }
            }
        } label: {
            Label("จัดการชั้น", systemImage: "building.2")
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 12)
                .frame(height: 34)
                .apChromeSurface(tint: Color.appAccent.opacity(0.06), in: Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var layoutModePicker: some View {
        HStack(spacing: 2) {
            layoutModeButton(icon: "square.grid.2x2", mode: "grid", label: "table_layout_mode_grid".t)
            layoutModeButton(
                icon: "rectangle.on.rectangle.angled",
                mode: "canvas",
                label: "table_layout_mode_canvas".t
            )
        }
        .padding(2)
        .apLiquidGlass(tint: Color.appAccent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private func layoutModeButton(icon: String, mode: String, label: String) -> some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                setLayoutMode(mode)
                APHaptic.trigger()
            }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(layoutModeRaw == mode ? .white : .textSecondary)
                .frame(width: 34, height: 30)
                .background(layoutModeRaw == mode ? Color.appAccent : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func setLayoutMode(_ mode: String) {
        layoutModeRaw = mode
        guard mode == "grid" else { return }
        activeResizeCorner = nil
        liveLayoutScale = nil
        liveLayoutOriginDelta = .zero
    }

    private var currentFloorPlanImagePath: String {
        activeFloorPlanImage?.resolvedImagePath ?? ""
    }

    private func saveFloorPlanImage(filename: String) {
        guard let diningAreaId = selectedDiningAreaId else { return }
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
        let branchId = BranchContext.shared.activeBranchIDString
        if let existing = floorPlanImages.first(where: {
            $0.diningAreaId == diningAreaId && ($0.branchId == branchId || $0.branchId.isEmpty)
        }) {
            existing.branchId = branchId
            existing.imageFilename = filename
            existing.isDeleted = false
            existing.isSynced = false
            existing.updatedAt = Date()
        } else {
            let newItem = FloorPlanImage(
                merchantId: merchantId,
                branchId: branchId,
                diningAreaId: diningAreaId,
                imageFilename: filename
            )
            modelContext.insert(newItem)
        }
        modelContext.saveWithLogging(label: #function)
        Task { await SyncEngine.shared.syncAll(modelContext: modelContext) }
    }

    @MainActor
    private func importFloorPlanPhoto(_ item: PhotosPickerItem) async {
        guard let diningAreaId = selectedDiningAreaId else {
            presetOperationError = "กรุณาเลือกพื้นที่ก่อนอัปโหลด Floor Plan"
            selectedPhotoItem = nil
            return
        }
        do {
            guard let sourceData = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: sourceData),
                  let jpegData = image.jpegData(compressionQuality: 0.85) else {
                throw NSError(domain: "FloorPlan", code: 1, userInfo: [NSLocalizedDescriptionKey: "ไม่สามารถอ่านไฟล์ภาพได้"])
            }
            let filename = "floor_plan_\(diningAreaId.uuidString.lowercased())_\(Int(Date().timeIntervalSince1970)).jpg"

            // Media must exist before metadata is published; otherwise another
            // device can pull a filename that still returns 404.
            _ = try await NetworkManager.shared.uploadFloorPlanMedia(data: jpegData, fileName: filename)
            guard selectedDiningAreaId == diningAreaId else { return }

            let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            try jpegData.write(to: docsURL.appendingPathComponent(filename), options: .atomic)
            saveFloorPlanImage(filename: filename)
            cachedFloorPlanImage = image
        } catch {
            presetOperationError = "อัปโหลด Floor Plan ไม่สำเร็จ: \(error.localizedDescription)"
        }
        selectedPhotoItem = nil
    }

    private func removeFloorPlanImage() {
        guard let existing = activeFloorPlanImage else { return }

        // Keep both the tombstone and local file until the server confirms the
        // deletion so an offline failure can retry without resurrecting it.
        cachedFloorPlanImage = nil
        existing.isDeleted = true
        existing.isSynced = false
        existing.updatedAt = Date()
        modelContext.saveWithLogging(label: #function)
        Task { await SyncEngine.shared.syncAll(modelContext: modelContext) }
    }


    private func loadCachedFloorPlanImage() {
        floorPlanLoadTask?.cancel()
        guard let requestedAreaId = selectedDiningAreaId else {
            cachedFloorPlanImage = nil
            return
        }
        if let floorPlan = activeFloorPlanImage, !floorPlan.imageFilename.isEmpty {
            if let path = floorPlan.resolvedImagePath, let uiImage = UIImage(contentsOfFile: path) {
                cachedFloorPlanImage = uiImage
            } else {
                // If not found locally, try to download from Storage
                floorPlanLoadTask = Task {
                    do {
                        let data = try await NetworkManager.shared.downloadFloorPlanMedia(fileName: floorPlan.imageFilename)
                        guard !Task.isCancelled, selectedDiningAreaId == requestedAreaId else { return }
                        if let downloadedImage = UIImage(data: data) {
                            // Save locally for future use
                            let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                            let fileURL = docsURL.appendingPathComponent(floorPlan.imageFilename)
                            try? data.write(to: fileURL)

                            await MainActor.run {
                                guard self.selectedDiningAreaId == requestedAreaId else { return }
                                self.cachedFloorPlanImage = downloadedImage
                            }
                        }
                    } catch {
                        print("Failed to download floor plan image: \(error)")
                        await MainActor.run {
                            if self.selectedDiningAreaId == requestedAreaId { self.cachedFloorPlanImage = nil }
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
        let branchId = BranchContext.shared.activeBranchIDString
        guard let diningAreaId = selectedDiningAreaId else { return nil }
        return floorPlanImages.first(where: {
            $0.diningAreaId == diningAreaId && !$0.isDeleted
                && ($0.branchId == branchId || $0.branchId.isEmpty)
        })
    }

    private var bgScaleBinding: Binding<Double> {
        Binding(
            get: { activeFloorPlanImage?.scale ?? 1.0 },
            set: { newValue in
                if let img = activeFloorPlanImage {
                    img.scale = newValue
                    img.isSynced = false
                    img.updatedAt = Date()
                    modelContext.saveWithLogging(label: #function)
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
                    modelContext.saveWithLogging(label: #function)
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
                    modelContext.saveWithLogging(label: #function)
                }
            }
        )
    }

    // MARK: - Table Layout Presets (Templates) Operations
    private static let layoutPresetSchemaVersion = 1

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func verifiedBackgroundData(filename: String, expectedChecksum: String? = nil) async throws -> Data {
        let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent(filename)
        let data: Data
        if let local = try? Data(contentsOf: fileURL) {
            data = local
        } else {
            data = try await NetworkManager.shared.downloadFloorPlanMedia(fileName: filename)
            try data.write(to: fileURL, options: .atomic)
        }
        if let expectedChecksum, sha256(data) != expectedChecksum {
            throw NSError(domain: "TableLayoutPreset", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Background image failed integrity verification."
            ])
        }
        return data
    }

    @MainActor
    private func saveLayoutPreset(name: String) async {
        guard !isPresetOperationRunning else { return }
        isPresetOperationRunning = true
        defer { isPresetOperationRunning = false }

        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
        let branchId = BranchContext.shared.activeBranchIDString
        guard let diningAreaId = selectedDiningAreaId else { return }

        let floorTables = tables.filter { tableBelongsToSelectedArea($0) && !$0.isDeleted }
        let items = floorTables.map { table in
            TableLayoutItem(
                id: table.id,
                tableNumber: table.tableNumber,
                capacity: table.capacity,
                tableShape: table.tableShape,
                positionX: table.positionX,
                positionY: table.positionY,
                layoutScale: table.resolvedLayoutScale,
                zone: table.zone
            )
        }

        guard let data = try? JSONEncoder().encode(items),
              let json = String(data: data, encoding: .utf8) else { return }

        let bgImage = activeFloorPlanImage
        let bgFilename = bgImage?.imageFilename
        var bgChecksum: String?
        if let bgFilename {
            do {
                let imageData = try await verifiedBackgroundData(filename: bgFilename)
                _ = try await NetworkManager.shared.uploadFloorPlanMedia(data: imageData, fileName: bgFilename)
                bgChecksum = sha256(imageData)
            } catch {
                presetOperationError = "Template was not saved because its background image could not be verified or uploaded: \(error.localizedDescription)"
                return
            }
        }
        let bgScale = bgImage?.scale ?? 1.0
        let bgOffsetX = bgImage?.offsetX ?? 0.0
        let bgOffsetY = bgImage?.offsetY ?? 0.0

        if let existing = layoutPresets.first(where: {
            $0.diningAreaId == diningAreaId &&
            $0.name.lowercased() == name.lowercased() &&
            $0.branchId == branchId &&
            $0.merchantId == merchantId &&
            !$0.isDeleted
        }) {
            existing.tableLayoutJson = json
            existing.bgImageFilename = bgFilename
            existing.bgImageChecksum = bgChecksum
            existing.schemaVersion = Self.layoutPresetSchemaVersion
            existing.bgImageScale = bgScale
            existing.bgImageOffsetX = bgOffsetX
            existing.bgImageOffsetY = bgOffsetY
            existing.updatedAt = Date()
            existing.isSynced = false
        } else {
            let preset = TableLayoutPreset(
                merchantId: merchantId,
                branchId: branchId,
                diningAreaId: diningAreaId,
                name: name,
                bgImageFilename: bgFilename,
                bgImageChecksum: bgChecksum,
                bgImageScale: bgScale,
                bgImageOffsetX: bgOffsetX,
                bgImageOffsetY: bgOffsetY,
                tableLayoutJson: json,
                schemaVersion: Self.layoutPresetSchemaVersion
            )
            modelContext.insert(preset)
        }

        modelContext.saveWithLogging(label: #function)
        APHaptic.trigger()

        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }

    @MainActor
    private func applyLayoutPreset(_ preset: TableLayoutPreset) async {
        guard !isPresetOperationRunning else { return }
        isPresetOperationRunning = true
        defer { isPresetOperationRunning = false }

        let currentMerchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
        let currentBranchId = BranchContext.shared.activeBranchIDString
        guard let diningAreaId = selectedDiningAreaId, preset.diningAreaId == diningAreaId else { return }

        // Security check
        guard preset.merchantId == currentMerchantId && preset.branchId == currentBranchId else {
            print("Security boundary breach: layout preset merchant/branch mismatch")
            return
        }
        guard preset.schemaVersion <= Self.layoutPresetSchemaVersion else {
            presetOperationError = "This template was created by a newer app version and cannot be applied safely."
            return
        }

        guard let data = preset.tableLayoutJson.data(using: .utf8),
              let items = try? JSONDecoder().decode([TableLayoutItem].self, from: data) else {
            presetOperationError = "The template data is damaged or incomplete."
            return
        }

        let otherFloorsTablesCount = tables.filter {
            tableBelongsToActiveBranch($0) && !tableBelongsToSelectedArea($0) && !$0.isDeleted
        }.count
        let availableSlots = 80 - otherFloorsTablesCount
        guard items.count <= availableSlots else {
            presetOperationError = "This template needs \(items.count) tables, but only \(max(0, availableSlots)) slots are available."
            return
        }

        let floorTables = tables.filter { tableBelongsToSelectedArea($0) && !$0.isDeleted }
        guard !floorTables.contains(where: { $0.status.lowercased() == "occupied" || $0.sessions.contains(where: { $0.isActive }) }) else {
            presetOperationError = "Close active table sessions before applying a template."
            return
        }

        var downloadedBackground: Data?
        if let newFilename = preset.bgImageFilename {
            do {
                downloadedBackground = try await verifiedBackgroundData(
                    filename: newFilename,
                    expectedChecksum: preset.bgImageChecksum
                )
            } catch {
                presetOperationError = "The template was not applied because its background image is unavailable or invalid."
                return
            }
        }

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
                    branchId: currentBranchId,
                    diningAreaId: diningAreaId,
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

        if let downloadedBackground, let image = UIImage(data: downloadedBackground) {
            cachedFloorPlanImage = image
        } else {
            loadCachedFloorPlanImage()
        }

        var matchedTableIds = Set<UUID>()

        for item in items {
            if let existingTable = tables.first(where: { $0.id == item.id })
                ?? floorTables.first(where: { $0.tableNumber == item.tableNumber }) {
                matchedTableIds.insert(existingTable.id)
                existingTable.tableNumber = item.tableNumber
                existingTable.floor = selectedFloor
                existingTable.floorId = floors.first(where: { $0.id == selectedFloor })?.uuid
                existingTable.branchId = currentBranchId
                existingTable.isDeleted = false
                existingTable.positionX = item.positionX
                existingTable.positionY = item.positionY
                existingTable.layoutScale = item.layoutScale.flatMap { $0 > 0 ? $0 : nil } ?? 1.0
                existingTable.capacity = item.capacity
                existingTable.tableShape = item.tableShape
                existingTable.isRound = item.tableShape == "circle" || item.tableShape == "oval"
                existingTable.zone = item.zone
                existingTable.updatedAt = Date()
                existingTable.isSynced = false
            } else {
                let newTable = RestaurantTable(
                    id: item.id,
                    tableNumber: item.tableNumber,
                    capacity: item.capacity,
                    tableShape: item.tableShape,
                    positionX: item.positionX,
                    positionY: item.positionY,
                    layoutScale: item.layoutScale.flatMap { $0 > 0 ? $0 : nil } ?? 1.0,
                    floor: selectedFloor,
                    floorId: floors.first(where: { $0.id == selectedFloor })?.uuid,
                    branchId: currentBranchId,
                    zone: item.zone
                )
                modelContext.insert(newTable)
                matchedTableIds.insert(newTable.id)
            }
        }

        for table in floorTables {
            if !matchedTableIds.contains(table.id) {
                table.isDeleted = true
                table.isSynced = false
                table.updatedAt = Date()
            }
        }

        modelContext.saveWithLogging(label: #function)
        APHaptic.trigger()

        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }

    private func deleteLayoutPreset(_ preset: TableLayoutPreset) {
        let currentMerchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
        let currentBranchId = BranchContext.shared.activeBranchIDString

        // Security check
        guard preset.merchantId == currentMerchantId && preset.branchId == currentBranchId else { return }

        preset.isDeleted = true
        preset.updatedAt = Date()
        preset.isSynced = false

        modelContext.saveWithLogging(label: #function)
        APHaptic.trigger()

        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }

    private var modernStatusWidget: some View {
        HStack(spacing: 6) {
            modernStatusDot(color: .appTeal, label: "table_status_vacant".t, count: countTables(status: "vacant"))
            modernStatusDot(color: .appRose, label: "table_status_occupied".t, count: countTables(status: "occupied"))
            modernStatusDot(color: .appAmber, label: "table_status_reserved".t, count: countTables(status: "reserved"))
            modernStatusDot(color: .appAccent, label: "table_status_cleaning_short".t, count: countTables(status: "cleaning"))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .apLiquidGlass(tint: Color.appTeal.opacity(0.045), in: Capsule())
    }

    private var headerEditModeBadge: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(Color.appAccent)
                .frame(width: 7, height: 7)
            Text("กำลังแก้ไข")
                .font(.system(size: 11, weight: .bold))
            Text(floors.first(where: { $0.id == selectedFloor })?.name ?? "Floor \(selectedFloor)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.textSecondary)
        }
        .foregroundColor(.appAccent)
        .padding(.horizontal, 12)
        .frame(height: 36)
        .apLiquidGlass(tint: Color.appAccent.opacity(0.14), in: Capsule())
    }

    private func modernStatusDot(color: Color, label: String, count: Int) -> some View {
        HStack(spacing: 3) {
            Text("\(count)")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .frame(minWidth: 12)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(color)
                .clipShape(Capsule())
                .scaleEffect(count > 0 ? 1.08 : 1.0)
                .animation(.spring(response: 0.25, dampingFraction: 0.6), value: count)

            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.textSecondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .fixedSize(horizontal: true, vertical: false)
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
                modelContext.insert(FloorData(floorNumber: nextId, name: name, branchId: activeBranchId, sortOrder: floors.count))
                modelContext.saveWithLogging(label: #function)
                Task { await SyncEngine.shared.syncAll(modelContext: modelContext) }
                selectFloor(nextId)
                floorNameInput = ""
                APHaptic.trigger()
            }
            Button("cancel".t, role: .cancel) { floorNameInput = "" }
        }
        .confirmationDialog("table_floor_remove_confirm".t, isPresented: $showingRemoveFloorConfirm, titleVisibility: .visible) {
            Button("table_floor_remove_btn".t, role: .destructive) {
                deleteSelectedDiningArea()
            }
            Button("cancel".t, role: .cancel) { }
        }
        // Rename alert
        .alert("table_floor_rename_title".t, isPresented: $showingRenameFloorAlert) {
            TextField("", text: $floorNameInput)
            Button("ok_btn".t) {
                if let fid = renamingFloorId, !floorNameInput.isEmpty {
                    if let floor = floors.first(where: { $0.id == fid }) {
                        floor.name = floorNameInput; floor.isSynced = false; floor.updatedAt = Date()
                        modelContext.saveWithLogging(label: #function)
                        Task { await SyncEngine.shared.syncAll(modelContext: modelContext) }
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
                selectFloor(floor.id)
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
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
        let branchId = BranchContext.shared.activeBranchIDString
        guard let diningAreaId = selectedDiningAreaId else { return [] }
        return layoutPresets.filter {
            $0.diningAreaId == diningAreaId &&
            $0.merchantId == merchantId &&
            $0.branchId == branchId &&
            !$0.isDeleted
        }
    }

    @ViewBuilder
    private var layoutPresetsToolbar: some View {
        Menu {
            Section("เลือกรูปแบบผัง") {
                if activePresets.isEmpty {
                    Text("No templates saved")
                } else {
                    ForEach(activePresets) { preset in
                        Button(action: {
                            Task { await applyLayoutPreset(preset) }
                        }) {
                            Label(preset.name, systemImage: "square.stack.3d.up")
                        }
                    }
                }
            }

            Button(action: { showingSavePresetAlert = true }) {
                Label("table_presets_save_alert".t, systemImage: "square.and.arrow.down")
            }

            if !activePresets.isEmpty {
                Menu {
                    ForEach(activePresets) { preset in
                        Button(role: .destructive, action: {
                            deleteLayoutPreset(preset)
                        }) {
                            Label("ลบรูปแบบ “\(preset.name)”", systemImage: "trash")
                        }
                    }
                } label: {
                    Label("จัดการรูปแบบที่บันทึก", systemImage: "ellipsis.circle")
                }
            }
        } label: {
            Label("รูปแบบผัง", systemImage: "square.stack.3d.up")
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 12)
                .frame(height: 34)
                .apChromeSurface(tint: Color.appAccent.opacity(0.06), in: Capsule())
        }
        .buttonStyle(.plain)
        .alert("table_presets_save_alert".t, isPresented: $showingSavePresetAlert) {
            TextField("table_presets_enter_name".t, text: $presetNameInput)
            Button("ok_btn".t) {
                if !presetNameInput.isEmpty {
                    let name = presetNameInput
                    Task { await saveLayoutPreset(name: name) }
                }
                presetNameInput = ""
            }
            Button("cancel".t, role: .cancel) { presetNameInput = "" }
        }
        .fixedSize(horizontal: true, vertical: false)
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
                            modelContext.saveWithLogging(label: #function)
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
            Section("table_floor_level_lbl".t) {
                ForEach(floors) { floor in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectFloor(floor.id)
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
            }

            Section("table_zone_lbl".t) {
                ForEach(zones, id: \.self) { zone in
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
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "building.2.crop.circle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.appAccent)
                Text("\(currentFloorName) · \("table_zone_\(selectedZone.lowercased())".t)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.textSecondary)
            }
            .padding(.horizontal, 8)
            .frame(height: 40)
        }
        .alert("table_floor_add_btn".t, isPresented: $showingAddFloorAlert) {
            TextField("table_floor_new_name".t, text: $floorNameInput)
            Button("table_create_btn".t) {
                let nextId = (floors.map(\.id).max() ?? 0) + 1
                let name = floorNameInput.isEmpty
                    ? String(format: "table_floor_new_name".t, nextId)
                    : floorNameInput
                modelContext.insert(FloorData(floorNumber: nextId, name: name, branchId: activeBranchId, sortOrder: floors.count))
                modelContext.saveWithLogging(label: #function)
                Task { await SyncEngine.shared.syncAll(modelContext: modelContext) }
                selectFloor(nextId)
                floorNameInput = ""
                APHaptic.trigger()
            }
            Button("cancel".t, role: .cancel) { floorNameInput = "" }
        }
        .confirmationDialog("table_floor_remove_confirm".t, isPresented: $showingRemoveFloorConfirm, titleVisibility: .visible) {
            Button("table_floor_remove_btn".t, role: .destructive) {
                deleteSelectedDiningArea()
            }
            Button("cancel".t, role: .cancel) { }
        }
        .alert("table_floor_rename_title".t, isPresented: $showingRenameFloorAlert) {
            TextField("", text: $floorNameInput)
            Button("ok_btn".t) {
                if let fid = renamingFloorId, !floorNameInput.isEmpty {
                    if let floor = floors.first(where: { $0.id == fid }) {
                        floor.name = floorNameInput; floor.isSynced = false; floor.updatedAt = Date()
                        modelContext.saveWithLogging(label: #function)
                        Task { await SyncEngine.shared.syncAll(modelContext: modelContext) }
                    }
                }
                renamingFloorId = nil
                floorNameInput = ""
            }
            Button("cancel".t, role: .cancel) { renamingFloorId = nil; floorNameInput = "" }
        }
    }

    private var tableActionsMenu: some View {
        Menu {
            Section {
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                        tableViewModeRaw = isListView ? "map" : "list"
                        APHaptic.trigger()
                    }
                } label: {
                    Label(
                        isListView ? "table_view_mode_map".t : "table_view_mode_list".t,
                        systemImage: isListView ? "map" : "list.bullet"
                    )
                }

                if !isListView {
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                            setLayoutMode(isGridMode ? "canvas" : "grid")
                            APHaptic.trigger()
                        }
                    } label: {
                        Label(
                            isGridMode ? "table_layout_mode_canvas".t : "table_layout_mode_grid".t,
                            systemImage: isGridMode ? "rectangle.on.rectangle.angled" : "square.grid.2x2"
                        )
                    }
                }
            }

            Section {
                Button {
                    if isEditingLayout {
                        isEditingLayout = false
                        isLayoutManagerAuthorized = false
                        layoutSelectedTableId = nil
                        layoutSelectedTableIds.removeAll()
                    } else {
                        checkManagerPermission(for: .toggleEditLayout(true))
                    }
                    APHaptic.trigger()
                } label: {
                    Label(
                        isEditingLayout ? "table_exit_edit_mode_acc".t : "table_enter_edit_mode_acc".t,
                        systemImage: isEditingLayout ? "pencil.slash" : "pencil"
                    )
                }

                Button {
                    isMovementLocked.toggle()
                    APHaptic.trigger()
                } label: {
                    Label(
                        isMovementLocked ? "Unlock canvas" : "Lock canvas",
                        systemImage: isMovementLocked ? "lock.open.fill" : "lock.fill"
                    )
                }
            }

            Section {
                Button {
                    guard !isOpeningBatchQR, !showingBatchQRSheet else { return }
                    isOpeningBatchQR = true
                    DispatchQueue.main.async { showingBatchQRSheet = true }
                } label: {
                    Label("table_qr_all_codes_title".t, systemImage: "qrcode")
                }

                let activeTables = searchTablesList.filter { !$0.isDeleted && tableBelongsToSelectedArea($0) }
                if !activeTables.isEmpty {
                    Menu {
                        ForEach(activeTables) { table in
                            Button {
                                findTable(table)
                            } label: {
                                Text(LocalizationManager.shared.t("table_find_item_template", table.tableNumber, table.capacity))
                            }
                        }
                    } label: {
                        Label("search".t, systemImage: "magnifyingglass")
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 40, height: 40)
        }
        .accessibilityLabel("more_actions".t)
    }

    @ViewBuilder
    private var quickActionsBar: some View {
        HStack(spacing: 0) {
            findTableCompactButton

            Divider()
                .frame(width: 1, height: 16)
                .background(Color.appBorderSubtle)

            printQRCodesCompactButton

            Divider()
                .frame(width: 1, height: 16)
                .background(Color.appBorderSubtle)

            lockPanZoomCompactButton

            Divider()
                .frame(width: 1, height: 16)
                .background(Color.appBorderSubtle)

            editLayoutSwitchCompactButton

            Divider()
                .frame(width: 1, height: 16)
                .background(Color.appBorderSubtle)

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
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(tableViewModeRaw == "map" ? "table_view_mode_list".t : "table_view_mode_map".t)

            Divider()
                .frame(width: 1, height: 16)
                .background(Color.appBorderSubtle)

            // Grid / Canvas toggle (only in map view)
            if !isListView {
                Button(action: {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                        setLayoutMode(isGridMode ? "canvas" : "grid")
                        APHaptic.trigger()
                    }
                }) {
                    Image(systemName: isGridMode ? "rectangle.on.rectangle.angled" : "square.grid.2x2")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(isGridMode ? .appAccent : .textPrimary)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isGridMode ? "table_layout_mode_canvas".t : "table_layout_mode_grid".t)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .apLiquidGlass(tint: Color.appAccent.opacity(0.035), in: Capsule())
    }

    @ViewBuilder
    private var findTableCompactButton: some View {
        let activeTables = searchTablesList.filter { !$0.isDeleted && tableBelongsToSelectedArea($0) }
        if !activeTables.isEmpty {
            Menu {
                ForEach(activeTables) { table in
                    Button(action: {
                        findTable(table)
                    }) {
                        Text(LocalizationManager.shared.t("table_find_item_template", table.tableNumber, table.capacity))
                    }
                }
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(isMovementLocked ? .textSecondary.opacity(0.4) : .appAccent)
                    .frame(width: 40, height: 40)
                    .background(Color.clear)
                    .contentShape(Rectangle())
            }
            .disabled(isMovementLocked)
        }
    }

    @ViewBuilder
    private var printQRCodesCompactButton: some View {
        Button(action: {
            guard !isOpeningBatchQR, !showingBatchQRSheet else { return }
            APHaptic.trigger()
            withAnimation(.easeOut(duration: 0.15)) {
                isOpeningBatchQR = true
            }
            // Yield a runloop so the loading overlay paints before the heavy cover mounts.
            DispatchQueue.main.async {
                showingBatchQRSheet = true
            }
        }) {
            ZStack {
                if isOpeningBatchQR && !showingBatchQRSheet {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.appAccent)
                } else {
                    Image(systemName: "qrcode")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.textPrimary)
                }
            }
            .frame(width: 40, height: 40)
            .background(Color.clear)
        }
        .buttonStyle(.plain)
        .disabled(isOpeningBatchQR)
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
                .frame(width: 40, height: 40)
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
                isLayoutManagerAuthorized = false
                Task {
                    await SyncEngine.shared.syncAll(modelContext: modelContext)
                }
            }
            APHaptic.trigger()
        }) {
            Image(systemName: isEditingLayout ? "pencil.and.outline" : "pencil")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(isEditingLayout ? .appAccent : .textSecondary)
                .frame(width: 40, height: 40)
                .background(isEditingLayout ? Color.appAccent.opacity(0.12) : Color.clear)
                .cornerRadius(6)
                .scaleEffect(isEditingLayout ? 1.05 : 1.0)
                .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isEditingLayout)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isEditingLayout ? "table_exit_edit_mode_acc".t : "table_enter_edit_mode_acc".t)
    }

    private func backToLoginButton(isCompact: Bool) -> some View {
        Button {
            APHaptic.trigger()
            sessionManager.lockStaffSession(modelContext: modelContext)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 12, weight: .bold))
                if !isCompact {
                    Text("table_back_to_login".t)
                        .font(.system(size: 12, weight: .bold))
                }
            }
            .foregroundColor(.textPrimary)
            .frame(width: isCompact ? 38 : nil, height: 40)
            .padding(.horizontal, isCompact ? 0 : 8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("table_back_to_login".t)
    }

    private var headerTitleView: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(Color.appAccent.opacity(isEditingLayout ? 0.24 : 0.15))
                    .frame(width: 24, height: 24)
                Image(systemName: isEditingLayout ? "square.and.pencil" : "tablecells.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.appAccent)
            }
            Text(isEditingLayout ? "แก้ไขผังโต๊ะ" : "table_management_title".t)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.textPrimary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 6)
        .frame(height: 40)
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
                        ForEach(activeRequestsForSelectedArea) { request in
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

    private func updateSearchTablesList(with newTables: [RestaurantTable]) {
        // SwiftData models are reference types, so comparing the old and new arrays can
        // miss in-place status/area changes. Keep this lightweight presentation cache fresh.
        searchTablesList = newTables.filter { !$0.isDeleted && tableBelongsToActiveBranch($0) }
    }

    private func findTable(_ table: RestaurantTable) {
        if isGridMode {
            guard selectedZone == "All" || table.zone == selectedZone else {
                selectedZone = "All"
                DispatchQueue.main.async { gridFocusTableId = table.id }
                return
            }
            gridFocusTableId = table.id
        } else {
            focusTableId = table.id
        }
    }
}

private struct QuickClearDialogsModifier: ViewModifier {
    @Binding var isVacantConfirmPresented: Bool
    let pendingVacantTableNumber: String
    let onConfirmVacant: () -> Void
    let onCancelVacant: () -> Void

    @Binding var isReasonPresented: Bool
    @Binding var reason: String
    @Binding var error: String?
    let onConfirmVoid: (String) -> Void
    let onCancelVoid: () -> Void

    func body(content: Content) -> some View {
        content
            .alert(
                LocalizationManager.shared.t("confirm_clear_table_title", pendingVacantTableNumber),
                isPresented: $isVacantConfirmPresented
            ) {
                Button("cancel_btn".t, role: .cancel) {
                    onCancelVacant()
                }
                Button("confirm_clear_table_btn".t, role: .destructive) {
                    onConfirmVacant()
                }
            } message: {
                Text("confirm_clear_table_msg".t)
            }
            .alert("ยกเลิกออเดอร์และเคลียร์โต๊ะ", isPresented: $isReasonPresented) {
                TextField("เหตุผลที่ยกเลิกออเดอร์", text: $reason)
                Button("ยืนยันการยกเลิก", role: .destructive) {
                    let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
                    reason = ""
                    onConfirmVoid(trimmed.isEmpty ? "Table cleared by manager" : trimmed)
                }
                Button("cancel_btn".t, role: .cancel) {
                    reason = ""
                    onCancelVoid()
                }
            } message: {
                Text("ออเดอร์ที่ยังไม่ชำระจะถูกยกเลิก คืนสต็อก และบันทึกประวัติผู้อนุมัติก่อนเคลียร์โต๊ะ")
            }
            .alert(
                "ไม่สามารถเคลียร์โต๊ะได้",
                isPresented: Binding(
                    get: { error != nil },
                    set: { if !$0 { error = nil } }
                )
            ) {
                Button("ok_btn".t) { error = nil }
            } message: {
                Text(error ?? "")
            }
    }
}

// MARK: - Table Detail / Action View

struct TableDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var lm: LocalizationManager
    @EnvironmentObject private var sessionManager: AppSessionManager
    @Bindable var table: RestaurantTable
    @Environment(\.dismiss) private var dismiss

    @Binding var selectedTab: MainDashboardView.DashboardTab
    @Binding var posTableSession: TableSession?
    let allowsDeletion: Bool

    @Query(sort: \RestaurantTable.tableNumber) private var allTables: [RestaurantTable]
    @Query(filter: #Predicate<RegisterSession> { $0.closedAt == nil && !$0.isDeleted })
    private var activeRegisterSessions: [RegisterSession]

    @State private var dynamicQRUrl: String = ""
    @State private var showingQRPopover = false
    @State private var editingCapacity = false
    @State private var tempCapacity: String = ""
    @State private var showNoActiveShiftAlert = false
    // H-2: Table Transfer
    @State private var showTransferSheet = false

    @AppStorage("logged_in_email") private var loggedInEmail = "owner@alphapos.com"
    @AppStorage("enable_web_ordering") private var enableWebOrdering = true
    @AppStorage("offline_sync_mode") private var offlineSyncMode = false
    /// Reads UserDefaults override first, then falls back to Config.plist LOCAL_SERVER_URL.
    private var customerWebBaseUrl: String {
        let ud = UserDefaults.standard.string(forKey: "dynamic_customer_web_url") ?? ""
        return ud.isEmpty ? "https://sync.alphaposweb.com" : ud
    }
    /// Returns the active staff display name, or falls back to the logged-in owner name.
    private var activeCashierDisplayName: String {
        let staffName = sessionManager.currentStaffSession?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !staffName.isEmpty { return staffName }
        return UserDefaults.standard.string(forKey: "logged_in_name") ?? "Staff"
    }
    @State private var showingManagerPinSheet = false
    @State private var deletionErrorMessage = ""
    @State private var showingDeletionError = false

    // Guard rail: block clearing a table that still has live kitchen tickets.
    @State private var showPendingTicketDialog = false
    @State private var pendingClearStatus: String? = nil   // "vacant" | "cleaning" | "reserved"
    @State private var showVoidReasonPrompt = false
    @State private var showingManagerPinSheetForVoid = false
    @State private var voidReasonText = ""
    @State private var contentPresented = false

    private func deleteTableWithAuth() {
        if sessionManager.can(.managerOverride) {
            performDelete()
        } else {
            showingManagerPinSheet = true
        }
    }

    private func performDelete() {
        guard !table.joinedGroupHasActiveSession else {
            deletionErrorMessage = "ไม่สามารถลบโต๊ะที่กำลังใช้งาน กรุณาเคลียร์โต๊ะก่อน"
            showingDeletionError = true
            return
        }

        table.prepareForDeletion()
        modelContext.saveWithLogging(label: #function)

        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
        dismiss()
    }

    private func updateTableZone(_ newZone: String) {
        table.zone = newZone
        table.isSynced = false
        table.updatedAt = Date()
        modelContext.saveWithLogging(label: #function)
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

    private var canReserveTable: Bool {
        (table.joinedParent ?? table).status.lowercased() == "vacant"
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

        if newStatus != "occupied" {
            // DEFENSIVE NET: never strand a live kitchen ticket when a table is
            // freed. Any open order still gets terminalized (served) before the
            // session closes, so the KDS can't keep showing a ghost ticket.
            // (The UI offers an explicit Serve/Void choice up front; this is the
            // last-line guarantee for every code path that clears a table.)
            for activeSession in leader.sessions.filter({ $0.isActive }) {
                activeSession.terminalizeOpenOrders(.serve, in: modelContext)
                activeSession.isActive = false
                activeSession.endedAt = Date()
                activeSession.isSynced = false
                activeSession.updatedAt = Date()
            }
            for child in leader.joinedChildren {
                for activeSession in child.sessions.filter({ $0.isActive }) {
                    activeSession.terminalizeOpenOrders(.serve, in: modelContext)
                    activeSession.isActive = false
                    activeSession.endedAt = Date()
                    activeSession.isSynced = false
                    activeSession.updatedAt = Date()
                }
            }
            if let current = posTableSession,
               ([leader] + leader.joinedChildren).contains(where: {
                   current.table?.id == $0.id
               }) {
                posTableSession = nil
            }
        }

        modelContext.saveWithLogging(label: #function)
    }

    // MARK: - Guard-railed table clearing
    //
    // Standards-based flow: a cashier may not silently free a table that still
    // has food live at the kitchen. `requestClear` checks for pending tickets
    // and, if found, forces an explicit choice (Serve vs Void) before the table
    // status changes. This is what prevents the "table vacant but ticket still
    // on the KDS" divergence at the source.

    /// Entry point for the Vacant / Cleaning / Reserved buttons.
    private func requestClear(_ newStatus: String) {
        guard newStatus != "reserved" || canReserveTable else { return }

        let leader = table.joinedParent ?? table
        let hasPending = leader.sessions.contains { $0.isActive && $0.hasPendingKitchenTickets }
            || leader.joinedChildren.contains { child in
                child.sessions.contains { $0.isActive && $0.hasPendingKitchenTickets }
            }

        if hasPending {
            // Block and ask the operator how to resolve the open ticket(s).
            pendingClearStatus = newStatus
            showPendingTicketDialog = true
            APHaptic.trigger()
        } else {
            applyClear(newStatus)
        }
    }

    /// Actually change the table status and sync. `updateGroupStatus` already
    /// terminalizes any lingering orders as a defensive net.
    ///
    /// Always PATCH-close remote sessions first. Vacant/cleaning uploads alone
    /// are rejected by the DB guard while any `table_sessions.is_active = 1`
    /// remains — without this, the next pull resurrects the old occupied state
    /// (e.g. multi-day elapsed timers like T4 @ 4,565 min).
    private func applyClear(_ newStatus: String) {
        let leader = table.joinedParent ?? table
        let tableNumbers = ([leader] + leader.joinedChildren).map(\.tableNumber)
        updateGroupStatus(newStatus)
        Task {
            for number in tableNumbers where !number.isEmpty {
                _ = try? await NetworkManager.shared.closeTableSession(tableNumber: number)
            }
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
        dismiss()
    }

    /// Resolution 1: the food really was delivered — mark served, then clear.
    private func resolvePendingAsServed() {
        let leader = table.joinedParent ?? table
        for session in leader.sessions.filter({ $0.isActive }) {
            session.terminalizeOpenOrders(.serve, in: modelContext)
        }
        for child in leader.joinedChildren {
            for session in child.sessions.filter({ $0.isActive }) {
                session.terminalizeOpenOrders(.serve, in: modelContext)
            }
        }
        if let status = pendingClearStatus { applyClear(status) }
        pendingClearStatus = nil
    }

    /// Resolution 2: the order is abandoned — void it (with reason + audit),
    /// then clear.
    private func resolvePendingAsVoid(reason: String) {
        let employeeId = sessionManager.currentStaffSession?.employeeId
        let leader = table.joinedParent ?? table
        let resolution: TableClearResolution = .void(reason: reason, employeeId: employeeId)
        for session in leader.sessions.filter({ $0.isActive }) {
            session.terminalizeOpenOrders(resolution, in: modelContext)
        }
        for child in leader.joinedChildren {
            for session in child.sessions.filter({ $0.isActive }) {
                session.terminalizeOpenOrders(resolution, in: modelContext)
            }
        }
        if let status = pendingClearStatus { applyClear(status) }
        pendingClearStatus = nil
        voidReasonText = ""
    }


    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 12) {
                        identityHeaderSection
                            .opacity(contentPresented ? 1 : 0)
                            .offset(y: contentPresented ? 0 : -16)
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.55), value: contentPresented)

                        groupingSection
                            .opacity(contentPresented ? 1 : 0)
                            .offset(y: contentPresented ? 0 : 12)
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.55).delay(0.06), value: contentPresented)

                        actionsSection
                            .opacity(contentPresented ? 1 : 0)
                            .offset(y: contentPresented ? 0 : 18)
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.55).delay(0.12), value: contentPresented)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .padding(.bottom, 16)
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
            .onAppear {
                if reduceMotion {
                    contentPresented = true
                } else {
                    contentPresented = false
                    DispatchQueue.main.async {
                        contentPresented = true
                    }
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
            .alert("ไม่สามารถลบโต๊ะ", isPresented: $showingDeletionError) {
                Button("ok_btn".t, role: .cancel) {}
            } message: {
                Text(deletionErrorMessage)
            }
            // GUARD RAIL: pending kitchen tickets block a silent table clear.
            .confirmationDialog(
                "table_pending_ticket_title".t,
                isPresented: $showPendingTicketDialog,
                titleVisibility: .visible
            ) {
                Button("table_pending_ticket_served".t) {
                    resolvePendingAsServed()
                }
                Button("table_pending_ticket_void".t, role: .destructive) {
                    if sessionManager.can(.managerOverride) {
                        showVoidReasonPrompt = true
                    } else {
                        showingManagerPinSheetForVoid = true
                    }
                }
                Button("cancel".t, role: .cancel) { pendingClearStatus = nil }
            } message: {
                Text("table_pending_ticket_message".t)
            }
            // Manager PIN gate for the void path (parity with other voids).
            .sheet(isPresented: $showingManagerPinSheetForVoid) {
                ManagerPINVerificationSheet(
                    isPresented: $showingManagerPinSheetForVoid,
                    onSuccess: { showVoidReasonPrompt = true }
                )
            }
            // Capture a void reason for the audit log.
            .alert("table_pending_ticket_void".t, isPresented: $showVoidReasonPrompt) {
                TextField("table_void_reason_placeholder".t, text: $voidReasonText)
                Button("confirm".t, role: .destructive) {
                    let reason = voidReasonText.trimmingCharacters(in: .whitespacesAndNewlines)
                    resolvePendingAsVoid(reason: reason.isEmpty ? "No reason given" : reason)
                }
                Button("cancel".t, role: .cancel) { pendingClearStatus = nil; voidReasonText = "" }
            } message: {
                Text("table_void_reason_prompt".t)
            }
        }
    }

    // MARK: - Identity Header

    private var identityHeaderSection: some View {
        let leader = table.joinedParent ?? table
        let previewSession = leader.sessions.first(where: { $0.isActive && Calendar.current.isDateInToday($0.startedAt) })
        let itemCount = previewSession?.itemCount ?? 0
        let status = statusColor(table.status)

        return HStack(alignment: .center, spacing: 14) {
            DynamicTableLayoutView(
                tableNumber: table.tableNumber,
                capacity: table.capacity,
                status: table.status,
                isEditingLayout: false,
                isDragging: false,
                isSelected: false,
                statusColor: status,
                itemCount: itemCount
            )
            // Keep the original layout canvas so chairs are not clipped; only
            // scale the rendered preview to preserve the compact modal.
            .frame(width: 120, height: 120)
            .scaleEffect(0.78)
            .frame(width: 96, height: 96)

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(LocalizationManager.shared.t("table_number_template", table.tableNumber))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)

                    Text("table_status_\(table.status.lowercased())".t)
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(status)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(status.opacity(0.12), in: Capsule())
                }

                capacityEditorRow

                zonePickerRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(
            Color.appSurface.opacity(0.72),
            in: RoundedRectangle(cornerRadius: APRadius.xl, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: APRadius.xl, style: .continuous)
                .stroke(status.opacity(0.18), lineWidth: 1)
        )
    }

    private var capacityEditorRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "chair.lounge.fill")
                .font(.subheadline)
                .foregroundColor(.textSecondary)
                .frame(width: 18)

            Text("table_capacity_lbl".t)
                .font(.subheadline)
                .foregroundColor(.textSecondary)

            if editingCapacity {
                HStack(spacing: 0) {
                    Button {
                        if table.capacity > 1 {
                            table.capacity -= 1
                            table.isSynced = false
                            table.updatedAt = Date()
                            modelContext.saveWithLogging(label: #function)
                            Task { await SyncEngine.shared.syncAll(modelContext: modelContext) }
                        }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.appAccent)
                    }

                    Text("\(table.capacity)")
                        .font(.headline)
                        .foregroundColor(.textPrimary)
                        .frame(width: 30)

                    Button {
                        if table.capacity < 20 {
                            table.capacity += 1
                            table.isSynced = false
                            table.updatedAt = Date()
                            modelContext.saveWithLogging(label: #function)
                            Task { await SyncEngine.shared.syncAll(modelContext: modelContext) }
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.appAccent)
                    }
                }

                Button("done".t) { editingCapacity = false }
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.appAccent)
            } else {
                Text("\(table.capacity)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.textPrimary)

                Button { editingCapacity = true } label: {
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.appAccent)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var zonePickerRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "rectangle.3.group")
                .font(.subheadline)
                .foregroundColor(.textSecondary)
                .frame(width: 18)

            Text("table_zone_lbl".t)
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

            Spacer(minLength: 0)
        }
    }

    // MARK: - Grouping

    private var groupingSection: some View {
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
                    Button {
                        table.joinedParent = nil
                        table.isSynced = false
                        table.status = "vacant"
                        table.updatedAt = Date()
                        modelContext.saveWithLogging(label: #function)
                        Task { await SyncEngine.shared.syncAll(modelContext: modelContext) }
                    } label: {
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
                .padding(10)
                .background(Color.appSurfaceHigh, in: RoundedRectangle(cornerRadius: APRadius.md, style: .continuous))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    if !table.joinedChildren.isEmpty {
                        Text(combinedGroupText)
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
                                    modelContext.saveWithLogging(label: #function)
                                    Task { await SyncEngine.shared.syncAll(modelContext: modelContext) }
                                }
                                .font(.caption)
                                .foregroundColor(.appRose)
                            }
                        }
                        Divider().background(Color.appDivider)
                    }

                    let floorTables = allTables.filter {
                        !$0.isDeleted && $0.id != table.id
                            && $0.branchId == table.branchId
                            && $0.floorId == table.floorId
                    }
                    let availableToJoin = floorTables.filter { $0.joinedParent == nil && $0.joinedChildren.isEmpty && $0.status == "vacant" }

                    if !availableToJoin.isEmpty {
                        Menu {
                            ForEach(availableToJoin) { targetTable in
                                Button {
                                    targetTable.joinedParent = table
                                    targetTable.status = table.status
                                    targetTable.isSynced = false
                                    targetTable.updatedAt = Date()
                                    modelContext.saveWithLogging(label: #function)
                                    Task { await SyncEngine.shared.syncAll(modelContext: modelContext) }
                                } label: {
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
                            .apLiquidGlass(
                                tint: Color.appAccent.opacity(0.07),
                                interactive: true,
                                in: RoundedRectangle(cornerRadius: APRadius.md, style: .continuous)
                            )
                        }
                    } else {
                        Text("table_no_vacant_combine_hint".t)
                            .font(.caption2)
                            .foregroundColor(.textTertiary)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.appSurface.opacity(0.62),
            in: RoundedRectangle(cornerRadius: APRadius.xl, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: APRadius.xl, style: .continuous)
                .stroke(Color.appBorderSubtle, lineWidth: 1)
        )
    }

    private var combinedGroupText: String {
        let heading = LocalizationManager.shared.t("table_combined_group_template", table.tableNumber)
        let children = table.joinedChildren.map { "T\($0.tableNumber)" }.joined(separator: ", ")
        return heading + " + " + children
    }

    // MARK: - Actions

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let session = activeSession {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("table_active_dining_session".t)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.textSecondary)
                        Label {
                            Text(session.startedAt, style: .time)
                        } icon: {
                            Image(systemName: "clock")
                        }
                        .font(.headline)
                        .foregroundColor(.textPrimary)
                    }

                    Spacer()

                    if enableWebOrdering && !offlineSyncMode {
                        Button {
                            let encodedTable = table.tableNumber.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? table.tableNumber
                            let merchantQ = UserDefaults.standard.string(forKey: "active_merchant_id").flatMap { $0.isEmpty ? nil : "&merchant=\($0)" } ?? ""
                            dynamicQRUrl = "\(customerWebBaseUrl)/?table=\(encodedTable)\(merchantQ)&token=\(session.sessionToken)"
                            showingQRPopover = true
                        } label: {
                            Label("QR Code", systemImage: "qrcode")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .foregroundColor(.appAccent)
                                .background(Color.appAccent.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: APRadius.sm))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
                .background(Color.appSurfaceHigh, in: RoundedRectangle(cornerRadius: APRadius.md))

                placeOrderButton(session)

                Button {
                    showTransferSheet = true
                    APHaptic.trigger()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.swap")
                            .font(.system(size: 13, weight: .semibold))
                        Text("table_transfer_btn".t)
                            .font(.system(size: 13, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 2)
                    .foregroundColor(.textPrimary)
                }
                .apGlassButton(tint: Color.appAccent.opacity(0.08))
                .sheet(isPresented: $showTransferSheet) {
                    TableTransferSheet(
                        fromTable: table,
                        session: session,
                        allTables: allTables,
                        modelContext: modelContext,
                        onTransferComplete: { dismiss() }
                    )
                }
            } else {
                Text("table_actions_title".t)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.appAccent)
                    .tracking(1.0)

                vacantTableActions
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.appSurface.opacity(0.62),
            in: RoundedRectangle(cornerRadius: APRadius.xl, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: APRadius.xl, style: .continuous)
                .stroke(Color.appBorderSubtle, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var vacantTableActions: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 10) { vacantTableActionsLayout }
        } else {
            vacantTableActionsLayout
        }
    }

    private var vacantTableActionsLayout: some View {
        VStack(spacing: 10) {
            Button {
                guard !activeRegisterSessions.isEmpty else {
                    showNoActiveShiftAlert = true
                    return
                }
                startNewSession()
            } label: {
                Label("table_start_session_btn".t, systemImage: "play.fill")
                    .lineLimit(1)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .apGlassButton(prominent: true, tint: .appAccent)

            HStack(spacing: 10) {
                Button { requestClear("reserved") } label: {
                    Label("table_reserve_btn".t, systemImage: "calendar.badge.clock")
                        .lineLimit(1)
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 2)
                }
                .apGlassButton()
                .disabled(!canReserveTable)

                Button { requestClear("vacant") } label: {
                    Label("table_vacant_btn".t, systemImage: "checkmark.circle")
                        .lineLimit(1)
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 2)
                }
                .apGlassButton()
            }

            if allowsDeletion {
                Button(role: .destructive) { deleteTableWithAuth() } label: {
                    Label("table_delete_btn".t, systemImage: "trash")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.appRose)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func placeOrderButton(_ session: TableSession) -> some View {
        Button {
            guard !activeRegisterSessions.isEmpty else {
                showNoActiveShiftAlert = true
                return
            }
            posTableSession = session
            selectedTab = .pos
            dismiss()
        } label: {
            Label("table_place_order_btn".t, systemImage: "fork.knife")
                .lineLimit(1)
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 3)
        }
        .apGlassButton(prominent: true, tint: .appAccent)
    }

    private func startNewSession() {
        let leader = table.joinedParent ?? table
        let newSession = TableSession(sessionToken: UUID().uuidString, startedAt: Date(), isActive: true, table: leader, guestCount: leader.capacity, cashierName: activeCashierDisplayName)
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
        modelContext.saveWithLogging(label: #function)

        posTableSession = newSession
        selectedTab = .pos
        dismiss()

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
        .modelContainer(for: [RestaurantTable.self, TableSession.self, FloorData.self], inMemory: true)
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
    let onClear: () -> Void

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
        let leader = table.joinedParent ?? table
        let effectiveStatus = leader.status
        let statusCol = statusColor(effectiveStatus)
        let activeSession = leader.sessions.first(where: { $0.isActive && Calendar.current.isDateInToday($0.startedAt) })
        let itemCount = activeSession?.itemCount ?? 0

        DynamicTableLayoutView(
            tableNumber: table.tableNumber,
            capacity: table.capacity,
            isRound: table.isRound,
            status: effectiveStatus,
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
        .contextMenu {
            if !isEditingLayout {
                if leader.status.lowercased() != "vacant"
                    || leader.sessions.contains(where: { $0.isActive }) {
                    Button(action: onClear) {
                        Label("เคลียร์โต๊ะ", systemImage: "eraser.fill")
                    }
                }
                Divider()
                Button(action: onLongPress) {
                    Label("table_details_title".t, systemImage: "info.circle")
                }
            }
        }
        .accessibilityLabel("Table \(table.tableNumber), \(effectiveStatus), \(table.capacity) guests")
        .accessibilityHint("Double-tap to open table")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            onTap()
        }
    }
}

struct InteractiveTableCardWrapper: View, Equatable {
    let table: RestaurantTable
    let isEditingLayout: Bool
    let activeDraggingTableId: UUID?
    let selectedTableId: UUID?
    let layoutSelectedTableId: UUID?
    let isMultiSelected: Bool
    /// Canvas-space delta while dragging (already zoom-compensated by the parent).
    let dragTranslation: CGSize
    let liveLayoutScale: CGFloat?
    let liveLayoutOriginDelta: CGSize
    let activeResizeCorner: TableResizeCorner?
    let canvasZoom: CGFloat
    let isBouncing: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void
    let onClear: () -> Void
    let onDragChanged: (DragGesture.Value) -> Void
    let onDragEnded: (DragGesture.Value) -> Void
    let onResizeChanged: (TableResizeCorner, DragGesture.Value) -> Void
    let onResizeEnded: (TableResizeCorner, DragGesture.Value) -> Void

    static func == (lhs: InteractiveTableCardWrapper, rhs: InteractiveTableCardWrapper) -> Bool {
        guard lhs.table.id == rhs.table.id,
              lhs.table.tableNumber == rhs.table.tableNumber,
              lhs.table.status == rhs.table.status,
              lhs.table.capacity == rhs.table.capacity,
              lhs.table.isRound == rhs.table.isRound,
              lhs.table.positionX == rhs.table.positionX,
              lhs.table.positionY == rhs.table.positionY,
              lhs.table.layoutScale == rhs.table.layoutScale,
              lhs.table.zone == rhs.table.zone,
              lhs.table.floor == rhs.table.floor,
              lhs.table.floorId == rhs.table.floorId,
              lhs.table.branchId == rhs.table.branchId,
              lhs.table.isDeleted == rhs.table.isDeleted,
              lhs.table.joinedParent?.id == rhs.table.joinedParent?.id,
              lhs.table.joinedChildren.count == rhs.table.joinedChildren.count,
              lhs.isEditingLayout == rhs.isEditingLayout,
              lhs.layoutSelectedTableId == rhs.layoutSelectedTableId,
              lhs.isMultiSelected == rhs.isMultiSelected,
              lhs.isBouncing == rhs.isBouncing else {
            return false
        }

        let lhsLayoutSelected = lhs.layoutSelectedTableId == lhs.table.id
        let rhsLayoutSelected = rhs.layoutSelectedTableId == rhs.table.id
        if lhsLayoutSelected || rhsLayoutSelected {
            guard lhs.liveLayoutScale == rhs.liveLayoutScale,
                  lhs.liveLayoutOriginDelta == rhs.liveLayoutOriginDelta,
                  lhs.activeResizeCorner == rhs.activeResizeCorner,
                  lhs.canvasZoom == rhs.canvasZoom else { return false }
        }

        let lhsIsDragging = lhs.activeDraggingTableId == lhs.table.id
        let rhsIsDragging = rhs.activeDraggingTableId == rhs.table.id
        guard lhsIsDragging == rhsIsDragging else { return false }
        if lhsIsDragging {
            guard lhs.dragTranslation == rhs.dragTranslation else { return false }
        }

        let lhsIsSelected = lhs.selectedTableId == lhs.table.id
        let rhsIsSelected = rhs.selectedTableId == rhs.table.id
        guard lhsIsSelected == rhsIsSelected else { return false }

        let lhsLeader = lhs.table.joinedParent ?? lhs.table
        let lhsActiveSession = lhsLeader.sessions.first(where: { $0.isActive && Calendar.current.isDateInToday($0.startedAt) })
        let lhsItemCount = lhsActiveSession?.itemCount ?? 0

        let rhsLeader = rhs.table.joinedParent ?? rhs.table
        let rhsActiveSession = rhsLeader.sessions.first(where: { $0.isActive && Calendar.current.isDateInToday($0.startedAt) })
        let rhsItemCount = rhsActiveSession?.itemCount ?? 0

        guard lhsItemCount == rhsItemCount else { return false }

        return true
    }

    private var isLayoutSelected: Bool {
        isEditingLayout && layoutSelectedTableId == table.id
    }

    private var effectiveScale: CGFloat {
        if isLayoutSelected, let live = liveLayoutScale {
            return live
        }
        return CGFloat(table.resolvedLayoutScale)
    }

    private var originDelta: CGSize {
        isLayoutSelected ? liveLayoutOriginDelta : .zero
    }

    var body: some View {
        let isDragging = activeDraggingTableId == table.id
        let isSelected = selectedTableId == table.id || isLayoutSelected || isMultiSelected
        let offsetX = CGFloat(table.positionX) + (isDragging ? dragTranslation.width : 0) + originDelta.width
        let offsetY = CGFloat(table.positionY) + (isDragging ? dragTranslation.height : 0) + originDelta.height
        let feedbackScale: CGFloat = isDragging ? 1.02 : (isBouncing ? 1.12 : 1.0)
        let zIndexVal = (isDragging || (activeResizeCorner != nil && isLayoutSelected)) ? 100.0 : (isBouncing || isLayoutSelected ? 50.0 : 1.0)

        let tableDragGesture = DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged(onDragChanged)
            .onEnded(onDragEnded)

        ZStack(alignment: .topLeading) {
            InteractiveTableCard(
                table: table,
                isEditingLayout: isEditingLayout,
                isDragging: isDragging || (activeResizeCorner != nil && isLayoutSelected),
                isSelected: isSelected,
                onTap: onTap,
                onLongPress: onLongPress,
                onClear: onClear
            )
            .scaleEffect(effectiveScale * feedbackScale, anchor: .topLeading)
            .tableDragGesture(isEditing: isEditingLayout && activeResizeCorner == nil, gesture: AnyGesture(tableDragGesture))

            if isLayoutSelected {
                tableResizeChrome
                    .zIndex(2)
            }
        }
        .offset(x: offsetX, y: offsetY)
        .zIndex(zIndexVal)
        .transaction { txn in
            if isDragging || activeResizeCorner != nil { txn.animation = nil }
        }
    }

    /// Bounding-box + 4 corner handles (NW/NE/SW/SE), inverse-scaled so handle size stays ~constant on screen.
    @ViewBuilder
    private var tableResizeChrome: some View {
        let base = unscaledCardSize
        let boxW = base.width * effectiveScale
        let boxH = base.height * effectiveScale
        let zoom = max(0.01, canvasZoom)
        let handle: CGFloat = 12 / zoom
        let stroke: CGFloat = 1.2 / zoom

        ZStack(alignment: .topLeading) {
            Rectangle()
                .stroke(Color.appAccent, lineWidth: stroke)
                .frame(width: boxW, height: boxH)
                .allowsHitTesting(false)

            ForEach(TableResizeCorner.allCases) { corner in
                resizeHandle(corner: corner, size: handle)
                    .position(corner.point(in: CGSize(width: boxW, height: boxH)))
            }
        }
        .frame(width: boxW, height: boxH, alignment: .topLeading)
    }

    private var unscaledCardSize: CGSize {
        let leftCount = table.capacity >= 3 ? 1 : 0
        let rightCount = table.capacity >= 4 ? 1 : 0
        let remaining = table.capacity - leftCount - rightCount
        let topCount = (remaining + 1) / 2
        let bottomCount = remaining / 2
        let tableWidth = max(76, CGFloat(max(topCount, bottomCount)) * 40 + 20)
        let tableHeight: CGFloat = 70
        return CGSize(width: tableWidth + 32, height: tableHeight + 32)
    }

    private func resizeHandle(corner: TableResizeCorner, size: CGFloat) -> some View {
        let hit = max(size, 28 / max(0.01, canvasZoom))
        return Rectangle()
            .fill(Color.appSurface)
            .frame(width: size, height: size)
            .overlay(Rectangle().stroke(Color.appAccent, lineWidth: max(1, 1.2 / max(0.01, canvasZoom))))
            .frame(width: hit, height: hit)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { onResizeChanged(corner, $0) }
                    .onEnded { onResizeEnded(corner, $0) }
            )
    }
}

/// Standard image-editor style corner handles for proportional resize.
enum TableResizeCorner: String, CaseIterable, Identifiable, Equatable {
    case nw, ne, sw, se

    var id: String { rawValue }

    func point(in size: CGSize) -> CGPoint {
        switch self {
        case .nw: return CGPoint(x: 0, y: 0)
        case .ne: return CGPoint(x: size.width, y: 0)
        case .sw: return CGPoint(x: 0, y: size.height)
        case .se: return CGPoint(x: size.width, y: size.height)
        }
    }
}

struct EmptyCanvasOverlayView: View {
    @EnvironmentObject private var lm: LocalizationManager
    var onAddTable: (() -> Void)? = nil

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
            if let onAddTable {
                Button(action: onAddTable) {
                    Label("table_empty_add_cta".t, systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(APGradient.accent)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
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

// MARK: - H-2: Table Transfer Sheet

struct TableTransferSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var lm: LocalizationManager

    let fromTable: RestaurantTable
    let session: TableSession
    let allTables: [RestaurantTable]
    let modelContext: ModelContext
    let onTransferComplete: () -> Void

    @State private var selectedTarget: RestaurantTable? = nil
    @State private var isTransferring = false
    @State private var showConfirm = false

    // Show eligible tables on the same floor (excluding current table)
    private var eligibleTables: [RestaurantTable] {
        allTables.filter {
            !$0.isDeleted
            && $0.id != fromTable.id
            && $0.joinedParent == nil
            && $0.branchId == fromTable.branchId
            && $0.floorId == fromTable.floorId
        }
        .sorted { ($0.tableNumber) < ($1.tableNumber) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                VStack(spacing: 0) {
                    // From table summary
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.triangle.swap")
                            .foregroundColor(.appAccent)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            let tableNum = "table_number_template".t.replacingOccurrences(of: "%@", with: fromTable.tableNumber)
                            let transferLabel = "\("table_transfer_from".t) \(tableNum)"
                            Text(transferLabel)
                                .font(.subheadline.bold())
                                .foregroundColor(.textPrimary)
                            Text("\(session.orders.filter { !$0.isDeleted }.count) " + "table_transfer_orders_count".t)
                                .font(.caption)
                                .foregroundColor(.textSecondary)
                        }
                        Spacer()
                    }
                    .padding()
                    .background(Color.appSurface)

                    Divider().background(Color.appDivider)

                    if eligibleTables.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "table.furniture")
                                .font(.system(size: 40))
                                .foregroundColor(.textTertiary)
                            Text("table_transfer_no_vacant".t)
                                .font(.subheadline)
                                .foregroundColor(.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], spacing: 12) {
                                ForEach(eligibleTables) { target in
                                    Button {
                                        selectedTarget = target
                                        showConfirm = true
                                    } label: {
                                        VStack(spacing: 6) {
                                            Image(systemName: target.status == "occupied" ? "tablecells.fill" : "tablecells")
                                                .font(.title2)
                                                .foregroundColor(target.status == "occupied" ? .orange : .appTeal)
                                            Text("table_number_template".t.replacingOccurrences(of: "%@", with: target.tableNumber))
                                                .font(.headline)
                                                .foregroundColor(.textPrimary)
                                            Text(target.status == "occupied" ? "ไม่ว่าง (Merge)" : "\(target.capacity) " + "table_seats_lbl".t)
                                                .font(.caption)
                                                .foregroundColor(target.status == "occupied" ? .orange : .textSecondary)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(14)
                                        .background(Color.appSurface)
                                        .cornerRadius(APRadius.md)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: APRadius.md)
                                                .stroke(target.status == "occupied" ? Color.orange.opacity(0.4) : Color.appBorderSubtle, lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding()
                        }
                    }
                }
            }
            .navigationTitle("table_transfer_btn".t)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("cancel_btn".t) { dismiss() }
                        .foregroundColor(.textSecondary)
                }
            }
            .confirmationDialog(
                "table_transfer_confirm_title".t,
                isPresented: $showConfirm,
                titleVisibility: .visible
            ) {
                Button(selectedTarget?.status == "occupied" ? "รวมโต๊ะ (Merge)" : "table_transfer_confirm_action".t) {
                    if let target = selectedTarget {
                        performTransfer(to: target)
                    }
                }
                Button("cancel_btn".t, role: .cancel) { selectedTarget = nil }
            } message: {
                if let target = selectedTarget {
                    let targetTableNum = "table_number_template".t.replacingOccurrences(of: "%@", with: target.tableNumber)
                    let actionText = target.status == "occupied" ? "ต้องการรวมออเดอร์ทั้งหมดไปยัง" : "table_transfer_confirm_msg".t
                    Text("\(actionText) \(targetTableNum)")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Transfer / Merge Logic
    private func performTransfer(to target: RestaurantTable) {
        let oldTable = fromTable
        let targetTableId = target.id

        // Fetch active session of target table
        let descriptor = FetchDescriptor<TableSession>(
            predicate: #Predicate<TableSession> { $0.table?.id == targetTableId && $0.isActive == true && !$0.isDeleted }
        )
        let targetSessions = (try? modelContext.fetch(descriptor)) ?? []

        if let targetSession = targetSessions.first {
            // MERGE active orders into target table session
            for order in session.orders where !order.isDeleted {
                order.tableSession = targetSession
                order.isSynced = false
                order.updatedAt = Date()
            }

            // Close old session
            session.isActive = false
            session.endedAt = Date()
            session.isSynced = false
            session.updatedAt = Date()

            // Update old table to vacant
            oldTable.status = "vacant"
            oldTable.isSynced = false
            oldTable.updatedAt = Date()

            // Target session is now dirty
            targetSession.isSynced = false
            targetSession.updatedAt = Date()

            let audit = AuditLog(
                actionType: "table_merge",
                details: "Merged Table \(oldTable.tableNumber) → \(target.tableNumber)",
                originalValue: 0,
                newValue: 0
            )
            modelContext.insert(audit)
        } else {
            // TRANSFER source session directly to vacant target table
            session.table = target
            session.isSynced = false
            session.updatedAt = Date()

            target.status = "occupied"
            target.isSynced = false
            target.updatedAt = Date()

            oldTable.status = "vacant"
            oldTable.isSynced = false
            oldTable.updatedAt = Date()

            for order in session.orders where !order.isDeleted {
                order.isSynced = false
                order.updatedAt = Date()
            }

            let audit = AuditLog(
                actionType: "table_transfer",
                details: "Table \(oldTable.tableNumber) → \(target.tableNumber) (\(session.orders.filter { !$0.isDeleted }.count) orders)",
                originalValue: 0,
                newValue: 0
            )
            modelContext.insert(audit)
        }

        modelContext.saveWithLogging(label: "TableTransferSheet.performTransfer")

        let sourceTableNumber = oldTable.tableNumber
        let isMerge = !targetSessions.isEmpty
        Task {
            // Merge closes the source session remotely; transfer relocates the
            // session so close-all on source would kill the moved session if
            // table_number hadn't updated yet — only PATCH-close on merge.
            if isMerge {
                _ = try? await NetworkManager.shared.closeTableSession(tableNumber: sourceTableNumber)
            }
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }

        onTransferComplete()
        dismiss()
    }
}
