import SwiftUI

// MARK: - In-memory image cache (L5)
// NSCache is thread-safe and auto-purges under memory pressure
private final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, UIImage>()
    private init() {
        cache.countLimit = 150
        cache.totalCostLimit = 50 * 1024 * 1024  // 50 MB
    }
    func get(_ key: String) -> UIImage? { cache.object(forKey: key as NSString) }
    func set(_ key: String, image: UIImage) { cache.setObject(image, forKey: key as NSString) }
}

// MARK: - Cached Remote Image (replaces bare AsyncImage)

private struct CachedRemoteImage<Fallback: View>: View {
    let urlString: String
    let fallbackIconView: Fallback

    // Start nil; populate from cache or network in task(id:) below
    @State private var uiImage: UIImage? = nil

    var body: some View {
        Group {
            if let uiImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                AsyncImage(url: URL(string: urlString)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .onAppear {
                                // Render and cache the UIImage on first load
                                Task.detached(priority: .background) {
                                    if let url = URL(string: urlString),
                                       let data = try? Data(contentsOf: url),
                                       let img = UIImage(data: data) {
                                        ImageCache.shared.set(urlString, image: img)
                                        await MainActor.run { uiImage = img }
                                    }
                                }
                            }
                    case .failure(_):
                        fallbackIconView
                    case .empty:
                        ProgressView()
                            .tint(.white.opacity(0.6))
                    @unknown default:
                        fallbackIconView
                    }
                }
            }
        }
        .task(id: urlString) {
            // Check cache on first appearance (and when urlString changes)
            if let cached = ImageCache.shared.get(urlString) {
                uiImage = cached
            }
        }
    }
}

// MARK: - RemoteImageView

/// A reusable async image view that loads images from remote URLs with fallback to local data or placeholder
struct RemoteImageView: View {
    let imageUrl: String?
    let imageData: Data?
    let fallbackColor: Color
    let fallbackIcon: String

    var body: some View {
        ZStack {
            // Fallback gradient background
            LinearGradient(
                colors: [fallbackColor, fallbackColor.opacity(0.5)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Try to display local image data first
            if let imageData = imageData, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            }
            // Then try to load from URL with caching
            else if let urlString = imageUrl, !urlString.isEmpty {
                CachedRemoteImage(urlString: urlString, fallbackIconView: fallbackIconView)
            }
            // Fallback icon if no image available
            else {
                fallbackIconView
            }
        }
    }

    private var fallbackIconView: some View {
        Image(systemName: fallbackIcon)
            .font(.system(size: 32, weight: .light))
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
