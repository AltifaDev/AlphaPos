import { translations } from './js/i18n.js';
import { defaultMenuItems } from './js/data.js';
import { clearCart, loadCart, saveCart } from './js/cart.js';
import { hideStatusModal, showStatusModal, showToast } from './js/ui.js';
import { OrderTracker } from './js/order-tracker.js';
import { FeedbackSystem } from './js/feedback.js';
import { waitTimeWidget } from './js/wait-time.js';
import { AllergenFilter } from './js/allergen-filter.js';
import { reservationSystem } from './js/reservation.js';
import { reorderHistory } from './js/reorder-history.js';
import { billView } from './js/bill-view.js';
import { loyaltySystem } from './js/loyalty.js';
import { pushManager } from './js/push-notifications.js';
import { orderingSessionGate } from './js/ordering-session-gate.js';
import { createClient } from '@supabase/supabase-js';
import { canTransitionOrder, normalizeOrderState } from './js/order-state-machine.js';
import { classifyOrderFailure } from './js/order-failure-state.js';






// Debug Logger for Headless testing
(function() {
    const urlParams = new URLSearchParams(window.location.search);
    if (urlParams.get('autoOnboard') !== 'true') return;
    window.addEventListener("DOMContentLoaded", () => {
        const logDiv = document.createElement("div");
        logDiv.id = "headlessLogs";
        logDiv.style = "position:fixed; bottom:0; left:0; width:100%; max-height:220px; overflow-y:auto; background:rgba(0,0,0,0.85); color:#00ff00; font-family:monospace; font-size:10px; z-index:999999; padding:5px; border-top:1px solid #00ff00; pointer-events:none;";
        document.body.appendChild(logDiv);

        const originalLog = console.log;
        const originalError = console.error;
        const originalWarn = console.warn;

        console.log = function(...args) {
            originalLog.apply(console, args);
            const p = document.createElement("p");
            p.innerText = "[LOG] " + args.map(a => typeof a === 'object' ? JSON.stringify(a) : a).join(" ");
            p.style.margin = "2px 0";
            logDiv.appendChild(p);
            logDiv.scrollTop = logDiv.scrollHeight;
        };

        console.error = function(...args) {
            originalError.apply(console, args);
            const p = document.createElement("p");
            p.innerText = "[ERR] " + args.map(a => typeof a === 'object' ? JSON.stringify(a) : a).join(" ");
            p.style.margin = "2px 0";
            p.style.color = "#ff3b30";
            logDiv.appendChild(p);
            logDiv.scrollTop = logDiv.scrollHeight;
        };

        console.warn = function(...args) {
            originalWarn.apply(console, args);
            const p = document.createElement("p");
            p.innerText = "[WRN] " + args.map(a => typeof a === 'object' ? JSON.stringify(a) : a).join(" ");
            p.style.margin = "2px 0";
            p.style.color = "#ffcc00";
            logDiv.appendChild(p);
            logDiv.scrollTop = logDiv.scrollHeight;
        };
    });
})();

/**
 * AlphaPos - Customer Self-Ordering App Controller
 *
 * Manages application state, cart modifications, menu rendering,
 * and ordering submissions to the KDS backend.
 */

// Safe HTML escaping to prevent XSS
function escapeHtml(str) {
    if (!str) return '';
    const div = document.createElement('div');
    div.textContent = str;
    return div.innerHTML;
}

function safeInnerHtml(el, html) {
    el.innerHTML = html.replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#x27;');
}

function resolvePromoMediaSrc(mediaData, defaultMimeType = 'image/jpeg') {
    if (!mediaData) return '';
    const value = String(mediaData).trim();
    if (!value) return '';
    if (value.startsWith('http://') || value.startsWith('https://') || value.startsWith('blob:') || value.startsWith('data:')) {
        return value;
    }
    // Legacy rows stored raw base64 in image_data
    if (defaultMimeType.startsWith('video/')) {
        return base64ToBlobUrl(value, defaultMimeType);
    }
    return `data:${defaultMimeType};base64,${value}`;
}

function base64ToBlobUrl(base64Data, defaultMimeType = 'video/mp4') {
    if (!base64Data) return '';
    if (base64Data.startsWith('http://') || base64Data.startsWith('https://') || base64Data.startsWith('blob:')) {
        return base64Data;
    }
    
    let mimeType = defaultMimeType;
    let rawBase64 = base64Data;
    
    if (base64Data.startsWith('data:')) {
        const parts = base64Data.split(',');
        if (parts.length > 1) {
            const matches = parts[0].match(/data:(.*?);base64/);
            if (matches && matches[1]) {
                mimeType = matches[1];
            }
            rawBase64 = parts[1];
        }
    }
    
    try {
        const byteCharacters = atob(rawBase64.trim());
        const byteNumbers = new Array(byteCharacters.length);
        for (let i = 0; i < byteCharacters.length; i++) {
            byteNumbers[i] = byteCharacters.charCodeAt(i);
        }
        const byteArray = new Uint8Array(byteNumbers);
        const blob = new Blob([byteArray], { type: mimeType });
        return URL.createObjectURL(blob);
    } catch (e) {
        console.error("Failed to convert base64 to Blob:", e);
        return base64Data.startsWith('data:') ? base64Data : `data:${mimeType};base64,${base64Data}`;
    }
}



function createSafeElement(tag, attrs = {}, textContent = '') {
    const el = document.createElement(tag);
    Object.entries(attrs).forEach(([k, v]) => el.setAttribute(k, v));
    if (textContent) el.textContent = textContent;
    return el;
}

function safeStorageGet(storage, key, fallback = null) {
    try {
        const value = storage?.getItem(key);
        return value === null || value === undefined ? fallback : value;
    } catch (error) {
        console.warn(`[Storage] Read unavailable for ${key}; continuing without persistence.`, error);
        return fallback;
    }
}

function safeStorageSet(storage, key, value) {
    try {
        storage?.setItem(key, value);
        return true;
    } catch (error) {
        console.warn(`[Storage] Write unavailable for ${key}; continuing in memory.`, error);
        return false;
    }
}

function safeStorageRemove(storage, key) {
    try {
        storage?.removeItem(key);
    } catch (error) {
        console.warn(`[Storage] Remove unavailable for ${key}.`, error);
    }
}

function formatCurrency(amount, currency = 'THB', locale = 'th-TH') {
    try {
        return new Intl.NumberFormat(locale, { style: 'currency', currency }).format(amount);
    } catch {
        return `฿${Number(amount).toFixed(2)}`;
    }
}

function formatNumber(num, decimals = 0) {
    try {
        return new Intl.NumberFormat().format(num);
    } catch {
        return String(num);
    }
}

class AlphaPosApp {
    constructor() {
        // Mock Menu Data representing actual restaurant dishes
        this.menuItems = defaultMenuItems; // Loaded from API as fallback

        // Inject sample high-quality food looping videos for recommended items
        if (this.menuItems && this.menuItems.length > 0) {
            // main1: Signature River Prawn Pad Thai
            const main1 = this.menuItems.find(i => i.id === "main1");
            if (main1) main1.videoUrl = "https://player.vimeo.com/external/435674703.sd.mp4?s=7f773cdccf1a0e784534f5263a232f3c64e5ba79&profile_id=139&oauth2_token_id=57447761";
            
            // app3: Tom Yum Goong
            const app3 = this.menuItems.find(i => i.id === "app3");
            if (app3) app3.videoUrl = "https://player.vimeo.com/external/371433846.sd.mp4?s=236da2f3c0227e3d077b90f741131a1b&profile_id=139&oauth2_token_id=57447761";

            // dessert1: Mango Sticky Rice
            const dessert1 = this.menuItems.find(i => i.id === "dessert1");
            if (dessert1) dessert1.videoUrl = "https://player.vimeo.com/external/538571059.sd.mp4?s=d00e62d22b62d377b8b209d6f83a45c382215c2d&profile_id=139&oauth2_token_id=57447761";
        }

        // Categories List
        this.categories = [
            { id: "foods", name: "Foods" },
            { id: "drinks", name: "Drinks" },
            { id: "desserts", name: "Desserts" }
        ];

        // App States
        this.currentCategory = "foods";
        // Allergen & Dietary Filter
        this.allergenFilter = new AllergenFilter();
        window._allergenFilter = this.allergenFilter;
        this.searchQuery = "";
        this.cart = {}; // Format: { cartKey: { itemId, quantity, selectedModifiers: [], notes } }
        this.modifiersConfig = { groups: [], modifiers: [], links: [] };
        this.menuViewMode = safeStorageGet(localStorage, 'menuViewMode', 'grid'); // 'list' | 'grid'
        this.tableNumber = ""; // Set only from QR URL (?table=) or session recovery
        this.sessionToken = null;
        this.selectedGuestCount = 2; // Default
        this.currentOnboardingStep = 1;
        this.currentView = "menu";
        this.branchCode = "";
        this.branchId = "";
        this.tableSessionId = "";
        this.permanentQRKey = "";
        this.customerTokenRefreshTimer = null;

        // Configuration (loaded from config.js or environment)
        const cfg = window.ALPHAPOS_CONFIG || {};
        this.supabaseUrl = cfg.supabaseUrl || '';
        // WSS host for postgres_changes (may differ from REST proxy origin).
        this.supabaseRealtimeUrl = cfg.supabaseRealtimeUrl || cfg.supabaseUrl || '';
        this.supabaseKey = cfg.supabaseKey || '';
        this.edgeFunctionUrl = cfg.edgeFunctionUrl || '';
        this.supabase = null;
        this.supabaseRealtime = null;
        this.merchantId = cfg.merchantId || '';
        this.localServerURL = cfg.localServerURL || window.location.origin;
        this.isLocalServerAvailable = true; // Always enable local server fallback via proxy
        this.merchantToken = null; // JWT token with merchant_id claim
        this._submitInProgress = false;
        this.syncHealthInterval = null;
        this._realtimeLive = false;
        this._knownOrderIds = new Set();
        this._orderHistoryFetchInFlight = false;
        this._lastHistoryRefreshAt = 0;
        this._orderHistorySignature = '';
        this._lastSessionCheckAt = 0;
        this._statusVisibilityHandler = null;
        this._lastNotifiedStatus = null;
        this._orderStates = new Map();
        this._activeModal = null;
        this._lastFocusedElement = null;
        this._activePromotions = [];
        this._appliedPromotions = [];
        this.merchantSettings = {};
        this.merchantDisplayName = 'Restaurant';

        this.lastFetchedOrders = [];
        this.currentLanguage = 'th';

        // Register Service Worker for offline capability
        if ('serviceWorker' in navigator) {
            window.addEventListener('load', () => {
                navigator.serviceWorker.register('./service-worker.js')
                    .then(reg => console.log('Service Worker registered successfully:', reg.scope))
                    .catch(err => console.error('Service Worker registration failed:', err));
            });
        }
    }

    // ========================================
    // ENHANCED BILL VIEW
    // ========================================

    /**
     * Show enhanced bill view with itemized breakdown, tip, and split options
     */
    showEnhancedBill() {
        // Initialize bill view with supabase, translation, and merchant settings
        billView.init(this.supabase, this.merchantId, (key, fallback) => this.translate(key, fallback), this.merchantSettings);

        // Cart is an object map: { cartKey: { itemId, quantity, selectedModifiers } } or legacy { itemId: qty }
        const items = Object.entries(this.cart || {}).map(([key, entry]) => {
            const isObj = entry && typeof entry === 'object';
            const itemId = isObj ? entry.itemId : key;
            const quantity = isObj ? (entry.quantity || 0) : (Number(entry) || 0);
            const menuItem = (this.menuItems || []).find(m => String(m.id) === String(itemId));
            const modifiers = isObj ? (entry.selectedModifiers || []) : [];
            return {
                name: menuItem ? this.getItemName(menuItem) : String(itemId),
                price: menuItem ? (menuItem.price || 0) : 0,
                quantity,
                modifiers
            };
        }).filter(item => item.quantity > 0);

        // Gather active discounts
        const discounts = (this._appliedPromotions || []).map(p => ({
            name: p.name || 'Discount',
            type: p.discount_type === 'percentage' ? 'percent' : 'fixed',
            value: p.discount_value || 0
        }));

        const orderData = {
            items,
            discounts,
            tableNumber: this.tableNumber,
            orderNumber: this._lastOrderNumber || ''
        };

        billView.showBill(orderData, {
            loyaltyPointsEarn: 0,
            loyaltyDiscount: 0
        });
    }

    /**
     * Show receipt after successful payment
     */
    showReceipt(paymentData) {
        billView.init(this.supabase, this.merchantId, (key, fallback) => this.translate(key, fallback), this.merchantSettings);

        const orderData = {
            items: this._lastOrderItems || [],
            discounts: [],
            tableNumber: this.tableNumber,
            orderNumber: this._lastOrderNumber || ''
        };

        billView.showReceipt(orderData, paymentData);
    }

    /**
     * Close the session after payment and block further ordering
     */
    async closeSessionAfterPayment() {
        try {
            // 1. Close session via Supabase
            if (this.supabase) {
                try {
                    const { error } = await this.supabase
                        .from('table_sessions')
                        .update({
                            is_active: 0,
                            ended_at: new Date().toISOString()
                        })
                        .eq('session_token', this.sessionToken)
                        .eq('table_number', this.tableNumber);
                    if (error) throw error;
                    console.log("[Payment] Supabase session closed successfully");
                } catch (e) {
                    console.warn("[Payment] Supabase session close failed:", e);
                }
            }

            // 2. Fallback: close session via local server
            if (this.isLocalServerAvailable) {
                try {
                    const res = await fetch(`${this.localServerURL}/v1/sessions/close`, {
                        method: "POST",
                        headers: { "Content-Type": "application/json" },
                        body: JSON.stringify({
                            table_number: this.tableNumber,
                            session_token: this.sessionToken
                        })
                    });
                    if (res.ok) {
                        console.log("[Payment] Local server session closed successfully");
                    }
                } catch (e) {
                    console.warn("[Payment] Local server session close failed:", e);
                }
            }

            // 3. Clear all local state
            this.sessionToken = null;
            localStorage.removeItem(`sessionToken_T${this.tableNumber}`);
            this.cart = {};
            this.saveCartToStorage();

            // 4. Mark payment completed in location verifier (permanent block)
            orderingSessionGate.markSessionClosed();

            // 5–6. Hide app UI and show blocking screen
            this.showBlockingState(
                "paymentCompleteTitle",
                "paymentCompleteDesc",
                "pleaseOrderStaff"
            );

        } catch (e) {
            console.error("[Payment] Error closing session:", e);
        }
    }

    _showToast(message, duration = 3000) {
        showToast(message, duration);
    }

    _showStatusModal(title, desc, isSuccess = false) {
        showStatusModal(title, desc, isSuccess);
    }

    _hideStatusModal() {
        hideStatusModal();
    }

    saveCartToStorage() {
        saveCart(this.tableNumber, this.cart);
    }

    loadCartFromStorage() {
        try {
            this.cart = loadCart(this.tableNumber);
        } catch (e) {
            console.error("Failed to parse saved cart:", e);
            try { clearCart(this.tableNumber); } catch (_) { /* storage may be unavailable */ }
            this.cart = {};
        }
    }

    unsubscribeRealtimeChannels() {
        const rt = this.supabaseRealtime || this.supabase;
        if (rt && this.realtimeChannels) {
            this.realtimeChannels.forEach(ch => {
                try {
                    rt.removeChannel(ch);
                } catch (e) {
                    console.error("Failed to remove channel:", e);
                }
            });
            this.realtimeChannels = [];
        }
        this._realtimeLive = false;
    }

    shutdownRealtime() {
        this.unsubscribeRealtimeChannels();
        if (this.pollingInterval) {
            clearInterval(this.pollingInterval);
            this.pollingInterval = null;
        }
        if (this.syncHealthInterval) {
            clearInterval(this.syncHealthInterval);
            this.syncHealthInterval = null;
        }
        if (this.promoCarouselInterval) {
            clearInterval(this.promoCarouselInterval);
            this.promoCarouselInterval = null;
        }
        if (this.customerTokenRefreshTimer) {
            clearTimeout(this.customerTokenRefreshTimer);
            this.customerTokenRefreshTimer = null;
        }
        if (this._statusVisibilityHandler) {
            document.removeEventListener('visibilitychange', this._statusVisibilityHandler);
            this._statusVisibilityHandler = null;
        }
    }

