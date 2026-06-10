import SwiftUI

struct TablesView: View {
    private var networkService = NetworkService.shared
    
    private var tables: [RestaurantTable] {
        networkService.tables
    }
    
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
    @State private var viewMode: ViewMode = .canvas
    
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
    
    private var filteredTables: [RestaurantTable] {
        tables.filter { $0.floor == selectedFloor }
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
                            let vacant   = tables.filter { $0.status == "vacant"   }.count
                            let occupied = tables.filter { $0.status == "occupied" }.count
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
                                    .foregroundColor(.appAccent)
                                    .frame(width: 30, height: 30)
                                    .background(Color.appSurface)
                                    .clipShape(Circle())
                             }
                            
                            Button(action: { Task { await loadTables() } }) {
                                Image(systemName: "arrow.clockwise")
                                    .foregroundColor(.appAccent)
                                    .frame(width: 30, height: 30)
                                    .background(Color.appSurface)
                                    .clipShape(Circle())
                            }
                        }
                        .padding(.horizontal, APSpacing.md)
                        .padding(.vertical, APSpacing.xs)
                        .background(Color.appBackground)
                        
                    } else {
                        // ── Portrait: original stacked layout ──
                        HStack(spacing: APSpacing.md) {
                            let vacant   = tables.filter { $0.status == "vacant"   }.count
                            let occupied = tables.filter { $0.status == "occupied" }.count
                            statItem(label: "vacant".localized(for: appLanguage),
                                     count: vacant,   color: .appTeal)
                            statItem(label: "occupied".localized(for: appLanguage),
                                     count: occupied, color: .appRose)
                        }
                        .padding(APSpacing.md)
                        
                        if !floors.isEmpty {
                            Picker("Floor", selection: $selectedFloor) {
                                ForEach(floors, id: \.self) { floorNum in
                                    Text(floorName(floorNum)).tag(floorNum)
                                }
                            }
                            .pickerStyle(.segmented)
                            .padding(.horizontal, APSpacing.md)
                            .padding(.bottom, APSpacing.sm)
                        }
                        
                        Picker("View Mode", selection: $viewMode) {
                            ForEach(ViewMode.allCases, id: \.self) { mode in
                                Text(mode == .grid ? "Grid View" : "Layout Canvas").tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, APSpacing.md)
                        .padding(.bottom, APSpacing.md)
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
                                    ForEach(filteredTables) { table in
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
                                        
                                        ForEach(filteredTables) { table in
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
                                .onChange(of: tables) { _, _ in
                                    autoFitCanvas(viewportSize: viewport.size)
                                }
                            }
                            // Stretch canvas edge-to-edge, ignoring safe area on sides
                            .ignoresSafeArea(edges: isCompactHeight ? [.horizontal, .bottom] : [])
                        }
                    }
                }
            }
            .navigationTitle(isCompactHeight ? "" : "manage_tables".localized(for: appLanguage))
            .navigationBarTitleDisplayMode(isCompactHeight ? .inline : .automatic)
            .navigationBarHidden(isCompactHeight)
            .toolbar {
                if !isCompactHeight {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button(action: {
                            APHaptic.trigger()
                            withAnimation {
                                if appTheme == AppTheme.dark.rawValue {
                                    appTheme = AppTheme.light.rawValue
                                } else {
                                    appTheme = AppTheme.dark.rawValue
                                }
                            }
                        }) {
                            Image(systemName: appTheme == AppTheme.dark.rawValue ? "sun.max.fill" : "moon.fill")
                                .foregroundColor(.appAccent)
                        }
                        
                        Button(action: {
                            Task {
                                await loadTables()
                            }
                        }) {
                            Image(systemName: "arrow.clockwise")
                                .foregroundColor(.appAccent)
                        }
                    }
                }
            }
        }
        .onAppear {
            Task {
                await loadTables()
            }
        }
        .onChange(of: tables) { _, newTables in
            if !newTables.isEmpty {
                let availableFloors = Array(Set(newTables.map { $0.floor })).sorted()
                if !availableFloors.contains(selectedFloor) {
                    selectedFloor = availableFloors.first ?? 1
                }
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
        
        return VStack(spacing: APSpacing.sm) {
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
            
            CompactTableLayoutView(table: table, statusColor: statusColor)
                .scaleEffect(0.9)
                .frame(height: 65)
            
            Spacer()
        }
        .frame(height: 140)
        .padding(APSpacing.md)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: APRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: APRadius.lg)
                .stroke(isOccupied ? Color.appRose.opacity(0.4) : Color.appDivider, lineWidth: 1.5)
        )
        .shadow(color: isOccupied ? Color.appRose.opacity(0.1) : Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
    }
    
    /// Compact inline badge used in landscape iPhone header
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
    
    private let chairWidth: CGFloat = 18
    private let chairHeight: CGFloat = 9
    private let chairCornerRadius: CGFloat = 3.5
    
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
    
    var body: some View {
        let isOccupied = table.status == "occupied"
        
        let leftCount = table.capacity >= 3 ? 1 : 0
        let rightCount = table.capacity >= 4 ? 1 : 0
        let remaining = table.capacity - leftCount - rightCount
        let topCount = (remaining + 1) / 2
        let bottomCount = remaining / 2
        
        let tableWidth = max(76, CGFloat(max(topCount, bottomCount)) * 40 + 20)
        let tableHeight: CGFloat = 70
        
        ZStack {
            // Table surface card
            VStack(spacing: 3) {
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
                    HStack(spacing: 4) {
                        HStack(spacing: 1) {
                            Image(systemName: "person.fill")
                                .font(.system(size: 8))
                            Text("\(table.guestCount)")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .foregroundColor(.textSecondary)
                        
                        if table.currentTotal > 0 {
                            Text("฿\(Int(table.currentTotal))")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.appRose)
                        }
                    }
                }
            }
            .frame(width: tableWidth, height: tableHeight)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.appSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(
                                Color.appBorderSubtle,
                                lineWidth: 1.2
                            )
                    )
            )
            .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
            
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
        .padding(16)
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
        ZStack {
            RoundedRectangle(cornerRadius: chairCornerRadius, style: .continuous)
                .fill(statusColor.opacity(0.25))
                .overlay(
                    RoundedRectangle(cornerRadius: chairCornerRadius, style: .continuous)
                        .stroke(statusColor.opacity(0.8), lineWidth: 1)
                )
            
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