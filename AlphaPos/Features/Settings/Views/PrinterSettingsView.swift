import SwiftUI
import SwiftData
import CoreImage
import Combine
#if canImport(StarIO10)
import StarIO10
#endif

struct PrinterSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var sessionManager: AppSessionManager

    // Printer settings
    @AppStorage("receipt_printer_enabled") private var receiptPrinterEnabled = true
    @AppStorage("kitchen_printer_enabled") private var kitchenPrinterEnabled = true
    @AppStorage("split_kitchen_print_by_category") private var splitKitchenPrintByCategory = true
    @AppStorage("printer_ip") private var printerIP = "192.168.1.201"
    // ── Shift auto-print toggles ──────────────────────────────────────────
    @AppStorage("print_open_shift")  private var printOpenShift  = false
    @AppStorage("print_close_shift") private var printCloseShift = true
    @AppStorage("auto_print_receipt_on_payment") private var autoPrintReceipt = true
    @AppStorage("auto_open_cash_drawer_on_cash_payment") private var autoOpenCashDrawerOnCashPayment = true
    @AppStorage("require_manager_override_for_drawer_test") private var requireManagerOverrideForDrawerTest = true
    // ── Remote receipt station (Staff iPhone → this iPad prints) ──────────
    @AppStorage("remote_receipt_print_enabled") private var remoteReceiptPrintEnabled = false
    @AppStorage("remote_kitchen_print_enabled") private var remoteKitchenPrintEnabled = true
    // ── Single-printer fallback (testing / broken station printer) ────────
    @AppStorage("single_printer_mode")    private var singlePrinterMode    = false
    @AppStorage("printer_role_fallback")  private var printerRoleFallback  = false
    @AppStorage("enable_table_system")    private var enableTableSystem    = true

    // ── Receipt behavior & content ───────────────────────────────────────
    @AppStorage("disable_receipt_printing") private var disableReceiptPrinting = false
    @AppStorage("show_logo_on_receipt")     private var showLogoOnReceipt     = true
    @Query(filter: #Predicate<Printer> { !$0.isDeleted }, sort: \Printer.name) private var printersList: [Printer]
    @Query(sort: \Category.name) private var appCategories: [Category]

    @State private var showingAddPrinterSheet = false
    @State private var selectedPrinterForEdit: Printer? = nil
    @State private var selectedPrintJobsForEdit = Set<String>()
    @State private var printerToDelete: Printer? = nil
    @State private var showDeleteRowConfirm = false

    // Form fields for adding/editing printer
    @State private var printerName = ""
    @State private var connectionType = "network" // network, bluetooth, usb
    @State private var ipAddress = ""
    @State private var portString = "9100"
    @State private var bluetoothName = ""
    @State private var paperWidth = "80mm" // 80mm, 58mm, 40mm Sticker
    @State private var printerRole = "kitchen" // receipt, kitchen, label
    @State private var selectedCategoriesForRouting = Set<String>() // Set of Category names/IDs

    // Print preview simulation state
    @State private var showingPreviewSheet = false
    @State private var selectedPrinterForPreview: Printer? = nil
    @State private var selectedPrintJobsForPreview = Set<String>()

    // Alert state for print simulation
    @State private var showingPrintAlert = false
    @State private var printAlertMessage = ""
    @State private var isTestingPrint = false
    @State private var isCheckingConnectivity = false
    @State private var showDrawerTestPINSheet = false

    // Auto-discovery
    @State private var showingDiscoverySheet = false
    @StateObject private var discovery = BonjourPrinterDiscovery()
    @State private var pendingDiscovered: DiscoveredPrinter? = nil

    /// Bridges PrinterConfigSheet's existing Boolean dismissal API to the
    /// item-driven edit sheet. Clearing the selected item dismisses the sheet
    /// and also prevents a future presentation from rendering an empty body.
    private var editSheetPresentationBinding: Binding<Bool> {
        Binding(
            get: { selectedPrinterForEdit != nil },
            set: { isPresented in
                if !isPresented {
                    selectedPrinterForEdit = nil
                }
            }
        )
    }

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        // ── Section header ────────────────────────────────
                        Text(L.Sections.printer.t)
                            .font(.system(size: 12))
                            .fontWeight(.bold)
                            .foregroundColor(.appAccent)
                            .tracking(1.0)

                        // ── Primary actions: Discover + Add ───────────────
                        HStack(spacing: 10) {
                            Button {
                                showingDiscoverySheet = true
                                discovery.start()
                            } label: {
                                Label("printer_discover_auto".t, systemImage: "dot.radiowaves.left.and.right")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 11)
                                    .background(APGradient.accent)
                                    .cornerRadius(10)
                            }
                            .buttonStyle(.plain)

                            Button {
                                printerName = ""
                                connectionType = "network"
                                ipAddress = ""
                                portString = "9100"
                                bluetoothName = ""
                                paperWidth = "80mm"
                                printerRole = "kitchen"
                                selectedCategoriesForRouting.removeAll()
                                selectedPrinterForEdit = nil
                                showingAddPrinterSheet = true
                            } label: {
                                Label("printer_add_manual".t, systemImage: "plus")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.appAccent)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 11)
                                    .background(Color.appAccent.opacity(0.10))
                                    .cornerRadius(10)
                                    .overlay(RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.appAccent.opacity(0.35), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }

                        // ── Secondary actions: Verify + Check Online ──────
                        if !printersList.filter({ !$0.isDeleted }).isEmpty {
                            HStack(spacing: 10) {
                                Button(action: runConnectivityCheck) {
                                    HStack(spacing: 5) {
                                        if isCheckingConnectivity {
                                            ProgressView().scaleEffect(0.7)
                                        } else {
                                            Image(systemName: "wifi")
                                        }
                                        Text("printer_check_connectivity".t)
                                    }
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(isCheckingConnectivity ? .textTertiary : .appTeal)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(Color.appTeal.opacity(0.08))
                                    .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                                .disabled(isCheckingConnectivity)

                                Button(action: requestHardwareVerification) {
                                    HStack(spacing: 5) {
                                        if isTestingPrint {
                                            ProgressView().scaleEffect(0.7)
                                        } else {
                                            Image(systemName: "checkmark.seal.fill")
                                        }
                                        Text("printer_test_all".t)
                                    }
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(isTestingPrint ? .textTertiary : .appAccent)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(Color.appAccent.opacity(0.08))
                                    .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                                .disabled(isTestingPrint)
                            }
                        }

                        VStack(spacing: 16) {
                            let activePrinters = printersList.filter { !$0.isDeleted }

                            let groups = groupedPrinters(activePrinters)

                            if groups.isEmpty {
                                VStack(spacing: 12) {
                                    Image(systemName: "printer.slash")
                                        .font(.system(size: 36))
                                        .foregroundColor(.textSecondary.opacity(0.5))
                                        .padding(.top, 8)
                                    Text("printer_empty_title".t)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.textPrimary)
                                    Text("printer_empty_desc".t)
                                        .font(.system(size: 12))
                                        .foregroundColor(.textSecondary)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 16)
                                        .padding(.bottom, 8)
                                }
                                .frame(maxWidth: .infinity)
                            } else {
                                ForEach(groups) { group in
                                    PrinterRowView(
                                        printer: group.printer,
                                        roles: group.roles,
                                        onPreview: {
                                            selectedPrinterForPreview = group.printer
                                            selectedPrintJobsForPreview = group.roles
                                            showingPreviewSheet = true
                                        },
                                        onEdit: {
                                            selectedPrintJobsForEdit = group.roles
                                            printerName = group.printer.name
                                            connectionType = group.printer.connectionType
                                            ipAddress = group.printer.ipAddress ?? ""
                                            portString = String(group.printer.port)
                                            bluetoothName = group.printer.bluetoothName ?? ""
                                            paperWidth = group.printer.paperWidth
                                            printerRole = group.printer.role

                                            selectedCategoriesForRouting = group.categories
                                            // Assign the sheet item last. This guarantees all
                                            // supporting edit state is ready before SwiftUI builds
                                            // PrinterConfigSheet on the same render pass.
                                            selectedPrinterForEdit = group.printer
                                        },
                                        onDelete: {
                                            printerToDelete = group.printer
                                            showDeleteRowConfirm = true
                                        }
                                    )

                                    if group.id != groups.last?.id {
                                        Divider()
                                            .background(Color.appDivider)
                                    }
                                }
                            }
                        }
                        .apCard()
                    }
                    .padding(.horizontal)

                    // ══ RECEIPT SETTINGS ═══════════════════════════════════
                    printSettingsGroup(titleKey: "printer_receipt_group".t) {
                        printToggleRow(
                            icon: "printer.fill", tint: .appAccent,
                            title: "printer_receipt_enabled_title".t,
                            subtitle: "printer_receipt_enabled_desc".t,
                            isOn: $receiptPrinterEnabled)

                        printDivider

                        printToggleRow(
                            icon: "fork.knife", tint: .appTeal,
                            title: "printer_kitchen_enabled_title".t,
                            subtitle: "printer_kitchen_enabled_desc".t,
                            isOn: $kitchenPrinterEnabled)

                        printDivider

                        printToggleRow(
                            icon: "rectangle.3.group", tint: .appAmber,
                            title: "printer_split_kitchen_title".t,
                            subtitle: "printer_split_kitchen_desc".t,
                            isOn: $splitKitchenPrintByCategory)

                        printDivider

                        printToggleRow(
                            icon: "nosign", tint: .appRose,
                            title: "printer_disable_receipt_title".t,
                            subtitle: "printer_disable_receipt_desc".t,
                            isOn: $disableReceiptPrinting)

                        printDivider

                        printToggleRow(
                            icon: "printer.dotmatrix.fill", tint: .appAccent,
                            title: "printer_auto_print_title".t,
                            subtitle: "printer_auto_print_desc".t,
                            isOn: $autoPrintReceipt)

                        printDivider

                        printToggleRow(
                            icon: "archivebox.fill", tint: .appAmber,
                            title: "printer_auto_open_drawer_title".t,
                            subtitle: "printer_auto_open_drawer_desc".t,
                            isOn: $autoOpenCashDrawerOnCashPayment)

                        printDivider

                        printToggleRow(
                            icon: "photo.fill", tint: .appTeal,
                            title: "printer_show_logo_title".t,
                            subtitle: "printer_show_logo_desc".t,
                            isOn: $showLogoOnReceipt)

                    }

                    // ══ SHIFT PRINTING ═════════════════════════════════════
                    printSettingsGroup(titleKey: "printer_shift_group".t) {
                        printToggleRow(
                            icon: "lock.open.fill", tint: .appTeal,
                            title: "printer_open_shift_title".t,
                            subtitle: "printer_open_shift_desc".t,
                            isOn: $printOpenShift)

                        printDivider

                        printToggleRow(
                            icon: "lock.fill", tint: .appRose,
                            title: "printer_close_shift_title".t,
                            subtitle: "printer_close_shift_desc".t,
                            isOn: $printCloseShift)
                    }

                    // ══ REMOTE PRINT STATION ═══════════════════════════════
                    printSettingsGroup(titleKey: "printer_remote_group".t) {
                        printToggleRow(
                            icon: "flame.fill", tint: .appTeal,
                            title: "printer_remote_kitchen_title".t,
                            subtitle: "printer_remote_kitchen_desc".t,
                            isOn: $remoteKitchenPrintEnabled)

                        printDivider

                        printToggleRow(
                            icon: "iphone.and.arrow.forward", tint: .appAmber,
                            title: "printer_remote_receipt_title".t,
                            subtitle: "printer_remote_receipt_desc".t,
                            isOn: $remoteReceiptPrintEnabled)
                    }

                    // ══ SINGLE-PRINTER MODE ════════════════════════════════
                    printSettingsGroup(titleKey: "printer_single_group_title".t) {
                        printToggleRow(
                            icon: "printer.fill", tint: .appAccent,
                            title: "printer_single_mode_title".t,
                            subtitle: "printer_single_mode_subtitle".t,
                            isOn: $singlePrinterMode)

                        printDivider

                        printToggleRow(
                            icon: "arrow.uturn.down.circle.fill", tint: .appAmber,
                            title: "printer_fallback_title".t,
                            subtitle: "printer_fallback_subtitle".t,
                            isOn: $printerRoleFallback)
                    }
                }
                .padding(.vertical)
            }
        }
        .navigationTitle(L.Sections.printer.t)
        .navigationBarTitleDisplayMode(.inline)
        .apNavBar(background: Color.appBackground)
        .sheet(isPresented: $showDrawerTestPINSheet) {
            ManagerPINVerificationSheet(isPresented: $showDrawerTestPINSheet) {
                runHardwareVerification()
            }
        }
        .alert("Printer Connection Test", isPresented: $showingPrintAlert) {
            Button("done".t, role: .cancel) { }
        } message: {
            Text(printAlertMessage)
        }
        .sheet(isPresented: $showingAddPrinterSheet) {
            PrinterConfigSheet(
                isPresented: $showingAddPrinterSheet,
                printerToEdit: nil,
                prefillName: pendingDiscovered?.name,
                prefillHost: pendingDiscovered?.host,
                prefillPort: pendingDiscovered?.port.map { Int($0) },
                prefillEmulation: pendingDiscovered?.inferredBrand?.rawValue,
                initialRoles: ["receipt", "kitchen"],
                initialCategories: [],
                onSave: savePrinterAction,
                appCategories: appCategories
            )
            .onDisappear { pendingDiscovered = nil }
        }
        .sheet(item: $selectedPrinterForEdit) { printer in
            PrinterConfigSheet(
                isPresented: editSheetPresentationBinding,
                printerToEdit: printer,
                initialRoles: selectedPrintJobsForEdit,
                initialCategories: selectedCategoriesForRouting,
                onSave: savePrinterAction,
                onDelete: deletePrinterAction,
                appCategories: appCategories
            )
            .id(printer.id)
        }
        .sheet(isPresented: $showingPreviewSheet) {
            if let printer = selectedPrinterForPreview {
                PrintPreviewSheet(
                    isPresented: $showingPreviewSheet,
                    printer: printer,
                    availableJobs: selectedPrintJobsForPreview
                )
            }
        }
        .sheet(isPresented: $showingDiscoverySheet, onDismiss: { discovery.stop() }) {
            PrinterDiscoverySheet(
                isPresented: $showingDiscoverySheet,
                discovery: discovery,
                onAdd: { discovered in
                    addDiscoveredPrinter(discovered)
                }
            )
        }
        .confirmationDialog(
            LocalizationManager.shared.currentLanguage == .thai ? "ยืนยันการลบเครื่องพิมพ์" : "Delete Printer",
            isPresented: $showDeleteRowConfirm,
            titleVisibility: .visible
        ) {
            Button(LocalizationManager.shared.currentLanguage == .thai ? "ลบเครื่องพิมพ์" : "Delete Printer", role: .destructive) {
                if let p = printerToDelete {
                    _ = deletePrinterAction(id: p.id)
                    printerToDelete = nil
                }
            }
            Button("cancel".t, role: .cancel) {
                printerToDelete = nil
            }
        } message: {
            Text(LocalizationManager.shared.currentLanguage == .thai
                ? "คุณแน่ใจหรือไม่ว่าต้องการลบการเชื่อมต่อเครื่องพิมพ์นี้?"
                : "Are you sure you want to delete this printer connection?")
        }
        .onDisappear {
            UserDefaults.standard.set(true, forKey: "printer_preferences_dirty")
            Task { await SyncEngine.shared.syncAll(modelContext: modelContext) }
        }
    }

    /// Hardware verification kicks the cash drawer — optionally require manager PIN first.
    private func requestHardwareVerification() {
        let groups = groupedPrinters(printersList.filter { !$0.isDeleted && $0.isActive })
        let willKickDrawer = groups.contains { $0.roles.contains("receipt") }
        if willKickDrawer,
           requireManagerOverrideForDrawerTest,
           !sessionManager.can(.managerOverride) {
            showDrawerTestPINSheet = true
            return
        }
        runHardwareVerification()
    }

    private func runHardwareVerification() {
        let groups = groupedPrinters(printersList.filter { !$0.isDeleted && $0.isActive })
        guard !groups.isEmpty else {
            printAlertMessage = "No active printers configured. Add and activate at least one printer first."
            showingPrintAlert = true
            return
        }

        isTestingPrint = true
        Task {
            var lines: [String] = ["Production Hardware Verification"]
            let roles = Set(groups.flatMap(\.roles))
            var drawerKickCount = 0

            for group in groups {
                for role in group.roles.sorted(by: roleSort) {
                    let printer = printerRecord(in: group, role: role)
                    let result = await PrintService.shared.printTest(to: printer, previewType: role)
                    lines.append("\(result.success ? "PASS" : "FAIL") \(hardwareRoleLabel(role)): \(printer.name)")
                    if let detail = result.log.last {
                        lines.append("  \(detail)")
                    }
                }

                if group.roles.contains("receipt") {
                    let printer = printerRecord(in: group, role: "receipt")
                    let drawer = await PrintService.shared.testCashDrawer(to: printer)
                    drawerKickCount += 1
                    lines.append("\(drawer.success ? "PASS" : "FAIL") Cash Drawer: \(printer.name)")
                    if let detail = drawer.log.last {
                        lines.append("  \(detail)")
                    }
                }
            }

            if drawerKickCount > 0 {
                await MainActor.run {
                    logDrawerTestAudit(success: true, detail: "Hardware verification kicked \(drawerKickCount) drawer route(s)")
                }
            }

            if !roles.contains("kitchen") {
                lines.append("MISSING Kitchen printer")
            }
            if !roles.contains("bar") && !roles.contains("label") {
                lines.append("MISSING Bar or label printer")
            }
            if !roles.contains("receipt") {
                lines.append("MISSING Receipt printer / cash drawer route")
            }

            printAlertMessage = lines.joined(separator: "\n")
            isTestingPrint = false
            showingPrintAlert = true
        }
    }

    /// Checks whether each active printer is reachable on the network WITHOUT
    /// emitting paper. Uses a standards-compliant TCP reachability probe so it
    /// works for ANY network printer supported on iPad/iPhone.
    private func runConnectivityCheck() {
        let groups = groupedPrinters(printersList.filter { !$0.isDeleted && $0.isActive })
        guard !groups.isEmpty else {
            printAlertMessage = "No active printers configured. Add and activate at least one printer first."
            showingPrintAlert = true
            return
        }

        isCheckingConnectivity = true
        Task {
            var lines: [String] = ["Printer Connectivity Check"]
            for group in groups {
                let printer = group.printer
                let result = await PrintService.shared.probeConnectivity(to: printer)
                let status = result.success ? "ONLINE" : "OFFLINE"
                let jobs = group.roles.sorted(by: roleSort).map(hardwareRoleLabel).joined(separator: ", ")
                lines.append("\(status) \(printer.name) [\(printer.connectionType.uppercased())] — \(jobs)")
                if let detail = result.log.last(where: { $0.hasPrefix("✓") || $0.hasPrefix("✗") }) ?? result.log.last {
                    lines.append("  \(detail)")
                }
            }
            printAlertMessage = lines.joined(separator: "\n")
            isCheckingConnectivity = false
            showingPrintAlert = true
        }
    }

    private func logDrawerTestAudit(success: Bool, detail: String) {
        let staffEmployeeId = sessionManager.currentStaffSession?.employeeId
        let audit = AuditLog(
            employeeId: staffEmployeeId,
            actionType: "cash_drawer_test",
            details: detail,
            originalValue: success ? 1 : 0,
            newValue: 0
        )
        modelContext.insert(audit)
        modelContext.saveWithLogging(label: #function)
    }

    private func hardwareRoleLabel(_ role: String) -> String {
        switch role {
        case "receipt": return "Receipt"
        case "kitchen": return "Kitchen"
        case "bar": return "Bar"
        case "label", "sticker": return "Label"
        default: return role.capitalized
        }
    }

    private func roleSort(_ lhs: String, _ rhs: String) -> Bool {
        roleSortIndex(lhs) < roleSortIndex(rhs)
    }

    /// Pre-fills the Add Printer form from a Bonjour-discovered printer, so the
    /// user only needs to confirm role/paper and save.
    private func addDiscoveredPrinter(_ discovered: DiscoveredPrinter) {
        showingDiscoverySheet = false
        discovery.stop()
        selectedPrinterForEdit = nil
        pendingDiscovered = discovered

        // Open the config sheet pre-filled so the user reviews before saving.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            showingAddPrinterSheet = true
        }
    }

    private func savePrinterAction(
        id: UUID?,
        name: String,
        connectionType: String,
        ipAddress: String?,
        port: Int,
        bluetoothName: String?,
        paperWidth: String,
        roles: Set<String>,
        isActive: Bool,
        emulation: String,
        selectedCategories: Set<String>,
        typography: PrintTypographyProfile
    ) -> Bool {
        let selectedRoles: Set<String> = roles.isEmpty ? Set(["receipt"]) : roles
        let existingGroup = id.flatMap { existingPrinterGroup(for: $0) } ?? []
        let destinationKey = physicalPrinterKey(
            connectionType: connectionType,
            ipAddress: ipAddress,
            port: port,
            bluetoothName: bluetoothName,
            paperWidth: paperWidth,
            emulation: emulation
        )

        // A logical prep station must have exactly one physical destination.
        // When an operator assigns Kitchen/Bar/Label to a new printer, make the
        // new selection authoritative and retire the same role from every other
        // physical printer. This prevents duplicate tickets without stopping a
        // single physical printer from owning receipt + kitchen + bar together.
        let exclusivePrepRoles = selectedRoles.intersection(["kitchen", "bar", "label"])
        for otherPrinter in printersList where
            !otherPrinter.isDeleted
                && exclusivePrepRoles.contains(otherPrinter.role)
                && physicalPrinterKey(otherPrinter) != destinationKey {
            otherPrinter.isDeleted = true
            otherPrinter.isSynced = false
            otherPrinter.updatedAt = Date()
            for rule in otherPrinter.routingRules {
                rule.isDeleted = true
                rule.isSynced = false
                rule.updatedAt = Date()
            }
        }

        for oldPrinter in existingGroup where !selectedRoles.contains(oldPrinter.role) {
            oldPrinter.isDeleted = true
            oldPrinter.isSynced = false
            oldPrinter.updatedAt = Date()
            for rule in oldPrinter.routingRules {
                rule.isDeleted = true
                rule.isSynced = false
                rule.updatedAt = Date()
            }
        }

        for role in selectedRoles {
            let printer: Printer
            if let existing = existingGroup.first(where: { $0.role == role }) ?? matchingPrinter(name: name, connectionType: connectionType, ipAddress: ipAddress, port: port, bluetoothName: bluetoothName, paperWidth: paperWidth, emulation: emulation, role: role) {
                printer = existing
                printer.isDeleted = false
                printer.name = name
                printer.connectionType = connectionType
                printer.ipAddress = ipAddress
                printer.port = port
                printer.bluetoothName = bluetoothName
                printer.paperWidth = paperWidth
                if printer.calibrationStatus != "verified" {
                    printer.printableWidthDots = paperWidth == "58mm" ? 384 : 576
                    printer.charactersPerLine = paperWidth == "58mm" ? 32 : 42
                    printer.qrModuleSize = paperWidth == "58mm" ? 5 : 7
                }
                printer.role = role
                printer.typographyProfile = typography
                printer.isActive = isActive
                printer.emulation = emulation
                printer.isSynced = false
                printer.updatedAt = Date()
            } else {
                printer = Printer(
                    name: name,
                    connectionType: connectionType,
                    ipAddress: ipAddress,
                    port: port,
                    bluetoothName: bluetoothName,
                    paperWidth: paperWidth,
                    status: existingGroup.first?.status ?? "unknown",
                    role: role,
                    isActive: isActive,
                    emulation: emulation,
                    isSynced: false,
                    isDeleted: false,
                    updatedAt: Date()
                )
                printer.typographyProfile = typography
                modelContext.insert(printer)
            }

            // Remove existing routing rules (soft delete)
            for rule in printer.routingRules {
                rule.isDeleted = true
                rule.isSynced = false
                rule.updatedAt = Date()
            }

            // Add new rules to prep printers only. Receipt prints are not category-routed.
            if role != "receipt" {
                for categoryName in selectedCategories {
                    let slug = categoryName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                    if let existingRule = printer.routingRules.first(where: { $0.categoryId == slug }) {
                        existingRule.isDeleted = false
                        existingRule.printOnOrder = enableTableSystem
                        existingRule.printOnPayment = !enableTableSystem
                        existingRule.isSynced = false
                        existingRule.updatedAt = Date()
                    } else {
                        let rule = PrintRoutingRule(
                            printer: printer,
                            categoryId: slug,
                            printOnOrder: enableTableSystem,
                            printOnPayment: !enableTableSystem,
                            isSynced: false,
                            isDeleted: false,
                            updatedAt: Date()
                        )
                        modelContext.insert(rule)
                        printer.routingRules.append(rule)
                    }
                }
            }
        }

        guard modelContext.saveWithLogging(label: #function) else { return false }
        syncKDSRoutingFromPrinters()

        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
        return true
    }

    private func deletePrinterAction(id: UUID) -> Bool {
        var targets = existingPrinterGroup(for: id)
        if targets.isEmpty, let direct = printersList.first(where: { $0.id == id }) {
            targets = [direct]
        }
        guard !targets.isEmpty else { return false }

        for printer in targets {
            printer.isDeleted = true
            printer.isActive = false
            printer.isSynced = false
            printer.updatedAt = Date()

            for rule in printer.routingRules {
                rule.isDeleted = true
                rule.isSynced = false
                rule.updatedAt = Date()
            }
        }

        guard modelContext.saveWithLogging(label: #function) else { return false }
        syncKDSRoutingFromPrinters()

        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
        return true
    }

    private func groupedPrinters(_ printers: [Printer]) -> [PrinterGroup] {
        var groups: [String: [Printer]] = [:]
        for printer in printers {
            groups[physicalPrinterKey(printer), default: []].append(printer)
        }
        return groups.values.map { members in
            let sorted = members.sorted { roleSortIndex($0.role) < roleSortIndex($1.role) }
            let categories = Set(members.flatMap { printer in
                printer.routingRules.filter { !$0.isDeleted }.compactMap { $0.categoryId }
            })
            return PrinterGroup(printer: sorted[0], members: sorted, roles: Set(members.map(\.role)), categories: categories)
        }
        .sorted { $0.printer.name.localizedCaseInsensitiveCompare($1.printer.name) == .orderedAscending }
    }

    private func printerRecord(in group: PrinterGroup, role: String) -> Printer {
        group.members.first { $0.role == role } ?? group.printer
    }

    private func existingPrinterGroup(for id: UUID) -> [Printer] {
        let allPrinters = (try? modelContext.fetch(FetchDescriptor<Printer>())) ?? printersList
        guard let selected = allPrinters.first(where: { $0.id == id }) else { return [] }
        let key = physicalPrinterKey(selected)
        var matched = allPrinters.filter { physicalPrinterKey($0) == key }
        if !matched.contains(where: { $0.id == id }) {
            matched.append(selected)
        }
        return matched
    }

    private func matchingPrinter(name: String, connectionType: String, ipAddress: String?, port: Int, bluetoothName: String?, paperWidth: String, emulation: String, role: String) -> Printer? {
        let allPrinters = (try? modelContext.fetch(FetchDescriptor<Printer>())) ?? printersList
        return allPrinters.first {
            $0.role == role
                && physicalPrinterKey($0) == physicalPrinterKey(connectionType: connectionType, ipAddress: ipAddress, port: port, bluetoothName: bluetoothName, paperWidth: paperWidth, emulation: emulation)
                && $0.name == name
        }
    }

    private func physicalPrinterKey(_ printer: Printer) -> String {
        physicalPrinterKey(
            connectionType: printer.connectionType,
            ipAddress: printer.ipAddress,
            port: printer.port,
            bluetoothName: printer.bluetoothName,
            paperWidth: printer.paperWidth,
            emulation: printer.emulation
        )
    }

    private func physicalPrinterKey(connectionType: String, ipAddress: String?, port: Int, bluetoothName: String?, paperWidth: String, emulation: String) -> String {
        switch connectionType {
        case "network": return "network|\(ipAddress ?? "")|\(port)"
        case "bluetooth": return "bluetooth|\(bluetoothName ?? "")"
        case "usb": return "usb|\(emulation)|\(paperWidth)"
        default: return "\(connectionType)|\(ipAddress ?? bluetoothName ?? "")"
        }
    }

    private func roleSortIndex(_ role: String) -> Int {
        ["receipt", "kitchen", "bar", "label"].firstIndex(of: role) ?? 99
    }

    private func syncKDSRoutingFromPrinters() {
        var routing: [String: Set<String>] = [:]
        let existingRaw = UserDefaults.standard.string(forKey: "kds_category_routing_json") ?? "{}"
        let defaultRoute = (try? JSONDecoder().decode([String: String].self, from: Data(existingRaw.utf8)))?["*"]
        for printer in printersList where !printer.isDeleted && printer.isActive {
            let station: String?
            switch printer.role {
            case "kitchen":
                station = "kitchen"
            case "bar", "label", "sticker":
                station = "bar"
            default:
                station = nil
            }
            guard let station else { continue }

            for rule in printer.routingRules where !rule.isDeleted {
                guard let category = rule.categoryId else { continue }
                routing[category, default: []].insert(station)
            }
        }

        let encoded = routing.mapValues { stations -> String in
            stations.contains("kitchen") && stations.contains("bar") ? "both" : (stations.first ?? "kitchen")
        }
        var updated = encoded
        // Do not manufacture a wildcard kitchen route. With no explicit
        // wildcard, OrderRoutingResolver can classify food vs beverage names
        // and the Bar role on a shared physical printer receives drink items.
        // Preserve a wildcard only when the operator already configured one in
        // KDS settings.
        if let defaultRoute {
            updated["*"] = defaultRoute
        }
        if let data = try? JSONEncoder().encode(updated),
           let json = String(data: data, encoding: .utf8) {
            UserDefaults.standard.set(json, forKey: "kds_category_routing_json")
        }
    }

    // ── Reusable settings UI ─────────────────────────────────────────────
    /// A titled card that groups related print-setting rows together.
    @ViewBuilder
    private func printSettingsGroup<Content: View>(
        titleKey: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(titleKey)
                .font(.system(size: 12))
                .fontWeight(.bold)
                .foregroundColor(.appAccent)
                .tracking(1.0)

            VStack(spacing: 0) { content() }
                .apCard()
        }
        .padding(.horizontal)
    }

    /// A single toggle row with a leading icon, title and subtitle.
    @ViewBuilder
    private func printToggleRow(
        icon: String,
        tint: Color,
        title: String,
        subtitle: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12)).foregroundColor(.textPrimary)
                Text(subtitle)
                    .font(.system(size: 12)).foregroundColor(.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(tint)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
    }

    /// Standard inset divider between two toggle rows.
    private var printDivider: some View {
        Divider().background(Color.appDivider).padding(.leading, 58)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - PrinterConfigSheet
// ─────────────────────────────────────────────────────────────────────────────
struct PrinterConfigSheet: View {
    @Binding var isPresented: Bool
    var printerToEdit: Printer?
    // Optional pre-fill values (used when adding a printer discovered via Bonjour)
    var prefillName: String? = nil
    var prefillHost: String? = nil
    var prefillPort: Int? = nil
    var prefillEmulation: String? = nil
    var initialRoles: Set<String> = ["receipt"]
    var initialCategories: Set<String> = []
    var onSave: (UUID?, String, String, String?, Int, String?, String, Set<String>, Bool, String, Set<String>, PrintTypographyProfile) -> Bool
    var onDelete: ((UUID) -> Bool)? = nil
    var appCategories: [Category]

    @State private var name: String
    @State private var connectionType: String
    @State private var ipAddress: String
    @State private var portString: String
    @State private var bluetoothName: String
    @State private var paperWidth: String
    @State private var selectedJobs: Set<String>
    @State private var isActive: Bool
    @State private var emulation: String
    @State private var selectedCategories: Set<String>
    @State private var bodyScale: Int
    @State private var emphasisScale: Int

    init(
        isPresented: Binding<Bool>,
        printerToEdit: Printer? = nil,
        prefillName: String? = nil,
        prefillHost: String? = nil,
        prefillPort: Int? = nil,
        prefillEmulation: String? = nil,
        initialRoles: Set<String> = ["receipt"],
        initialCategories: Set<String> = [],
        onSave: @escaping (UUID?, String, String, String?, Int, String?, String, Set<String>, Bool, String, Set<String>, PrintTypographyProfile) -> Bool,
        onDelete: ((UUID) -> Bool)? = nil,
        appCategories: [Category]
    ) {
        self._isPresented = isPresented
        self.printerToEdit = printerToEdit
        self.prefillName = prefillName
        self.prefillHost = prefillHost
        self.prefillPort = prefillPort
        self.prefillEmulation = prefillEmulation
        self.initialRoles = initialRoles
        self.initialCategories = initialCategories
        self.onSave = onSave
        self.onDelete = onDelete
        self.appCategories = appCategories

        if let printer = printerToEdit {
            _name = State(initialValue: printer.name)
            _connectionType = State(initialValue: printer.connectionType)
            _ipAddress = State(initialValue: printer.ipAddress ?? "")
            _portString = State(initialValue: String(printer.port))
            _bluetoothName = State(initialValue: printer.bluetoothName ?? "")
            _paperWidth = State(initialValue: printer.paperWidth)
            _selectedJobs = State(initialValue: initialRoles.isEmpty ? [printer.role] : initialRoles)
            _isActive = State(initialValue: printer.isActive)
            _emulation = State(initialValue: printer.emulation)
            _selectedCategories = State(initialValue: initialCategories)
            _bodyScale = State(initialValue: printer.typographyProfile.body.scale)
            _emphasisScale = State(initialValue: printer.typographyProfile.emphasis.scale)
        } else {
            _name = State(initialValue: prefillName ?? "")
            _connectionType = State(initialValue: prefillHost != nil ? "network" : "network")
            _ipAddress = State(initialValue: prefillHost ?? "")
            _portString = State(initialValue: prefillPort.map(String.init) ?? "9100")
            _bluetoothName = State(initialValue: "")
            _paperWidth = State(initialValue: "80mm")
            _selectedJobs = State(initialValue: initialRoles.isEmpty ? ["receipt", "kitchen"] : initialRoles)
            _isActive = State(initialValue: true)
            _emulation = State(initialValue: prefillEmulation ?? "epson")
            _selectedCategories = State(initialValue: initialCategories)
            _bodyScale = State(initialValue: 1)
            _emphasisScale = State(initialValue: 2)
        }
    }

    @State private var showingValidationAlert = false
    @State private var validationMessage = ""

    @State private var isTesting = false
    @State private var showingTestResultAlert = false
    @State private var testResultMessage = ""

    // ── Phase 2: LAN reachability probe state ────────────────────────────
    @State private var isProbing = false
    @State private var probeResult: ConnectivityResult? = nil
    @State private var showingUnreachableConfirm = false
    @State private var unreachableDetail = ""
    @State private var showingDeleteConfirmation = false

    /// The brand backing the current emulation selection. Drives which
    /// interfaces are offered and the capability advice shown to the operator.
    private var currentBrand: PrinterBrand {
        PrinterBrand(rawValue: emulation.lowercased()) ?? .generic
    }

    /// The currently-selected interface as a capability enum (nil if the raw
    /// connectionType string is unrecognised).
    private var currentInterface: PrinterCapability.Interface? {
        PrinterCapability.Interface(rawValue: connectionType)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        identitySection
                        connectionSection
                        mediaSection
                        if hasPrepJobs {
                            routingSection
                        }
                        typographySection

                        // ── ACTIONS ──────────────────────────────────────────
                        VStack(spacing: 12) {
                            Button(action: validateAndSave) {
                                Text("save".t)
                            }
                            .apGradientButton(gradient: APGradient.accent)

                            Button(action: runTestPrint) {
                                HStack {
                                    if isTesting {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                            .padding(.trailing, 8)
                                    }
                                    Text(isTesting ? "Testing Connection..." : "Test Connection & Print")
                                        .fontWeight(.bold)
                                }
                            }
                            .disabled(isTesting)
                            .padding(.vertical, 8)

                            if let onDelete = onDelete, let _ = printerToEdit?.id {
                                Button(action: {
                                    showingDeleteConfirmation = true
                                }) {
                                    Text("delete".t)
                                        .foregroundColor(.appRose)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle(
                printerToEdit == nil
                    ? (LocalizationManager.shared.currentLanguage == .thai
                        ? "เพิ่มการเชื่อมต่อเครื่องพิมพ์"
                        : "Add Printer Connection")
                    : (LocalizationManager.shared.currentLanguage == .thai
                        ? "แก้ไขการเชื่อมต่อเครื่องพิมพ์"
                        : "Edit Printer Connection")
            )
            .apNavBar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel".t) { isPresented = false }
                        .foregroundColor(.textPrimary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("save".t) {
                        validateAndSave()
                    }
                    .fontWeight(.bold)
                    .foregroundColor(.appAccent)
                }
            }
            .onAppear {
                if let printer = printerToEdit {
                    name = printer.name
                    connectionType = printer.connectionType
                    ipAddress = printer.ipAddress ?? ""
                    portString = String(printer.port)
                    bluetoothName = printer.bluetoothName ?? ""
                    paperWidth = printer.paperWidth
                    selectedJobs = initialRoles.isEmpty ? [printer.role] : initialRoles
                    isActive = printer.isActive
                    emulation = printer.emulation

                    selectedCategories = initialCategories
                } else {
                    selectedJobs = initialRoles.isEmpty ? ["receipt"] : initialRoles
                    // Pre-fill from an auto-discovered printer (Bonjour)
                    if let n = prefillName { name = n }
                    // Auto-select the inferred brand so emulation + interface are
                    // correct before the operator even looks at the form.
                    if let e = prefillEmulation, !e.isEmpty { emulation = e }
                    if let h = prefillHost, !h.isEmpty {
                        connectionType = "network"
                        ipAddress = h
                    }
                    if let p = prefillPort { portString = String(p) }
                }
                // Ensure the interface is valid for the brand. Legacy data (or a
                // brand switch) may hold an interface iOS no longer allows.
                let brand = PrinterBrand(rawValue: emulation.lowercased()) ?? .generic
                if let iface = PrinterCapability.Interface(rawValue: connectionType),
                   PrinterCapability.support(brand: brand, over: iface) == .unsupported {
                    connectionType = PrinterCapability.recommendedInterface(for: brand).rawValue
                }
            }
            .alert("Configuration Error", isPresented: $showingValidationAlert) {
                Button("ok_btn".t, role: .cancel) { }
            } message: {
                Text(validationMessage)
            }
            .alert(isTesting ? "Testing Connection" : "Connection Test Result", isPresented: $showingTestResultAlert) {
                Button("ok_btn".t, role: .cancel) { }
            } message: {
                ScrollView {
                    Text(testResultMessage)
                        .font(.system(.caption, design: .monospaced))
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .onChange(of: emulation) { _, newValue in
                let brand = PrinterBrand(rawValue: newValue.lowercased()) ?? .generic
                // If the currently-selected interface is impossible for this
                // brand on iPad, fall back to the recommended (network) path.
                if let iface = PrinterCapability.Interface(rawValue: connectionType),
                   PrinterCapability.support(brand: brand, over: iface) == .unsupported {
                    connectionType = PrinterCapability.recommendedInterface(for: brand).rawValue
                }
                probeResult = nil
            }
            .onChange(of: connectionType) { _, _ in
                probeResult = nil
            }
            .confirmationDialog(
                "printer_unreachable_title".t,
                isPresented: $showingUnreachableConfirm,
                titleVisibility: .visible
            ) {
                Button("printer_save_anyway".t, role: .destructive) { performSave() }
                Button("cancel".t, role: .cancel) { }
            } message: {
                Text(unreachableDetail)
            }
            .confirmationDialog(
                LocalizationManager.shared.currentLanguage == .thai ? "ยืนยันการลบเครื่องพิมพ์" : "Delete Printer",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button(LocalizationManager.shared.currentLanguage == .thai ? "ลบเครื่องพิมพ์" : "Delete Printer", role: .destructive) {
                    if let printerId = printerToEdit?.id, let onDelete = onDelete {
                        if onDelete(printerId) {
                            isPresented = false
                        } else {
                            validationMessage = LocalizationManager.shared.currentLanguage == .thai
                                ? "ไม่สามารถลบเครื่องพิมพ์ได้ กรุณาลองใหม่อีกครั้ง"
                                : "Unable to delete printer. Please try again."
                            showingValidationAlert = true
                        }
                    }
                }
                Button("cancel".t, role: .cancel) { }
            } message: {
                Text(LocalizationManager.shared.currentLanguage == .thai
                    ? "คุณแน่ใจหรือไม่ว่าต้องการลบการเชื่อมต่อเครื่องพิมพ์นี้?"
                    : "Are you sure you want to delete this printer connection?")
            }
        }
    }

    private func runTestPrint() {
        let portInt = Int(portString.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 9100
        // Phase 2: exercise EVERY role assigned to this physical printer so a
        // multi-role station (e.g. kitchen + bar) is fully verified in one tap.
        let roles = selectedJobs.isEmpty ? ["receipt"] : selectedJobs.sorted(by: roleSort)

        let tempPrinter = Printer(
            name: name.isEmpty ? "Test Printer" : name,
            connectionType: connectionType,
            ipAddress: ipAddress.isEmpty ? nil : ipAddress,
            port: portInt,
            bluetoothName: bluetoothName.isEmpty ? nil : bluetoothName,
            paperWidth: paperWidth,
            role: roles.first ?? "receipt",
            isActive: isActive,
            emulation: emulation
        )

        isTesting = true
        Task {
            var lines: [String] = ["Test Print — \(tempPrinter.name)"]
            for role in roles {
                let result = await PrintService.shared.printTest(to: tempPrinter, previewType: role)
                result.log.forEach { print("[StarUSB Test] \($0)") }
                lines.append("")
                lines.append("\(result.success ? "PASS" : "FAIL") \(testRoleLabel(role))")
                if let detail = result.log.last(where: { $0.hasPrefix("✓") || $0.hasPrefix("✗") }) ?? result.log.last {
                    lines.append("  \(detail)")
                }
            }
            await MainActor.run {
                isTesting = false
                testResultMessage = lines.joined(separator: "\n")
                showingTestResultAlert = true
            }
        }
    }

    private func testRoleLabel(_ role: String) -> String {
        switch role {
        case "receipt": return "Receipt / Check"
        case "kitchen": return "Kitchen Ticket"
        case "bar": return "Bar Ticket"
        case "label", "sticker": return "Sticker Label"
        default: return role.capitalized
        }
    }

    private func validateAndSave() {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            validationMessage = "Please specify a printer name."
            showingValidationAlert = true
            return
        }

        if connectionType == "network" {
            let ipTrimmed = ipAddress.trimmingCharacters(in: .whitespacesAndNewlines)
            if ipTrimmed.isEmpty {
                validationMessage = "TCP/IP connection requires an IP address."
                showingValidationAlert = true
                return
            }

            let parts = ipTrimmed.split(separator: ".")
            if parts.count != 4 {
                validationMessage = "Invalid IP address format. (e.g. 192.168.1.100)"
                showingValidationAlert = true
                return
            }
        }

        if selectedJobs.isEmpty {
            validationMessage = "Please select at least one print job for this printer."
            showingValidationAlert = true
            return
        }

        // Phase 2: verify LAN reachability before committing a network printer.
        // We don't hard-block (the operator may configure ahead of powering the
        // printer on) — an unreachable host surfaces a confirmation instead.
        if connectionType == "network" {
            let host = ipAddress.trimmingCharacters(in: .whitespacesAndNewlines)
            let portInt = UInt16(clamping: Int(portString.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 9100)
            isProbing = true
            Task {
                let result = await TCPConnectivityProbe.probe(host: host, port: portInt, timeout: 2.5)
                await MainActor.run {
                    isProbing = false
                    probeResult = result
                    if result.isReachable {
                        performSave()
                    } else {
                        unreachableDetail = "\(result.detail)\n\nต้องการบันทึกการตั้งค่านี้ต่อไปหรือไม่?"
                        showingUnreachableConfirm = true
                    }
                }
            }
        } else {
            performSave()
        }
    }

    private func performSave() {
        let portInt = Int(portString.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 9100
        if onSave(
            printerToEdit?.id,
            name,
            connectionType,
            connectionType == "network" ? ipAddress : nil,
            portInt,
            (connectionType == "bluetooth" || connectionType == "usb") ? bluetoothName : nil,
            paperWidth,
            selectedJobs,
            isActive,
            emulation,
            selectedCategories,
            PrintTypographyProfile(
                header: .init(scale: selectedJobs.contains("kitchen") || selectedJobs.contains("bar") ? emphasisScale : 1, bold: true),
                metadata: .compact,
                body: .init(scale: bodyScale, bold: selectedJobs.contains("kitchen") || selectedJobs.contains("bar")),
                emphasis: .init(scale: emphasisScale, bold: true),
                footer: .compact
            )
        ) {
            isPresented = false
        } else {
            validationMessage = "Unable to save printer settings. Please try again."
            showingValidationAlert = true
        }
    }

    private func roleSort(_ lhs: String, _ rhs: String) -> Bool {
        let order = ["receipt", "kitchen", "bar", "label"]
        return (order.firstIndex(of: lhs) ?? 99) < (order.firstIndex(of: rhs) ?? 99)
    }

    private var hasPrepJobs: Bool {
        !selectedJobs.isDisjoint(with: ["kitchen", "bar", "label"])
    }

    @ViewBuilder
    private var typographySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Print Text Size")
                .font(.headline)
                .foregroundColor(.appAccent)
            Text("กำหนดขนาดแยกตามส่วน โดยระบบจะรักษาความกว้างของกระดาษ 58/80mm")
                .font(.footnote)
                .foregroundColor(.textSecondary)
            Picker("รายการสินค้า", selection: $bodyScale) {
                Text("ปกติ").tag(1)
                Text("ใหญ่").tag(2)
            }
            Picker("หัวเรื่อง / ยอดรวม", selection: $emphasisScale) {
                Text("ปกติ").tag(1)
                Text("ใหญ่").tag(2)
            }
            Button("Use Recommended Sizes") {
                let profile = PrintTypographyProfile.recommended(for: selectedJobs.first ?? "receipt", paperWidth: paperWidth)
                bodyScale = profile.body.scale
                emphasisScale = profile.emphasis.scale
            }
            .font(.footnote.weight(.semibold))
        }
        .apCard()
    }
}

// ── EXTENSION: COMPILER OPTIMIZATIONS ───────────────────────────────────────
extension PrinterConfigSheet {
    @ViewBuilder
    private var identitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("printer_identity_section".t)
                .font(.system(size: 12))
                .fontWeight(.bold)
                .foregroundColor(.appAccent)
                .tracking(1.0)

            VStack(alignment: .leading, spacing: 6) {
                Text("printer_brand_lbl".t)
                    .font(.system(size: 12))
                    .fontWeight(.bold)
                    .foregroundColor(.textSecondary)
                Picker("Emulation", selection: $emulation) {
                    ForEach(PrinterBrand.allCases) { brand in
                        Text(brand.displayName).tag(brand.rawValue)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .padding()
                .background(Color.appSurfaceHigh)
                .foregroundColor(.textPrimary)
                .cornerRadius(8)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("printer_name_lbl".t)
                    .font(.system(size: 12))
                    .fontWeight(.bold)
                    .foregroundColor(.textSecondary)
                TextField("e.g. Kitchen Printer, Main Cashier", text: $name)
                    .textFieldStyle(PlainTextFieldStyle())
                    .padding()
                    .background(Color.appSurfaceHigh)
                    .foregroundColor(.textPrimary)
                    .cornerRadius(8)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("printer_jobs_lbl".t)
                    .font(.system(size: 12))
                    .fontWeight(.bold)
                    .foregroundColor(.textSecondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190))], alignment: .leading, spacing: 10) {
                    printJobToggle("receipt", title: "printer_job_receipt".t, icon: "printer.fill", tint: .appAccent)
                    printJobToggle("kitchen", title: "printer_job_kitchen".t, icon: "fork.knife", tint: .appTeal)
                    printJobToggle("bar", title: "printer_job_bar".t, icon: "cup.and.saucer.fill", tint: .appAmber)
                    printJobToggle("label", title: "printer_job_label".t, icon: "tag.fill", tint: .appAmber)
                }
            }

            Toggle("printer_active_status".t, isOn: $isActive)
                .tint(.appAccent)
        }
        .apCard()
    }

    private func printJobToggle(_ value: String, title: String, icon: String, tint: Color) -> some View {
        let isSelected = selectedJobs.contains(value)
        return Button {
            if isSelected {
                selectedJobs.remove(value)
            } else {
                selectedJobs.insert(value)
            }
            APHaptic.trigger()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundColor(isSelected ? tint : .textTertiary)
                Image(systemName: icon)
                    .foregroundColor(tint)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(isSelected ? tint.opacity(0.10) : Color.appSurfaceHigh)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? tint.opacity(0.35) : Color.appBorderSubtle, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("printer_connection_section".t)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.appAccent)
                .tracking(1.0)

            // ── Connection type picker (capability-driven) ────────────────
            // Only interfaces that can actually work for this brand on
            // iPad/iPhone are offered; impossible paths are never shown so the
            // operator cannot pick a dead end.
            let interfaces = PrinterCapability.selectableInterfaces(for: currentBrand)
            Picker("Connection Type", selection: $connectionType) {
                ForEach(interfaces, id: \.self) { iface in
                    Text(interfaceLabel(iface)).tag(iface.rawValue)
                }
            }
            .pickerStyle(SegmentedPickerStyle())

            // ── Capability advice for the current (brand × interface) ──────
            if let iface = currentInterface {
                capabilityAdviceBanner(for: iface)
            }

            // ── USB: live accessory scanner ───────────────────────────────
            if connectionType == "usb" {
                USBAccessoryScannerView(selectedIdentifier: $bluetoothName)
            }

            // ── Network fields ────────────────────────────────────────────
            if connectionType == "network" {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("printer_ip_lbl".t)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.textSecondary)
                            TextField("192.168.1.X", text: $ipAddress)
                                .keyboardType(.numbersAndPunctuation)
                                .textFieldStyle(PlainTextFieldStyle())
                                .padding(10)
                                .background(Color.appSurfaceHigh)
                                .foregroundColor(.textPrimary)
                                .cornerRadius(8)
                        }
                        .frame(maxWidth: .infinity)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("printer_port_lbl".t)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.textSecondary)
                            TextField("9100", text: $portString)
                                .keyboardType(.numberPad)
                                .textFieldStyle(PlainTextFieldStyle())
                                .padding(10)
                                .background(Color.appSurfaceHigh)
                                .foregroundColor(.textPrimary)
                                .cornerRadius(8)
                        }
                        .frame(width: 80)
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.appAccent)
                            .font(.system(size: 12))
                        Text("printer_wifi_same_hint".t)
                            .font(.system(size: 12))
                            .foregroundColor(.textSecondary)
                    }

                    networkProbeRow
                }
            }

            // ── Bluetooth field ───────────────────────────────────────────
            if connectionType == "bluetooth" {
                VStack(alignment: .leading, spacing: 6) {
                    Text("printer_bt_name_lbl".t)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.textSecondary)
                    TextField("เช่น Star TSP100-B101", text: $bluetoothName)
                        .textFieldStyle(PlainTextFieldStyle())
                        .padding(10)
                        .background(Color.appSurfaceHigh)
                        .foregroundColor(.textPrimary)
                        .cornerRadius(8)
                    Text("printer_bt_pair_hint".t)
                        .font(.system(size: 12))
                        .foregroundColor(.textSecondary)
                }
            }
        }
        .apCard()
    }

    /// Human-readable label for a connection interface segment.
    private func interfaceLabel(_ iface: PrinterCapability.Interface) -> String {
        switch iface {
        case .network:   return "TCP/IP LAN"
        case .bluetooth: return "Bluetooth"
        case .usb:       return "USB Direct"
        }
    }

    /// Contextual advice for the selected brand × interface, color-coded by
    /// support level so the operator immediately sees whether the path is
    /// fully supported, MFi/SDK-gated, or a dead end.
    @ViewBuilder
    private func capabilityAdviceBanner(for iface: PrinterCapability.Interface) -> some View {
        let support = PrinterCapability.support(brand: currentBrand, over: iface)
        let advice = PrinterCapability.advice(brand: currentBrand, over: iface)
        let style = adviceStyle(for: support)
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: style.icon)
                .foregroundColor(style.tint)
                .font(.system(size: 12))
                .padding(.top, 1)
            Text(advice)
                .font(.system(size: 12))
                .foregroundColor(.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(style.tint.opacity(0.10))
        .cornerRadius(8)
    }

    private func adviceStyle(for support: PrinterCapability.Support) -> (icon: String, tint: Color) {
        switch support {
        case .supported:
            return ("checkmark.seal.fill", .appTeal)
        case .requiresMFi, .requiresSDK:
            return ("exclamationmark.triangle.fill", .appAmber)
        case .unsupported:
            return ("xmark.octagon.fill", .appRose)
        }
    }

    /// Inline LAN reachability probe — verifies host:port is live over a RAW
    /// TCP handshake WITHOUT emitting paper (standards-compliant "is it online").
    @ViewBuilder
    private var networkProbeRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: runProbe) {
                HStack(spacing: 6) {
                    if isProbing {
                        ProgressView().scaleEffect(0.7).tint(.appTeal)
                    } else {
                        Image(systemName: "wifi")
                    }
                    Text(isProbing ? "กำลังตรวจสอบ..." : "ตรวจสอบการเชื่อมต่อ")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundColor(.appTeal)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.appTeal.opacity(0.10))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .disabled(isProbing || ipAddress.trimmingCharacters(in: .whitespaces).isEmpty)

            if let result = probeResult {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: result.isReachable ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(result.isReachable ? .appTeal : .appRose)
                        .font(.system(size: 12))
                    Text(result.detail)
                        .font(.system(size: 12))
                        .foregroundColor(.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func runProbe() {
        let host = ipAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { return }
        let portRaw = Int(portString.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 9100
        let portInt = UInt16(clamping: portRaw)
        isProbing = true
        probeResult = nil
        Task {
            let result = await TCPConnectivityProbe.probe(host: host, port: portInt)
            await MainActor.run {
                probeResult = result
                isProbing = false
                APHaptic.trigger()
            }
        }
    }

    @ViewBuilder
    private var mediaSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("printer_media_section".t)
                .font(.system(size: 12))
                .fontWeight(.bold)
                .foregroundColor(.appAccent)
                .tracking(1.0)

            Picker("Paper Width", selection: $paperWidth) {
                Text("printer_paper_80".t).tag("80mm")
                Text("printer_paper_58".t).tag("58mm")
                Text("printer_paper_40_sticker".t).tag("40mm Sticker")
            }
            .pickerStyle(SegmentedPickerStyle())
        }
        .apCard()
    }

    @ViewBuilder
    private var routingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("printer_routing_section".t)
                .font(.system(size: 12))
                .fontWeight(.bold)
                .foregroundColor(.appAccent)
                .tracking(1.0)

            Text("printer_routing_desc".t)
                .font(.system(size: 12))
                .foregroundColor(.textSecondary)

            if appCategories.isEmpty {
                Text("printer_routing_empty".t)
                    .font(.system(size: 12))
                    .foregroundColor(.textSecondary)
                    .italic()
            } else {
                Button {
                    selectedCategories.removeAll()
                    APHaptic.trigger()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: selectedCategories.isEmpty ? "checkmark.square.fill" : "square")
                            .foregroundColor(selectedCategories.isEmpty ? .appAccent : .textTertiary)
                        Text("printer_all_categories".t)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.textPrimary)
                        Spacer()
                        Text("printer_default_tag".t)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.appAccent)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .background(selectedCategories.isEmpty ? Color.appAccent.opacity(0.10) : Color.appSurfaceHigh)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(selectedCategories.isEmpty ? Color.appAccent.opacity(0.35) : Color.appBorderSubtle, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], alignment: .leading, spacing: 10) {
                    ForEach(appCategories) { category in
                        let slug = category.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                        let isSelected = selectedCategories.contains(slug)
                        Button(action: {
                            if isSelected {
                                selectedCategories.remove(slug)
                            } else {
                                selectedCategories.insert(slug)
                            }
                            APHaptic.trigger()
                        }) {
                            HStack {
                                Text(category.name)
                                    .font(.system(size: 12))
                                    .fontWeight(.semibold)
                                Spacer()
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12))
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(isSelected ? Color.appAccent : Color.appSurfaceHigh)
                            .foregroundColor(isSelected ? .white : .textPrimary)
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(isSelected ? Color.clear : Color.appBorderSubtle, lineWidth: 1)
                            )
                        }
                    }
                }
            }
        }
        .apCard()
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Print Preview Sheet
// ─────────────────────────────────────────────────────────────────────────────
struct PrintPreviewSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var isPresented: Bool
    var printer: Printer
    var availableJobs: Set<String> = []
    @State private var previewType: String = "" // "receipt", "kitchen", "bar", "label"

    @State private var isPrinting = false
    @State private var printResultSuccess = false
    @State private var qrVerified = false
    @State private var thaiVerified = false
    @State private var contrastVerified = false
    @State private var cutVerified = false

    // ── Store info (อ่านค่าจริงจาก AppStorage เหมือน ReceiptTemplateSettingsView) ──
    @AppStorage("store_name")        private var storeName       = "AlphaPos Restaurant"
    @AppStorage("store_phone")       private var storePhone      = "02-123-4567"
    @AppStorage("store_address")     private var storeAddress    = "123 Sukhumvit Rd, Bangkok, Thailand"
    @AppStorage("store_tax_id")      private var storeTaxId      = ""
    @AppStorage("store_branch_code") private var storeBranchCode = "00000"
    @AppStorage("store_logo_path")   private var storeLogoPath   = ""
    @AppStorage("promptpay_number")  private var promptPayNumber = ""

    // ── Default template สำหรับ previewType ที่เลือก ──
    @Query(sort: \ReceiptTemplate.name) private var allTemplates: [ReceiptTemplate]

    private var activeTemplate: ReceiptTemplate? {
        let role = previewType.isEmpty ? printer.role : previewType
        let typeKey = role == "label" ? "sticker" : role
        return allTemplates.first(where: { !$0.isDeleted && $0.templateType == typeKey && $0.isDefault })
            ?? allTemplates.first(where: { !$0.isDeleted && $0.templateType == typeKey })
    }

    // ── สร้าง fixedPreviewType สำหรับ ReceiptLivePreview ──
    private var livePreviewType: ReceiptLivePreview.PreviewType {
        switch previewType {
        case "kitchen": return .kitchen
        case "bar":     return .bar
        case "label", "sticker": return .sticker
        default:        return .receipt
        }
    }

    private var orderedJobs: [String] {
        let jobs = availableJobs.isEmpty ? Set([printer.role]) : availableJobs
        let order = ["receipt", "kitchen", "bar", "label"]
        return jobs.sorted { (order.firstIndex(of: $0) ?? 99) < (order.firstIndex(of: $1) ?? 99) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    Picker("Preview Format", selection: $previewType) {
                        ForEach(orderedJobs, id: \.self) { job in
                            Text(previewLabel(job)).tag(job)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding()
                    .background(Color.appSurface)

                    ScrollView {
                        VStack(spacing: 24) {
                            ReceiptLivePreview(
                                storeName:         storeName,
                                storeAddress:      storeAddress,
                                storePhone:        storePhone,
                                storeTaxId:        storeTaxId,
                                storeBranchCode:   storeBranchCode,
                                storeLogoPath:     storeLogoPath,
                                promptPayNumber:   promptPayNumber,
                                headerText:        activeTemplate?.headerText ?? "",
                                footerText:        activeTemplate?.footerText ?? "",
                                showTaxId:         activeTemplate?.showTaxId         ?? true,
                                showCustomerInfo:  activeTemplate?.showCustomerInfo  ?? true,
                                paperWidth:        activeTemplate?.paperWidth        ?? printer.paperWidth,
                                showLogo:          activeTemplate?.showLogo          ?? true,
                                showServiceCharge: activeTemplate?.showServiceCharge ?? true,
                                showTableInfo:     activeTemplate?.showTableInfo     ?? true,
                                showQRCode:        activeTemplate?.showQRCode        ?? true,
                                showItemModifiers: activeTemplate?.showItemModifiers ?? true,
                                showOrderType:     activeTemplate?.showOrderType     ?? true,
                                fixedPreviewType:  livePreviewType
                            )

                            if previewType == "receipt", printResultSuccess {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Physical calibration checklist")
                                        .font(.headline)
                                    Toggle("QR scans to the printed receipt number", isOn: $qrVerified)
                                    Toggle("Thai text is complete and readable", isOn: $thaiVerified)
                                    Toggle("Black/gray text has sufficient contrast", isOn: $contrastVerified)
                                    Toggle("Nothing is clipped and the cutter clears the footer", isOn: $cutVerified)
                                    Button("Confirm 58/80 mm calibration") {
                                        printer.calibrationStatus = "verified"
                                        printer.calibratedAt = Date()
                                        printer.isSynced = false
                                        printer.updatedAt = Date()
                                        try? modelContext.save()
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(!(qrVerified && thaiVerified && contrastVerified && cutVerified))
                                }
                                .padding()
                                .apCard()
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("printer_preview_title".t)
            .apNavBar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("close".t) { isPresented = false }
                        .foregroundColor(.textPrimary)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(action: startTestPrint) {
                        if isPrinting {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Text("printer_print_test_page".t)
                                .fontWeight(.bold)
                        }
                    }
                    .disabled(isPrinting)
                    .foregroundColor(isPrinting ? .textTertiary : .appAccent)
                }
            }
            .onAppear {
                previewType = orderedJobs.first ?? printer.role
            }
        }
    }

    private func previewLabel(_ job: String) -> String {
        switch job {
        case "receipt": return "Receipt"
        case "kitchen": return "Kitchen"
        case "bar": return "Bar"
        case "label", "sticker": return "Sticker"
        default: return job.capitalized
        }
    }

    private func startTestPrint() {
        isPrinting = true
        Task {
            let result = await PrintService.shared.printTest(to: printer, previewType: previewType)
            isPrinting = false
            printResultSuccess = result.success
            if result.success, previewType == "receipt" {
                printer.calibrationStatus = "pending_confirmation"
                printer.isSynced = false
                printer.updatedAt = Date()
                try? modelContext.save()
            }
            // Log เต็มดูได้ที่ Xcode Console
            result.log.forEach { print("[PrintTest] \($0)") }
            // Haptic feedback ให้รู้ผลโดยไม่ต้องแสดง Alert
            APHaptic.trigger()
        }
    }
}

// ── Receipt Preview Card
struct ReceiptPreviewCard: View {
    var paperWidth: String

    var body: some View {
        VStack(spacing: 0) {
            PaperEdgePattern()
                .fill(Color.appDivider)
                .frame(height: 8)
                .opacity(0.3)

            VStack(alignment: .leading, spacing: 12) {
                VStack(spacing: 4) {
                    Text("ALPHAPOS CAFE & GRILL")
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.bold)
                    Text("123 Sukhumvit Rd, Bangkok, Thailand")
                        .font(.system(.caption2, design: .monospaced))
                    Text("TAX ID: 0-1055-63045-88-1")
                        .font(.system(.caption2, design: .monospaced))
                    Text("Tel: 02-123-4567")
                        .font(.system(.caption2, design: .monospaced))
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .foregroundColor(.black)
                .padding(.top, 16)

                DividerPattern()

                VStack(alignment: .leading, spacing: 2) {
                    Text("DATE: 2026-06-10 12:15:00")
                    Text("POS ID: AP-IPAD-01")
                    Text("CASHIER: Somchai Lertwit")
                    Text("ORDER ID: #AP-102546-CN")
                    Text("TABLE: Table 08 (Zone A)")
                    Text("GUESTS: 3 Persons")
                }
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.black)

                DividerPattern()

                HStack {
                    Text("ITEM")
                    Spacer()
                    Text("QTY")
                    Text("PRICE").frame(width: 70, alignment: .trailing)
                }
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.bold)
                .foregroundColor(.black)

                DividerPattern()

                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("Premium Beef Burger")
                            Spacer()
                            Text("2")
                            Text("฿440.00").frame(width: 70, alignment: .trailing)
                        }
                        Text("  + Extra Cheese (x2) (+฿40)")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.gray)
                        Text("  + Medium Rare")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.gray)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("Crispy French Fries")
                            Spacer()
                            Text("1")
                            Text("฿120.00").frame(width: 70, alignment: .trailing)
                        }
                        Text("  + Spicy Seasoning")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.gray)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("Matcha Green Tea Latte")
                            Spacer()
                            Text("2")
                            Text("฿220.00").frame(width: 70, alignment: .trailing)
                        }
                        Text("  + Sweet 50% (x2)")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.gray)
                        Text("  + Oat Milk (+฿30)")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.gray)
                    }
                }
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.black)

                DividerPattern()

                VStack(spacing: 2) {
                    HStack {
                        Text("SUBTOTAL")
                        Spacer()
                        Text("฿850.00")
                    }
                    HStack {
                        Text("10% SERVICE CHARGE")
                        Spacer()
                        Text("฿85.00")
                    }
                    HStack {
                        Text("7% VAT INCLUSIVE")
                        Spacer()
                        Text("฿61.17")
                    }
                    HStack {
                        Text("PROMO DISCOUNT (5%)")
                        Spacer()
                        Text("-฿42.50")
                    }

                    DividerPattern()
                        .padding(.vertical, 4)

                    HStack {
                        Text("GRAND TOTAL")
                            .fontWeight(.bold)
                        Spacer()
                        Text("฿892.50")
                            .fontWeight(.bold)
                    }
                }
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.black)

                DividerPattern()

                VStack(spacing: 8) {
                    Text("PAID VIA DYNAMIC QR PROMPTPAY")
                        .font(.system(.caption2, design: .monospaced))
                        .fontWeight(.bold)

                    ZStack {
                        Rectangle()
                            .fill(Color.white)
                            .frame(width: 100, height: 100)
                            .border(Color.black, width: 1)

                        GridPattern()
                            .stroke(Color.black, lineWidth: 2)
                            .frame(width: 80, height: 80)
                    }
                    .padding(.vertical, 6)

                    Text("THANK YOU FOR YOUR PATRONAGE")
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.bold)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .foregroundColor(.black)
                .padding(.bottom, 24)
            }
            .padding(.horizontal, paperWidth == "58mm" ? 20 : 32)
            .background(Color(hex: "FCFCF9"))

            PaperEdgePattern()
                .fill(Color.appDivider)
                .frame(height: 8)
                .rotationEffect(.degrees(180))
                .opacity(0.3)
        }
        .frame(width: paperWidth == "58mm" ? 320 : 400)
        .cornerRadius(4)
        .shadow(radius: 4)
    }
}

