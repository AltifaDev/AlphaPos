// WaitlistView.swift
// AlphaPos — L-1: Waitlist / Queue Management

import SwiftUI
import SwiftData
import Combine


// MARK: - Main Waitlist Sheet

struct WaitlistView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var lm: LocalizationManager

    @Query(
        filter: #Predicate<WaitlistEntry> { !$0.isDeleted && $0.status == "waiting" },
        sort: \WaitlistEntry.queueNumber
    ) private var waitingList: [WaitlistEntry]

    @Query(
        filter: #Predicate<WaitlistEntry> {
            !$0.isDeleted && $0.status != "waiting"
        },
        sort: \WaitlistEntry.arrivedAt, order: .reverse
    ) private var history: [WaitlistEntry]


    @State private var showingAddSheet = false
    @State private var selectedEntry: WaitlistEntry? = nil
    @State private var showHistory = false

    // Timer to refresh elapsed time
    @State private var tick = Date()
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var nextQueueNumber: Int {
        (waitingList.map { $0.queueNumber }.max() ?? 0) + 1
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Header stats
                    headerStats

                    Divider().background(Color.appDivider)

                    // Toggle: Waiting / History
                    Picker("", selection: $showHistory) {
                        Text("waitlist_tab_waiting".t + " (\(waitingList.count))").tag(false)
                        Text("waitlist_tab_history".t).tag(true)
                    }
                    .pickerStyle(.segmented)
                    .padding(APSpacing.md)
                    .background(Color.appSurface)

                    if showHistory {
                        historyList
                    } else if waitingList.isEmpty {
                        emptyState
                    } else {
                        waitingListView
                    }
                }
            }
            .navigationTitle("waitlist_title".t)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("close_btn_label".t) { dismiss() }
                        .foregroundColor(.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showingAddSheet = true }) {
                        Label("waitlist_add_btn".t, systemImage: "person.badge.plus")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundColor(.appAccent)
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                AddWaitlistSheet(queueNumber: nextQueueNumber) { entry in
                    modelContext.insert(entry)
                    modelContext.saveWithLogging(label: "WaitlistView.add")
                    Task { await SyncEngine.shared.syncAll(modelContext: modelContext) }
                }
            }
            .sheet(item: $selectedEntry) { entry in
                WaitlistEntryDetailSheet(entry: entry) {
                    modelContext.saveWithLogging(label: "WaitlistView.update")
                    Task { await SyncEngine.shared.syncAll(modelContext: modelContext) }
                }
            }
            .onReceive(timer) { _ in tick = Date() }
        }
        .apColorScheme()
    }

    // MARK: - Header Stats

    private var headerStats: some View {
        HStack(spacing: 16) {
            statCard(title: "waitlist_stat_waiting".t,
                     value: "\(waitingList.count)",
                     icon: "person.3.fill", color: .appAccent)
            statCard(title: "waitlist_stat_avg_wait".t,
                     value: avgWaitText,
                     icon: "clock.fill", color: .appAmber)
            statCard(title: "waitlist_stat_seated_today".t,
                     value: "\(seatedToday)",
                     icon: "checkmark.circle.fill", color: .appTeal)
            Spacer()
        }
        .padding(APSpacing.md)
        .background(Color.appSurface)
    }

    private var avgWaitText: String {
        guard !waitingList.isEmpty else { return "—" }
        let avg = waitingList.map { $0.waitMinutesElapsed }.reduce(0, +) / waitingList.count
        return "\(avg) " + "waitlist_min_unit".t
    }

    private var seatedToday: Int {
        let start = Calendar.current.startOfDay(for: Date())
        return history.filter { $0.status == "seated" && ($0.seatedAt ?? Date()) >= start }.count
    }

    private func statCard(title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16)).foregroundColor(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(.title3.bold()).foregroundColor(.textPrimary)
                Text(title).font(.caption2).foregroundColor(.textSecondary)
            }
        }
        .padding(10)
        .background(color.opacity(0.07))
        .cornerRadius(10)
    }

    // MARK: - Waiting List

    private var waitingListView: some View {
        List {
            ForEach(waitingList) { entry in
                waitlistRow(entry)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                    .onTapGesture { selectedEntry = entry }
            }
        }
        .listStyle(.plain)
        .background(Color.appBackground)
    }

    private func waitlistRow(_ entry: WaitlistEntry) -> some View {
        let overdue = entry.isOverdue
        return HStack(spacing: 12) {
            // Queue number badge
            ZStack {
                Circle()
                    .fill(overdue ? Color.appAmber : Color.appAccent)
                    .frame(width: 42, height: 42)
                Text("#\(entry.queueNumber)")
                    .font(.system(size: 14, weight: .black))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.guestName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.textPrimary)
                    Text("👥 \(entry.partySize)")
                        .font(.caption2).foregroundColor(.textSecondary)
                }
                HStack(spacing: 8) {
                    Label("\(entry.waitMinutesElapsed) " + "waitlist_min_unit".t,
                          systemImage: "clock")
                        .font(.caption2)
                        .foregroundColor(overdue ? .appAmber : .textTertiary)
                    if let phone = entry.phone, !phone.isEmpty {
                        Label(phone, systemImage: "phone")
                            .font(.caption2).foregroundColor(.textTertiary)
                    }
                }
                if overdue {
                    Text("waitlist_overdue_badge".t)
                        .font(.caption2.bold())
                        .foregroundColor(.appAmber)
                }
            }

            Spacer()

            // Quick action: Seat
            Button(action: { seatEntry(entry) }) {
                Image(systemName: "chair.lounge.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.appTeal)
                    .frame(width: 36, height: 36)
                    .background(Color.appTeal.opacity(0.12))
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(overdue ? Color.appAmber.opacity(0.04) : Color.appSurface)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(overdue ? Color.appAmber.opacity(0.3) : Color.appBorderSubtle, lineWidth: 1)
        )
    }

    // MARK: - History List

    private var historyList: some View {
        List {
            ForEach(history.prefix(30)) { entry in
                HStack(spacing: 10) {
                    Image(systemName: entry.status == "seated" ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(entry.status == "seated" ? .appTeal : .appRose)
                        .font(.system(size: 18))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.guestName).font(.subheadline.bold()).foregroundColor(.textPrimary)
                        HStack(spacing: 6) {
                            Text("👥 \(entry.partySize)").font(.caption2).foregroundColor(.textSecondary)
                            if let seated = entry.seatedTableNumber {
                                Text("🍽 T\(seated)").font(.caption2).foregroundColor(.appTeal)
                            }
                            Text(statusLabel(entry.status))
                                .font(.caption2.bold())
                                .foregroundColor(entry.status == "seated" ? .appTeal : .appRose)
                        }
                    }
                    Spacer()
                    Text(entry.arrivedAt.formatted(.dateTime.hour().minute()))
                        .font(.caption2).foregroundColor(.textTertiary)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .background(Color.appBackground)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.3").font(.system(size: 44)).foregroundColor(.textTertiary)
            Text("waitlist_empty_title".t).font(.headline).foregroundColor(.textSecondary)
            Text("waitlist_empty_desc".t).font(.subheadline).foregroundColor(.textTertiary)
                .multilineTextAlignment(.center).padding(.horizontal)
            Button(action: { showingAddSheet = true }) {
                Label("waitlist_add_btn".t, systemImage: "person.badge.plus")
                    .font(.subheadline.bold())
                    .padding(.horizontal, 20).padding(.vertical, 10)
                    .background(APGradient.accent).foregroundColor(.white).cornerRadius(10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
    }

    // MARK: - Actions

    private func seatEntry(_ entry: WaitlistEntry) {
        entry.status = "seated"
        entry.seatedAt = Date()
        entry.isSynced = false
        entry.updatedAt = Date()
        modelContext.saveWithLogging(label: "WaitlistView.seat")
        Task { await SyncEngine.shared.syncAll(modelContext: modelContext) }
        APHaptic.trigger()
    }

    private func statusLabel(_ status: String) -> String {
        switch status {
        case "seated":   return "waitlist_status_seated".t
        case "no_show":  return "waitlist_status_no_show".t
        case "cancelled": return "waitlist_status_cancelled".t
        default:         return "waitlist_status_waiting".t
        }
    }
}

// MARK: - Add Waitlist Sheet

struct AddWaitlistSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var lm: LocalizationManager

    let queueNumber: Int
    let onSave: (WaitlistEntry) -> Void

    @State private var guestName = ""
    @State private var partySize = 2
    @State private var phone = ""
    @State private var notes = ""
    @State private var estimatedWait = 15

    var body: some View {
        NavigationStack {
            Form {
                Section("waitlist_guest_section".t) {
                    TextField("waitlist_name_placeholder".t, text: $guestName)
                    Stepper("waitlist_party_size_lbl".t + ": \(partySize)",
                             value: $partySize, in: 1...20)
                    TextField("waitlist_phone_placeholder".t, text: $phone)
                        .keyboardType(.phonePad)
                }
                Section("waitlist_wait_section".t) {
                    Stepper("waitlist_est_wait_lbl".t + ": \(estimatedWait) " + "waitlist_min_unit".t,
                             value: $estimatedWait, in: 5...120, step: 5)
                }
                Section("waitlist_notes_section".t) {
                    TextField("waitlist_notes_placeholder".t, text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
                Section {
                    Button(action: save) {
                        Text("waitlist_save_btn".t).frame(maxWidth: .infinity)
                            .foregroundColor(guestName.isEmpty ? .textTertiary : .white)
                    }
                    .listRowBackground(guestName.isEmpty ? Color.appSurfaceHigh : nil)
                    .disabled(guestName.isEmpty)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .navigationTitle("waitlist_add_title".t + " #\(queueNumber)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel_btn".t) { dismiss() }.foregroundColor(.textSecondary)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        let entry = WaitlistEntry(
            guestName: guestName,
            partySize: partySize,
            phone: phone.isEmpty ? nil : phone,
            notes: notes.isEmpty ? nil : notes,
            queueNumber: queueNumber,
            estimatedWaitMinutes: estimatedWait
        )
        onSave(entry)
        dismiss()
    }
}

// MARK: - Entry Detail Sheet (Seat / Cancel / No-Show)

struct WaitlistEntryDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var lm: LocalizationManager
    @Bindable var entry: WaitlistEntry
    let onSave: () -> Void

    @State private var tableNumber = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("waitlist_queue_number_lbl".t)
                        Spacer()
                        Text("#\(entry.queueNumber)").fontWeight(.bold).foregroundColor(.appAccent)
                    }
                    HStack {
                        Text("waitlist_party_size_lbl".t)
                        Spacer()
                        Text("👥 \(entry.partySize)").foregroundColor(.textSecondary)
                    }
                    if let phone = entry.phone { HStack {
                        Text("waitlist_phone_placeholder".t)
                        Spacer()
                        Text(phone).foregroundColor(.textSecondary)
                    }}
                    if let notes = entry.notes, !notes.isEmpty {
                        Text(notes).font(.caption).foregroundColor(.textSecondary)
                    }
                }

                if entry.status == "waiting" {
                    Section("waitlist_seat_section".t) {
                        TextField("waitlist_table_number_placeholder".t, text: $tableNumber)
                            .keyboardType(.numberPad)
                        Button(action: { seat() }) {
                            Label("waitlist_seat_btn".t, systemImage: "chair.lounge.fill")
                                .frame(maxWidth: .infinity)
                                .foregroundColor(.white)
                                .padding(.vertical, 10)
                                .background(Color.appTeal)
                                .cornerRadius(10)
                        }
                        .listRowBackground(Color.clear)
                        .buttonStyle(.plain)
                    }

                    Section("waitlist_cancel_section".t) {
                        Button(action: { updateStatus("cancelled") }) {
                            Label("waitlist_cancel_btn".t, systemImage: "xmark.circle")
                                .foregroundColor(.appRose).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        Button(action: { updateStatus("no_show") }) {
                            Label("waitlist_no_show_btn".t, systemImage: "person.fill.xmark")
                                .foregroundColor(.secondary).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Section {
                        HStack {
                            Text("waitlist_status_lbl".t)
                            Spacer()
                            Text(statusLabel(entry.status))
                                .fontWeight(.bold)
                                .foregroundColor(entry.status == "seated" ? .appTeal : .appRose)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .navigationTitle(entry.guestName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("close_btn_label".t) { dismiss() }.foregroundColor(.textSecondary)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func seat() {
        entry.status = "seated"
        entry.seatedAt = Date()
        entry.seatedTableNumber = tableNumber.isEmpty ? nil : tableNumber
        entry.isSynced = false; entry.updatedAt = Date()
        onSave(); dismiss(); APHaptic.trigger()
    }

    private func updateStatus(_ status: String) {
        entry.status = status
        entry.cancelledAt = Date()
        entry.isSynced = false; entry.updatedAt = Date()
        onSave(); dismiss()
    }

    private func statusLabel(_ status: String) -> String {
        switch status {
        case "seated":   return "waitlist_status_seated".t
        case "no_show":  return "waitlist_status_no_show".t
        case "cancelled": return "waitlist_status_cancelled".t
        default:         return "waitlist_status_waiting".t
        }
    }
}
