// HeldOrdersView.swift
// AlphaPos — Hold / Recall Orders Management

import SwiftUI
import SwiftData

// MARK: - Held Orders View

struct HeldOrdersView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Query(
        filter: #Predicate<Order> { order in
            order.status == "held" && !order.isDeleted
        },
        sort: \Order.createdAt,
        order: .reverse
    )
    private var heldOrders: [Order]
    
    let onRecall: (Order) -> Void
    
    @State private var orderToCancel: Order?
    @State private var showCancelConfirmation = false
    @State private var animateCards = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                
                if heldOrders.isEmpty {
                    emptyState
                } else {
                    ordersGrid
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: APSpacing.sm) {
                        Image(systemName: "pause.circle.fill")
                            .foregroundColor(.appAccent)
                        Text("held_orders_title".t)
                            .font(.headline).fontWeight(.bold)
                            .foregroundColor(.textPrimary)
                        
                        if !heldOrders.isEmpty {
                            Text("\(heldOrders.count)")
                                .font(.caption2.weight(.bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.appAccent)
                                .clipShape(Capsule())
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("close_btn_label".t) {
                        APHaptic.trigger()
                        dismiss()
                    }
                    .foregroundColor(.appAccent)
                    .fontWeight(.semibold)
                }
            }
            .toolbarBackground(Color.appSurface, for: .navigationBar)
            .alert("Cancel Order?", isPresented: $showCancelConfirmation, presenting: orderToCancel) { order in
                Button("Keep", role: .cancel) {
                    orderToCancel = nil
                }
                Button("Void Order", role: .destructive) {
                    voidOrder(order)
                }
            } message: { order in
                Text(String(format: "held_orders_void_confirm_template".t, order.orderNumber))
            }
            .onAppear {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.75)) {
                    animateCards = true
                }
            }
        }
        .apColorScheme()
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: APSpacing.lg) {
            ZStack {
                Circle()
                    .fill(Color.appSurface)
                    .frame(width: 100, height: 100)
                Image(systemName: "tray")
                    .font(.system(size: 44))
                    .foregroundStyle(APGradient.accent)
            }
            
            Text("held_orders_none".t)
                .font(.title2).fontWeight(.bold)
                .foregroundColor(.textPrimary)
            
            Text("held_orders_none_desc".t)
                .font(.subheadline)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Orders Grid
    
    private var ordersGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 320, maximum: 420), spacing: APSpacing.md)],
                spacing: APSpacing.md
            ) {
                ForEach(Array(heldOrders.enumerated()), id: \.element.id) { index, order in
                    heldOrderCard(order: order, index: index)
                        .transition(.asymmetric(
                            insertion: .scale.combined(with: .opacity),
                            removal: .scale.combined(with: .opacity)
                        ))
                }
            }
            .padding(APSpacing.lg)
        }
    }
    
    // MARK: - Held Order Card
    
    private func heldOrderCard(order: Order, index: Int) -> some View {
        let holdDuration = timeHeldString(since: order.createdAt)
        let activeItems = order.items.filter { !$0.isDeleted }
        let itemsSummary = activeItems.prefix(4).compactMap { item -> String? in
            guard let name = item.menuItem?.name else { return nil }
            return "\(item.quantity)× \(name)"
        }
        let remainingCount = max(0, activeItems.count - 4)
        
        return VStack(spacing: 0) {
            // Card header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(order.orderNumber)
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(.textPrimary)
                    
                    HStack(spacing: APSpacing.sm) {
                        Label(holdDuration, systemImage: "clock")
                            .font(.caption)
                            .foregroundColor(.appAmber)
                        
                        if let table = order.tableSession?.table?.tableNumber {
                            Label("Table \(table)", systemImage: "tablecells")
                                .font(.caption)
                                .foregroundColor(.textSecondary)
                        }
                    }
                }
                
                Spacer()
                
                APBadge(text: "HELD", color: Color(hex: "F59E0B"), icon: "pause.fill")
            }
            .padding(APSpacing.md)
            .background(Color.appSurfaceHigh.opacity(0.5))
            
            Divider().background(Color.appDivider)
            
            // Items list
            VStack(alignment: .leading, spacing: APSpacing.xs) {
                ForEach(itemsSummary, id: \.self) { item in
                    HStack(spacing: APSpacing.sm) {
                        Circle()
                            .fill(Color.appAccent.opacity(0.5))
                            .frame(width: 5, height: 5)
                        Text(item)
                            .font(.system(size: 13))
                            .foregroundColor(.textSecondary)
                    }
                }
                
                if remainingCount > 0 {
                    Text("+\(remainingCount) more item\(remainingCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.textTertiary)
                        .padding(.leading, 13)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(APSpacing.md)
            
            Divider().background(Color.appDivider)
            
            // Footer with total and actions
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("pos_total".t)
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                    Text("฿\(order.total, specifier: "%.2f")")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.textPrimary)
                }
                
                Spacer()
                
                HStack(spacing: APSpacing.sm) {
                    // Cancel button
                    Button(action: {
                        orderToCancel = order
                        showCancelConfirmation = true
                        APHaptic.trigger()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .bold))
                            Text("btn_void".t)
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundColor(.appRose)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.appRose.opacity(0.1))
                        .cornerRadius(APRadius.sm)
                        .overlay(
                            RoundedRectangle(cornerRadius: APRadius.sm)
                                .stroke(Color.appRose.opacity(0.25), lineWidth: 1)
                        )
                    }
                    
                    // Recall button
                    Button(action: {
                        APHaptic.trigger()
                        onRecall(order)
                        dismiss()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 11, weight: .bold))
                            Text("btn_recall".t)
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: APRadius.sm, style: .continuous)
                                .fill(APGradient.accent)
                        )
                        .shadow(color: Color.appAccent.opacity(0.3), radius: 6, y: 2)
                    }
                }
            }
            .padding(APSpacing.md)
        }
        .background(
            RoundedRectangle(cornerRadius: APRadius.lg, style: .continuous)
                .fill(Color.appSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: APRadius.lg, style: .continuous)
                        .fill(APGradient.cardShimmer)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: APRadius.lg, style: .continuous)
                        .stroke(Color.appBorderSubtle, lineWidth: 1)
                )
        )
        .shadow(color: APShadow.card.color, radius: APShadow.card.radius, x: APShadow.card.x, y: APShadow.card.y)
        .clipShape(RoundedRectangle(cornerRadius: APRadius.lg, style: .continuous))
        .offset(y: animateCards ? 0 : 40)
        .opacity(animateCards ? 1 : 0)
        .animation(
            .spring(response: 0.5, dampingFraction: 0.75).delay(Double(index) * 0.05),
            value: animateCards
        )
    }
    
    // MARK: - Actions
    
    private func voidOrder(_ order: Order) {
        // Audit log
        let auditLog = AuditLog(
            actionType: "order_void",
            details: "Voided held order \(order.orderNumber) — Total: ฿\(String(format: "%.2f", order.total))",
            originalValue: order.total,
            newValue: 0.0
        )
        modelContext.insert(auditLog)
        
        // Mark order and items cancelled
        order.status = "cancelled"
        order.isSynced = false
        order.updatedAt = Date()
        
        for item in order.items {
            item.status = "cancelled"
            item.isSynced = false
            item.updatedAt = Date()
        }
        
        try? modelContext.save()
        
        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
        
        orderToCancel = nil
        APHaptic.trigger()
    }
    
    // MARK: - Helpers
    
    private func timeHeldString(since date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        let minutes = Int(interval / 60)
        
        if minutes < 1 {
            return "Just now"
        } else if minutes < 60 {
            return "\(minutes)m ago"
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return "\(hours)h \(remainingMinutes)m ago"
        }
    }
}
