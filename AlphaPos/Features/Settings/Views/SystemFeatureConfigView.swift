import SwiftUI

// MARK: - SystemFeatureConfigView
// ─────────────────────────────────────────────────────────────────────────────
// Centralized Feature Control Dashboard — Unified toggle panel for ALL
// system-level feature flags discovered across the AlphaPos codebase.
// Each @AppStorage key maps to exactly the same key used by the consuming
// views (POSView, PrintService, KitchenDisplayView, etc.), ensuring
// changes here propagate instantly via UserDefaults observation.
// ─────────────────────────────────────────────────────────────────────────────

struct SystemFeatureConfigView: View {
    // ── 1. Payment Methods ───────────────────────────────────────────────
    @AppStorage("payment_method_cash_enabled") private var cashEnabled = true
    @AppStorage("payment_method_card_enabled") private var cardEnabled = true
    @AppStorage("payment_method_qr_enabled") private var qrEnabled = true
    @AppStorage("payment_method_truemoney_enabled") private var trueMoneyEnabled = true
    @AppStorage("payment_method_linepay_enabled") private var linePayEnabled = false
    @AppStorage("payment_method_grabpay_enabled") private var grabPayEnabled = false
    @AppStorage("payment_test_mode") private var paymentTestMode = false

    // ── 2. POS & Floorplan Features ──────────────────────────────────────
    @AppStorage("enable_table_system") private var enableTableSystem = true
    @AppStorage("enable_web_ordering") private var enableWebOrdering = true
    @AppStorage("enable_tax") private var enableTax = true
    @AppStorage("enable_service_charge") private var enableServiceCharge = true
    @AppStorage("promotions_auto_apply") private var promotionsAutoApply = true
    @AppStorage("enable_realtime_stock_warning") private var enableRealtimeStockWarning = true

    // ── 3. Kitchen Display System (KDS) ──────────────────────────────────
    @AppStorage("kds_show_kitchen") private var kdsShowKitchen = true
    @AppStorage("kds_show_bar") private var kdsShowBar = true
    @AppStorage("kds_auto_complete_enabled") private var kdsAutoCompleteEnabled = false
    @AppStorage("kds_sound_enabled") private var kdsSoundEnabled = true

    // ── 4. Printers & Receipts ───────────────────────────────────────────
    @AppStorage("receipt_printer_enabled") private var receiptPrinterEnabled = true
    @AppStorage("kitchen_printer_enabled") private var kitchenPrinterEnabled = true
    @AppStorage("disable_receipt_printing") private var disableReceiptPrinting = false
    @AppStorage("auto_print_receipt_on_payment") private var autoPrintReceipt = false
    @AppStorage("print_open_shift") private var printOpenShift = false
    @AppStorage("print_close_shift") private var printCloseShift = true
    @AppStorage("show_logo_on_receipt") private var showLogoOnReceipt = true
    @AppStorage("show_qr_on_receipt") private var showQrOnReceipt = true

    // ── 5. Security & Advanced ───────────────────────────────────────────
    @AppStorage("require_manager_override_for_refund") private var requireManagerOverrideForRefund = true
    @AppStorage("escalation_auto_sound") private var autoSound = true
    @AppStorage("escalation_repeat_alert") private var repeatAlert = true
    @AppStorage("offline_sync_mode") private var offlineSyncMode = false
    @AppStorage("developer_mode_enabled") private var developerModeEnabled = false
    @AppStorage("gemini_api_key") private var geminiApiKey = ""

