/**
 * AlphaPos — Order Submission Module
 * Handles order creation, submission to server, and order history.
 */
import { fetchWithFallback } from './api.js';
import { formatCurrency } from './app-core.js';

export const OrderSubmissionMixin = {
    async submitOrder() {
        if (this.cart.length === 0) return;

        const { total } = this.calculateTotals();
        const orderId = `ord-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
        const orderNumber = `ORD-${String(Date.now()).slice(-4)}`;

        const orderPayload = {
            id: orderId,
            tableNumber: this.tableNumber,
            table_number: this.tableNumber,
            total: total,
            status: 'preparing',
            sessionToken: this.sessionToken,
            guestCount: this.guestCount,
            orderNumber: orderNumber,
            items: this.cart.map(item => ({
                id: item.id,
                item_id: item.item_id,
                name: item.name,
                quantity: item.quantity,
                price: item.price,
                status: 'cooking',
                notes: item.notes || '',
                modifiers: item.modifiers || []
            }))
        };

        try {
            const response = await fetch('/v1/orders', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(orderPayload)
            });

            if (!response.ok) {
                const err = await response.json();
                throw new Error(err.detail || err.error || 'Order submission failed');
            }

            const result = await response.json();
            this._lastOrderId = orderId;

            // Clear cart
            this.clearCartState();

            // Show success
            this._showOrderSuccess(orderNumber, total);

            // Trigger wait time + order tracker
            setTimeout(() => {
                if (this.showWaitTime) this.showWaitTime();
                if (this.showOrderTracker) this.showOrderTracker(orderId);
            }, 2500);

            // Trigger feedback after delay (if order gets served)
            console.log(`[Order] ✅ Submitted: ${orderNumber} (${formatCurrency(total)})`);
            return result;

        } catch (e) {
            console.error('[Order] Submit failed:', e);
            this._showToast(e.message || 'Order failed', 'error');
            throw e;
        }
    },

    _showOrderSuccess(orderNumber, total) {
        const modal = document.getElementById('orderSuccessModal');
        if (modal) {
            const numEl = modal.querySelector('.order-number');
            const totalEl = modal.querySelector('.order-total');
            if (numEl) numEl.textContent = orderNumber;
            if (totalEl) totalEl.textContent = formatCurrency(total);
            modal.classList.add('active');
        }
    },

    hideOrderSuccess() {
        const modal = document.getElementById('orderSuccessModal');
        if (modal) modal.classList.remove('active');
    },

    async loadOrderHistory() {
        try {
            const response = await fetch(`/v1/orders?table_number=${this.tableNumber}`);
            if (response.ok) {
                return await response.json();
            }
        } catch (e) {
            console.warn('[Order] History fetch failed:', e);
        }
        return [];
    },

    async renderOrderHistory() {
        const orders = await this.loadOrderHistory();
        const container = document.getElementById('orderHistoryList');
        if (!container) return;

        if (orders.length === 0) {
            container.innerHTML = `<div class="empty-state">${this.translate('noOrders', 'No orders yet')}</div>`;
            return;
        }

        container.innerHTML = orders.map(order => `
            <div class="order-history-card" data-order-id="${order.id}">
                <div class="order-header">
                    <span class="order-num">${order.order_number}</span>
                    <span class="order-status ${order.status}">${order.status}</span>
                </div>
                <div class="order-items-summary">${order.items?.length || 0} items</div>
                <div class="order-total">${formatCurrency(order.total)}</div>
            </div>
        `).join('');
    }
};
