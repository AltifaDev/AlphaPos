import SwiftUI

struct SplashScreenView: View {
    let statusText: String
    @State private var pulse = false

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 28) {
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(APGradient.accent)
                        .frame(width: 92, height: 92)
                        .shadow(color: Color.appAccent.opacity(pulse ? 0.55 : 0.25), radius: pulse ? 28 : 14, x: 0, y: 10)

                    Image(systemName: "bolt.fill")
                        .font(.system(size: 44, weight: .black))
                        .foregroundColor(.white)
                }
                .scaleEffect(pulse ? 1.03 : 0.98)

                VStack(spacing: 8) {
                    Text("AlphaPos")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundColor(.textPrimary)

                    Text("splash_secure_pos".t)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.textSecondary)
                }

                HStack(spacing: 10) {
                    ProgressView()
                        .tint(.appAccent)
                    Text(statusText)
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.textSecondary)
                }
                .padding(.top, 8)
                .accessibilityElement(children: .combine)
            }
            .padding(32)
        }
        .apColorScheme()
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}
