/**
 * AlphaPos — Realtime Manager Module
 * Handles Supabase Realtime subscriptions and polling fallback.
 */

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
