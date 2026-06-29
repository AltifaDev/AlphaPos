import SwiftUI
import Combine

enum AlertPriority: Int, Comparable {
    case low = 0
    case medium = 1
    case high = 2
    
    var labelKey: String {
        switch self {
        case .low: return "priority_low"
        case .medium: return "priority_medium"
        case .high: return "priority_high"
        }
    }
    
    var color: Color {
        switch self {
        case .low: return .textTertiary
        case .medium: return .appAmber
        case .high: return .appRose
        }
    }
    
    static func < (lhs: AlertPriority, rhs: AlertPriority) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

enum AlertType {
    case serviceRequest(ServiceRequest)
    case order(Order)
}

struct StaffAlert: Identifiable {
    var id: String {
        switch type {
        case .serviceRequest(let req): return "req-\(req.id)"
        case .order(let order): return "order-\(order.id)"
        }
    }
    
    let type: AlertType
    let tableNumber: String
    let title: String
    let subtitle: String
    let timestamp: Date
    let priority: AlertPriority
    let isActive: Bool
}

struct NotificationListView: View {
    private var networkService = NetworkService.shared
    @AppStorage("app_language") private var appLanguage = "en"
    
    @State private var isLoading = false
    @State private var expandedTables = Set<String>()
    @State private var processingAlertIds = Set<String>()
    @State private var readAlertIds = Set<String>()
    @StateObject private var deepLinkRouter = DeepLinkRouter.shared

    private var alerts: [StaffAlert] {
        var list: [StaffAlert] = []
        
        // Map service requests
        for req in networkService.serviceRequests {
            let isActive = req.status == "pending"
            
            let table = networkService.tables.first(where: { $0.tableNumber == req.tableNumber })
            let isTableOccupied = table?.status.lowercased() == "occupied"
            
            let belongsToSession: Bool
            if isTableOccupied, let sessionStartedAtStr = table?.sessionStartedAt,
               let sessionDate = isoStringToDate(sessionStartedAtStr),
               let reqDate = isoStringToDate(req.createdAt) {
                belongsToSession = reqDate >= sessionDate
            } else {
                belongsToSession = false
            }
            
            guard isActive || belongsToSession else { continue }
            
            let isBill = req.requestType.lowercased().contains("bill") || req.requestType.lowercased().contains("check")
            let priority: AlertPriority = isBill ? .high : .medium
            let date = isoStringToDate(req.createdAt) ?? Date()
            
            list.append(StaffAlert(
                type: .serviceRequest(req),
                tableNumber: req.tableNumber,
                title: String(format: "table_label".localized(for: appLanguage), req.tableNumber),
                subtitle: req.requestType,
                timestamp: date,
                priority: priority,
                isActive: isActive
            ))
        }
        
        // Map orders
        for order in networkService.orders {
            // 1. Filter out empty orders
            guard !order.items.isEmpty else { continue }
            
            // 2. Filter out orders older than 24 hours unless they belong to an active session
            let date = isoStringToDate(order.createdAt) ?? Date()
            let activeSessionTokens = Set(networkService.tables.compactMap { $0.sessionToken })
            let isSessionActive = order.sessionToken.map { activeSessionTokens.contains($0) } ?? false
            
            let statusLower = order.status.lowercased()
            // Waiters need alerts for preparing/cooking and ready orders.
            // Only cancelled orders are filtered out.
            guard statusLower != "cancelled" else { continue }
            
            let isActive = statusLower == "ready" || statusLower == "preparing" || statusLower == "cooking"
            
            guard isActive || isSessionActive else { continue }
            
            let priority: AlertPriority = statusLower == "ready" ? .high : .medium
            
            let itemsSummary = order.items.map { "\($0.quantity)x \($0.name)" }.joined(separator: ", ")
            let statusLabel = statusLower == "ready" ? "order_ready".localized(for: appLanguage) :
                              (statusLower == "preparing" || statusLower == "cooking") ? "order_preparing".localized(for: appLanguage) :
                              statusLower == "served" ? "order_served".localized(for: appLanguage) :
                              "order_completed".localized(for: appLanguage)
            
            list.append(StaffAlert(
                type: .order(order),
                tableNumber: order.tableNumber,
                title: "\(statusLabel) — \(order.orderNumber)",
                subtitle: itemsSummary,
                timestamp: date,
                priority: priority,
                isActive: isActive
            ))
        }
        
        return list
    }
    
    private var activeAlerts: [StaffAlert] {
        alerts.filter { $0.isActive }
            .sorted { (lhs, rhs) in
                if lhs.priority != rhs.priority {
                    return lhs.priority.rawValue > rhs.priority.rawValue
                }
                return lhs.timestamp > rhs.timestamp
            }
    }
    
