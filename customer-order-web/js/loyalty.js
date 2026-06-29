/**
 * AlphaPos — Loyalty / Rewards System
 * 
 * Manages customer loyalty points, tiers, earning, and redemption.
 * Integrates with Supabase RPCs: earn_loyalty_points, redeem_loyalty_points, get_loyalty_dashboard
 */

export class LoyaltySystem {
    constructor() {
        this.supabase = null;
        this.merchantId = null;
        this.config = null; // { loyalty_enabled, points_per_baht, redemption_rate, welcome_bonus }
        this.account = null; // customer_accounts row
        this.dashboard = null; // from get_loyalty_dashboard RPC
        this.isLoggedIn = false;
        this._pollInterval = null;
    }

    /**
     * Initialize loyalty system — fetch merchant config
     */
    async init(supabaseClient, merchantId, localServerURL) {
        this.supabase = supabaseClient;
        this.merchantId = merchantId;
        this.localServerURL = localServerURL;

        // Try to restore session from localStorage
        const savedAccount = localStorage.getItem('alphapos_loyalty_account');
        if (savedAccount) {
            try {
                this.account = JSON.parse(savedAccount);
                this.isLoggedIn = true;
            } catch(e) { /* ignore */ }
        }

        // Fetch merchant loyalty config
        await this._fetchConfig();

        if (!this.config?.loyalty_enabled) return;

        // If logged in, fetch dashboard
        if (this.isLoggedIn) {
            await this._fetchDashboard();
        }
    }

    async _fetchConfig() {
        try {
            if (this.supabase) {
                const { data } = await this.supabase
                    .from('merchants')
                    .select('loyalty_enabled, loyalty_points_per_baht, loyalty_redemption_rate, loyalty_welcome_bonus')
                    .eq('id', this.merchantId)
                    .single();
                if (data) {
                    this.config = data;
                    return;
                }
            }
        } catch(e) { console.warn('[Loyalty] Config fetch failed:', e); }

        // Fallback defaults
        this.config = {
            loyalty_enabled: false,
            loyalty_points_per_baht: 1,
            loyalty_redemption_rate: 0.25,
            loyalty_welcome_bonus: 50
        };
    }

    async _fetchDashboard() {
        if (!this.account?.id) return;
        try {
            if (this.supabase) {
                const { data } = await this.supabase.rpc('get_loyalty_dashboard', {
                    p_merchant_id: this.merchantId,
                    p_customer_account_id: this.account.id
                });
                if (data) {
                    this.dashboard = data;
                    return;
                }
            }
        } catch(e) { console.warn('[Loyalty] Dashboard fetch failed:', e); }
    }

    // =========================================================================
    // MINI WIDGET (Header)
    // =========================================================================

    renderMiniWidget(containerId) {
        const container = document.getElementById(containerId);
        if (!container) return;
        if (!this.config?.loyalty_enabled) { container.innerHTML = ''; return; }

        if (!this.isLoggedIn) {
            container.innerHTML = `
                <button class="loyalty-mini-badge loyalty-join-btn" onclick="window._loyaltySystem.showRegisterModal()">
                    <span class="loyalty-mini-icon">⭐</span>
                    <span class="loyalty-mini-text">${this._t('joinRewards')}</span>
                </button>
            `;
            return;
        }

        const points = this.dashboard?.points_balance ?? this.account?.points_balance ?? 0;
        const tier = this.dashboard?.current_tier ?? this.account?.loyalty_tier ?? 'Bronze';
        const tierColor = this._getTierColor(tier);

        container.innerHTML = `
            <button class="loyalty-mini-badge" onclick="window._loyaltySystem.showDashboard()">
                <span class="loyalty-mini-icon">⭐</span>
                <span class="loyalty-mini-points">${this._formatPoints(points)}</span>
                <span class="loyalty-tier-badge" style="background:${tierColor}">${tier}</span>
            </button>
        `;
    }

    // =========================================================================
    // EARN PREVIEW (Cart)
    // =========================================================================

    renderEarnPreview(cartTotal) {
        if (!this.config?.loyalty_enabled || !this.isLoggedIn) return '';
        const pointsToEarn = Math.floor(cartTotal * (this.config.loyalty_points_per_baht || 1));
        if (pointsToEarn <= 0) return '';

        const tier = this.dashboard?.current_tier ?? 'Bronze';
        const multiplier = this.dashboard?.tier_multiplier ?? 1;
        const actualPoints = Math.floor(pointsToEarn * multiplier);

        return `
            <div class="loyalty-earn-preview">
                <span class="loyalty-earn-icon">⭐</span>
                <span class="loyalty-earn-text">
                    ${this._t('earnPoints')} <strong>+${actualPoints}</strong> ${this._t('loyaltyPoints')}
                </span>
                ${multiplier > 1 ? `<span class="loyalty-multiplier-badge">${multiplier}x</span>` : ''}
            </div>
        `;
    }

