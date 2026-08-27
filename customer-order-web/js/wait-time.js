/**
 * AlphaPos - Estimated Wait Time Widget
 * 
 * Displays estimated wait time with:
 * - Circular SVG progress ring (color-coded by wait duration)
 * - "~15 min" estimated time (big number)
 * - "3 orders ahead" context info
 * - Auto-updates every 30 seconds
 * - Mini badge version for header
 * - Countdown animation when close to ready
 */

export class WaitTimeWidget {
    constructor() {
        this.supabase = null;
        this.merchantId = '';
        this.localServerURL = '';
        this.pollingInterval = null;
        this.countdownInterval = null;
        this.waitData = null;
        this.isDestroyed = false;
        this.lastFetchTime = null;
        this.translateFn = (key, fallback) => fallback || key;
    }

    /**
     * Initialize the widget
     * @param {object} options - { supabaseClient, merchantId, localServerURL, translateFn }
     */
    init(options = {}) {
        this.supabase = options.supabaseClient || null;
        this.merchantId = options.merchantId || '';
        this.localServerURL = options.localServerURL || window.location.origin;
        if (options.translateFn) this.translateFn = options.translateFn;
        this.fetchWaitTime();
        this.startPolling();
    }

    /**
     * Fetch estimated wait time from server
     */
    async fetchWaitTime() {
        if (this.isDestroyed) return;

        try {
            let data = null;

            // Try Supabase RPC first
            if (this.supabase && this.merchantId) {
                try {
                    const { data: rpcData, error } = await this.supabase.rpc(
                        'get_estimated_wait_time',
                        { p_merchant_id: this.merchantId }
                    );
                    if (!error && rpcData) {
                        data = rpcData;
                    }
                } catch (e) {
                    console.warn('[WaitTime] Supabase RPC failed, trying local:', e);
                }
            }

            // Fallback to local server
            if (!data) {
                try {
                    const res = await fetch(`${this.localServerURL}/v1/wait-time`, {
                        headers: { 'Content-Type': 'application/json' }
                    });
                    if (res.ok) {
                        data = await res.json();
                    }
                } catch (e) {
                    console.warn('[WaitTime] Local server failed:', e);
                }
            }

            if (data) {
                this.waitData = {
                    estimatedMinutes: data.estimated_minutes || 0,
                    ordersAhead: data.orders_ahead || 0,
                    itemsInQueue: data.items_in_queue || 0,
                    avgPrepTime: data.avg_prep_time_minutes || 0,
                    calculatedAt: data.calculated_at || new Date().toISOString()
                };
                this.lastFetchTime = Date.now();
                this.updateAllRenderedWidgets();
            }
        } catch (err) {
            console.error('[WaitTime] Fetch error:', err);
        }
    }

    /**
     * Get color class based on estimated minutes
     */
    getColorClass(minutes) {
        if (minutes <= 10) return 'green';
        if (minutes <= 20) return 'yellow';
        if (minutes <= 30) return 'orange';
        return 'red';
    }

    /**
     * Get status message based on wait time
     */
    getStatusMessage(minutes) {
        if (minutes <= 5) return this.translateFn('almostReady', 'Almost ready!');
        if (minutes <= 10) return this.translateFn('fastService', 'Fast service');
        if (minutes <= 20) return this.translateFn('preparingYourOrder', 'Preparing your order');
        return this.translateFn('kitchenBusy', 'Kitchen is busy');
    }

