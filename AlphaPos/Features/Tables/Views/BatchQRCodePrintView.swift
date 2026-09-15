import SwiftUI
import SwiftData

struct BatchQRCodePrintView: View {
    @EnvironmentObject private var lm: LocalizationManager
    let tables: [RestaurantTable]
    @AppStorage("active_merchant_id") private var activeMerchantId = ""
    @AppStorage("qr_custom_store_name") private var qrCustomStoreName = "AlphaPos Restaurant"
    @AppStorage("qr_custom_header") private var qrCustomHeader = "Scan to Order"
    @AppStorage("qr_custom_color") private var qrCustomColor = "#111115"
    @Query(sort: \FloorData.sortOrder) private var allFloors: [FloorData]
    @AppStorage("table_qr_print_mode") private var qrPrintMode = "permanent"

    /// Reads UserDefaults override first, then falls back to production customer web URL.
    private var customerWebBaseUrl: String {
        let ud = UserDefaults.standard.string(forKey: "dynamic_customer_web_url") ?? ""
        return ud.isEmpty ? "https://sync.alphaposweb.com" : ud
    }

    private var floors: [FloorData] {
        let branchId = BranchContext.shared.activeBranchIDString
        return allFloors.filter { $0.branchId == branchId && $0.isActive && !$0.isDeleted }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var qrCodeCache: [UUID: UIImage] = [:]
    @State private var zoomedTable: RestaurantTable? = nil
    @State private var sharePDFURL: URL? = nil
    @State private var showShareSheet = false
    @State private var showMerchantAlert = false
    @State private var showPrintError = false
    @State private var printErrorMessage = ""
    @State private var gridWidth: CGFloat = 800
    @State private var isGenerating = true
    @State private var generateDone = 0
    @State private var generateTotal = 0
    @State private var copiedTableID: UUID? = nil
    @State private var showQRGuide = false
    @Namespace private var qrZoomNamespace

    /// Active tables only, naturally sorted (1, 2, 3 … 201) then grouped by floor / zone.
    private var sortedTables: [RestaurantTable] {
        tables
            .filter {
                guard !$0.isDeleted else { return false }
                if qrPrintMode == "permanent" {
                    return !($0.qrCodeIdentifier ?? "").isEmpty
                }
                return activeSession(for: $0) != nil
            }
            .sorted { lhs, rhs in
                let floorCmp = (lhs.floor ?? 1).compare(rhs.floor ?? 1)
                if floorCmp != .orderedSame { return floorCmp == .orderedAscending }
                let zoneCmp = zoneSortKey(lhs.zone).compare(zoneSortKey(rhs.zone), options: .caseInsensitive)
                if zoneCmp != .orderedSame { return zoneCmp == .orderedAscending }
                return lhs.tableNumber.compare(rhs.tableNumber, options: [.numeric, .caseInsensitive]) == .orderedAscending
            }
    }

    private var sections: [QRSection] {
        var buckets: [(key: String, floor: Int, zone: String, tables: [RestaurantTable])] = []
        var indexByKey: [String: Int] = [:]

        for table in sortedTables {
            let floor = table.floor ?? 1
            let zone = (table.zone?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "Indoor"
            let key = "\(floor)||\(zone)"
            if let idx = indexByKey[key] {
                buckets[idx].tables.append(table)
            } else {
                indexByKey[key] = buckets.count
                buckets.append((key: key, floor: floor, zone: zone, tables: [table]))
            }
        }

        return buckets.map { bucket in
            QRSection(
                id: bucket.key,
                title: sectionTitle(floor: bucket.floor, zone: bucket.zone),
                subtitle: String(format: "table_qr_section_count".t, bucket.tables.count),
                tables: bucket.tables
            )
        }
    }

    var body: some View {
        let columnCount = gridColumnCount(for: gridWidth)
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: 10),
            count: columnCount
        )

        ZStack {
            NavigationStack {
                Group {
                    if isGenerating {
                        // Keep first paint light — avoid mounting the full grid while encoding QR images.
                        Color.appBackground
                            .ignoresSafeArea()
                    } else {
                        ScrollView(.vertical, showsIndicators: true) {
                            VStack(alignment: .leading, spacing: 14) {
                                Button {
                                    showQRGuide = true
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "info.circle.fill")
                                            .font(.title3)
                                            .foregroundColor(.appAccent)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(lm.languageCode == "th" ? "วิธีใช้งาน QR Code โต๊ะ" : "How table QR codes work")
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundColor(.textPrimary)
                                            Text(lm.languageCode == "th" ? "การใช้ซ้ำ หลายเครื่อง อายุคำขอ และการสร้างใหม่" : "Reuse, multiple devices, request expiry, and regeneration")
                                                .font(.caption)
                                                .foregroundColor(.textSecondary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption.weight(.semibold))
                                            .foregroundColor(.textTertiary)
                                    }
                                    .padding(12)
                                    .background(Color.appAccent.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 12)
                                .accessibilityHint(lm.languageCode == "th" ? "เปิดคู่มือการใช้งาน Permanent QR และ Session QR" : "Opens the Permanent QR and Session QR guide")

                                Picker("รูปแบบ QR Code", selection: $qrPrintMode) {
                                    Text("QR ประจำโต๊ะ").tag("permanent")
                                    Text("QR ตามรอบลูกค้า").tag("session")
                                }
                                .pickerStyle(.segmented)
                                .padding(.horizontal, 12)

                                qrModeExplanationCard
                                    .padding(.horizontal, 12)

                                Text("table_qr_grid_preview_hint".t)
                                    .font(.caption)
                                    .foregroundColor(.textSecondary)
                                    .padding(.horizontal, 12)
                                    .padding(.top, 8)

                                if activeMerchantId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    merchantMissingBanner
                                        .padding(.horizontal, 12)
                                }

                                if sections.isEmpty {
                                    emptyQRState
                                        .padding(.horizontal, 12)
                                        .padding(.top, 20)
                                } else {
                                    ForEach(sections) { section in
                                        VStack(alignment: .leading, spacing: 8) {
                                            HStack(alignment: .firstTextBaseline) {
                                                Text(section.title)
                                                    .font(.subheadline.weight(.bold))
                                                    .foregroundColor(.textPrimary)
                                                Spacer(minLength: 8)
                                                Text(section.subtitle)
                                                    .font(.caption2)
                                                    .foregroundColor(.textSecondary)
                                            }
                                            .padding(.horizontal, 12)

                                            LazyVGrid(columns: columns, spacing: 10) {
                                                ForEach(section.tables) { table in
                                                    TableQRCard(
                                                        table: table,
                                                        qrImage: qrCodeCache[table.id],
                                                        namespace: qrZoomNamespace,
                                                        isZoomed: zoomedTable?.id == table.id,
                                                        compact: columnCount >= 5
                                                    ) {
                                                        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                                                            zoomedTable = table
                                                        }
                                                    }
                                                }
                                            }
                                            .padding(.horizontal, 10)
                                        }
                                    }
                                }
                            }
                            .padding(.bottom, 24)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                GeometryReader { geo in
                                    Color.clear
                                        .preference(key: QRGridWidthKey.self, value: geo.size.width)
                                }
                            )
                        }
                        .scrollDismissesKeyboard(.immediately)
                    }
                }
                .background(Color.appBackground)
                .navigationTitle("table_qr_all_codes_title".t)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("close_btn".t) { dismiss() }
                    }

                    ToolbarItemGroup(placement: .navigationBarTrailing) {
                        Button {
                            showQRGuide = true
                        } label: {
                            Image(systemName: "questionmark.circle")
                        }
                        .accessibilityLabel(lm.languageCode == "th" ? "คู่มือ QR Code" : "QR code guide")

                        Button(action: sharePDF) {
                            Label("table_qr_export_pdf_btn".t, systemImage: "square.and.arrow.up")
                        }
                        .disabled(sortedTables.isEmpty || isGenerating)

                        Button(action: printPDF) {
                            Label("table_qr_print_btn".t, systemImage: "printer.fill")
                                .foregroundColor(.appAccent)
                        }
                        .disabled(sortedTables.isEmpty || isGenerating)
                    }
                }
                .onPreferenceChange(QRGridWidthKey.self) { width in
                    if width > 0, abs(width - gridWidth) > 0.5 {
                        gridWidth = width
                    }
                }
            }

            if isGenerating {
                generatingOverlay
                    .transition(.opacity)
                    .zIndex(2)
            }

            if let table = zoomedTable, !isGenerating {
                zoomedOverlay(for: table)
                    .transition(.opacity)
                    .allowsHitTesting(true)
                    .zIndex(3)
            }
        }
        .onAppear {
            generateAllQRCodes()
            if activeMerchantId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // Defer alert until grid is ready so it doesn't fight the loading UI.
            }
        }
        .onChange(of: qrPrintMode) {
            generateAllQRCodes()
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = sharePDFURL {
                ShareSheet(activityItems: [url])
            }
        }
        .sheet(isPresented: $showQRGuide) {
            TableQRCodeGuideView()
                .environmentObject(lm)
        }
        .alert("table_qr_merchant_missing_title".t, isPresented: $showMerchantAlert) {
            Button("ok_btn".t, role: .cancel) {}
        } message: {
            Text("table_qr_merchant_missing_msg".t)
        }
        .alert("table_qr_print_error_title".t, isPresented: $showPrintError) {
            Button("ok_btn".t, role: .cancel) {}
        } message: {
            Text(printErrorMessage)
        }
    }

    private var qrModeExplanationCard: some View {
        let permanent = qrPrintMode == "permanent"
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: permanent ? "qrcode" : "clock.arrow.circlepath")
                    .font(.headline)
                    .foregroundStyle(Color.appAccent)
                Text(permanent
                     ? (lm.languageCode == "th" ? "QR ประจำโต๊ะ — สำหรับติดใช้งานถาวร" : "Permanent table QR — for ongoing use")
                     : (lm.languageCode == "th" ? "QR ตามรอบลูกค้า — สำหรับการเข้าใช้ครั้งเดียว" : "Session QR — for one guest visit"))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.textPrimary)
            }

            VStack(alignment: .leading, spacing: 7) {
                ForEach(modeInstructions(permanent: permanent), id: \.self) { instruction in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.appTeal)
                            .padding(.top, 2)
                        Text(instruction)
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .apLiquidGlass(
            tint: Color.appAccent.opacity(0.05),
            allowNativeOnPad: true,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }

    private func modeInstructions(permanent: Bool) -> [String] {
        if permanent {
            return lm.languageCode == "th"
                ? [
                    "พิมพ์ QR แล้วติดให้ตรงกับหมายเลขโต๊ะ ใช้ใบเดิมซ้ำได้ทุกวัน",
                    "เมื่อลูกค้าสแกน พนักงานต้องตรวจสอบโต๊ะและยืนยันคำขอภายใน 5 นาที",
                    "การเคลียร์โต๊ะไม่ทำให้ QR เปลี่ยน สร้างใหม่เฉพาะเมื่อ QR สูญหายหรือถูกเผยแพร่ผิดที่"
                ]
                : [
                    "Print and place each QR on its matching table; the same code can be reused every day.",
                    "After a guest scans, staff verify the table and approve the request within five minutes.",
                    "Clearing the table does not change this QR. Regenerate it only if it is lost or exposed."
                ]
        }
        return lm.languageCode == "th"
            ? [
                "เปิดโต๊ะหรือสร้างรอบลูกค้าในหน้าจัดการโต๊ะก่อน QR จึงจะแสดงในหน้านี้",
                "แชร์หรือพิมพ์ QR ให้ลูกค้าของรอบปัจจุบัน ใช้ร่วมกันได้หลายเครื่องในโต๊ะเดียวกัน",
                "QR จะหมดอายุทันทีเมื่อชำระเงินและเคลียร์โต๊ะ ลูกค้ารอบใหม่ต้องใช้ QR ที่สร้างใหม่"
            ]
            : [
                "Open the table or create a guest session first; its QR will then appear on this page.",
                "Share or print the QR for the current visit. Multiple guests at the same table may use it.",
                "The QR expires when payment is completed and the table is cleared; the next visit gets a new QR."
            ]
    }

    private var emptyQRState: some View {
        let permanent = qrPrintMode == "permanent"
        return VStack(spacing: 12) {
            Image(systemName: permanent ? "qrcode.viewfinder" : "tablecells.badge.ellipsis")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(Color.appAccent)
            Text(permanent
                 ? (lm.languageCode == "th" ? "ยังไม่มี QR ประจำโต๊ะ" : "No permanent table QR codes")
                 : (lm.languageCode == "th" ? "ยังไม่มีโต๊ะที่เปิดรอบลูกค้า" : "No active guest sessions"))
                .font(.headline)
                .foregroundStyle(Color.textPrimary)
            Text(permanent
                 ? (lm.languageCode == "th"
                    ? "กรุณาสร้างหรือเปิดใช้งานโต๊ะและกำหนด QR ประจำโต๊ะจากหน้าจัดการโต๊ะ แล้วกลับมาที่หน้านี้อีกครั้ง"
                    : "Create or enable tables and assign their permanent QR codes in Table Management, then return here.")
                 : (lm.languageCode == "th"
                    ? "ไปที่หน้าจัดการโต๊ะ เลือกโต๊ะว่างแล้วเปิดโต๊ะ เมื่อมี Table Session ระบบจะแสดง QR ของรอบนั้นที่นี่โดยอัตโนมัติ"
                    : "Open a vacant table in Table Management. When its table session starts, the session QR appears here automatically."))
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 620)
            Button {
                showQRGuide = true
            } label: {
                Label(lm.languageCode == "th" ? "อ่านคู่มือฉบับเต็ม" : "Read the full guide", systemImage: "questionmark.circle")
            }
            .apGlassButton(prominent: true, tint: Color.appAccent)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .apLiquidGlass(
            tint: Color.appAccent.opacity(0.035),
            allowNativeOnPad: true,
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
    }

    private var merchantMissingBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text("table_qr_merchant_missing_msg".t)
                .font(.caption)
                .foregroundColor(.textSecondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12))
        .cornerRadius(10)
    }

    private var generatingOverlay: some View {
        ZStack {
            Color.appBackground.opacity(0.92)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .stroke(Color.appAccent.opacity(0.15), lineWidth: 5)
                        .frame(width: 72, height: 72)
                    Circle()
                        .trim(from: 0, to: generateTotal > 0 ? CGFloat(generateDone) / CGFloat(generateTotal) : 0.08)
                        .stroke(Color.appAccent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .frame(width: 72, height: 72)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.2), value: generateDone)
                    Image(systemName: "qrcode")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(.appAccent)
                        .symbolEffect(.pulse, options: .repeating)
                }

                VStack(spacing: 6) {
                    Text("table_qr_preparing_lbl".t)
                        .font(.headline)
                        .foregroundColor(.textPrimary)
                    if generateTotal > 0 {
                        Text(String(format: "table_qr_generating_progress".t, generateDone, generateTotal))
                            .font(.subheadline)
                            .foregroundColor(.textSecondary)
                            .monospacedDigit()
                    }
                }
            }
            .padding(28)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.appSurface)
                    .shadow(color: .black.opacity(0.1), radius: 20, y: 8)
            )
        }
        .allowsHitTesting(true)
    }

    // MARK: - Layout helpers

    private func gridColumnCount(for width: CGFloat) -> Int {
        switch width {
        case ..<500: return 3
        case ..<700: return 4
        case ..<900: return 5
        default: return 6
        }
    }

    private func zoneSortKey(_ zone: String?) -> String {
        let raw = (zone ?? "Indoor").trimmingCharacters(in: .whitespacesAndNewlines)
        switch raw.lowercased() {
        case "indoor", "ในร้าน": return "0-Indoor"
        case "outdoor", "นอกร้าน": return "1-Outdoor"
        case "rooftop", "roof", "ดาดฟ้า": return "2-Rooftop"
        default: return "3-\(raw)"
        }
    }

    private func sectionTitle(floor: Int, zone: String) -> String {
        let floorName = floors.first(where: { $0.id == floor })?.name
            ?? String(format: "table_floor_new_name".t, floor)
        let zoneLabel: String = {
            switch zone.lowercased() {
            case "indoor": return "table_zone_indoor".t
            case "outdoor": return "table_zone_outdoor".t
            case "rooftop", "roof": return "table_zone_rooftop".t
            default: return zone
            }
        }()
        return "\(floorName) · \(zoneLabel)"
    }

    private func qrURL(for tableNumber: String) -> String {
        let encodedTable = tableNumber.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? tableNumber
        var url = "\(customerWebBaseUrl)/?table=\(encodedTable)"
        let merchant = activeMerchantId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !merchant.isEmpty {
            url += "&merchant=\(merchant)"
        }
        if qrPrintMode == "permanent",
           let table = tables.first(where: { $0.tableNumber == tableNumber }),
           let permanentKey = table.qrCodeIdentifier,
           !permanentKey.isEmpty {
            let encodedKey = permanentKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? permanentKey
            url += "&key=\(encodedKey)"
        } else if qrPrintMode == "session",
           let table = tables.first(where: { $0.tableNumber == tableNumber }),
           let session = activeSession(for: table) {
            url += "&token=\(session.sessionToken)"
        }
        return url
    }

    private func activeSession(for table: RestaurantTable) -> TableSession? {
        let leader = table.joinedParent ?? table
        return leader.sessions.first(where: { $0.isActive })
    }

    // MARK: - QR generation

    /// Shared CIContext — creating one per QR was a major stall source.
    private static let sharedCIContext = CIContext(options: [.useSoftwareRenderer: false])

    private func generateAllQRCodes() {
        let tableData = sortedTables.map {
            (id: $0.id, tableNumber: $0.tableNumber, token: activeSession(for: $0)?.sessionToken,
             permanentKey: $0.qrCodeIdentifier)
        }
        let merchantId = activeMerchantId
        let baseUrl = customerWebBaseUrl
        let mode = qrPrintMode
        let total = tableData.count

        isGenerating = true
        generateDone = 0
        generateTotal = total

        guard total > 0 else {
            finishGeneration(cache: [:])
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            var temporaryCache: [UUID: UIImage] = [:]
            temporaryCache.reserveCapacity(total)

            for (offset, table) in tableData.enumerated() {
                let encodedTable = table.tableNumber.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? table.tableNumber
                var qrUrl = "\(baseUrl)/?table=\(encodedTable)"
                let merchant = merchantId.trimmingCharacters(in: .whitespacesAndNewlines)
                if !merchant.isEmpty {
                    qrUrl += "&merchant=\(merchant)"
                }
                if mode == "permanent", let permanentKey = table.permanentKey, !permanentKey.isEmpty {
                    let encodedKey = permanentKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? permanentKey
                    qrUrl += "&key=\(encodedKey)"
                } else if mode == "session", let token = table.token {
                    qrUrl += "&token=\(token)"
                }
                // Preview scale 6 is sharp enough for on-screen cards; PDF rebuilds at higher scale.
                if let image = Self.generateQRCodeSync(from: qrUrl, scale: 6) {
                    temporaryCache[table.id] = image
                }

                let done = offset + 1
                // Throttle UI progress updates to keep the main thread responsive.
                if done == total || done % 3 == 0 {
                    DispatchQueue.main.async {
                        self.generateDone = done
                    }
                }
            }

            DispatchQueue.main.async {
                self.finishGeneration(cache: temporaryCache)
            }
        }
    }

    private func finishGeneration(cache: [UUID: UIImage]) {
        qrCodeCache = cache
        generateDone = generateTotal
        // Reveal the grid without an opacity-gated entrance animation.
        // LazyVGrid + delayed `.animation(value:)` often left cards stuck at opacity 0.
        withAnimation(.easeOut(duration: 0.25)) {
            isGenerating = false
        }
        if activeMerchantId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            showMerchantAlert = true
        }
    }

    private static func generateQRCodeSync(from string: String, scale: CGFloat = 10) -> UIImage? {
        let showLogo = UserDefaults.standard.object(forKey: "qr_custom_show_logo") as? Bool ?? true
        let logoPreset = UserDefaults.standard.string(forKey: "qr_custom_logo_preset") ?? "bolt.fill"
        let colorHex = UserDefaults.standard.string(forKey: "qr_custom_color") ?? "#111115"

        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(string.data(using: .utf8), forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel")

        guard let ciImage = filter.outputImage else { return nil }

        let tintColor = UIColor(hex: colorHex)

        guard let colorFilter = CIFilter(name: "CIFalseColor") else { return nil }
        colorFilter.setValue(ciImage, forKey: kCIInputImageKey)
        colorFilter.setValue(CIColor(color: tintColor), forKey: "inputColor0")
        colorFilter.setValue(CIColor(red: 1, green: 1, blue: 1), forKey: "inputColor1")

        guard let output = colorFilter.outputImage else { return nil }

        let transform = CGAffineTransform(scaleX: scale, y: scale)
        let scaledOutput = output.transformed(by: transform)

        guard let cgImage = sharedCIContext.createCGImage(scaledOutput, from: scaledOutput.extent) else { return nil }

        let tintedImage = UIImage(cgImage: cgImage)

        if showLogo && !logoPreset.isEmpty {
            return tintedImage.overlayLogo(systemIconName: logoPreset, tintColor: tintColor)
        }

        return tintedImage
    }

    // MARK: - Zoom overlay

    private func zoomedOverlay(for table: RestaurantTable) -> some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) {
                        zoomedTable = nil
                    }
                }

            VStack(spacing: 20) {
                HStack {
                    Spacer()
                    Button(action: {
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) {
                            zoomedTable = nil
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.textSecondary)
                    }
                    .buttonStyle(.plain)
                }

                Text(qrCustomStoreName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.textSecondary)

                Text(LocalizationManager.shared.t("table_number_template", table.tableNumber))
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(Color(hex: qrCustomColor))

                Text(sectionTitle(floor: table.floor ?? 1, zone: table.zone ?? "Indoor"))
                    .font(.caption)
                    .foregroundColor(.textSecondary)

                let qrUrl = qrURL(for: table.tableNumber)

                if let qrImage = qrCodeCache[table.id] {
                    Image(uiImage: qrImage)
                        .resizable()
                        .interpolation(.none)
                        .frame(width: 280, height: 280)
                        .matchedGeometryEffect(id: "qr_image_\(table.id)", in: qrZoomNamespace)
                        .padding(16)
                        .background(Color.white)
                        .cornerRadius(12)
                        .shadow(color: Color.black.opacity(0.12), radius: 8)
                } else {
                    ProgressView()
                        .frame(width: 312, height: 312)
                }

                VStack(spacing: 8) {
                    Text(qrCustomHeader)
                        .font(.caption)
                        .foregroundColor(.textSecondary)

                    if let destination = URL(string: qrUrl) {
                        Button {
                            openURL(destination)
                        } label: {
                            Text(qrUrl)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.appAccent)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                                .lineLimit(2)
                                .underline()
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("เปิดลิงก์ในเบราว์เซอร์")
                    } else {
                        Text(qrUrl)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                            .lineLimit(2)
                    }

                    Button(action: {
                        UIPasteboard.general.setItems([[
                            "public.utf8-plain-text": qrUrl,
                            "public.url": qrUrl
                        ]])
                        copiedTableID = table.id
                        APHaptic.trigger()
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(2))
                            if copiedTableID == table.id {
                                copiedTableID = nil
                            }
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: copiedTableID == table.id ? "checkmark.circle.fill" : "doc.on.doc")
                            Text(copiedTableID == table.id ? "sync_tech_copied".t : "table_qr_copy_link_btn".t)
                        }
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.appAccent)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.appAccent.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .padding(.top, 4)
                }
            }
            .padding(24)
            .frame(width: 380)
            .background(Color.appSurface)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.25), radius: 15)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.appBorderSubtle, lineWidth: 1)
            )
            .matchedGeometryEffect(id: "card_container_\(table.id)", in: qrZoomNamespace)
        }
    }

    // MARK: - PDF / Print

    private func buildPDF() -> URL? {
        let pdfRenderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595.2, height: 841.8))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("AlphaPos_Table_QRCodes.pdf")
        let columnsPerPage = 4
        let rowsPerPage = 5
        let itemsPerPage = columnsPerPage * rowsPerPage
        let pageTables = sortedTables

        do {
            try pdfRenderer.writePDF(to: url) { context in
                let totalPages = max(1, Int(ceil(Double(pageTables.count) / Double(itemsPerPage))))

                for pageIndex in 0..<totalPages {
                    context.beginPage()

                    let title = "AlphaPos - " + "table_qr_all_codes_title".t
                    title.draw(
                        at: CGPoint(x: 28, y: 28),
                        withAttributes: [
                            .font: UIFont.boldSystemFont(ofSize: 15),
                            .foregroundColor: UIColor.black
                        ]
                    )

                    let drawContext = context.cgContext
                    drawContext.setStrokeColor(UIColor.lightGray.cgColor)
                    drawContext.setLineWidth(0.5)
                    drawContext.move(to: CGPoint(x: 28, y: 50))
                    drawContext.addLine(to: CGPoint(x: 567.2, y: 50))
                    drawContext.strokePath()

                    let startX: CGFloat = 28
                    let startY: CGFloat = 62
                    let colWidth: CGFloat = (595.2 - 56) / CGFloat(columnsPerPage)
                    let rowHeight: CGFloat = (841.8 - 100) / CGFloat(rowsPerPage)

                    let startIndex = pageIndex * itemsPerPage
                    let endIndex = min(startIndex + itemsPerPage, pageTables.count)

                    for index in startIndex..<endIndex {
                        let table = pageTables[index]
                        let itemIndex = index - startIndex
                        let col = CGFloat(itemIndex % columnsPerPage)
                        let row = CGFloat(itemIndex / columnsPerPage)
                        let x = startX + col * colWidth
                        let y = startY + row * rowHeight

                        let cardRect = CGRect(x: x + 3, y: y + 3, width: colWidth - 6, height: rowHeight - 6)
                        drawContext.setFillColor(UIColor(white: 0.98, alpha: 1.0).cgColor)
                        drawContext.fill(cardRect)
                        drawContext.setStrokeColor(UIColor(white: 0.85, alpha: 1.0).cgColor)
                        drawContext.setLineWidth(0.8)
                        UIBezierPath(roundedRect: cardRect, cornerRadius: 6).stroke()

                        let storeName = UserDefaults.standard.string(forKey: "qr_custom_store_name") ?? "AlphaPos Restaurant"
                        let headerText = UserDefaults.standard.string(forKey: "qr_custom_header") ?? "Scan to Order"
                        let colorHex = UserDefaults.standard.string(forKey: "qr_custom_color") ?? "#111115"
                        let themeColor = UIColor(hex: colorHex)

                        storeName.draw(
                            at: CGPoint(x: x + 10, y: y + 10),
                            withAttributes: [
                                .font: UIFont.systemFont(ofSize: 7, weight: .semibold),
                                .foregroundColor: UIColor.darkGray
                            ]
                        )

                        let tableName = LocalizationManager.shared.t("table_number_template", table.tableNumber)
                        tableName.draw(
                            at: CGPoint(x: x + 10, y: y + 22),
                            withAttributes: [
                                .font: UIFont.boldSystemFont(ofSize: 11),
                                .foregroundColor: themeColor
                            ]
                        )

                        let meta = sectionTitle(floor: table.floor ?? 1, zone: table.zone ?? "Indoor")
                        meta.draw(
                            at: CGPoint(x: x + 10, y: y + 36),
                            withAttributes: [
                                .font: UIFont.systemFont(ofSize: 7),
                                .foregroundColor: UIColor.gray
                            ]
                        )

                        let qrUrl = qrURL(for: table.tableNumber)
                        let qrSize: CGFloat = min(colWidth - 24, rowHeight - 70)
                        if let qrImage = Self.generateQRCodeSync(from: qrUrl) {
                            qrImage.draw(in: CGRect(
                                x: x + (colWidth - qrSize) / 2,
                                y: y + 46,
                                width: qrSize,
                                height: qrSize
                            ))
                        }

                        let linkAttrs: [NSAttributedString.Key: Any] = [
                            .font: UIFont.systemFont(ofSize: 7),
                            .foregroundColor: UIColor.gray
                        ]
                        let linkWidth = headerText.size(withAttributes: linkAttrs).width
                        headerText.draw(
                            at: CGPoint(x: x + (colWidth - linkWidth) / 2, y: y + rowHeight - 18),
                            withAttributes: linkAttrs
                        )
                    }

                    let footerText = "Page \(pageIndex + 1) of \(totalPages)"
                    let footerAttrs: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 8),
                        .foregroundColor: UIColor.gray
                    ]
                    footerText.draw(
                        at: CGPoint(
                            x: 567.2 - footerText.size(withAttributes: footerAttrs).width,
                            y: 818
                        ),
                        withAttributes: footerAttrs
                    )
                }
            }
            return url
        } catch {
            printErrorMessage = error.localizedDescription
            showPrintError = true
            return nil
        }
    }

    /// AirPrint / system print dialog — must present from the topmost VC (fullScreenCover).
    private func printPDF() {
        guard let url = buildPDF() else { return }
        guard UIPrintInteractionController.isPrintingAvailable else {
            // Fall back to share sheet so the user can still AirPrint / save from there.
            sharePDFURL = url
            showShareSheet = true
            return
        }

        let controller = UIPrintInteractionController.shared
        let printInfo = UIPrintInfo(dictionary: nil)
        printInfo.outputType = .general
        printInfo.jobName = "AlphaPos Table QR Codes"
        controller.printInfo = printInfo
        controller.printingItem = url

        DispatchQueue.main.async {
            if let presenter = Self.topMostViewController() {
                controller.present(from: presenter.view.bounds, in: presenter.view, animated: true) { _, completed, error in
                    if let error {
                        self.printErrorMessage = error.localizedDescription
                        self.showPrintError = true
                    } else if !completed {
                        // User cancelled — no alert.
                    }
                }
            } else {
                // Ultimate fallback: share sheet (works via SwiftUI presentation).
                self.sharePDFURL = url
                self.showShareSheet = true
            }
        }
    }

    /// Share / export PDF via SwiftUI sheet (avoids presenting from root under fullScreenCover).
    private func sharePDF() {
        guard let url = buildPDF() else { return }
        sharePDFURL = url
        showShareSheet = true
    }

    /// Walk the presentation chain so alerts / print / share appear above fullScreenCover.
    private static func topMostViewController(
        base: UIViewController? = nil
    ) -> UIViewController? {
        let root: UIViewController? = {
            if let base { return base }
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let window = scenes
                .flatMap { $0.windows }
                .first(where: { $0.isKeyWindow })
                ?? scenes.first?.windows.first
            return window?.rootViewController
        }()

        if let nav = root as? UINavigationController {
            return topMostViewController(base: nav.visibleViewController ?? nav)
        }
        if let tab = root as? UITabBarController {
            return topMostViewController(base: tab.selectedViewController ?? tab)
        }
        if let presented = root?.presentedViewController {
            return topMostViewController(base: presented)
        }
        return root
    }
}

