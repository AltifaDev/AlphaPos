import SwiftUI

struct TablesView: View {
    @State private var networkService = NetworkService.shared
    
    private var tables: [RestaurantTable] {
        networkService.tables
    }

    // Stable snapshot for canvas — only updated when floor-filtered tables actually change
    @State private var canvasTables: [RestaurantTable] = []
    
    @AppStorage("app_theme") private var appTheme = AppTheme.light.rawValue
    @AppStorage("app_language") private var appLanguage = "en"
    
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.verticalSizeClass) private var vSizeClass
    
    /// true when iPhone is in landscape (compact height)
    private var isCompactHeight: Bool { vSizeClass == .compact }
    
    @State private var selectedTable: RestaurantTable? = nil
    @State private var guestCount = 2
    @State private var isRefreshing = false
    
    @State private var selectedFloor = 1
    @State private var selectedZone = "All"
    @State private var viewMode: ViewMode = .canvas
    @State private var isAnimatedIn = false
    @State private var offlinePulse = false
    @State private var cachedFloorPlanImage: UIImage? = nil
    // Floor plan image loading state
    @State private var isDownloadingFloorPlan = false
    @State private var floorPlanDownloadError: String? = nil
    @State private var cachedFloorPlanFilename: String? = nil  // track ชื่อไฟล์ที่ cache ไว้ล่าสุด
    @State private var floorPlanDownloadTask: Task<Void, Never>? = nil  // guard ป้องกัน download ซ้ำ

    // Zoom & Pan gesture states for canvas mode (iPad-like interaction)
    @State private var zoomScale: CGFloat = 0.45
    @State private var gestureScale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @State private var activePanOffset: CGSize = .zero
    // H-1: Loading state while navigating to TableDetailView
    @State private var loadingTableId: String? = nil
    @GestureState private var isZooming = false
    
    enum ViewMode: String, CaseIterable {
        case grid = "Grid"
        case canvas = "Layout"
    }
    
    private var floors: [Int] {
        Array(Set(tables.map { $0.floor })).sorted()
    }
    
    private var zones: [String] {
        let floorTables = tables.filter { $0.floor == selectedFloor }
        let uniqueZones = Set(floorTables.compactMap { $0.zone }).filter { !$0.isEmpty }
        return ["All"] + Array(uniqueZones).sorted()
    }
    

    private var filteredTables: [RestaurantTable] {
        let floorTables = tables.filter { $0.floor == selectedFloor }
        let baseTables: [RestaurantTable]
        if selectedZone == "All" {
            baseTables = floorTables
        } else {
            baseTables = floorTables.filter { $0.zone == selectedZone }
        }
        return baseTables.sorted {
            $0.tableNumber.localizedStandardCompare($1.tableNumber) == .orderedAscending
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                
                if !networkService.isTableSystemEnabled {
                    VStack(spacing: APSpacing.lg) {
                        Spacer()
                        Image(systemName: "table.furniture")
                            .font(.system(size: 70))
                            .foregroundStyle(APGradient.accent)
                            .shadow(color: Color.appAccent.opacity(0.3), radius: 10)
                            .padding(.bottom, APSpacing.md)
                        
                        Text("table_system_disabled_title".localized(for: appLanguage))
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.textPrimary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        Text("table_system_disabled_desc".localized(for: appLanguage))
                            .font(.subheadline)
                            .foregroundColor(.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, APSpacing.xl)
                            .lineSpacing(4)
                        Spacer()
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.appBackground.ignoresSafeArea())
                } else {
                    VStack(spacing: 0) {

                        // H-7 FIX: Offline banner — shown when NetworkService cannot reach server
                        if networkService.connectionError {
                            HStack(spacing: 8) {
                                Image(systemName: "wifi.slash")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white)
                                Text("ออฟไลน์ — ข้อมูลอาจไม่อัพเดต")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.white)
                                Spacer()
                                Image(systemName: "exclamationmark.circle")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.appRose)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }

                    if isCompactHeight {
                        // ── Landscape iPhone: single compact toolbar row ──
                        HStack(spacing: APSpacing.sm) {
                            // Stat badges (small)
                            let vacant   = filteredTables.filter { $0.status != "occupied" }.count
                            let occupied = filteredTables.filter { $0.status == "occupied" }.count
                            compactStatBadge(label: "vacant".localized(for: appLanguage),
                                             count: vacant,   color: .appTeal)
                            compactStatBadge(label: "occupied".localized(for: appLanguage),
                                             count: occupied, color: .appRose)
                            
                            Divider().frame(height: 20)
                            
                            // Floor dropdown
                            if !floors.isEmpty {
                                Menu {
                                    ForEach(floors, id: \.self) { floorNum in
                                        Button {
                                            selectedFloor = floorNum
                                            selectedZone = "All"
                                            APHaptic.trigger()
                                        } label: {
                                            if selectedFloor == floorNum {
                                                Label(floorName(floorNum), systemImage: "checkmark")
                                            } else {
                                                Text(floorName(floorNum))
                                            }
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(floorName(selectedFloor))
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(.textPrimary)
                                        Image(systemName: "chevron.up.chevron.down")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(.textSecondary)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.appSurfaceHigh)
                                    .cornerRadius(8)
                                    .overlay(RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.appBorderSubtle, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                            
                            // Zone dropdown
                            if zones.count > 1 {
                                Divider().frame(height: 20)
                                
                                Menu {
                                    ForEach(zones, id: \.self) { zone in
                                        Button {
                                            selectedZone = zone
                                            APHaptic.trigger()
                                        } label: {
                                            if selectedZone == zone {
                                                Label(zone.localized(for: appLanguage), systemImage: "checkmark")
                                            } else {
                                                Text(zone.localized(for: appLanguage))
                                            }
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(selectedZone.localized(for: appLanguage))
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(.textPrimary)
                                        Image(systemName: "chevron.up.chevron.down")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(.textSecondary)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.appSurfaceHigh)
                                    .cornerRadius(8)
                                    .overlay(RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.appBorderSubtle, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                            
                            Divider().frame(height: 20)
                            
                            // View mode picker
                            Picker("View Mode", selection: $viewMode) {
                                ForEach(ViewMode.allCases, id: \.self) { mode in
                                    Text(mode == .grid ? "Grid" : "Canvas").tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 160)
                            
                            Spacer()
                            
                            Divider().frame(height: 20)
                            
                            // Theme + Refresh (replace hidden navbar)
                            Button(action: {
                                APHaptic.trigger()
                                withAnimation {
                                    appTheme = appTheme == AppTheme.dark.rawValue
                                        ? AppTheme.light.rawValue
                                        : AppTheme.dark.rawValue
                                }
                            }) {
                                Image(systemName: appTheme == AppTheme.dark.rawValue ? "sun.max.fill" : "moon.fill")
                                    .foregroundColor(.white)
                                    .frame(width: 30, height: 30)
                                    .background(Color.white.opacity(0.18))
                                    .clipShape(Circle())
                             }
                            .accessibilityLabel(appTheme == AppTheme.dark.rawValue ? "switch_to_light_mode".localized(for: appLanguage) : "switch_to_dark_mode".localized(for: appLanguage))
                            
                            Button(action: { Task { await loadTables() } }) {
                                Image(systemName: "arrow.clockwise")
                                    .foregroundColor(.white)
                                    .frame(width: 30, height: 30)
                                    .background(Color.white.opacity(0.18))
                                    .clipShape(Circle())
                            }
                            .accessibilityLabel("refresh_tables".localized(for: appLanguage))
                        }
                        .padding(.horizontal, APSpacing.md)
                        .padding(.vertical, APSpacing.xs)
                        .background(APGradient.accent.ignoresSafeArea(edges: .top))
                        .offset(y: isAnimatedIn ? 0 : -50)
                        .opacity(isAnimatedIn ? 1 : 0)
                        
                    } else {
                        // ── Row 1: Compact title bar (white background) ──
                        HStack(spacing: APSpacing.sm) {
                            Image(systemName: "table.furniture.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.appAccent)

                            Text("manage_tables".localized(for: appLanguage))
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(.textPrimary)

                            // Online/Offline status indicator
                            Circle()
                                .fill(networkService.isOnline ? Color.appTeal : Color.orange)
                                .frame(width: 8, height: 8)
                                .scaleEffect(networkService.isOnline ? 1.0 : (offlinePulse ? 1.4 : 0.8))
                                .opacity(networkService.isOnline ? 1.0 : (offlinePulse ? 0.4 : 1.0))
                                .animation(
                                    networkService.isOnline
                                        ? .default
                                        : .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                                    value: offlinePulse
                                )
                                .onAppear { offlinePulse = true }

                            Spacer()

                            // Stat badges inline in header
                            let vacant   = filteredTables.filter { $0.status != "occupied" }.count
                            let occupied = filteredTables.filter { $0.status == "occupied" }.count
                            headerStatBadge(count: vacant,   color: .appTeal, icon: "circle.fill")
                            headerStatBadge(count: occupied, color: .appRose, icon: "circle.fill")

                            // Quick Sales Summary chip
                            let todayRevenue = networkService.tables.reduce(0.0) { $0 + $1.currentTotal }
                            if todayRevenue > 0 {
                                Text("\u{0E3F}\(Int(todayRevenue).formatted())")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundColor(Color(hex: "2D71F8"))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color(hex: "2D71F8").opacity(0.10))
                                    .cornerRadius(6)
                            }

                            Divider().frame(height: 18)

                            // Theme toggle
                            Button(action: {
                                APHaptic.trigger()
                                withAnimation {
                                    appTheme = appTheme == AppTheme.dark.rawValue
                                        ? AppTheme.light.rawValue
                                        : AppTheme.dark.rawValue
                                }
                            }) {
                                Image(systemName: appTheme == AppTheme.dark.rawValue ? "sun.max.fill" : "moon.fill")
                                    .font(.system(size: 13))
                                    .foregroundColor(.appAccent)
                                    .frame(width: 30, height: 30)
                                    .background(Color.appAccent.opacity(0.08))
                                    .clipShape(Circle())
                            }
                            .accessibilityLabel(appTheme == AppTheme.dark.rawValue ? "switch_to_light_mode".localized(for: appLanguage) : "switch_to_dark_mode".localized(for: appLanguage))
                            // Refresh
                            Button(action: { Task { await loadTables() } }) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 13))
                                    .foregroundColor(.appAccent)
                                    .frame(width: 30, height: 30)
                                    .background(Color.appAccent.opacity(0.08))
                                    .clipShape(Circle())
                            }
                            .accessibilityLabel("refresh_tables".localized(for: appLanguage))
                        }
                        .padding(.horizontal, APSpacing.md)
                        .padding(.vertical, 9)
                        .background(Color.appSurface.ignoresSafeArea(edges: .top))
                        .overlay(alignment: .bottom) { Divider() }
                        .offset(y: isAnimatedIn ? 0 : -50)
                        .opacity(isAnimatedIn ? 1 : 0)

                        // ── Row 2: Floor & Zone Dropdown + View mode segmented ──
                        HStack(spacing: 8) {
                            // Floor dropdown
                            if !floors.isEmpty {
                                Menu {
                                    ForEach(floors, id: \.self) { floorNum in
                                        Button {
                                            selectedFloor = floorNum
                                            selectedZone = "All"
                                            APHaptic.trigger()
                                        } label: {
                                            if selectedFloor == floorNum {
                                                Label(floorName(floorNum), systemImage: "checkmark")
                                            } else {
                                                Text(floorName(floorNum))
                                            }
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(floorName(selectedFloor))
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(.textPrimary)
                                        Image(systemName: "chevron.up.chevron.down")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(.textSecondary)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(Color.appSurfaceHigh)
                                    .cornerRadius(9)
                                    .overlay(RoundedRectangle(cornerRadius: 9)
                                        .stroke(Color.appBorderSubtle, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                            
                            // Zone dropdown
                            if zones.count > 1 {
                                Menu {
                                    ForEach(zones, id: \.self) { zone in
                                        Button {
                                            selectedZone = zone
                                            APHaptic.trigger()
                                        } label: {
                                            if selectedZone == zone {
                                                Label(zone.localized(for: appLanguage), systemImage: "checkmark")
                                            } else {
                                                Text(zone.localized(for: appLanguage))
                                            }
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(selectedZone.localized(for: appLanguage))
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(.textPrimary)
                                        Image(systemName: "chevron.up.chevron.down")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(.textSecondary)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(Color.appSurfaceHigh)
                                    .cornerRadius(9)
                                    .overlay(RoundedRectangle(cornerRadius: 9)
                                        .stroke(Color.appBorderSubtle, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                            
                            Spacer()
                            
                            // View mode — segmented เล็กๆ
                            Picker("View", selection: $viewMode) {
                                ForEach(ViewMode.allCases, id: \.self) { mode in
                                    Text(mode == .grid ? "Grid" : "Canvas").tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 130)
                        }
                        .padding(.horizontal, APSpacing.md)
                        .padding(.vertical, 8)
                        .background(Color.appSurface)
                        .overlay(alignment: .bottom) { Divider() }
                        .opacity(isAnimatedIn ? 1 : 0)
                    }
                    
                    if tables.isEmpty {
                        VStack(spacing: APSpacing.md) {
                            ProgressView().tint(.appAccent)
                            Text("loading_tables_layout".localized(for: appLanguage))
                                .font(.caption).foregroundColor(.textSecondary)
                        }
                        .frame(maxHeight: .infinity)
                    } else {
                        if viewMode == .grid {
                            ScrollView {
                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: APSpacing.md) {
                                    ForEach(Array(filteredTables.enumerated()), id: \.element.id) { index, table in
                                        gridCell(table: table, index: index)
                                    }
                                }
                                .padding(.horizontal, APSpacing.md)
                                .padding(.bottom, APSpacing.xl)
                            }
                            .refreshable {
                                await loadTables()
                            }
                        } else {
                            // Zoomable & Pannable Blueprint Layout View (iPad-matched layout)
                            GeometryReader { viewport in
                                ZStack(alignment: .topLeading) {
                                    ZStack(alignment: .topLeading) {
                                        // Floor Plan background image (behind grid & tables)
                                        if let img = cachedFloorPlanImage {
                                            let activeFloorPlanImage = networkService.floorPlanImages.first(where: { $0.floor == selectedFloor })
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

                                        // Loading indicator while downloading floor plan
                                        if isDownloadingFloorPlan {
                                            VStack(spacing: 8) {
                                                ProgressView()
                                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                                    .scaleEffect(1.2)
                                                Text("กำลังโหลดแผนผัง...")
                                                    .font(.caption2)
                                                    .foregroundColor(.white.opacity(0.85))
                                            }
                                            .padding(12)
                                            .background(.ultraThinMaterial)
                                            .cornerRadius(10)
                                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                                            .allowsHitTesting(false)
                                        }

                                        // Error banner เมื่อโหลดรูปไม่สำเร็จ
                                        if let errMsg = floorPlanDownloadError, !isDownloadingFloorPlan {
                                            VStack(spacing: 6) {
                                                Image(systemName: "photo.badge.exclamationmark")
                                                    .font(.title3)
                                                    .foregroundColor(.white.opacity(0.6))
                                                Text(errMsg)
                                                    .font(.caption2)
                                                    .foregroundColor(.white.opacity(0.7))
                                                    .multilineTextAlignment(.center)
                                                Button("ลองอีกครั้ง") {
                                                    floorPlanDownloadError = nil
                                                    loadCachedFloorPlanImage()
                                                }
                                                .font(.caption2.bold())
                                                .foregroundColor(.appAccent)
                                            }
                                            .padding(14)
                                            .background(.ultraThinMaterial)
                                            .cornerRadius(10)
                                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                                            .allowsHitTesting(true)
                                        }

                                        CanvasBackgroundGrid()
                                            .frame(width: 1500, height: 1200)
                                            .allowsHitTesting(false)

                                        
                                        ForEach(Array(canvasTables.enumerated()), id: \.element.id) { index, table in
                                            let statusColor: Color = {
                                                switch table.status.lowercased() {
                                                case "occupied": return Color.appRose
                                                case "reserved": return Color.appAmber
                                                case "cleaning": return Color.appAccent
                                                default: return Color.appTeal
                                                }
                                            }()
                                            
                                            Group {
                                                if table.status == "occupied" {
                                                    NavigationLink(destination: TableDetailView(table: table)) {
                                                        CompactTableLayoutView(table: table, statusColor: statusColor)
                                                    }
                                                    .buttonStyle(.plain)
                                                } else {
                                                    Button(action: {
                                                        APHaptic.trigger()
                                                        guestCount = 2
                                                        selectedTable = table
                                                    }) {
                                                        CompactTableLayoutView(table: table, statusColor: statusColor)
                                                    }
                                                    .buttonStyle(.plain)
                                                }
                                            }
                                            .offset(x: CGFloat(table.positionX), y: CGFloat(table.positionY))
                                            .scaleEffect(isAnimatedIn ? 1.0 : 0.3)
                                            .opacity(isAnimatedIn ? (selectedZone == "All" || table.zone == selectedZone ? 1.0 : 0.25) : 0)
                                            .animation(.spring(response: 0.45, dampingFraction: 0.8), value: selectedZone)
                                            .animation(.spring(response: 0.65, dampingFraction: 0.72).delay(Double(index) * 0.04), value: isAnimatedIn)
                                        }
                                    }
                                    .frame(width: 1500, height: 1200)
                                    .scaleEffect(zoomScale * gestureScale, anchor: .topLeading)
                                    .offset(CGSize(
                                        width: panOffset.width + activePanOffset.width,
                                        height: panOffset.height + activePanOffset.height
                                    ))
                                }
                                .frame(width: viewport.size.width, height: viewport.size.height, alignment: .topLeading)
                                .background(Color.appSurface)
                                .contentShape(Rectangle())
                                .clipped()
                                .simultaneousGesture(
                                    DragGesture(minimumDistance: 10)
                                        .onChanged { value in
                                            guard !isZooming else { return }
                                            activePanOffset = value.translation
                                        }
                                        .onEnded { value in
                                            guard !isZooming else { return }
                                            panOffset.width += value.translation.width
                                            panOffset.height += value.translation.height
                                            activePanOffset = .zero
                                        }
                                )
                                .simultaneousGesture(
                                    MagnificationGesture()
                                        .updating($isZooming) { value, state, transaction in
                                            state = true
                                        }
                                        .onChanged { value in
                                            gestureScale = value
                                        }
                                        .onEnded { value in
                                            zoomScale = min(2.0, max(0.2, zoomScale * value))
                                            gestureScale = 1.0
                                        }
                                )
                                .onTapGesture(count: 2) {
                                    autoFitCanvas(viewportSize: viewport.size)
                                }
                                .onAppear {
                                    autoFitCanvas(viewportSize: viewport.size)
                                }
                                .onChange(of: viewport.size) { _, newSize in
                                    autoFitCanvas(viewportSize: newSize)
                                }
                                .onChange(of: selectedFloor) { _, _ in
                                    autoFitCanvas(viewportSize: viewport.size)
                                }
                            }
                            // Floating Zoom Controls
                            .overlay(
                                VStack(spacing: 0) {
                                    Button(action: {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                            zoomScale = min(2.0, zoomScale + 0.15)
                                        }
                                    }) {
                                        Image(systemName: "plus")
                                            .font(.system(size: 18, weight: .medium))
                                            .foregroundColor(.primary)
                                            .frame(width: 44, height: 44)
                                    }
                                    
                                    Divider()
                                        .frame(width: 30)
                                        .background(Color.gray.opacity(0.3))
                                    
                                    Button(action: {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                            zoomScale = max(0.2, zoomScale - 0.15)
                                        }
                                    }) {
                                        Image(systemName: "minus")
                                            .font(.system(size: 18, weight: .medium))
                                            .foregroundColor(.primary)
                                            .frame(width: 44, height: 44)
                                    }
                                }
                                .background(.thinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 3)
                                .padding(16),
                                alignment: .bottomTrailing
                            )
                            // Stretch canvas edge-to-edge, ignoring safe area on sides
                            .ignoresSafeArea(edges: isCompactHeight ? [.horizontal, .bottom] : [])
                        }
                    }
                }
            }
        }
        .navigationBarHidden(true)
        }
        .onAppear {
            Task {
                await loadTables()
            }
            canvasTables = tables.filter { $0.floor == selectedFloor }
            loadCachedFloorPlanImage()
            withAnimation(.spring(response: 0.65, dampingFraction: 0.8)) {
                isAnimatedIn = true
            }
        }
        .onDisappear {
            isAnimatedIn = false
        }
       .onChange(of: tables) { _, newTables in
            if !newTables.isEmpty {
                let availableFloors = Array(Set(newTables.map { $0.floor })).sorted()
                if !availableFloors.contains(selectedFloor) {
                    selectedFloor = availableFloors.first ?? 1
                }
            }
            // Update canvas snapshot only when status actually changes (not on every sync tick)
            let newFiltered = newTables.filter { $0.floor == selectedFloor }
            let currentStatuses = canvasTables.map { ($0.tableNumber, $0.status, $0.currentTotal, $0.sessionStartedAt) }
            let newStatuses     = newFiltered.map   { ($0.tableNumber, $0.status, $0.currentTotal, $0.sessionStartedAt) }
            let changed = zip(currentStatuses, newStatuses).contains { a, b in
                a.0 != b.0 || a.1 != b.1 || a.2 != b.2 || a.3 != b.3
            } || currentStatuses.count != newStatuses.count
            if changed {
                canvasTables = newFiltered
            }
            
            // Reset zone filter if no longer available on this floor
            let availableZones = Set(newFiltered.compactMap { $0.zone }).filter { !$0.isEmpty }
            if selectedZone != "All" && !availableZones.contains(selectedZone) {
                selectedZone = "All"
            }
        }
        .onChange(of: selectedFloor) { _, newFloor in
            canvasTables = tables.filter { $0.floor == newFloor }
            // Cancel task เก่าและ reset state เมื่อเปลี่ยน floor
            floorPlanDownloadTask?.cancel()
            floorPlanDownloadTask = nil
            isDownloadingFloorPlan = false
            floorPlanDownloadError = nil
            loadCachedFloorPlanImage()
            
            // Reset zone filter if not available on the new floor
            let newFloorTables = tables.filter { $0.floor == newFloor }
            let newZones = Set(newFloorTables.compactMap { $0.zone }).filter { !$0.isEmpty }
            if selectedZone != "All" && !newZones.contains(selectedZone) {
                selectedZone = "All"
            }
        }
        .onChange(of: networkService.floorPlanImages) { _, _ in
            loadCachedFloorPlanImage()
        }
        .sheet(item: $selectedTable) { table in
            openSessionSheetView(for: table)
                .presentationDetents([.fraction(0.45)])
                .apColorScheme()
        }
    }

    private func loadCachedFloorPlanImage() {
        guard let floorPlan = networkService.floorPlanImages.first(where: { $0.floor == selectedFloor && !$0.isDeleted }),
              !floorPlan.imageFilename.isEmpty else {
            cachedFloorPlanImage = nil
            cachedFloorPlanFilename = nil
            isDownloadingFloorPlan = false
            floorPlanDownloadError = nil
            return
        }

        let filename = floorPlan.imageFilename

        // ── Cache invalidation: ถ้า filename เปลี่ยน (รูปถูก update บน iPad) → ล้าง cache ──
        if cachedFloorPlanFilename != filename {
            cachedFloorPlanImage = nil
            cachedFloorPlanFilename = nil
            floorPlanDownloadError = nil
        }

        // ── ถ้ามีไฟล์ local ที่ filename ตรง → โหลดทันที ──
        if let path = floorPlan.resolvedImagePath, let uiImage = UIImage(contentsOfFile: path) {
            cachedFloorPlanImage = uiImage
            cachedFloorPlanFilename = filename
            isDownloadingFloorPlan = false
            return
        }

        // ── Guard: ถ้ากำลัง download อยู่แล้ว → ไม่ spawn Task ซ้ำ ──
        guard !isDownloadingFloorPlan else { return }

        isDownloadingFloorPlan = true
        floorPlanDownloadError = nil

        // ── Cancel Task เก่า (ถ้ามี) ก่อน spawn ใหม่ ──
        floorPlanDownloadTask?.cancel()
        floorPlanDownloadTask = Task {
            do {
                let data = try await networkService.downloadFloorPlanMedia(fileName: filename)
                guard !Task.isCancelled else { return }

                if let downloadedImage = UIImage(data: data) {
                    // บันทึกลง Documents เพื่อใช้ครั้งต่อไป
                    let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                    let fileURL = docsURL.appendingPathComponent(filename)
                    try? data.write(to: fileURL)

                    await MainActor.run {
                        self.cachedFloorPlanImage = downloadedImage
                        self.cachedFloorPlanFilename = filename
                        self.isDownloadingFloorPlan = false
                        self.floorPlanDownloadError = nil
                    }
                } else {
                    await MainActor.run {
                        self.isDownloadingFloorPlan = false
                        self.floorPlanDownloadError = "ไม่สามารถถอดรหัสรูปภาพได้"
                    }
                }
            } catch is CancellationError {
                // Task ถูก cancel — ไม่ต้องทำอะไร
            } catch {
                await MainActor.run {
                    self.isDownloadingFloorPlan = false
                    self.floorPlanDownloadError = "โหลดแผนผังไม่สำเร็จ\nแตะเพื่อลองใหม่"
                }
            }
        }
    }

    private func autoFitCanvas(viewportSize: CGSize) {
        let floorTables = filteredTables
        guard !floorTables.isEmpty else {
            zoomScale = 0.6
            panOffset = .zero
            return
        }
        
        let tableWidth: CGFloat = 120
        let tableHeight: CGFloat = 100
        // Use smaller margin in compact (landscape iPhone) to maximise canvas area
        let margin: CGFloat = isCompactHeight ? 20 : 40
        
        let minX = floorTables.map { CGFloat($0.positionX) }.min() ?? 0
        let maxX = floorTables.map { CGFloat($0.positionX) + tableWidth }.max() ?? 1500
        let minY = floorTables.map { CGFloat($0.positionY) }.min() ?? 0
        let maxY = floorTables.map { CGFloat($0.positionY) + tableHeight }.max() ?? 1200
        
        let boundingWidth  = maxX - minX
        let boundingHeight = maxY - minY
        
        let contentWidth  = boundingWidth  + margin * 2
        let contentHeight = boundingHeight + margin * 2
        
        let scaleX = viewportSize.width  / contentWidth
        let scaleY = viewportSize.height / contentHeight
        
        let calculatedScale = min(scaleX, scaleY)
        // Allow slightly higher max on compact so tables fill the narrow height
        let maxScale: CGFloat = isCompactHeight ? 1.5 : 1.2
        let finalScale = min(maxScale, max(0.25, calculatedScale))
        
        let centerX = minX + boundingWidth  / 2
        let centerY = minY + boundingHeight / 2
        
        let targetX = (viewportSize.width  / 2) - (centerX * finalScale)
        let targetY = (viewportSize.height / 2) - (centerY * finalScale)
        
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            self.zoomScale = finalScale
            self.panOffset = CGSize(width: targetX, height: targetY)
            self.activePanOffset = .zero
        }
    }
    
    private func floorName(_ floorNum: Int) -> String {
        switch floorNum {
        case 1: return "1st Floor"
        case 2: return "2nd Floor"
        case 3: return "3rd Floor"
        default: return "\(floorNum)th Floor"
        }
    }
    
    @ViewBuilder
    private func gridCell(table: RestaurantTable, index: Int) -> some View {
        let directionOffset: CGFloat = (index % 2 == 0) ? -80 : 80
        Group {
            if table.status == "occupied" {
                // H-1: Show skeleton overlay while loading TableDetailView
                NavigationLink(destination:
                    TableDetailView(table: table)
                        .onAppear { loadingTableId = nil }
                ) {
                    ZStack {
                        tableCard(table: table)
                        if loadingTableId == table.id {
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.black.opacity(0.35))
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(1.2)
                        }
                    }
                }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture().onEnded {
                    loadingTableId = table.id
                })
            } else {
                Button(action: {
                    APHaptic.trigger()
                    guestCount = 2
                    selectedTable = table
                }) {
                    tableCard(table: table)
                }
                .buttonStyle(.plain)
            }
        }
        .offset(x: isAnimatedIn ? 0 : directionOffset, y: isAnimatedIn ? 0 : 40)
        .opacity(isAnimatedIn ? 1 : 0)
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.92)).combined(with: .offset(y: 20)),
            removal: .opacity.combined(with: .scale(scale: 0.92))
        ))
        .animation(.spring(response: 0.45, dampingFraction: 0.82).delay(Double(index % 6) * 0.035), value: isAnimatedIn)
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: filteredTables)
    }

    // MARK: - Table Card Component
    
    private func tableCard(table: RestaurantTable) -> some View {
        let status = table.status.lowercased()
        
        let (statusText, statusColor, strokeColor, shadowColor): (String, Color, Color, Color) = {
            switch status {
            case "occupied":
                return (
                    "occupied".localized(for: appLanguage),
                    Color.appRose,
                    Color.appRose.opacity(0.5),
                    Color.appRose.opacity(0.12)
                )
            case "reserved":
                return (
                    "reserved".localized(for: appLanguage),
                    Color.appAmber,
                    Color.appAmber.opacity(0.5),
                    Color.appAmber.opacity(0.12)
                )
            case "cleaning":
                return (
                    "cleaning".localized(for: appLanguage),
                    Color.appAccent,
                    Color.appAccent.opacity(0.5),
                    Color.appAccent.opacity(0.12)
                )
            default: // vacant
                return (
                    "vacant".localized(for: appLanguage),
                    Color.appTeal,
                    Color.appDivider,
                    Color.black.opacity(0.04)
                )
            }
        }()
        
        return VStack(alignment: .leading, spacing: 0) {
            // ── Top Row: Table Title & Status Badge ──
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "table_label".localized(for: appLanguage), table.tableNumber))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.textPrimary)
                    
                    if let zone = table.zone, !zone.isEmpty {
                        Text(zone)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.textTertiary)
                    }
                }
                
                Spacer()
                
                // Status Badge
                Text(statusText)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(statusColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(statusColor.opacity(0.12))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(statusColor.opacity(0.25), lineWidth: 0.5)
                    )
            }
            
            Spacer(minLength: 4)
            
            // ── Middle Section: POS Core details ──
            VStack(alignment: .leading, spacing: 4) {
                if status == "occupied" {
                    // Active Bill Amount (Large, bold, rounded)
                    let formattedTotal = table.currentTotal.formatted(.number.precision(.fractionLength(0...2)))
                    Text("฿\(formattedTotal)")
                        .font(.system(size: 21, weight: .black, design: .rounded))
                        .foregroundColor(.textPrimary)
                        .transition(.scale.combined(with: .opacity))
                    
                    // Occupancy Ratio (actual guests / capacity)
                    HStack(spacing: 4) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.textSecondary)
                        Text("\(table.guestCount) / \(table.capacity)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.textSecondary)
                    }
                } else if status == "reserved" {
                    Text("reserved".localized(for: appLanguage).uppercased())
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(Color.appAmber)
                        .padding(.vertical, 2)
                    
                    HStack(spacing: 4) {
                        Image(systemName: "person.2")
                            .font(.system(size: 10))
                            .foregroundColor(.textSecondary)
                        Text(String(format: "seats_count".localized(for: appLanguage), table.capacity))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.textSecondary)
                    }
                } else if status == "cleaning" {
                    HStack(spacing: 5) {
                        Image(systemName: "bubbles.and.sparkles")
                            .font(.system(size: 12))
                            .foregroundColor(Color.appAccent)
                        Text("cleaning".localized(for: appLanguage))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.textPrimary)
                    }
                    .padding(.vertical, 2)
                    
                    HStack(spacing: 4) {
                        Image(systemName: "person.2")
                            .font(.system(size: 10))
                            .foregroundColor(.textSecondary)
                        Text(String(format: "seats_count".localized(for: appLanguage), table.capacity))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.textSecondary)
                    }
                } else { // vacant
                    // Clean capacity seats count
                    HStack(spacing: 4) {
                        Image(systemName: "person.2")
                            .font(.system(size: 11))
                            .foregroundColor(.textSecondary)
                        Text(String(format: "seats_count".localized(for: appLanguage), table.capacity))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.textSecondary)
                    }
                    .padding(.vertical, 2)
                    
                    // Tap to Open subtle action invitation
                    Text("open_table".localized(for: appLanguage))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color.appTeal)
                        .padding(.vertical, 3)
                        .padding(.horizontal, 6)
                        .background(Color.appTeal.opacity(0.08))
                        .cornerRadius(6)
                }
            }
            
            Spacer(minLength: 4)
            
            // ── Bottom Section: Clock, time elapsed, etc. ──
            HStack {
                if status == "occupied" {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 9))
                            .foregroundColor(.textSecondary)
                        ElapsedTimeBadge(startedAt: table.sessionStartedAt)
                    }
                } else {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 6, height: 6)
                        Text(statusText)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(statusColor)
                    }
                }
                
                Spacer()
            }
        }
        .padding(APSpacing.md)
        .frame(height: 138)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: APRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: APRadius.lg, style: .continuous)
                .stroke(strokeColor, lineWidth: status == "vacant" ? 1.0 : 1.5)
        )
        .shadow(color: shadowColor, radius: 8, x: 0, y: 4)
    }
    
    /// Compact inline badge used in landscape iPhone header
    // ── Mini stat badge used inside the compact header title row ──
    private func headerStatBadge(count: Int, color: Color, icon: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 6))
                .foregroundColor(color)
            Text("\(count)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(.textPrimary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(color.opacity(0.10))
        .cornerRadius(6)
    }

    private func compactStatBadge(label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
                .font(.caption2).foregroundColor(.textSecondary)
            Text("\(count)")
                .font(.caption).fontWeight(.bold).foregroundColor(.textPrimary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.appSurface)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.appDivider, lineWidth: 1))
    }
    
    private func statItem(label: String, count: Int, color: Color) -> some View {
        HStack(spacing: APSpacing.sm) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
                .font(.caption).foregroundColor(.textSecondary)
            Spacer()
            Text("\(count)")
                .font(.subheadline).fontWeight(.bold).foregroundColor(.textPrimary)
        }
        .padding(APSpacing.sm)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: APRadius.sm))
        .overlay(RoundedRectangle(cornerRadius: APRadius.sm).stroke(Color.appDivider, lineWidth: 1))
        .frame(maxWidth: .infinity)
    }
    
    private func openSessionSheetView(for table: RestaurantTable) -> some View {
        VStack(spacing: APSpacing.lg) {
            Text(String(format: "open_session_table".localized(for: appLanguage), table.tableNumber))
                .font(.headline).fontWeight(.bold)
                .foregroundColor(.textPrimary)
                .padding(.top, APSpacing.lg)
            
            VStack(spacing: APSpacing.sm) {
                Text("select_guest_count".localized(for: appLanguage))
                    .font(.caption).foregroundColor(.textSecondary)
                
                Picker("Guests", selection: $guestCount) {
                    ForEach(1...12, id: \.self) { num in
                        Text(String(format: "guests_count_label".localized(for: appLanguage), num)).tag(num)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 100)
            }
            
            Button(action: {
                selectedTable = nil
                Task {
                    _ = try? await NetworkService.shared.openSession(tableNumber: table.tableNumber, guestCount: guestCount)
                    await loadTables()
                }
            }) {
                Label("open_table".localized(for: appLanguage), systemImage: "door.left.hand.open")
                    .apGradientButton(gradient: APGradient.positive)
            }
            .padding(.horizontal, APSpacing.md)
            .padding(.bottom, APSpacing.md)
        }
    }
    
    private func loadTables() async {
        isRefreshing = true
        await networkService.refreshAll()
        isRefreshing = false
    }
}