    private var activeAlertsByTable: [(tableNumber: String, alerts: [StaffAlert])] {
        let grouped = Dictionary(grouping: activeAlerts, by: { $0.tableNumber })
        return grouped.map { (tableNumber: $0.key, alerts: $0.value) }
            .sorted { (lhs, rhs) in
                // Sort by highest priority alert first
                let lhsMaxPriority = lhs.alerts.map { $0.priority }.max() ?? .low
                let rhsMaxPriority = rhs.alerts.map { $0.priority }.max() ?? .low
                if lhsMaxPriority != rhsMaxPriority {
                    return lhsMaxPriority.rawValue > rhsMaxPriority.rawValue
                }
                
                // If priority is same, sort by newest alert timestamp
                let lhsNewest = lhs.alerts.map { $0.timestamp }.max() ?? Date.distantPast
                let rhsNewest = rhs.alerts.map { $0.timestamp }.max() ?? Date.distantPast
                return lhsNewest > rhsNewest
            }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                                VStack(spacing: 0) {
                    if isLoading && activeAlerts.isEmpty {
                        ProgressView().tint(.appAccent).frame(maxHeight: .infinity)
                    } else if activeAlerts.isEmpty {
                        VStack(spacing: APSpacing.md) {
                            Image(systemName: "bell.slash.fill")
                                .font(.system(size: 48)).foregroundColor(.textTertiary)
                            Text("no_pending_requests".localized(for: appLanguage))
                                .font(.headline).foregroundColor(.textSecondary)
                            Text("pending_requests_sub".localized(for: appLanguage))
                                .font(.caption).foregroundColor(.textTertiary)
                                .multilineTextAlignment(.center).frame(maxWidth: 260)
                        }
                        .frame(maxHeight: .infinity)
                    } else {
                        ScrollViewReader { scrollProxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                if !activeAlerts.isEmpty {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("active_alerts_section".localized(for: appLanguage))
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(.textSecondary)
                                            .textCase(.uppercase)
                                            .padding(.horizontal, 16)
                                            .padding(.top, 8)
                                        
                                        ForEach(activeAlertsByTable, id: \.tableNumber) { group in
                                            tableGroupCard(tableNumber: group.tableNumber, alerts: group.alerts)
                                                .padding(.horizontal, 16)
                                                .id("alert-group-\(group.tableNumber)")
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 8)
                        }
                        .onReceive(deepLinkRouter.$scrollToAlertId.compactMap { $0 }) { alertId in
                            guard !alertId.isEmpty else { return }
                            withAnimation(.easeInOut(duration: 0.4)) {
                                scrollProxy.scrollTo("alert-\(alertId)", anchor: .center)
                            }
                            // Clear after scroll
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                deepLinkRouter.clearAlertScroll()
                            }
                        }
                        } // end ScrollViewReader
                    }
                }
            }
            .navigationTitle("alerts".localized(for: appLanguage))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        StaffMessagingView()
                    } label: {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .foregroundColor(.appAccent)
                            .overlay(alignment: .topTrailing) {
                                MessagingBadgeView(count: 0)
                                    .offset(x: 8, y: -6)
                            }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: loadRequests) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.appAccent)
                    }
                }
            }
        }
        .onAppear {
            loadRequests()
        }
    }
    
    private func tableGroupCard(tableNumber: String, alerts: [StaffAlert]) -> some View {
        let isCollapsed = !expandedTables.contains(tableNumber)
        
        let requestsCount = alerts.filter {
            if case .serviceRequest = $0.type { return true }
            return false
        }.count
        
        let readyCount = alerts.filter {
            if case .order(let order) = $0.type, order.status.lowercased() == "ready" { return true }
            return false
        }.count
        
        let preparingCount = alerts.filter {
            if case .order(let order) = $0.type, order.status.lowercased() == "preparing" { return true }
            return false
        }.count
        
        let hasHighPriority = alerts.contains(where: { $0.priority == .high })
        let highlightColor = hasHighPriority ? Color.appRose : Color.appAccent
        
        let unreadAlerts = alerts.filter { $0.isActive && !readAlertIds.contains($0.id) }
        let hasUnread = !unreadAlerts.isEmpty
        
        let cardBgColor = hasUnread ? (hasHighPriority ? Color.appRose.opacity(0.06) : Color.appAccent.opacity(0.06)) : Color.appSurface
        let cardStrokeColor = hasUnread ? (hasHighPriority ? Color.appRose.opacity(0.4) : Color.appAccent.opacity(0.4)) : (hasHighPriority ? Color.appRose.opacity(0.3) : Color.appBorderSubtle)
        
        let actionText: String
        if readyCount > 0 && requestsCount > 0 {
            actionText = "serve_action".localized(for: appLanguage) + " & " + "resolve".localized(for: appLanguage)
        } else if readyCount > 0 {
            actionText = "serve_action".localized(for: appLanguage) + " " + "all".localized(for: appLanguage)
        } else {
            actionText = "resolve".localized(for: appLanguage) + " " + "all".localized(for: appLanguage)
        }
        
        return VStack(spacing: 0) {
            HStack(spacing: APSpacing.sm) {
                Button(action: {
                    APHaptic.trigger()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        if expandedTables.contains(tableNumber) {
                            expandedTables.remove(tableNumber)
                        } else {
                            expandedTables.insert(tableNumber)
                            // Mark all active alerts for this table as read
                            for alert in alerts {
                                if alert.isActive {
                                    readAlertIds.insert(alert.id)
                                }
                            }
                        }
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                            .font(.footnote)
                            .foregroundColor(.textSecondary)
                        
                        Text(String(format: "table_label".localized(for: appLanguage), tableNumber))
                            .font(.system(size: 14, weight: .black))
                            .foregroundColor(.textPrimary)
                        
                        if hasUnread {
                            Circle()
                                .fill(hasHighPriority ? Color.appRose : Color.appAccent)
                                .frame(width: 8, height: 8)
                        }
                        
                        HStack(spacing: 4) {
                            if requestsCount > 0 {
                                HStack(spacing: 2) {
                                    Image(systemName: "bell.fill")
                                        .font(.system(size: 10))
                                    Text("\(requestsCount)")
                                        .font(.system(size: 10, weight: .bold))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.appAmber)
                                .cornerRadius(8)
                            }
                            
                            if readyCount > 0 {
                                HStack(spacing: 2) {
                                    Image(systemName: "fork.knife")
                                        .font(.system(size: 10))
                                    Text("\(readyCount)")
                                        .font(.system(size: 10, weight: .bold))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.appAccent)
                                .cornerRadius(8)
                            }
                            
                            if preparingCount > 0 {
                                HStack(spacing: 2) {
                                    Image(systemName: "hourglass")
                                        .font(.system(size: 10))
                                    Text("\(preparingCount)")
                                        .font(.system(size: 10, weight: .bold))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.textSecondary)
                                .cornerRadius(8)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                let actableAlerts = alerts.filter {
                    switch $0.type {
                    case .serviceRequest(let req): return req.status == "pending"
                    case .order(let order): return order.status.lowercased() == "ready"
                    }
                }
                
                if !actableAlerts.isEmpty {
                    let isProcessing = actableAlerts.contains(where: { processingAlertIds.contains($0.id) })
                    Button(action: {
                        resolveAllForTable(actableAlerts)
                    }) {
                        if isProcessing {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.7)
                                .frame(width: 40, height: 12)
                        } else {
                            Text(actionText)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(isProcessing ? Color.gray : highlightColor)
                    .cornerRadius(12)
                    .disabled(isProcessing)
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, APSpacing.md)
            .padding(.vertical, APSpacing.sm)
            
            if !isCollapsed {
                Divider()
                    .padding(.horizontal, APSpacing.md)
                
                VStack(spacing: 0) {
                    ForEach(alerts) { alert in
                        compactAlertRow(alert: alert)
                        
                        if alert.id != alerts.last?.id {
                            Divider()
                                .padding(.leading, 56)
                                .padding(.trailing, APSpacing.md)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .background(cardBgColor)
        .cornerRadius(APRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: APRadius.md)
                .stroke(cardStrokeColor, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
    }
    
    private func compactAlertRow(alert: StaffAlert) -> some View {
        var iconName = "bell.fill"
        var iconColor = Color.appAmber
        var iconBgColor = Color.appAmber.opacity(0.15)
        
        switch alert.type {
        case .serviceRequest(let req):
            let isBill = req.requestType.lowercased().contains("bill") || req.requestType.lowercased().contains("check")
            iconName = isBill ? "creditcard.fill" : "bell.fill"
            iconColor = isBill ? .appRose : .appAmber
            iconBgColor = (isBill ? Color.appRose : Color.appAmber).opacity(0.15)
            
        case .order(let order):
            let statusLower = order.status.lowercased()
            if statusLower == "ready" {
                iconName = "fork.knife"
                iconColor = .appAccent
                iconBgColor = Color.appAccent.opacity(0.15)
            } else if statusLower == "preparing" {
                iconName = "hourglass"
                iconColor = .appAmber
                iconBgColor = Color.appAmber.opacity(0.15)
            } else {
                iconName = "checkmark.circle.fill"
                iconColor = .appTeal
                iconBgColor = Color.appTeal.opacity(0.15)
            }
        }
        
        return HStack(spacing: APSpacing.sm) {
            ZStack {
                Circle()
                    .fill(iconBgColor)
                    .frame(width: 32, height: 32)
                
                Image(systemName: iconName)
                    .font(.system(size: 13))
                    .foregroundColor(iconColor)
            }
            
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(alert.title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.textPrimary)
                    
                    if alert.isActive {
                        APBadge(text: alert.priority.labelKey.localized(for: appLanguage), color: alert.priority.color)
                    }
                }
                
                Text(alert.subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.textSecondary)
                    .lineLimit(2)
                
                Text(alert.timestamp, style: .time)
                    .font(.system(size: 9))
                    .foregroundColor(.textTertiary)
            }
            
            Spacer()
            
            if alert.isActive {
                let alertId = alert.id
                let isProcessing = processingAlertIds.contains(alertId)
                
                switch alert.type {
                case .serviceRequest(let req):
                    Button(action: {
                        resolveRequest(req: req)
                    }) {
                        if isProcessing {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.7)
                                .frame(width: 38, height: 12)
                        } else {
                            Text("resolve".localized(for: appLanguage))
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background {
                        if isProcessing {
                            Color.gray
                        } else {
                            APGradient.positive
                        }
                    }
                    .clipShape(Capsule())
                    .disabled(isProcessing)
                    .buttonStyle(.plain)
                    
                case .order(let order):
                    if order.status.lowercased() == "ready" {
                        Button(action: {
                            serveOrder(order: order)
                        }) {
                            if isProcessing {
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(0.7)
                                    .frame(width: 32, height: 12)
                            } else {
                                Text("serve_action".localized(for: appLanguage))
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background {
                            if isProcessing {
                                Color.gray
                            } else {
                                APGradient.accent
                            }
                        }
                        .clipShape(Capsule())
                        .disabled(isProcessing)
                        .buttonStyle(.plain)
                    }
                }
            } else {
                HStack(spacing: 2) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9))
                        .foregroundColor(.textTertiary)
                    Text(resolvedLabel(for: alert))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.textTertiary)
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, APSpacing.md)
    }
    
    private func resolvedLabel(for alert: StaffAlert) -> String {
        switch alert.type {
        case .serviceRequest:
            return "completed".localized(for: appLanguage)
        case .order(let order):
            let statusLower = order.status.lowercased()
            if statusLower == "served" {
                return "order_served".localized(for: appLanguage)
            } else if statusLower == "completed" {
                return "order_completed".localized(for: appLanguage)
            } else {
                return order.status.capitalized
            }
        }
    }
    
    private func loadRequests() {
        Task {
            isLoading = true
            await networkService.refreshAll()
            isLoading = false
        }
    }
    
    private func resolveRequest(req: ServiceRequest) {
        let alertId = "req-\(req.id)"
        guard !processingAlertIds.contains(alertId) else { return }
        processingAlertIds.insert(alertId)
        APHaptic.trigger()
        Task {
            _ = try? await networkService.resolveRequest(requestId: req.id)
            processingAlertIds.remove(alertId)
        }
    }
    
    private func serveOrder(order: Order) {
        let alertId = "order-\(order.id)"
        guard !processingAlertIds.contains(alertId) else { return }
        processingAlertIds.insert(alertId)
        APHaptic.trigger()
        Task {
            _ = try? await networkService.serveOrder(orderId: order.id)
            processingAlertIds.remove(alertId)
        }
    }
    
    private func resolveAllForTable(_ alerts: [StaffAlert]) {
        let toProcess = alerts.filter { !processingAlertIds.contains($0.id) }
        guard !toProcess.isEmpty else { return }
        
        for alert in toProcess {
            processingAlertIds.insert(alert.id)
        }
        
        APHaptic.trigger()
        Task {
            for alert in toProcess {
                switch alert.type {
                case .serviceRequest(let req):
                    _ = try? await networkService.resolveRequest(requestId: req.id)
                case .order(let order):
                    if order.status.lowercased() == "ready" {
                        _ = try? await networkService.serveOrder(orderId: order.id)
                    }
                }
                processingAlertIds.remove(alert.id)
            }
        }
    }
    
    private func isoStringToDate(_ str: String) -> Date? {
        let df = ISO8601DateFormatter()
        return df.date(from: str)
    }
}
