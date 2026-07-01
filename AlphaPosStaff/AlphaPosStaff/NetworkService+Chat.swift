// NetworkService+Chat.swift
// Staff messaging: channels, messages, read state, online staff, direct channels.

import Foundation

extension NetworkService {
    
    // MARK: - Staff Messaging
    
    func fetchChannels() async throws -> [ChatChannel] {
        let employeeId = UserDefaults.standard.string(forKey: "logged_in_employee_id") ?? ""
        guard !employeeId.isEmpty else { return [] }
        
        // 1. Check if a merchant-wide Team Chat channel exists
        let teamData = try await sendSupabaseRequest(method: "GET", endpoint: "chat_channels", queryItems: [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "merchant_id", value: "eq.\(activeMerchantId)"),
            URLQueryItem(name: "channel_type", value: "eq.team")
        ])
        let teamArray = (try? JSONSerialization.jsonObject(with: teamData) as? [[String: Any]]) ?? []
        
        if teamArray.isEmpty {
            // Auto-create team channel
            let teamChannelId = UUID().uuidString
            let payload: [String: Any] = [
                "id": teamChannelId,
                "name": "Team Chat",
                "channel_type": "team",
                "participants": [employeeId],
                "merchant_id": activeMerchantId
            ]
            _ = try? await sendSupabaseRequest(method: "POST", endpoint: "chat_channels", payload: payload)
        } else if let firstTeam = teamArray.first {
            let teamId = firstTeam["id"] as? String ?? ""
            let rawParticipants = firstTeam["participants"]
            var participants: [String] = []
            if let arr = rawParticipants as? [String] {
                participants = arr
            } else if let str = rawParticipants as? String {
                participants = str.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            }
            
            if !participants.contains(employeeId) {
                // Add current employee to the team channel
                participants.append(employeeId)
                _ = try? await sendSupabaseRequest(method: "PATCH", endpoint: "chat_channels", queryItems: [
                    URLQueryItem(name: "id", value: "eq.\(teamId)")
                ], payload: ["participants": participants])
            }
        }
        