// MARK: - Compact Table Layout & Chairs View

struct CompactTableLayoutView: View {
    let table: RestaurantTable
    let statusColor: Color
    
    private let chairWidth: CGFloat = 24
    private let chairHeight: CGFloat = 13
    private let chairCornerRadius: CGFloat = 4.0
    private let chairGap: CGFloat = 6

    private let roundTableMinDiam: CGFloat = 82
    private let roundTableChairRadiusFactor: CGFloat = 18

    private var formattedTableNumber: String {
        let trimmed = table.tableNumber.trimmingCharacters(in: .whitespacesAndNewlines)
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
        if table.isRound {
            roundLayout
        } else {
            rectangularLayout
        }
    }

    // ── Round Table Layout ──
    private var roundLayout: some View {
        let effectiveCount = max(table.capacity, 1)
        let tableDiam = max(roundTableMinDiam, CGFloat(table.capacity) * roundTableChairRadiusFactor + 30)
        let chairRadius = tableDiam / 2 + chairHeight / 2 + chairGap

        return ZStack {
            tableContent
                .frame(width: tableDiam, height: tableDiam)
                .background(
                    Circle()
                        .fill(Color.appSurface)
                        .overlay(Circle().stroke(Color.appBorderSubtle, lineWidth: 1.2))
                )
                .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)

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
        .padding(16)
    }

