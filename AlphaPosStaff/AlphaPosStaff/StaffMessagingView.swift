// StaffMessagingView.swift
// AlphaPosStaff — Staff-to-Staff Messaging System
//
// Provides real-time messaging between staff members including
// team chat, direct messages, and quick preset messages for
// common restaurant communication needs.

import SwiftUI

// MARK: - Models

struct ChatChannel: Identifiable, Codable {
    let id: String
    let name: String
    let type: String // "team" or "direct"
    let participants: [String] // employee IDs
    let lastMessage: String?
    let lastMessageAt: String?
    let unreadCount: Int
    
    enum CodingKeys: String, CodingKey {
        case id, name, type, participants
        case lastMessage = "last_message"
        case lastMessageAt = "last_message_at"
        case unreadCount = "unread_count"
    }
}

struct ChatMessage: Identifiable, Codable, Equatable {
    let id: String
    let channelId: String
    let senderId: String
    let senderName: String
    let text: String
    let createdAt: String
    let isRead: Bool
    
    enum CodingKeys: String, CodingKey {
        case id
        case channelId = "channel_id"
        case senderId = "sender_id"
        case senderName = "sender_name"
        case text
        case createdAt = "created_at"
        case isRead = "is_read"
    }
}

struct StaffMember: Identifiable {
    let id: String
    let name: String
    let role: String
    let isOnline: Bool
}

// MARK: - Quick Message Presets

enum QuickMessagePreset: CaseIterable {
    case needHelp
    case orderReady
    case runningLow
    case takingBreak
    case backFromBreak
    case customerComplaint
    
    var icon: String {
        switch self {
        case .needHelp: return "hand.raised.fill"
        case .orderReady: return "tray.fill"
        case .runningLow: return "exclamationmark.triangle.fill"
        case .takingBreak: return "cup.and.saucer.fill"
        case .backFromBreak: return "figure.walk"
        case .customerComplaint: return "person.fill.xmark"
        }
    }
    
    var color: Color {
        switch self {
        case .needHelp: return .appAmber
        case .orderReady: return .appGreen
        case .runningLow: return .appRose
        case .takingBreak: return .appPurple
        case .backFromBreak: return .appTeal
        case .customerComplaint: return .appRose
        }
    }
    
    func text(for lang: String) -> String {
        switch self {
        case .needHelp: return "need_help".localized(for: lang)
        case .orderReady: return "order_ready_pickup".localized(for: lang)
        case .runningLow: return "running_low".localized(for: lang)
        case .takingBreak: return "taking_break".localized(for: lang)
        case .backFromBreak: return "back_from_break".localized(for: lang)
        case .customerComplaint: return "customer_complaint".localized(for: lang)
        }
    }
}

// MARK: - Main View

struct StaffMessagingView: View {
    @AppStorage("app_language") private var appLanguage = "en"
    @AppStorage("logged_in_employee_name") private var currentEmployeeName = ""
    
    @State private var channels: [ChatChannel] = []
    @State private var isLoading = false
    @State private var selectedChannel: ChatChannel? = nil
    @State private var showNewMessage = false
    @State private var staffMembers: [StaffMember] = []
    
