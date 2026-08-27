/**
 * AlphaPos - Reorder History Module
 * 
 * Provides order history persistence (localStorage + Supabase)
 * and quick "Order Again" functionality.
 */

const STORAGE_KEY = 'alphapos_order_history';
const MAX_ORDERS = 10;

export class ReorderHistory {
    constructor() {
        this.orders = [];
        this.menuItems = [];
        this.translateFn = (key, fallback) => fallback || key;
        this.addToCartFn = null;
        this.showToastFn = null;
        this.supabase = null;
        this.merchantId = null;
    }

    /**
     * Initialize: load from localStorage and optionally from Supabase
     */
    init(options = {}) {
        this.translateFn = options.translate || this.translateFn;
        this.menuItems = options.menuItems || [];
        this.addToCartFn = options.addToCart || null;
        this.showToastFn = options.showToast || null;
        this.supabase = options.supabaseClient || null;
        this.merchantId = options.merchantId || null;

        this.orders = this._loadFromStorage();
    }

    /**
     * Save a completed order to history
     */
    saveOrder(orderData) {
        if (!orderData || !orderData.items || orderData.items.length === 0) return;

        const record = {
            id: orderData.id || this._generateId(),
            orderNumber: orderData.orderNumber || '',
            tableNumber: orderData.tableNumber || '',
            items: orderData.items.map(item => ({
                itemId: item.itemId || item.item_id || item.id,
                name: item.name || item.item_name || '',
                quantity: item.quantity || 1,
                price: item.price || 0,
                selectedModifiers: item.selectedModifiers || [],
                notes: item.notes || ''
            })),
            total: orderData.total || 0,
            status: orderData.status || 'preparing',
            createdAt: orderData.createdAt || new Date().toISOString()
        };

        // Prevent duplicate
        this.orders = this.orders.filter(o => o.id !== record.id);

        // Add to front
        this.orders.unshift(record);

        // Keep max orders
        if (this.orders.length > MAX_ORDERS) {
            this.orders = this.orders.slice(0, MAX_ORDERS);
        }

        this._saveToStorage();
    }

    /**
     * Get all saved orders
     */
    getHistory() {
        return this.orders;
    }

    /**
     * Get the most recent order
     */
    getLastOrder() {
        return this.orders.length > 0 ? this.orders[0] : null;
    }

    /**
     * Reorder: add all items from a past order to the current cart
     */
    reorder(orderId) {
        const order = this.orders.find(o => o.id === orderId);
        if (!order || !this.addToCartFn) return;

        let addedCount = 0;
        let unavailableCount = 0;

        order.items.forEach(item => {
            const menuItem = this.menuItems.find(m => m.id === item.itemId);
            if (menuItem) {
                // Item available — add to cart
                this.addToCartFn(item.itemId, item.quantity, item.selectedModifiers, item.notes);
                addedCount++;
            } else {
                unavailableCount++;
            }
        });

        // Show toast feedback
        if (this.showToastFn) {
            if (addedCount > 0 && unavailableCount === 0) {
                this.showToastFn(this.translateFn('addedToCart', 'Added to cart') + ` (${addedCount} items)`);
            } else if (addedCount > 0 && unavailableCount > 0) {
                this.showToastFn(
                    `${addedCount} ${this.translateFn('addedToCart', 'added')} · ${unavailableCount} ${this.translateFn('itemUnavailable', 'unavailable')}`
                );
            } else {
                this.showToastFn(this.translateFn('itemUnavailable', 'Items no longer available'));
            }
        }
    }

    /**
     * Clear all order history
     */
    clearHistory() {
        this.orders = [];
        this._saveToStorage();
    }

    /**
     * Update available menu items (for availability checking)
     */
    updateMenuItems(menuItems) {
        this.menuItems = menuItems || [];
    }

    /**
     * Check if a menu item is still available
     */
    isItemAvailable(itemId) {
        return this.menuItems.some(m => m.id === itemId);
    }

    /**
     * Check if item price has changed
     */
    getItemPriceChange(itemId, savedPrice) {
        const current = this.menuItems.find(m => m.id === itemId);
        if (!current) return null;
        if (Math.abs(current.price - savedPrice) > 0.01) {
            return { oldPrice: savedPrice, newPrice: current.price };
        }
        return null;
    }

    // =====================================================
    // RENDERING
    // =====================================================

    /**
     * Render quick reorder widget (compact card above menu)
     */
    renderQuickReorder(containerId) {
        const container = document.getElementById(containerId);
        if (!container) return;

        const lastOrder = this.getLastOrder();
        if (!lastOrder) {
            container.innerHTML = '';
            container.classList.add('hidden');
            return;
        }

        container.classList.remove('hidden');

        const timeAgo = this._formatTimeAgo(lastOrder.createdAt);

        container.innerHTML = `
            <button class="recent-order-trigger" type="button" onclick="app.showOrderHistory()">
                <span class="recent-order-icon" aria-hidden="true">↻</span>
                <span class="recent-order-copy">
                    <strong>${this.translateFn('lastOrder', 'Last Order')}</strong>
                    <small>${timeAgo}</small>
                </span>
                <span class="recent-order-chevron" aria-hidden="true">›</span>
            </button>
        `;
    }

