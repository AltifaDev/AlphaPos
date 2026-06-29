/**
 * AlphaPos - Allergen & Dietary Filter Module
 * 
 * Provides dietary filtering (Vegetarian, Vegan, Halal, Gluten-free),
 * allergen exclusion, badges on menu cards, and detail bottom sheet.
 */

export class AllergenFilter {
    constructor() {
        this.allergenTags = [];           // All allergen definitions
        this.menuItemAllergens = {};      // { itemId: [allergenCodes] }
        this.activeDietaryFilters = new Set(); // 'vegetarian', 'vegan', 'halal', 'gluten_free'
        this.excludedAllergens = new Set();    // allergen codes to exclude
        this.menuItemDietary = {};        // { itemId: { is_vegetarian, is_vegan, is_halal, is_gluten_free, spice_level, calories } }
        this.supabase = null;
        this.merchantId = '';
        this.translateFn = null;
    }

    /**
     * Initialize with Supabase client and fetch allergen data
     */
    async init(supabaseClient, merchantId, translateFn) {
        this.supabase = supabaseClient;
        this.merchantId = merchantId;
        this.translateFn = translateFn || ((key, fallback) => fallback);

        await this.fetchAllergenData();
    }

    /**
     * Fetch allergen tags and menu item allergen mappings from Supabase
     */
    async fetchAllergenData() {
        try {
            // Fetch allergen definitions
            if (this.supabase) {
                const { data: tags, error: tagsError } = await this.supabase
                    .from('allergen_tags')
                    .select('*')
                    .eq('is_active', true)
                    .order('sort_order');

                if (!tagsError && tags) {
                    this.allergenTags = tags;
                }

                // Fetch menu item ↔ allergen mappings
                const { data: mappings, error: mapError } = await this.supabase
                    .from('menu_item_allergens')
                    .select('menu_item_id, allergen_id');

                if (!mapError && mappings) {
                    this.menuItemAllergens = {};
                    for (const m of mappings) {
                        if (!this.menuItemAllergens[m.menu_item_id]) {
                            this.menuItemAllergens[m.menu_item_id] = [];
                        }
                        const tag = this.allergenTags.find(t => t.id === m.allergen_id);
                        if (tag) {
                            this.menuItemAllergens[m.menu_item_id].push(tag.code);
                        }
                    }
                }

                // Fetch dietary info from menu_items
                const { data: items, error: itemsError } = await this.supabase
                    .from('menu_items')
                    .select('id, is_vegetarian, is_vegan, is_halal, is_gluten_free, spice_level, calories, prep_time_minutes');

                if (!itemsError && items) {
                    this.menuItemDietary = {};
                    for (const item of items) {
                        this.menuItemDietary[item.id] = {
                            is_vegetarian: item.is_vegetarian || false,
                            is_vegan: item.is_vegan || false,
                            is_halal: item.is_halal || false,
                            is_gluten_free: item.is_gluten_free || false,
                            spice_level: item.spice_level || 0,
                            calories: item.calories || null,
                            prep_time_minutes: item.prep_time_minutes || null
                        };
                    }
                }
            }
        } catch (err) {
            console.warn('[AllergenFilter] Failed to fetch allergen data:', err);
        }

        // If no data from server, use defaults
        if (this.allergenTags.length === 0) {
            this.allergenTags = this._getDefaultAllergenTags();
        }
    }

