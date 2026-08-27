/**
 * AlphaPos — Payment Handler Module
 * Customer checkout assistance only.
 *
 * A customer browser must never settle an order or close a table session.
 * Payment is completed atomically by AlphaPos/AlphaPosStaff after staff
 * verifies the tender.  This legacy mixin is retained for the modular UI,
 * but all choices now create the same authenticated service request.
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
        await this.requestCheckoutAssistance(method);
    },

    async showPromptPayQR(amount) {
        void amount;
        await this.requestCheckoutAssistance('promptpay');
    },

    async confirmPromptPayPaid() {
        await this.requestCheckoutAssistance('promptpay');
    },

    async submitPayment(method, amount) {
        void amount;
        await this.requestCheckoutAssistance(method);
    },

    async requestCheckoutAssistance(method) {
        try {
            if (!this.supabase) throw new Error('Customer session is unavailable');
            const idempotencyKey = crypto.randomUUID();
            const { error } = await this.supabase.rpc('create_customer_service_request', {
                p_request_type: 'request_bill',
                p_note: `Preferred payment: ${String(method || 'unspecified').slice(0, 40)}`,
                p_idempotency_key: idempotencyKey
            });
            if (error) throw error;
            this.hidePaymentSelector();
            this._showToast(this.translate('staffNotified', 'Staff has been notified.'), 'success');
        } catch (e) {
            console.error('[Checkout] Assistance request failed:', e);
            this._showToast(e.message, 'error');
        }
    }
};