// ── Kitchen Ticket Preview Card
struct KitchenTicketPreviewCard: View {
    var paperWidth: String
    var stationLabel: String = "HOT KITCHEN TICKET"

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                Text(stationLabel)
                    .font(.system(size: 12))
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .tracking(2.0)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.appRose)

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TABLE: T-08")
                            .font(.system(.title3, design: .monospaced))
                            .fontWeight(.black)
                        Text("Order: #AP-1025")
                            .font(.system(.caption, design: .monospaced))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("QUE: #32")
                            .font(.system(.title3, design: .monospaced))
                            .fontWeight(.black)
                            .foregroundColor(.appRose)
                        Text("12:15:32")
                            .font(.system(.caption, design: .monospaced))
                    }
                }
                .foregroundColor(.black)

                DividerPattern()

                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("2 x PREMIUM BEEF BURGER")
                                .font(.system(.body, design: .monospaced))
                                .fontWeight(.black)
                            Spacer()
                            Text("[ ] Pending")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.gray)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("- ** EXTRA CHEESE (x2)")
                                .font(.system(.caption, design: .monospaced))
                                .fontWeight(.bold)
                                .foregroundColor(.appRose)
                            Text("- ** MEDIUM RARE")
                                .font(.system(.caption, design: .monospaced))
                                .fontWeight(.bold)
                                .foregroundColor(.appRose)
                        }
                        .padding(.leading, 12)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("1 x CRISPY FRENCH FRIES")
                                .font(.system(.body, design: .monospaced))
                                .fontWeight(.black)
                            Spacer()
                            Text("[ ] Pending")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.gray)
                        }

                        Text("- SPICY SEASONING")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.black.opacity(0.8))
                            .padding(.leading, 12)
                    }
                }
                .foregroundColor(.black)

                DividerPattern()

                Text("PRINT JOB: #AP-PRNT-4592\nSTAFF: Somchai Lertwit")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.black.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 16)
            }
            .padding(.horizontal, paperWidth == "58mm" ? 20 : 32)
            .padding(.top, 16)
            .background(Color(hex: "FCFCF9"))

            PaperEdgePattern()
                .fill(Color.appDivider)
                .frame(height: 8)
                .rotationEffect(.degrees(180))
                .opacity(0.3)
        }
        .frame(width: paperWidth == "58mm" ? 320 : 400)
        .cornerRadius(4)
        .shadow(radius: 4)
    }
}

