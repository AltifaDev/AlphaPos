/**
 * AlphaPos — App Core Module
 * 
 * Contains the AlphaPosApp class skeleton with constructor, init(),
 * and utility methods. All feature-specific logic is imported from
 * separate modules and mixed in.
 */

import { translations } from './i18n.js';
import { defaultMenuItems } from './data.js';
import { fetchWithFallback, fetchWithRetry } from './api.js';
import { clearCart, loadCart, saveCart } from './cart.js';
import { hideStatusModal, showStatusModal, showToast } from './ui.js';

// Feature modules
import { OnboardingMixin } from './onboarding.js';
import { MenuRendererMixin } from './menu-renderer.js';
import { CartManagerMixin } from './cart-manager.js';
import { OrderSubmissionMixin } from './order-submission.js';
import { PaymentHandlerMixin } from './payment-handler.js';
import { ServiceRequestsMixin } from './service-requests.js';
import { RealtimeManagerMixin } from './realtime-manager.js';
import { ThemeManagerMixin } from './theme-manager.js';

// Safe HTML escaping
export function escapeHtml(str) {
    if (!str) return '';
    const div = document.createElement('div');
    div.textContent = str;
    return div.innerHTML;
}

export function formatCurrency(amount, currency = 'THB', locale = 'th-TH') {
    try {
        return new Intl.NumberFormat(locale, { style: 'currency', currency }).format(amount);
    } catch {
        return `฿${Number(amount).toFixed(2)}`;
    }
}

export function formatNumber(num, decimals = 0) {
    try {
        return new Intl.NumberFormat().format(num);
    } catch {
        return String(num);
    }
}

/**
 * Main Application Class — assembles all mixins
 */
export class AlphaPosApp {
    constructor() {
        // State
        this.menuItems = defaultMenuItems;
        this.categories = [];
        this.cart = [];
        this.currentCategory = 'recommended';
        this.currentLang = localStorage.getItem('alphapos_lang') || 'th';
        this.currentTheme = localStorage.getItem('alphapos_theme') || 'dark';
        this.guestCount = 1;
        this.tableNumber = '';
        this.sessionToken = '';
        this.supabase = null;
        this.realtimeChannels = [];
        this.pollingInterval = null;
        this.syncHealthInterval = null;
        this._lastOrderId = null;
        this._orderTracker = null;
        this._waitTimeWidget = null;
        this._allergenFilter = null;
        this._feedbackSystem = null;

        // Translations reference
        this.translations = translations;

        // Debounce helper
        this._debounceTimers = {};
    }

    /**
     * Initialize app — called after DOM is ready
     */
    async init() {
        console.log('[AlphaPos] Initializing modular app...');
        
        // Parse URL params (table, session token from QR)
        this.parseURLParams();
        
        // Apply theme
        this.applyTheme();
        
        // Apply language
        this.translateUI();
        
        // Init Supabase client
        this.initSupabase();
        
        // Setup accessibility
        this.setupAccessibilityHandlers();
        
        // Load menu
        await this.loadMenuFromServer();
        
        // Show onboarding if needed
        if (!this.sessionToken) {
            this.showOnboardingPanel();
        } else {
            this.renderCategories();
            this.renderMenuItems();
        }
        
        // Setup realtime
        this.setupRealtimeSubscriptions();
        
        // Start sync health polling
        this.startSyncHealthPolling();
        
        console.log('[AlphaPos] ✅ App initialized');
    }

    // ==========================================
    // Utility Methods
    // ==========================================
    
    _debounce(key, fn, delay = 300) {
        if (this._debounceTimers[key]) clearTimeout(this._debounceTimers[key]);
        this._debounceTimers[key] = setTimeout(fn, delay);
    }

    parseURLParams() {
        const params = new URLSearchParams(window.location.search);
        this.tableNumber = params.get('table') || params.get('t') || '';
        this.sessionToken = params.get('session') || params.get('s') || '';
        const lang = params.get('lang') || params.get('l');
        if (lang && ['th', 'en', 'zh'].includes(lang)) {
            this.currentLang = lang;
        }
    }

    initSupabase() {
        if (window.ALPHAPOS_CONFIG && window.ALPHAPOS_CONFIG.supabaseUrl && window.supabase) {
            try {
                this.supabase = window.supabase.createClient(
                    window.ALPHAPOS_CONFIG.supabaseUrl,
                    window.ALPHAPOS_CONFIG.supabaseKey
                );
                console.log('[Supabase] Client initialized');
            } catch (e) {
                console.warn('[Supabase] Init failed:', e);
            }
        }
    }

    setupAccessibilityHandlers() {
        // Keyboard navigation support
        document.addEventListener('keydown', (e) => {
            if (e.key === 'Escape') {
                this.closeAllModals();
            }
        });
    }

    closeAllModals() {
        // Close any open sheets/modals
        document.querySelectorAll('.bottom-sheet.active, .modal.active').forEach(el => {
            el.classList.remove('active');
        });
    }

    calculateTotals() {
        const subtotal = this.cart.reduce((sum, item) => sum + (item.price * item.quantity), 0);
        const serviceCharge = subtotal * 0.10;
        const vat = (subtotal + serviceCharge) * 0.07;
        const total = subtotal + serviceCharge + vat;
        return { subtotal, serviceCharge, vat, total };
    }

    switchView(viewName) {
        document.querySelectorAll('.app-view').forEach(el => el.classList.remove('active'));
        const target = document.getElementById(`view-${viewName}`);
        if (target) target.classList.add('active');
    }
}

// ==========================================
// Apply Mixins
// ==========================================
Object.assign(AlphaPosApp.prototype, OnboardingMixin);
Object.assign(AlphaPosApp.prototype, MenuRendererMixin);
Object.assign(AlphaPosApp.prototype, CartManagerMixin);
Object.assign(AlphaPosApp.prototype, OrderSubmissionMixin);
Object.assign(AlphaPosApp.prototype, PaymentHandlerMixin);
Object.assign(AlphaPosApp.prototype, ServiceRequestsMixin);
Object.assign(AlphaPosApp.prototype, RealtimeManagerMixin);
Object.assign(AlphaPosApp.prototype, ThemeManagerMixin);
