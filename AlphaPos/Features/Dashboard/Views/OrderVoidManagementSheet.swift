//
//  OrderVoidManagementSheet.swift
//  AlphaPos
//
//  Created by Antigravity on 2026-09-03.
//

import SwiftUI
import SwiftData

struct OrderVoidManagementSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var lm: LocalizationManager
    @EnvironmentObject private var sessionManager: AppSessionManager

    var initialOrder: Order? = nil
    var onVoidCompleted: (() -> Void)? = nil

    @Query(
        filter: #Predicate<Order> { !$0.isDeleted && $0.status != "cancelled" },
        sort: \Order.createdAt,
        order: .reverse
    )
    private var activeOrders: [Order]

    @State private var selectedOrder: Order? = nil
    @State private var searchText = ""
    @State private var selectedReason = "duplicate_entry"
    @State private var customReason = ""
    @State private var restockInventory = true
    @State private var showingManagerPinSheet = false
    @State private var authorizedManagerId: UUID? = nil
    @State private var isProcessing = false
    @State private var successMessage: String? = nil

    private let reasons: [(id: String, th: String, en: String)] = [
        ("duplicate_entry", "คีย์ออเดอร์ซ้ำ / แก้ไขข้อผิดพลาด", "Duplicate order / Error"),
        ("customer_cancelled", "ลูกค้าขอยกเลิก / เปลี่ยนใจ", "Customer cancelled"),
        ("wrong_table_or_items", "คีย์ผิดโต๊ะ / ผิดเมนู", "Wrong table or items"),
        ("amount_mismatch", "ยอดเงินไม่ตรง / ลบเพื่อคีย์ใหม่", "Amount mismatch"),
        ("other", "อื่นๆ (ระบุหมายเหตุ)", "Other (specify note)")
    ]

    private var filteredOrders: [Order] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty {
            return Array(activeOrders.prefix(25))
        }
        return activeOrders.filter { order in
            order.orderNumber.lowercased().contains(trimmed) ||
            order.cashierName.lowercased().contains(trimmed) ||
            (order.tableSession?.table?.tableNumber.lowercased().contains(trimmed) ?? false) ||
            (order.deliveryBrand?.lowercased().contains(trimmed) ?? false) ||
            String(format: "%.0f", order.recognizedNetTotal).contains(trimmed)
        }
    }

    private var currentReasonText: String {
        let defaultText = reasons.first(where: { $0.id == selectedReason })?.th ?? selectedReason
        if selectedReason == "other", !customReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return customReason.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return defaultText
    }

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                // Left Column: Order Selection
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.textTertiary)
                        TextField(lm.currentLanguage == .thai ? "ค้นหาเลขบิล, โต๊ะ, แคชเชียร์..." : "Search bill #, table, cashier...", text: $searchText)
                            .textFieldStyle(.plain)
                        if !searchText.isEmpty {
                            Button { searchText = "" } label: {
                                Image(systemName: "xmark.circle.fill").foregroundColor(.textTertiary)
                            }
                        }
                    }
                    .padding(10)
                    .background(Color.appSurfaceHigh)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    Text(lm.currentLanguage == .thai ? "เลือกออเดอร์ที่ต้องการยกเลิก" : "Select order to void")
                        .font(.caption.bold())
                        .foregroundColor(.textSecondary)

                    if filteredOrders.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.system(size: 30))
                                .foregroundColor(.textTertiary)
                            Text(lm.currentLanguage == .thai ? "ไม่พบบิลที่ค้นหา" : "No orders found")
                                .font(.caption)
                                .foregroundColor(.textTertiary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(filteredOrders) { order in
                                    orderRow(order)
                                }
                            }
                        }
                    }
                }
                .padding()
                .frame(width: 320)
                .background(Color.appSurface)

                Divider().background(Color.appDivider)

                // Right Column: Order Void Action & Confirmation
                if let order = selectedOrder {
                    orderDetailView(order)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "arrow.left.circle")
                            .font(.system(size: 40))
                            .foregroundColor(.textTertiary)
                        Text(lm.currentLanguage == .thai ? "โปรดเลือกออเดอร์จากรายการทางซ้ายมือเพื่อจัดการ" : "Please select an order from the list")
                            .font(.subheadline)
                            .foregroundColor(.textTertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.appBackground)
                }
            }
            .navigationTitle(lm.currentLanguage == .thai ? "จัดการยกเลิกบิล (Void Order)" : "Void Order Management")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(lm.currentLanguage == .thai ? "ปิด" : "Close") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                if let initial = initialOrder {
                    selectedOrder = initial
                } else if selectedOrder == nil, let first = filteredOrders.first {
                    selectedOrder = first
                }
            }
            .sheet(isPresented: $showingManagerPinSheet) {
                ManagerPINVerificationSheet(
                    isPresented: $showingManagerPinSheet,
                    onSuccess: {
                        let managerId = authorizedManagerId
                        authorizedManagerId = nil
                        executeVoid(authorizedManagerId: managerId)
                    },
                    onAuthorizedManager: { manager in
                        authorizedManagerId = manager.id
                    }
                )
            }
        }
    }

    // MARK: - Subviews

    private func orderRow(_ order: Order) -> some View {
        let isSelected = selectedOrder?.id == order.id
        return Button {
            selectedOrder = order
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("#\(order.orderNumber)")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(isSelected ? .white : .textPrimary)
                    Spacer()
                    Text("฿\(order.recognizedNetTotal.formatted(.number.precision(.fractionLength(2))))")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(isSelected ? .white : .appAccent)
                }

                HStack(spacing: 6) {
                    if let tableNo = order.tableSession?.table?.tableNumber {
                        Label(tableNo, systemImage: "table.furniture")
                            .font(.system(size: 10))
                    } else if let brand = order.deliveryBrand, !brand.isEmpty {
                        Label(brand, systemImage: "scooter")
                            .font(.system(size: 10))
                    } else {
                        Label(order.orderType.capitalized, systemImage: "takeoutbag.and.cup.and.straw")
                            .font(.system(size: 10))
                    }
                    Spacer()
                    Text(order.createdAt.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 10, design: .monospaced))
                }
                .foregroundColor(isSelected ? .white.opacity(0.8) : .textTertiary)
            }
            .padding(10)
            .background(isSelected ? Color.appAccent : Color.appSurfaceHigh)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func orderDetailView(_ order: Order) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Header Summary Banner
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text("#\(order.orderNumber)")
                                    .font(.title3.bold())
                                    .foregroundColor(.textPrimary)

                                Text(order.isSettled ? (lm.currentLanguage == .thai ? "ชำระเงินแล้ว" : "Paid") : (lm.currentLanguage == .thai ? "ยังไม่ชำระ" : "Unpaid"))
                                    .font(.caption2.bold())
                                    .foregroundColor(order.isSettled ? .appTeal : .appAmber)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background((order.isSettled ? Color.appTeal : Color.appAmber).opacity(0.12))
                                    .clipShape(Capsule())
                            }

                            Text("เวลา: \(order.createdAt.formatted(date: .abbreviated, time: .shortened)) · แคชเชียร์: \(order.cashierName ?? "-")")
                                .font(.caption)
                                .foregroundColor(.textTertiary)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text(lm.currentLanguage == .thai ? "ยอดสุทธิ" : "Net Total")
                                .font(.caption2)
                                .foregroundColor(.textSecondary)
                            Text("฿\(order.recognizedNetTotal.formatted(.number.precision(.fractionLength(2))))")
                                .font(.system(size: 22, weight: .bold, design: .monospaced))
                                .foregroundColor(.textPrimary)
                        }
                    }
                    .padding()
                    .background(Color.appSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    // Items Breakdown
                    VStack(alignment: .leading, spacing: 8) {
                        Text(lm.currentLanguage == .thai ? "รายการสินค้าในบิล (\(order.items.count) รายการ)" : "Order Items (\(order.items.count))")
                            .font(.caption.bold())
                            .foregroundColor(.textSecondary)

                        VStack(spacing: 0) {
                            ForEach(order.items.filter { !$0.isDeleted }) { item in
                                HStack {
                                    Text("\(item.quantity)x")
                                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                                        .foregroundColor(.appAccent)
                                        .frame(width: 30, alignment: .leading)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.itemName)
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(.textPrimary)
                                        if !item.modifiers.isEmpty {
                                            Text(item.modifiers.map { "\($0.modifier?.name ?? "") (+฿\($0.price.formatted(.number.precision(.fractionLength(0)))))" }.joined(separator: ", "))
                                                .font(.system(size: 10))
                                                .foregroundColor(.textTertiary)
                                        }
                                    }

                                    Spacer()

                                    Text("฿\(item.subtotal.formatted(.number.precision(.fractionLength(2))))")
                                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                        .foregroundColor(.textSecondary)
                                }
                                .padding(.vertical, 6)
                                Divider().background(Color.appDivider)
                            }
                        }
                        .padding()
                        .background(Color.appSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    // Void Settings: Reason & Restock
                    VStack(alignment: .leading, spacing: 14) {
                        Text(lm.currentLanguage == .thai ? "การตั้งค่าการยกเลิกบิล" : "Void Configuration")
                            .font(.caption.bold())
                            .foregroundColor(.textSecondary)

                        // Reason Picker
                        VStack(alignment: .leading, spacing: 6) {
                            Text(lm.currentLanguage == .thai ? "สาเหตุในการยกเลิกบิล:" : "Reason for void:")
                                .font(.caption2)
                                .foregroundColor(.textSecondary)

                            Picker("", selection: $selectedReason) {
                                ForEach(reasons, id: \.id) { r in
                                    Text(lm.currentLanguage == .thai ? r.th : r.en).tag(r.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.appSurfaceHigh)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                            if selectedReason == "other" {
                                TextField(lm.currentLanguage == .thai ? "ระบุเหตุผลเพิ่มเติม..." : "Specify reason...", text: $customReason)
                                    .textFieldStyle(.roundedBorder)
                                    .padding(.top, 4)
                            }
                        }

                        Divider().background(Color.appDivider)

                        // Restock Toggle
                        Toggle(isOn: $restockInventory) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(lm.currentLanguage == .thai ? "คืนสต๊อกสินค้าเข้าคลัง (Restock Inventory)" : "Return Stock to Inventory")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.textPrimary)
                                Text(lm.currentLanguage == .thai
                                     ? "คืนวัตถุดิบและรายการอาหารเข้าสต๊อกทันที เหมาะสำหรับบิลที่คีย์ซ้ำหรือไม่ได้ทำอาหารจริง"
                                     : "Restores ingredients and items into stock. Ideal for duplicate orders.")
                                    .font(.caption2)
                                    .foregroundColor(.textTertiary)
                            }
                        }
                        .toggleStyle(SwitchToggleStyle(tint: .appAccent))
                        .padding(10)
                        .background(restockInventory ? Color.appTeal.opacity(0.08) : Color.appSurfaceHigh)
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                        // Money Reversal Note
                        if order.isSettled {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.uturn.backward.circle.fill")
                                    .foregroundColor(.appAmber)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(lm.currentLanguage == .thai ? "คืนเงินและปรับยอดยกเลิกอัตโนมัติ" : "Automatic Payment Reversal")
                                        .font(.caption.bold())
                                        .foregroundColor(.textPrimary)
                                    Text(lm.currentLanguage == .thai
                                         ? "ระบบจะออกรายการคืนเงิน (Refund) เต็มจำนวน ฿\(order.recognizedNetTotal.formatted(.number.precision(.fractionLength(2)))) เพื่อหักลบยอดขายและยอดชำระออกจากรายงาน"
                                         : "Full refund of ฿\(order.recognizedNetTotal.formatted(.number.precision(.fractionLength(2)))) will be issued to reconcile sales.")
                                        .font(.caption2)
                                        .foregroundColor(.textSecondary)
                                }
                            }
                            .padding(10)
                            .background(Color.appAmber.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .padding()
                    .background(Color.appSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding()
            }

            Divider().background(Color.appDivider)

            // Bottom Action Bar
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(lm.currentLanguage == .thai ? "ต้องใช้รหัสผ่านผู้จัดการ (Manager PIN)" : "Manager PIN Required")
                        .font(.caption2)
                        .foregroundColor(.textTertiary)
                    Text(lm.currentLanguage == .thai ? "เพื่อความปลอดภัยในการยกเลิกยอดขาย" : "For loss prevention and audit trail")
                        .font(.caption2)
                        .foregroundColor(.textTertiary)
                }

                Spacer()

                Button {
                    showingManagerPinSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.bin.fill")
                        Text(lm.currentLanguage == .thai ? "ยกเลิกบิลนี้ (Void Order)" : "Void This Order")
                    }
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Color.appRose)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(isProcessing)
            }
            .padding(14)
            .background(Color.appSurface)
        }
        .background(Color.appBackground)
    }

    // MARK: - Actions

    private func executeVoid(authorizedManagerId: UUID? = nil) {
        guard let order = selectedOrder, !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }

        let managerId = authorizedManagerId ?? sessionManager.currentStaffSession?.employeeId

        order.voidEntireOrder(
            reason: currentReasonText,
            restockInventory: restockInventory,
            managerEmployeeId: managerId,
            in: modelContext
        )

        onVoidCompleted?()
        dismiss()
    }
}
