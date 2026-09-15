// InventoryHubViews.swift
// AlphaPos — Counts / More / Purchasing hubs (dense enterprise chrome)

import SwiftUI
import SwiftData

// MARK: - Counts Hub (toolbar entry + full audit list)

struct InventoryCountsHubView: View {
    @Binding var showingCycleCount: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: APSpacing.sm) {
                Text("inventory_stock_audit".t)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.textPrimary)
                Spacer(minLength: 0)
                Button {
                    showingCycleCount = true
                } label: {
                    Label("inventory_cycle_count".t, systemImage: "checklist")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.appTeal)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.appTeal.opacity(0.12))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, APSpacing.md)
            .padding(.vertical, 8)
            .background(Color.appSurface)
            .overlay(Rectangle().fill(Color.appDivider).frame(height: 1), alignment: .bottom)

            StockAuditView()
        }
    }
}

// MARK: - Purchasing & Suppliers Hub

enum PurchasingSubTab: Int, CaseIterable, Identifiable {
    case purchaseOrders = 0
    case suppliers = 1

    var id: Int { rawValue }

    func title(isThai: Bool) -> String {
        switch self {
        case .purchaseOrders: return isThai ? "ใบสั่งซื้อสินค้า (PO)" : "Purchase Orders"
        case .suppliers: return isThai ? "ผู้จัดจำหน่าย (Suppliers)" : "Suppliers"
        }
    }

    var icon: String {
        switch self {
        case .purchaseOrders: return "doc.text.fill"
        case .suppliers: return "building.2.fill"
        }
    }
}

struct InventoryPurchasingHubView: View {
    let activeBranch: Branch?
    @Binding var showingDocumentScanner: Bool
    @EnvironmentObject private var lm: LocalizationManager
    @State private var selectedTab: PurchasingSubTab = .purchaseOrders

    var body: some View {
        VStack(spacing: 0) {
            // Sub-navigation bar
            HStack(spacing: 12) {
                Picker("", selection: $selectedTab) {
                    ForEach(PurchasingSubTab.allCases) { tab in
                        Label(tab.title(isThai: lm.currentLanguage == .thai), systemImage: tab.icon)
                            .tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 420)

                Spacer()
            }
            .padding(.horizontal, APSpacing.md)
            .padding(.vertical, 8)
            .background(Color.appSurface)
            .overlay(Rectangle().fill(Color.appDivider).frame(height: 1), alignment: .bottom)

            // Content
            Group {
                switch selectedTab {
                case .purchaseOrders:
                    if let branch = activeBranch {
                        PurchaseOrderManagerView(
                            activeBranch: branch,
                            embedded: true,
                            onScanDocument: { showingDocumentScanner = true }
                        )
                    } else {
                        ContentUnavailableView(
                            "manage_branches".t,
                            systemImage: "building.2",
                            description: Text("inventory_select_branch_first".t)
                        )
                    }
                case .suppliers:
                    SupplierManagerView()
                }
            }
        }
    }
}
