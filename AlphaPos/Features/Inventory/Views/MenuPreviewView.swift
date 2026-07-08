// MenuPreviewView.swift
// AlphaPos — L-8: Online Menu Preview
//
// Displays the customer-facing web ordering page in a WKWebView so staff
// can see how the menu looks before handing customers the QR code.
// Falls back to a local SwiftData list when offline.

import SwiftUI
import WebKit
import SwiftData

// MARK: - Menu Preview Sheet

struct MenuPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var lm: LocalizationManager
    @AppStorage("active_merchant_id") private var merchantId = ""
    @AppStorage("offline_sync_mode") private var offlineSyncMode = false

    @Query(
        filter: #Predicate<MenuItem> { $0.isAvailable && !$0.isDeleted },
        sort: \MenuItem.name
    ) private var menuItems: [MenuItem]

    @Query(
        filter: #Predicate<Category> { !$0.isDeleted },
        sort: \Category.name
    ) private var categories: [Category]

    @State private var isLoading = true
    @State private var loadError: String? = nil
    @State private var useOfflineFallback = false
    @State private var webViewRef: WKWebView? = nil

    private var customerWebBaseUrl: String {
        let ud = UserDefaults.standard.string(forKey: "dynamic_customer_web_url") ?? ""
        return ud.isEmpty ? "https://alphapos.altifadev.workers.dev" : ud
    }

    private var previewURL: URL? {
        URL(string: "\(customerWebBaseUrl)/?merchant=\(merchantId)&preview=true&lang=\(lm.languageCode)")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                if offlineSyncMode || useOfflineFallback {
                    offlinePreview
                } else {
                    webPreview
                }
            }
            .navigationTitle("menu_preview_title".t)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("close_btn_label".t) { dismiss() }
                        .foregroundColor(.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        // Refresh
                        if !offlineSyncMode && !useOfflineFallback {
                            Button(action: { webViewRef?.reload() }) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.appAccent)
                            }
                        }
                        // Toggle offline preview
                        Button(action: {
                            withAnimation { useOfflineFallback.toggle() }
                        }) {
                            Label(
                                useOfflineFallback ? "menu_preview_web_btn".t : "menu_preview_offline_btn".t,
                                systemImage: useOfflineFallback ? "globe" : "list.bullet"
                            )
                            .font(.caption.bold())
                            .foregroundColor(.appAccent)
                        }
                    }
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Web Preview

    private var webPreview: some View {
        ZStack {
            if let url = previewURL {
                MenuWebView(url: url, isLoading: $isLoading, loadError: $loadError, webViewRef: $webViewRef)

                if isLoading {
                    VStack(spacing: 16) {
                        ProgressView().scaleEffect(1.4)
                        Text("menu_preview_loading".t)
                            .font(.subheadline).foregroundColor(.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.appBackground)
                }

                if let error = loadError {
                    VStack(spacing: 16) {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.system(size: 44)).foregroundColor(.appRose)
                        Text("menu_preview_error_title".t)
                            .font(.headline).foregroundColor(.textPrimary)
                        Text(error).font(.caption).foregroundColor(.textSecondary)
                            .multilineTextAlignment(.center).padding(.horizontal)
                        Button(action: { useOfflineFallback = true }) {
                            Label("menu_preview_offline_btn".t, systemImage: "list.bullet")
                                .font(.subheadline.bold())
                                .padding(.horizontal, 20).padding(.vertical, 10)
                                .background(Color.appSurfaceHigh).foregroundColor(.appAccent)
                                .cornerRadius(10)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.appBackground)
                }
            } else {
                Text("menu_preview_invalid_url".t)
                    .foregroundColor(.textTertiary)
            }
        }
    }

    // MARK: - Offline Fallback Preview

    private var offlinePreview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Banner
                HStack(spacing: 10) {
                    Image(systemName: "list.bullet.rectangle.portrait")
                        .font(.system(size: 18)).foregroundColor(.appAccent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("menu_preview_offline_title".t)
                            .font(.subheadline.bold()).foregroundColor(.textPrimary)
                        Text("menu_preview_offline_desc".t)
                            .font(.caption2).foregroundColor(.textSecondary)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.appAccent.opacity(0.06))

                Divider().background(Color.appDivider)

                // Categories + Items
                let groupedByCategory = Dictionary(grouping: menuItems) { item -> String in
                    item.category?.name ?? "menu_preview_no_category".t
                }
                let sortedKeys = groupedByCategory.keys.sorted()

                ForEach(sortedKeys, id: \.self) { catName in
                    let items = (groupedByCategory[catName] ?? []).sorted { $0.name < $1.name }
                    VStack(alignment: .leading, spacing: 0) {
                        // Category header
                        Text(catName)
                            .font(.caption.bold())
                            .foregroundColor(.appAccent)
                            .tracking(0.8)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.appSurface)

                        Divider().background(Color.appDivider)

                        ForEach(items) { item in
                            menuItemRow(item)
                            Divider().background(Color.appDivider).padding(.leading, 16)
                        }
                    }
                }

                if menuItems.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "fork.knife").font(.system(size: 44)).foregroundColor(.textTertiary)
                        Text("menu_preview_no_items".t).font(.headline).foregroundColor(.textSecondary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 40)
                }
            }
        }
        .background(Color.appBackground)
    }

    private func menuItemRow(_ item: MenuItem) -> some View {
        HStack(spacing: 12) {
            // Thumbnail
            if let data = item.imageData, let uiImg = UIImage(data: data) {
                Image(uiImage: uiImg)
                    .resizable().scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.appSurfaceHigh)
                    .frame(width: 56, height: 56)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(.textTertiary).font(.system(size: 20))
                    )
            }

            // Name + description
            VStack(alignment: .leading, spacing: 3) {
                Text(item.localizedName)
                    .font(.system(size: 14, weight: .semibold)).foregroundColor(.textPrimary)
                if let desc = item.descriptionTranslations[lm.languageCode],
                   !desc.isEmpty {
                    Text(desc)
                        .font(.caption2).foregroundColor(.textSecondary).lineLimit(2)
                }
                if !item.isAvailable {
                    Text("menu_preview_unavailable".t)
                        .font(.caption2.bold()).foregroundColor(.appRose)
                }
            }

            Spacer()

            // Price
            Text(String(format: "฿%.0f", item.price))
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(.appAccent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.appBackground)
    }
}

// MARK: - WKWebView Wrapper

struct MenuWebView: UIViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool
    @Binding var loadError: String?
    @Binding var webViewRef: WKWebView?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        DispatchQueue.main.async { webViewRef = webView }
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: MenuWebView
        init(_ parent: MenuWebView) { self.parent = parent }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.isLoading = true
            parent.loadError = nil
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
            parent.loadError = error.localizedDescription
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
            parent.loadError = error.localizedDescription
        }
    }
}
