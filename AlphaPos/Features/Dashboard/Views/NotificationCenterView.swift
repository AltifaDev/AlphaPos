// NotificationCenterView.swift
// AlphaPos — Enterprise Notification Center (Master Device)
// v2: Wired to NotificationStore for real Supabase Realtime alerts.

import SwiftUI
import SwiftData

/// Unified Notification Center for the Master Device.
/// Aggregates alerts from ALL devices via NotificationStore.
///
/// Data flow:
/// ```
/// Supabase Realtime WS → SyncEngine → InAppNotificationManager
///                                    → NotificationStore → THIS VIEW
/// ```
struct NotificationCenterView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var lm: LocalizationManager
    
    @ObservedObject private var store = NotificationStore.shared
    
    @State private var selectedFilter: NotificationAlert.AlertCategory = .all
    @State private var searchText = ""
    @State private var showEscalationSettings = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection
            
            Divider().background(Color.appDivider)
            
            // Filter chips
            filterChipsSection
            
            Divider().background(Color.appDivider)
            
            // Alerts list
            alertsListSection
        }
        .background(Color.appBackground)
        .sheet(isPresented: $showEscalationSettings) {
            EscalationSettingsSheet()
        }
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("notification_center_title".t)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.textPrimary)
                Text("notification_center_subtitle".t)
                    .font(.subheadline)
                    .foregroundColor(.textSecondary)
            }
            
            Spacer()
            
            // Unread count badge
            if store.unreadCount > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.appAccent)
                    Text("\(store.unreadCount)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.appAccent)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.appAccent.opacity(0.1))
                .cornerRadius(10)
            }
            
            // Mark all read
            if store.activeCount > 0 {
                Button {
                    withAnimation { store.acknowledgeAll() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                        Text("notif_mark_all_read".t)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.appSurfaceHigh)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            
            // Escalation rules button
            Button {
                showEscalationSettings = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(Color.appSurfaceHigh)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }
    
    // MARK: - Filter Chips
    
    private var filterChipsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(NotificationAlert.AlertCategory.allCases) { category in
                    let count = category == .all ? store.activeCount : store.filtered(by: category).count
                    
                    Button {
                        withAnimation { selectedFilter = category }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: category.icon)
                                .font(.system(size: 12))
                            Text(category.rawValue)
                                .font(.system(size: 12, weight: .medium))
                            if count > 0 {
                                Text("\(count)")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 18, height: 18)
                                    .background(category.color)
                                    .clipShape(Circle())
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(selectedFilter == category ? category.color.opacity(0.15) : Color.appSurfaceHigh)
                        .foregroundColor(selectedFilter == category ? category.color : .textSecondary)
                        .cornerRadius(20)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(selectedFilter == category ? category.color.opacity(0.3) : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
    }
    
    // MARK: - Alerts List
    
    private var alertsListSection: some View {
        let filteredAlerts = store.filtered(by: selectedFilter)
        
        return Group {
            if filteredAlerts.isEmpty {
                // Empty state
                VStack(spacing: 16) {
                    Image(systemName: "bell.slash")
                        .font(.system(size: 44))
                        .foregroundColor(.textTertiary)
                    Text("notif_no_alerts".t)
                        .font(.headline)
                        .foregroundColor(.textSecondary)
                    Text("notif_no_alerts_desc".t)
                        .font(.subheadline)
                        .foregroundColor(.textTertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredAlerts) { alert in
                            alertRow(alert)
                        }
                    }
                    .padding()
                }
            }
        }
    }
    
    // MARK: - Alert Row
    
    private func alertRow(_ alert: NotificationAlert) -> some View {
        HStack(spacing: 12) {
            // Priority indicator
            Rectangle()
                .fill(alert.priority.color)
                .frame(width: 4)
                .cornerRadius(2)
            
            // Category icon
            ZStack {
                Circle()
                    .fill(alert.category.color.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: alert.category.icon)
                    .font(.system(size: 14))
                    .foregroundColor(alert.category.color)
            }
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(alert.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(alert.isRead ? .textSecondary : .textPrimary)
                    
                    if !alert.isRead {
                        Circle()
                            .fill(Color.appAccent)
                            .frame(width: 6, height: 6)
                    }
                    
                    Spacer()
                    
                    Text(timeAgo(alert.createdAt))
                        .font(.system(size: 11))
                        .foregroundColor(.textTertiary)
                }
                
                Text(alert.message)
                    .font(.system(size: 12))
                    .foregroundColor(.textSecondary)
                    .lineLimit(2)
                
                HStack(spacing: 8) {
                    // Device badge
                    HStack(spacing: 4) {
                        Image(systemName: deviceIcon(alert.device))
                            .font(.system(size: 9))
                        Text(alert.device)
                            .font(.system(size: 10))
                    }
                    .foregroundColor(.textTertiary)
                    
                    // Priority badge
                    Text(alert.priority.label)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(alert.priority.color)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(alert.priority.color.opacity(0.1))
                        .cornerRadius(4)
                }
            }
            
            // Actions
            VStack(spacing: 4) {
                Button {
                    withAnimation { store.acknowledge(alert.id) }
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.green)
                        .frame(width: 28, height: 28)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                
                Button {
                    withAnimation { store.markRead(alert.id) }
                } label: {
                    Image(systemName: "eye")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.textTertiary)
                        .frame(width: 28, height: 28)
                        .background(Color.appSurfaceHigh)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(alert.isRead ? Color.appSurface.opacity(0.7) : Color.appSurface)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    alert.priority == .critical ? alert.priority.color.opacity(0.3) : Color.appBorderSubtle,
                    lineWidth: 1
                )
        )
        .onAppear {
            // Auto-mark as read after appearing on screen
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                store.markRead(alert.id)
            }
        }
    }
    
    // MARK: - Helpers
    
    private func timeAgo(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "notif_just_now".t }
        if interval < 3600 { return "\(Int(interval / 60)) " + "notif_min_ago".t }
        if interval < 86400 { return "\(Int(interval / 3600)) " + "notif_hr_ago".t }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
    
    private func deviceIcon(_ device: String) -> String {
        switch device.lowercased() {
        case let d where d.contains("ipad"): return "ipad.landscape"
        case let d where d.contains("iphone"), let d where d.contains("staff"): return "iphone"
        case let d where d.contains("kitchen"): return "display"
        case let d where d.contains("customer"), let d where d.contains("web"): return "globe"
        default: return "server.rack"
        }
    }
}

// MARK: - Escalation Settings Sheet

private struct EscalationSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    @AppStorage("escalation_critical_timeout_min") private var criticalTimeout = 5
    @AppStorage("escalation_high_timeout_min") private var highTimeout = 15
    @AppStorage("escalation_auto_sound") private var autoSound = true
    @AppStorage("escalation_repeat_alert") private var repeatAlert = true
    
    var body: some View {
        NavigationStack {
            Form {
                Section("escalation_timing_section".t) {
                    Stepper("escalation_critical_timeout".t + ": \(criticalTimeout) min", value: $criticalTimeout, in: 1...30)
                    Stepper("escalation_high_timeout".t + ": \(highTimeout) min", value: $highTimeout, in: 5...60)
                }
                
                Section("escalation_behavior_section".t) {
                    Toggle("escalation_auto_sound".t, isOn: $autoSound)
                    Toggle("escalation_repeat_alert".t, isOn: $repeatAlert)
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("escalation_how_it_works".t)
                            .font(.headline)
                        Text("escalation_explanation".t)
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                    }
                }
            }
            .navigationTitle("escalation_rules_title".t)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("close".t) { dismiss() }
                }
            }
        }
    }
}