    private var currentEmployeeId: String {
        UserDefaults.standard.string(forKey: "logged_in_employee_id") ?? ""
    }
    
    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            
            if isLoading && channels.isEmpty {
                loadingView
            } else if channels.isEmpty {
                emptyStateView
            } else {
                channelListView
            }
        }
        .navigationTitle("messages".localized(for: appLanguage))
        .navigationBarTitleDisplayMode(.large)
        .apNavBar()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showNewMessage = true
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.appAccent)
                }
            }
        }
        .sheet(item: $selectedChannel) { channel in
            ChatDetailView(
                channel: channel,
                currentEmployeeId: currentEmployeeId,
                currentEmployeeName: currentEmployeeName
            )
        }
        .sheet(isPresented: $showNewMessage) {
            NewMessageView(
                staffMembers: staffMembers,
                onSelectStaff: { staff in
                    showNewMessage = false
                    // Create or open DM channel
                    Task {
                        await openDirectMessage(with: staff)
                    }
                }
            )
        }
        .task {
            await loadChannels()
        }
        .refreshable {
            await loadChannels()
        }
    }
    
    // MARK: - Channel List
    
    private var channelListView: some View {
        ScrollView {
            LazyVStack(spacing: APSpacing.sm) {
                // Quick Messages Section
                quickMessagesSection
                
                // Team Channels
                let teamChannels = channels.filter { $0.type == "team" }
                if !teamChannels.isEmpty {
                    sectionHeader("team_chat".localized(for: appLanguage), icon: "person.3.fill")
                    
                    ForEach(teamChannels) { channel in
                        channelRow(channel, isTeam: true)
                    }
                }
                
                // Direct Messages
                let dmChannels = channels.filter { $0.type == "direct" }
                if !dmChannels.isEmpty {
                    sectionHeader("direct_message".localized(for: appLanguage), icon: "bubble.left.and.bubble.right.fill")
                    
                    ForEach(dmChannels) { channel in
                        channelRow(channel, isTeam: false)
                    }
                }
            }
            .padding(.horizontal, APSpacing.md)
            .padding(.top, APSpacing.sm)
            .padding(.bottom, APSpacing.xxl)
        }
    }
    
    // MARK: - Quick Messages Section
    
    private var quickMessagesSection: some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            sectionHeader("quick_messages".localized(for: appLanguage), icon: "bolt.fill")
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: APSpacing.sm) {
                    ForEach(QuickMessagePreset.allCases, id: \.self) { preset in
                        quickMessageChip(preset)
                    }
                }
                .padding(.horizontal, APSpacing.xs)
            }
        }
        .padding(.bottom, APSpacing.sm)
    }
    
    private func quickMessageChip(_ preset: QuickMessagePreset) -> some View {
        Button {
            sendQuickMessage(preset)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: preset.icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(preset.color)
                
                Text(preset.text(for: appLanguage))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
            }
            .padding(.horizontal, APSpacing.md)
            .padding(.vertical, APSpacing.sm + 2)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.appSurface)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(preset.color.opacity(0.3), lineWidth: 1)
                    )
            )
            .shadow(color: preset.color.opacity(0.15), radius: 4, x: 0, y: 2)
        }
    }
    
    // MARK: - Channel Row
    
    private func channelRow(_ channel: ChatChannel, isTeam: Bool) -> some View {
        Button {
            selectedChannel = channel
        } label: {
            HStack(spacing: APSpacing.md) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(isTeam ?
                              LinearGradient(colors: [.appAccent, .appPurple], startPoint: .topLeading, endPoint: .bottomTrailing) :
                              LinearGradient(colors: [.appTeal, .appGreen], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: isTeam ? "person.3.fill" : "person.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                    
                    // Online indicator for DMs
                    if !isTeam {
                        Circle()
                            .fill(Color.appGreen)
                            .frame(width: 12, height: 12)
                            .overlay(
                                Circle().stroke(Color.appSurface, lineWidth: 2)
                            )
                            .offset(x: 16, y: 16)
                    }
                }
                
                // Content
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(channel.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.textPrimary)
                        
                        Spacer()
                        
                        if let lastAt = channel.lastMessageAt {
                            Text(formatTimestamp(lastAt))
                                .font(.caption2)
                                .foregroundStyle(Color.textTertiary)
                        }
                    }
                    
                    HStack {
                        Text(channel.lastMessage ?? "")
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        if channel.unreadCount > 0 {
                            Text("\(channel.unreadCount)")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule().fill(Color.appAccent)
                                )
                        }
                    }
                }
            }
            .padding(APSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: APRadius.md, style: .continuous)
                    .fill(Color.appSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: APRadius.md, style: .continuous)
                            .stroke(Color.appBorderSubtle, lineWidth: 1)
                    )
            )
        }
    }
    
    // MARK: - Section Header
    
    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.appAccent)
            
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.textSecondary)
                .textCase(.uppercase)
                .tracking(0.5)
            
            Spacer()
        }
        .padding(.top, APSpacing.md)
        .padding(.bottom, APSpacing.xs)
    }
    
    // MARK: - Empty & Loading States
    
    private var emptyStateView: some View {
        VStack(spacing: APSpacing.lg) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 56))
                .foregroundStyle(Color.textTertiary)
            
            Text("messages".localized(for: appLanguage))
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(Color.textPrimary)
            
            Text("no_messages_yet".localized(for: appLanguage))
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(APSpacing.xl)
    }
    
    private var loadingView: some View {
        VStack(spacing: APSpacing.md) {
            ProgressView()
                .tint(.appAccent)
                .scaleEffect(1.3)
            
            Text("loading".localized(for: appLanguage))
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
        }
    }
    
    // MARK: - Helpers
    
    private func formatTimestamp(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: isoString) ?? ISO8601DateFormatter().date(from: isoString) else {
            return ""
        }
        
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "HH:mm"
            return timeFormatter.string(from: date)
        } else {
            let dayFormatter = DateFormatter()
            dayFormatter.dateFormat = "E"
            return dayFormatter.string(from: date)
        }
    }
    
    // MARK: - Data Loading
    
    private func loadChannels() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            channels = try await NetworkService.shared.fetchChannels()
            staffMembers = try await NetworkService.shared.fetchOnlineStaff()
        } catch {
            #if DEBUG
            print("StaffMessagingView: Failed to load channels: \(error)")
            #endif
        }
    }
    
    private func sendQuickMessage(_ preset: QuickMessagePreset) {
        // Send to team channel
        guard let teamChannel = channels.first(where: { $0.type == "team" }) else { return }
        
        Task {
            do {
                _ = try await NetworkService.shared.sendMessage(
                    channelId: teamChannel.id,
                    text: preset.text(for: "en") // Always send in English for consistency
                )
                // Reload to show sent message
                await loadChannels()
            } catch {
                #if DEBUG
                print("StaffMessagingView: Failed to send quick message: \(error)")
                #endif
            }
        }
    }
    
    private func openDirectMessage(with staff: StaffMember) async {
        // Find existing DM channel or create one
        if let existing = channels.first(where: {
            $0.type == "direct" && $0.participants.contains(staff.id)
        }) {
            selectedChannel = existing
        } else {
            // Create new DM channel
            do {
                let newChannel = try await NetworkService.shared.createDirectChannel(
                    participantId: staff.id,
                    participantName: staff.name
                )
                channels.insert(newChannel, at: 0)
                selectedChannel = newChannel
            } catch {
                #if DEBUG
                print("StaffMessagingView: Failed to create DM: \(error)")
                #endif
            }
        }
    }
}

