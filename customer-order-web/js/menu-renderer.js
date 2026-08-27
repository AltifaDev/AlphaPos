/**
 * AlphaPos — Menu Renderer Module
 * Handles category rendering, menu item cards, search, and filtering.
 */
import { escapeHtml, formatCurrency } from './app-core.js';

export const MenuRendererMixin = {
    async loadMenuFromServer() {
        if (this.supabase) {
            try {
                let query = this.supabase
                    .from('menu_items')
                    .select('*')
                    .eq('is_deleted', false);

                if (this.branchId) {
                    query = query.or(`branch_id.is.null,branch_id.eq.${this.branchId}`);
                }
                if (this.merchantId) {
                    query = query.eq('merchant_id', this.merchantId);
                }

                const { data, error } = await query;
                if (!error && data && data.length > 0) {
                    this.menuItems = data;
                    console.log(`[Menu] Loaded ${data.length} items from Supabase`);
                }
            } catch (e) {
                console.warn('[Menu] Supabase fetch failed, trying local server:', e);
            }
        }

        if ((!this.menuItems || this.menuItems.length === 0) && this.isLocalServerAvailable) {
            try {
                const response = await fetch('/v1/menu');
                if (response.ok) {
                    const data = await response.json();
                    if (data && data.length > 0) {
                        this.menuItems = data;
                        console.log(`[Menu] Loaded ${data.length} items from local server`);
                    }
                }
            } catch (e) {
                console.warn('[Menu] Server fetch failed, using defaults:', e);
            }
        }

        // Extract categories
        const cats = new Set(this.menuItems.map(i => i.category));
        this.categories = ['recommended', ...Array.from(cats)];

        // Init allergen filter if available
        if (this._allergenFilter) {
            await this._allergenFilter.init(this.supabase, window.ALPHAPOS_CONFIG?.merchantId);
        }
    },

    renderCategories() {
        const container = document.getElementById('categoriesContainer');
        if (!container) return;

        container.innerHTML = this.categories.map(cat => `
            <button class="category-pill ${cat === this.currentCategory ? 'active' : ''}"
                    onclick="app.switchCategory('${cat}')">
                ${this.translate(cat, cat)}
            </button>
        `).join('');
    },

    switchCategory(category) {
        this.currentCategory = category;
        this.renderCategories();
        this.renderMenuItems();
    },

    renderMenuItems() {
        const container = document.getElementById('menuGrid');
        if (!container) return;

        let items = this.currentCategory === 'recommended'
            ? this.menuItems.slice(0, 8)
            : this.menuItems.filter(i => i.category === this.currentCategory);

        // Apply allergen/dietary filters if active
        if (this._allergenFilter) {
            items = this._allergenFilter.applyFilters(items);
        }

        // Apply search filter
        const searchInput = document.getElementById('menuSearch');
        if (searchInput && searchInput.value.trim()) {
            const query = searchInput.value.trim().toLowerCase();
            items = items.filter(i =>
                (i.name || '').toLowerCase().includes(query) ||
                (i.desc || i.description || '').toLowerCase().includes(query)
            );
        }

        if (items.length === 0) {
            container.innerHTML = `<div class="empty-state">${this.translate('noItemsMatch', 'No items found')}</div>`;
            return;
        }

        container.innerHTML = items.map(item => this._renderItemCard(item)).join('');
    },

    _renderItemCard(item) {
        const name = this.getItemName(item);
        const desc = this.getItemDesc(item);
        const price = formatCurrency(item.price);
        const qty = this.getItemTotalQuantity(item.id);
        const isAvailable = item.is_available !== false && item.is_available !== 0 && item.is_available !== '0';
        const allergenBadges = this._allergenFilter ? this._allergenFilter.renderBadges(item.id) : '';
        const outOfStockBadge = !isAvailable
            ? `<span class="out-of-stock-badge">${this.translate('outOfStock', 'สินค้าหมด / Sold Out')}</span>`
            : '';

        let actionControl = '';
        if (!isAvailable) {
            actionControl = `<button class="add-btn disabled" disabled aria-disabled="true">${this.translate('outOfStockBtn', 'หมด')}</button>`;
        } else if (qty > 0) {
            actionControl = `
                <div class="qty-control">
                    <button onclick="app.updateCartQuantity('${item.id}', -1)">−</button>
                    <span>${qty}</span>
                    <button onclick="app.updateCartQuantity('${item.id}', 1)">+</button>
                </div>`;
        } else {
            actionControl = `<button class="add-btn" onclick="app.addToCart('${item.id}')">+</button>`;
        }

        return `
            <div class="menu-card ${!isAvailable ? 'out-of-stock' : ''}" data-item-id="${item.id}">
                ${item.image_url ? `<div class="menu-card-img" style="background-image:url('${escapeHtml(item.image_url)}')">${outOfStockBadge}</div>` : (outOfStockBadge ? `<div class="menu-card-badge-container">${outOfStockBadge}</div>` : '')}
                <div class="menu-card-body">
                    <h3 class="menu-card-name">${escapeHtml(name)}</h3>
                    ${desc ? `<p class="menu-card-desc">${escapeHtml(desc)}</p>` : ''}
                    ${allergenBadges}
                    <div class="menu-card-footer">
                        <span class="menu-card-price">${price}</span>
                        ${actionControl}
                    </div>
                </div>
            </div>
        `;
    },

    getItemName(item) {
        if (item.name_translations && item.name_translations[this.currentLang]) {
            return item.name_translations[this.currentLang];
        }
        return item.name || '';
    },

    getItemDesc(item) {
        if (item.description_translations && item.description_translations[this.currentLang]) {
            return item.description_translations[this.currentLang];
        }
        return item.desc || item.description || '';
    },

    getItemTotalQuantity(itemId) {
        return this.cart.filter(c => c.item_id === itemId || c.id === itemId)
            .reduce((sum, c) => sum + c.quantity, 0);
    },

    handleSearch(event) {
        this._debounce('search', () => this.renderMenuItems(), 300);
    },

    clearSearch() {
        const input = document.getElementById('menuSearch');
        if (input) input.value = '';
        this.renderMenuItems();
    },

    animateMenuEntrance() {
        document.querySelectorAll('.menu-card').forEach((card, i) => {
            card.style.opacity = '0';
            card.style.transform = 'translateY(20px)';
            setTimeout(() => {
                card.style.transition = 'all 0.3s ease';
                card.style.opacity = '1';
                card.style.transform = 'translateY(0)';
            }, i * 50);
        });
    }
};
