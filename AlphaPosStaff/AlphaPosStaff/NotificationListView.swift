import SwiftUI

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
    @State private var collapsedTables = Set<String>()
    @State private var processingAlertIds = Set<String>()

    private var alerts: [StaffAlert] {
        var list: [StaffAlert] = []
        
        // Map service requests
        for req in networkService.serviceRequests {
            let isActive = req.status == "pending"
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
            let isWithin24Hours = Date().timeIntervalSince(date) <= 86400
            
            guard isSessionActive || isWithin24Hours else { continue }
            
            let statusLower = order.status.lowercased()
            // Waiters need alerts for preparing/cooking and ready orders.
            // Only cancelled orders are filtered out.
            guard statusLower != "cancelled" else { continue }
            
            let isActive = statusLower == "ready" || statusLower == "preparing" || statusLower == "cooking"
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
    
    private var historyAlerts: [StaffAlert] {
        alerts.filter { !$0.isActive }
            .sorted { $0.timestamp > $1.timestamp }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    if isLoading && activeAlerts.isEmpty && historyAlerts.isEmpty {
                        ProgressView().tint(.appAccent).frame(maxHeight: .infinity)
                    } else if activeAlerts.isEmpty && historyAlerts.isEmpty {
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
                        List {
                            if !activeAlerts.isEmpty {
                                Section {
                                    ForEach(activeAlertsByTable, id: \.tableNumber) { group in
                                        tableGroupCard(tableNumber: group.tableNumber, alerts: group.alerts)
                                            .listRowBackground(Color.clear)
                                            .listRowSeparator(.hidden)
                                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                    }
                                } header: {
                                    Text("active_alerts_section".localized(for: appLanguage))
                                        .font(.subheadline).fontWeight(.bold)
                                        .foregroundColor(.textSecondary)
                                        .textCase(.uppercase)
                                }
                            }
                            
                            if !historyAlerts.isEmpty {
                                Section {
                                    ForEach(historyAlerts) { alert in
                                        alertRow(alert: alert)
                                            .listRowBackground(Color.appSurface)
                                            .listRowSeparator(.hidden)
                                            .padding(.vertical, 4)
                                    }
                                } header: {
                                    Text("resolved_history_section".localized(for: appLanguage))
                                        .font(.subheadline).fontWeight(.bold)
                                        .foregroundColor(.textSecondary)
                                        .textCase(.uppercase)
                                }
                            }
                        }
                        .listStyle(.grouped)
                        .scrollContentBackground(.hidden)
                        .background(Color.appBackground)
                    }
                }
            }
            .navigationTitle("alerts".localized(for: appLanguage))
            .toolbar {
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
        let isCollapsed = collapsedTables.contains(tableNumber)
        
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
                        if isCollapsed {
                            collapsedTables.remove(tableNumber)
                        } else {
                            collapsedTables.insert(tableNumber)
                        }
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                            .font(.footnote)
                            .foregroundColor(.textSecondary)
                        
                        Text(String(format: "table_label".localized(for: appLanguage), tableNumber))
                            .font(.headline).fontWeight(.black)
                            .foregroundColor(.textPrimary)
                        
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
            .padding(.vertical, APSpacing.md)
            
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
        .background(Color.appSurface)
        .cornerRadius(APRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: APRadius.md)
                .stroke(hasHighPriority ? Color.appRose.opacity(0.3) : Color.appBorderSubtle, lineWidth: 1)
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
        .padding(.vertical, 6)
        .padding(.horizontal, APSpacing.md)
    }
    
    private func alertRow(alert: StaffAlert) -> some View {
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
        
        return HStack(spacing: APSpacing.md) {
            ZStack {
                Circle()
                    .fill(iconBgColor)
                    .frame(width: 44, height: 44)
                
                Image(systemName: iconName)
                    .foregroundColor(iconColor)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(alert.title)
                        .font(.subheadline).fontWeight(.black)
                        .foregroundColor(.textPrimary)
                    
                    if alert.isActive {
                        APBadge(text: alert.priority.labelKey.localized(for: appLanguage), color: alert.priority.color)
                    }
                }
                
                Text(alert.subtitle)
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                    .lineLimit(2)
                
                Text(alert.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.textTertiary)
            }
            
            Spacer()
            
            if alert.isActive {
                switch alert.type {
                case .serviceRequest(let req):
                    Button(action: {
                        resolveRequest(req: req)
                    }) {
                        Text("resolve".localized(for: appLanguage))
                            .font(.caption).fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(APGradient.positive)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    
                case .order(let order):
                    if order.status.lowercased() == "ready" {
                        Button(action: {
                            serveOrder(order: order)
                        }) {
                            Text("serve_action".localized(for: appLanguage))
                                .font(.caption).fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(APGradient.accent)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.caption2)
                        .foregroundColor(.textTertiary)
                    Text(resolvedLabel(for: alert))
                        .font(.caption2).fontWeight(.medium)
                        .foregroundColor(.textTertiary)
                }
            }
        }
        .padding(APSpacing.md)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: APRadius.md)
                .stroke(Color.appBorderSubtle, lineWidth: 1)
        )
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
