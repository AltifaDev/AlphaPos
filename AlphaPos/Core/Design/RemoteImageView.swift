import SwiftUI
import Foundation
import UIKit
import CryptoKit

// MARK: - RemoteImageManager (High-Performance Memory & Disk Cache)

final class RemoteImageManager: @unchecked Sendable {
    static let shared = RemoteImageManager()

    let memoryCache = NSCache<NSString, UIImage>()
    private var diskCacheURL: URL? = nil

    private init() {
        memoryCache.countLimit = 250
        memoryCache.totalCostLimit = 64 * 1024 * 1024  // 64 MB

        let fileManager = FileManager.default
        if let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let dir = cacheDir.appendingPathComponent("ProductImages", isDirectory: true)
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            diskCacheURL = dir
        }
    }

    private func cacheFilename(for urlString: String) -> String? {
        guard let data = urlString.data(using: .utf8) else { return nil }
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02hhx", $0) }.joined()
    }

    /// Synchronously check if the image is in the memory cache
    func getFromMemory(key: String) -> UIImage? {
        return memoryCache.object(forKey: key as NSString)
    }

    /// Loads the image from memory cache, disk cache, or downloads it from network if not cached.
    func loadImage(from urlString: String) async -> UIImage? {
        if let cached = getFromMemory(key: urlString) {
            return cached
        }

        guard let filename = cacheFilename(for: urlString) else { return nil }
        let diskURL = diskCacheURL?.appendingPathComponent(filename)

        // Check disk cache
        if let diskURL = diskURL, FileManager.default.fileExists(atPath: diskURL.path) {
            if let data = try? Data(contentsOf: diskURL), let image = UIImage(data: data) {
                memoryCache.setObject(image, forKey: urlString as NSString)
                return image
            }
        }

        // Fetch from network
        guard let url = URL(string: urlString) else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data) else { return nil }

            // Save to memory cache
            memoryCache.setObject(image, forKey: urlString as NSString)

            // Save to disk cache in background
            if let diskURL = diskURL {
                Task.detached(priority: .background) {
                    try? data.write(to: diskURL)
                }
            }

            return image
        } catch {
            return nil
        }
    }

    /// Enqueues background prefetching tasks for a list of URLs
    func prefetchImages(urls: [String]) {
        Task.detached(priority: .background) {
            for urlString in urls {
                if urlString.isEmpty { continue }
                _ = await self.loadImage(from: urlString)
            }
        }
    }
}

// MARK: - CachedRemoteImage (Synchronous Cache Check + Asynchronous Task Loader)

private struct CachedRemoteImage<Fallback: View>: View {
    let urlString: String
    let fallbackIconView: Fallback

    @State private var uiImage: UIImage? = nil

    var body: some View {
        Group {
            if let uiImage = uiImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                fallbackIconView
                    .onAppear {
                        // Check memory cache synchronously to prevent any flicker during cell reuse/scrolling
                        if let cached = RemoteImageManager.shared.getFromMemory(key: urlString) {
                            self.uiImage = cached
                        }
                    }
            }
        }
        .task(id: urlString) {
            if uiImage == nil {
                let img = await RemoteImageManager.shared.loadImage(from: urlString)
                if !Task.isCancelled {
                    self.uiImage = img
                }
            }
        }
    }
}

// MARK: - RemoteImageView

/// A high-performance async image view that loads images from remote URLs with dual caching and instant fallback
struct RemoteImageView: View {
    let imageUrl: String?
    let imageData: Data?
    let fallbackColor: Color
    let fallbackIcon: String
    var iconSize: CGFloat = 32

    var body: some View {
        ZStack {
            // Fallback background
            LinearGradient(
                colors: [fallbackColor, fallbackColor.opacity(0.5)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // 1. Local/Database Image Binary Data (Instant)
            if let imageData = imageData, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            }
            // 2. Remote URL Image (Double-Cached)
            else if let urlString = imageUrl, !urlString.isEmpty {
                CachedRemoteImage(urlString: urlString, fallbackIconView: fallbackIconView)
            }
            // 3. Fallback Placeholder Icon
            else {
                fallbackIconView
            }
        }
    }

    private var fallbackIconView: some View {
        Image(systemName: fallbackIcon)
            .font(.system(size: iconSize, weight: .light))
            .foregroundColor(.white.opacity(0.8))
    }
}

#Preview {
    HStack(spacing: 16) {
        RemoteImageView(
            imageUrl: nil,
            imageData: nil,
            fallbackColor: Color(hex: "1E1B4B"),
            fallbackIcon: "fork.knife"
        )
        .frame(height: 110)

        RemoteImageView(
            imageUrl: "https://images.unsplash.com/photo-1546069901-ba9599a7e63c?w=400&q=80",
            imageData: nil,
            fallbackColor: Color(hex: "1E1B4B"),
            fallbackIcon: "fork.knife"
        )
        .frame(height: 110)
    }
}