    /**
     * Live order-status via Supabase Realtime (WSS on supabaseRealtimeUrl).
     * Polling in startStatusPolling remains as the always-on fallback.
     */
    setupCustomerRealtime() {
        const rt = this.supabaseRealtime || this.supabase;
        if (!rt || !this.tableNumber) {
            console.warn('[Realtime] No client/table — poll-only mode');
            return;
        }
        this.unsubscribeRealtimeChannels();
        this.realtimeChannels = [];

        try {
            const statusChannel = rt
                .channel(`customer-status-${this.tableSessionId}`)
                .on('postgres_changes', {
                    event: 'UPDATE',
                    schema: 'public',
                    table: 'orders',
                    filter: `session_token=eq.${this.sessionToken}`
                }, (payload) => {
                    this._handleLiveOrderChange(payload.new);
                })
                // The customer status screen is item-based. POS/KDS can mark one
                // item served without changing the parent order until every item
                // is terminal, so listening to orders alone leaves the UI stale.
                .on('postgres_changes', {
                    event: 'UPDATE',
                    schema: 'public',
                    table: 'order_items'
                }, (payload) => {
                    this._handleLiveOrderItemChange(payload.new);
                })
                .on('postgres_changes', {
                    event: 'INSERT',
                    schema: 'public',
                    table: 'orders',
                    filter: `session_token=eq.${this.sessionToken}`
                }, (payload) => {
                    this._handleLiveOrderChange(payload.new);
                })
                .subscribe((status) => {
                    if (status === 'SUBSCRIBED') {
                        this._realtimeLive = true;
                        console.log('[Realtime] Subscribed to order status for table', this.tableNumber);
                    } else if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT' || status === 'CLOSED') {
                        this._realtimeLive = false;
                        console.warn('[Realtime] Channel', status, '— relying on poll fallback');
                    }
                });
            this.realtimeChannels.push(statusChannel);

            if (this.merchantId) {
                const sessionChannel = rt
                    .channel(`customer-session-${this.tableSessionId}`)
                    .on('postgres_changes', {
                        event: 'UPDATE',
                        schema: 'public',
                        table: 'table_sessions',
                        filter: `id=eq.${this.tableSessionId}`
                    }, async (payload) => {
                        const row = payload.new || {};
                        if (String(row.table_number) !== String(this.tableNumber)) return;
                        if (row.is_active === 0 || row.is_active === false) {
                            if (this.sessionToken && row.session_token === this.sessionToken) {
                                orderingSessionGate.markSessionClosed();
                                this.showBlockingState(
                                    "sessionClosedTitle",
                                    "sessionClosedDesc",
                                    "pleaseOrderStaff"
                                );
                            }
                        }
                    })
                    .subscribe();
                this.realtimeChannels.push(sessionChannel);

                const menuChannel = rt
                    .channel(`customer-menu-${this.merchantId}`)
                    .on('postgres_changes', {
                        event: '*',
                        schema: 'public',
                        table: 'menu_items'
                    }, () => {
                        console.log('[Realtime] Menu items updated on server, refreshing menu...');
                        this.loadMenuFromServer();
                    })
                    .subscribe();
                this.realtimeChannels.push(menuChannel);
            }
        } catch (e) {
            this._realtimeLive = false;
            console.warn('[Realtime] Setup failed — poll fallback only:', e);
        }
    }

    _handleLiveOrderChange(order) {
        if (!order) return;
        const nextState = normalizeOrderState(order.status);
        const previousState = this._orderStates.get(order.id) || null;
        if (!nextState || !canTransitionOrder(previousState, nextState)) {
            console.warn(JSON.stringify({ level: 'warning', event: 'order_state.invalid_transition', orderId: order.id, from: previousState, to: order.status }));
            return;
        }
        this._orderStates.set(order.id, nextState);
        if (this._debouncedFetchHistory) {
            this._debouncedFetchHistory();
        } else if (this.currentView === "status") {
            this.fetchOrderHistory();
        } else {
            this.updateStatusTabBadgeCount();
        }
        // Notify when status reaches a customer-relevant state.
        try {
            const notifyStatuses = {
                ready: {
                    title: this.translate ? this.translate('pushOrderReadyTitle', 'Order Ready') : 'Order Ready',
                    body: this.translate ? this.translate('pushOrderReadyBody', 'Your order is ready to be served.') : 'Your order is ready to be served.'
                },
                served: {
                    title: this.translate ? this.translate('pushOrderServedTitle', 'Enjoy your meal!') : 'Enjoy your meal!',
                    body: this.translate ? this.translate('pushOrderServedBody', 'Your order has been served.') : 'Your order has been served.'
                },
                cancelled: {
                    title: this.translate ? this.translate('pushOrderCancelledTitle', 'Order Cancelled') : 'Order Cancelled',
                    body: this.translate ? this.translate('pushOrderCancelledBody', 'Your order has been cancelled. Please contact staff.') : 'Your order has been cancelled. Please contact staff.'
                }
            };
            const info = notifyStatuses[order.status];
            const changed = order.status !== this._lastNotifiedStatus;
            if (info && changed && typeof pushManager !== 'undefined' && pushManager?.permission === 'granted') {
                pushManager.showLocalNotification(info.title, info.body, {
                    tag: `order-${order.id}`,
                    orderId: order.id,
                    type: 'order_update',
                    url: '/'
                });
                this._lastNotifiedStatus = order.status;
            }
        } catch (e) {
            console.warn('[Realtime] Notification failed:', e);
        }
    }

    _handleLiveOrderItemChange(item) {
        if (!item?.order_id || !this._knownOrderIds.has(item.order_id)) return;
        if (this._debouncedFetchHistory) {
            this._debouncedFetchHistory();
        } else if (this.currentView === "status") {
            this.fetchOrderHistory({ showLoading: false });
        } else {
            this.updateStatusTabBadgeCount();
        }
    }

    /**
     * GUEST COUNT PERSISTENCE (SessionStorage)
     */

    restoreGuestCount() {
        const saved = sessionStorage.getItem('alphapos_guest_count');
        const timestamp = parseInt(sessionStorage.getItem('alphapos_guest_count_timestamp') || '0');

        // Only restore if set within last 30 minutes
        const EXPIRY_MS = 30 * 60 * 1000;
        const isExpired = (Date.now() - timestamp) > EXPIRY_MS;

        if (saved && !isExpired) {
            const guestCount = parseInt(saved);
            console.log(`[Guest Count] Restored from session: ${guestCount} persons`);
            return guestCount;
        }

        if (saved && isExpired) {
            console.warn(`[Guest Count] Session expired (${Math.round((Date.now() - timestamp) / 1000)}s ago)`);
            sessionStorage.removeItem('alphapos_guest_count');
            sessionStorage.removeItem('alphapos_guest_count_timestamp');
        }

        return null;
    }

    clearGuestCount() {
        sessionStorage.removeItem('alphapos_guest_count');
        sessionStorage.removeItem('alphapos_guest_count_timestamp');
        this.selectedGuestCount = null;
        console.log('[Guest Count] Cleared from session');
    }

    getGuestCount() {
        return this.selectedGuestCount || this.restoreGuestCount();
    }

    validateGuestCount() {
        const guestCount = this.getGuestCount();

        if (!guestCount) {
            return {
                valid: false,
                message: 'Please select number of guests before ordering'
            };
        }

        if (guestCount < 1 || guestCount > 100) {
            return {
                valid: false,
                message: 'Invalid guest count (must be 1-100)'
            };
        }

        return {
            valid: true,
            guestCount: guestCount,
            message: `Order for ${guestCount} guest${guestCount > 1 ? 's' : ''}`
        };
    }

    /**
     * Initializes the Web Application
     */
    async init() {
        this.parseURLParams();
        this.loadCartFromStorage();

        window.addEventListener("beforeunload", () => this.shutdownRealtime());
        window.addEventListener("pagehide", () => this.shutdownRealtime());

        // Exchange the opaque QR session token for a short-lived, branch-scoped
        // customer JWT before creating any Supabase client. URL/localStorage
        // merchant values are hints only; signed claims become authoritative.
        const cachedQrToken = this.tableNumber
            ? safeStorageGet(localStorage, `sessionToken_T${this.tableNumber}`)
            : null;
        const qrToken = this.sessionToken || cachedQrToken;
        if (this.permanentQRKey) {
            const approved = await this.exchangePermanentQR(this.permanentQRKey);
            if (!approved && window.ALPHAPOS_CONFIG?.isProduction) {
                this.showQrInvalidError();
                return;
            }
        } else if (qrToken) {
            const exchanged = await this.exchangeCustomerSession(qrToken);
            if (!exchanged && window.ALPHAPOS_CONFIG?.isProduction) {
                this.showQrInvalidError();
                return;
            }
        } else if (window.ALPHAPOS_CONFIG?.isProduction) {
            this.showQrInvalidError();
            return;
        }

        // Initialize Supabase Client
        // If a JWT token with merchant_id claim is available (from QR code URL),
        // use it as the access token. This replaces the old x-merchant-id header approach.
        // The JWT is signed by the Supabase JWT Secret, so PostgREST trusts its claims.
        const hasSupabaseConfig = this.supabaseUrl &&
            this.supabaseKey &&
            !this.supabaseUrl.includes('your-supabase-project') &&
            !this.supabaseKey.includes('your-anon-key');
        const effectiveKey = this.merchantToken || this.supabaseKey;
        const clientHeaders = {
            // When using JWT, merchant_id is embedded in the token claims — no header needed
            // Keep x-merchant-id as fallback for backward compatibility during transition
            ...(this.merchantToken
                ? { 'Authorization': `Bearer ${this.merchantToken}` }
                : { 'x-merchant-id': this.merchantId })
        };
        this.supabase = hasSupabaseConfig ? createClient(this.supabaseUrl, this.supabaseKey, {
            global: { headers: clientHeaders }
        }) : null;
        // Dedicated Realtime client: REST may be Worker-proxied, but WSS must
        // open against the public API host (Caddy → Kong Realtime).
        const realtimeHost = this.supabaseRealtimeUrl || this.supabaseUrl;
        const realtimeDistinct = realtimeHost && realtimeHost !== this.supabaseUrl;
        this.supabaseRealtime = (hasSupabaseConfig && realtimeHost)
            ? (realtimeDistinct
                ? createClient(realtimeHost, this.supabaseKey, {
                    global: { headers: clientHeaders },
                    realtime: { params: { apikey: this.supabaseKey } }
                })
                : this.supabase)
            : null;
        if (this.merchantToken && this.supabaseRealtime?.realtime?.setAuth) {
            try { this.supabaseRealtime.realtime.setAuth(this.merchantToken); } catch (_) { /* ignore */ }
        }

        const isAllowed = await this.checkOrOpenSession();
        if (isAllowed === false) {
            console.warn("Initialization halted: Web ordering or table system is disabled.");
            return;
        }
        await this.loadMenuFromServer();

        // Paint the catalog as soon as the core menu query completes. Optional
        // integrations must never leave customers looking at an empty shell.
        this.renderCategories();
        this.renderMenuItems();
        this.updateCartUI();

        await this.loadModifiersConfig();
        await this.loadPromotions();

        // Initialize loyalty system
        if (this.supabase || this.localServerURL) {
            try {
                await loyaltySystem.init(this.supabase, this.merchantId, this.localServerURL);
                loyaltySystem.renderMiniWidget('loyaltyMiniContainer');
            } catch (error) {
                console.warn('[Loyalty] Optional initialization failed; menu remains available.', error);
            }
        }

        // Repaint once optional configuration is ready (modifier/promotion badges).
        this.renderCategories();
        this.renderMenuItems();
        this.updateCartUI();

        // Start status polling
        this.startStatusPolling();
        this.setupAccessibilityHandlers();

        // Initialize reorder history (after menu is loaded)
        this.initReorderHistory();

        // Initialize push notifications
        this._initPushNotifications();

        // Initialize Theme from localStorage (Default: Light Mode)
        const savedTheme = localStorage.getItem("theme") || "light";
        const body = document.body;
        const iconEl = document.querySelector("#themeToggleBtn .theme-toggle-icon");

        if (savedTheme === "dark") {
            body.classList.add("dark-theme");
            if (iconEl) {
                iconEl.classList.remove("icon-moon");
                iconEl.classList.add("icon-sun");
            }
        } else {
            body.classList.remove("dark-theme");
            if (iconEl) {
                iconEl.classList.remove("icon-sun");
                iconEl.classList.add("icon-moon");
            }
        }

        // Initialize language switcher
        const savedLang = localStorage.getItem("lang") || "th";
        this.switchLanguage(savedLang);

        // Close lang dropdown on outside click
        document.addEventListener("click", (e) => {
            const dd = document.getElementById("langDropdown");
            if (dd && !dd.contains(e.target)) {
                dd.classList.remove("open");
            }
        });

        // Keep the document height stable while customers scroll. Collapsing the
        // promo banner on scroll causes iOS Safari rubber-band events to expand it
        // again at the bottom, producing a visible flash and a large layout jump.
        document.body.classList.remove("header-scrolled-up");
        this.initMotionSystem();

        // Developer auto-onboard check for headless testing
        this.autoOnboardIfRequested();
    }

    async exchangeCustomerSession(sessionToken) {
        if (!sessionToken || !this.tableNumber || !this.supabaseUrl || !this.supabaseKey) return false;
        try {
            const base = (this.edgeFunctionUrl || `${this.supabaseUrl.replace(/\/$/, '')}/functions/v1`).replace(/\/$/, '');
            const response = await fetch(`${base}/issue-customer-session-token`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'apikey': this.supabaseKey,
                    'Authorization': `Bearer ${this.supabaseKey}`
                },
                body: JSON.stringify({ table_number: String(this.tableNumber), session_token: sessionToken })
            });
            const body = await response.json().catch(() => ({}));
            if (!response.ok || !body.access_token || !body.branch_id) {
                throw Object.assign(new Error(body.title || 'Customer session rejected'), { code: body.code, traceId: body.traceId });
            }
            this.merchantToken = body.access_token;
            this.merchantId = body.merchant_id;
            this.branchId = body.branch_id;
            this.tableSessionId = body.table_session_id;
            this.tableNumber = String(body.table_number);
            this.sessionToken = sessionToken;
            safeStorageRemove(sessionStorage, 'alphapos_customer_jwt');
            safeStorageSet(localStorage, 'active_merchant_id', body.merchant_id);
            safeStorageSet(localStorage, `sessionToken_T${this.tableNumber}`, sessionToken);
            if (this.customerTokenRefreshTimer) clearTimeout(this.customerTokenRefreshTimer);
            const refreshInMs = Math.max(60_000, (Number(body.expires_in || 1800) - 120) * 1000);
            this.customerTokenRefreshTimer = setTimeout(() => {
                // Reload is deliberate: it atomically replaces REST and Realtime
                // clients with a new signed session while preserving the cart.
                window.location.reload();
            }, refreshInMs);
            return true;
        } catch (error) {
            console.error(JSON.stringify({ level: 'error', event: 'customer_session.exchange_failed', code: error.code || 'NETWORK_ERROR', traceId: error.traceId || null }));
            safeStorageRemove(sessionStorage, 'alphapos_customer_jwt');
            return false;
        }
    }

    async exchangePermanentQR(permanentKey) {
        if (!permanentKey || !this.tableNumber || !this.isMerchantIdValid() || !this.supabaseUrl || !this.supabaseKey) return false;
        const base = (this.edgeFunctionUrl || `${this.supabaseUrl.replace(/\/$/, '')}/functions/v1`).replace(/\/$/, '');
        let approvalRequestId = null;
        let expiresAt = Date.now() + 5 * 60 * 1000;

        try {
            while (Date.now() < expiresAt) {
                const response = await fetch(`${base}/issue-customer-session-token`, {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                        'apikey': this.supabaseKey,
                        'Authorization': `Bearer ${this.supabaseKey}`
                    },
                    body: JSON.stringify({
                        merchant_id: this.merchantId,
                        table_number: String(this.tableNumber),
                        permanent_key: permanentKey,
                        ...(approvalRequestId ? { approval_request_id: approvalRequestId } : {})
                    })
                });
                const body = await response.json().catch(() => ({}));
                if (response.ok && body.access_token && body.session_token) {
                    this.merchantToken = body.access_token;
                    this.merchantId = body.merchant_id;
                    this.branchId = body.branch_id;
                    this.tableSessionId = body.table_session_id;
                    this.tableNumber = String(body.table_number);
                    this.sessionToken = body.session_token;
                    safeStorageSet(localStorage, 'active_merchant_id', body.merchant_id);
                    safeStorageSet(localStorage, `sessionToken_T${this.tableNumber}`, body.session_token);
                    this.hideBlockingState();
                    this.cleanUrlParams();
                    return true;
                }
                if (response.status === 202) {
                    this.showBlockingState(
                        'staffApprovalWaitingTitle', 'staffApprovalWaitingDesc', 'staffApprovalWaitingFooter'
                    );
                }
                // A transient Edge Function/PostgREST failure must not turn a
                // valid pending approval into an "invalid QR" screen. Keep the
                // current request id and retry until its normal expiry time.
                if (response.status >= 500 && approvalRequestId) {
                    console.warn(JSON.stringify({
                        level: 'warn', event: 'permanent_qr.poll_retry',
                        code: body.code || 'SERVER_ERROR', traceId: body.traceId || null
                    }));
                    await new Promise(resolve => setTimeout(resolve, 2500));
                    continue;
                }
                if (response.status !== 202 || !body.approval_request_id) {
                    throw Object.assign(new Error(body.title || 'Permanent QR rejected'), { code: body.code, traceId: body.traceId });
                }
                approvalRequestId = body.approval_request_id;
                if (body.expires_at) expiresAt = new Date(body.expires_at).getTime();
                await new Promise(resolve => setTimeout(resolve, 2500));
            }
            throw Object.assign(new Error('Staff approval timed out'), { code: 'STAFF_APPROVAL_TIMEOUT' });
        } catch (error) {
            console.error(JSON.stringify({ level: 'error', event: 'permanent_qr.exchange_failed', code: error.code || 'NETWORK_ERROR', traceId: error.traceId || null }));
            return false;
        }
    }

    startSyncHealthPolling() {
        this.refreshSyncHealth();
        if (this.syncHealthInterval) clearInterval(this.syncHealthInterval);
        this.syncHealthInterval = setInterval(() => this.refreshSyncHealth(), 30000);
    }

    async refreshSyncHealth() {
        const panel = document.getElementById("syncHealthPanel");
        const title = document.getElementById("syncHealthTitle");
        const meta = document.getElementById("syncHealthMeta");
        const retryBtn = document.getElementById("syncRetryBtn");
        if (!panel || !title || !meta || !retryBtn) return;

        if (!this.isLocalServerAvailable) {
            panel.classList.add("hide");
            return;
        }

        try {
            const res = await fetch(`${this.localServerURL}/v1/sync/status`);
            if (!res.ok) throw new Error(`HTTP ${res.status}`);
            const status = await res.json();
            const localPending = Number(status.pendingCount || 0);
            const hubPending = Number(status.hub?.pending_count || 0);
            const hubFailed = Number(status.hub?.failed_count || status.failed_count || 0);
            const pending = Number(status.pending_count || (localPending + hubPending));
            const maxAttempts = Number(status.maxAttempts || 0);

            panel.classList.toggle("pending", pending > 0 || hubFailed > 0);
            panel.classList.toggle("synced", pending === 0 && hubFailed === 0);
            panel.classList.toggle("has-issue", pending > 0 || hubFailed > 0);
            title.textContent = pending > 0 || hubFailed > 0 ? "Pending sync" : "Synced";
            meta.textContent = pending > 0 || hubFailed > 0
                ? `${pending} pending${hubFailed ? ` · ${hubFailed} failed` : ""}${maxAttempts > 0 ? ` · ${maxAttempts} attempts` : ""}`
                : "0 pending";
            retryBtn.classList.toggle("hide", pending === 0);
        } catch (error) {
            panel.classList.remove("synced");
            panel.classList.add("pending");
            panel.classList.add("has-issue");
            title.textContent = "Sync status unavailable";
            meta.textContent = "Check server";
            retryBtn.classList.add("hide");
        }
    }

    setupAccessibilityHandlers() {
        document.addEventListener("keydown", (event) => {
            if (event.key === "Escape") {
                if (document.getElementById("productDetailModal")?.classList.contains("active")) {
                    this.closeProductDetailModal();
                    return;
                }
                if (document.getElementById("cartDrawerOverlay")?.classList.contains("show")) {
                    this.toggleCartDrawer(false);
                    return;
                }
            }

            if (event.key !== "Tab" || !this._activeModal) return;

            const focusable = Array.from(this._activeModal.querySelectorAll(
                'a[href], button:not([disabled]), textarea:not([disabled]), input:not([disabled]), select:not([disabled]), [tabindex]:not([tabindex="-1"])'
            )).filter(el => el.offsetParent !== null);

            if (focusable.length === 0) return;

            const first = focusable[0];
            const last = focusable[focusable.length - 1];

            if (event.shiftKey && document.activeElement === first) {
                event.preventDefault();
                last.focus();
            } else if (!event.shiftKey && document.activeElement === last) {
                event.preventDefault();
                first.focus();
            }
        });
    }

    setActiveModal(modal) {
        this._activeModal = modal || null;
        if (modal) {
            this._lastFocusedElement = document.activeElement;
            const firstFocusable = modal.querySelector('button:not([disabled]), textarea:not([disabled]), input:not([disabled]), [tabindex]:not([tabindex="-1"])');
            setTimeout(() => firstFocusable?.focus(), 40);
        } else if (this._lastFocusedElement && typeof this._lastFocusedElement.focus === "function") {
            this._lastFocusedElement.focus();
            this._lastFocusedElement = null;
        }
    }

    async retrySyncQueue() {
        const retryBtn = document.getElementById("syncRetryBtn");
        if (retryBtn) retryBtn.disabled = true;
        if (!this.isLocalServerAvailable) return;

        try {
            let headers = {};
            const configuredToken = window.ALPHAPOS_CONFIG?.apiAuthToken || "";
            const storedToken = sessionStorage.getItem("alphapos_api_token") || "";
            let token = configuredToken || storedToken;
            if (!token && location.hostname !== "localhost" && location.hostname !== "127.0.0.1") {
                token = window.prompt("API token") || "";
                if (token) sessionStorage.setItem("alphapos_api_token", token);
            }
            if (token) headers.Authorization = `Bearer ${token}`;

            const res = await fetch(`${this.localServerURL}/v1/sync/retry`, { method: "POST", headers });
            if (!res.ok) throw new Error(`HTTP ${res.status}`);
            await this.refreshSyncHealth();
            this._showToast("Sync retry complete", 2500);
        } catch (error) {
            console.error("Sync retry failed:", error);
            this._showToast("Sync retry failed", 3500);
        } finally {
            if (retryBtn) retryBtn.disabled = false;
        }
    }

    // ─────────────────────────────────────────────────────────────
    // Scroll-Hide Header
    // Hide promo banner when user scrolls down > threshold.
    // Restore when scrolled back near top.
    // ─────────────────────────────────────────────────────────────
    _initScrollHideHeader() {
        document.body.classList.remove("header-scrolled-up");
    }

    initMotionSystem() {
        if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
            document.documentElement.classList.add('reduce-motion');
            return;
        }
        if (!this._motionObserver) {
            this._motionObserver = new IntersectionObserver((entries) => {
                entries.forEach(entry => {
                    if (!entry.isIntersecting) return;
                    entry.target.classList.add('motion-visible');
                    this._motionObserver.unobserve(entry.target);
                });
            }, { rootMargin: '0px 0px -8% 0px', threshold: 0.08 });
        }
        this.refreshMotionTargets();
        requestAnimationFrame(() => document.body.classList.add('motion-ready'));
    }

    refreshMotionTargets() {
        if (!this._motionObserver) return;
        const targets = document.querySelectorAll(
            '.featured-item-card:not([data-motion]), .list-item-card:not([data-motion]), ' +
            '.category-tab:not([data-motion]), .status-item-card:not([data-motion]), ' +
            '.service-capsule:not([data-motion])'
        );
        targets.forEach((element, index) => {
            element.dataset.motion = 'reveal';
            element.style.setProperty('--motion-index', String(index % 8));
            this._motionObserver.observe(element);
        });
    }

    async autoOnboardIfRequested() {
        const urlParams = new URLSearchParams(window.location.search);
        if (urlParams.get('autoOnboard') !== 'true') return;
        console.log("[AutoOnboard] Started automatic onboarding...");

        let attempts = 0;
        while (this.currentOnboardingStep !== 2 && attempts < 100) {
            await new Promise(r => setTimeout(r, 100));
            attempts++;
        }

        if (this.currentOnboardingStep === 2) {
            console.log("[AutoOnboard] Guest-count step is ready; selecting 4 guests...");
            this.setGuestCount(4);
            await new Promise(r => setTimeout(r, 400));
            const btn2 = document.getElementById("startOrderBtn");
            if (btn2) btn2.click();
        } else {
            console.log("[AutoOnboard] Guest-count step was not reached.");
            return;
        }

        await new Promise(r => setTimeout(r, 1200));

        console.log("[AutoOnboard] Onboarding completed via new flow.");

        // Check if automated ordering/detail test is requested
        const autoOrder = urlParams.get('autoOrder') === 'true';
        const autoOpenDetail = urlParams.get('autoOpenDetail') === 'true';

        if (autoOrder) {
            // Wait for onboarding overlay to dismiss and menu to render
            await new Promise(r => setTimeout(r, 2500));

            // Add first loaded item to cart
            const item = this.menuItems[0];
            console.log("[AutoOnboard] Adding first item to cart:", item ? item.id : "none");
            if (item) {
                // Add to cart manually to trigger full cart logic
                const count = this.cart[item.id] || 0;
                this.cart[item.id] = count + 1;
                this.updateCartUI();
                this.jiggleCartNotification();
            }

            // Wait for cart jiggle animation
            await new Promise(r => setTimeout(r, 800));

            // Open cart drawer
            console.log("[AutoOnboard] Opening cart drawer...");
            this.toggleCartDrawer(true);

            // Wait for drawer slide-up animation
            await new Promise(r => setTimeout(r, 800));

            // Submit order
            console.log("[AutoOnboard] Submitting order to local server...");
            await this.submitOrder();

            // Wait for toast notification and then switch to order status view
            await new Promise(r => setTimeout(r, 2000));
            console.log("[AutoOnboard] Switching to status view...");
            this.switchView("status");
        } else if (autoOpenDetail) {
            // Wait for onboarding overlay to dismiss and menu to render
            await new Promise(r => setTimeout(r, 2500));
            const firstId = this.menuItems[0] ? this.menuItems[0].id : "isan1";
            console.log("[AutoOnboard] Automatically opening product detail modal for " + firstId + "...");
            this.openProductDetailModal(firstId);
        }
    }

    async fetchMerchantSettings() {
        const branchCode = this.branchCode;
        const pickMerchant = (res) => {
            if (Array.isArray(res)) {
                return res.find(m =>
                    (!this.merchantId || m.id === this.merchantId) &&
                    (!branchCode || m.branch_code === branchCode || m.branchCode === branchCode)
                ) || res.find(m => !this.merchantId || m.id === this.merchantId) || res[0];
            }
            return res;
        };
        const localUrl = `${this.localServerURL}/v1/merchants`;

        if (this.isLocalServerAvailable && !window.ALPHAPOS_CONFIG?.isProduction) {
            try {
                const res = await fetch(localUrl, { headers: { 'Content-Type': 'application/json' } });
                if (res.ok) {
                    const localSettings = pickMerchant(await res.json());
                    if (localSettings) return localSettings;
                }
            } catch (error) {
                console.warn("Local merchant settings unavailable, trying Supabase:", error);
            }
        }

        if (!this.supabase) return null;

        try {
            let query = this.supabase
                .from('merchants')
                .select('id, name, logo_url, web_cover_url, web_cover_media_type, branch_code, is_table_system_enabled, is_web_ordering_enabled, tax_rate, tax_type, service_charge_rate');

            if (this.merchantId) query = query.eq('id', this.merchantId);
            if (branchCode) query = query.eq('branch_code', branchCode);

            const settingsPromise = query.limit(1).maybeSingle();
            const timeoutPromise = new Promise((_, reject) => {
                setTimeout(() => reject(new Error("Merchant settings lookup timed out")), 5000);
            });
            const { data, error } = await Promise.race([settingsPromise, timeoutPromise]);
            if (error) throw error;
            return pickMerchant(data);
        } catch (error) {
            console.warn("Merchant settings unavailable; using enabled defaults:", error);
            return null;
        }
    }

    showOnboardingPanel(panelId) {
        const wizard = document.getElementById("onboardingWizard");
        if (!wizard) return;
        wizard.classList.add("active");
        ["onboardingLoading", "onboardingStep2", "onboardingStep3"].forEach(id => {
            const panel = document.getElementById(id);
            if (panel) panel.classList.toggle("active", id === panelId);
        });
    }

    applyMerchantBranding(settings = {}) {
        const rawName = settings.name || settings.store_name || settings.storeName || '';
        const name = String(rawName).trim() || 'Restaurant';
        const logoUrl = settings.logo_url || settings.logoUrl || '';
        const initial = Array.from(name)[0]?.toUpperCase() || 'R';
        this.merchantDisplayName = name;

        const brandName = document.getElementById('merchantBrandName');
        if (brandName) brandName.textContent = name;
        const welcome = document.getElementById('merchantWelcomeTitle');
        if (welcome) welcome.textContent = `${this.translate('welcomeTo', 'ยินดีต้อนรับสู่')} ${name}`;
        const loadingTitle = document.getElementById('loadingBrandTitle');
        if (loadingTitle) loadingTitle.textContent = name;
        document.title = `${name} | ${this.translate('orderOnlineTitle', 'สั่งอาหารออนไลน์')}`;

        const logo = document.getElementById('merchantLogo');
        if (logo) {
            logo.replaceChildren();
            if (logoUrl && /^(https?:|data:image\/)/i.test(String(logoUrl))) {
                const img = document.createElement('img');
                img.className = 'merchant-logo-image';
                img.alt = `${name} logo`;
                img.src = logoUrl;
                img.onerror = () => {
                    logo.replaceChildren();
                    const fallback = document.createElement('span');
                    fallback.className = 'header-logo-inner';
                    fallback.textContent = initial;
                    logo.appendChild(fallback);
                };
                logo.appendChild(img);
            } else {
                const fallback = document.createElement('span');
                fallback.className = 'header-logo-inner';
                fallback.textContent = initial;
                logo.appendChild(fallback);
            }
        }
    }

    showAppLoading(message = "") {
        this.showOnboardingPanel("onboardingLoading");
        const titleEl = document.getElementById("loadingBrandTitle");
        const descEl = document.getElementById("loadingBrandDesc");
        if (titleEl) titleEl.textContent = "AlphaPos";
        if (descEl) descEl.textContent = message || this.translate("preparingTable", "Preparing your table...");
    }

    showBlockingState(titleKey, descKey, footerKey, options = {}) {
        // Hide both main app content and onboarding wizard via class (not inline display)
        const appContainer = document.querySelector(".app-container");
        const onboardingWizard = document.getElementById("onboardingWizard");
        if (appContainer) {
            appContainer.classList.add("is-blocked");
            appContainer.style.display = "none";
        }
        if (onboardingWizard) {
            onboardingWizard.classList.add("is-blocked");
            onboardingWizard.style.display = "none";
        }

        // Display the safe full-screen blocking overlay
        const overlay = document.getElementById("blockingOverlay");
        if (overlay) {
            overlay.classList.add("active");
            
            const titleEl = document.getElementById("blockingTitle");
            const descEl = document.getElementById("blockingDesc");
            const footerEl = document.getElementById("blockingFooterText");
            const retryBtn = document.getElementById("blockingRetryBtn");

            if (titleEl) {
                titleEl.textContent = this.translate(titleKey, titleKey);
            }
            if (descEl) {
                descEl.textContent = this.translate(descKey, descKey);
            }
            if (footerEl) {
                footerEl.textContent = footerKey
                    ? this.translate(footerKey, footerKey)
                    : "";
            }
            if (retryBtn) {
                retryBtn.classList.toggle("hide", !options.showRetry);
            }
        }
    }

    hideBlockingState() {
        const appContainer = document.querySelector('.app-container');
        const onboardingWizard = document.getElementById('onboardingWizard');
        const overlay = document.getElementById('blockingOverlay');
        if (appContainer) {
            appContainer.classList.remove('is-blocked');
            appContainer.style.display = '';
        }
        if (onboardingWizard) {
            onboardingWizard.classList.remove('is-blocked');
            onboardingWizard.style.display = '';
        }
        overlay?.classList.remove('active');
    }

    /**
     * True when runtime config has usable Supabase credentials.
     */
    hasValidRuntimeConfig(cfg = window.ALPHAPOS_CONFIG) {
        if (!cfg || typeof cfg !== "object") return false;
        const url = cfg.supabaseUrl || "";
        const key = cfg.supabaseKey || "";
        return !!(
            url &&
            key &&
            !url.includes("your-supabase-project") &&
            !key.includes("your-anon-key")
        );
    }

    applyRuntimeConfig(cfg = window.ALPHAPOS_CONFIG || {}) {
        if (!cfg || typeof cfg !== "object") return;
        if (cfg.supabaseUrl) this.supabaseUrl = cfg.supabaseUrl;
        if (cfg.supabaseRealtimeUrl) this.supabaseRealtimeUrl = cfg.supabaseRealtimeUrl;
        else if (cfg.supabaseUrl) this.supabaseRealtimeUrl = cfg.supabaseUrl;
        if (cfg.supabaseKey) this.supabaseKey = cfg.supabaseKey;
        if (cfg.edgeFunctionUrl) this.edgeFunctionUrl = cfg.edgeFunctionUrl;
        if (cfg.merchantId) this.merchantId = cfg.merchantId || this.merchantId;
        if (cfg.localServerURL) this.localServerURL = cfg.localServerURL;
        if (cfg.branchCode) this.branchCode = cfg.branchCode || this.branchCode;
    }

    isMerchantIdValid(id = this.merchantId) {
        return !!(id && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id));
    }

    /**
     * Resolve menu image URLs from absolute, relative, data:, or storage paths.
     */
    resolveMenuImageUrl(imageUrl) {
        const placeholder = "data:image/svg+xml," + encodeURIComponent(
            '<svg xmlns="http://www.w3.org/2000/svg" width="600" height="400" viewBox="0 0 600 400">' +
            '<rect fill="#e8eeff" width="600" height="400"/>' +
            '<text x="300" y="210" text-anchor="middle" fill="#6b7294" font-family="sans-serif" font-size="28">AlphaPos</text>' +
            '</svg>'
        );
        if (!imageUrl) return placeholder;
        const value = String(imageUrl).trim();
        if (!value) return placeholder;
        if (
            value.startsWith('http://') ||
            value.startsWith('https://') ||
            value.startsWith('data:') ||
            value.startsWith('blob:')
        ) {
            return value;
        }
        // Absolute path on same origin
        if (value.startsWith('/')) {
            return value;
        }
        // Supabase storage-style relative path
        const base = (this.supabaseUrl || '').replace(/\/$/, '');
        if (base && (value.startsWith('storage/') || value.includes('/object/'))) {
            return `${base}/${value.replace(/^\//, '')}`;
        }
        if (base) {
            return `${base}/storage/v1/object/public/${value.replace(/^\//, '')}`;
        }
        return placeholder;
    }

    finishOnboardingLoading(message, delay = 650) {
        this.showOnboardingPanel("onboardingStep3");
        const loadingStatus = document.getElementById("loadingStatusText");
        const progressFill = document.getElementById("setupProgressFill");
        if (loadingStatus) loadingStatus.textContent = message;
        if (progressFill) {
            progressFill.style.width = "0";
            setTimeout(() => { progressFill.style.width = "100%"; }, 50);
        }

        setTimeout(() => {
            const wizard = document.getElementById("onboardingWizard");
            if (!wizard) return;
            wizard.style.opacity = "0";
            setTimeout(() => {
                wizard.classList.remove("active");
                wizard.style.opacity = "";
                this.animateMenuEntrance();
            }, 350);
        }, delay);
    }

    async getActiveSessionForTable() {
        let success = false;
        let session = null;

        if (this.supabase) {
            try {
                let query = this.supabase
                    .from('table_sessions')
                    .select('*')
                    .eq('table_number', this.tableNumber)
                    .eq('is_active', 1);

                if (this.merchantId) query = query.eq('merchant_id', this.merchantId);

                const sessionPromise = query
                    .order('created_at', { ascending: false })
                    .limit(1)
                    .maybeSingle();
                const timeoutPromise = new Promise((_, reject) => {
                    setTimeout(() => reject(new Error("Active session lookup timed out")), 5000);
                });
                const { data, error } = await Promise.race([sessionPromise, timeoutPromise]);

                if (error) throw error;
                if (data) {
                    session = {
                        sessionToken: data.session_token,
                        guestCount: data.guest_count || 1,
                        createdAt: data.created_at || data.started_at
                    };
                }
                success = true;
            } catch (error) {
                console.error("Failed to read active Supabase session, trying local fallback:", error);
            }
        }

        if (!success && this.isLocalServerAvailable) {
            try {
                const res = await fetch(`${this.localServerURL}/v1/sessions`);
                if (res.ok) {
                    const sessions = await res.json();
                    session = sessions.find(s => String(s.tableNumber) === String(this.tableNumber)) || null;
                    success = true;
                }
            } catch (localErr) {
                console.error("Failed to read active local session:", localErr);
            }
        }

        return session;
    }

    async checkOrOpenSession() {
        const urlParams = new URLSearchParams(window.location.search);
        const tableParam = urlParams.get('table') || urlParams.get('t') || this.tableNumber;
        this.showAppLoading(this.translate("checkingTable", "Checking table availability..."));

        // Check if Table System or Web Ordering is enabled for this merchant
        const merchantSettings = await this.fetchMerchantSettings();
        this.merchantSettings = merchantSettings || {};
        this.applyMerchantBranding(this.merchantSettings);
        if (merchantSettings) {
            if (merchantSettings.is_table_system_enabled === false) {
                this.showBlockingState(
                    "tableSystemDisabledTitle",
                    "tableSystemDisabledDesc",
                    "pleaseOrderStaff"
                );
                return false;
            }
            if (merchantSettings.is_web_ordering_enabled === false) {
                this.showBlockingState(
                    "webOrderingDisabledTitle",
                    "webOrderingDisabledDesc",
                    "pleaseOrderStaff"
                );
                return false;
            }
        }

        // Block access if table parameter is missing (and nothing recovered from session)
        if (!tableParam || String(tableParam).trim() === '' || String(tableParam).trim() === '--') {
            this.showBlockingState(
                "tableParamMissingTitle",
                "tableParamMissingDesc",
                "pleaseOrderStaff"
            );
            return false;
        }

        // In production identity must come from the signed customer-session JWT.
        const isProd = !!(window.ALPHAPOS_CONFIG && window.ALPHAPOS_CONFIG.isProduction);
        if (isProd && (!this.merchantToken || !this.isMerchantIdValid() || !this.branchId || !this.tableSessionId)) {
            this.showBlockingState(
                "merchantParamMissingTitle",
                "merchantParamMissingDesc",
                "pleaseOrderStaff"
            );
            return false;
        }

        // Ensure tableNumber stays in sync with the resolved param
        this.tableNumber = String(tableParam).trim();
        this._updateTableBadge();

        const welcomeEl = document.getElementById("welcomeTableNum");
        const labelEl = document.getElementById("tableLabelNum");
        if (welcomeEl) welcomeEl.innerText = this.tableNumber;
        if (labelEl) labelEl.innerText = this.tableNumber;

        // Verify token (either URL parameter or localStorage)
        const cachedToken = localStorage.getItem(`sessionToken_T${this.tableNumber}`);
        // A freshly scanned QR always wins over a stale cached token.
        const tokenToVerify = this.sessionToken || cachedToken;

        if (tokenToVerify) {
            // Verify if session token is still active on the server
            const isActive = await this.verifySessionWithServer(tokenToVerify);
            if (isActive) {
                this.sessionToken = tokenToVerify;
                localStorage.setItem(`sessionToken_T${this.tableNumber}`, tokenToVerify);
                this.finishOnboardingLoading(this.translate("resumingSession", "Resuming your table session..."));
                this.cleanUrlParams(); // Clean URL params to prevent re-onboarding on reload
                console.log("Resumed session verified by server:", this.sessionToken);
                return true;
            } else {
                // Clear invalid/expired session
                this.sessionToken = null;
                localStorage.removeItem(`sessionToken_T${this.tableNumber}`);
                
                // Clear cart from storage as the session is no longer valid
                this.cart = {};
                this.saveCartToStorage();

                // If URL had a token (fresh QR scan) but it's invalid, show QR error
                if (this.sessionToken === null && urlParams.get('token')) {
                    this.showQrInvalidError();
                    return false;
                }
            }
        }

        // If URL has a token but we never entered the verify block (no cached token either), validate it
        if (!this.sessionToken && urlParams.get('token')) {
            const urlToken = urlParams.get('token');
            const isValid = await this.verifySessionWithServer(urlToken);
            if (!isValid) {
                this.showQrInvalidError();
                return false;
            } else {
                this.sessionToken = urlToken;
                localStorage.setItem(`sessionToken_T${this.tableNumber}`, urlToken);
                this.finishOnboardingLoading(this.translate("resumingSession", "Resuming your table session..."));
                this.cleanUrlParams(); // Clean URL params to prevent re-onboarding on reload
                return true;
            }
        }

        if (isProd) {
            this.showQrInvalidError();
            return false;
        }

        const activeSession = await this.getActiveSessionForTable();
        if (activeSession && activeSession.sessionToken) {
            this.sessionToken = activeSession.sessionToken;
            this.selectedGuestCount = activeSession.guestCount || this.selectedGuestCount;
            localStorage.setItem(`sessionToken_T${this.tableNumber}`, this.sessionToken);
            this.finishOnboardingLoading(this.translate("resumingSession", "Resuming your table session..."));
            this.cleanUrlParams(); // Clean URL params to prevent re-onboarding on reload
            console.log("Active table session resumed without asking guest count:", this.sessionToken);
            return true;
        }

        // No active session — ask guest count, then open a table session (no GPS/Wi-Fi gate).
        this.currentOnboardingStep = 2;
        this.showOnboardingPanel("onboardingStep2");
        this.renderInteractiveSeats();
        return true;
    }

    cleanUrlParams() {
        try {
            const url = new URL(window.location.href);
            let replaced = false;
            if (url.searchParams.has('token')) {
                url.searchParams.delete('token');
                replaced = true;
            }
            if (url.searchParams.has('jwt')) {
                url.searchParams.delete('jwt');
                replaced = true;
            }
            if (url.searchParams.has('key')) {
                url.searchParams.delete('key');
                replaced = true;
            }
            if (replaced) {
                window.history.replaceState({}, document.title, url.pathname + url.search);
            }
        } catch (e) {
            console.error("Failed to clean URL parameters:", e);
        }
    }

    async verifySessionWithServer(token) {
        let success = false;
        let isActive = false;

        if (this.supabase) {
            try {
                const { data, error } = await this.supabase
                    .from('table_sessions')
                    .select('id, merchant_id, branch_id, table_number, session_token, is_active, ended_at')
                    .eq('id', this.tableSessionId)
                    .eq('merchant_id', this.merchantId)
                    .eq('branch_id', this.branchId)
                    .eq('table_number', this.tableNumber)
                    .eq('session_token', token)
                    .eq('is_active', 1)
                    .is('ended_at', null)
                    .maybeSingle();

                if (!error && data) {
                    isActive = true;
                    success = true;
                }
            } catch (e) {
                console.error("Failed to verify session with Supabase, trying local server fallback:", e);
            }
        }

        if (!success && this.isLocalServerAvailable && !window.ALPHAPOS_CONFIG?.isProduction) {
            try {
                const res = await fetch(`${this.localServerURL}/v1/sessions`);
                if (res.ok) {
                    const sessions = await res.json();
                    const matched = sessions.find(s => String(s.tableNumber) === String(this.tableNumber) && s.sessionToken === token);
                    isActive = !!matched;
                    console.log("[DEBUG] verifySessionWithServer matched:", isActive, "tableNumber:", this.tableNumber, "token:", token, "matched_session:", matched);
                    success = true;
                }
            } catch (localErr) {
                console.error("Failed to verify session with local server:", localErr);
            }
        }

        return isActive;
    }

    /**
     * Show QR code invalid/expired error to the customer
     * Displays bilingual error message (Thai + English)
     */
    showQrInvalidError() {
        console.warn("[QR Validation] Token mismatch or table not occupied. Access denied.");
        this.showBlockingState(
            "qrInvalidTitle",
            "qrInvalidMessage",
            "pleaseOrderStaff"
        );
    }

    renderInteractiveSeats() {
        const container = document.getElementById("interactiveSeatsContainer");
        const textEl = document.getElementById("tableLabelNum");
        if (!container) return;

        container.innerHTML = "";
        if (textEl) textEl.innerText = this.tableNumber || "--";

        const raw = this.selectedGuestCount === '8+' ? 8 : parseInt(this.selectedGuestCount, 10);
        const count = Number.isFinite(raw) && raw > 0 ? raw : 2;

        for (let i = 0; i < count; i++) {
            const angle = (i * 360 / count) * Math.PI / 180;
            const radius = 52;
            const x = Math.round(50 + radius * Math.cos(angle - Math.PI/2)) + "%";
            const y = Math.round(50 + radius * Math.sin(angle - Math.PI/2)) + "%";

            const seat = document.createElement("div");
            seat.className = "seat";
            seat.style.left = x;
            seat.style.top = y;
            seat.style.animationDelay = `${i * 0.08}s`;
            seat.innerHTML = '<span class="app-icon icon-utensils" aria-hidden="true"></span>';
            container.appendChild(seat);
        }
    }

    setGuestCount(count) {
        // Persist numeric guest count (handle "8+" special case)
        this.selectedGuestCount = count === '8+' ? 8 : parseInt(count, 10);
        if (!Number.isFinite(this.selectedGuestCount) || this.selectedGuestCount < 1) {
            this.selectedGuestCount = 2;
        }

        try {
            sessionStorage.setItem('alphapos_guest_count', String(this.selectedGuestCount));
            sessionStorage.setItem('alphapos_guest_count_timestamp', String(Date.now()));
        } catch (_) { /* ignore */ }

        const pills = document.querySelectorAll(".guest-pill");
        pills.forEach(pill => {
            const pillVal = pill.innerText.trim();
            const matches = pillVal === String(count)
                || (count === '8+' && pillVal === '8+')
                || (String(this.selectedGuestCount) === pillVal)
                || (this.selectedGuestCount >= 8 && pillVal === '8+');
            pill.classList.toggle("active", matches);
        });

        console.log(`[Guest Count] Set to ${this.selectedGuestCount} persons`);
        this.renderInteractiveSeats();
    }

    async confirmGuestCount() {
        const btn = document.getElementById("startOrderBtn");
        if (!btn) return;
        btn.disabled = true;
        const btnLabel = btn.querySelector("span");
        if (btnLabel) btnLabel.innerText = "Starting session...";

        const generateUUID = () => {
            if (typeof crypto !== 'undefined' && crypto.randomUUID) {
                return crypto.randomUUID();
            }
            if (typeof crypto !== 'undefined' && crypto.getRandomValues) {
                return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {
                    const r = crypto.getRandomValues(new Uint8Array(1))[0] % 16;
                    const v = c === 'x' ? r : (r & 0x3 | 0x8);
                    return v.toString(16);
                });
            }
            return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {
                const r = Math.random() * 16 | 0;
                const v = c === 'x' ? r : (r & 0x3 | 0x8);
                return v.toString(16);
            });
        };

        try {
            const guestCount = this.selectedGuestCount === '8+' ? 8 : parseInt(this.selectedGuestCount);
            let sessionToken = null;
            let success = false;

            if (this.supabase) {
                try {
                    // Check if there is already an active session for this table
                    const { data: existingSession, error: fetchError } = await this.supabase
                        .from('table_sessions')
                        .select('*')
                        .eq('table_number', this.tableNumber)
                        .eq('is_active', 1)
                        .maybeSingle();

                    if (!fetchError && existingSession) {
                        const sessionDate = new Date(existingSession.created_at);
                        const today = new Date();
                        const isToday = sessionDate.getDate() === today.getDate() &&
                                        sessionDate.getMonth() === today.getMonth() &&
                                        sessionDate.getFullYear() === today.getFullYear();

                        if (isToday) {
                            console.log("Reusing existing active session for today:", existingSession.session_token);
                            sessionToken = existingSession.session_token;
                            success = true;
                        } else {
                            console.log("Stale active session from yesterday found. Closing it...");
                            await this.supabase
                                .from('table_sessions')
                                .update({ is_active: 0, ended_at: new Date().toISOString() })
                                .eq('id', existingSession.id);
                        }
                    }

                    if (!success) {
                        const sessionId = generateUUID();
                        sessionToken = "session-" + sessionId.replace(/-/g, '').substring(0, 13);

                        const { error } = await this.supabase
                            .from('table_sessions')
                            .insert([{
                                id: sessionId,
                                table_number: this.tableNumber,
                                session_token: sessionToken,
                                is_active: 1,
                                guest_count: guestCount,
                                created_at: new Date().toISOString(),
                                merchant_id: this.merchantId
                            }]);

                        if (error) {
                            // If a conflict still occurs (e.g. race condition), try fetching the active session one more time
                            if (error.code === '23505' || String(error.message).includes('duplicate') || String(error.code) === '409') {
                                const { data: retrySession, error: retryError } = await this.supabase
                                    .from('table_sessions')
                                    .select('session_token')
                                    .eq('table_number', this.tableNumber)
                                    .eq('is_active', 1)
                                    .maybeSingle();

                                if (!retryError && retrySession) {
                                    sessionToken = retrySession.session_token;
                                    success = true;
                                    console.log("Recovered from insert conflict, using active session:", sessionToken);
                                } else {
                                    throw error;
                                }
                            } else {
                                throw error;
                            }
                        } else {
                            success = true;
                        }
                    }
                } catch (supabaseError) {
                    console.error("Supabase failed to open session, falling back to local server:", supabaseError);
                }
            }

            if (!success) {
                // Local server fallback
                const res = await fetch(`${this.localServerURL}/v1/sessions/open`, {
                    method: "POST",
                    headers: { "Content-Type": "application/json" },
                    body: JSON.stringify({
                        table_number: this.tableNumber,
                        guest_count: guestCount,
                        merchant_id: this.merchantId,
                        branch_code: this.branchCode
                    })
                });
                if (!res.ok) throw new Error("Local server failed to open session");
                const resData = await res.json();
                sessionToken = resData.session_token;
                success = true;
            }

            this.sessionToken = sessionToken;
            localStorage.setItem(`sessionToken_T${this.tableNumber}`, this.sessionToken);
            this.cleanUrlParams(); // Clean URL params to prevent re-onboarding on reload

            // Show Step 3 (Success Progress Screen)
            document.getElementById("onboardingStep2").classList.remove("active");
            document.getElementById("onboardingStep3").classList.add("active");
            this.currentOnboardingStep = 3;

            const progressFill = document.getElementById("setupProgressFill");
            setTimeout(() => {
                progressFill.style.width = "100%";
            }, 100);

            setTimeout(() => {
                const wizard = document.getElementById("onboardingWizard");
                wizard.style.opacity = "0";
                wizard.style.transform = "translateY(-50px)";
                setTimeout(() => {
                    wizard.classList.remove("active");
                    wizard.style.opacity = "";
                    wizard.style.transform = "";
                    this.animateMenuEntrance();
                }, 500);
            }, 1800);

            console.log("Session established successfully:", this.sessionToken);

        } catch (error) {
            console.error("Failed to open table session:", error);
            this._showToast(this.translate("failedConnectServer"), 5000);
        } finally {
            if (btn) {
                btn.disabled = false;
                const label = btn.querySelector("span");
                if (label) label.innerText = this.translate("startOrdering");
            }
        }
    }

    animateMenuEntrance() {
        const tabs = document.querySelectorAll(".category-tab");
        tabs.forEach((tab, index) => {
            tab.style.opacity = "0";
            tab.style.transform = "translateX(20px)";
            setTimeout(() => {
                tab.style.transition = "all 0.5s cubic-bezier(0.16, 1, 0.3, 1)";
                tab.style.opacity = "1";
                tab.style.transform = "translateX(0)";
            }, index * 60);
        });

        this.renderMenuItems();
    }

    async loadModifiersConfig() {
        let success = false;
        if (this.supabase) {
            try {
                const [groupsRes, modsRes, linksRes] = await Promise.all([
                    this.supabase.from('modifier_groups').select('*').eq('is_deleted', false),
                    this.supabase.from('modifiers').select('*').eq('is_deleted', false)
                        .or(`branch_id.is.null,branch_id.eq.${this.branchId}`),
                    this.supabase.from('menu_item_modifier_groups').select('*').eq('is_deleted', false)
                ]);

                if (groupsRes.error) throw groupsRes.error;
                if (modsRes.error) throw modsRes.error;
                if (linksRes.error) throw linksRes.error;

                this.modifiersConfig = {
                    groups: groupsRes.data,
                    modifiers: modsRes.data,
                    links: linksRes.data
                };
                success = true;
                console.log("[Modifiers] Config loaded from Supabase:", this.modifiersConfig);
            } catch (error) {
                console.error("[Modifiers] Failed to load modifiers from Supabase, trying local fallback:", error);
            }
        }

        if (!success && this.isLocalServerAvailable) {
            try {
                const res = await fetch(`${this.localServerURL}/v1/modifiers-config`);
                if (res.ok) {
                    this.modifiersConfig = await res.json();
                    success = true;
                    console.log("[Modifiers] Config loaded from local server:", this.modifiersConfig);
                }
            } catch (localErr) {
                console.error("[Modifiers] Local server modifiers config failed:", localErr);
            }
        }

        if (!success) {
            this.modifiersConfig = { groups: [], modifiers: [], links: [] };
        }
    }

    hasModifiers(itemId) {
        if (!this.modifiersConfig || !this.modifiersConfig.links) return false;
        return this.modifiersConfig.links.some(l => l.menu_item_id === itemId);
    }

    _normalizeMenuItem(item) {
        return {
            id: item.id,
            name: item.name,
            desc: item.desc || item.description || "",
            price: parseFloat(item.price) || 0,
            category: (item.category || "mains").toString().toLowerCase().trim(),
            emoji: item.emoji || "",
            imgClass: item.imgClass || item.img_class || "img-main",
            imageUrl: item.image_url || item.imageUrl || "",
            videoUrl: item.video_url || item.videoUrl || "",
            isAvailable: item.is_available !== false && item.isAvailable !== false,
            isDeleted: item.is_deleted === true || item.isDeleted === true
        };
    }

    _applyLoadedMenu(rawItems) {
        const mapped = (rawItems || [])
            .map(item => this._normalizeMenuItem(item))
            .filter(item => item.isAvailable && !item.isDeleted && item.name);
        if (mapped.length === 0) return false;
        this.menuItems = mapped;
        this._refreshCategoriesFromMenu();
        return true;
    }

    _refreshCategoriesFromMenu() {
        const categories = new Set(
            (this.menuItems || []).map(i => (i.category || "").toLowerCase())
        );
        const hasDrinks = categories.has("drinks") || categories.has("beverages");
        const hasDesserts = categories.has("desserts") || categories.has("dessert");
        const hasFood = [...categories].some(c =>
            c && c !== "drinks" && c !== "beverages" && c !== "desserts" && c !== "dessert"
        );

        this.categories = [];
        if (hasFood || this.categories.length === 0) {
            this.categories.push({ id: "foods", name: "Foods" });
        }
        if (hasDrinks) this.categories.push({ id: "drinks", name: "Drinks" });
        if (hasDesserts) this.categories.push({ id: "desserts", name: "Desserts" });
        if (this.categories.length === 0) {
            this.categories = [
                { id: "foods", name: "Foods" },
                { id: "drinks", name: "Drinks" },
                { id: "desserts", name: "Desserts" }
            ];
        }
        if (!this.categories.some(c => c.id === this.currentCategory)) {
            this.currentCategory = this.categories[0].id;
        }
    }

    _matchesMenuCategory(item, categoryId) {
        const cat = (item.category || "").toLowerCase();
        if (categoryId === "foods") {
            return cat !== "drinks" && cat !== "beverages" && cat !== "desserts" && cat !== "dessert";
        }
        if (categoryId === "drinks") {
            return cat === "drinks" || cat === "beverages";
        }
        if (categoryId === "desserts") {
            return cat === "desserts" || cat === "dessert";
        }
        return cat === categoryId;
    }

    async loadMenuFromServer() {
        let success = false;
        if (this.supabase) {
            try {
                let query = this.supabase
                    .from('menu_items')
                    .select('*')
                    .eq('is_deleted', false)
                    .eq('is_available', true)
                    .or(`branch_id.is.null,branch_id.eq.${this.branchId}`);

                // Prefer explicit merchant filter when UUID is known (RLS + header can still apply).
                if (this.merchantId && /^[0-9a-f-]{36}$/i.test(this.merchantId)) {
                    query = query.eq('merchant_id', this.merchantId);
                }

                const { data, error } = await query;
                if (error) throw error;
                if (this._applyLoadedMenu(data)) {
                    success = true;
                    console.log(`[Menu] Loaded ${this.menuItems.length} items from Supabase`);
                } else {
                    console.warn("[Menu] Supabase returned no available items for merchant", this.merchantId);
                }
            } catch (error) {
                console.error("Failed to load menu from Supabase, trying local server fallback...", error);
            }
        }

        if (!success && this.isLocalServerAvailable) {
            try {
                const headers = {};
                if (this.merchantId) headers['x-merchant-id'] = this.merchantId;
                const res = await fetch(`${this.localServerURL}/v1/menu`, { headers });
                if (res.ok) {
                    const data = await res.json();
                    if (this._applyLoadedMenu(data)) {
                        success = true;
                        console.log(`[Menu] Loaded ${this.menuItems.length} items from local server fallback.`);
                    }
                }
            } catch (localErr) {
                console.error("Failed to load menu from local server:", localErr);
            }
        }

        this._menuLoadFailed = !success;

        if (!success) {
            // Keep demo defaults only in non-production; otherwise show a clear empty state.
            const isProd = !!(window.ALPHAPOS_CONFIG && window.ALPHAPOS_CONFIG.isProduction);
            if (isProd) {
                this.menuItems = [];
                console.warn("[Menu] No menu available from server; showing empty state.");
            } else if (!this.menuItems || this.menuItems.length === 0) {
                this.menuItems = defaultMenuItems.map(i => this._normalizeMenuItem(i));
                this._menuLoadFailed = false;
            }
            this._refreshCategoriesFromMenu();
        }

        this._updateMenuEmptyState(!this.menuItems || this.menuItems.length === 0);

        // Initialize allergen filter after menu is loaded
        if (this.supabase) {
            try {
                await this.allergenFilter.init(this.supabase, this.merchantId, (key, fallback) => this.translate(key, fallback));
                document.getElementById('dietaryFilterContainer')?.classList.add('hidden');
            } catch (error) {
                console.warn('[Allergens] Optional initialization failed; showing the unfiltered menu.', error);
            }
            try {
                if (!this.feedbackSystem) {
                    this.feedbackSystem = new FeedbackSystem();
                }
                this.feedbackSystem.init(this.supabase, this.merchantId, (key, fallback) => this.translate(key, fallback));
            } catch (error) {
                console.warn('[Feedback] Optional initialization failed.', error);
            }
            try {
                reservationSystem.init(this.supabase, this.merchantId);
            } catch (error) {
                console.warn('[Reservations] Optional initialization failed.', error);
            }
        }
    }

    async retryLoadMenu() {
        const retryBtn = document.getElementById("menuRetryBtn");
        if (retryBtn) {
            retryBtn.disabled = true;
            const label = retryBtn.querySelector("span");
            if (label) label.innerText = "...";
        }
        try {
            await this.loadMenuFromServer();
            this.renderCategories();
            this.renderMenuItems();
        } finally {
            if (retryBtn) {
                retryBtn.disabled = false;
                const label = retryBtn.querySelector("span");
                if (label) {
                    label.innerText = this.translate("menuRetry", "Reload Menu");
                }
            }
        }
    }

    _updateMenuEmptyState(isEmpty) {
        const emptyState = document.getElementById("searchEmptyState");
        const emptyText = emptyState ? emptyState.querySelector(".search-empty-text") : null;
        const retryBtn = document.getElementById("menuRetryBtn");
        if (!emptyState) return;
        if (isEmpty && !(this.searchQuery || "").trim()) {
            emptyState.classList.add("visible");
            if (emptyText) {
                emptyText.innerText = this._menuLoadFailed
                    ? this.translate("menuEmptyLoadFailed", "Could not load the menu. Please try again.")
                    : this.translate(
                        "menuEmptyNoItems",
                        "Menu is not available yet. Please ask staff for help."
                    );
            }
            if (retryBtn) {
                retryBtn.classList.toggle("hide", !this._menuLoadFailed);
            }
        } else if (!isEmpty && !(this.searchQuery || "").trim()) {
            emptyState.classList.remove("visible");
            if (retryBtn) retryBtn.classList.add("hide");
        }
    }


    /**
     * Toggles Dark / Light mode (Default: Light Mode)
     */
    toggleTheme() {
        const body = document.body;
        body.classList.toggle("dark-theme");

        const isDark = body.classList.contains("dark-theme");
        const iconEl = document.querySelector("#themeToggleBtn .theme-toggle-icon");

        if (isDark) {
            if (iconEl) {
                iconEl.classList.remove("icon-moon");
                iconEl.classList.add("icon-sun");
            }
            localStorage.setItem("theme", "dark");
        } else {
            if (iconEl) {
                iconEl.classList.remove("icon-sun");
                iconEl.classList.add("icon-moon");
            }
            localStorage.setItem("theme", "light");
        }
    }

    /**
     * Switch UI language and dynamically update all texts
     */
    switchLanguage(lang) {
        if (!translations[lang]) {
            lang = "th";
        }
        this.currentLanguage = lang;
        localStorage.setItem("lang", lang);
        document.documentElement.lang = lang;

        const items = document.querySelectorAll(".lang-dropdown-item");
        const currentFlag = document.getElementById("langCurrentFlag");
        const currentLabel = document.getElementById("langCurrentLabel");

        items.forEach(item => {
            item.classList.toggle("active", item.dataset.lang === lang);
            if (item.dataset.lang === lang) {
                const flag = item.querySelector(".lang-flag").textContent;
                const name = item.querySelector(".lang-name").textContent;
                currentFlag.textContent = flag;
                currentLabel.textContent = name;
            }
        });

        document.getElementById("langDropdown").classList.remove("open");

        this.translateUI();
    }

    toggleLangDropdown(event) {
        event.stopPropagation();
        document.getElementById("langDropdown").classList.toggle("open");
    }

    translate(key, defaultVal = "") {
        const lang = this.currentLanguage || 'th';
        const dict = translations[lang];
        if (dict && dict[key] !== undefined) {
            return dict[key];
        }
        const enDict = translations['en'];
        if (enDict && enDict[key] !== undefined) {
            return enDict[key];
        }
        return defaultVal || key;
    }

    getItemName(item) {
        if (!item) return "";
        const lang = this.currentLanguage || 'th';
        if (item.name_translations && item.name_translations[lang]) {
            return item.name_translations[lang];
        }
        return this.translate('item_' + item.id + '_name', item.name);
    }

    getItemDesc(item) {
        if (!item) return "";
        const lang = this.currentLanguage || 'th';
        if (item.description_translations && item.description_translations[lang]) {
            return item.description_translations[lang];
        }
        return this.translate('item_' + item.id + '_desc', item.desc || "");
    }

    translateUI() {
        // Translate all static texts marked with data-translate-key
        const elements = document.querySelectorAll("[data-translate-key]");
        elements.forEach(el => {
            const key = el.getAttribute("data-translate-key");
            const translation = this.translate(key);
            if (translation) {
                if (el.tagName === "TEXTAREA" || el.tagName === "INPUT") {
                    el.placeholder = translation;
                } else {
                    el.innerText = translation;
                }
            }
        });

        // Translate table badge dynamically
        const badgeEl = document.getElementById("tableBadge");
        if (badgeEl) {
            const tableTextEl = badgeEl.querySelector(".table-text");
            if (tableTextEl) {
                tableTextEl.innerText = this.translate("tableBadgeText").replace("{num}", this.tableNumber);
            }
        }

        // Re-render categories & menu items
        this.renderCategories();
        this.renderMenuItems();

        // Re-render cart UI
        this.updateCartUI();

        // Trigger location verifier refresh in matching language
        // Re-render order history if loaded
        if (this.lastFetchedOrders && this.lastFetchedOrders.length > 0) {
            this.renderOrderHistory(this.lastFetchedOrders);
        }
    }


    /**
     * Parses the table number and session token from the URL params
     */
    parseURLParams() {
        const urlParams = new URLSearchParams(window.location.search);
        const table = urlParams.get('table') || urlParams.get('t');
        const merchant = urlParams.get('merchant') || urlParams.get('merchant_id');
        const branch = urlParams.get('branch') || urlParams.get('branch_code');
        const token = urlParams.get('token');
        const permanentKey = urlParams.get('key');
        const jwt = urlParams.get('jwt'); // Merchant JWT token from QR code

        // Validate table number: must be a non-empty string. Normalize 'T3' -> '3' for DB mapping.
        if (table && table.trim() !== '') {
            let normalizedTable = table.trim();
            if (/^[tT]\d+$/.test(normalizedTable)) {
                normalizedTable = normalizedTable.substring(1);
            }
            this.tableNumber = normalizedTable;
            try { sessionStorage.setItem('alphapos_table', normalizedTable); } catch (_) { /* ignore */ }
        } else {
            // Recover table from session if QR params were stripped after first load
            try {
                const cached = sessionStorage.getItem('alphapos_table');
                if (cached && cached.trim()) this.tableNumber = cached.trim();
            } catch (_) { /* ignore */ }
        }

        if (token) {
            this.sessionToken = token;
        }
        if (permanentKey && permanentKey.length <= 255) {
            this.permanentQRKey = permanentKey;
        }

        // Use JWT token from URL if provided (generated by iPad POS for this table's QR code)
        if (jwt) {
            this.merchantToken = jwt;
            console.log('[Auth] Using merchant JWT token from QR code URL');
        }

        let savedMerchant = safeStorageGet(localStorage, 'active_merchant_id', '');
        if (savedMerchant === '00000000-0000-0000-0000-000000000000') {
            savedMerchant = '';
        }
        // Prioritize URL parameter 'merchant' over saved merchant in localStorage to support scanning new store QR codes.
        // Fall back to saved merchant if URL param is absent.
        this.merchantId = (merchant && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(merchant) ? merchant : savedMerchant) || (window.ALPHAPOS_CONFIG?.merchantId || '');
        if (this.merchantId) {
            safeStorageSet(localStorage, 'active_merchant_id', this.merchantId);
        }
        this.branchCode = branch || safeStorageGet(localStorage, 'active_branch_code', '') || (window.ALPHAPOS_CONFIG?.branchCode || '');
        if (this.branchCode) {
            safeStorageSet(localStorage, 'active_branch_code', this.branchCode);
        }

        // Update Header Badge (null-safe — never throw and abort init)
        this._updateTableBadge();
    }

    _updateTableBadge() {
        try {
            const badgeEl = document.getElementById("tableBadge");
            const textEl = badgeEl ? badgeEl.querySelector(".table-text") : null;
            if (!textEl) return;
            const num = this.tableNumber && String(this.tableNumber).trim() ? this.tableNumber : "--";
            textEl.innerText = this.translate("tableBadgeText").replace("{num}", num);
        } catch (e) {
            console.warn("[AlphaPos] Failed to update table badge:", e);
        }
    }

    /**
     * Render category tabs
     */
    /**
     * Handle search input and filter menu items
     */
    handleSearch(value) {
        this.searchQuery = value;
        const clearBtn = document.getElementById("searchClearBtn");
        if (clearBtn) {
            clearBtn.classList.toggle("visible", value.length > 0);
        }
        this.renderMenuItems();
    }

    /**
     * Clear search input and reset menu
     */
    clearSearch() {
        document.getElementById("searchInput").value = "";
        this.handleSearch("");
        document.getElementById("searchInput").focus();
    }

    renderCategories() {
        const container = document.getElementById("categoryTabs");
        container.innerHTML = "";

        const categoryIcons = {
            "foods": `<svg class="category-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 2v7c0 1.1.9 2 2 2h4a2 2 0 0 0 2-2V2"></path><path d="M7 2v4"></path><path d="M21 15V2v0a5 5 0 0 0-5 5v3c0 1.1.9 2 2 2h3Z"></path><path d="M12 11v11"></path><path d="M18 11v11"></path></svg>`,
            "drinks": `<svg class="category-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M6 8h12L16 22H8L6 8z"></path><path d="m14 2-3 6"></path><path d="M18 2h-4"></path></svg>`,
            "desserts": `<svg class="category-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 2a5 5 0 0 0-5 5v2a5 5 0 0 0 10 0V7a5 5 0 0 0-5-5z"></path><path d="M6 14h12L12 22z"></path><path d="M17 14H7"></path></svg>`
        };

        this.categories.forEach(category => {
            const tab = document.createElement("button");
            tab.className = `category-tab ${this.currentCategory === category.id ? 'active' : ''}`;
            const iconHtml = categoryIcons[category.id] || '';
            const labelText = this.translate('category_' + category.id, category.name);
            tab.innerHTML = `${iconHtml}<span class="category-name">${escapeHtml(labelText)}</span>`;
            tab.onclick = () => this.switchCategory(category.id);
            container.appendChild(tab);
        });
    }

    /**
     * Dynamic Menu rendering
     */
    renderMenuItems() {
        const grid = document.getElementById("menuGrid");
        const featuredGrid = document.getElementById("featuredMenuGrid");
        const featuredSection = document.getElementById("featuredMenuSection");

        if (grid) grid.innerHTML = "";
        if (featuredGrid) featuredGrid.innerHTML = "";

        const query = this.searchQuery.trim().toLowerCase();
        const isSearching = query.length > 0;

        // Update Section Title
        const activeCategory = this.categories.find(c => c.id === this.currentCategory);
        const titleEl = document.getElementById("currentCategoryTitle");
        if (isSearching) {
            if (titleEl) {
                titleEl.innerText = this.translate('searchResults', `Search: "${this.searchQuery}"`)
                    .replace('{q}', this.searchQuery);
            }
        } else {
            if (titleEl) {
                if (this.currentCategory === "foods") {
                    titleEl.innerText = this.translate('category_mains', "Main Dishes");
                } else {
                    titleEl.innerText = activeCategory ? this.translate('category_' + activeCategory.id, activeCategory.name) : this.translate('menuTab', "Menu");
                }
            }
        }

        // Filter items
        let itemsToRender;
        if (isSearching) {
            itemsToRender = this.menuItems.filter(item => {
                const name = this.getItemName(item).toLowerCase();
                const desc = this.getItemDesc(item).toLowerCase();
                return name.includes(query) || desc.includes(query);
            });
        } else {
            itemsToRender = this.menuItems.filter(item => this._matchesMenuCategory(item, this.currentCategory));
        }

        // Apply allergen & dietary filters
        itemsToRender = this.allergenFilter.applyFilters(itemsToRender);

        // Show/hide empty state (search miss OR menu truly empty)
        const emptyState = document.getElementById("searchEmptyState");
        if (emptyState) {
            const menuEmpty = !this.menuItems || this.menuItems.length === 0;
            emptyState.classList.toggle("visible", (isSearching && itemsToRender.length === 0) || menuEmpty);
            const emptyText = emptyState.querySelector(".search-empty-text");
            if (emptyText) {
                if (menuEmpty) {
                    emptyText.innerText = this.translate(
                        "menuEmptyNoItems",
                        "Menu is not available yet. Please ask staff for help."
                    );
                } else if (isSearching && itemsToRender.length === 0) {
                    emptyText.innerText = this.translate("noSearchResults", "No items found");
                }
            }
        }

        // Hide featured section when searching
        if (isSearching || itemsToRender.length === 0) {
            if (featuredSection) featuredSection.style.display = "none";
        } else {
            if (featuredSection) featuredSection.style.display = "block";
        }

        // Split into Featured items and standard list items
        let featuredItems = [];
        let listItems = [];

        if (isSearching) {
            listItems = itemsToRender;
        } else {
            featuredItems = itemsToRender.slice(0, 5);
            listItems = itemsToRender.slice(5);
            if (featuredItems.length === 0 && featuredSection) {
                featuredSection.style.display = "none";
            }
        }

        // Helper to render a card or row
        const createItemHTML = (item, index, isFeatured) => {
            const inCartQty = this.getItemTotalQuantity(item.id);
            const isAvailable = item.is_available !== false && item.is_available !== 0 && item.is_available !== '0';

            let actionPillHtml;
            if (!isAvailable) {
                actionPillHtml = `
                    <button class="add-btn-only disabled" disabled aria-disabled="true" style="opacity: 0.6; cursor: not-allowed; font-size: 11px; width: auto; padding: 4px 10px; border-radius: 12px;">
                        <span>${this.translate('outOfStockBtn', 'หมด')}</span>
                    </button>
                `;
            } else if (inCartQty === 0) {
                actionPillHtml = `
                    <button class="add-btn-only" aria-label="Add ${escapeHtml(this.getItemName(item))} to cart" onclick="app.updateCartQuantity('${item.id}', 1); event.stopPropagation();">
                        <span class="add-btn-plus">+</span>
                    </button>
                `;
            } else {
                actionPillHtml = `
                    <div class="quantity-control-pill" onclick="event.stopPropagation()">
                        <button class="pill-qty-btn dec-btn" aria-label="Decrease ${escapeHtml(this.getItemName(item))}" onclick="app.updateCartQuantity('${item.id}', -1); event.stopPropagation();">-</button>
                        <span class="pill-qty-val">${inCartQty}</span>
                        <button class="pill-qty-btn inc-btn" aria-label="Increase ${escapeHtml(this.getItemName(item))}" onclick="app.updateCartQuantity('${item.id}', 1); event.stopPropagation();">+</button>
                    </div>
                `;
            }

            let itemSubcategory = "Main Course";
            if (item.category === "drinks") {
                itemSubcategory = this.translate("category_drinks", "Beverages");
            } else if (item.category === "desserts") {
                itemSubcategory = this.translate("category_desserts", "Desserts");
            } else if (item.category === "appetizers") {
                itemSubcategory = this.translate("category_appetizers", "Appetizers");
            } else {
                itemSubcategory = this.translate("category_mains", "Main Course");
            }

            const element = document.createElement("div");
            element.className = isFeatured 
                ? `featured-item-card ${inCartQty > 0 ? 'selected' : ''} ${!isAvailable ? 'out-of-stock' : ''}`
                : `list-item-card ${inCartQty > 0 ? 'selected' : ''} ${!isAvailable ? 'out-of-stock' : ''}`;

            element.style.animationDelay = `${index * 0.05}s`;
            element.setAttribute("role", "button");
            element.setAttribute("tabindex", "0");
            element.setAttribute("aria-label", `${this.getItemName(item)} ฿${item.price.toFixed(2)}`);
            element.setAttribute("data-item-id", item.id);
            element.addEventListener("keydown", (event) => {
                if (event.key === "Enter" || event.key === " ") {
                    event.preventDefault();
                    this.openProductDetailModal(item.id);
                }
            });

            // Tap vs. scroll detection using the W3C Pointer Events API (the
            // cross-platform standard covering mouse, touch and pen). We open the
            // modal on pointerup only when the pointer barely moved since
            // pointerdown — a genuine tap/click — so scrolling the list never
            // triggers the modal. There is no synthetic 300ms click involved, so
            // the response is immediate on both mobile and desktop.
            let _pointerStartX = 0;
            let _pointerStartY = 0;
            let _pointerActive = false;
            const TAP_SLOP = 12; // px of movement still considered a tap (iOS/Android standard ~10-12px)

            const isInteractiveTarget = (target) =>
                target.closest('button, a, input, textarea, select, .quantity-control-pill, .add-btn-only, .modal-qty-stepper');

            element.addEventListener("pointerdown", (event) => {
                if (isInteractiveTarget(event.target)) { _pointerActive = false; return; }
                _pointerActive = true;
                _pointerStartX = event.clientX;
                _pointerStartY = event.clientY;
            });

            element.addEventListener("pointerup", (event) => {
                if (!_pointerActive) return;
                _pointerActive = false;
                if (isInteractiveTarget(event.target)) return;
                // If the pointer moved beyond the slop threshold it was a scroll/drag, not a tap.
                if (Math.abs(event.clientX - _pointerStartX) > TAP_SLOP ||
                    Math.abs(event.clientY - _pointerStartY) > TAP_SLOP) return;
                this.openProductDetailModal(item.id);
            });

            // Cancel the pending tap if the browser takes over the gesture (e.g. scroll).
            element.addEventListener("pointercancel", () => { _pointerActive = false; });

            const resolvedImg = escapeHtml(this.resolveMenuImageUrl(item.imageUrl));
            const imgFallback = "this.onerror=null;this.src=this.dataset.fallback||'';";
            let mediaHtml;
            if (isFeatured && item.videoUrl) {
                mediaHtml = `
                    <video class="featured-item-img" autoplay loop muted playsinline style="width: 100%; height: 100%; object-fit: cover; border-radius: 50%;" onerror="this.style.display='none'; this.nextElementSibling.style.display='block';">
                        <source src="${escapeHtml(item.videoUrl)}" type="video/mp4">
                        <img class="featured-item-img" src="${resolvedImg}" data-fallback="${resolvedImg}" alt="${escapeHtml(this.getItemName(item))}" onerror="${imgFallback}">
                    </video>
                    <img class="featured-item-img" src="${resolvedImg}" data-fallback="${resolvedImg}" alt="${escapeHtml(this.getItemName(item))}" style="display:none;" onerror="${imgFallback}">
                `;
            } else {
                mediaHtml = `<img class="featured-item-img" src="${resolvedImg}" data-fallback="${resolvedImg}" alt="${escapeHtml(this.getItemName(item))}" onerror="${imgFallback}">`;
            }

            if (isFeatured) {
                element.innerHTML = `
                    <div class="featured-item-img-container">
                        ${mediaHtml}
                    </div>
                    <div class="featured-item-content">
                        <div class="featured-item-category">${escapeHtml(itemSubcategory)}</div>
                        <div class="featured-item-rating">
                            <span class="star-icon">★</span>
                            <span class="badge-icon">
                                <svg width="12" height="12" viewBox="0 0 24 24" fill="currentColor">
                                    <path d="M12 2C6.5 2 2 6.5 2 12s4.5 10 10 10 10-4.5 10-10S17.5 2 12 2zm-2 15l-5-5 1.41-1.41L10 14.17l7.59-7.59L19 8l-9 9z"/>
                                </svg>
                            </span>
                        </div>
                        <h3 class="featured-item-title">${escapeHtml(this.getItemName(item))}</h3>
                        <p class="featured-item-desc">${escapeHtml(this.getItemDesc(item))}</p>
                        <div class="featured-item-price-action" onclick="event.stopPropagation()">
                            <span class="featured-item-price">฿${item.price.toFixed(2)}</span>
                            <div class="featured-item-action">
                                ${actionPillHtml}
                            </div>
                        </div>
                    </div>
                `;
            } else {
                let mediaHtml;
                if (item.videoUrl) {
                    mediaHtml = `
                        <video class="list-item-img" autoplay loop muted playsinline style="width: 100%; height: 100%; object-fit: cover;" onerror="this.style.display='none'; this.nextElementSibling.style.display='block';">
                            <source src="${escapeHtml(item.videoUrl)}" type="video/mp4">
                            <img class="list-item-img" src="${resolvedImg}" data-fallback="${resolvedImg}" alt="${escapeHtml(this.getItemName(item))}" onerror="${imgFallback}">
                        </video>
                        <img class="list-item-img" src="${resolvedImg}" data-fallback="${resolvedImg}" alt="${escapeHtml(this.getItemName(item))}" style="display:none;" onerror="${imgFallback}">
                    `;
                } else {
                    mediaHtml = `
                        <img class="list-item-img" src="${resolvedImg}" data-fallback="${resolvedImg}" alt="${escapeHtml(this.getItemName(item))}" onerror="${imgFallback}">
                    `;
                }

                const qtyBadgeHtml = inCartQty > 0 ? `<div class="card-qty-badge">${inCartQty}</div>` : '';

                element.innerHTML = `
                    <div class="list-item-content">
                        <div class="list-item-category">${escapeHtml(itemSubcategory)}</div>
                        <div class="list-item-rating">
                            <span class="star-icon">★</span>
                        </div>
                        <h3 class="list-item-title">${escapeHtml(this.getItemName(item))}</h3>
                        <p class="list-item-desc">${escapeHtml(this.getItemDesc(item))}</p>
                        ${this.allergenFilter.renderBadges(item.id)}
                        <div class="list-item-price-action">
                            <span class="list-item-price">฿${item.price.toFixed(2)}</span>
                            <div class="list-item-action" onclick="event.stopPropagation()">
                                ${actionPillHtml}
                            </div>
                        </div>
                    </div>
                    <div class="list-item-img-container">
                        ${mediaHtml}
                        ${qtyBadgeHtml}
                    </div>
                `;
            }

            return element;
        };

        // Render featured items
        if (featuredGrid) {
            featuredGrid.classList.toggle("scrollable", featuredItems.length > 3);
        }
        featuredItems.forEach((item, index) => {
            if (featuredGrid) {
                featuredGrid.appendChild(createItemHTML(item, index, true));
            }
        });

        // Render standard items
        listItems.forEach((item, index) => {
            if (grid) {
                grid.appendChild(createItemHTML(item, index, false));
            }
        });

        // Apply saved view mode (grid/list) after rendering
        if (grid) {
            grid.classList.toggle('grid-view', this.menuViewMode === 'grid');
        }
        // Sync toggle buttons
        this.setMenuView(this.menuViewMode);

        // Warm the browser cache with detail images so the product modal
        // shows its hero image instantly (no flash) when a card is tapped.
        this.prefetchMenuImages();
        this.refreshMotionTargets();
    }

    /**
     * Preloads menu item images in the background so they are cached before
     * the user opens the product detail modal. Runs during idle time and
     * skips URLs that have already been requested.
     */
    prefetchMenuImages() {
        if (!this.menuItems || !this.menuItems.length) return;
        this._prefetchedImages = this._prefetchedImages || new Set();

        const urls = [];
        for (const item of this.menuItems) {
            const url = item.imageUrl;
            if (!url) continue;
            if (!(url.startsWith('http://') || url.startsWith('https://'))) continue;
            if (this._prefetchedImages.has(url)) continue;
            this._prefetchedImages.add(url);
            urls.push(url);
        }
        if (!urls.length) return;

        const run = () => {
            urls.forEach(url => {
                const img = new Image();
                img.decoding = "async";
                img.src = url;
            });
        };
        if (typeof requestIdleCallback === "function") {
            requestIdleCallback(run, { timeout: 2000 });
        } else {
            setTimeout(run, 300);
        }
    }

    /**
     * Switches menu list view between 'list' (1-col) and 'grid' (2-col)
     */
    setMenuView(mode) {
        this.menuViewMode = mode;
        localStorage.setItem('menuViewMode', mode);

        const grid = document.getElementById('menuGrid');
        if (grid) {
            if (mode === 'grid') {
                grid.classList.add('grid-view');
            } else {
                grid.classList.remove('grid-view');
            }
        }

        // Update toggle button active state
        const listBtn = document.getElementById('viewListBtn');
        const gridBtn = document.getElementById('viewGridBtn');
        if (listBtn) listBtn.classList.toggle('active', mode === 'list');
        if (gridBtn) gridBtn.classList.toggle('active', mode === 'grid');
    }

    /**
     * Switches active category tab
     */
    switchCategory(categoryId) {
        this.currentCategory = categoryId;
        this.renderCategories();
        this.renderMenuItems();
    }

    /**
     * Get the total quantity of a specific menu item in the cart
     */
    getItemTotalQuantity(itemId) {
        let total = 0;
        Object.values(this.cart).forEach(cartItem => {
            if (typeof cartItem === 'number') {
                // Legacy support
            } else if (cartItem && cartItem.itemId === itemId) {
                total += cartItem.quantity;
            }
        });
        if (typeof this.cart[itemId] === 'number') {
            total += this.cart[itemId];
        }
        return total;
    }

    /**
     * Adds item to cart (supports modifiers and notes)
     */
    addToCart(itemId, quantity = 1, selectedModifiers = [], notes = "") {
        const sortedModIds = selectedModifiers.map(m => m.id).sort();
        const notesKey = notes ? btoa(unescape(encodeURIComponent(notes))).slice(0, 10) : "";
        const cartKey = sortedModIds.length > 0
            ? `${itemId}-${sortedModIds.join("-")}${notesKey ? "-" + notesKey : ""}`
            : itemId;

        if (this.cart[cartKey] && typeof this.cart[cartKey] === 'object') {
            this.cart[cartKey].quantity += quantity;
        } else {
            this.cart[cartKey] = {
                itemId: itemId,
                quantity: quantity,
                selectedModifiers: selectedModifiers,
                notes: notes
            };
        }
        this.updateItemCardUI(itemId);
        this.updateCartUI();
        this.jiggleCartNotification();
    }

    /**
     * Updates cart item quantities (supports cartKey and itemId)
     */
    updateCartQuantity(cartKeyOrItemId, change) {
        let itemId = (this.cart[cartKeyOrItemId] && typeof this.cart[cartKeyOrItemId] === 'object') ? this.cart[cartKeyOrItemId].itemId : cartKeyOrItemId;
        if (this.cart[cartKeyOrItemId]) {
            if (typeof this.cart[cartKeyOrItemId] === 'number') {
                const newQty = this.cart[cartKeyOrItemId] + change;
                if (newQty <= 0) {
                    delete this.cart[cartKeyOrItemId];
                } else {
                    this.cart[cartKeyOrItemId] = newQty;
                }
            } else {
                const currentQty = this.cart[cartKeyOrItemId].quantity || 0;
                const newQty = currentQty + change;
                if (newQty <= 0) {
                    delete this.cart[cartKeyOrItemId];
                } else {
                    this.cart[cartKeyOrItemId].quantity = newQty;
                }
            }
        } else {
            if (change < 0) {
                const matchingKeys = Object.keys(this.cart).filter(k => {
                    const val = this.cart[k];
                    return (val && val.itemId === cartKeyOrItemId) || k === cartKeyOrItemId;
                });
                if (matchingKeys.length > 0) {
                    const targetKey = matchingKeys[matchingKeys.length - 1];
                    itemId = (this.cart[targetKey] && typeof this.cart[targetKey] === 'object') ? this.cart[targetKey].itemId : targetKey;
                    if (typeof this.cart[targetKey] === 'number') {
                        const newQty = this.cart[targetKey] + change;
                        if (newQty <= 0) delete this.cart[targetKey];
                        else this.cart[targetKey] = newQty;
                    } else {
                        const newQty = (this.cart[targetKey].quantity || 0) + change;
                        if (newQty <= 0) delete this.cart[targetKey];
                        else this.cart[targetKey].quantity = newQty;
                    }
                }
            } else if (change > 0) {
                if (this.hasModifiers(cartKeyOrItemId)) {
                    this.openProductDetailModal(cartKeyOrItemId);
                    return;
                } else {
                    this.addToCart(cartKeyOrItemId, change);
                    return;
                }
            }
        }

        this.updateItemCardUI(itemId);
        this.updateCartUI();
    }

    /**
     * Inline DOM update helper for individual product cards to prevent page layout redraws
     */
    updateItemCardUI(itemId) {
        const inCartQty = this.getItemTotalQuantity(itemId);
        const cards = document.querySelectorAll(`[data-item-id="${itemId}"]`);
        
        cards.forEach(card => {
            card.classList.toggle("selected", inCartQty > 0);

            const isFeatured = card.classList.contains("featured-item-card");
            const actionEl = card.querySelector(isFeatured ? ".featured-item-action" : ".list-item-action");
            
            if (actionEl) {
                const item = this.menuItems.find(i => i.id === itemId);
                if (!item) return;

                let actionPillHtml;
                if (inCartQty === 0) {
                    actionPillHtml = `
                        <button class="add-btn-only" aria-label="Add ${escapeHtml(this.getItemName(item))} to cart" onclick="app.updateCartQuantity('${item.id}', 1); event.stopPropagation();">
                            <span class="add-btn-plus">+</span>
                        </button>
                    `;
                } else {
                    actionPillHtml = `
                        <div class="quantity-control-pill" onclick="event.stopPropagation()">
                            <button class="pill-qty-btn dec-btn" aria-label="Decrease ${escapeHtml(this.getItemName(item))}" onclick="app.updateCartQuantity('${item.id}', -1); event.stopPropagation();">-</button>
                            <span class="pill-qty-val">${inCartQty}</span>
                            <button class="pill-qty-btn inc-btn" aria-label="Increase ${escapeHtml(this.getItemName(item))}" onclick="app.updateCartQuantity('${item.id}', 1); event.stopPropagation();">+</button>
                        </div>
                    `;
                }
                actionEl.innerHTML = actionPillHtml;
            }
        });
    }

    /**
     * Calculate subtotal, promotions, service charges, vat, and total.
     * Rules mirror POS: cart-wide %/fixed, item-scoped %/fixed,
     * bundle / buy X get Y / buy X pay Y.
     */
    calculateTotals() {
        let subtotal = 0;
        const lineItems = [];

        Object.keys(this.cart).forEach(cartKey => {
            const cartItem = this.cart[cartKey];
            if (cartItem === undefined || cartItem === null) return;

            let itemId = cartKey;
            let qty = 0;
            let modifierPriceSum = 0;

            if (typeof cartItem === 'number') {
                itemId = cartKey;
                qty = cartItem;
            } else {
                itemId = cartItem.itemId;
                qty = cartItem.quantity;
                const selectedModifiers = cartItem.selectedModifiers || [];
                selectedModifiers.forEach(m => {
                    modifierPriceSum += parseFloat(m.price || 0);
                });
            }

            const item = this.menuItems.find(m => m.id === itemId);
            if (item) {
                const unit = item.price + modifierPriceSum;
                const lineTotal = unit * qty;
                subtotal += lineTotal;
                lineItems.push({ itemId, qty, unit, lineTotal });
            }
        });

        const promoResult = this.calculateBestPromotionDiscount(subtotal, lineItems);
        const discount = promoResult.amount;
        const discountedSubtotal = Math.max(0, subtotal - discount);
        const taxRate = Number(this.merchantSettings.tax_rate ?? 7) / 100;
        const serviceCharge = discountedSubtotal * (Number(this.merchantSettings.service_charge_rate ?? 10) / 100);
        const inclusiveTax = (this.merchantSettings.tax_type || 'inclusive') === 'inclusive';
        const itemTax = inclusiveTax ? discountedSubtotal * taxRate / (1 + taxRate) : discountedSubtotal * taxRate;
        const serviceTax = serviceCharge * taxRate;
        const tax = itemTax + serviceTax;
        const total = discountedSubtotal + serviceCharge + serviceTax + (inclusiveTax ? 0 : itemTax);

        this._appliedPromotions = promoResult.promotion ? [promoResult.promotion] : [];

        return {
            subtotal,
            discount,
            discountLabel: promoResult.label,
            serviceCharge,
            tax,
            total,
            promotion: promoResult.promotion
        };
    }

    calculateBestPromotionDiscount(subtotal, lineItems) {
        const promos = (this._activePromotions || []).filter(p => {
            const type = p.discount_type || p.discountType || 'none';
            return type && type !== 'none' && this.isPromotionCurrentlyVisible(p);
        });
        if (!promos.length || subtotal <= 0) {
            return { amount: 0, label: '', promotion: null };
        }

        let best = { amount: 0, label: '', promotion: null };
        for (const promo of promos) {
            const amount = this.promotionDiscountAmount(promo, subtotal, lineItems);
            if (amount > best.amount) {
                const type = promo.discount_type || promo.discountType;
                const value = Number(promo.discount_value ?? promo.discountValue ?? 0);
                let label = promo.title || 'Discount';
                if (type === 'percentage') label = `${promo.title || 'Discount'} (−${value}%)`;
                else if (type === 'fixed') label = `${promo.title || 'Discount'} (−฿${value})`;
                best = { amount, label, promotion: promo };
            }
        }
        return best;
    }

    promotionDiscountAmount(promo, subtotal, lineItems) {
        const type = promo.discount_type || promo.discountType || 'none';
        const value = Number(promo.discount_value ?? promo.discountValue ?? 0);
        const minSpend = Number(promo.minimum_spend ?? promo.minimumSpend ?? 0);
        const itemId = promo.applies_to_menu_item_id || promo.appliesToMenuItemId || '';
        const requiredQty = Math.max(1, Number(promo.required_quantity ?? promo.requiredQuantity ?? 1));
        const rewardQty = Math.max(0, Number(promo.reward_quantity ?? promo.rewardQuantity ?? 0));

        if (subtotal < minSpend) return 0;

        if (type === 'percentage' || type === 'fixed') {
            let base = subtotal;
            if (itemId) {
                base = lineItems
                    .filter(l => String(l.itemId) === String(itemId))
                    .reduce((sum, l) => sum + l.lineTotal, 0);
                if (base <= 0) return 0;
            }
            if (type === 'percentage') return Math.min(base, base * (Math.min(100, value) / 100));
            return Math.min(base, Math.max(0, value));
        }

        if (!itemId) return 0;
        const lines = lineItems.filter(l => String(l.itemId) === String(itemId));
        if (!lines.length) return 0;

        if (type === 'bundle_price' && value > 0) {
            return lines.reduce((total, line) => {
                const bundles = Math.floor(line.qty / requiredQty);
                if (bundles <= 0) return total;
                const regular = line.unit * requiredQty * bundles;
                const promoTotal = value * bundles;
                return total + Math.max(0, regular - promoTotal);
            }, 0);
        }

        if (type === 'buy_x_get_y' && rewardQty > 0) {
            const groupSize = requiredQty + rewardQty;
            return lines.reduce((total, line) => {
                const groups = Math.floor(line.qty / groupSize);
                return total + Math.max(0, line.unit * groups * rewardQty);
            }, 0);
        }

        if (type === 'buy_x_pay_y' && rewardQty > 0 && rewardQty < requiredQty) {
            return lines.reduce((total, line) => {
                const groups = Math.floor(line.qty / requiredQty);
                const freeUnits = groups * (requiredQty - rewardQty);
                return total + Math.max(0, line.unit * freeUnits);
            }, 0);
        }

        return 0;
    }

    /**
     * Update Floating Cart and Drawer info
     */
    updateCartUI() {
        const { subtotal, discount, discountLabel, serviceCharge, tax, total } = this.calculateTotals();
        let totalItems = 0;

        Object.values(this.cart).forEach(cartItem => {
            if (typeof cartItem === 'number') {
                totalItems += cartItem;
            } else if (cartItem && typeof cartItem.quantity === 'number') {
                totalItems += cartItem.quantity;
            }
        });

        // Update elements
        document.getElementById("cartCount").innerText = totalItems;
        document.getElementById("cartTotal").innerText = `฿${total.toFixed(2)}`;

        // Breakdown elements in drawer
        document.getElementById("breakdownSubtotal").innerText = `฿${subtotal.toFixed(2)}`;
        const discountRow = document.getElementById("breakdownDiscountRow");
        const discountEl = document.getElementById("breakdownDiscount");
        const discountLabelEl = document.getElementById("breakdownDiscountLabel");
        if (discountRow && discountEl) {
            if (discount > 0) {
                discountRow.style.display = '';
                discountEl.innerText = `-฿${discount.toFixed(2)}`;
                if (discountLabelEl) discountLabelEl.innerText = discountLabel || 'Discount';
            } else {
                discountRow.style.display = 'none';
            }
        }
        document.getElementById("breakdownService").innerText = `฿${serviceCharge.toFixed(2)}`;
        document.getElementById("breakdownTax").innerText = `฿${tax.toFixed(2)}`;
        document.getElementById("breakdownTotal").innerText = `฿${total.toFixed(2)}`;

        // Render items inside drawer list
        this.renderDrawerCartList();

        // Render loyalty earn preview in cart
        const earnPreviewContainer = document.getElementById('loyaltyEarnPreview');
        if (earnPreviewContainer && loyaltySystem.config?.loyalty_enabled) {
            earnPreviewContainer.innerHTML = loyaltySystem.renderEarnPreview(total);
        }

        // Show/hide floating cart bar
        const cartBar = document.getElementById("cartBar");
        if (totalItems > 0) {
            cartBar.classList.add("show");
        } else {
            cartBar.classList.remove("show");
            this.toggleCartDrawer(false); // Auto close drawer if cart emptied
        }

        // Update floating request button alignment when cart bar is active
        const requestBtn = document.getElementById("floatingRequestBtn");
        if (requestBtn) {
            if (totalItems > 0) {
                requestBtn.classList.add("cart-active");
            } else {
                requestBtn.classList.remove("cart-active");
            }
        }

        // Save cart state to storage
        this.saveCartToStorage();
    }

    /**
     * Render the items breakdown row inside the cart drawer
     */
    renderDrawerCartList() {
        const container = document.getElementById("cartItemsList");
        container.innerHTML = "";

        const cartKeys = Object.keys(this.cart);
        const itemCount = cartKeys.reduce((total, key) => {
            const value = this.cart[key];
            return total + (typeof value === 'object' ? Number(value.quantity || 0) : Number(value || 0));
        }, 0);
        const countEl = document.getElementById("cartDrawerCount");
        if (countEl) countEl.textContent = `${itemCount} ${this.translate('itemsLabel', 'items')}`;

        if (cartKeys.length === 0) {
            container.innerHTML = `<div class="empty-state">${this.translate('emptyTray')}</div>`;
            return;
        }

        cartKeys.forEach(cartKey => {
            const cartItem = this.cart[cartKey];
            if (!cartItem) return;

            let itemId = cartKey;
            let qty = cartItem;
            let selectedModifiers = [];
            let notes = "";

            if (typeof cartItem === 'object') {
                itemId = cartItem.itemId;
                qty = cartItem.quantity;
                selectedModifiers = cartItem.selectedModifiers || [];
                notes = cartItem.notes || "";
            }

            const item = this.menuItems.find(m => m.id === itemId);
            if (!item) return;

            // Calculate item single price including modifiers
            let modifierPriceSum = 0;
            let modifierNames = [];
            selectedModifiers.forEach(m => {
                modifierPriceSum += parseFloat(m.price || 0);
                const translatedModName = this.translate('modifier_' + m.name, m.name);
                modifierNames.push(`${translatedModName} (+฿${parseFloat(m.price || 0).toFixed(2)})`);
            });

            const singlePrice = item.price + modifierPriceSum;
            const rowTotal = singlePrice * qty;

            const modifierHtml = modifierNames.length > 0
                ? `<div class="cart-item-modifiers" style="font-size: 0.85rem; color: var(--text-secondary); margin-top: 4px;">
                     ${modifierNames.join(", ")}
                   </div>`
                : "";

            const notesHtml = notes.trim()
                ? `<div class="cart-item-notes" style="font-size: 0.8rem; color: #d97706; margin-top: 2px; font-style: italic;">
                     ${this.translate('noteLabel')}: "${escapeHtml(notes)}"
                   </div>`
                : "";

            const row = document.createElement("div");
            row.className = "cart-item-row";
            row.style.setProperty('--cart-row-index', container.children.length);
            row.innerHTML = `
                <div class="cart-item-details">
                     <div class="cart-item-name">${escapeHtml(this.getItemName(item))}</div>
                    ${modifierHtml}
                    ${notesHtml}
                    <div class="cart-item-price-sum">฿${singlePrice.toFixed(2)} × ${qty} = ฿${rowTotal.toFixed(2)}</div>
                </div>
                <div class="quantity-control">
                    <button class="qty-btn" onclick="app.updateCartQuantity('${cartKey}', -1)">-</button>
                    <span class="qty-value">${qty}</span>
                    <button class="qty-btn" onclick="app.updateCartQuantity('${cartKey}', 1)">+</button>
                </div>
            `;
            container.appendChild(row);
        });
    }

    /**
     * Show / Hide the Cart Drawer
     */
    toggleCartDrawer(show) {
        const overlay = document.getElementById("cartDrawerOverlay");
        if (show) {
            overlay.classList.add("show");
            this.setActiveModal(overlay);
        } else {
            overlay.classList.remove("show");
            if (this._activeModal === overlay) this.setActiveModal(null);
        }
    }



    /**
     * Animate cart bar on new item additions
     */
    jiggleCartNotification() {
        const cartContent = document.querySelector(".cart-bar-content");
        if (cartContent) {
            cartContent.classList.remove("jiggle");
            void cartContent.offsetWidth; // Force DOM reflow
            cartContent.classList.add("jiggle");
            setTimeout(() => {
                cartContent.classList.remove("jiggle");
            }, 400);
        }
    }

    switchView(viewName) {
        const commitView = () => {
            this.currentView = viewName;
            const appContainer = document.querySelector('.app-container');
            if (appContainer) appContainer.scrollTop = 0;

            document.querySelectorAll(".nav-tab").forEach(tab => {
                tab.classList.remove("active");
                tab.setAttribute('aria-selected', 'false');
            });
            document.querySelectorAll(".view-panel").forEach(panel => {
                panel.classList.add("hide");
                panel.classList.remove("active");
            });

            if (viewName === "menu") {
                document.getElementById("navTabMenu").classList.add("active");
                document.getElementById("menuView").classList.remove("hide");
                document.getElementById("menuView").classList.add("active");
                this.updateCartUI();
            } else if (viewName === "status") {
                document.getElementById("navTabStatus").classList.add("active");
                document.getElementById("statusView").classList.remove("hide");
                document.getElementById("statusView").classList.add("active");
                document.getElementById("cartBar").classList.remove("show");
                this.fetchOrderHistory();
            } else if (viewName === "service") {
                document.getElementById("navTabService").classList.add("active");
                document.getElementById("serviceView").classList.remove("hide");
                document.getElementById("serviceView").classList.add("active");
                document.getElementById("cartBar").classList.remove("show");
            }

            document.querySelector(`#navTab${viewName[0].toUpperCase()}${viewName.slice(1)}`)
                ?.setAttribute('aria-selected', 'true');
            const requestBtn = document.getElementById("floatingRequestBtn");
            if (requestBtn) requestBtn.style.display = viewName === "service" ? "none" : "flex";
        };

        window.scrollTo({ top: 0, behavior: 'smooth' });
        const canTransition = typeof document.startViewTransition === 'function'
            && !window.matchMedia('(prefers-reduced-motion: reduce)').matches;
        if (canTransition) document.startViewTransition(commitView);
        else commitView();
    }

    async fetchOrderHistory({ showLoading = true } = {}) {
        if (!this.sessionToken) return;
        if (this._orderHistoryFetchInFlight) return;
        this._orderHistoryFetchInFlight = true;

        const activeContainer = document.getElementById("activeOrdersList");
        const pastContainer = document.getElementById("pastOrdersList");
        if (showLoading && activeContainer) {
            activeContainer.setAttribute("aria-busy", "true");
            activeContainer.innerHTML = Array.from({ length: 5 }, () => `
                <div class="status-row-skeleton" aria-hidden="true">
                    <span class="skeleton-qty"></span><span class="skeleton-copy"></span><span class="skeleton-state"></span>
                </div>`).join("");
        }
        if (showLoading && pastContainer) pastContainer.innerHTML = "";

        let success = false;
        let formattedOrders = [];

        if (this.supabase) {
            try {
                // The session was already validated before ordering. Read the exact
                // database rows for this merchant/table/session without unrelated joins.
                const { data: ordersData, error: ordersError } = await this.supabase
                    .from('orders')
                    .select('*, order_items(*, order_item_modifiers(*))')
                    .eq('merchant_id', this.merchantId)
                    .eq('table_number', this.tableNumber)
                    .eq('session_token', this.sessionToken)
                    .order('created_at', { ascending: true });

                if (ordersError) throw ordersError;

                    formattedOrders = (ordersData || []).map(order => {
                        const items = (order.order_items || []).map(item => {
                            const mods = (item.order_item_modifiers || []).map(m => {
                                const modConfig = this.modifiersConfig.modifiers.find(mc => mc.id === m.modifier_id);
                                return {
                                    id: m.id,
                                    name: modConfig ? modConfig.name : "Modifier",
                                    price: m.price
                                };
                            });
                            return {
                                id: item.id,
                                name: item.item_name,
                                quantity: item.quantity,
                                price: item.price,
                                status: item.status,
                                item_id: item.item_id,
                                notes: item.notes || "",
                                modifiers: mods
                            };
                        });
                        return {
                            id: order.id,
                            orderNumber: order.order_number,
                            tableNumber: order.table_number,
                            total: order.total,
                            status: order.status,
                            createdAt: order.created_at,
                            items: items
                        };
                    });
                    success = true;
            } catch (error) {
                console.error("Supabase error fetching order history, falling back to local server:", error);
            }
        }

        if (!success && this.isLocalServerAvailable) {
            try {
                const params = new URLSearchParams({ table_number: this.tableNumber, session_token: this.sessionToken });
                const res = await fetch(`${this.localServerURL}/v1/orders?${params}`);
                if (res.ok) {
                    formattedOrders = await res.json();
                    success = true;
                }
            } catch (localErr) {
                console.error("Local server error fetching order history:", localErr);
            }
        }

        if (success) {
            this.lastFetchedOrders = formattedOrders;
            this._knownOrderIds = new Set(formattedOrders.map(order => order.id));
            this._lastHistoryRefreshAt = Date.now();
            const nextSignature = JSON.stringify(formattedOrders.map(order => ({
                id: order.id,
                status: order.status,
                total: order.total,
                items: order.items.map(item => ({
                    id: item.id,
                    status: item.status,
                    quantity: item.quantity,
                    notes: item.notes,
                    modifiers: item.modifiers
                }))
            })));
            // A reconciliation response with identical data must not rebuild the
            // status DOM: on Safari that can reset a customer's scroll position.
            if (showLoading || nextSignature !== this._orderHistorySignature) {
                this._orderHistorySignature = nextSignature;
                this.renderOrderHistory(formattedOrders);
            }
        } else if (showLoading && activeContainer) {
            activeContainer.removeAttribute("aria-busy");
            activeContainer.innerHTML = `<div class="empty-state">${this.translate('noActiveItems')}</div>`;
        }
        this._orderHistoryFetchInFlight = false;
    }

    renderOrderHistory(orders) {
        const activeContainer = document.getElementById("activeOrdersList");
        const pastContainer = document.getElementById("pastOrdersList");
        const grandTotalEl = document.getElementById("sessionGrandTotal");
        const badgeEl = document.getElementById("statusTabBadge");

        // Update table info subtitle in the header
        const tableInfoEl = document.getElementById("statusTableInfo");
        if (tableInfoEl) {
            tableInfoEl.innerText = `${this.translate('tableLabel')} ${this.tableNumber} • ${this.selectedGuestCount || 1} ${this.translate('guestsLabel')}`;
        }

        activeContainer.innerHTML = "";
        pastContainer.innerHTML = "";

        let grandTotal = 0;
        let activeCookingCount = 0;
        let activeItems = [];
        let pastItems = [];

        orders.forEach(order => {
            grandTotal += order.total;

            order.items.forEach(item => {
                const status = (item.status || "cooking").toLowerCase();
                if (status === "pending" || status === "cooking" || status === "preparing" || status === "ready") {
                    activeItems.push({
                        orderNumber: order.orderNumber,
                        id: item.id,
                        name: item.name,
                        quantity: item.quantity,
                        price: item.price,
                        status: status,
                        item_id: item.item_id,
                        notes: item.notes,
                        modifiers: item.modifiers
                    });
                    activeCookingCount += item.quantity;
                } else {
                    pastItems.push({
                        orderNumber: order.orderNumber,
                        id: item.id,
                        name: item.name,
                        quantity: item.quantity,
                        price: item.price,
                        status: status,
                        item_id: item.item_id,
                        notes: item.notes,
                        modifiers: item.modifiers
                    });
                }
            });
        });

        grandTotalEl.innerText = `฿${grandTotal.toFixed(2)}`;
        activeContainer.removeAttribute("aria-busy");

        if (activeCookingCount > 0) {
            badgeEl.innerText = activeCookingCount;
            badgeEl.classList.remove("hide");
        } else {
            badgeEl.classList.add("hide");
        }

        // Show/hide Track Order button
        const trackBtn = document.getElementById('btnTrackOrder');
        if (trackBtn) {
            trackBtn.style.display = (activeCookingCount > 0 && this._lastOrderId) ? 'inline-flex' : 'none';
        }

        if (activeItems.length === 0) {
            activeContainer.innerHTML = `<div class="empty-state">${this.translate('noActiveItems')}</div>`;
        } else {
            activeItems.forEach(item => {
                const statusClass = (item.status || "cooking").toLowerCase();
                const matchedMenuItem = this.menuItems.find(m => m.id === item.item_id) || this.menuItems.find(m => m.name === item.name);
                const displayName = matchedMenuItem ? this.getItemName(matchedMenuItem) : item.name;

                const el = document.createElement("div");
                el.className = "status-item-card";
                const noteKey = `item_note_${item.id}`;
                const savedNote = localStorage.getItem(noteKey) || '';
                
                let modifiersHtml = "";
                if (item.modifiers && item.modifiers.length > 0) {
                    const modNames = item.modifiers.map(m => {
                        const translatedName = this.translate('modifier_' + m.name, m.name);
                        return `${translatedName} (+฿${parseFloat(m.price || 0).toFixed(2)})`;
                    });
                    modifiersHtml = `<div class="item-modifiers-display" style="font-size: 0.8rem; color: #6B7280; margin-top: 2px;">${modNames.join(", ")}</div>`;
                }

                const itemNote = item.notes || savedNote;
                const noteHtml = itemNote.trim()
                    ? `<div class="item-note-display" style="font-size: 0.8rem; color: #d97706; margin-top: 2px; font-style: italic;">
                         <span class="note-icon app-icon icon-menu" aria-hidden="true"></span> <span class="note-text">${escapeHtml(itemNote)}</span>
                       </div>`
                    : "";

                const statusLabel = statusClass === "ready"
                    ? this.translate('stepReady')
                    : statusClass === "pending"
                        ? this.translate('stepReceived')
                        : this.translate('stepPreparing');
                const statusIcon = statusClass === "ready" ? "icon-bell" : statusClass === "pending" ? "icon-check" : "icon-clock";

                el.innerHTML = `
                    <div class="status-item-body compact-status-row">
                        <span class="item-qty" aria-label="${item.quantity}">×${item.quantity}</span>
                        <div class="item-info">
                            <div class="item-header">
                                <span class="item-name">${escapeHtml(displayName)}</span>
                            </div>
                            <div class="item-meta">#${escapeHtml(item.orderNumber || '')}</div>
                            ${modifiersHtml}
                            ${noteHtml}
                        </div>
                        <div class="status-action-group">
                            <span class="status-badge ${statusClass}"><span class="app-icon ${statusIcon}" aria-hidden="true"></span>${statusLabel}</span>
                            <button class="add-note-btn" aria-label="${this.translate('addNoteBtn')}" onclick="app.addItemNote('${item.id}', '${escapeHtml(displayName)}')" title="${this.translate('addNoteBtn')}"><span class="app-icon icon-menu" aria-hidden="true"></span></button>
                        </div>
                    </div>
                `;
                el.style.setProperty('--row-index', activeContainer.children.length);
                activeContainer.appendChild(el);
            });
        }

        if (pastItems.length === 0) {
            pastContainer.innerHTML = `<div class="empty-state">${this.translate('noServedItems')}</div>`;
        } else {
            pastItems.forEach(item => {
                const statusLabel = item.status === "cancelled" ? this.translate('cancelledStatus') : this.translate('servedStatus');
                const statusClass = item.status === "cancelled" ? "cancelled" : "served";
                const statusIcon = item.status === "cancelled" ? "icon-alert" : "icon-utensils";

                const matchedMenuItem = this.menuItems.find(m => m.id === item.item_id) || this.menuItems.find(m => m.name === item.name);
                const displayName = matchedMenuItem ? this.getItemName(matchedMenuItem) : item.name;

                const el = document.createElement("div");
                el.className = "status-item-card served-item";
                const pastNoteKey = `item_note_${item.id}`;
                const pastSavedNote = localStorage.getItem(pastNoteKey) || '';

                let modifiersHtml = "";
                if (item.modifiers && item.modifiers.length > 0) {
                    const modNames = item.modifiers.map(m => {
                        const translatedName = this.translate('modifier_' + m.name, m.name);
                        return `${translatedName} (+฿${parseFloat(m.price || 0).toFixed(2)})`;
                    });
                    modifiersHtml = `<div class="item-modifiers-display" style="font-size: 0.8rem; color: #6B7280; margin-top: 2px;">${modNames.join(", ")}</div>`;
                }

                const itemNote = item.notes || pastSavedNote;
                const noteHtml = itemNote.trim()
                    ? `<div class="item-note-display" style="font-size: 0.8rem; color: #d97706; margin-top: 2px; font-style: italic;">
                         <span class="note-icon app-icon icon-menu" aria-hidden="true"></span> <span class="note-text">${escapeHtml(itemNote)}</span>
                       </div>`
                    : "";

                el.innerHTML = `
                    <span class="item-qty" aria-label="${item.quantity}">×${item.quantity}</span>
                    <div class="item-info">
                        <div class="item-header">
                            <span class="item-name">${escapeHtml(displayName)}</span>
                        </div>
                        <div class="item-meta">#${escapeHtml(item.orderNumber || '')}</div>
                        ${modifiersHtml}
                        ${noteHtml}
                    </div>
                    <div class="served-action-group">
                        <button class="add-note-btn" aria-label="${this.translate('addNoteBtn')}" onclick="app.addItemNote('${item.id}', '${escapeHtml(displayName)}')" title="${this.translate('addNoteBtn')}"><span class="app-icon icon-menu" aria-hidden="true"></span></button>
                        <span class="status-badge ${statusClass}"><span class="app-icon ${statusIcon}" aria-hidden="true"></span>${statusLabel}</span>
                        ${item.status !== "cancelled" ? `<button class="reorder-action-btn" onclick="app.reorderItem('${escapeHtml(item.name)}')">${this.translate('orderAgainBtn')}</button>` : ''}
                    </div>
                `;
                el.style.setProperty('--row-index', pastContainer.children.length);
                pastContainer.appendChild(el);
            });
        }

    }

    reorderItem(name) {
        const item = this.menuItems.find(m => m.name === name);
        if (item) {
            const currentQty = this.cart[item.id] || 0;
            this.cart[item.id] = currentQty + 1;
            this.updateCartUI();
            this.jiggleCartNotification();

            this.switchView("menu");
            this.toggleCartDrawer(true);

            const translatedName = this.getItemName(item);
            const toast = document.getElementById("toast");
            toast.innerText = this.translate('addedToCartMsg').replace('{name}', translatedName);
            toast.className = "toast show";
            setTimeout(() => {
                toast.className = "toast";
            }, 2000);
        } else {
            this._showToast("Unable to find this dish in menu.");
        }
    }

    /**
     * Add/edit a note for an order item (post-order).
     * Stores locally and attempts to PATCH to server.
     */
    addItemNote(itemId, itemName) {
        const noteKey = `item_note_${itemId}`;
        const existingNote = localStorage.getItem(noteKey) || '';
        const promptText = this.translate('addNotePrompt');

        const note = prompt(promptText, existingNote);

        if (note === null) return; // User cancelled

        if (note.trim() === '') {
            localStorage.removeItem(noteKey);
        } else {
            localStorage.setItem(noteKey, note.trim());
        }

        // Attempt to send note to server (best-effort, non-blocking)
        this._sendItemNoteToServer(itemId, note.trim());

        // Show confirmation toast
        if (note.trim()) {
            const msg = this.translate('noteSavedMsg').replace('{name}', itemName);
            this._showToast(msg, 2500);
        }

        // Re-render order history to show updated note
        if (this.lastFetchedOrders && this.lastFetchedOrders.length > 0) {
            this.renderOrderHistory(this.lastFetchedOrders);
        }
    }

    async _sendItemNoteToServer(itemId, note) {
        // Try Supabase first
        if (this.supabase) {
            try {
                const { error } = await this.supabase.rpc('update_customer_order_item_note', {
                    p_order_item_id: itemId,
                    p_note: note
                });
                if (!error) {
                    console.log(`[Note] Saved note for item ${itemId} to server`);
                    return;
                }
            } catch (e) {
                console.warn('[Note] Supabase PATCH failed, trying local:', e);
            }
        }

        // Fallback to local server
        if (this.isLocalServerAvailable && !window.ALPHAPOS_CONFIG?.isProduction) {
            try {
                await fetch(`${this.localServerURL}/v1/order-items/${itemId}/note`, {
                    method: 'PATCH',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ customer_note: note })
                });
                console.log(`[Note] Saved note for item ${itemId} to local server`);
            } catch (e) {
                console.warn('[Note] Local server PATCH also failed:', e);
            }
        }
    }

    startStatusPolling() {
        // Debounce helper to prevent rapid-fire fetches from multiple Realtime events
        this._debouncedFetchHistory = this._debounce(() => {
            if (this.currentView === "status") {
                this.fetchOrderHistory({ showLoading: false });
            } else {
                this.updateStatusTabBadgeCount();
            }
        }, 1500);

        // Live WSS via supabaseRealtimeUrl (api host); poll remains as fallback.
        this.setupCustomerRealtime();

        // Realtime is primary. Polling only repairs missed websocket events and
        // validates the session; do not re-download nested order data every 10s.
        if (this.pollingInterval) {
            clearInterval(this.pollingInterval);
        }
        this.pollingInterval = setInterval(async () => {
            if (document.hidden) return;

            const now = Date.now();
            // Session changes normally arrive via Realtime. Keep a 60s fallback.
            if (this.sessionToken && now - this._lastSessionCheckAt >= 60000) {
                this._lastSessionCheckAt = now;
                const isActive = await this.verifySessionWithServer(this.sessionToken);
                if (!isActive) {
                    console.warn("Session closed by POS/server for table:", this.tableNumber);
                    this.sessionToken = null;
                    localStorage.removeItem(`sessionToken_T${this.tableNumber}`);

                    this.cart = {};
                    this.saveCartToStorage();

                    orderingSessionGate.markSessionClosed();

                    this.showBlockingState(
                        "sessionClosedTitle",
                        "sessionClosedDesc",
                        "pleaseOrderStaff"
                    );
                    return;
                }
            }

            // When Realtime is healthy, a five-minute reconciliation is enough.
            // If the channel is down, poll every 30s until it reconnects.
            const reconciliationMs = this._realtimeLive ? 300000 : 30000;
            if (now - this._lastHistoryRefreshAt >= reconciliationMs) {
                if (this.currentView === "status") {
                    this.fetchOrderHistory({ showLoading: false });
                } else {
                    this.updateStatusTabBadgeCount();
                }
            }
        }, 30000);

        if (this._statusVisibilityHandler) {
            document.removeEventListener('visibilitychange', this._statusVisibilityHandler);
        }
        this._statusVisibilityHandler = () => {
            if (!document.hidden && this.sessionToken) {
                if (this.currentView === "status") this.fetchOrderHistory({ showLoading: false });
                else this.updateStatusTabBadgeCount();
            }
        };
        document.addEventListener('visibilitychange', this._statusVisibilityHandler);
    }

    /**
     * Debounce utility: Returns a function that delays execution by `delay` ms.
     * If called again before delay expires, previous call is cancelled.
     */
    _debounce(fn, delay) {
        let timeoutId = null;
        return function(...args) {
            clearTimeout(timeoutId);
            timeoutId = setTimeout(() => fn.apply(this, args), delay);
        };
    }

    async updateStatusTabBadgeCount() {
        if (!this.sessionToken) return;
        let success = false;
        let ordersData = [];

        if (this.supabase) {
            try {
                const { data: sessionData, error: sessionError } = await this.supabase
                    .from('table_sessions')
                    .select('*')
                    .eq('table_number', this.tableNumber)
                    .eq('session_token', this.sessionToken)
                    .eq('is_active', 1)
                    .maybeSingle();

                if (sessionError || !sessionData) {
                    throw new Error("No active Supabase session found");
                }

                const { data: ords, error: ordersError } = await this.supabase
                    .from('orders')
                    .select('*, order_items(*)')
                    .eq('session_token', this.sessionToken);

                if (!ordersError) {
                    ordersData = ords;
                    success = true;
                }
            } catch (e) {
                console.error("Supabase error updating status tab badge count, falling back to local server:", e);
            }
        }

        if (!success && this.isLocalServerAvailable) {
            try {
                const params = new URLSearchParams({ table_number: this.tableNumber, session_token: this.sessionToken });
                const res = await fetch(`${this.localServerURL}/v1/orders?${params}`);
                if (res.ok) {
                    ordersData = await res.json();
                    success = true;
                }
            } catch (localErr) {
                console.error("Local server error fetching orders for badge:", localErr);
            }
        }

        if (success) {
            let activeCookingCount = 0;
            ordersData.forEach(order => {
                const items = order.order_items || order.items || [];
                items.forEach(item => {
                    const status = (item.status || "cooking").toLowerCase();
                    if (status === "pending" || status === "cooking" || status === "preparing" || status === "ready") {
                        activeCookingCount += item.quantity;
                    }
                });
            });
            const badgeEl = document.getElementById("statusTabBadge");
            if (activeCookingCount > 0) {
                badgeEl.innerText = activeCookingCount;
                badgeEl.classList.remove("hide");
            } else {
                badgeEl.classList.add("hide");
            }
        }
    }

    async sendServiceRequest(type) {
        const serviceKeyMap = {
            'Bill (Cash)': 'payCash',
            'Bill (Card)': 'payCard',
            'Bill (QR)': 'payQR',
            'Ice/Water': 'getWater',
            'Extra Utensils': 'utensils',
            'General Help': 'callStaffBtn'
        };
        const displayType = this.translate(serviceKeyMap[type] || type);

        // Show loading status modal
        this._showStatusModal(this.translate("callingStaff"), this.translate("callingStaffDesc"), false);

        let success = false;

        if (this.supabase) {
            try {
                const reqId = crypto.randomUUID
                    ? crypto.randomUUID()
                    : (() => 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, c => {
                        const r = crypto.getRandomValues(new Uint8Array(1))[0] % 16;
                        return (c === 'x' ? r : (r & 0x3 | 0x8)).toString(16);
                    }))();

                const { error } = await this.supabase.rpc('create_customer_service_request', {
                    p_request_type: type,
                    p_idempotency_key: reqId
                });

                if (error) throw error;
                success = true;
            } catch (error) {
                console.error("Supabase failed to submit service request, falling back to local server:", error);
            }
        }

        if (!success && this.isLocalServerAvailable && !window.ALPHAPOS_CONFIG?.isProduction) {
            try {
                const res = await fetch(`${this.localServerURL}/v1/requests`, {
                    method: "POST",
                    headers: { "Content-Type": "application/json" },
                    body: JSON.stringify({
                        table_number: this.tableNumber,
                        request_type: type,
                        merchant_id: this.merchantId,
                        branch_code: this.branchCode
                    })
                });
                if (!res.ok) throw new Error("Local server failed to post service request");
                success = true;
            } catch (localErr) {
                console.error("Local server failed to post service request:", localErr);
            }
        }

        if (success) {
            const btnNotification = document.getElementById("activeRequestNotification");
            const btnRequestType = document.getElementById("activeRequestType");

            if (btnRequestType && btnNotification) {
                btnRequestType.innerText = displayType;
                btnNotification.classList.remove("hide");

                if (this._serviceRequestTimeout) clearTimeout(this._serviceRequestTimeout);
                this._serviceRequestTimeout = setTimeout(() => {
                    btnNotification.classList.add("hide");
                }, 10000);
            }

            // Show success status modal
            this._showStatusModal(
                this.translate("staffCalledSuccess"),
                `${this.translate("staffCalled")}: ${displayType}. ${this.translate("staffCalledSuccessDesc")}`,
                true
            );

            setTimeout(() => {
                this._hideStatusModal();
            }, 2000);
        } else {
            this._hideStatusModal();
            this._showToast(this.translate('serviceCallFailed'), 5000);
        }
    }

    /**
     * Submits order to kitchen (requires active table session; staff confirms before kitchen).
     */
    async submitOrder() {
        if (this._submitInProgress) return;
        this._submitInProgress = true;

        // Block after payment / session close (not GPS/Wi-Fi).
        if (!orderingSessionGate.canOrder()) {
            this._showToast(this.translate(
                "orderingBlockedSession",
                "This table session is closed. Please scan the QR code again if you need to order."
            ));
            this._submitInProgress = false;
            return;
        }

        // Revalidate at checkout: cached pages/QR tokens may outlive the table session.
        if (!this.sessionToken || !(await this.verifySessionWithServer(this.sessionToken))) {
            this.showQrInvalidError();
            this._submitInProgress = false;
            return;
        }

        const btn = document.getElementById("submitOrderBtn");
        const btnText = btn.querySelector(".btn-text");
        const spinner = btn.querySelector(".btn-spinner");
        const warning = document.getElementById("btnWarningText");

        if (warning) {
            warning.classList.add("hide");
            warning.removeAttribute("role");
        }

        btn.classList.add("disabled");
        btn.setAttribute("disabled", "true");
        btnText.innerText = this.translate("sendingOrder");
        spinner.classList.remove("hide");

        // Show sending order status modal
        this._showStatusModal(this.translate("sendingOrder"), this.translate("sendingOrderDesc"), false);

        const generateUUID = () => {
            if (typeof crypto !== 'undefined' && crypto.randomUUID) {
                return crypto.randomUUID();
            }
            return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {
                const r = crypto.getRandomValues(new Uint8Array(1))[0] % 16;
                const v = c === 'x' ? r : (r & 0x3 | 0x8);
                return v.toString(16);
            });
        };

        const attemptKey = `alphapos-order-attempt:${this.sessionToken}`;
        const fingerprint = JSON.stringify([this.tableNumber, this.sessionToken, this.cart]);
        let attempt;
        try { attempt = JSON.parse(sessionStorage.getItem(attemptKey)); } catch (_) {}
        const orderId = attempt?.fingerprint === fingerprint ? attempt.orderId : generateUUID();
        this._lastOrderId = orderId;
        const now = new Date();
        const yyyy = now.getFullYear();
        const mm = String(now.getMonth() + 1).padStart(2, '0');
        const dd = String(now.getDate()).padStart(2, '0');
        // Use 5-digit random number to prevent duplicate key conflicts under the 20-char VARCHAR limit (e.g. ORD-20260623-12345 is 18 chars)
        const rand = Math.floor(10000 + Math.random() * 90000);
        const orderNum = attempt?.fingerprint === fingerprint
            ? attempt.orderNum
            : `ORD-${yyyy}${mm}${dd}-${rand}`;
        const idempotencyKey = attempt?.fingerprint === fingerprint && attempt?.idempotencyKey
            ? attempt.idempotencyKey
            : generateUUID();
        sessionStorage.setItem(attemptKey, JSON.stringify({ fingerprint, orderId, orderNum, idempotencyKey }));

        const orderItems = [];
        Object.keys(this.cart).forEach(cartKey => {
            const cartItem = this.cart[cartKey];
            if (!cartItem) return;

            let itemId = cartKey;
            let qty = cartItem;
            let selectedModifiers = [];
            let notes = "";

            if (typeof cartItem === 'object') {
                itemId = cartItem.itemId;
                qty = cartItem.quantity;
                selectedModifiers = cartItem.selectedModifiers || [];
                notes = cartItem.notes || "";
            }

            const item = this.menuItems.find(m => m.id === itemId);
            if (!item) return;

            const orderItemId = generateUUID();

            let modifierPriceSum = 0;
            selectedModifiers.forEach(m => {
                modifierPriceSum += parseFloat(m.price || 0);
            });

            const mappedModifiers = selectedModifiers.map(m => ({
                id: generateUUID(),
                order_item_id: orderItemId,
                modifier_id: m.id,
                price: m.price,
                merchant_id: this.merchantId
            }));

            // Supabase fk_order_items_menu_item constraint references menu_items(id) which is of type TEXT.
            // Short-key identifiers (e.g. "isan1") exist in menu_items(id) on Supabase, so they are valid.
            // Pass item.id directly to avoid setting it to null.
            const safeItemId = item.id;

            orderItems.push({
                id: orderItemId,
                order_id: orderId,
                item_name: item.name,
                price: item.price + modifierPriceSum,
                quantity: qty,
                // Web items start as 'pending' so the POS "pending self-orders"
                // approval banner surfaces them. Staff approval on the iPad/iPhone
                // promotes them to 'cooking' AND fires the kitchen print — nothing
                // is sent to the kitchen or printed until that confirmation.
                status: 'pending',
                item_id: safeItemId,
                merchant_id: this.merchantId,
                notes: notes,
                modifiers: mappedModifiers
            });
        });

        const { subtotal, discount, serviceCharge, tax, total } = this.calculateTotals();
        let success = false;
        let submissionError = null;

        if (this.supabase) {
            try {
                const orderPayload = {
                        id: orderId,
                        order_number: orderNum,
                        table_number: this.tableNumber,
                        total: total,
                        subtotal: subtotal,
                        discount: discount || 0,
                        tax: tax,
                        service_charge: serviceCharge,
                        status: 'pending',
                        // Web orders must be reviewed by staff on the iPad/iPhone
                        // before any kitchen ticket prints. order_source flags the
                        // channel; is_staff_confirmed stays false until the POS
                        // approval banner is tapped.
                        order_source: 'web',
                        is_staff_confirmed: false,
                        session_token: this.sessionToken,
                        guest_count: this.selectedGuestCount === '8+' ? 8 : parseInt(this.selectedGuestCount),
                        merchant_id: this.merchantId,
                        branch_id: this.branchId,
                        idempotency_key: idempotencyKey,
                        created_at: new Date().toISOString()
                    };

                const itemsToInsert = orderItems.map(item => ({
                    id: item.id,
                    order_id: item.order_id,
                    item_name: item.item_name,
                    quantity: item.quantity,
                    price: item.price,
                    status: item.status,
                    item_id: item.item_id,
                    merchant_id: item.merchant_id,
                    notes: item.notes
                }));

                const modifiersToInsert = [];
                orderItems.forEach(item => {
                    if (item.modifiers && item.modifiers.length > 0) {
                        item.modifiers.forEach(m => {
                            modifiersToInsert.push({
                                id: m.id,
                                order_item_id: m.order_item_id,
                                modifier_id: m.modifier_id,
                                price: m.price,
                                merchant_id: m.merchant_id
                            });
                        });
                    }
                });

                // One PostgreSQL transaction: order, items and modifiers commit together.
                const { error: orderErr } = await this.supabase.rpc('create_customer_order', {
                    p_order: orderPayload,
                    p_items: itemsToInsert,
                    p_modifiers: modifiersToInsert
                });
                if (orderErr) throw orderErr;

                success = true;
                console.log("Supabase order submission succeeded.");

                // Push is now handled reliably by a database trigger/webhook on orders INSERT.
            } catch (sbErr) {
                submissionError = sbErr;
                console.error("Supabase order submission failed:", JSON.stringify(sbErr));
            }
        }

        if (!success) {
            this._hideStatusModal();
            const failureState = classifyOrderFailure(submissionError);
            const isSessionClosed = failureState === 'session-closed';
            const messageKey = isSessionClosed ? 'orderingBlockedSession' : 'orderSubmitUncertain';
            const fallback = isSessionClosed
                ? 'This table session is closed. Scan the QR code at your table again, or ask a staff member for help.'
                : 'We could not confirm whether your order was received. Check Order Status or ask staff before trying again; a retry is protected from duplicates.';
            const message = this.translate(messageKey, fallback);

            if (warning) {
                warning.textContent = message;
                warning.classList.remove("hide");
                warning.setAttribute("role", "alert");
            }
            this._showToast(message, 8000);
            if (isSessionClosed) {
                orderingSessionGate.markSessionClosed();
            } else {
                // Retrying reuses attemptKey/idempotencyKey, so an uncertain
                // response cannot create a second order.
                btn.classList.remove("disabled");
                btn.removeAttribute("disabled");
            }
            btnText.innerText = this.translate("sendToKitchen");
            spinner.classList.add("hide");
            this._submitInProgress = false;
            return;
        }

        if (success) {
            sessionStorage.removeItem(attemptKey);
            if (warning) warning.classList.add("hide");
            console.log("Order saved successfully:", orderNum);

            btnText.innerText = this.translate("sendToKitchen");
            spinner.classList.add("hide");

            // Show success status modal
            this._showStatusModal(
                this.translate('orderSentSuccess').replace('{num}', orderNum),
                this.translate('orderSuccessDesc'),
                true
            );

            setTimeout(() => {
                this._hideStatusModal();
            }, 2000);

            this.cart = {};
            this.renderMenuItems();
            this.updateCartUI();
            this.toggleCartDrawer(false);

            // Save order to reorder history
            reorderHistory.saveOrder({
                id: orderId,
                orderNumber: orderNum,
                tableNumber: this.tableNumber,
                items: orderItems,
                total: total,
                status: 'pending',
                createdAt: new Date().toISOString()
            });

            // Show estimated wait time after successful order 
            this.showWaitTime();

            // Prompt for push notifications (if not already granted)
            this._promptPushAfterOrder();

            // Earn loyalty points for this order
            if (loyaltySystem.isLoggedIn && loyaltySystem.config?.loyalty_enabled) {
                loyaltySystem.earnPointsForOrder(orderId, total);
            }
        }

        this._submitInProgress = false;
    }

    /**
     * Show the Order Progress Tracker panel for a given order ID.
     */
    showOrderTracker(orderId) {
        if (!orderId) {
            orderId = this._lastOrderId;
        }
        if (!orderId) {
            console.warn('[OrderTracker] No order ID to track');
            return;
        }

        // Destroy previous tracker if any
        if (this._orderTracker) {
            this._orderTracker.destroy();
        }

        this._orderTracker = new OrderTracker();
        this._orderTracker.init(orderId, this.supabase, {
            translate: (key, fallback) => this.translate(key, fallback),
            merchantId: this.merchantId,
            localServerURL: this.localServerURL
        });

        // Show the panel
        const panel = document.getElementById('orderTrackerPanel');
        if (panel) {
            panel.classList.remove('hidden');
            // Render the tracker
            setTimeout(() => {
                this._orderTracker.render('orderTrackerContent');
            }, 100);
        }
    }

    /**
     * Hide the Order Progress Tracker panel.
     */
    hideOrderTracker() {
        const panel = document.getElementById('orderTrackerPanel');
        if (panel) {
            panel.classList.add('hidden');
        }
        if (this._orderTracker) {
            this._orderTracker.destroy();
            this._orderTracker = null;
        }
    }

    /**
     * Show estimated wait time after order submission.
     * Stores lastOrderId and triggers tracker display.
     */
    showWaitTime() {
        if (!this._lastOrderId) return;

        // Auto-show the tracker after a brief delay (let success modal dismiss)
        setTimeout(() => {
            this.showOrderTracker(this._lastOrderId);
        }, 2500);
    }

    /**
     * Trigger the customer feedback form.
     * Called when:
     * - Order status changes to "served" (via realtime)
     * - User manually clicks "Leave Feedback" button
     */
    triggerFeedback(orderId) {
        if (!this.feedbackSystem) return;

        const oid = orderId || this._lastOrderId || null;
        const tableNum = this.tableNumber || null;
        const session = this.sessionToken || null;

        // Delay slightly so it doesn't interrupt the user mid-action
        setTimeout(() => {
            this.feedbackSystem.showFeedbackForm(oid, tableNum, session);
        }, 1000);
    }

    /**
     * Called when a realtime order update shows status = "served"
     */
    _onOrderServed(orderId) {
        this.triggerFeedback(orderId);
    }

    async loadPromotions() {
        let promoData = [];

        // 1. Try to fetch from Supabase
        if (this.supabase) {
            try {
                const { data, error } = await this.supabase
                    .from('promotions')
                    .select('*')
                    .eq('is_active', 1)
                    .eq('is_deleted', 0);
                if (!error && data && data.length > 0) {
                    promoData = data.filter(p => this.isPromotionCurrentlyVisible(p));
                }
            } catch (e) {
                console.warn("Failed to fetch promotions from Supabase, trying local server:", e);
            }
        }

        // 2. If empty/failed, try local python server
        if (promoData.length === 0 && this.isLocalServerAvailable) {
            try {
                const res = await fetch(`${this.localServerURL}/v1/promotions`);
                if (res.ok) {
                    const data = await res.json();
                    promoData = data.filter(p => p.isActive && !p.isDeleted && this.isPromotionCurrentlyVisible(p));
                }
            } catch (e) {
                console.warn("Failed to fetch promotions from local server:", e);
            }
        }

        this._activePromotions = promoData || [];
        this.renderPromotions(promoData);
        if (this.cart && Object.keys(this.cart).length > 0) {
            this.updateCartUI();
        }
    }

    isPromotionCurrentlyVisible(promo) {
        const now = Date.now();
        const startValue = promo.starts_at || promo.startsAt;
        const endValue = promo.ends_at || promo.endsAt;
        if (startValue && Date.parse(startValue) > now) return false;
        if (endValue && Date.parse(endValue) < now) return false;
        return true;
    }

    renderPromotions(promotions) {
        const slider = document.getElementById("promotionsSlider");
        const indicatorsContainer = document.getElementById("promoIndicators");
        if (!slider || !indicatorsContainer) return;

        slider.innerHTML = "";
        indicatorsContainer.innerHTML = "";

        // Default culinary cover assets (reliable fallback when merchant has no promotions/covers)
        const defaultCoverVideo = "https://player.vimeo.com/external/435674703.sd.mp4?s=7f773cdccf1a0e784534f5263a232f3c64e5ba79&profile_id=139&oauth2_token_id=57447761";
        const defaultCoverImage = "https://images.unsplash.com/photo-1555396273-367ea4eb4db5?auto=format&fit=crop&w=1200&q=80";

        if (!promotions || promotions.length === 0) {
            console.log("No promotions to display, using merchant cover or default media fallback.");
            const slide = document.createElement("div");
            slide.className = "promo-slide active";
            const configuredCover = this.merchantSettings.web_cover_url || this.merchantSettings.webCoverUrl || '';
            const configuredType = this.merchantSettings.web_cover_media_type || this.merchantSettings.webCoverMediaType || '';
            const videoItem = (this.menuItems || []).find(item => item.videoUrl);
            const imageItem = (this.menuItems || []).find(item => item.imageUrl);
            
            const coverMedia = configuredCover || videoItem?.videoUrl || defaultCoverVideo;
            const coverType = configuredCover
                ? (configuredType === 'video' ? 'video' : 'image')
                : (coverMedia.includes('.mp4') || coverMedia.includes('vimeo') ? 'video' : 'image');
            const merchantName = this.merchantDisplayName || 'Restaurant';
            
            const createCoverFallback = () => {
                const img = document.createElement('img');
                img.className = 'merchant-cover-image';
                img.src = defaultCoverImage;
                img.alt = merchantName;
                return img;
            };

            // Always include a dark gradient placeholder background behind the media
            const placeholderBg = document.createElement("div");
            placeholderBg.className = "promo-placeholder-bg";
            slide.appendChild(placeholderBg);

            if (coverMedia && coverType === 'video') {
                const video = document.createElement('video');
                video.className = 'merchant-cover-video';
                video.autoplay = true;
                video.muted = true;
                video.defaultMuted = true;
                video.loop = true;
                video.playsInline = true;
                video.preload = 'auto';
                video.setAttribute('autoplay', '');
                video.setAttribute('muted', '');
                video.setAttribute('loop', '');
                video.setAttribute('playsinline', '');
                video.setAttribute('webkit-playsinline', '');
                
                const resolvedSrc = resolvePromoMediaSrc(coverMedia, 'video/mp4');
                video.src = resolvedSrc;

                video.onerror = (err) => {
                    console.warn("Cover video failed to load, falling back to cover image:", err);
                    video.replaceWith(createCoverFallback());
                };
                slide.appendChild(video);
                
                const startPlay = () => {
                    video.play()?.catch(() => { /* Safari may wait for user gesture */ });
                };
                video.addEventListener('canplay', startPlay, { once: true });
                startPlay();
            } else if (coverMedia) {
                const img = document.createElement('img');
                img.className = 'merchant-cover-image';
                img.src = resolvePromoMediaSrc(coverMedia, 'image/jpeg');
                img.alt = merchantName;
                img.onerror = () => img.replaceWith(createCoverFallback());
                slide.appendChild(img);
            } else {
                slide.appendChild(createCoverFallback());
            }

            slider.appendChild(slide);

            if (this.promoCarouselInterval) {
                clearInterval(this.promoCarouselInterval);
                this.promoCarouselInterval = null;
            }
            this.currentSlideIdx = 0;
            this.totalSlides = 1;
            return;
        }

        promotions.forEach((promo, idx) => {
            const slide = document.createElement("div");
            slide.className = `promo-slide ${idx === 0 ? 'active' : ''}`;

            const placeholderBg = document.createElement("div");
            placeholderBg.className = "promo-placeholder-bg";
            slide.appendChild(placeholderBg);

            const imgData = promo.imageData || promo.image_data || promo.imageUrl || promo.image_url;
            const mediaType = promo.mediaType || promo.media_type || "image";
            if (imgData && mediaType === "video") {
                const video = document.createElement("video");
                video.className = "merchant-cover-video";
                video.autoplay = true;
                video.muted = true;
                video.defaultMuted = true;
                video.loop = true;
                video.playsInline = true;
                video.preload = "auto";
                video.setAttribute("autoplay", "");
                video.setAttribute("muted", "");
                video.setAttribute("loop", "");
                video.setAttribute("playsinline", "");
                video.setAttribute("webkit-playsinline", "");

                const resolvedSrc = resolvePromoMediaSrc(imgData, "video/mp4");
                const source = document.createElement("source");
                source.src = resolvedSrc;
                source.type = "video/mp4";
                video.appendChild(source);
                video.src = resolvedSrc;

                video.onerror = () => {
                    console.warn("Promo video failed to load:", String(video.src || "").slice(0, 120));
                    const img = document.createElement("img");
                    img.src = defaultCoverImage;
                    video.replaceWith(img);
                };
                slide.appendChild(video);
                video.play()?.catch(() => { /* autoplay may be blocked until gesture */ });
            } else if (imgData) {
                const img = document.createElement("img");
                img.className = "merchant-cover-image";
                img.src = resolvePromoMediaSrc(imgData, "image/jpeg");
                img.onerror = () => {
                    img.src = defaultCoverImage;
                };
                slide.appendChild(img);
            } else {
                const img = document.createElement("img");
                img.src = defaultCoverImage;
                img.alt = promo.title;
                slide.appendChild(img);
            }

            const overlay = document.createElement("div");
            overlay.className = "promo-overlay";
            const desc = promo.promoDescription || promo.promo_description || promo.description || "";
            const discountType = promo.discountType || promo.discount_type || "none";
            const discountValue = Number(promo.discountValue ?? promo.discount_value ?? 0);
            let badge = "";
            if (discountType === "percentage" && discountValue > 0) {
                badge = `<span class="promo-discount-badge">-${discountValue}%</span>`;
            } else if (discountType === "fixed" && discountValue > 0) {
                badge = `<span class="promo-discount-badge">-฿${discountValue}</span>`;
            } else if (discountType === "buy_x_get_y") {
                badge = `<span class="promo-discount-badge">Buy X Get Y</span>`;
            } else if (discountType === "bundle_price") {
                badge = `<span class="promo-discount-badge">Bundle</span>`;
            }
            overlay.innerHTML = `
                ${badge}
                <h3 class="promo-title">${escapeHtml(promo.title)}</h3>
                <p class="promo-desc">${escapeHtml(desc)}</p>
            `;
            slide.appendChild(overlay);
            slider.appendChild(slide);

            const indicator = document.createElement("span");
            indicator.className = `indicator ${idx === 0 ? 'active' : ''}`;
            indicator.onclick = () => this.goToSlide(idx);
            indicatorsContainer.appendChild(indicator);
        });

        this.currentSlideIdx = 0;
        this.totalSlides = promotions.length;

        this.startPromotionCarousel();
    }

    goToSlide(slideIdx) {
        const slides = document.querySelectorAll(".promo-slide");
        const indicators = document.querySelectorAll(".promo-indicators .indicator");
        if (slides.length === 0) return;

        slides[this.currentSlideIdx]?.classList.remove("active");
        indicators[this.currentSlideIdx]?.classList.remove("active");

        this.currentSlideIdx = (slideIdx + slides.length) % slides.length;
        slides[this.currentSlideIdx]?.classList.add("active");
        indicators[this.currentSlideIdx]?.classList.add("active");
    }

    startPromotionCarousel() {
        if (this.promoCarouselInterval) {
            clearInterval(this.promoCarouselInterval);
            this.promoCarouselInterval = null;
        }
        if (this.totalSlides <= 1) return;

        this.promoCarouselInterval = setInterval(() => {
            this.goToSlide(this.currentSlideIdx + 1);
        }, 4500);
    }

    /**
     * Opens product detail modal
     */
    openProductDetailModal(itemId) {
        const item = this.menuItems.find(m => m.id === itemId);
        if (!item) return;

        this.activeModalItemId = itemId;
        // Reset modal quantity to 1 each time modal opens
        this.modalQty = 1;

        // Reset special instructions textarea
        document.getElementById("specialInstructionsInput").value = "";

        // Set content
        const modal = document.getElementById("productDetailModal");
        const titleEl = document.getElementById("modalProductTitle");
        const descEl = document.getElementById("modalProductDesc");
        const priceEl = document.getElementById("modalProductPrice");
        const imageEl = document.getElementById("modalProductImage");
        const addBtn = document.getElementById("modalAddBtn");

        titleEl.innerText = this.getItemName(item);
        descEl.innerText = this.getItemDesc(item);
        priceEl.innerText = `฿${item.price.toFixed(2)}`;

        // Resolve a safe image URL (relative paths → Supabase/CDN base; else local placeholder)
        const safeUrl = this.resolveMenuImageUrl(item.imageUrl);

        // Smooth image loading: show a skeleton shimmer, preload the image,
        // then fade it in once ready. Avoids the "flash / refresh" caused by
        // a background-image that only starts downloading when the modal opens.
        imageEl.style.backgroundImage = "";
        imageEl.classList.remove("is-loaded");
        imageEl.classList.add("is-loading");

        // Reuse a single <img> element inside the hero container.
        let heroImg = imageEl.querySelector(".modal-hero-img");
        if (!heroImg) {
            heroImg = document.createElement("img");
            heroImg.className = "modal-hero-img";
            heroImg.alt = "";
            heroImg.decoding = "async";
            imageEl.appendChild(heroImg);
        }
        // Reset so the fade-in re-triggers for the new image.
        heroImg.style.opacity = "";

        // Token guards against a stale (slow) image finishing after the user
        // has already opened a different item.
        const loadToken = (this._heroLoadToken = (this._heroLoadToken || 0) + 1);
        const applyImage = () => {
            if (loadToken !== this._heroLoadToken) return; // superseded
            heroImg.src = safeUrl;
            imageEl.classList.remove("is-loading");
            imageEl.classList.add("is-loaded");
        };
        const preloader = new Image();
        preloader.decoding = "async";
        preloader.onload = applyImage;
        preloader.onerror = () => {
            if (loadToken !== this._heroLoadToken) return;
            heroImg.onerror = null;
            heroImg.src = this.resolveMenuImageUrl('');
            imageEl.classList.remove("is-loading");
            imageEl.classList.add("is-loaded");
        };
        preloader.src = safeUrl;
        // If the browser already has it cached, onload may not fire — apply now.
        if (preloader.complete && preloader.naturalWidth > 0) applyImage();

        // Setup active state for add button
        const inCartQty = this.getItemTotalQuantity(itemId);
        if (inCartQty > 0) {
            addBtn.innerText = this.translate('addMore').replace('{qty}', inCartQty);
        } else {
            addBtn.innerText = this.translate('addToOrder');
        }

        document.getElementById("specialInstructionsInput").placeholder = this.translate("specialInstructionsPlaceholder");

        // Render modifier options
        const modalModifiersSection = document.getElementById("modalModifiersSection");
        modalModifiersSection.innerHTML = "";
        modalModifiersSection.classList.add("hide");

        if (this.modifiersConfig && this.modifiersConfig.links) {
            const linkedGroupIds = this.modifiersConfig.links
                .filter(l => l.menu_item_id === itemId)
                .map(l => l.modifier_group_id);

            const linkedGroups = this.modifiersConfig.groups
                .filter(g => linkedGroupIds.includes(g.id));

            if (linkedGroups.length > 0) {
                modalModifiersSection.classList.remove("hide");

                linkedGroups.forEach(group => {
                    const groupContainer = document.createElement("div");
                    groupContainer.className = "modifier-group-container";
                    groupContainer.dataset.groupId = group.id;
                    groupContainer.dataset.min = group.min_selection || 0;
                    groupContainer.dataset.max = group.max_selection || 0;

                    const groupHeader = document.createElement("div");
                    groupHeader.className = "modifier-group-header";

                    const groupTitle = document.createElement("div");
                    groupTitle.className = "modifier-group-title";
                    groupTitle.innerText = this.translate('modifier_group_' + group.name, group.name);

                    const groupSubtitle = document.createElement("div");
                    groupSubtitle.className = "modifier-group-subtitle";

                    const min = parseInt(group.min_selection || 0);
                    const max = parseInt(group.max_selection || 0);
                    if (min > 0 && max > 0) {
                        if (min === max) {
                            groupSubtitle.innerText = this.translate('selectExactly').replace('{min}', min);
                        } else {
                            groupSubtitle.innerText = this.translate('selectRange').replace('{min}', min).replace('{max}', max);
                        }
                    } else if (max > 0) {
                        groupSubtitle.innerText = this.translate('selectUpTo').replace('{max}', max);
                    } else if (min > 0) {
                        groupSubtitle.innerText = this.translate('selectAtLeast').replace('{min}', min);
                    } else {
                        groupSubtitle.innerText = this.translate('optional');
                    }

                    groupHeader.appendChild(groupTitle);
                    groupHeader.appendChild(groupSubtitle);
                    groupContainer.appendChild(groupHeader);

                    const optionsList = document.createElement("div");
                    optionsList.className = "modifier-options-list";

                    const groupMods = this.modifiersConfig.modifiers
                        .filter(m => m.modifier_group_id === group.id && m.is_available !== 0);

                    groupMods.forEach(mod => {
                        const optionItem = document.createElement("div");
                        optionItem.className = "modifier-option-item";
                        optionItem.dataset.modifierId = mod.id;
                        optionItem.dataset.price = mod.extra_price || 0;
                        optionItem.dataset.name = mod.name;

                        const inputClass = max === 1 ? "modifier-radio" : "modifier-checkbox";

                        optionItem.innerHTML = `
                            <div class="modifier-option-label">
                                <span class="${inputClass}"></span>
                                <span>${escapeHtml(this.translate('modifier_' + mod.name, mod.name))}</span>
                            </div>
                            <div class="modifier-option-price">+฿${parseFloat(mod.extra_price || 0).toFixed(2)}</div>
                        `;

                        optionItem.addEventListener("click", () => {
                            this.toggleModifierSelection(optionItem, groupContainer, max);
                        });

                        optionsList.appendChild(optionItem);
                    });

                    groupContainer.appendChild(optionsList);
                    modalModifiersSection.appendChild(groupContainer);
                });
            }
        }

        // Set initial modal price display
        this.updateModalPriceDisplay();

        // Show Modal with animation
        modal.classList.add("active");
        this.setActiveModal(modal);

        const cardEl = document.querySelector(`[data-item-id="${itemId}"]`);
        if (cardEl) {
            cardEl.classList.add('pressed');
            setTimeout(() => cardEl.classList.remove('pressed'), 200);
        }
    }

    toggleModifierSelection(optionItem, groupContainer, max) {
        if (max === 1) {
            const options = groupContainer.querySelectorAll(".modifier-option-item");
            options.forEach(opt => {
                if (opt !== optionItem) {
                    opt.classList.remove("selected");
                }
            });
            optionItem.classList.toggle("selected");
        } else {
            const selectedCount = groupContainer.querySelectorAll(".modifier-option-item.selected").length;
            const isCurrentlySelected = optionItem.classList.contains("selected");

            if (!isCurrentlySelected && max > 0 && selectedCount >= max) {
                this._showToast(this.translate("validationMax").replace("{max}", max));
                return;
            }
            optionItem.classList.toggle("selected");
        }

        this.updateModalPriceDisplay();
    }

    updateModalPriceDisplay() {
        if (!this.activeModalItemId) return;
        const item = this.menuItems.find(m => m.id === this.activeModalItemId);
        if (!item) return;

        let basePrice = item.price;
        let modsPrice = 0;

        const selectedOptions = document.querySelectorAll("#modalModifiersSection .modifier-option-item.selected");
        selectedOptions.forEach(opt => {
            modsPrice += parseFloat(opt.dataset.price || 0);
        });

        const qty = this.modalQty || 1;
        const unitPrice = basePrice + modsPrice;
        const totalPrice = unitPrice * qty;
        document.getElementById("modalProductPrice").innerText = `฿${totalPrice.toFixed(2)}`;

        // Update qty stepper display
        const qtyValEl = document.getElementById("modalQtyVal");
        const qtyDecEl = document.getElementById("modalQtyDec");
        if (qtyValEl) qtyValEl.textContent = qty;
        if (qtyDecEl) qtyDecEl.disabled = qty <= 1;

        // Update add button text
        const addBtn = document.getElementById("modalAddBtn");
        if (addBtn) {
            const inCartQty = this.getItemTotalQuantity(this.activeModalItemId);
            if (inCartQty > 0) {
                addBtn.innerText = this.translate('addMore').replace('{qty}', inCartQty);
            } else {
                addBtn.innerText = this.translate('addToOrder');
            }
        }
    }

    changeModalQty(delta) {
        const current = this.modalQty || 1;
        this.modalQty = Math.max(1, current + delta);
        this.updateModalPriceDisplay();
    }

    closeProductDetailModal() {
        const modal = document.getElementById("productDetailModal");
        modal.classList.remove("active");
        this.activeModalItemId = null;
        this.modalQty = 1;
        if (this._activeModal === modal) this.setActiveModal(null);
    }

    addProductFromModal() {
        if (!this.activeModalItemId) return;
        const itemId = this.activeModalItemId;

        // Get selected modifiers
        const selectedModifiers = [];
        const selectedOptions = document.querySelectorAll("#modalModifiersSection .modifier-option-item.selected");

        // Validate modifier group constraints
        let validationFailed = false;
        const groupContainers = document.querySelectorAll("#modalModifiersSection .modifier-group-container");
        groupContainers.forEach(container => {
            const min = parseInt(container.dataset.min || 0);
            const selectedInGroup = container.querySelectorAll(".modifier-option-item.selected").length;
            const groupName = container.querySelector(".modifier-group-title").innerText;

            if (selectedInGroup < min) {
                this._showToast(this.translate("validationMin").replace("{min}", min).replace("{group}", groupName));
                validationFailed = true;
            }
        });

        if (validationFailed) return;

        selectedOptions.forEach(opt => {
            selectedModifiers.push({
                id: opt.dataset.modifierId,
                name: opt.dataset.name,
                price: parseFloat(opt.dataset.price || 0)
            });
        });

        const notes = document.getElementById("specialInstructionsInput").value || "";

        const qty = this.modalQty || 1;
        this.addToCart(itemId, qty, selectedModifiers, notes);
        this.closeProductDetailModal();
    }

    // ============================================================
    // WAIT TIME WIDGET
    // ============================================================

    /**
     * Show estimated wait time widget (called after order submission)
     */
    showWaitTime() {
        // Initialize widget with app context
        waitTimeWidget.init({
            supabaseClient: this.supabase,
            merchantId: this.merchantId,
            localServerURL: this.localServerURL,
            translateFn: (key, fallback) => this.translate(key, fallback)
        });

        // Render full widget in status view
        const fullContainer = document.getElementById('waitTimeFullContainer');
        if (fullContainer) {
            fullContainer.classList.remove('hidden');
            waitTimeWidget.renderFull('waitTimeFullContainer');
        }

        // Render mini badge in header
        const miniContainer = document.getElementById('waitTimeMiniContainer');
        if (miniContainer) {
            miniContainer.classList.remove('hidden');
            waitTimeWidget.renderMini('waitTimeMiniContainer');
        }
    }

    /**
     * Hide wait time widget (called when order is served/completed)
     */
    hideWaitTime() {
        waitTimeWidget.destroy();

        const fullContainer = document.getElementById('waitTimeFullContainer');
        if (fullContainer) fullContainer.classList.add('hidden');

        const miniContainer = document.getElementById('waitTimeMiniContainer');
        if (miniContainer) miniContainer.classList.add('hidden');
    }

    // ============================================================
    // PUSH NOTIFICATIONS
    // ============================================================

    /**
     * Initialize push notification manager
     */
    async _initPushNotifications() {
        try {
            await pushManager.init();
            // Listen for service worker messages (notification clicks)
            if ('serviceWorker' in navigator) {
                navigator.serviceWorker.addEventListener('message', (event) => {
                    if (event.data && event.data.type === 'PUSH_NOTIFICATION_CLICK') {
                        const orderId = event.data.orderId;
                        if (orderId) {
                            this.showOrderTracker(orderId);
                        }
                    }
                });
            }
        } catch (err) {
            console.warn('[Push] Init error:', err);
        }
    }

    /**
     * Prompt user for push notifications after order (with delay for UX)
     */
    _promptPushAfterOrder() {
        if (!pushManager.isSupported) return;
        if (pushManager.permission === 'granted') {
            // Already granted — just subscribe for this order
            pushManager.subscribe(this._lastOrderId);
            return;
        }
        if (pushManager.permission === 'denied') return;

        // Show custom prompt after 3 seconds (let order confirmation sink in)
        setTimeout(() => {
            pushManager.showPermissionPrompt();
        }, 3000);
    }

    /**
     * Called when user clicks "Enable Notifications" in custom prompt
     */
    async _enablePushNotifications() {
        const granted = await pushManager.requestPermission();
        if (granted && this._lastOrderId) {
            pushManager.subscribe(this._lastOrderId);
            this._showToast(this.translate('pushOrderConfirmed', 'Notifications enabled!'), { type: 'success', duration: 3000 });
        }
    }

    /**
     * Called when user clicks "Maybe Later" in push prompt
     */
    _dismissPushPrompt() {
        pushManager.hidePermissionPrompt();
    }

    // ============================================================
    // REORDER HISTORY
    // ============================================================

    /**
     * Initialize reorder history system
     */
    initReorderHistory() {
        reorderHistory.init({
            translate: (key, fallback) => this.translate(key, fallback),
            menuItems: this.menuItems,
            addToCart: (itemId, qty, mods, notes) => this.addToCart(itemId, qty, mods, notes),
            showToast: (msg) => this._showToast(msg),
            supabaseClient: this.supabase,
            merchantId: this.merchantId
        });

        // Expose singleton for onclick handlers
        window._reorderHistory = reorderHistory;

        // Render quick reorder widget
        reorderHistory.renderQuickReorder('reorderWidgetContainer');
    }

    /**
     * Show the full order history panel
     */
    showOrderHistory() {
        const panel = document.getElementById('orderHistoryPanel');
        if (!panel) return;
        panel.classList.remove('hidden');
        reorderHistory.updateMenuItems(this.menuItems);
        reorderHistory.renderHistoryView('orderHistoryContent');
    }

    /**
     * Hide the order history panel
     */
    hideOrderHistory() {
        const panel = document.getElementById('orderHistoryPanel');
        if (panel) panel.classList.add('hidden');
    }

    // ========================
    // Reservation System
    // ========================
    showReservation() {
        reservationSystem.showReservationForm();
    }

    hideReservation() {
        reservationSystem.hideReservationForm();
    }
}

