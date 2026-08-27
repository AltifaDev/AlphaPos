/**
 * AlphaPos — Realtime Manager Module
 * Handles Supabase Realtime subscriptions and polling fallback.
 */

import { pushManager } from './push-notifications.js';

export const RealtimeManagerMixin = {
    setupRealtimeSubscriptions() {
        if (!this.supabase) {
            this.startPollingFallback();
            return;
        }

        try {
            // Subscribe to order status changes
            const statusChannel = this.supabase
                .channel('status-changes')
                .on('postgres_changes', {
                    event: 'UPDATE',
                    schema: 'public',
                    table: 'orders',
                    filter: `table_number=eq.${this.tableNumber}`
                }, (payload) => {
                    console.log('[Realtime] Order status change:', payload.new?.status);
                    this._handleOrderStatusChange(payload.new);
                })
                .subscribe();
            this.realtimeChannels.push(statusChannel);

            // Subscribe to new orders for this table
            const ordersChannel = this.supabase
                .channel('orders-changes')
                .on('postgres_changes', {
                    event: 'INSERT',
                    schema: 'public',
                    table: 'orders',
                    filter: `table_number=eq.${this.tableNumber}`
                }, (payload) => {
                    console.log('[Realtime] New order:', payload.new?.order_number);
                })
                .subscribe();
            this.realtimeChannels.push(ordersChannel);

            // Subscribe to menu changes
            const menuChannel = this.supabase
                .channel('menu-changes')
                .on('postgres_changes', {
                    event: '*',
                    schema: 'public',
                    table: 'menu_items'
                }, () => {
                    console.log('[Realtime] Menu updated, reloading...');
                    this.loadMenuFromServer();
                })
                .subscribe();
            this.realtimeChannels.push(menuChannel);

            console.log('[Realtime] ✅ Subscribed to 3 channels');
        } catch (e) {
            console.warn('[Realtime] Subscription failed, falling back to polling:', e);
            this.startPollingFallback();
        }
    },

    startPollingFallback() {
        if (this.pollingInterval) return;
        this.pollingInterval = setInterval(() => {
            this._pollForUpdates();
        }, 10000); // 10s
    },

    async _pollForUpdates() {
        try {
            const response = await fetch(`/v1/orders?table_number=${this.tableNumber}&status=preparing`);
            if (response.ok) {
                const orders = await response.json();
                // Check for status changes
                orders.forEach(order => this._handleOrderStatusChange(order));
            }
        } catch (e) {
            // Silent fail for polling
        }
    },

    _handleOrderStatusChange(order) {
        if (!order) return;
        // Update order tracker if active
        if (this._orderTracker && order.id === this._lastOrderId) {
            this._orderTracker.updateStatus(order.status);
        }

        // Notify the customer when their order reaches a relevant status.
        // Only fires for this table's active order, only on a real change,
        // and only when notification permission was granted. Uses the service
        // worker notification already wired in push-notifications.js.
        try {
            const notifyStatuses = {
                ready: {
                    title: this.translate ? this.translate('pushOrderReadyTitle', 'Order Ready! 🔔') : 'Order Ready! 🔔',
                    body: this.translate ? this.translate('pushOrderReadyBody', 'Your order is ready to be served.') : 'Your order is ready to be served.'
                },
                served: {
                    title: this.translate ? this.translate('pushOrderServedTitle', 'Enjoy your meal! 🍽️') : 'Enjoy your meal! 🍽️',
                    body: this.translate ? this.translate('pushOrderServedBody', 'Your order has been served.') : 'Your order has been served.'
                },
                cancelled: {
                    title: this.translate ? this.translate('pushOrderCancelledTitle', 'Order Cancelled') : 'Order Cancelled',
                    body: this.translate ? this.translate('pushOrderCancelledBody', 'Your order has been cancelled. Please contact staff.') : 'Your order has been cancelled. Please contact staff.'
                }
            };
            const isThisTablesOrder = !this._lastOrderId || order.id === this._lastOrderId;
            const changed = order.status !== this._lastNotifiedStatus;
            const info = notifyStatuses[order.status];
            if (info && isThisTablesOrder && changed && pushManager && pushManager.permission === 'granted') {
                pushManager.showLocalNotification(info.title, info.body, {
                    tag: `order-${order.id}`,
                    orderId: order.id,
                    type: 'order_update',
                    url: '/'
                });
                this._lastNotifiedStatus = order.status;
            }
        } catch (e) {
            console.warn('[Realtime] Order status notification failed:', e);
        }

        // Trigger feedback when served
        if (order.status === 'served' && this._feedbackSystem) {
            setTimeout(() => {
                this._feedbackSystem.showFeedbackForm(order.id, this.tableNumber, this.sessionToken);
            }, 5000);
        }
    },

    unsubscribeRealtimeChannels() {
        this.realtimeChannels.forEach(ch => {
            try { ch.unsubscribe(); } catch (e) {}
        });
        this.realtimeChannels = [];
        if (this.pollingInterval) {
            clearInterval(this.pollingInterval);
            this.pollingInterval = null;
        }
    },

    startSyncHealthPolling() {
        this.syncHealthInterval = setInterval(() => this.refreshSyncHealth(), 30000);
    },

    async refreshSyncHealth() {
        try {
            const response = await fetch('/v1/sync/status');
            if (response.ok) {
                const data = await response.json();
                const badge = document.getElementById('syncBadge');
                if (badge && data.pending_count > 0) {
                    badge.textContent = data.pending_count;
                    badge.style.display = 'inline-flex';
                } else if (badge) {
                    badge.style.display = 'none';
                }
            }
        } catch (e) {}
    },

    shutdownRealtime() {
        this.unsubscribeRealtimeChannels();
        if (this.syncHealthInterval) {
            clearInterval(this.syncHealthInterval);
        }
    }
};