    /**
     * Render dietary filter bar + allergen exclusion into container
     */
    renderFilters(containerId) {
        const container = document.getElementById(containerId);
        if (!container) return;

        const t = (key, fallback) => this.translateFn(key, fallback);

        const dietaryOptions = [
            { type: 'vegetarian', icon: '🥬', label: t('vegetarian', 'Vegetarian') },
            { type: 'vegan', icon: '🌱', label: t('vegan', 'Vegan') },
            { type: 'halal', icon: '☪️', label: t('halal', 'Halal') },
            { type: 'gluten_free', icon: '🌾', label: t('glutenFree', 'Gluten-free') }
        ];

        let html = `
            <div class="dietary-filter-bar">
                <div class="dietary-filter-scroll">
                    ${dietaryOptions.map(opt => `
                        <button class="dietary-pill ${this.activeDietaryFilters.has(opt.type) ? 'active' : ''}"
                                data-filter-type="${opt.type}"
                                onclick="window._allergenFilter.toggleDietaryFilter('${opt.type}')">
                            <span class="dietary-pill-icon">${opt.icon}</span>
                            <span class="dietary-pill-label">${opt.label}</span>
                        </button>
                    `).join('')}
                    <button class="dietary-pill allergen-expand-btn"
                            onclick="window._allergenFilter.toggleAllergenPanel()">
                        <span class="dietary-pill-icon">⚠️</span>
                        <span class="dietary-pill-label">${t('allergenInfo', 'Allergens')}</span>
                        ${this.excludedAllergens.size > 0 ? `<span class="dietary-pill-badge">${this.excludedAllergens.size}</span>` : ''}
                    </button>
                </div>
                ${this._getActiveFilterCount() > 0 ? `
                    <div class="dietary-filter-status">
                        <span class="filter-status-text">${this._getActiveFilterCount()} ${t('filterActive', 'filters active')}</span>
                        <button class="filter-clear-btn" onclick="window._allergenFilter.clearAllFilters()">${t('showAll', 'Show All')}</button>
                    </div>
                ` : ''}
            </div>
            <div class="allergen-exclusion-panel ${this._allergenPanelOpen ? 'open' : ''}" id="allergenExclusionPanel">
                <div class="allergen-panel-header">
                    <h4>${t('allergenWarning', 'Allergen Exclusion')}</h4>
                    <button class="allergen-panel-close" onclick="window._allergenFilter.toggleAllergenPanel()">✕</button>
                </div>
                <div class="allergen-panel-grid">
                    ${this.allergenTags.map(tag => `
                        <button class="allergen-exclusion-chip ${this.excludedAllergens.has(tag.code) ? 'active' : ''} severity-${tag.severity || 'warning'}"
                                onclick="window._allergenFilter.toggleAllergenExclusion('${tag.code}')">
                            <span class="allergen-chip-icon">${tag.icon || '⚠️'}</span>
                            <span class="allergen-chip-label">${this._getAllergenName(tag)}</span>
                        </button>
                    `).join('')}
                </div>
            </div>
        `;

        container.innerHTML = html;
    }

    /**
     * Apply dietary + allergen filters to menu items array
     * Returns filtered array
     */
    applyFilters(menuItems) {
        if (this.activeDietaryFilters.size === 0 && this.excludedAllergens.size === 0) {
            return menuItems;
        }

        return menuItems.filter(item => {
            const dietary = this.menuItemDietary[item.id] || {};
            const itemAllergens = this.menuItemAllergens[item.id] || [];

            // Check dietary filters (ANY active filter must match)
            if (this.activeDietaryFilters.size > 0) {
                let matchesDietary = false;
                if (this.activeDietaryFilters.has('vegetarian') && dietary.is_vegetarian) matchesDietary = true;
                if (this.activeDietaryFilters.has('vegan') && dietary.is_vegan) matchesDietary = true;
                if (this.activeDietaryFilters.has('halal') && dietary.is_halal) matchesDietary = true;
                if (this.activeDietaryFilters.has('gluten_free') && dietary.is_gluten_free) matchesDietary = true;
                if (!matchesDietary) return false;
            }

            // Check allergen exclusions (item must NOT contain any excluded allergen)
            if (this.excludedAllergens.size > 0) {
                for (const excluded of this.excludedAllergens) {
                    if (itemAllergens.includes(excluded)) return false;
                }
            }

            return true;
        });
    }

    /**
     * Render allergen badges on a menu item card
     */
    renderBadges(itemId) {
        const itemAllergens = this.menuItemAllergens[itemId] || [];
        const dietary = this.menuItemDietary[itemId] || {};

        let html = '<div class="allergen-badges-row">';

        // Dietary icons first
        if (dietary.is_vegetarian) html += '<span class="dietary-icon veg" title="Vegetarian">🥬</span>';
        if (dietary.is_vegan) html += '<span class="dietary-icon vegan" title="Vegan">🌱</span>';
        if (dietary.is_halal) html += '<span class="dietary-icon halal" title="Halal">☪️</span>';
        if (dietary.is_gluten_free) html += '<span class="dietary-icon gf" title="Gluten-free">🚫🌾</span>';

        // Spice level
        if (dietary.spice_level && dietary.spice_level > 0) {
            html += `<span class="spice-meter" title="Spice Level ${dietary.spice_level}">`;
            for (let i = 0; i < 5; i++) {
                html += `<span class="spice-dot ${i < dietary.spice_level ? 'active' : ''}">🌶️</span>`;
            }
            html += '</span>';
        }

        // Calorie badge
        if (dietary.calories) {
            html += `<span class="calorie-badge">${dietary.calories} ${this.translateFn('calories', 'cal')}</span>`;
        }

        // Allergen badges (max 3 shown, +N for rest)
        const displayAllergens = itemAllergens.slice(0, 3);
        const remaining = itemAllergens.length - 3;

        for (const code of displayAllergens) {
            const tag = this.allergenTags.find(t => t.code === code);
            if (tag) {
                html += `<span class="allergen-badge severity-${tag.severity || 'warning'}" 
                               title="${this._getAllergenName(tag)}"
                               onclick="event.stopPropagation(); window._allergenFilter.showAllergenSheet('${itemId}')">
                    ${tag.icon || '⚠️'}
                </span>`;
            }
        }

        if (remaining > 0) {
            html += `<span class="allergen-badge more" 
                           onclick="event.stopPropagation(); window._allergenFilter.showAllergenSheet('${itemId}')">
                +${remaining}
            </span>`;
        }

        html += '</div>';
        return html;
    }