    /**
     * Render full order history view
     */
    renderHistoryView(containerId) {
        const container = document.getElementById(containerId);
        if (!container) return;

        if (this.orders.length === 0) {
            container.innerHTML = `
                <div class="order-history-empty">
                    <span class="order-history-empty-icon">📋</span>
                    <p class="order-history-empty-text">${this.translateFn('noHistory', 'No past orders')}</p>
                </div>
            `;
            return;
        }

        container.innerHTML = `
            <div class="order-history-header">
                <h3 class="order-history-title">${this.translateFn('orderHistory', 'Order History')}</h3>
                <button class="order-history-clear-btn" onclick="window._reorderHistory.clearHistory(); window._reorderHistory.renderHistoryView('${containerId}');">
                    ${this.translateFn('clearHistory', 'Clear')}
                </button>
            </div>
            <div class="order-history-list">
                ${this.orders.map(order => this._renderOrderCard(order)).join('')}
            </div>
        `;
    }

    _renderOrderCard(order) {
        const date = new Date(order.createdAt);
        const dateStr = date.toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
        const timeStr = date.toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit' });
        const itemCount = order.items.reduce((sum, i) => sum + i.quantity, 0);

        const hasUnavailable = order.items.some(i => !this.isItemAvailable(i.itemId));
        const hasPriceChange = order.items.some(i => {
            const change = this.getItemPriceChange(i.itemId, i.price);
            return change !== null;
        });

        return `
            <div class="order-history-item" data-order-id="${order.id}">
                <div class="order-history-item-header" onclick="window._reorderHistory._toggleExpand('${order.id}')">
                    <div class="order-history-item-info">
                        <span class="order-history-date">${dateStr} · ${timeStr}</span>
                        <span class="order-history-summary">${itemCount} items · ฿${order.total.toFixed(0)}</span>
                    </div>
                    <div class="order-history-item-actions">
                        <button class="reorder-btn reorder-btn-sm" onclick="event.stopPropagation(); window._reorderHistory.reorder('${order.id}')">
                            ${this.translateFn('orderAgain', 'Order Again')}
                        </button>
                        <span class="order-history-chevron">›</span>
                    </div>
                </div>
                <div class="order-history-item-details hidden" id="orderDetail_${order.id}">
                    <div class="order-history-items-list">
                        ${order.items.map(item => {
                            const available = this.isItemAvailable(item.itemId);
                            const priceChange = this.getItemPriceChange(item.itemId, item.price);
                            return `
                                <div class="order-history-item-row ${!available ? 'unavailable' : ''}">
                                    <span class="item-name">${this._escapeHtml(item.name)} ×${item.quantity}</span>
                                    <span class="item-price">
                                        ${priceChange ? `<del>฿${item.price}</del> ฿${priceChange.newPrice}` : `฿${(item.price * item.quantity).toFixed(0)}`}
                                    </span>
                                    ${!available ? `<span class="item-unavailable-badge">${this.translateFn('itemUnavailable', 'Unavailable')}</span>` : ''}
                                    ${priceChange ? `<span class="item-price-changed-badge">${this.translateFn('priceChanged', 'Price changed')}</span>` : ''}
                                </div>
                            `;
                        }).join('')}
                    </div>
                </div>
            </div>
        `;
    }

    _toggleExpand(orderId) {
        const detail = document.getElementById(`orderDetail_${orderId}`);
        if (!detail) return;

        const chevron = detail.parentElement.querySelector('.order-history-chevron');
        detail.classList.toggle('hidden');
        if (chevron) {
            chevron.classList.toggle('expanded');
        }
    }

    // =====================================================
    // PRIVATE HELPERS
    // =====================================================

    _loadFromStorage() {
        try {
            const data = localStorage.getItem(STORAGE_KEY);
            if (data) {
                return JSON.parse(data);
            }
        } catch (e) {
            console.warn('[ReorderHistory] Failed to load from storage:', e);
        }
        return [];
    }

    _saveToStorage() {
        try {
            localStorage.setItem(STORAGE_KEY, JSON.stringify(this.orders));
        } catch (e) {
            console.warn('[ReorderHistory] Failed to save to storage:', e);
        }
    }

    _generateId() {
        return 'rh_' + Date.now() + '_' + Math.random().toString(36).slice(2, 8);
    }

    _formatTimeAgo(isoString) {
        const date = new Date(isoString);
        const now = new Date();
        const diffMs = now - date;
        const diffMin = Math.floor(diffMs / 60000);
        const diffHrs = Math.floor(diffMs / 3600000);
        const diffDays = Math.floor(diffMs / 86400000);

        if (diffMin < 1) return 'just now';
        if (diffMin < 60) return `${diffMin}m ago`;
        if (diffHrs < 24) return `${diffHrs}h ago`;
        if (diffDays < 7) return `${diffDays}d ago`;
        return date.toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
    }

    _escapeHtml(str) {
        if (!str) return '';
        const div = document.createElement('div');
        div.textContent = str;
        return div.innerHTML;
    }
}

// Singleton export
export const reorderHistory = new ReorderHistory();
