/**
 * AlphaPos - Order Progress Tracker Module
 * 
 * Visual vertical timeline showing real-time order status:
 * Placed → Confirmed → Preparing → Ready → Served
 * 
 * Uses Supabase Realtime to subscribe to order_status_history changes.
 */

export class OrderTracker {
    constructor() {
        this.orderId = null;
        this.supabase = null;
        this.channel = null;
        this.containerId = null;
        this.pollInterval = null;
        this.timerInterval = null;
        this.translateFn = null;

        this.steps = [
            { key: 'placed', icon: '📝', dbStatus: 'pending' },
            { key: 'confirmed', icon: '✅', dbStatus: 'confirmed' },
            { key: 'preparing', icon: '👨‍🍳', dbStatus: 'preparing' },
            { key: 'ready', icon: '🔔', dbStatus: 'ready' },
            { key: 'served', icon: '🍽️', dbStatus: 'served' }
        ];

        this.statusHistory = [];
        this.currentStatus = 'pending';
        this.orderData = null;
        this.estimatedWait = null;
        this.orderCreatedAt = null;
    }

    /**
     * Initialize the tracker with an order ID and Supabase client.
     */
    async init(orderId, supabaseClient, options = {}) {
        this.orderId = orderId;
        this.supabase = supabaseClient;
        this.translateFn = options.translate || ((key, fallback) => fallback || key);
        this.merchantId = options.merchantId || '';
        this.localServerURL = options.localServerURL || window.location.origin;

        // Fetch initial order data
        await this.fetchOrderData();
        await this.fetchStatusHistory();
        await this.fetchEstimatedWait();

        // Subscribe to realtime changes
        this.subscribeRealtime();

        // Start elapsed time timer
        this.startTimer();

        // Poll estimated wait every 30s
        this.pollInterval = setInterval(() => this.fetchEstimatedWait(), 30000);
    }

    /**
     * Fetch the order details from Supabase or local server.
     */
    async fetchOrderData() {
        try {
            if (this.supabase) {
                const { data, error } = await this.supabase
                    .from('orders')
                    .select('id, order_number, total, status, created_at, confirmed_at, preparing_at, ready_at, served_at, cancelled_at, table_number, order_type')
                    .eq('id', this.orderId)
                    .single();

                if (!error && data) {
                    this.orderData = data;
                    this.currentStatus = data.status || 'pending';
                    this.orderCreatedAt = new Date(data.created_at);
                    return;
                }
            }

            // Fallback: local server
            const res = await fetch(`${this.localServerURL}/v1/orders?id=${this.orderId}`);
            if (res.ok) {
                const json = await res.json();
                const order = Array.isArray(json) ? json[0] : json;
                if (order) {
                    this.orderData = order;
                    this.currentStatus = order.status || 'pending';
                    this.orderCreatedAt = new Date(order.created_at);
                }
            }
        } catch (e) {
            console.warn('[OrderTracker] Failed to fetch order data:', e);
        }
    }

    /**
     * Fetch status history from order_status_history table.
     */
    async fetchStatusHistory() {
        try {
            if (this.supabase) {
                const { data, error } = await this.supabase
                    .from('order_status_history')
                    .select('*')
                    .eq('order_id', this.orderId)
                    .order('changed_at', { ascending: true });

                if (!error && data) {
                    this.statusHistory = data;
                    if (data.length > 0) {
                        this.currentStatus = data[data.length - 1].to_status;
                    }
                    return;
                }
            }
        } catch (e) {
            console.warn('[OrderTracker] Failed to fetch status history:', e);
        }

        // Derive timeline from order timestamps if history not available
        this.deriveTimelineFromOrder();
    }

    /**
     * Derive timeline from order timestamp columns (fallback).
     */
    deriveTimelineFromOrder() {
        if (!this.orderData) return;
        const o = this.orderData;
        this.statusHistory = [];

        if (o.created_at) {
            this.statusHistory.push({ to_status: 'pending', changed_at: o.created_at });
        }
        if (o.confirmed_at) {
            this.statusHistory.push({ to_status: 'confirmed', changed_at: o.confirmed_at });
        }
        if (o.preparing_at) {
            this.statusHistory.push({ to_status: 'preparing', changed_at: o.preparing_at });
        }
        if (o.ready_at) {
            this.statusHistory.push({ to_status: 'ready', changed_at: o.ready_at });
        }
        if (o.served_at) {
            this.statusHistory.push({ to_status: 'served', changed_at: o.served_at });
        }
    }