    /**
     * Show allergen detail bottom sheet for specific item
     */
    showAllergenSheet(itemId) {
        const sheet = document.getElementById('allergenDetailSheet');
        if (!sheet) return;

        const t = (key, fallback) => this.translateFn(key, fallback);
        const itemAllergens = this.menuItemAllergens[itemId] || [];
        const dietary = this.menuItemDietary[itemId] || {};

        let html = `
            <div class="allergen-sheet-header">
                <h3>${t('allergenInfo', 'Allergen Information')}</h3>
                <button class="allergen-sheet-close" onclick="window._allergenFilter.hideAllergenSheet()">✕</button>
            </div>
            <div class="allergen-sheet-body">
        `;

        // Dietary info section
        const dietaryInfo = [];
        if (dietary.is_vegetarian) dietaryInfo.push({ icon: '🥬', label: t('vegetarian', 'Vegetarian') });
        if (dietary.is_vegan) dietaryInfo.push({ icon: '🌱', label: t('vegan', 'Vegan') });
        if (dietary.is_halal) dietaryInfo.push({ icon: '☪️', label: t('halal', 'Halal') });
        if (dietary.is_gluten_free) dietaryInfo.push({ icon: '🌾❌', label: t('glutenFree', 'Gluten-free') });

        if (dietaryInfo.length > 0) {
            html += '<div class="allergen-sheet-section">';
            html += `<h4 class="allergen-sheet-section-title">${t('dietaryFilters', 'Dietary')}</h4>`;
            html += '<div class="allergen-sheet-tags">';
            for (const d of dietaryInfo) {
                html += `<span class="allergen-sheet-tag safe">${d.icon} ${d.label}</span>`;
            }
            html += '</div></div>';
        }

        // Allergen list
        if (itemAllergens.length > 0) {
            html += '<div class="allergen-sheet-section">';
            html += `<h4 class="allergen-sheet-section-title">${t('containsAllergen', 'Contains')}</h4>`;
            html += '<div class="allergen-sheet-list">';
            for (const code of itemAllergens) {
                const tag = this.allergenTags.find(t => t.code === code);
                if (tag) {
                    html += `
                        <div class="allergen-sheet-item severity-${tag.severity}">
                            <span class="allergen-sheet-item-icon">${tag.icon || '⚠️'}</span>
                            <span class="allergen-sheet-item-name">${this._getAllergenName(tag)}</span>
                            <span class="allergen-sheet-item-severity">${tag.severity === 'danger' ? '⚠️ High Risk' : tag.severity === 'warning' ? '⚠ Caution' : 'ℹ️ Info'}</span>
                        </div>
                    `;
                }
            }
            html += '</div></div>';
        } else {
            html += `<div class="allergen-sheet-safe">
                <span class="allergen-sheet-safe-icon">✅</span>
                <p>No known allergens listed</p>
            </div>`;
        }

        // Nutrition
        if (dietary.calories || dietary.spice_level) {
            html += '<div class="allergen-sheet-section">';
            html += '<h4 class="allergen-sheet-section-title">Nutrition</h4>';
            html += '<div class="allergen-sheet-nutrition">';
            if (dietary.calories) {
                html += `<div class="nutrition-item"><span class="nutrition-icon">🔥</span><span>${dietary.calories} ${t('calories', 'cal')}</span></div>`;
            }
            if (dietary.spice_level > 0) {
                html += `<div class="nutrition-item"><span class="nutrition-icon">🌶️</span><span>${t('spiceLevel', 'Spice Level')} ${'🌶️'.repeat(dietary.spice_level)}</span></div>`;
            }
            html += '</div></div>';
        }

        html += '</div>';

        sheet.innerHTML = html;
        sheet.classList.add('active');
        document.body.classList.add('sheet-open');
    }