    /**
     * Render full wait time widget (for order confirmation screen)
     * @param {string} containerId - DOM element ID
     */
    renderFull(containerId) {
        const container = document.getElementById(containerId);
        if (!container) return;

        const minutes = this.waitData ? this.waitData.estimatedMinutes : 0;
        const ordersAhead = this.waitData ? this.waitData.ordersAhead : 0;
        const colorClass = this.getColorClass(minutes);
        const statusMsg = this.getStatusMessage(minutes);
        const progress = Math.min(1, minutes / 45); // Normalize to max 45 min
        const circumference = 2 * Math.PI * 52;
        const targetOffset = circumference * (1 - progress);

        container.innerHTML = `
            <div class="wait-time-widget wait-time-${colorClass}" data-wait-type="full">
                <div class="wait-time-ring-container">
                    <svg class="wait-time-ring" viewBox="0 0 120 120" aria-hidden="true">
                        <circle class="wait-time-ring-bg" cx="60" cy="60" r="52" />
                        <circle class="wait-time-ring-progress" cx="60" cy="60" r="52"
                            stroke-dasharray="${circumference}"
                            stroke-dashoffset="${circumference}"
                            data-target-offset="${targetOffset}"
                        />
                        <circle class="wait-time-ring-pulse" cx="60" cy="60" r="52" />
                    </svg>
                    <div class="wait-time-center">
                        <span class="wait-time-value">~${minutes}</span>
                        <span class="wait-time-unit">${this.translateFn('minutesShort', 'min')}</span>
                    </div>
                </div>
                <div class="wait-time-info">
                    <div class="wait-time-status">${statusMsg}</div>
                    <div class="wait-time-orders-ahead">
                        <span class="wait-time-ahead-count">${ordersAhead}</span>
                        <span class="wait-time-ahead-label">${this.translateFn('ordersAhead', 'orders ahead')}</span>
                    </div>
                    <div class="wait-time-updated">
                        ${this.translateFn('updatedJustNow', 'Updated just now')}
                    </div>
                </div>
            </div>
        `;

        // Animate entrance
        const widget = container.querySelector('.wait-time-widget');
        if (widget) {
            widget.classList.add('anim-fade-in-scale');
            requestAnimationFrame(() => requestAnimationFrame(() => {
                const ring = widget.querySelector('.wait-time-ring-progress');
                if (ring) ring.style.strokeDashoffset = ring.dataset.targetOffset;
            }));
        }
    }

    /**
     * Render mini wait time badge (for header)
     * @param {string} containerId - DOM element ID
     */
    renderMini(containerId) {
        const container = document.getElementById(containerId);
        if (!container) return;

        const minutes = this.waitData ? this.waitData.estimatedMinutes : 0;
        const colorClass = this.getColorClass(minutes);

        container.innerHTML = `
            <div class="wait-time-mini wait-time-mini-${colorClass}" data-wait-type="mini" title="${this.translateFn('estimatedWait', 'Estimated Wait')}: ~${minutes} ${this.translateFn('minutesShort', 'min')}">
                <svg class="wait-time-mini-icon" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                    <circle cx="12" cy="12" r="10"/>
                    <polyline points="12 6 12 12 16 14"/>
                </svg>
                <span class="wait-time-mini-text">~${minutes}m</span>
            </div>
        `;
    }

    /**
     * Update all currently rendered widgets
     */
    updateAllRenderedWidgets() {
        // Update full widgets
        document.querySelectorAll('[data-wait-type="full"]').forEach(widget => {
            const container = widget.parentElement;
            if (container) this.renderFull(container.id);
        });

        // Update mini widgets
        document.querySelectorAll('[data-wait-type="mini"]').forEach(widget => {
            const container = widget.parentElement;
            if (container) this.renderMini(container.id);
        });
    }

    /**
     * Start polling every 30 seconds
     */
    startPolling() {
        this.stopPolling();
        this.pollingInterval = setInterval(() => {
            this.fetchWaitTime();
        }, 30000);
    }

    /**
     * Stop polling
     */
    stopPolling() {
        if (this.pollingInterval) {
            clearInterval(this.pollingInterval);
            this.pollingInterval = null;
        }
    }

    /**
     * Get latest wait data
     */
    getWaitData() {
        return this.waitData;
    }

    /**
     * Show the widget (unhide containers)
     */
    show() {
        document.querySelectorAll('.wait-time-widget, .wait-time-mini').forEach(el => {
            el.closest('.wait-time-container')?.classList.remove('hidden');
        });
    }

    /**
     * Hide the widget
     */
    hide() {
        document.querySelectorAll('.wait-time-container').forEach(el => {
            el.classList.add('hidden');
        });
    }

    /**
     * Destroy and cleanup
     */
    destroy() {
        this.isDestroyed = true;
        this.stopPolling();
        if (this.countdownInterval) {
            clearInterval(this.countdownInterval);
            this.countdownInterval = null;
        }
        // Clear rendered widgets
        document.querySelectorAll('[data-wait-type]').forEach(el => {
            el.remove();
        });
    }
}

// Export singleton
export const waitTimeWidget = new WaitTimeWidget();