// MARK: - QR usage guide

private struct TableQRCodeGuideView: View {
    @EnvironmentObject private var lm: LocalizationManager
    @Environment(\.dismiss) private var dismiss

    private var isThai: Bool { lm.languageCode == "th" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    introCard

                    guideSection(
                        icon: "qrcode",
                        title: isThai ? "QR ประจำโต๊ะ ใช้ซ้ำได้" : "Permanent QR is reusable",
                        body: isThai
                            ? "พิมพ์ติดโต๊ะเพียงครั้งเดียวและใช้ได้ต่อเนื่อง QR จะไม่เปลี่ยนทุก 5 นาที การเปิดหรือปิดรอบลูกค้าก็ไม่ทำให้ภาพ QR เปลี่ยน"
                            : "Print it once and keep it on the table. The QR does not change every five minutes, and opening or closing a guest session does not change it."
                    )

                    guideSection(
                        icon: "clock.badge.checkmark",
                        title: isThai ? "5 นาทีคือเวลารอยืนยัน" : "Five minutes is the approval window",
                        body: isThai
                            ? "หลังลูกค้าสแกน ระบบส่งคำขอให้พนักงานยืนยันภายใน 5 นาที หากไม่ได้ยืนยัน คำขอจะหมดอายุ แต่ QR ใบเดิมยังสแกนใหม่ได้"
                            : "After a scan, staff have five minutes to approve the request. If it expires, the same printed QR can be scanned again."
                    )

                    guideSection(
                        icon: "iphone.gen3.radiowaves.left.and.right",
                        title: isThai ? "ใช้ได้หลายเครื่อง" : "Works on multiple devices",
                        body: isThai
                            ? "ลูกค้าหลายเครื่องสามารถสแกนโต๊ะเดียวกันได้ ระบบรวมเป็นคำขอรอดำเนินการหนึ่งรายการและใช้ Table Session เดียวกัน เพื่อไม่ให้ออเดอร์ของโต๊ะถูกแยก"
                            : "Multiple devices may scan the same table. They share one pending approval and one table session so the table's orders are not split."
                    )

                    guideSection(
                        icon: "arrow.triangle.2.circlepath",
                        title: isThai ? "QR จะเปลี่ยนเมื่อใด" : "When the QR changes",
                        body: isThai
                            ? "QR ประจำโต๊ะจะเปลี่ยนเฉพาะเมื่อผู้ดูแลสั่งเพิกถอนหรือสร้าง QR ใหม่จากการตั้งค่าโต๊ะ เหมาะสำหรับกรณี QR สูญหาย ถูกเผยแพร่ หรือไม่ต้องการให้ใบเดิมใช้งานต่อ"
                            : "A Permanent QR changes only when an administrator revokes or regenerates it in table settings—use this if a code is lost, exposed, or should no longer work."
                    )

                    guideSection(
                        icon: "person.crop.circle.badge.checkmark",
                        title: isThai ? "ขั้นตอนสำหรับพนักงาน" : "Staff workflow",
                        body: isThai
                            ? "1. ลูกค้าสแกน QR\n2. ตรวจสอบเลขโต๊ะและพื้นที่\n3. กดยืนยันคำขอภายใน 5 นาที\n4. รับออเดอร์ใน Table Session เดียวกัน\n5. เมื่อชำระเงินเสร็จ ให้เคลียร์โต๊ะตามปกติ"
                            : "1. Customer scans the QR\n2. Verify the table and area\n3. Approve within five minutes\n4. Receive orders in the shared table session\n5. Clear the table normally after payment"
                    )

                    qrModeComparison
                }
                .padding(16)
            }
            .background(Color.appBackground)
            .navigationTitle(isThai ? "คู่มือ QR Code โต๊ะ" : "Table QR guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(isThai ? "เสร็จสิ้น" : "Done") { dismiss() }
                }
            }
        }
    }

    private var introCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lightbulb.fill")
                .foregroundColor(.orange)
            Text(isThai
                 ? "เลือกชนิด QR ให้เหมาะกับการใช้งาน ก่อนพิมพ์และติดตั้งที่โต๊ะ"
                 : "Choose the QR type that matches your workflow before printing and placing it on a table.")
                .font(.subheadline)
                .foregroundColor(.textPrimary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func guideSection(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.appAccent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                Text(body)
                    .font(.subheadline)
                    .foregroundColor(.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.appBorderSubtle, lineWidth: 1))
    }

    private var qrModeComparison: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(isThai ? "เลือกแบบไหนดี" : "Which mode should I choose?")
                .font(.headline)
                .foregroundColor(.textPrimary)
            comparisonRow(
                title: isThai ? "QR ประจำโต๊ะ" : "Permanent QR",
                detail: isThai ? "ติดโต๊ะถาวร · ใช้ซ้ำ · รอพนักงานยืนยัน" : "Keep on table · reusable · staff approval"
            )
            Divider()
            comparisonRow(
                title: isThai ? "QR ตามรอบลูกค้า" : "Session QR",
                detail: isThai ? "ใช้เฉพาะรอบปัจจุบัน · หมดอายุเมื่อเคลียร์โต๊ะ" : "Current visit only · expires when table is cleared"
            )
        }
        .padding(14)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.appBorderSubtle, lineWidth: 1))
    }

    private func comparisonRow(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundColor(.textPrimary)
            Text(detail).font(.caption).foregroundColor(.textSecondary)
        }
    }
}