    // ── Rectangular Table Layout ──
    private var rectangularLayout: some View {
        let leftCount = table.capacity >= 3 ? 1 : 0
        let rightCount = table.capacity >= 4 ? 1 : 0
        let remaining = table.capacity - leftCount - rightCount
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
                                .stroke(Color.appBorderSubtle, lineWidth: 1.2)
                        )
                )
                .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)

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
        .padding(16)
    }

    // Shared table content (label, status, elapsed)
    private var tableContent: some View {
        let isOccupied = table.status == "occupied"

        return VStack(spacing: 3) {
            Text(formattedTableNumber)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.textPrimary)
                .lineLimit(1)
            
            Text(table.status.uppercased())
                .font(.system(size: 8, weight: .heavy))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .foregroundColor(statusColor)
                .background(statusColor.opacity(0.12))
                .cornerRadius(4)
            
            if isOccupied {
                ElapsedTimeBadge(startedAt: table.sessionStartedAt)
            }
        }
    }
    
    private func xOffsetForIndex(_ idx: Int, count: Int, totalWidth: CGFloat) -> CGFloat {
        if count == 1 { return 0 }
        let availableWidth = totalWidth - 22
        let step = availableWidth / CGFloat(count - 1)
        return -availableWidth / 2 + CGFloat(idx) * step
    }
    
    enum ChairSide {
        case top, bottom, left, right
    }
    
    @ViewBuilder
    private func chairView(width: CGFloat, height: CGFloat, side: ChairSide) -> some View {
        let shapeSide: ChairShapeView.Side = {
            switch side {
            case .top:    return .top
            case .bottom: return .bottom
            case .left:   return .left
            case .right:  return .right
            }
        }()
        ChairShapeView(side: shapeSide, color: statusColor)
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

// MARK: - Canvas Background Grid Pattern

struct CanvasBackgroundGrid: View {
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let step: CGFloat = 20
                for x in stride(from: 0, to: geometry.size.width, by: step) {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: geometry.size.height))
                }
                for y in stride(from: 0, to: geometry.size.height, by: step) {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                }
            }
            .stroke(Color.appDivider.opacity(0.4), lineWidth: 0.5)
            .background(Color.appSurface.opacity(0.1))
            .cornerRadius(12)
        }
    }
}