import SwiftUI

struct LanguageReloadOverlayView: View {
    let language: AppLanguage
    
    @State private var rotation: Double = 0.0
    
    var titleMessage: String {
        switch language {
        case .english:    return "Applying English..."
        case .thai:       return "กำลังตั้งค่าภาษาไทย..."
        case .chinese:    return "正在应用简体中文..."
        case .japanese:   return "日本語を適用中..."
        case .korean:     return "한국어 적용 중..."
        case .indonesian: return "Menerapkan Bahasa Indonesia..."
        case .malay:      return "Mengenakan Bahasa Melayu..."
        }
    }
    
    var subtitleMessage: String {
        switch language {
        case .english:    return "Please wait while the system reloads."
        case .thai:       return "กรุณารอสักครู่ ระบบกำลังโหลดหน้าจอใหม่"
        case .chinese:    return "请稍候，系统正在重新加载。"
        case .japanese:   return "システム再読み込み中。少々お待ちください。"
        case .korean:     return "시스템을 다시 로드하는 동안 잠시 기다려 주십시오."
        case .indonesian: return "Mohon tunggu selagi sistem memuat ulang."
        case .malay:      return "Sila tunggu sementara sistem memuat semula."
        }
    }
    
    var body: some View {
        ZStack {
            // Glassmorphic / dark backdrop
            Color.black.opacity(0.4)
                .background(.ultraThinMaterial)
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Beautiful custom glowing spinner
                ZStack {
                    Circle()
                        .stroke(Color.appAccent.opacity(0.15), lineWidth: 5)
                        .frame(width: 80, height: 80)
                    
                    Circle()
                        .trim(from: 0, to: 0.35)
                        .stroke(
                            LinearGradient(
                                colors: [Color.appAccent, Color.appAccent.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 5, lineCap: .round)
                        )
                        .frame(width: 80, height: 80)
                        .rotationEffect(.degrees(rotation))
                        .onAppear {
                            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                                rotation = 360.0
                            }
                        }
                    
                    // Center flag icon
                    Text(language.flag)
                        .font(.system(size: 32))
                }
                .shadow(color: Color.appAccent.opacity(0.35), radius: 16, x: 0, y: 4)
                
                VStack(spacing: 8) {
                    Text(titleMessage)
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.textPrimary)
                    
                    Text(subtitleMessage)
                        .font(.subheadline)
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
            .padding(40)
            .background(Color.appSurface)
            .cornerRadius(24)
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color.appBorderSubtle, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.25), radius: 25, x: 0, y: 12)
            .frame(maxWidth: 420)
            .padding(.horizontal, 24)
        }
    }
}