// Instantiate app globally
window.app = new AlphaPosApp();
window.orderingSessionGate = orderingSessionGate;
orderingSessionGate.init();

// Wait for config.js (window.ALPHAPOS_CONFIG) to be available before init
// This is needed because config.js is injected by Cloudflare Worker as a separate script tag
// and may load after the bundled JS in some browsers
async function waitForConfig(maxWaitMs = 5000) {
    const start = Date.now();
    while (!window.ALPHAPOS_CONFIG && Date.now() - start < maxWaitMs) {
        await new Promise(resolve => setTimeout(resolve, 50));
    }
    if (!window.ALPHAPOS_CONFIG) {
        console.warn('[AlphaPos] config.js not loaded within timeout');
    }
    return !!window.ALPHAPOS_CONFIG;
}

async function bootAlphaPosApp() {
    if (window.__alphaposBooted) return;
    window.__alphaposBooted = true;

    try {
        if ('scrollRestoration' in history) {
            history.scrollRestoration = 'manual';
        }
        window.scrollTo(0, 0);

        await waitForConfig();
        const cfg = window.ALPHAPOS_CONFIG || {};
        window.app.applyRuntimeConfig(cfg);

        const isProd = !!(cfg && cfg.isProduction);
        const hasConfig = window.app.hasValidRuntimeConfig(cfg);
        // In production, missing config is a hard fail with retry UI (avoid blank ordering).
        // Local/dev can continue with local-server fallbacks.
        if (isProd && !hasConfig) {
            console.error('[AlphaPos] Missing or invalid runtime config in production');
            window.app.showBlockingState(
                "configMissingTitle",
                "configMissingDesc",
                "pleaseOrderStaff",
                { showRetry: true }
            );
            window.__alphaposBooted = false;
            return;
        }

        await window.app.init();
    } catch (err) {
        console.error('[AlphaPos] Boot failed:', err);
        window.__alphaposBooted = false;
        try {
            window.app.showBlockingState(
                "configMissingTitle",
                "configMissingDesc",
                "pleaseOrderStaff",
                { showRetry: true }
            );
        } catch (_) { /* ignore */ }
    }
}

// Avoid missing init when the module loads after DOMContentLoaded already fired
if (document.readyState === 'loading') {
    window.addEventListener('DOMContentLoaded', () => { bootAlphaPosApp(); });
} else {
    bootAlphaPosApp();
}