    // =========================================================================
    // REDEEM FLOW (Payment)
    // =========================================================================

    showRedeemFlow(cartTotal) {
        if (!this.config?.loyalty_enabled || !this.isLoggedIn) return;
        const points = this.dashboard?.points_balance ?? this.account?.points_balance ?? 0;
        if (points <= 0) return;

        const redemptionRate = this.config.loyalty_redemption_rate || 0.25;
        const maxDiscount = Math.min(points * redemptionRate, cartTotal * 0.5); // max 50% off
        const maxPoints = Math.floor(maxDiscount / redemptionRate);

        const modal = document.createElement('div');
        modal.className = 'loyalty-redeem-overlay';
        modal.id = 'loyaltyRedeemOverlay';
        modal.innerHTML = `
            <div class="loyalty-redeem-card">
                <div class="loyalty-redeem-header">
                    <span class="loyalty-redeem-icon">🎁</span>
                    <h3>${this._t('usePoints')}</h3>
                    <p class="loyalty-redeem-balance">${this._t('pointsBalance')}: <strong>${this._formatPoints(points)}</strong></p>
                </div>
                <div class="loyalty-redeem-body">
                    <div class="loyalty-redeem-slider-container">
                        <input type="range" id="loyaltyRedeemSlider" class="loyalty-redeem-slider"
                            min="0" max="${maxPoints}" value="0" step="10"
                            oninput="window._loyaltySystem._updateRedeemPreview(this.value)">
                        <div class="loyalty-redeem-labels">
                            <span>0</span>
                            <span>${this._formatPoints(maxPoints)}</span>
                        </div>
                    </div>
                    <div class="loyalty-redeem-preview" id="loyaltyRedeemPreview">
                        <div class="loyalty-redeem-points-selected">
                            <span id="redeemPointsValue">0</span> ${this._t('loyaltyPoints')}
                        </div>
                        <div class="loyalty-redeem-discount">
                            = ฿<span id="redeemDiscountValue">0</span> ${this._t('discountApplied', 'off')}
                        </div>
                    </div>
                </div>
                <div class="loyalty-redeem-actions">
                    <button class="loyalty-redeem-cancel" onclick="window._loyaltySystem.hideRedeemFlow()">
                        ${this._t('cancel', 'Cancel')}
                    </button>
                    <button class="loyalty-redeem-confirm" id="loyaltyRedeemConfirmBtn"
                        onclick="window._loyaltySystem._confirmRedeem()">
                        ${this._t('redeemPoints')}
                    </button>
                </div>
            </div>
        `;
        document.body.appendChild(modal);
        requestAnimationFrame(() => modal.classList.add('active'));

        this._redeemState = { maxPoints, redemptionRate, cartTotal };
    }

    _updateRedeemPreview(value) {
        const points = parseInt(value);
        const discount = (points * (this._redeemState?.redemptionRate || 0.25)).toFixed(0);
        const pointsEl = document.getElementById('redeemPointsValue');
        const discountEl = document.getElementById('redeemDiscountValue');
        if (pointsEl) pointsEl.textContent = this._formatPoints(points);
        if (discountEl) discountEl.textContent = discount;
    }

    _confirmRedeem() {
        const slider = document.getElementById('loyaltyRedeemSlider');
        const points = parseInt(slider?.value || 0);
        if (points > 0) {
            const discount = points * (this._redeemState?.redemptionRate || 0.25);
            this._pendingRedemption = { points, discount };
            // Emit event for app.js to pick up
            window.dispatchEvent(new CustomEvent('loyalty:redeem', { detail: { points, discount } }));
        }
        this.hideRedeemFlow();
    }

    hideRedeemFlow() {
        const overlay = document.getElementById('loyaltyRedeemOverlay');
        if (overlay) {
            overlay.classList.remove('active');
            setTimeout(() => overlay.remove(), 300);
        }
    }

    getPendingRedemption() {
        return this._pendingRedemption || null;
    }

    clearPendingRedemption() {
        this._pendingRedemption = null;
    }

