/**
 * AlphaPos — Order Submission Module
 * Handles order creation via PostgreSQL RPC create_customer_order and order history.
 */
import { formatCurrency } from './app-core.js';
import { orderingSessionGate } from './ordering-session-gate.js';

export const OrderSubmissionMixin = {
    async submitOrder() {
        if (this._submitInProgress) return;
        if (!orderingSessionGate.canOrder()) {
            this._showToast(this.translate('orderingBlockedSession', 'This table session is closed. Please scan QR again.'), 'error');
            return;
        }

        const cartItems = Array.isArray(this.cart) ? this.cart : Object.values(this.cart || {});
        if (cartItems.length === 0) return;

        this._submitInProgress = true;
        const generateUUID = () => (typeof crypto !== 'undefined' && crypto.randomUUID)
            ? crypto.randomUUID()
            : 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, c => {
                const r = Math.random() * 16 | 0;
                return (c === 'x' ? r : (r & 0x3 | 0x8)).toString(16);
            });

        const orderId = generateUUID();
        const idempotencyKey = generateUUID();
        const now = new Date();
        const dateStr = `${now.getFullYear()}${String(now.getMonth() + 1).padStart(2, '0')}${String(now.getDate()).padStart(2, '0')}`;
        const randomSuffix = Math.floor(1000 + Math.random() * 9000);
        const orderNumber = `ORD-${dateStr}-${randomSuffix}`;

        const { subtotal = 0, discount = 0, serviceCharge = 0, tax = 0, total = 0 } = this.calculateTotals ? this.calculateTotals() : { total: 0 };

        const orderPayload = {
            id: orderId,
            order_number: orderNumber,
            table_number: this.tableNumber,
            total: total,
            subtotal: subtotal,
            discount: discount,
            tax: tax,
            service_charge: serviceCharge,
            status: 'pending',
            order_source: 'web',
            is_staff_confirmed: false,
            session_token: this.sessionToken,
            guest_count: Number(this.selectedGuestCount || this.guestCount || 2),
            merchant_id: this.merchantId,
            branch_id: this.branchId,
            idempotency_key: idempotencyKey,
            created_at: now.toISOString()
        };

        const itemsPayload = [];
        const modifiersPayload = [];

        cartItems.forEach(item => {
            if (!item) return;
            const itemId = item.item_id || item.id;
            const itemRowId = generateUUID();
            const qty = Math.max(1, Number(item.quantity || item.qty || 1));
            const price = Number(item.price || 0);

            itemsPayload.push({
                id: itemRowId,
                order_id: orderId,
                item_name: item.name || item.item_name || 'Item',
                quantity: qty,
                price: price,
                status: 'pending',
                item_id: itemId,
                merchant_id: this.merchantId,
                branch_id: this.branchId,
                notes: item.notes || ''
            });

            if (item.modifiers && Array.isArray(item.modifiers)) {
                item.modifiers.forEach(mod => {
                    modifiersPayload.push({
                        id: generateUUID(),
                        order_item_id: itemRowId,
                        modifier_id: mod.modifier_id || mod.id,
                        price: Number(mod.price || mod.extra_price || 0),
                        merchant_id: this.merchantId
                    });
                });
            }
        });

        try {
            if (this.supabase) {
                const { data, error } = await this.supabase.rpc('create_customer_order', {
                    p_order: orderPayload,
                    p_items: itemsPayload,
                    p_modifiers: modifiersPayload
                });
                if (error) throw error;
            } else if (this.isLocalServerAvailable && !window.ALPHAPOS_CONFIG?.isProduction) {
                const res = await fetch(`${this.localServerURL || ''}/v1/orders`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify(orderPayload)
                });
                if (!res.ok) {
                    const err = await res.json().catch(() => ({}));
                    throw new Error(err.detail?.message || err.detail || 'Order failed');
                }
            } else {
                throw new Error('No connection to ordering server.');
            }

            this._lastOrderId = orderId;
            this._lastOrderNumber = orderNumber;

            // Clear cart
            if (this.clearCartState) this.clearCartState();
            else if (this.cart) {
                this.cart = Array.isArray(this.cart) ? [] : {};
                if (this.saveCartToStorage) this.saveCartToStorage();
                if (this.updateCartUI) this.updateCartUI();
            }

            // Show success
            this._showOrderSuccess(orderNumber, total);

            // Trigger wait time + tracker
            setTimeout(() => {
                if (this.showWaitTime) this.showWaitTime();
                if (this.showOrderTracker) this.showOrderTracker(orderId);
            }, 2500);

            console.log(`[Order] ✅ Submitted via RPC: ${orderNumber} (${formatCurrency(total)})`);
            return { id: orderId, order_number: orderNumber };
        } catch (e) {
            console.error('[Order] Submit failed:', e);
            this._showToast?.(e.message || 'Order failed', 'error');
            throw e;
        } finally {
            this._submitInProgress = false;
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
        if (this.supabase && this.sessionToken) {
            try {
                const { data, error } = await this.supabase
                    .from('orders')
                    .select('*, order_items(*)')
                    .eq('session_token', this.sessionToken)
                    .order('created_at', { ascending: false });
                if (!error && data) return data;
            } catch (err) {
                console.warn('[OrderHistory] Supabase fetch failed:', err);
            }
        }

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
                <div class="order-items-summary">${(order.order_items || order.items)?.length || 0} items</div>
                <div class="order-total">${formatCurrency(order.total)}</div>
            </div>
        `).join('');
    }
};