    /**
     * Hide allergen detail sheet
     */
    hideAllergenSheet() {
        const sheet = document.getElementById('allergenDetailSheet');
        if (sheet) {
            sheet.classList.remove('active');
            document.body.classList.remove('sheet-open');
        }
    }

    // ─── Toggle Methods ─────────────────────────────────────────

    toggleDietaryFilter(type) {
        if (this.activeDietaryFilters.has(type)) {
            this.activeDietaryFilters.delete(type);
        } else {
            this.activeDietaryFilters.add(type);
        }
        this._onFilterChange();
    }

    toggleAllergenExclusion(code) {
        if (this.excludedAllergens.has(code)) {
            this.excludedAllergens.delete(code);
        } else {
            this.excludedAllergens.add(code);
        }
        this._onFilterChange();
    }

    toggleAllergenPanel() {
        this._allergenPanelOpen = !this._allergenPanelOpen;
        const panel = document.getElementById('allergenExclusionPanel');
        if (panel) {
            panel.classList.toggle('open', this._allergenPanelOpen);
        }
    }

    clearAllFilters() {
        this.activeDietaryFilters.clear();
        this.excludedAllergens.clear();
        this._allergenPanelOpen = false;
        this._onFilterChange();
    }

    // ─── Private Helpers ────────────────────────────────────────

    _onFilterChange() {
        // Re-render filters
        this.renderFilters('dietaryFilterContainer');
        // Trigger menu re-render in main app
        if (window.app && typeof window.app.renderMenuItems === 'function') {
            window.app.renderMenuItems();
        }
    }

    _getActiveFilterCount() {
        return this.activeDietaryFilters.size + this.excludedAllergens.size;
    }

    _getAllergenName(tag) {
        const lang = localStorage.getItem('lang') || 'th';
        if (lang === 'th' && tag.name_th) return tag.name_th;
        if (lang === 'zh' && tag.name_zh) return tag.name_zh;
        return tag.name_en || tag.code;
    }

    _getDefaultAllergenTags() {
        return [
            { code: 'gluten', name_en: 'Gluten', name_th: 'กลูเตน', name_zh: '麸质', icon: '🌾', severity: 'warning', sort_order: 1 },
            { code: 'dairy', name_en: 'Dairy', name_th: 'นม', name_zh: '乳制品', icon: '🥛', severity: 'warning', sort_order: 2 },
            { code: 'eggs', name_en: 'Eggs', name_th: 'ไข่', name_zh: '鸡蛋', icon: '🥚', severity: 'warning', sort_order: 3 },
            { code: 'nuts', name_en: 'Tree Nuts', name_th: 'ถั่วเปลือกแข็ง', name_zh: '坚果', icon: '🥜', severity: 'danger', sort_order: 4 },
            { code: 'peanuts', name_en: 'Peanuts', name_th: 'ถั่วลิสง', name_zh: '花生', icon: '🥜', severity: 'danger', sort_order: 5 },
            { code: 'shellfish', name_en: 'Shellfish', name_th: 'หอย/กุ้ง', name_zh: '贝类', icon: '🦐', severity: 'danger', sort_order: 6 },
            { code: 'fish', name_en: 'Fish', name_th: 'ปลา', name_zh: '鱼', icon: '🐟', severity: 'warning', sort_order: 7 },
            { code: 'soy', name_en: 'Soy', name_th: 'ถั่วเหลือง', name_zh: '大豆', icon: '🫘', severity: 'warning', sort_order: 8 },
            { code: 'sesame', name_en: 'Sesame', name_th: 'งา', name_zh: '芝麻', icon: '⚪', severity: 'warning', sort_order: 9 },
            { code: 'celery', name_en: 'Celery', name_th: 'ขึ้นฉ่าย', name_zh: '芹菜', icon: '🥬', severity: 'info', sort_order: 10 },
            { code: 'mustard', name_en: 'Mustard', name_th: 'มัสตาร์ด', name_zh: '芥末', icon: '🟡', severity: 'info', sort_order: 11 },
            { code: 'sulfites', name_en: 'Sulfites', name_th: 'ซัลไฟต์', name_zh: '亚硫酸盐', icon: '🧪', severity: 'info', sort_order: 12 }
        ];
    }
}