    var body: some View {
        ScrollView {
            VStack(spacing: APSpacing.lg) {

                // ═══════════════════════════════════════════════════════════
                // SECTION 1: ช่องทางการชำระเงิน
                // ═══════════════════════════════════════════════════════════
                VStack(alignment: .leading, spacing: 0) {
                    sectionHeader(
                        title: "ช่องทางการชำระเงิน (Payment Methods)",
                        icon: "creditcard.and.123",
                        color: .appAccent
                    )

                    toggleRow(
                        title: "รับชำระด้วยเงินสด (Cash)",
                        subtitle: "เปิดรับชำระค่าอาหารและสินค้าด้วยเงินสดบนหน้าจอ POS",
                        isOn: $cashEnabled
                    )
                    sectionDivider

                    toggleRow(
                        title: "รับชำระด้วยบัตรเครดิต (Credit Card)",
                        subtitle: "เปิดรับชำระผ่านเครื่องรูดบัตรหรือสแกนบัตร",
                        isOn: $cardEnabled
                    )
                    sectionDivider

                    toggleRow(
                        title: "รับชำระด้วย QR Code (PromptPay)",
                        subtitle: "สร้างคิวอาร์โค้ดสแกนจ่ายผ่านพร้อมเพย์อัตโนมัติ",
                        isOn: $qrEnabled
                    )
                    sectionDivider

                    toggleRow(
                        title: "รับชำระด้วย TrueMoney Wallet",
                        subtitle: "เปิดรับชำระผ่านบัญชีทรูมันนี่วอลเล็ท",
                        isOn: $trueMoneyEnabled
                    )
                    sectionDivider

                    toggleRow(
                        title: "รับชำระด้วย LINE Pay",
                        subtitle: "เปิดรับชำระผ่าน Rabbit LINE Pay",
                        isOn: $linePayEnabled
                    )
                    sectionDivider

                    toggleRow(
                        title: "รับชำระด้วย GrabPay",
                        subtitle: "เปิดรับชำระผ่าน GrabPay wallet",
                        isOn: $grabPayEnabled
                    )
                    sectionDivider

                    toggleRow(
                        title: "โหมดทดลองชำระเงิน (Payment Sandbox)",
                        subtitle: "จำลองการทำรายการชำระเงินเพื่อทดสอบโดยไม่หักเงินจริง",
                        isOn: $paymentTestMode,
                        tint: .orange
                    )
                }
                .apCard()

                // ═══════════════════════════════════════════════════════════
                // SECTION 2: ระบบ POS และผังโต๊ะ
                // ═══════════════════════════════════════════════════════════
                VStack(alignment: .leading, spacing: 0) {
                    sectionHeader(
                        title: "ระบบ POS และผังโต๊ะ (POS & Floorplan)",
                        icon: "banknote.fill",
                        color: .green
                    )

                    toggleRow(
                        title: "ระบบผังโต๊ะอาหาร (Table System)",
                        subtitle: "เปิดใช้งานระบบเลือกโต๊ะและสั่งอาหารแยกตามโต๊ะ หากปิดจะใช้โหมดขายปลีก Quick-Sale เท่านั้น",
                        isOn: $enableTableSystem
                    )
                    sectionDivider

                    toggleRow(
                        title: "ระบบสั่งอาหารออนไลน์ (Web Ordering)",
                        subtitle: "เปิดรับออเดอร์จากลูกค้าผ่าน QR Code / เว็บไซต์สั่งอาหารเข้ามาที่ POS อัตโนมัติ",
                        isOn: $enableWebOrdering
                    )
                    sectionDivider

                    toggleRow(
                        title: "ระบบภาษีมูลค่าเพิ่ม (VAT/Tax)",
                        subtitle: "คำนวณและบันทึกภาษีมูลค่าเพิ่ม (VAT 7%) ลงในบิลขาย",
                        isOn: $enableTax
                    )
                    sectionDivider

                    toggleRow(
                        title: "คิดค่าบริการ (Service Charge)",
                        subtitle: "คำนวณค่าบริการเพิ่มเติมตามร้อยละที่กำหนดสำหรับทานที่ร้าน",
                        isOn: $enableServiceCharge
                    )
                    sectionDivider

                    toggleRow(
                        title: "ระบบโปรโมชันอัตโนมัติ (Auto Promotions)",
                        subtitle: "คำนวณและใส่โปรโมชันที่เข้าเงื่อนไข (BOGO, ส่วนลด) ลงในตะกร้าโดยอัตโนมัติ",
                        isOn: $promotionsAutoApply
                    )
                    sectionDivider

                    toggleRow(
                        title: "เตือนวัตถุดิบต่ำแบบเรียลไทม์ (Stock Warning)",
                        subtitle: "แสดงไอคอนเตือน ⚠️ บนการ์ดเมนูอาหารในหน้า POS เมื่อส่วนผสมเหลือน้อยกว่าเกณฑ์คงเหลือ",
                        isOn: $enableRealtimeStockWarning
                    )
                }
                .apCard()

                // ═══════════════════════════════════════════════════════════
                // SECTION 3: ระบบจัดการครัว (KDS)
                // ═══════════════════════════════════════════════════════════
                VStack(alignment: .leading, spacing: 0) {
                    sectionHeader(
                        title: "ระบบจัดการครัว (Kitchen Display System)",
                        icon: "flame.fill",
                        color: .appTeal
                    )

                    toggleRow(
                        title: "แสดงรายการครัวอาหาร (Kitchen Station)",
                        subtitle: "ส่งและแสดงรายการออเดอร์ไปยังหน้าจอครัวหลัก (Kitchen)",
                        isOn: $kdsShowKitchen
                    )
                    sectionDivider

                    toggleRow(
                        title: "แสดงรายการบาร์เครื่องดื่ม (Bar Station)",
                        subtitle: "ส่งและแสดงรายการออเดอร์ไปยังหน้าจอบาร์เครื่องดื่ม (Bar/Beverage)",
                        isOn: $kdsShowBar
                    )
                    sectionDivider

                    toggleRow(
                        title: "เคลียร์ออเดอร์อัตโนมัติ (Auto-Complete)",
                        subtitle: "เปลี่ยนสถานะออเดอร์เป็น 'พร้อมเสิร์ฟ' อัตโนมัติเมื่อปรุงอาหารครบทุกรายการ",
                        isOn: $kdsAutoCompleteEnabled
                    )
                    sectionDivider

                    toggleRow(
                        title: "เสียงแจ้งเตือนออเดอร์ใหม่ (Alert Sounds)",
                        subtitle: "ส่งเสียงเตือนผ่านลำโพงเครื่องเมื่อมีออเดอร์ใหม่เข้ามาในหน้าจอครัว",
                        isOn: $kdsSoundEnabled
                    )
                }
                .apCard()

                // ═══════════════════════════════════════════════════════════
                // SECTION 4: เครื่องพิมพ์และใบเสร็จ
                // ═══════════════════════════════════════════════════════════
                VStack(alignment: .leading, spacing: 0) {
                    sectionHeader(
                        title: "เครื่องพิมพ์และใบเสร็จ (Printers & Receipts)",
                        icon: "printer.fill",
                        color: .orange
                    )

                    // ── Printer Hardware Enable/Disable ──
                    toggleRow(
                        title: "เครื่องพิมพ์ใบเสร็จ (Receipt Printer)",
                        subtitle: "เปิดใช้งานเครื่องพิมพ์สำหรับพิมพ์ใบเสร็จรับเงิน / ใบเสร็จย่อ",
                        isOn: $receiptPrinterEnabled
                    )
                    sectionDivider

                    toggleRow(
                        title: "เครื่องพิมพ์ครัว/บาร์/สติกเกอร์ (Kitchen Printer)",
                        subtitle: "เปิดใช้งานเครื่องพิมพ์สำหรับพิมพ์ตั๋วออเดอร์ครัว, บาร์เครื่องดื่ม และป้ายสติกเกอร์ฉลากสินค้า",
                        isOn: $kitchenPrinterEnabled
                    )
                    sectionDivider

                    // ── Receipt Behavior ──
                    toggleRow(
                        title: "ระงับพิมพ์ใบเสร็จทั้งหมด (Disable Receipt Printing)",
                        subtitle: "ข้ามคำสั่งพิมพ์ใบเสร็จชั่วคราวทั้งแบบอัตโนมัติและแบบกดปุ่ม (ไม่ส่งผลต่อตั๋วครัว)",
                        isOn: $disableReceiptPrinting,
                        tint: .red
                    )
                    sectionDivider

                    toggleRow(
                        title: "พิมพ์ใบเสร็จอัตโนมัติ (Auto Print on Payment)",
                        subtitle: "สั่งพิมพ์ใบเสร็จทันทีโดยอัตโนมัติเมื่อชำระเงินบนหน้าจอ POS สำเร็จ",
                        isOn: $autoPrintReceipt
                    )
                    sectionDivider

                    // ── Shift Reports ──
                    toggleRow(
                        title: "พิมพ์ใบเปิดกะอัตโนมัติ (Print Open Shift)",
                        subtitle: "พิมพ์สรุปข้อมูลเปิดกะ (ยอดเปิดลิ้นชัก, ชื่อแคชเชียร์) อัตโนมัติเมื่อเปิดกะใหม่",
                        isOn: $printOpenShift
                    )
                    sectionDivider

                    toggleRow(
                        title: "พิมพ์ Z-Report ปิดกะอัตโนมัติ (Print Close Shift)",
                        subtitle: "พิมพ์รายงานสรุปยอดขายปิดกะ (Z-Report) อัตโนมัติเมื่อทำการปิดกะ",
                        isOn: $printCloseShift
                    )
                    sectionDivider

                    // ── Receipt Content ──
                    toggleRow(
                        title: "แสดงโลโก้บนใบเสร็จ (Show Logo)",
                        subtitle: "พิมพ์รูปภาพโลโก้ร้านอาหารหรือข้อความ Header ที่หัวใบเสร็จ",
                        isOn: $showLogoOnReceipt
                    )
                    sectionDivider

                    toggleRow(
                        title: "แสดง QR Code บนใบเสร็จ (Show QR Code)",
                        subtitle: "พิมพ์ QR Code สำหรับการชำระเงินหรือตรวจสอบใบเสร็จดิจิทัลที่ท้ายใบเสร็จ",
                        isOn: $showQrOnReceipt
                    )
                }
                .apCard()

                // ═══════════════════════════════════════════════════════════
                // SECTION 5: ความปลอดภัยและระบบขั้นสูง
                // ═══════════════════════════════════════════════════════════
                VStack(alignment: .leading, spacing: 0) {
                    sectionHeader(
                        title: "ความปลอดภัยและระบบขั้นสูง (Security & Advanced)",
                        icon: "lock.shield.fill",
                        color: .red
                    )

                    toggleRow(
                        title: "อนุมัติคืนเงินโดยผู้จัดการ (Manager Override)",
                        subtitle: "การดำเนินการคืนเงิน (Refund) ต้องยืนยันรหัส PIN ผู้จัดการร้านทุกครั้ง",
                        isOn: $requireManagerOverrideForRefund
                    )
                    sectionDivider

                    toggleRow(
                        title: "เสียงเตือนออเดอร์ค้าง (Escalation Sound)",
                        subtitle: "ส่งเสียงเตือนต่อเนื่องเมื่อออเดอร์ไม่ได้รับบริการตามระยะเวลาที่ตั้งไว้",
                        isOn: $autoSound
                    )
                    sectionDivider

                    toggleRow(
                        title: "แจ้งเตือนส่งซ้ำ (Repeat Escalation Alerts)",
                        subtitle: "ส่งแจ้งเตือนซ้ำหลายรอบจนกว่าจะมีพนักงานเข้ามากดรับงาน",
                        isOn: $repeatAlert
                    )
                    sectionDivider

                    toggleRow(
                        title: "โหมดออฟไลน์ (Offline Sync Mode)",
                        subtitle: "ทำงานแบบออฟไลน์ — บันทึกข้อมูลลงอุปกรณ์ในเครื่องเท่านั้น ซิงก์เมื่อกลับมาออนไลน์",
                        isOn: $offlineSyncMode,
                        tint: .orange
                    )
                    sectionDivider

                    toggleRow(
                        title: "โหมดนักพัฒนา (Developer Mode)",
                        subtitle: "เปิดเมนูเครื่องมือนักพัฒนาสำหรับดีบัก แสดง Console Log และเมนูทดสอบภายใน",
                        isOn: $developerModeEnabled,
                        tint: .purple
                    )
                }
                .apCard()

                // ═══════════════════════════════════════════════════════════
                // SECTION 6: การตั้งค่าปัญญาประดิษฐ์ (AI & Gemini Config)
                // ═══════════════════════════════════════════════════════════
                VStack(alignment: .leading, spacing: 0) {
                    sectionHeader(
                        title: "ระบบประมวลผล AI & Gemini",
                        icon: "sparkles",
                        color: .appTeal
                    )

                    if offlineSyncMode {
                        HStack(spacing: 8) {
                            Image(systemName: "wifi.slash")
                                .foregroundColor(.orange)
                            Text("โหมดออฟไลน์เปิดอยู่: ฟังก์ชัน AI ทั้งหมดถูกปิดใช้งานชั่วคราว")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                        .padding(.vertical, 14)
                        .padding(.horizontal, 14)
                    } else {
                        textFieldRow(
                            title: "Gemini API Key",
                            subtitle: "ระบุรหัสเอพีไอคีย์สำหรับเชื่อมต่อประมวลผลเมนูและบิลใบเสร็จ (แชร์คีย์นี้ทุกหน้าใช้งาน AI)",
                            placeholder: "ป้อน Gemini API Key ของคุณ...",
                            text: $geminiApiKey,
                            isSecure: true
                        )
                    }
                }
                .apCard()

            }
            .padding()
        }
        .background(Color.appBackground)
        .navigationTitle("การควบคุมระบบ (System Control)")
        .navigationBarTitleDisplayMode(.inline)
        .apNavBar(background: Color.appBackground)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Reusable Components
    // ─────────────────────────────────────────────────────────────────────────

    private var sectionDivider: some View {
        Divider().background(Color.appDivider).padding(.leading, 12)
    }

    private func sectionHeader(title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 30, height: 30)
                .background(color.gradient)
                .clipShape(RoundedRectangle(cornerRadius: 7))

            Text(title)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(.textPrimary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appSurfaceHigh.opacity(0.6))
    }

    private func toggleRow(
        title: String,
        subtitle: String,
        isOn: Binding<Bool>,
        tint: Color = .appAccent
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.textPrimary)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(tint)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
    }

    private func textFieldRow(
        title: String,
        subtitle: String,
        placeholder: String,
        text: Binding<String>,
        isSecure: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.textPrimary)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if isSecure {
                SecureField(placeholder, text: text)
                    .font(.footnote)
                    .padding(10)
                    .background(Color.appBackground)
                    .cornerRadius(APRadius.sm)
                    .overlay(
                        RoundedRectangle(cornerRadius: APRadius.sm)
                            .stroke(Color.appDivider, lineWidth: 1)
                    )
                    .textInputAutocapitalization(.none)
                    .autocorrectionDisabled()
            } else {
                TextField(placeholder, text: text)
                    .font(.footnote)
                    .padding(10)
                    .background(Color.appBackground)
                    .cornerRadius(APRadius.sm)
                    .overlay(
                        RoundedRectangle(cornerRadius: APRadius.sm)
                            .stroke(Color.appDivider, lineWidth: 1)
                    )
                    .textInputAutocapitalization(.none)
                    .autocorrectionDisabled()
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
    }
}