// ── Sticker Preview Card
struct StickerPreviewCard: View {
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("T-08 [TICKET 1/3]")
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.bold)
                    Spacer()
                    Text("QUE: #32")
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundColor(.appAccent)
                }
                .foregroundColor(.black)

                Rectangle()
                    .fill(Color.black.opacity(0.2))
                    .frame(height: 1)

                Text("Matcha Latte (Oat)")
                    .font(.system(.headline, design: .monospaced))
                    .fontWeight(.black)
                    .foregroundColor(.black)

                VStack(alignment: .leading, spacing: 2) {
                    Text("- Sweet 50%")
                    Text("- Extra Oat Milk (+฿30)")
                }
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.black.opacity(0.8))

                Spacer()

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("2026-06-10 12:15")
                        Text("AlphaPOS Cafe & Grill")
                    }
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.black.opacity(0.6))

                    Spacer()

                    HStack(spacing: 2) {
                        ForEach(0..<12) { i in
                            Rectangle()
                                .fill(Color.black)
                                .frame(width: i % 3 == 0 ? 3 : (i % 2 == 0 ? 1.5 : 0.8), height: 18)
                        }
                    }
                }
            }
            .padding(16)
            .frame(width: 280, height: 180)
            .background(Color.white)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.black.opacity(0.12), lineWidth: 1)
            )
        }
        .shadow(radius: 4)
    }
}