    // =========================================================================
    // FULL DASHBOARD (Sheet/Panel)
    // =========================================================================

    showDashboard() {
        // Remove existing
        const existing = document.getElementById('loyaltyDashboardPanel');
        if (existing) existing.remove();

        const points = this.dashboard?.points_balance ?? 0;
        const tier = this.dashboard?.current_tier ?? 'Bronze';
        const tierColor = this._getTierColor(tier);
        const nextTier = this.dashboard?.next_tier;
        const pointsToNext = this.dashboard?.points_to_next_tier ?? 0;
        const progress = this.dashboard?.tier_progress ?? 0;
        const transactions = this.dashboard?.recent_transactions ?? [];

        const panel = document.createElement('div');
        panel.className = 'loyalty-dashboard-overlay';
        panel.id = 'loyaltyDashboardPanel';
        panel.innerHTML = `
            <div class="loyalty-dashboard">
                <div class="loyalty-dashboard-header">
                    <button class="loyalty-dashboard-close" onclick="window._loyaltySystem.hideDashboard()">✕</button>
                    <div class="loyalty-dashboard-tier-card" style="background: linear-gradient(135deg, ${tierColor}22, ${tierColor}44)">
                        <div class="loyalty-tier-icon-large">⭐</div>
                        <div class="loyalty-tier-name" style="color:${tierColor}">${tier}</div>
                        <div class="loyalty-points-large">${this._formatPoints(points)}</div>
                        <div class="loyalty-points-label">${this._t('loyaltyPoints')}</div>
                    </div>
                </div>

                ${nextTier ? `
                <div class="loyalty-progress-section">
                    <div class="loyalty-progress-header">
                        <span>${this._t('nextTier')}</span>
                        <span class="loyalty-next-tier-name" style="color:${this._getTierColor(nextTier)}">${nextTier}</span>
                    </div>
                    <div class="loyalty-progress-bar">
                        <div class="loyalty-progress-fill" style="width:${Math.min(progress, 100)}%; background:${this._getTierColor(nextTier)}"></div>
                    </div>
                    <div class="loyalty-progress-footer">
                        <span>${this._formatPoints(pointsToNext)} ${this._t('loyaltyPoints')} ${this._t('remaining', 'more')}</span>
                    </div>
                </div>
                ` : ''}

                <div class="loyalty-benefits-section">
                    <h4>${this._t('tierBenefits', 'Tier Benefits')}</h4>
                    <div class="loyalty-benefits-list">
                        ${this._renderBenefits(tier)}
                    </div>
                </div>

                <div class="loyalty-history-section">
                    <h4>${this._t('pointsHistory', 'Points History')}</h4>
                    <div class="loyalty-history-list">
                        ${transactions.length === 0 
                            ? `<div class="loyalty-history-empty">${this._t('noHistory', 'No transactions yet')}</div>`
                            : transactions.map(tx => this._renderTransaction(tx)).join('')
                        }
                    </div>
                </div>

                <button class="loyalty-dashboard-logout" onclick="window._loyaltySystem.logout()">
                    ${this._t('logout', 'Log out')}
                </button>
            </div>
        `;
        document.body.appendChild(panel);
        requestAnimationFrame(() => panel.classList.add('active'));
    }

    hideDashboard() {
        const panel = document.getElementById('loyaltyDashboardPanel');
        if (panel) {
            panel.classList.remove('active');
            setTimeout(() => panel.remove(), 300);
        }
    }

    _renderBenefits(tier) {
        const benefits = {
            'Bronze': ['1x points earning', 'Birthday bonus 50 pts'],
            'Silver': ['1.5x points earning', 'Birthday bonus 100 pts', '5% discount on orders'],
            'Gold': ['2x points earning', 'Birthday bonus 200 pts', '10% discount on orders', 'Priority seating'],
            'Platinum': ['3x points earning', 'Birthday bonus 500 pts', '15% discount on orders', 'Priority seating', 'Complimentary dessert']
        };
        const list = benefits[tier] || benefits['Bronze'];
        return list.map(b => `<div class="loyalty-benefit-item">✓ ${b}</div>`).join('');
    }

