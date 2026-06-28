/**
 * AlphaPos — Payment Handler Module
 * Handles payment selection, PromptPay QR, and payment submission.
 */
import { formatCurrency } from './app-core.js';

export const PaymentHandlerMixin = {
    showPaymentSelector() {
        const sheet = document.getElementById('paymentSheet');
        if (sheet) sheet.classList.add('active');

        const { total } = this.calculateTotals();
        const totalEl = document.getElementById('paymentTotal');
        if (totalEl) totalEl.textContent = formatCurrency(total);
    },

    hidePaymentSelector() {
        const sheet = document.getElementById('paymentSheet');
        if (sheet) sheet.classList.remove('active');
    },

    async selectPaymentMethod(method) {
        const { total } = this.calculateTotals();

        if (method === 'promptpay') {
            await this.showPromptPayQR(total);
        } else if (method === 'cash') {
            await this.submitPayment('Cash', total);
        } else if (method === 'card') {
            await this.submitPayment('Credit Card', total);
        }
    },

    async showPromptPayQR(amount) {
        try {
            const response = await fetch('/v1/payments/intent', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    method: 'promptpay',
                    amount: amount,
                    order_id: this._lastOrderId || ''
                })
            });

            if (response.ok) {
                const data = await response.json();
                // Show QR code UI
                const qrContainer = document.getElementById('promptPayQR');
                if (qrContainer) {
                    qrContainer.innerHTML = `
                        <div class="qr-card">
                            <h3>PromptPay</h3>
                            <p class="qr-amount">${formatCurrency(amount)}</p>
                            <p class="qr-id">${data.promptpay_id || ''}</p>
                            <p class="qr-ref">Ref: ${data.reference || ''}</p>
                            <button onclick="app.confirmPromptPayPaid()" class="confirm-paid-btn">
                                ${this.translate('confirmPaid', 'I have paid')}
                            </button>
                        </div>
                    `;
                    qrContainer.classList.add('active');
                }
            }
        } catch (e) {
            console.error('[Payment] Intent failed:', e);
            this._showToast('Payment error', 'error');
        }
    },

    async confirmPromptPayPaid() {
        const { total } = this.calculateTotals();
        await this.submitPayment('QR PromptPay', total);
    },

    async submitPayment(method, amount) {
        try {
            const response = await fetch('/v1/payments', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    id: `pay-${Date.now()}`,
                    order_id: this._lastOrderId || '',
                    amount: amount,
                    payment_method: method
                })
            });

            if (response.ok) {
                this.hidePaymentSelector();
                this._showToast(this.translate('paymentSuccess', 'Payment successful!'), 'success');

                // Close session and block further ordering
                if (typeof this.closeSessionAfterPayment === 'function') {
                    await this.closeSessionAfterPayment();
                }
            } else {
                throw new Error('Payment failed');
            }
        } catch (e) {
            console.error('[Payment] Submit failed:', e);
            this._showToast(e.message, 'error');
        }
    }
};