// ── Mini Shapes / Helpers for Simulators
struct DividerPattern: View {
    var body: some View {
        Text("--------------------------------------------------")
            .font(.system(.caption2, design: .monospaced))
            .foregroundColor(.black.opacity(0.4))
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

struct PaperEdgePattern: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        let width = rect.width
        let triangleWidth: CGFloat = 8
        let triangleHeight: CGFloat = 6
        var currentX: CGFloat = 0

        while currentX < width {
            path.addLine(to: CGPoint(x: currentX + triangleWidth/2, y: rect.minY + triangleHeight))
            path.addLine(to: CGPoint(x: currentX + triangleWidth, y: rect.maxY))
            currentX += triangleWidth
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct GridPattern: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let steps = 6
        let w = rect.width / CGFloat(steps)
        let h = rect.height / CGFloat(steps)

        for i in 0...steps {
            path.move(to: CGPoint(x: rect.minX + CGFloat(i)*w, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX + CGFloat(i)*w, y: rect.maxY))

            path.move(to: CGPoint(x: rect.minX, y: rect.minY + CGFloat(i)*h))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + CGFloat(i)*h))
        }
        return path
    }
}

// ── Printer Row View Component
private struct PrinterGroup: Identifiable {
    let printer: Printer
    let members: [Printer]
    let roles: Set<String>
    let categories: Set<String>
    var id: String {
        [printer.connectionType, printer.ipAddress ?? "", String(printer.port), printer.bluetoothName ?? "", printer.paperWidth, printer.emulation].joined(separator: "|")
    }
}