    _renderTransaction(tx) {
        const isEarn = tx.transaction_type === 'earn';
        const sign = isEarn ? '+' : '-';
        const cls = isEarn ? 'earn' : 'redeem';
        const date = new Date(tx.created_at).toLocaleDateString();
        return `
            <div class="loyalty-history-item ${cls}">
                <div class="loyalty-history-icon">${isEarn ? '⬆️' : '⬇️'}</div>
                <div class="loyalty-history-details">
                    <div class="loyalty-history-desc">${tx.description || tx.source || tx.transaction_type}</div>
                    <div class="loyalty-history-date">${date}</div>
                </div>
                <div class="loyalty-history-points ${cls}">${sign}${Math.abs(tx.points)}</div>
            </div>
        `;
    }

    // =========================================================================
    // QUICK REGISTER / LOGIN
    // =========================================================================

    showRegisterModal() {
        const existing = document.getElementById('loyaltyRegisterModal');
        if (existing) existing.remove();

        const modal = document.createElement('div');
        modal.className = 'loyalty-register-overlay';
        modal.id = 'loyaltyRegisterModal';
        modal.innerHTML = `
            <div class="loyalty-register-card">
                <button class="loyalty-register-close" onclick="window._loyaltySystem.hideRegisterModal()">✕</button>
                <div class="loyalty-register-header">
                    <div class="loyalty-register-icon">⭐</div>
                    <h3>${this._t('joinRewards')}</h3>
                    <p class="loyalty-register-subtitle">${this._t('joinRewardsDesc', 'Earn points with every order')}</p>
                    ${this.config?.loyalty_welcome_bonus > 0 
                        ? `<div class="loyalty-welcome-bonus">🎁 +${this.config.loyalty_welcome_bonus} ${this._t('loyaltyPoints')} ${this._t('welcomeBonus', 'welcome bonus')}</div>` 
                        : ''
                    }
                </div>
                <form class="loyalty-register-form" onsubmit="window._loyaltySystem._handleRegister(event)">
                    <div class="loyalty-form-group">
                        <label>${this._t('phoneNumber')}</label>
                        <input type="tel" id="loyaltyPhone" class="loyalty-input" 
                            placeholder="0XX-XXX-XXXX" required maxlength="12"
                            pattern="[0-9\\-]{9,12}">
                    </div>
                    <div class="loyalty-form-group">
                        <label>${this._t('yourName', 'Name')}</label>
                        <input type="text" id="loyaltyName" class="loyalty-input" 
                            placeholder="${this._t('yourName', 'Name')}" required maxlength="50">
                    </div>
                    <button type="submit" class="loyalty-register-submit">
                        ${this._t('joinRewards')}
                    </button>
                </form>
                <div class="loyalty-register-footer">
                    <button class="loyalty-login-link" onclick="window._loyaltySystem._toggleLoginMode()">
                        ${this._t('alreadyMember', 'Already a member? Log in')}
                    </button>
                </div>
            </div>
        `;
        document.body.appendChild(modal);
        requestAnimationFrame(() => modal.classList.add('active'));
    }

    hideRegisterModal() {
        const modal = document.getElementById('loyaltyRegisterModal');
        if (modal) {
            modal.classList.remove('active');
            setTimeout(() => modal.remove(), 300);
        }
    }

    async _handleRegister(e) {
        e.preventDefault();
        const phone = document.getElementById('loyaltyPhone')?.value?.trim();
        const name = document.getElementById('loyaltyName')?.value?.trim();
        if (!phone || !name) return;

        try {
            const account = await this.quickRegister(phone, name);
            if (account) {
                this.hideRegisterModal();
                this._showPointsAnimation(this.config?.loyalty_welcome_bonus || 0);
                // Re-render mini widget
                this.renderMiniWidget('loyaltyMiniContainer');
            }
        } catch(err) {
            console.error('[Loyalty] Register failed:', err);
        }
    }

    async quickRegister(phone, name) {
        try {
            let data;
            if (this.supabase) {
                // Check if account exists
                const { data: existing } = await this.supabase
                    .from('customer_accounts')
                    .select('*')
                    .eq('merchant_id', this.merchantId)
                    .eq('phone', phone)
                    .single();

                if (existing) {
                    // Login instead
                    this.account = existing;
                } else {
                    // Create new
                    const { data: newAccount, error } = await this.supabase
                        .from('customer_accounts')
                        .insert({
                            merchant_id: this.merchantId,
                            phone: phone,
                            display_name: name,
                            points_balance: this.config?.loyalty_welcome_bonus || 0,
                            auth_provider: 'phone'
                        })
                        .select()
                        .single();

                    if (error) throw error;
                    this.account = newAccount;
                }
            } else {
                // Fallback local
                this.account = {
                    id: crypto.randomUUID(),
                    phone, display_name: name,
                    points_balance: this.config?.loyalty_welcome_bonus || 0,
                    loyalty_tier: 'Bronze'
                };
            }

            this.isLoggedIn = true;
            localStorage.setItem('alphapos_loyalty_account', JSON.stringify(this.account));
            await this._fetchDashboard();
            return this.account;
        } catch(err) {
            console.error('[Loyalty] Registration error:', err);
            return null;
        }
    }

