import SwiftUI

/// POS-owned transient alerts and banners.
/// Transactional state remains in `POSView`; this modifier only renders it.
struct POSAlerts: ViewModifier {
    @EnvironmentObject private var lm: LocalizationManager
    @Binding var showingErrorBanner: Bool
    @Binding var errorMessage: String?
    @Binding var showUnsavedCartNavigationAlert: Bool

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if showingErrorBanner, let message = errorMessage {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.white)
                        Text(message)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                        Spacer()
                        Button {
                            withAnimation { showingErrorBanner = false }
                        } label: {
                            Image(systemName: "xmark")
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.appRose)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: Color.appRose.opacity(0.3), radius: 8, y: 4)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showingErrorBanner)
            .alert(
                lm.currentLanguage == .thai ? "มีรายการที่ยังไม่บันทึก" : "Unsaved order",
                isPresented: $showUnsavedCartNavigationAlert
            ) {
                Button(lm.currentLanguage == .thai ? "อยู่หน้านี้ต่อ" : "Stay here", role: .cancel) {}
            } message: {
                Text(lm.currentLanguage == .thai
                    ? "กรุณาบันทึก พักรายการ หรือเคลียร์ตะกร้าก่อนเปลี่ยนหน้า"
                    : "Save, hold, or clear the cart before leaving POS.")
            }
    }
}