struct PrinterRowView: View {
    let printer: Printer
    let roles: Set<String>
    var onPreview: () -> Void
    var onEdit: () -> Void
    var onDelete: (() -> Void)? = nil

    @State private var connectionStatus: ConnectionStatus = .unknown
    @State private var isTesting = false

    enum ConnectionStatus {
        case unknown, online, offline, testing
        var color: Color {
            switch self {
            case .unknown:  return .textTertiary
            case .online:   return .appTeal
            case .offline:  return .appRose
            case .testing:  return .appAmber
            }
        }
        var icon: String {
            switch self {
            case .unknown:  return "circle.dotted"
            case .online:   return "checkmark.circle.fill"
            case .offline:  return "xmark.circle.fill"
            case .testing:  return "arrow.triangle.2.circlepath"
            }
        }
        var label: String {
            switch self {
            case .unknown:  return "Tap to test"
            case .online:   return "Online"
            case .offline:  return "Offline / Error"
            case .testing:  return "Testing..."
            }
        }
    }

    private var primaryRole: String {
        let order = ["receipt", "kitchen", "bar", "label"]
        return roles.sorted { (order.firstIndex(of: $0) ?? 99) < (order.firstIndex(of: $1) ?? 99) }.first ?? printer.role
    }
    private var iconName: String {
        switch primaryRole {
        case "receipt": return "printer.fill"
        case "kitchen": return "printer.dotmatrix.fill"
        case "bar":     return "cup.and.saucer.fill"
        default:        return "tag.fill"
        }
    }
    private var iconColor: Color {
        switch primaryRole {
        case "receipt": return .appAccent
        case "kitchen": return .appTeal
        case "bar":     return .appAmber
        default:        return .appAmber
        }
    }
    private var connectionText: String {
        switch printer.connectionType {
        case "network":   return "\(printer.ipAddress ?? "No IP"):\(printer.port)"
        case "bluetooth": return "Bluetooth · \(printer.bluetoothName ?? "Unknown")"
        default:          return "USB / Lightning"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Main row ─────────────────────────────────────────────────
            HStack(spacing: 14) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(iconColor.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: iconName)
                        .foregroundColor(iconColor)
                        .font(.system(size: 18, weight: .semibold))
                }

                // Info
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(printer.name)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.textPrimary)

