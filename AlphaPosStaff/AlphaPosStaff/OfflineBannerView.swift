// OfflineBannerView.swift
// AlphaPosStaff — Offline Status Banner
// Shows a persistent banner when device is offline with queue info.

import SwiftUI

struct OfflineBannerView: View {
    @AppStorage("app_language") private var appLanguage = "en"
    let queueCount: Int
    var isSyncing: Bool = false
    
    var body: some View {
        HStack(spacing: 10) {
            // Status icon
            ZStack {
                Circle()
                    .fill(isSyncing ? Color.orange.opacity(0.2) : Color.red.opacity(0.2))
                    .frame(width: 28, height: 28)
                
                if isSyncing {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.orange)
                        .rotationEffect(.degrees(isSyncing ? 360 : 0))
                } else {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.red)
                }
            }
            
            // Text
            VStack(alignment: .leading, spacing: 1) {
                Text(isSyncing ? "offline_syncing".localized(for: appLanguage) : "offline_banner".localized(for: appLanguage))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(isSyncing ? .orange : .red)
                
                Text("offline_banner_desc".localized(for: appLanguage))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Queue badge
            if queueCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "tray.full.fill")
                        .font(.system(size: 10))
                    Text("\(queueCount)")
                        .font(.system(size: 11, weight: .bold))
                    Text("offline_queued".localized(for: appLanguage))
                        .font(.system(size: 10))
                }
                .foregroundColor(.orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.12))
                .cornerRadius(6)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(UIColor.systemBackground).opacity(0.95))
                .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSyncing ? Color.orange.opacity(0.3) : Color.red.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal)
        .padding(.top, 4)
    }
}

// MARK: - Compact version (for inside tabs)

struct OfflineBadge: View {
    @AppStorage("app_language") private var appLanguage = "en"
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 9, weight: .bold))
            Text("offline_banner".localized(for: appLanguage))
                .font(.system(size: 9, weight: .bold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.red.opacity(0.85))
        .cornerRadius(10)
    }
}

#Preview {
    VStack(spacing: 20) {
        OfflineBannerView(queueCount: 3, isSyncing: false)
        OfflineBannerView(queueCount: 1, isSyncing: true)
        OfflineBadge()
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
