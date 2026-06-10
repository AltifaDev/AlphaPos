import SwiftUI

struct NotificationListView: View {
    private var networkService = NetworkService.shared
    @AppStorage("app_language") private var appLanguage = "en"
    
    private var requests: [ServiceRequest] {
        networkService.serviceRequests.filter { $0.status == "pending" }
    }
    
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    if isLoading && requests.isEmpty {
                        ProgressView().tint(.appAccent).frame(maxHeight: .infinity)
                    } else if requests.isEmpty {
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
                            ForEach(requests) { req in
                                requestRow(req: req)
                                    .listRowBackground(Color.appSurface)
                                    .listRowSeparator(.hidden)
                                    .padding(.vertical, 4)
                            }
                        }
                        .listStyle(.plain)
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
    
    private func requestRow(req: ServiceRequest) -> some View {
        let isBill = req.requestType.lowercased().contains("bill") || req.requestType.lowercased().contains("check")
        
        return HStack(spacing: APSpacing.md) {
            // Icon
            ZStack {
                Circle()
                    .fill((isBill ? Color.appRose : Color.appAmber).opacity(0.15))
                    .frame(width: 44, height: 44)
                
                Image(systemName: isBill ? "creditcard.fill" : "bell.fill")
                    .foregroundColor(isBill ? .appRose : .appAmber)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: "table_label".localized(for: appLanguage), req.tableNumber))
                    .font(.subheadline).fontWeight(.black)
                    .foregroundColor(.textPrimary)
                
                Text(req.requestType)
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                
                if let date = isoStringToDate(req.createdAt) {
                    Text(date, style: .time)
                        .font(.caption2)
                        .foregroundColor(.textTertiary)
                }
            }
            
            Spacer()
            
            // Resolve button
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
        }
        .padding(APSpacing.md)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: APRadius.md)
                .stroke(Color.appBorderSubtle, lineWidth: 1)
        )
    }
    
    private func loadRequests() {
        Task {
            isLoading = true
            await networkService.refreshAll()
            isLoading = false
        }
    }
    
    private func resolveRequest(req: ServiceRequest) {
        APHaptic.trigger()
        Task {
            _ = try? await networkService.resolveRequest(requestId: req.id)
        }
    }
    
    private func isoStringToDate(_ str: String) -> Date? {
        let df = ISO8601DateFormatter()
        return df.date(from: str)
    }
}
