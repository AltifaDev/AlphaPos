/**
 * AlphaPos — Cart Manager Module
 * Handles cart state, add/remove items, render cart drawer.
 */
import { formatCurrency } from './app-core.js';

export const CartManagerMixin = {
    addToCart(itemId) {
        const menuItem = this.menuItems.find(i => i.id === itemId);
        if (!menuItem) return;

        // Check if already in cart
        const existing = this.cart.find(c => c.item_id === itemId && !c.modifiers?.length);
        if (existing) {
            existing.quantity += 1;
        } else {
            this.cart.push({
                id: `cart-${Date.now()}-${Math.random().toString(36).slice(2, 6)}`,
                item_id: itemId,
                name: menuItem.name,
                price: menuItem.price,
                quantity: 1,
                modifiers: [],
                notes: ''
            });
        }

        this.saveCartToStorage();
        this.renderMenuItems();
        this.renderCartBadge();
        this.renderCartDrawer();
    },

    updateCartQuantity(itemId, delta) {
        const item = this.cart.find(c => c.item_id === itemId);
        if (!item) return;

        item.quantity += delta;
        if (item.quantity <= 0) {
            this.cart = this.cart.filter(c => c !== item);
        }

        this.saveCartToStorage();
        this.renderMenuItems();
        this.renderCartBadge();
        this.renderCartDrawer();
    },

    removeFromCart(cartItemId) {
        this.cart = this.cart.filter(c => c.id !== cartItemId);
        this.saveCartToStorage();
        this.renderMenuItems();
        this.renderCartBadge();
        this.renderCartDrawer();
    },

    saveCartToStorage() {
        try {
            localStorage.setItem('alphapos_cart', JSON.stringify(this.cart));
        } catch (e) {
            console.warn('[Cart] Save failed:', e);
        }
    },

    loadCartFromStorage() {
        try {
            const saved = localStorage.getItem('alphapos_cart');
            if (saved) {
                this.cart = JSON.parse(saved);
            }
        } catch (e) {
            this.cart = [];
        }
    },

    clearCartState() {
        this.cart = [];
        localStorage.removeItem('alphapos_cart');
        this.renderCartBadge();
        this.renderCartDrawer();
        this.renderMenuItems();
    },

    renderCartBadge() {
        const badge = document.getElementById('cartBadge');
        const totalItems = this.cart.reduce((sum, i) => sum + i.quantity, 0);
        if (badge) {
            badge.textContent = totalItems;
            badge.style.display = totalItems > 0 ? 'flex' : 'none';
        }

        // Update floating cart bar
        const bar = document.getElementById('floatingCartBar');
        if (bar) {
            bar.style.display = totalItems > 0 ? 'flex' : 'none';
            const { total } = this.calculateTotals();
            const barTotal = bar.querySelector('.cart-bar-total');
            const barCount = bar.querySelector('.cart-bar-count');
            if (barTotal) barTotal.textContent = formatCurrency(total);
            if (barCount) barCount.textContent = `${totalItems} ${this.translate('items', 'items')}`;
        }
    },

    renderCartDrawer() {
        const container = document.getElementById('cartDrawerList');
        if (!container) return;

        if (this.cart.length === 0) {
            container.innerHTML = `<div class="empty-cart">${this.translate('emptyCart', 'Your cart is empty')}</div>`;
            return;
        }

        container.innerHTML = this.cart.map(item => `
            <div class="cart-item" data-cart-id="${item.id}">
                <div class="cart-item-info">
                    <span class="cart-item-name">${item.name}</span>
                    ${item.notes ? `<span class="cart-item-notes">${item.notes}</span>` : ''}
                </div>
                <div class="cart-item-controls">
                    <button onclick="app.updateCartQuantity('${item.item_id}', -1)">−</button>
                    <span>${item.quantity}</span>
                    <button onclick="app.updateCartQuantity('${item.item_id}', 1)">+</button>
                </div>
                <span class="cart-item-price">${formatCurrency(item.price * item.quantity)}</span>
            </div>
        `).join('');

        // Render totals
        const { subtotal, serviceCharge, vat, total } = this.calculateTotals();
        const totalsEl = document.getElementById('cartTotals');
        if (totalsEl) {
            totalsEl.innerHTML = `
                <div class="total-row"><span>${this.translate('subtotal', 'Subtotal')}</span><span>${formatCurrency(subtotal)}</span></div>
                <div class="total-row"><span>${this.translate('serviceCharge', 'Service Charge 10%')}</span><span>${formatCurrency(serviceCharge)}</span></div>
                <div class="total-row"><span>${this.translate('vat', 'VAT 7%')}</span><span>${formatCurrency(vat)}</span></div>
                <div class="total-row total-final"><span>${this.translate('total', 'Total')}</span><span>${formatCurrency(total)}</span></div>
            `;
        }
    }
};