// MARK: - Chat Detail View

struct ChatDetailView: View {
    let channel: ChatChannel
    let currentEmployeeId: String
    let currentEmployeeName: String
    
    @AppStorage("app_language") private var appLanguage = "en"
    @Environment(\.dismiss) private var dismiss
    
    @State private var messages: [ChatMessage] = []
    @State private var messageText = ""
    @State private var isLoading = false
    @State private var showQuickMessages = false
    @State private var scrollProxy: ScrollViewProxy? = nil
    @State private var refreshTimer: Timer? = nil
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Messages list
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 4) {
                                ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                                    VStack(spacing: 4) {
                                        if shouldShowTimestampHeader(for: index) {
                                            Text(formatMessageHeaderDate(message.createdAt))
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundColor(.textTertiary)
                                                .padding(.vertical, 8)
                                                .frame(maxWidth: .infinity, alignment: .center)
                                        }
                                        
                                        messageBubble(message)
                                    }
                                    .id(message.id)
                                }
                            }
                            .padding(.horizontal, APSpacing.md)
                            .padding(.vertical, APSpacing.sm)
                        }
                        .onAppear { scrollProxy = proxy }
                        .onChange(of: messages.count) { _ in
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo(messages.last?.id, anchor: .bottom)
                            }
                        }
                    }
                    
                    Divider().overlay(Color.appDivider)
                    
                    // Input bar
                    inputBar
                }
            }
            .navigationTitle(channel.name)
            .navigationBarTitleDisplayMode(.inline)
            .apNavBar()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
            .task {
                await loadMessages()
                startPolling()
            }
            .onDisappear {
                refreshTimer?.invalidate()
                refreshTimer = nil
            }
            .sheet(isPresented: $showQuickMessages) {
                quickMessagesSheet
            }
        }
    }
    
    // MARK: - Message Bubble
    
    private func messageBubble(_ message: ChatMessage) -> some View {
        let isMine = message.senderId == currentEmployeeId
        let showAvatar = !isMine && channel.type != "direct"
        
        return VStack(alignment: isMine ? .trailing : .leading, spacing: 2) {
            HStack(alignment: .bottom, spacing: 8) {
                if isMine { Spacer(minLength: 60) }
                
                if showAvatar {
                    // Avatar for others in group channels
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.appTeal.opacity(0.8), .appGreen.opacity(0.6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 30, height: 30)
                        .overlay(
                            Text(String(message.senderName.prefix(1)).uppercased())
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                        )
                }
                
                VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
                    if !isMine && channel.type != "direct" {
                        Text(message.senderName)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.textTertiary)
                            .padding(.leading, 8)
                    }
                    
                    Text(message.text)
                        .font(.system(size: 15))
                        .foregroundColor(isMine ? .white : Color.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            isMine ?
                            AnyShapeStyle(
                                LinearGradient(
                                    colors: [Color(red: 0.0, green: 0.58, blue: 1.0), Color(red: 0.0, green: 0.45, blue: 0.95)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            ) :
                            AnyShapeStyle(Color.appSurface)
                        )
                        .clipShape(MessageBubbleShape(isMine: isMine))
                        .overlay(
                            MessageBubbleShape(isMine: isMine)
                                .stroke(isMine ? Color.clear : Color.appBorderSubtle, lineWidth: 0.5)
                        )
                }
                
                if !isMine { Spacer(minLength: 60) }
            }
            
            if isMine && message.id == messages.last?.id {
                Text(message.isRead ? "Read" : "Delivered")
                    .font(.system(size: 9))
                    .foregroundColor(.textTertiary)
                    .padding(.trailing, 8)
                    .padding(.top, 1)
            }
        }
        .padding(.vertical, 1)
    }
    
    // MARK: - Read Receipt
    
    private func readReceiptIcon(_ isRead: Bool) -> some View {
        Image(systemName: isRead ? "checkmark.circle.fill" : "checkmark.circle")
            .font(.system(size: 11))
            .foregroundStyle(isRead ? Color.appAccent : Color.textTertiary)
    }
    
    // MARK: - Input Bar
    
    private var inputBar: some View {
        HStack(spacing: APSpacing.sm) {
            // Quick message button (looks like iMessage plug-in expansion button)
            Button {
                showQuickMessages = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(
                        Circle().fill(Color.appSurface)
                    )
            }
            
            // Text field
            HStack(spacing: 8) {
                TextField("iMessage", text: $messageText)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.textPrimary)
                    .tint(Color(red: 0.0, green: 0.478, blue: 1.0))
                
                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.textTertiary.opacity(0.3) : Color(red: 0.0, green: 0.478, blue: 1.0))
                }
                .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.appSurface)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.appBorderSubtle, lineWidth: 1)
                    )
            )
        }
        .padding(.horizontal, APSpacing.md)
        .padding(.vertical, APSpacing.sm)
        .background(Color.appBackground)
    }
    
    // MARK: - Quick Messages Sheet
    
    private var quickMessagesSheet: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: APSpacing.sm) {
                        ForEach(QuickMessagePreset.allCases, id: \.self) { preset in
                            Button {
                                messageText = preset.text(for: appLanguage)
                                showQuickMessages = false
                                sendMessage()
                            } label: {
                                HStack(spacing: APSpacing.md) {
                                    Image(systemName: preset.icon)
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundStyle(preset.color)
                                        .frame(width: 40, height: 40)
                                        .background(
                                            Circle().fill(preset.color.opacity(0.15))
                                        )
                                    
                                    Text(preset.text(for: appLanguage))
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundStyle(Color.textPrimary)
                                    
                                    Spacer()
                                    
                                    Image(systemName: "paperplane.fill")
                                        .font(.system(size: 14))
                                        .foregroundStyle(Color.textTertiary)
                                }
                                .padding(APSpacing.md)
                                .background(
                                    RoundedRectangle(cornerRadius: APRadius.md, style: .continuous)
                                        .fill(Color.appSurface)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: APRadius.md, style: .continuous)
                                                .stroke(Color.appBorderSubtle, lineWidth: 1)
                                        )
                                )
                            }
                        }
                    }
                    .padding(APSpacing.md)
                }
            }
            .navigationTitle("quick_messages".localized(for: appLanguage))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showQuickMessages = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
    
    // MARK: - Helpers
    
    private func shouldShowTimestampHeader(for index: Int) -> Bool {
        guard index > 0 else { return true }
        let currentMsg = messages[index]
        let prevMsg = messages[index - 1]
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        guard let currentDate = formatter.date(from: currentMsg.createdAt) ?? ISO8601DateFormatter().date(from: currentMsg.createdAt),
              let prevDate = formatter.date(from: prevMsg.createdAt) ?? ISO8601DateFormatter().date(from: prevMsg.createdAt) else {
            return false
        }
        
        // Show timestamp if messages are sent more than 15 minutes (900 seconds) apart
        return currentDate.timeIntervalSince(prevDate) > 900
    }
    
    private func formatMessageHeaderDate(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: isoString) ?? ISO8601DateFormatter().date(from: isoString) else {
            return ""
        }
        
        let calendar = Calendar.current
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        let timeString = timeFormatter.string(from: date)
        
        if calendar.isDateInToday(date) {
            return "Today \(timeString)"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday \(timeString)"
        } else {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "E, d MMM"
            return "\(dateFormatter.string(from: date)) \(timeString)"
        }
    }

    private func formatMessageTime(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: isoString) ?? ISO8601DateFormatter().date(from: isoString) else {
            return ""
        }
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        return timeFormatter.string(from: date)
    }
    
    private func sendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        messageText = ""
        
        // Optimistic local insert
        let optimisticMsg = ChatMessage(
            id: UUID().uuidString,
            channelId: channel.id,
            senderId: currentEmployeeId,
            senderName: currentEmployeeName,
            text: text,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            isRead: false
        )
        messages.append(optimisticMsg)
        
        Task {
            do {
                _ = try await NetworkService.shared.sendMessage(
                    channelId: channel.id,
                    text: text
                )
            } catch {
                #if DEBUG
                print("ChatDetailView: Failed to send message: \(error)")
                #endif
            }
        }
    }
    
    private func loadMessages() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            messages = try await NetworkService.shared.fetchMessages(channelId: channel.id)
            // Mark as read
            try? await NetworkService.shared.markAsRead(channelId: channel.id)
        } catch {
            #if DEBUG
            print("ChatDetailView: Failed to load messages: \(error)")
            #endif
        }
    }
    
    private func startPolling() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            Task {
                do {
                    let freshMessages = try await NetworkService.shared.fetchMessages(channelId: channel.id)
                    if freshMessages.count != messages.count {
                        await MainActor.run {
                            messages = freshMessages
                        }
                    }
                } catch {}
            }
        }
    }
}