// MARK: - Section model

private struct QRSection: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let tables: [RestaurantTable]
}

private struct QRGridWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct QRCardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

private extension Int {
    func compare(_ other: Int) -> ComparisonResult {
        if self < other { return .orderedAscending }
        if self > other { return .orderedDescending }
        return .orderedSame
    }
}

/// Compact QR card for dense multi-column grids
struct TableQRCard: View {
    let table: RestaurantTable
    let qrImage: UIImage?
    let namespace: Namespace.ID
    let isZoomed: Bool
    var compact: Bool = false
    let action: () -> Void

    @AppStorage("qr_custom_store_name") private var qrCustomStoreName = "AlphaPos Restaurant"
    @AppStorage("qr_custom_header") private var qrCustomHeader = "Scan to Order"
    @AppStorage("qr_custom_color") private var qrCustomColor = "#111115"

    var body: some View {
        let qrSide: CGFloat = compact ? 96 : 120

        // Use ButtonStyle (not DragGesture) so ScrollView can own vertical pans.
        Button {
            APHaptic.trigger()
            action()
        } label: {
            VStack(spacing: compact ? 4 : 6) {
                Text(qrCustomStoreName)
                    .font(.system(size: compact ? 8 : 10, weight: .bold))
                    .foregroundColor(.textSecondary)
                    .lineLimit(1)

                Text(LocalizationManager.shared.t("table_number_template", table.tableNumber))
                    .font(compact ? .caption.weight(.bold) : .subheadline.weight(.bold))
                    .foregroundColor(Color(hex: qrCustomColor))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                if let zone = table.zone, !zone.isEmpty {
                    Text(zoneLabel(zone))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.textSecondary)
                        .lineLimit(1)
                }

                if let qrImage = qrImage {
                    Image(uiImage: qrImage)
                        .resizable()
                        .interpolation(.none)
                        .frame(width: qrSide, height: qrSide)
                        .matchedGeometryEffect(id: "qr_image_\(table.id)", in: namespace, isSource: !isZoomed)
                        .padding(compact ? 4 : 6)
                        .background(Color.white)
                        .cornerRadius(6)
                        .shadow(color: Color.black.opacity(0.06), radius: 2)
                } else {
                    ProgressView()
                        .frame(width: qrSide + 8, height: qrSide + 8)
                }

                Text(qrCustomHeader)
                    .font(.system(size: compact ? 8 : 10, weight: .semibold))
                    .foregroundColor(.textSecondary)
                    .lineLimit(1)
            }
            .padding(.vertical, compact ? 8 : 12)
            .padding(.horizontal, compact ? 6 : 8)
            .frame(maxWidth: .infinity)
            .background(Color.appSurface)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.appBorderSubtle, lineWidth: 1)
            )
            .matchedGeometryEffect(id: "card_container_\(table.id)", in: namespace, isSource: !isZoomed)
            // Keep source card nearly invisible during zoom; never gate on entrance
            // animation — LazyVGrid often skipped delayed opacity reveals and left a blank grid.
            .opacity(isZoomed ? 0.01 : 1.0)
        }
        .buttonStyle(QRCardPressStyle())
    }

    private func zoneLabel(_ zone: String) -> String {
        switch zone.lowercased() {
        case "indoor": return "table_zone_indoor".t
        case "outdoor": return "table_zone_outdoor".t
        case "rooftop", "roof": return "table_zone_rooftop".t
        default: return zone
        }
    }
}
