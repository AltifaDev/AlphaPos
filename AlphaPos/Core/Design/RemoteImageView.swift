import SwiftUI
import Foundation
import UIKit
import CryptoKit
import ImageIO

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

    /// Synchronously check or decode and cache binary image data
    func getOrDecode(data: Data) -> UIImage? {
        let key = "data_\(data.count)_\(data.prefix(32).hashValue)" as NSString
        if let cached = memoryCache.object(forKey: key) {
            return cached
        }
        guard let image = UIImage(data: data) else { return nil }
        memoryCache.setObject(image, forKey: key)
        return image
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
            let (data, _) = try await AppNetworkTransport.data(from: url, purpose: .remoteMedia)
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

    func loadThumbnail(from urlString: String, targetPixelSize: CGFloat) async -> UIImage? {
        let roundedSize = max(64, Int(targetPixelSize.rounded()))
        let cacheKey = "thumbnail_\(roundedSize)_\(urlString)"
        if let cached = getFromMemory(key: cacheKey) { return cached }
        guard let filename = cacheFilename(for: urlString) else { return nil }
        let diskURL = diskCacheURL?.appendingPathComponent(filename)
        let data: Data?
        if let diskURL, FileManager.default.fileExists(atPath: diskURL.path) {
            data = try? Data(contentsOf: diskURL, options: .mappedIfSafe)
        } else if let url = URL(string: urlString),
                  let response = try? await AppNetworkTransport.data(from: url, purpose: .remoteMedia) {
            data = response.0
            if let diskURL, let data {
                Task.detached(priority: .utility) { try? data.write(to: diskURL, options: .atomic) }
            }
        } else { data = nil }
        guard let data,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: roundedSize,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        let image = UIImage(cgImage: cgImage)
        memoryCache.setObject(image, forKey: cacheKey as NSString, cost: cgImage.bytesPerRow * cgImage.height)
        return image
    }

    func prefetchThumbnails(urls: [String], targetPixelSize: CGFloat) {
        Task.detached(priority: .utility) {
            for url in urls where !url.isEmpty {
                guard !Task.isCancelled else { return }
                _ = await self.loadThumbnail(from: url, targetPixelSize: targetPixelSize)
            }
        }
    }
}

struct RemoteThumbnailView: View {
    let imageUrl: String?
    let targetPixelSize: CGFloat
    let fallbackColor: Color
    let fallbackIcon: String
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            LinearGradient(colors: [fallbackColor, fallbackColor.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing)
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else { Image(systemName: fallbackIcon).font(.system(size: 32, weight: .light)).foregroundStyle(.white.opacity(0.8)) }
        }
        .task(id: imageUrl) {
            guard let imageUrl, !imageUrl.isEmpty else { return }
            image = await RemoteImageManager.shared.loadThumbnail(from: imageUrl, targetPixelSize: targetPixelSize)
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

            // 1. Local/Database Image Binary Data (Instant & Cached)
            if let imageData = imageData, let uiImage = RemoteImageManager.shared.getOrDecode(data: imageData) {
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