                        HStack(spacing: 4) {
                            ForEach(Array(roles).sorted(by: roleSort), id: \.self) { role in
                                Text(roleLabel(role))
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(roleColor(role))
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(roleColor(role).opacity(0.12))
                                    .cornerRadius(4)
                            }
                        }
                    }

                    Text(connectionText)
                        .font(.system(size: 12))
                        .foregroundColor(.textSecondary)

                    Text("\(printer.paperWidth) · \(printer.emulation.uppercased())")
                        .font(.system(size: 12))
                        .foregroundColor(.textTertiary)
                }

                Spacer()

                // Actions column
                VStack(spacing: 8) {
                    // Edit button
                    Button(action: onEdit) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.appAccent)
                            .frame(width: 32, height: 32)
                            .background(Color.appAccent.opacity(0.10))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)

                    // Preview button
                    Button(action: onPreview) {
                        Image(systemName: "eye.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.textSecondary)
                            .frame(width: 32, height: 32)
                            .background(Color.appSurfaceHigh)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)

                    if let onDelete = onDelete {
                        // Delete button
                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.appRose)
                                .frame(width: 32, height: 32)
                                .background(Color.appRose.opacity(0.10))
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.vertical, 10)

            // ── Live connection status bar ────────────────────────────────
            Button {
                guard !isTesting else { return }
                runQuickTest()
            } label: {
                HStack(spacing: 8) {
                    if connectionStatus == .testing {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(connectionStatus.color)
                    } else {
                        Image(systemName: connectionStatus.icon)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(connectionStatus.color)
                    }
                    Text(connectionStatus.label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(connectionStatus.color)
                    Spacer()
                    if connectionStatus == .unknown {
                        Text("printer_test_connection".t)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.appAccent)
                    }
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 12))
                        .foregroundColor(connectionStatus == .unknown ? .appAccent : connectionStatus.color.opacity(0.6))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(connectionStatus.color.opacity(0.07))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(connectionStatus.color.opacity(0.20), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .padding(.bottom, 4)
        }
    }

    private func runQuickTest() {
        isTesting = true
        connectionStatus = .testing
        APHaptic.trigger()
        Task {
            let result = await PrintService.shared.printTest(to: printer, previewType: primaryRole)
            await MainActor.run {
                connectionStatus = result.success ? .online : .offline
                isTesting = false
            }
        }
    }

    private func roleSort(_ lhs: String, _ rhs: String) -> Bool {
        let order = ["receipt", "kitchen", "bar", "label"]
        return (order.firstIndex(of: lhs) ?? 99) < (order.firstIndex(of: rhs) ?? 99)
    }

    private func roleLabel(_ role: String) -> String {
        switch role {
        case "receipt": return "Receipt"
        case "kitchen": return "Kitchen"
        case "bar": return "Bar"
        default: return "Sticker"
        }
    }

    private func roleColor(_ role: String) -> Color {
        switch role {
        case "receipt": return .appAccent
        case "kitchen": return .appTeal
        case "bar": return .appAmber
        default: return .appAmber
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Printer Discovery Sheet (Bonjour / mDNS Auto-Discovery)
// ─────────────────────────────────────────────────────────────────────────────

struct PrinterDiscoverySheet: View {
    @Binding var isPresented: Bool
    @ObservedObject var discovery: BonjourPrinterDiscovery
    var onAdd: (DiscoveredPrinter) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // ── Status banner ──────────────────────────────────
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Color.appAccent.opacity(0.12))
                                    .frame(width: 44, height: 44)
                                if discovery.isScanning {
                                    ProgressView().tint(.appAccent)
                                } else {
                                    Image(systemName: "dot.radiowaves.left.and.right")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundColor(.appAccent)
                                }
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(discovery.isScanning ? "กำลังค้นหาเครื่องพิมพ์..." : "ค้นหาเสร็จสิ้น")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.textPrimary)
                                Text("printer_discover_hint".t)
                                    .font(.system(size: 12))
                                    .foregroundColor(.textSecondary)
                            }
                            Spacer()
                        }
                        .padding(14)
                        .background(Color.appSurface)
                        .cornerRadius(12)

                        // ── Results ────────────────────────────────────────
                        if discovery.printers.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: discovery.isScanning ? "magnifyingglass" : "wifi.exclamationmark")
                                    .font(.system(size: 40))
                                    .foregroundColor(.textTertiary)
                                    .padding(.top, 20)
                                Text(discovery.isScanning ? "กำลังสแกนเครือข่าย..." : "ไม่พบเครื่องพิมพ์")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.textPrimary)
                                Text(discovery.isScanning
                                     ? "กรุณารอสักครู่"
                                     : "ตรวจสอบว่าเครื่องพิมพ์เปิดอยู่และเชื่อมต่อ Wi-Fi เดียวกับ iPad — หรือเพิ่มด้วยตนเองผ่าน IP Address")
                                    .font(.system(size: 12))
                                    .foregroundColor(.textSecondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 24)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, 20)
                        } else {
                            VStack(spacing: 10) {
                                ForEach(discovery.printers) { printer in
                                    discoveredRow(printer)
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("printer_discover_title".t)
            .navigationBarTitleDisplayMode(.inline)
            .apNavBar(background: Color.appBackground)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("close".t) { isPresented = false }
                        .foregroundColor(.textPrimary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        discovery.start()
                    } label: {
                        Label("printer_rescan".t, systemImage: "arrow.clockwise")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.appAccent)
                    }
                    .disabled(discovery.isScanning)
                }
            }
        }
        .apColorScheme()
    }

    private func discoveredRow(_ printer: DiscoveredPrinter) -> some View {
        Button {
            APHaptic.trigger()
            onAdd(printer)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.appTeal.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: "printer.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.appTeal)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(printer.name)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)

                    if let host = printer.host {
                        Text("\(host):\(printer.port.map { String($0) } ?? "9100")")
                            .font(.system(size: 12))
                            .foregroundColor(.textSecondary)
                    } else {
                        Text("printer_resolving_ip".t)
                            .font(.system(size: 12))
                            .foregroundColor(.textTertiary)
                    }

                    if let brand = printer.inferredBrand {
                        Text(brand.displayName)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.appAccent)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.appAccent.opacity(0.10))
                            .cornerRadius(4)
                    }
                }

                Spacer()

                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.appAccent)
            }
            .padding(12)
            .background(Color.appSurface)
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(Color.appBorderSubtle, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}


