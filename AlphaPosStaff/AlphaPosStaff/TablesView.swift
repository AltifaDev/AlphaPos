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
    
    // Zoom & Pan gesture states for canvas mode (iPad-like interaction)
    @State private var zoomScale: CGFloat = 0.45
    @State private var gestureScale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @State private var activePanOffset: CGSize = .zero
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
        if selectedZone == "All" {
            return floorTables
        } else {
            return floorTables.filter { $0.zone == selectedZone }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    if isCompactHeight {
                        // ── Landscape iPhone: single compact toolbar row ──
                        HStack(spacing: APSpacing.sm) {
                            // Stat badges (small)
                            let vacant   = filteredTables.filter { $0.status == "vacant"   }.count
                            let occupied = filteredTables.filter { $0.status == "occupied" }.count
                            compactStatBadge(label: "vacant".localized(for: appLanguage),
                                             count: vacant,   color: .appTeal)
                            compactStatBadge(label: "occupied".localized(for: appLanguage),
                                             count: occupied, color: .appRose)
                            
                            Divider().frame(height: 20)
                            
                            // Floor picker (inline style, smaller)
                            if !floors.isEmpty {
                                Picker("Floor", selection: $selectedFloor) {
                                    ForEach(floors, id: \.self) { floorNum in
                                        Text(floorName(floorNum)).tag(floorNum)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .frame(maxWidth: 200)
                            }
                            
                            // Zone picker (inline style, smaller)
                            if zones.count > 1 {
                                Divider().frame(height: 20)
                                
                                Picker("Zone", selection: $selectedZone) {
                                    ForEach(zones, id: \.self) { zone in
                                        Text(zone.localized(for: appLanguage)).tag(zone)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .frame(maxWidth: 180)
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
                            
                            Button(action: { Task { await loadTables() } }) {
                                Image(systemName: "arrow.clockwise")
                                    .foregroundColor(.white)
                                    .frame(width: 30, height: 30)
                                    .background(Color.white.opacity(0.18))
                                    .clipShape(Circle())
                            }
                        }
                        .padding(.horizontal, APSpacing.md)
                        .padding(.vertical, APSpacing.xs)
                        .background(APGradient.accent.ignoresSafeArea(edges: .top))
                        .offset(y: isAnimatedIn ? 0 : -50)
                        .opacity(isAnimatedIn ? 1 : 0)
                        
                    } else {
                        // ── Portrait: Custom Blue Gradient Header ──
                        // ── Row 1: Compact title bar (soft gradient) ──
                        HStack(spacing: APSpacing.sm) {
                            Image(systemName: "table.furniture.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white.opacity(0.9))

                            Text("manage_tables".localized(for: appLanguage))
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(.white)

                            Spacer()

                            // Stat badges inline in header
                            let vacant   = filteredTables.filter { $0.status == "vacant"   }.count
                            let occupied = filteredTables.filter { $0.status == "occupied" }.count
                            headerStatBadge(count: vacant,   color: .appTeal,  icon: "circle.fill")
                            headerStatBadge(count: occupied, color: .appRose,  icon: "circle.fill")
                            Divider().frame(height: 16).overlay(Color.white.opacity(0.3))
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
                                    .foregroundColor(.white)
                                    .frame(width: 30, height: 30)
                                    .background(Color.white.opacity(0.15))
                                    .clipShape(Circle())
                            }
                            // Refresh
                            Button(action: { Task { await loadTables() } }) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 13))
                                    .foregroundColor(.white)
                                    .frame(width: 30, height: 30)
                                    .background(Color.white.opacity(0.15))
                                    .clipShape(Circle())
                            }
                        }
                        .padding(.horizontal, APSpacing.md)
                        .padding(.vertical, 9)
                        .background(APGradient.accent.ignoresSafeArea(edges: .top))
                        .offset(y: isAnimatedIn ? 0 : -50)
                        .opacity(isAnimatedIn ? 1 : 0)
                        // ── Row 2: Pickers compact in one scrollable row ──
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: APSpacing.sm) {
                                if !floors.isEmpty {
                                    Picker("Floor", selection: $selectedFloor) {
                                        ForEach(floors, id: \.self) { floorNum in
                                            Text(floorName(floorNum)).tag(floorNum)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                    .frame(minWidth: CGFloat(floors.count) * 72)
                                }
                                if zones.count > 1 {
                                    Picker("Zone", selection: $selectedZone) {
                                        ForEach(zones, id: \.self) { zone in
                                            Text(zone.localized(for: appLanguage)).tag(zone)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                    .frame(minWidth: CGFloat(zones.count) * 68)
                                }
                                Picker("View", selection: $viewMode) {
                                    ForEach(ViewMode.allCases, id: \.self) { mode in
                                        Text(mode == .grid ? "Grid" : "Canvas").tag(mode)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .frame(minWidth: 130)
                            }
                            .padding(.horizontal, APSpacing.md)
                        }
                        .padding(.vertical, APSpacing.xs)
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
                                        let directionOffset: CGFloat = (index % 2 == 0) ? -80 : 80
                                        Group {
                                            if table.status == "occupied" {
                                                NavigationLink(destination: TableDetailView(table: table)) {
                                                    tableCard(table: table)
                                                }
                                                .buttonStyle(.plain)
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
                                        .offset(x: isAnimatedIn ? 0 : directionOffset, y: isAnimatedIn ? 0 : 60)
                                        .opacity(isAnimatedIn ? 1 : 0)
                                        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(Double(index) * 0.03), value: filteredTables)
                                        .animation(.spring(response: 0.65, dampingFraction: 0.75).delay(Double(index) * 0.04), value: isAnimatedIn)
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
                                        CanvasBackgroundGrid()
                                            .frame(width: 1500, height: 1200)
                                            .allowsHitTesting(false)

                                        
                                        ForEach(Array(canvasTables.enumerated()), id: \.element.id) { index, table in
                                            let statusColor = table.status == "occupied" ? Color.appRose : Color.appTeal
                                            
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
                            // Stretch canvas edge-to-edge, ignoring safe area on sides
                            .ignoresSafeArea(edges: isCompactHeight ? [.horizontal, .bottom] : [])
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
            let currentStatuses = canvasTables.map { ($0.tableNumber, $0.status, $0.currentTotal) }
            let newStatuses     = newFiltered.map   { ($0.tableNumber, $0.status, $0.currentTotal) }
            let changed = zip(currentStatuses, newStatuses).contains { a, b in
                a.0 != b.0 || a.1 != b.1 || a.2 != b.2
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
            
            // Reset zone filter if not available on the new floor
            let newFloorTables = tables.filter { $0.floor == newFloor }
            let newZones = Set(newFloorTables.compactMap { $0.zone }).filter { !$0.isEmpty }
            if selectedZone != "All" && !newZones.contains(selectedZone) {
                selectedZone = "All"
            }
        }
        .sheet(item: $selectedTable) { table in
            openSessionSheetView(for: table)
                .presentationDetents([.fraction(0.45)])
                .apColorScheme()
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
    
    // MARK: - Table Card Component
    
    private func tableCard(table: RestaurantTable) -> some View {
        let isOccupied = table.status == "occupied"
        let statusColor = isOccupied ? Color.appRose : Color.appTeal
        
        let estWidth: CGFloat = {
            if table.isRound {
                let effectiveCount = max(table.capacity, 1)
                let tableDiam = max(82, CGFloat(effectiveCount) * 18 + 30)
                let chairGap: CGFloat = 6
                let chairHeight: CGFloat = 13
                let chairRadius = tableDiam / 2 + chairHeight / 2 + chairGap
                return (chairRadius + chairHeight) * 2
            } else {
                let leftCount = table.capacity >= 3 ? 1 : 0
                let rightCount = table.capacity >= 4 ? 1 : 0
                let remaining = table.capacity - leftCount - rightCount
                let topCount = (remaining + 1) / 2
                let bottomCount = remaining / 2
                let maxRow = max(topCount, bottomCount)
                let tableWidth = max(76, CGFloat(maxRow) * 40 + 20)
                let chairGap: CGFloat = 6
                let chairHeight: CGFloat = 13
                let totalChairsWidth = (leftCount > 0 ? chairHeight + chairGap : 0) + (rightCount > 0 ? chairHeight + chairGap : 0)
                return tableWidth + totalChairsWidth + 10
            }
        }()

        return GeometryReader { cardGeo in
            VStack(spacing: APSpacing.sm) {
                HStack {
                    Text(String(format: "table_label".localized(for: appLanguage), table.tableNumber))
                        .font(.headline).fontWeight(.black)
                        .foregroundColor(.textPrimary)
                    
                    Spacer()
                    
                    APBadge(
                        text: isOccupied ? "occupied".localized(for: appLanguage) : "vacant".localized(for: appLanguage),
                        color: statusColor
                    )
                }
                
                Spacer()
                
                let targetWidth = cardGeo.size.width - 32
                let scale = min(0.9, targetWidth / estWidth)
                
                CompactTableLayoutView(table: table, statusColor: statusColor)
                    .scaleEffect(scale)
                    .frame(height: 65)
                
                Spacer()
            }
            .padding(APSpacing.md)
            .frame(width: cardGeo.size.width, height: cardGeo.size.height)
            .background(Color.appSurface)
            .clipShape(RoundedRectangle(cornerRadius: APRadius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: APRadius.lg)
                    .stroke(isOccupied ? Color.appRose.opacity(0.4) : Color.appDivider, lineWidth: 1.5)
            )
            .shadow(color: isOccupied ? Color.appRose.opacity(0.1) : Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
        }
        .frame(height: 140)
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
                .foregroundColor(.white)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.14))
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