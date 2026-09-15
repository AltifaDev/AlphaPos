import SwiftUI

/// Presentation boundary for payment methods used by the POS checkout flow.
/// The owner supplies the payment actions so this view cannot mutate carts or
/// sessions on its own.
struct POSPaymentSheets: ViewModifier {
    @Binding var activePayment: POSActivePaymentMethod?
    let totalAmount: Double
    let onPark: (String) -> Void
    let onCash: (Double) async -> Void
    let onQRCode: () -> Void
    let onCard: () -> Void
    let onThaiChuaThaiPlus: (String) -> Void

    func body(content: Content) -> some View {
        content.fullScreenCover(item: $activePayment) { method in
            switch method {
            case .cash:
                CashPaymentModalView(totalAmount: totalAmount, onPark: {
                    onPark("Cash")
                }) { amount in
                    await onCash(amount)
                }
            case .qrCode:
                QRPaymentModalView(totalAmount: totalAmount, onPark: {
                    onPark("QR PromptPay")
                }) {
                    onQRCode()
                }
            case .creditCard:
                CreditCardPaymentModalView(totalAmount: totalAmount, onPark: {
                    onPark("Credit Card")
                }) {
                    onCard()
                }
            case .thaiChuaThaiPlus:
                ThaiChuaThaiPlusPaymentModal(totalAmount: totalAmount, onPark: {
                    onPark(GovernmentSupportProgram.thaiChuaThaiPlus)
                }) { reference in
                    onThaiChuaThaiPlus(reference)
                }
            }
        }
    }
}