    async login(phone) {
        try {
            if (this.supabase) {
                const { data } = await this.supabase
                    .from('customer_accounts')
                    .select('*')
                    .eq('merchant_id', this.merchantId)
                    .eq('phone', phone)
                    .single();

                if (data) {
                    this.account = data;
                    this.isLoggedIn = true;
                    localStorage.setItem('alphapos_loyalty_account', JSON.stringify(this.account));
                    await this._fetchDashboard();
                    this.renderMiniWidget('loyaltyMiniContainer');
                    return data;
                }
            }
            return null;
        } catch(err) {
            console.error('[Loyalty] Login error:', err);
            return null;
        }
    }

    _toggleLoginMode() {
        const form = document.querySelector('.loyalty-register-form');
        if (!form) return;
        const nameGroup = form.querySelector('.loyalty-form-group:nth-child(2)');
        if (nameGroup) {
            nameGroup.style.display = nameGroup.style.display === 'none' ? '' : 'none';
        }
        const submitBtn = form.querySelector('.loyalty-register-submit');
        if (submitBtn) {
            const isLogin = nameGroup?.style.display === 'none';
            submitBtn.textContent = isLogin ? this._t('login', 'Log in') : this._t('joinRewards');
        }
    }

    logout() {
        this.account = null;
        this.dashboard = null;
        this.isLoggedIn = false;
        localStorage.removeItem('alphapos_loyalty_account');
        this.hideDashboard();
        this.renderMiniWidget('loyaltyMiniContainer');
    }

    // =========================================================================
    // POINTS EARNED ANIMATION (after order)
    // =========================================================================

    showPointsEarned(points) {
        this._showPointsAnimation(points);
    }

    _showPointsAnimation(points) {
        if (points <= 0) return;
        const anim = document.createElement('div');
        anim.className = 'loyalty-points-animation';
        anim.innerHTML = `
            <div class="loyalty-points-anim-content">
                <span class="loyalty-points-anim-icon">⭐</span>
                <span class="loyalty-points-anim-value">+${points}</span>
                <span class="loyalty-points-anim-label">${this._t('pointsEarned')}</span>
            </div>
        `;
        document.body.appendChild(anim);
        requestAnimationFrame(() => anim.classList.add('active'));
        setTimeout(() => {
            anim.classList.remove('active');
            setTimeout(() => anim.remove(), 500);
        }, 2500);
    }

    // =========================================================================
    // After order: earn points via RPC
    // =========================================================================

    async earnPointsForOrder(orderId, amount) {
        if (!this.isLoggedIn || !this.account?.id) return 0;
        try {
            if (this.supabase) {
                const { data } = await this.supabase.rpc('earn_loyalty_points', {
                    p_merchant_id: this.merchantId,
                    p_customer_account_id: this.account.id,
                    p_order_id: orderId,
                    p_amount: amount
                });
                const earned = data?.points_earned || Math.floor(amount * (this.config?.loyalty_points_per_baht || 1));
                this.showPointsEarned(earned);
                await this._fetchDashboard();
                this.renderMiniWidget('loyaltyMiniContainer');
                return earned;
            }
        } catch(e) { console.warn('[Loyalty] Earn points error:', e); }
        return 0;
    }

    // =========================================================================
    // HELPERS
    // =========================================================================

    _getTierColor(tier) {
        const colors = {
            'Bronze': '#CD7F32',
            'Silver': '#C0C0C0',
            'Gold': '#FFD700',
            'Platinum': '#E5E4E2'
        };
        return colors[tier] || colors['Bronze'];
    }

    _formatPoints(pts) {
        return Number(pts || 0).toLocaleString();
    }

    _t(key, fallback) {
        if (window.app && typeof window.app.translate === 'function') {
            return window.app.translate(key, fallback || key);
        }
        return fallback || key;
    }

    destroy() {
        if (this._pollInterval) {
            clearInterval(this._pollInterval);
            this._pollInterval = null;
        }
    }
}

// Singleton
export const loyaltySystem = new LoyaltySystem();

// Expose globally for onclick handlers
window._loyaltySystem = loyaltySystem;