// MARK: - USB Accessory Scanner View
// Uses StarIO10 discovery so a device is only reported as supported when the
// same SDK used for printing can resolve it.
// ─────────────────────────────────────────────────────────────────────────────

#if canImport(StarIO10)
@MainActor
private final class StarUSBDiscovery: NSObject, ObservableObject, StarDeviceDiscoveryManagerDelegate {
    struct Device: Identifiable, Equatable {
        let identifier: String
        let model: String
        var id: String { identifier }
    }

    @Published var devices: [Device] = []
    @Published var isScanning = false
    @Published var errorMessage: String?
    private var manager: (any StarDeviceDiscoveryManager)?

    func scan() {
        manager?.stopDiscovery()
        devices = []
        errorMessage = nil
        isScanning = true
        do {
            let discovery = try StarDeviceDiscoveryManagerFactory.create(interfaceTypes: [.usb])
            discovery.discoveryTime = 2_000
            discovery.delegate = self
            manager = discovery
            try discovery.startDiscovery()
        } catch {
            errorMessage = error.localizedDescription
            isScanning = false
        }
    }

    func stop() {
        manager?.stopDiscovery()
        manager = nil
        isScanning = false
    }

    nonisolated func manager(_ manager: any StarDeviceDiscoveryManager, didFind printer: StarPrinter) {
        let identifier = printer.connectionSettings.identifier
        let model = printer.information.map { String(describing: $0.model) }
            ?? "Star Micronics printer"
        Task { @MainActor in
            let device = Device(identifier: identifier, model: model)
            if !devices.contains(device) { devices.append(device) }
        }
    }