// MARK: - New Message View

struct NewMessageView: View {
    let staffMembers: [StaffMember]
    let onSelectStaff: (StaffMember) -> Void
    
    @AppStorage("app_language") private var appLanguage = "en"
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    
    private var filteredStaff: [StaffMember] {
        if searchText.isEmpty { return staffMembers }
        return staffMembers.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Search bar
                    HStack(spacing: APSpacing.sm) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(Color.textTertiary)
                        
                        TextField("search_staff".localized(for: appLanguage), text: $searchText)
                            .font(.subheadline)
                            .foregroundStyle(Color.textPrimary)
                            .tint(.appAccent)
                    }
                    .padding(APSpacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: APRadius.md, style: .continuous)
                            .fill(Color.appSurface)
                    )
                    .padding(.horizontal, APSpacing.md)
                    .padding(.top, APSpacing.sm)
                    
                    // Staff list
                    ScrollView {
                        LazyVStack(spacing: APSpacing.sm) {
                            ForEach(filteredStaff) { staff in
                                Button {
                                    onSelectStaff(staff)
                                } label: {
                                    HStack(spacing: APSpacing.md) {
                                        ZStack(alignment: .bottomTrailing) {
                                            Circle()
                                                .fill(
                                                    LinearGradient(
                                                        colors: [.appTeal.opacity(0.8), .appGreen.opacity(0.6)],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    )
                                                )
                                                .frame(width: 44, height: 44)
                                                .overlay(
                                                    Text(String(staff.name.prefix(1)).uppercased())
                                                        .font(.system(size: 16, weight: .bold))
                                                        .foregroundStyle(.white)
                                                )
                                            
                                            // Online indicator
                                            Circle()
                                                .fill(staff.isOnline ? Color.appGreen : Color.textTertiary)
                                                .frame(width: 12, height: 12)
                                                .overlay(
                                                    Circle().stroke(Color.appBackground, lineWidth: 2)
                                                )
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(staff.name)
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundStyle(Color.textPrimary)
                                            
                                            HStack(spacing: 4) {
                                                Text(staff.role.capitalized)
                                                    .font(.caption)
                                                    .foregroundStyle(Color.textSecondary)
                                                
                                                Text("•")
                                                    .foregroundStyle(Color.textTertiary)
                                                
                                                Text(staff.isOnline ? "online".localized(for: appLanguage) : "offline".localized(for: appLanguage))
                                                    .font(.caption)
                                                    .foregroundStyle(staff.isOnline ? Color.appGreen : Color.textTertiary)
                                            }
                                        }
                                        
                                        Spacer()
                                        
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(Color.textTertiary)
                                    }
                                    .padding(APSpacing.md)
                                    .background(
                                        RoundedRectangle(cornerRadius: APRadius.md, style: .continuous)
                                            .fill(Color.appSurface)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: APRadius.md, style: .continuous)
                                                    .stroke(Color.appBorderSubtle, lineWidth: 1)
                                            )
                                    )
                                }
                            }
                        }
                        .padding(.horizontal, APSpacing.md)
                        .padding(.top, APSpacing.md)
                    }
                }
            }
            .navigationTitle("direct_message".localized(for: appLanguage))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Text("cancel".localized(for: appLanguage))
                            .foregroundStyle(Color.appAccent)
                    }
                }
            }
        }
        .presentationDetents([.large])
    }
}

// MARK: - Unread Badge Helper

struct MessagingBadgeView: View {
    let count: Int
    
    var body: some View {
        if count > 0 {
            Text("\(count)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    Capsule().fill(Color.appAccent)
                )
        }
    }
}

// MARK: - iMessage Bubble Shape
struct MessageBubbleShape: Shape {
    let isMine: Bool
    
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: isMine ?
                [.topLeft, .topRight, .bottomLeft] :
                [.topLeft, .topRight, .bottomRight],
            cornerRadii: CGSize(width: 17, height: 17)
        )
        return Path(path.cgPath)
    }
}