        // 2. Fetch all channels where current employee is a participant
        let data = try await sendSupabaseRequest(method: "GET", endpoint: "chat_channels", queryItems: [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "participants", value: "cs.{\(employeeId)}"),
            URLQueryItem(name: "order", value: "last_message_at.desc.nullslast")
        ])
        let jsonArray = (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
        
        // Fetch all unread messages to count them per channel ID
        let unreadData = (try? await sendSupabaseRequest(method: "GET", endpoint: "chat_messages", queryItems: [
            URLQueryItem(name: "select", value: "id,channel_id"),
            URLQueryItem(name: "sender_id", value: "neq.\(employeeId)"),
            URLQueryItem(name: "is_read", value: "eq.false")
        ])) ?? Data()
        let unreadMessages = (try? JSONSerialization.jsonObject(with: unreadData) as? [[String: Any]]) ?? []
        
        // Group unread counts by channel_id
        var unreadCounts: [String: Int] = [:]
        for msg in unreadMessages {
            if let chId = msg["channel_id"] as? String {
                unreadCounts[chId, default: 0] += 1
            }
        }
        
        // Update global unreadChatCount
        await MainActor.run {
            self.unreadChatCount = unreadMessages.count
        }
        
        return jsonArray.compactMap { dict in
            guard let id = dict["id"] as? String,
                  let name = dict["name"] as? String,
                  let channelType = dict["channel_type"] as? String else { return nil }
            
            let participants: [String]
            if let arr = dict["participants"] as? [String] {
                participants = arr
            } else if let str = dict["participants"] as? String {
                participants = str.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            } else {
                participants = []
            }
            
            return ChatChannel(
                id: id,
                name: name,
                type: channelType,
                participants: participants,
                lastMessage: dict["last_message_text"] as? String,
                lastMessageAt: dict["last_message_at"] as? String,
                unreadCount: unreadCounts[id] ?? 0
            )
        }
    }
    
    func fetchMessages(channelId: String) async throws -> [ChatMessage] {
        let data = try await sendSupabaseRequest(method: "GET", endpoint: "chat_messages", queryItems: [
            URLQueryItem(name: "select", value: "*,employees(first_name,last_name)"),
            URLQueryItem(name: "channel_id", value: "eq.\(channelId)"),
            URLQueryItem(name: "order", value: "created_at.asc"),
            URLQueryItem(name: "limit", value: "100")
        ])
        let jsonArray = (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
        return jsonArray.compactMap { dict in
            guard let id = dict["id"] as? String,
                  let senderId = dict["sender_id"] as? String,
                  let text = dict["message_text"] as? String,
                  let createdAt = dict["created_at"] as? String else { return nil }
            
            let empDict = dict["employees"] as? [String: Any]
            let firstName = empDict?["first_name"] as? String ?? ""
            let lastName = empDict?["last_name"] as? String ?? ""
            let senderName = firstName.isEmpty ? "Staff" : "\(firstName) \(lastName)"
            
            return ChatMessage(
                id: id,
                channelId: channelId,
                senderId: senderId,
                senderName: senderName,
                text: text,
                createdAt: createdAt,
                isRead: dict["is_read"] as? Bool ?? false
            )
        }
    }
    
    @discardableResult
    func sendMessage(channelId: String, text: String) async throws -> ChatMessage {
        let employeeId = UserDefaults.standard.string(forKey: "logged_in_employee_id") ?? ""
        let employeeName = UserDefaults.standard.string(forKey: "logged_in_employee_name") ?? "Staff"
        let messageId = UUID().uuidString
        
        let payload: [String: Any] = [
            "id": messageId,
            "channel_id": channelId,
            "sender_id": employeeId,
            "message_text": text,
            "merchant_id": activeMerchantId,
            "is_read": false
        ]
        
        _ = try await sendSupabaseRequest(method: "POST", endpoint: "chat_messages", payload: payload)
        
        // Update channel last_message
        _ = try? await sendSupabaseRequest(method: "PATCH", endpoint: "chat_channels", queryItems: [
            URLQueryItem(name: "id", value: "eq.\(channelId)")
        ], payload: [
            "last_message_text": text,
            "last_message_at": ISO8601DateFormatter().string(from: Date())
        ])
        
        return ChatMessage(
            id: messageId,
            channelId: channelId,
            senderId: employeeId,
            senderName: employeeName,
            text: text,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            isRead: false
        )
    }
    
    func markAsRead(channelId: String) async throws {
        let employeeId = UserDefaults.standard.string(forKey: "logged_in_employee_id") ?? ""
        _ = try await sendSupabaseRequest(method: "PATCH", endpoint: "chat_messages", queryItems: [
            URLQueryItem(name: "channel_id", value: "eq.\(channelId)"),
            URLQueryItem(name: "sender_id", value: "neq.\(employeeId)"),
            URLQueryItem(name: "is_read", value: "eq.false")
        ], payload: ["is_read": true])
    }
    
    func fetchOnlineStaff() async throws -> [StaffMember] {
        let data = try await sendSupabaseRequest(method: "GET", endpoint: "employees", queryItems: [
            URLQueryItem(name: "select", value: "id,first_name,last_name,role"),
            URLQueryItem(name: "merchant_id", value: "eq.\(activeMerchantId)")
        ])
        let jsonArray = (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
        let currentId = UserDefaults.standard.string(forKey: "logged_in_employee_id") ?? ""
        return jsonArray.compactMap { dict in
            guard let id = dict["id"] as? String, id != currentId else { return nil }
            let firstName = dict["first_name"] as? String ?? ""
            let lastName = dict["last_name"] as? String ?? ""
            let role = dict["role"] as? String ?? "staff"
            return StaffMember(id: id, name: "\(firstName) \(lastName)", role: role, isOnline: true)
        }
    }
    
    func createDirectChannel(participantId: String, participantName: String) async throws -> ChatChannel {
        let employeeId = UserDefaults.standard.string(forKey: "logged_in_employee_id") ?? ""
        let employeeName = UserDefaults.standard.string(forKey: "logged_in_employee_name") ?? "Me"
        let channelId = UUID().uuidString
        
        let payload: [String: Any] = [
            "id": channelId,
            "name": participantName,
            "channel_type": "direct",
            "participants": [employeeId, participantId],
            "merchant_id": activeMerchantId
        ]
        
        _ = try await sendSupabaseRequest(method: "POST", endpoint: "chat_channels", payload: payload)
        
        return ChatChannel(
            id: channelId,
            name: participantName,
            type: "direct",
            participants: [employeeId, participantId],
            lastMessage: nil,
            lastMessageAt: nil,
            unreadCount: 0
        )
    }
    
    func fetchTotalUnreadChatCount() async -> Int {
        let employeeId = UserDefaults.standard.string(forKey: "logged_in_employee_id") ?? ""
        guard !employeeId.isEmpty else { return 0 }
        
        do {
            let unreadData = try await sendSupabaseRequest(method: "GET", endpoint: "chat_messages", queryItems: [
                URLQueryItem(name: "select", value: "id"),
                URLQueryItem(name: "sender_id", value: "neq.\(employeeId)"),
                URLQueryItem(name: "is_read", value: "eq.false")
            ])
            let unreadMessages = (try? JSONSerialization.jsonObject(with: unreadData) as? [[String: Any]]) ?? []
            
            // Update the local observable property on MainActor
            let count = unreadMessages.count
            await MainActor.run {
                self.unreadChatCount = count
            }
            return count
        } catch {
            print("fetchTotalUnreadChatCount: Failed to fetch unread chat count: \(error)")
            return 0
        }
    }
}