    nonisolated func managerDidFinishDiscovery(_ manager: any StarDeviceDiscoveryManager) {
        Task { @MainActor in
            isScanning = false
            self.manager = nil
        }
    }
}
#endif

@MainActor
struct USBAccessoryScannerView: View {
    @Binding var selectedIdentifier: String
#if canImport(StarIO10)
    @StateObject private var discovery = StarUSBDiscovery()
#endif

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "cable.connector.horizontal")
                    .foregroundColor(.appTeal)
                    .font(.system(size: 12, weight: .semibold))
                Text("printer_usb_connected".t)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.textPrimary)
                Spacer()
                Button {
#if canImport(StarIO10)
                    discovery.scan()
#endif
                    APHaptic.trigger()
                } label: {
                    HStack(spacing: 4) {
#if canImport(StarIO10)
                        if discovery.isScanning {
                            ProgressView().scaleEffect(0.7).tint(.appAccent)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12, weight: .bold))
                        }
#else
                        Image(systemName: "exclamationmark.triangle.fill")
#endif
                        Text("printer_usb_scan".t)
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundColor(.appAccent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.appAccent.opacity(0.10))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }

#if canImport(StarIO10)
            if let error = discovery.errorMessage {
                Text("StarIO10 USB discovery failed: \(error)")
                    .font(.system(size: 12))
                    .foregroundColor(.red)
                    .padding(10)
            } else if discovery.devices.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "printer.slash")
                        .foregroundColor(.textTertiary)
                        .font(.system(size: 12))
                    Text("printer_usb_empty".t)
                        .font(.system(size: 12))
                        .foregroundColor(.textTertiary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.appSurfaceHigh)
                .cornerRadius(8)
            } else {
                ForEach(discovery.devices) { device in
                    Button {
                        selectedIdentifier = device.identifier
                        APHaptic.trigger()
                    } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.appTeal.opacity(0.12))
                                .frame(width: 36, height: 36)
                            Image(systemName: "printer.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.appTeal)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.model)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.textPrimary)
                            Text(device.identifier)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.appTeal)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 3) {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.appTeal)
                                    .frame(width: 6, height: 6)
                                Text(selectedIdentifier == device.identifier
                                     ? "เลือกแล้ว" : "StarIO10 พร้อมใช้งาน")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.appTeal)
                            }
                        }
                    }
                    .padding(10)
                    .background(Color.appTeal.opacity(0.05))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(selectedIdentifier == device.identifier
                                    ? Color.appTeal : Color.appTeal.opacity(0.25), lineWidth: 1.5)
                    )
                    }
                    .buttonStyle(.plain)
                }
            }
#else
            Text("StarIO10 is not included in this build.")
                .font(.system(size: 12))
                .foregroundColor(.red)
#endif
        }
        .padding(12)
        .background(Color.appSurface)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.appTeal.opacity(0.30), lineWidth: 1.5)
        )
#if canImport(StarIO10)
        .onAppear { discovery.scan() }
        .onChange(of: discovery.devices) { _, devices in
            if selectedIdentifier.isEmpty, let first = devices.first {
                selectedIdentifier = first.identifier
            }
        }
        .onDisappear { discovery.stop() }
#endif
    }
}