    /**
     * Fetch estimated wait time from RPC or local endpoint.
     */
    async fetchEstimatedWait() {
        try {
            if (this.supabase && this.merchantId) {
                const { data, error } = await this.supabase
                    .rpc('get_estimated_wait_time', { p_merchant_id: this.merchantId });

                if (!error && data) {
                    this.estimatedWait = data;
                    this.renderETA();
                    return;
                }
            }

            // Fallback: local server
            const res = await fetch(`${this.localServerURL}/v1/wait-time`);
            if (res.ok) {
                const json = await res.json();
                this.estimatedWait = json;
                this.renderETA();
            }
        } catch (e) {
            console.warn('[OrderTracker] Failed to fetch wait time:', e);
        }
    }

    /**
     * Subscribe to realtime status changes.
     */
    subscribeRealtime() {
        if (!this.supabase) return;

        try {
            this.channel = this.supabase
                .channel(`order-tracker-${this.orderId}`)
                .on('postgres_changes', {
                    event: 'INSERT',
                    schema: 'public',
                    table: 'order_status_history',
                    filter: `order_id=eq.${this.orderId}`
                }, payload => {
                    console.log('[OrderTracker] Realtime status update:', payload.new);
                    this.statusHistory.push(payload.new);
                    this.currentStatus = payload.new.to_status;
                    this.render(this.containerId);
                })
                .on('postgres_changes', {
                    event: 'UPDATE',
                    schema: 'public',
                    table: 'orders',
                    filter: `id=eq.${this.orderId}`
                }, payload => {
                    this.orderData = payload.new;
                    this.currentStatus = payload.new.status;
                    this.render(this.containerId);
                })
                .subscribe();
        } catch (e) {
            console.warn('[OrderTracker] Realtime subscription failed:', e);
        }
    }

