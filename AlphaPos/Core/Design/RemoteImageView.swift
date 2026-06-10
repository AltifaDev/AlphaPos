import SwiftUI

/// A reusable async image view that loads images from remote URLs with fallback to local data or placeholder
struct RemoteImageView: View {
    let imageUrl: String?
    let imageData: Data?
    let fallbackColor: Color
    let fallbackIcon: String
    
    @State private var loadedImage: UIImage? = nil
    @State private var isLoading = false
    @State private var hasError = false
    
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
            // Then try to load from URL
            else if let urlString = imageUrl, !urlString.isEmpty {
                AsyncImage(url: URL(string: urlString)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
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
