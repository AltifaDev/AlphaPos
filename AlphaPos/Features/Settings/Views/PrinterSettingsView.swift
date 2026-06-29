import SwiftUI
import SwiftData
import CoreImage

struct PrinterSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    
    // Printer settings
    @AppStorage("receipt_printer_enabled") private var receiptPrinterEnabled = true
    @AppStorage("kitchen_printer_enabled") private var kitchenPrinterEnabled = true
    @AppStorage("printer_ip") private var printerIP = "192.168.1.201"
    // ── Shift auto-print toggles ──────────────────────────────────────────
    @AppStorage("print_open_shift")  private var printOpenShift  = false
    @AppStorage("print_close_shift") private var printCloseShift = true
    
    @Query(sort: \Printer.name) private var printersList: [Printer]
    @Query(sort: \Category.name) private var appCategories: [Category]
    
    @State private var showingAddPrinterSheet = false
    @State private var showingEditPrinterSheet = false
    @State private var selectedPrinterForEdit: Printer? = nil
    
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
    
    // Alert state for print simulation
    @State private var showingPrintAlert = false
    @State private var printAlertMessage = ""
    @State private var isTestingPrint = false

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(L.Sections.printer.t)
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.appAccent)
                                .tracking(1.0)
                            Spacer()
                            Button(action: {
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
                            }) {
                                Label("Add Printer", systemImage: "plus.circle.fill")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.appAccent)
                            }
                        }
                        
                        VStack(spacing: 16) {
                            let activePrinters = printersList.filter { !$0.isDeleted }
                            
                            if activePrinters.isEmpty {
                                VStack(spacing: 12) {
                                    Image(systemName: "printer.slash")
                                        .font(.system(size: 36))
                                        .foregroundColor(.textSecondary.opacity(0.5))
                                        .padding(.top, 8)
                                    Text("No printers configured yet.")
                                        .font(.headline)
                                        .foregroundColor(.textPrimary)
                                    Text("Tap 'Add Printer' above to configure a thermal receipt, kitchen ticket, or label sticker printer.")
                                        .font(.caption)
                                        .foregroundColor(.textSecondary)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 16)
                                        .padding(.bottom, 8)
                                }
                                .frame(maxWidth: .infinity)
                            } else {
                                ForEach(activePrinters) { printer in
                                    PrinterRowView(
                                        printer: printer,
                                        onPreview: {
                                            selectedPrinterForPreview = printer
                                            showingPreviewSheet = true
                                        },
                                        onEdit: {
                                            selectedPrinterForEdit = printer
                                            printerName = printer.name
                                            connectionType = printer.connectionType
                                            ipAddress = printer.ipAddress ?? ""
                                            portString = String(printer.port)
                                            bluetoothName = printer.bluetoothName ?? ""
                                            paperWidth = printer.paperWidth
                                            printerRole = printer.role
                                            
                                            selectedCategoriesForRouting = Set(printer.routingRules.filter { !$0.isDeleted }.compactMap { $0.categoryId })
                                            showingEditPrinterSheet = true
                                        }
                                    )
                                    
                                    if printer.id != activePrinters.last?.id {
                                        Divider()
                                            .background(Color.appDivider)
                                    }
                                }
                            }
                        }
                        .apCard()
                    }
                    .padding(.horizontal)

                    // ── SECTION: SHIFT AUTO-PRINT ────────────────────────
                    VStack(alignment: .leading, spacing: 12) {
                        Text("SHIFT PRINTING")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.appAccent)
                            .tracking(1.0)

                        VStack(spacing: 0) {
                            // Open Shift toggle
                            HStack(spacing: 14) {
                                Image(systemName: "lock.open.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.appTeal)
                                    .frame(width: 32, height: 32)
                                    .background(Color.appTeal.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Print Open Shift Slip")
                                        .font(.body).foregroundColor(.textPrimary)
                                    Text("Auto-print when shift starts")
                                        .font(.caption).foregroundColor(.textSecondary)
                                }
                                Spacer()
                                Toggle("", isOn: $printOpenShift)
                                    .labelsHidden()
                                    .tint(.appTeal)
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)

                            Divider().background(Color.appDivider).padding(.leading, 58)

                            // Close Shift / Z-Report toggle
                            HStack(spacing: 14) {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.appRose)
                                    .frame(width: 32, height: 32)
                                    .background(Color.appRose.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Print Z-Report on Close Shift")
                                        .font(.body).foregroundColor(.textPrimary)
                                    Text("Auto-print Z-Report when shift ends")
                                        .font(.caption).foregroundColor(.textSecondary)
                                }
                                Spacer()
                                Toggle("", isOn: $printCloseShift)
                                    .labelsHidden()
                                    .tint(.appRose)
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)
                        }
                        .apCard()
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
        }
        .navigationTitle(L.Sections.printer.t)
        .navigationBarTitleDisplayMode(.inline)
        .apNavBar(background: Color.appBackground)
        .alert("Printer Connection Test", isPresented: $showingPrintAlert) {
            Button("Done", role: .cancel) { }
        } message: {
            Text(printAlertMessage)
        }
        .sheet(isPresented: $showingAddPrinterSheet) {
            PrinterConfigSheet(
                isPresented: $showingAddPrinterSheet,
                printerToEdit: nil,
                onSave: savePrinterAction,
                appCategories: appCategories
            )
        }
        .sheet(isPresented: $showingEditPrinterSheet) {
            PrinterConfigSheet(
                isPresented: $showingEditPrinterSheet,
                printerToEdit: selectedPrinterForEdit,
                onSave: savePrinterAction,
                onDelete: deletePrinterAction,
                appCategories: appCategories
            )
        }
        .sheet(isPresented: $showingPreviewSheet) {
            if let printer = selectedPrinterForPreview {
                PrintPreviewSheet(isPresented: $showingPreviewSheet, printer: printer)
            }
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
        role: String,
        isActive: Bool,
        emulation: String,
        selectedCategories: Set<String>
    ) {
        let printer: Printer
        if let id = id, let existing = printersList.first(where: { $0.id == id }) {
            printer = existing
            printer.name = name
            printer.connectionType = connectionType
            printer.ipAddress = ipAddress
            printer.port = port
            printer.bluetoothName = bluetoothName
            printer.paperWidth = paperWidth
            printer.role = role
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
                status: "unknown",
                role: role,
                isActive: isActive,
                emulation: emulation,
                isSynced: false,
                isDeleted: false,
                updatedAt: Date()
            )
            modelContext.insert(printer)
        }
        
        // Remove existing routing rules (soft delete)
        for rule in printer.routingRules {
            rule.isDeleted = true
            rule.isSynced = false
            rule.updatedAt = Date()
        }
        
        // Add new rules
        for categoryName in selectedCategories {
            let slug = categoryName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if let existingRule = printer.routingRules.first(where: { $0.categoryId == slug }) {
                existingRule.isDeleted = false
                existingRule.isSynced = false
                existingRule.updatedAt = Date()
            } else {
                let rule = PrintRoutingRule(
                    printer: printer,
                    categoryId: slug,
                    printOnOrder: true,
                    printOnPayment: (role == "receipt"),
                    isSynced: false,
                    isDeleted: false,
                    updatedAt: Date()
                )
                modelContext.insert(rule)
                printer.routingRules.append(rule)
            }
        }
        
        try? modelContext.save()
        
        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }
    
    private func deletePrinterAction(id: UUID) {
        if let printer = printersList.first(where: { $0.id == id }) {
            printer.isDeleted = true
            printer.isSynced = false
            printer.updatedAt = Date()
            
            for rule in printer.routingRules {
                rule.isDeleted = true
                rule.isSynced = false
                rule.updatedAt = Date()
            }
            
            try? modelContext.save()
            
            Task {
                await SyncEngine.shared.syncAll(modelContext: modelContext)
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - PrinterConfigSheet
// ─────────────────────────────────────────────────────────────────────────────
struct PrinterConfigSheet: View {
    @Binding var isPresented: Bool
    var printerToEdit: Printer?
    var onSave: (UUID?, String, String, String?, Int, String?, String, String, Bool, String, Set<String>) -> Void
    var onDelete: ((UUID) -> Void)? = nil
    var appCategories: [Category]
    
    @State private var name: String = ""
    @State private var connectionType: String = "network" // network, bluetooth, usb
    @State private var ipAddress: String = ""
    @State private var portString: String = "9100"
    @State private var bluetoothName: String = ""
    @State private var paperWidth: String = "80mm" // 80mm, 58mm, 40mm Sticker
    @State private var role: String = "kitchen" // receipt, kitchen, label
    @State private var isActive: Bool = true
    @State private var emulation: String = "epson" // epson, star, generic, tspl
    @State private var selectedCategories = Set<String>()
    
    @State private var showingValidationAlert = false
    @State private var validationMessage = ""
    
    @State private var isTesting = false
    @State private var showingTestResultAlert = false
    @State private var testResultMessage = ""
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        identitySection
                        connectionSection
                        mediaSection
                        routingSection
                        
                        // ── ACTIONS ──────────────────────────────────────────
                        VStack(spacing: 12) {
                            Button(action: validateAndSave) {
                                Text("Save Configuration")
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
                            
                            if let onDelete = onDelete, let printerId = printerToEdit?.id {
                                Button(action: {
                                    onDelete(printerId)
                                    isPresented = false
                                }) {
                                    Text("Delete Printer Connection")
                                        .foregroundColor(.appRose)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle(printerToEdit == nil ? "Add Printer Connection" : "Edit Printer Connection")
            .apNavBar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                        .foregroundColor(.textPrimary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
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
                    role = printer.role
                    isActive = printer.isActive
                    emulation = printer.emulation
                    
                    selectedCategories = Set(printer.routingRules.filter { !$0.isDeleted }.compactMap { $0.categoryId })
                }
            }
            .alert("Configuration Error", isPresented: $showingValidationAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(validationMessage)
            }
            .alert(isTesting ? "Testing Connection" : "Connection Test Result", isPresented: $showingTestResultAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                ScrollView {
                    Text(testResultMessage)
                        .font(.system(.caption, design: .monospaced))
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .onChange(of: emulation) { oldValue, newValue in
                if newValue == "generic" && connectionType == "usb" {
                    connectionType = "network"
                }
            }
        }
    }
    
    private func runTestPrint() {
        print("[Xcode Console] User tapped Test Connection & Print")
        let portInt = Int(portString.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 9100
        print("[Xcode Console] Configured inputs: connectionType=\(connectionType), ip=\(ipAddress), port=\(portInt), emulation=\(emulation), role=\(role)")
        
        let tempPrinter = Printer(
            name: name.isEmpty ? "Test Printer" : name,
            connectionType: connectionType,
            ipAddress: ipAddress.isEmpty ? nil : ipAddress,
            port: portInt,
            bluetoothName: bluetoothName.isEmpty ? nil : bluetoothName,
            paperWidth: paperWidth,
            role: role,
            isActive: isActive,
            emulation: emulation
        )
        
        print("[Xcode Console] Spawning print test task...")
        isTesting = true
        Task {
            print("[Xcode Console] Executing PrintService.printTest...")
            let result = await PrintService.shared.printTest(to: tempPrinter, previewType: role)
            isTesting = false
            print("[Xcode Console] PrintService.printTest finished. Success=\(result.success)")
            testResultMessage = result.log.joined(separator: "\n")
            showingTestResultAlert = true
            print("[Xcode Console] Presenting test result alert.")
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
        
        let portInt = Int(portString.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 9100
        
        onSave(
            printerToEdit?.id,
            name,
            connectionType,
            connectionType == "network" ? ipAddress : nil,
            portInt,
            connectionType == "bluetooth" ? bluetoothName : nil,
            paperWidth,
            role,
            isActive,
            emulation,
            selectedCategories
        )
        isPresented = false
    }
}

// ── EXTENSION: COMPILER OPTIMIZATIONS ───────────────────────────────────────
extension PrinterConfigSheet {
    @ViewBuilder
    private var identitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PRINTER IDENTITY")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.appAccent)
                .tracking(1.0)
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Printer Brand / Emulation")
                    .font(.caption)
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
                Text("Printer Name")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.textSecondary)
                TextField("e.g. Kitchen Printer, Main Cashier", text: $name)
                    .textFieldStyle(PlainTextFieldStyle())
                    .padding()
                    .background(Color.appSurfaceHigh)
                    .foregroundColor(.textPrimary)
                    .cornerRadius(8)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Printer Role")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.textSecondary)
                Picker("Role", selection: $role) {
                    Text("Receipt (FOH)").tag("receipt")
                    Text("Kitchen (BOH)").tag("kitchen")
                    Text("Bar Station").tag("bar")
                    Text("Label Sticker").tag("label")
                }
                .pickerStyle(SegmentedPickerStyle())
            }
            
            Toggle("Printer Active Status", isOn: $isActive)
                .tint(.appAccent)
        }
        .apCard()
    }
    
    @ViewBuilder
    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CONNECTION INTERFACE")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.appAccent)
                .tracking(1.0)
            
            if emulation == "generic" {
                Picker("Connection Type", selection: $connectionType) {
                    Text("TCP/IP LAN").tag("network")
                    Text("Bluetooth").tag("bluetooth")
                }
                .pickerStyle(SegmentedPickerStyle())
            } else {
                Picker("Connection Type", selection: $connectionType) {
                    Text("TCP/IP LAN").tag("network")
                    Text("Bluetooth").tag("bluetooth")
                    Text("USB direct").tag("usb")
                }
                .pickerStyle(SegmentedPickerStyle())
            }
            
            if connectionType == "network" {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("IP Address")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.textSecondary)
                        TextField("192.168.1.X", text: $ipAddress)
                            .keyboardType(.numbersAndPunctuation)
                            .textFieldStyle(PlainTextFieldStyle())
                            .padding()
                            .background(Color.appSurfaceHigh)
                            .foregroundColor(.textPrimary)
                            .cornerRadius(8)
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Port")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.textSecondary)
                        TextField("9100", text: $portString)
                            .keyboardType(.numberPad)
                            .textFieldStyle(PlainTextFieldStyle())
                            .padding()
                            .background(Color.appSurfaceHigh)
                            .foregroundColor(.textPrimary)
                            .cornerRadius(8)
                    }
                    
                    Text("Recommended connection for local router setups. Ensure the printer and iPad are connected to the same local Wi-Fi router network.")
                        .font(.caption2)
                        .foregroundColor(.textSecondary)
                        .padding(.top, 2)
                }
            } else if connectionType == "bluetooth" {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Bluetooth Accessory Name")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.textSecondary)
                        TextField("e.g. Star TSP100-B101", text: $bluetoothName)
                            .textFieldStyle(PlainTextFieldStyle())
                            .padding()
                            .background(Color.appSurfaceHigh)
                            .foregroundColor(.textPrimary)
                            .cornerRadius(8)
                    }
                    
                    Text("Requires standard Bluetooth pairing inside iPad Settings first. Only MFi-certified Bluetooth printers are supported.")
                        .font(.caption2)
                        .foregroundColor(.textSecondary)
                        .padding(.top, 2)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.appTeal)
                        Text("MFi USB Direct Printing Enabled")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.appTeal)
                    }
                    
                    Text("Connect your MFi-compatible printer (e.g. Star TSP143IIIU, Epson TM-m30) directly using a Lightning/USB data cable. No networking setup needed.")
                        .font(.caption2)
                        .foregroundColor(.textSecondary)
                }
                .padding(10)
                .background(Color.appTeal.opacity(0.1))
                .cornerRadius(6)
            }
            
            if emulation == "generic" {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.appAmber)
                        Text("Generic USB is unsupported on iOS")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.appAmber)
                    }
                    
                    Text("Xprinter, Rongta, and generic printers do NOT support USB direct printing on iPad due to Apple's MFi security restrictions. Please connect the printer to your router via Ethernet cable and choose TCP/IP LAN.")
                        .font(.caption2)
                        .foregroundColor(.textSecondary)
                }
                .padding(10)
                .background(Color.appAmber.opacity(0.1))
                .cornerRadius(6)
                .padding(.top, 4)
            }
        }
        .apCard()
    }
    
    @ViewBuilder
    private var mediaSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MEDIA SPECIFICATIONS")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.appAccent)
                .tracking(1.0)
            
            Picker("Paper Width", selection: $paperWidth) {
                Text("80 mm Thermal").tag("80mm")
                Text("58 mm Thermal").tag("58mm")
                Text("40 mm Sticker").tag("40mm Sticker")
            }
            .pickerStyle(SegmentedPickerStyle())
        }
        .apCard()
    }
    
    @ViewBuilder
    private var routingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CATEGORY ROUTING MAP")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.appAccent)
                .tracking(1.0)
            
            Text("Map menu categories to this printer. If none are selected, all categories will default to printing here.")
                .font(.caption2)
                .foregroundColor(.textSecondary)
            
            if appCategories.isEmpty {
                Text("No categories registered in system database.")
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                    .italic()
            } else {
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
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                Spacer()
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.caption2)
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
    @Binding var isPresented: Bool
    var printer: Printer
    @State private var previewType: String = "" // "receipt", "kitchen", "bar", "label"
    
    @State private var isPrinting = false
    @State private var printResultSuccess = false
    
    // ── Store info (อ่านค่าจริงจาก AppStorage เหมือน ReceiptTemplateSettingsView) ──
    @AppStorage("store_name")        private var storeName       = "AlphaPos Restaurant"
    @AppStorage("store_phone")       private var storePhone      = "02-123-4567"
    @AppStorage("store_address")     private var storeAddress    = "123 Sukhumvit Rd, Bangkok"
    @AppStorage("store_tax_id")      private var storeTaxId      = "1234567890123"
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

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    Picker("Preview Format", selection: $previewType) {
                        Text("FOH Receipt").tag("receipt")
                        Text("BOH Kitchen Ticket").tag("kitchen")
                        Text("Bar Ticket").tag("bar")
                        Text("Label Sticker").tag("label")
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
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Digital Print Preview")
            .apNavBar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { isPresented = false }
                        .foregroundColor(.textPrimary)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: startTestPrint) {
                        if isPrinting {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Text("Print Test Page")
                                .fontWeight(.bold)
                        }
                    }
                    .disabled(isPrinting)
                    .foregroundColor(isPrinting ? .textTertiary : .appAccent)
                }
            }
            .onAppear {
                previewType = printer.role
            }
        }
    }
    
    private func startTestPrint() {
        isPrinting = true
        Task {
            let result = await PrintService.shared.printTest(to: printer, previewType: previewType)
            isPrinting = false
            printResultSuccess = result.success
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
                    .font(.caption2)
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
struct PrinterRowView: View {
    let printer: Printer
    var onPreview: () -> Void
    var onEdit: () -> Void
    
    private var iconName: String {
        switch printer.role {
        case "receipt": return "printer.fill"
        case "kitchen": return "printer.dotmatrix.fill"
        case "bar":     return "cup.and.saucer.fill"
        default: return "tag.fill"
        }
    }
    
    private var iconColor: Color {
        switch printer.role {
        case "receipt": return Color.appAccent
        case "kitchen": return Color.appTeal
        case "bar":     return Color.appAmber
        default: return Color.appAmber
        }
    }
    
    private var connectionText: String {
        if printer.connectionType == "network" {
            return "\(printer.ipAddress ?? "No IP"):\(printer.port)"
        } else if printer.connectionType == "bluetooth" {
            return "Bluetooth: \(printer.bluetoothName ?? "Unknown")"
        } else {
            return "USB Connection"
        }
    }
    
    private var roleLabel: String {
        switch printer.role {
        case "receipt": return "Receipt"
        case "kitchen": return "Kitchen"
        case "bar":     return "Bar"
        default: return "Sticker"
        }
    }
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.12))
                    .frame(width: 42, height: 42)
                Image(systemName: iconName)
                    .foregroundColor(iconColor)
                    .font(.title3)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(printer.name)
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                
                Text("\(connectionText) • \(printer.paperWidth)")
                    .font(.caption)
                    .foregroundColor(.textSecondary)
            }
            
            Spacer()
            
            Text(roleLabel)
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(iconColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(iconColor.opacity(0.12))
                .cornerRadius(APRadius.sm)
            
            HStack(spacing: 8) {
                Button(action: onPreview) {
                    Image(systemName: "eye.fill")
                        .foregroundColor(.textSecondary)
                        .padding(8)
                        .background(Color.appSurfaceHigh)
                        .clipShape(Circle())
                }
                
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .foregroundColor(.appAccent)
                        .padding(8)
                        .background(Color.appSurfaceHigh)
                        .clipShape(Circle())
                }
            }
        }
        .padding(.vertical, 4)
    }
}