    /**
     * Render the timeline into a container element.
     */
    render(containerId) {
        this.containerId = containerId;
        const container = document.getElementById(containerId);
        if (!container) return;

        const t = (key, fallback) => this.translateFn(key, fallback);
        const currentStepIndex = this.steps.findIndex(s => s.dbStatus === this.currentStatus);

        let html = `
            <div class="order-tracker">
                <div class="tracker-header">
                    <h3 class="tracker-title">${t('orderTracker', 'Order Progress')}</h3>
                    ${this.orderData ? `<span class="tracker-order-num">#${this.orderData.order_number || ''}</span>` : ''}
                </div>
                <div class="tracker-timeline">
        `;

        this.steps.forEach((step, index) => {
            const isCompleted = index < currentStepIndex;
            const isCurrent = index === currentStepIndex;
            const isPending = index > currentStepIndex;

            let stateClass = 'pending';
            if (isCompleted) stateClass = 'completed';
            else if (isCurrent) stateClass = 'current';

            // Get timestamp for this step
            const historyEntry = this.statusHistory.find(h => h.to_status === step.dbStatus);
            const timestamp = historyEntry ? this.formatTime(historyEntry.changed_at) : '';

            // Calculate elapsed since previous step
            let elapsed = '';
            if (historyEntry && index > 0) {
                const prevStep = this.steps[index - 1];
                const prevEntry = this.statusHistory.find(h => h.to_status === prevStep.dbStatus);
                if (prevEntry) {
                    elapsed = this.formatElapsed(prevEntry.changed_at, historyEntry.changed_at);
                }
            }

            const stepTitle = t(`order${step.key.charAt(0).toUpperCase() + step.key.slice(1)}`, step.key);

            html += `
                <div class="tracker-step ${stateClass}">
                    <div class="tracker-step-line-container">
                        ${index > 0 ? `<div class="tracker-timeline-line ${isCompleted || isCurrent ? 'active' : ''}"></div>` : ''}
                        <div class="tracker-step-dot ${stateClass}">
                            ${isCompleted ? '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"></polyline></svg>' : `<span class="tracker-dot-icon">${step.icon}</span>`}
                        </div>
                    </div>
                    <div class="tracker-step-content">
                        <div class="tracker-step-title">${stepTitle}</div>
                        ${timestamp ? `<div class="tracker-step-time">${timestamp}</div>` : ''}
                        ${elapsed ? `<div class="tracker-step-elapsed">${elapsed}</div>` : ''}
                        ${isCurrent ? `<div class="tracker-step-active-label">${t('currentStep', 'Current')}</div>` : ''}
                    </div>
                </div>
            `;
        });

        html += `</div>`; // close tracker-timeline

        // ETA card
        html += `<div class="tracker-eta-card" id="trackerETACard">${this.renderETAContent()}</div>`;

        // Elapsed since order placed
        html += `
            <div class="tracker-elapsed-total" id="trackerElapsedTotal">
                ${this.orderCreatedAt ? `${t('elapsed', 'Elapsed')}: <span id="trackerElapsedValue">${this.getElapsedSinceOrder()}</span>` : ''}
            </div>
        `;

        html += `</div>`; // close order-tracker

        container.innerHTML = html;
    }

    /**
     * Render just the ETA card content.
     */
    renderETAContent() {
        const t = (key, fallback) => this.translateFn(key, fallback);

        if (this.currentStatus === 'served' || this.currentStatus === 'completed') {
            return `<div class="eta-completed">${t('orderServed', 'Served')} ✓</div>`;
        }

        if (!this.estimatedWait) {
            return `<div class="eta-loading">${t('calculating', 'Calculating...')}</div>`;
        }

        const minutes = this.estimatedWait.estimated_minutes || 0;
        const ordersAhead = this.estimatedWait.orders_ahead || 0;
        const colorClass = minutes <= 10 ? 'fast' : minutes <= 20 ? 'moderate' : minutes <= 30 ? 'busy' : 'very-busy';

        return `
            <div class="eta-content ${colorClass}">
                <div class="eta-ring">
                    <svg class="eta-ring-svg" viewBox="0 0 60 60">
                        <circle class="eta-ring-bg" cx="30" cy="30" r="26" fill="none" stroke-width="4"/>
                        <circle class="eta-ring-progress" cx="30" cy="30" r="26" fill="none" stroke-width="4"
                            stroke-dasharray="${Math.PI * 52}"
                            stroke-dashoffset="${Math.PI * 52 * (1 - Math.min(minutes / 60, 1))}"/>
                    </svg>
                    <span class="eta-minutes">~${minutes}</span>
                </div>
                <div class="eta-details">
                    <div class="eta-label">${t('estimatedWait', 'Estimated wait')}</div>
                    <div class="eta-value">${minutes} ${t('minutesShort', 'min')}</div>
                    <div class="eta-orders-ahead">${ordersAhead} ${t('ordersAhead', 'orders ahead')}</div>
                </div>
            </div>
        `;
    }

    /**
     * Re-render just the ETA card.
     */
    renderETA() {
        const etaCard = document.getElementById('trackerETACard');
        if (etaCard) {
            etaCard.innerHTML = this.renderETAContent();
        }
    }

    /**
     * Start the elapsed time timer (updates every second).
     */
    startTimer() {
        this.timerInterval = setInterval(() => {
            const el = document.getElementById('trackerElapsedValue');
            if (el && this.orderCreatedAt) {
                el.textContent = this.getElapsedSinceOrder();
            }
        }, 1000);
    }

    /**
     * Get elapsed time since order was placed.
     */
    getElapsedSinceOrder() {
        if (!this.orderCreatedAt) return '';
        const now = new Date();
        const diffMs = now - this.orderCreatedAt;
        return this.formatDuration(diffMs);
    }

    /**
     * Format a timestamp into HH:MM display.
     */
    formatTime(isoString) {
        if (!isoString) return '';
        const d = new Date(isoString);
        return d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
    }

    /**
     * Format elapsed time between two timestamps.
     */
    formatElapsed(startIso, endIso) {
        const start = new Date(startIso);
        const end = new Date(endIso);
        const diffMs = end - start;
        return this.formatDuration(diffMs);
    }

    /**
     * Format a duration in ms to human-readable string.
     */
    formatDuration(ms) {
        if (ms < 0) ms = 0;
        const totalSec = Math.floor(ms / 1000);
        const min = Math.floor(totalSec / 60);
        const sec = totalSec % 60;

        if (min >= 60) {
            const hr = Math.floor(min / 60);
            const remainMin = min % 60;
            return `${hr}h ${remainMin}m`;
        }
        if (min > 0) {
            return `${min}m ${sec}s`;
        }
        return `${sec}s`;
    }

    /**
     * Clean up subscriptions and intervals.
     */
    destroy() {
        if (this.channel && this.supabase) {
            this.supabase.removeChannel(this.channel);
            this.channel = null;
        }
        if (this.pollInterval) {
            clearInterval(this.pollInterval);
            this.pollInterval = null;
        }
        if (this.timerInterval) {
            clearInterval(this.timerInterval);
            this.timerInterval = null;
        }
    }
}
