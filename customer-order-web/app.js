import { translations } from './js/i18n.js';
import { defaultMenuItems } from './js/data.js';

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

function createSafeElement(tag, attrs = {}, textContent = '') {
    const el = document.createElement(tag);
    Object.entries(attrs).forEach(([k, v]) => el.setAttribute(k, v));
    if (textContent) el.textContent = textContent;
    return el;
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


        // Categories List
        this.categories = [
            { id: "mains", name: "🍛 Main Dishes" },
            { id: "appetizers", name: "🍲 Appetizers" },
            { id: "drinks", name: "🥤 Beverages" },
            { id: "desserts", name: "🥭 Desserts" }
        ];

        // App States
        this.currentCategory = "mains";
        this.searchQuery = "";
        this.cart = {}; // Format: { cartKey: { itemId, quantity, selectedModifiers: [], notes } }
        this.modifiersConfig = { groups: [], modifiers: [], links: [] };
        this.tableNumber = "1"; // Default fallback
        this.sessionToken = null;
        this.selectedGuestCount = 2; // Default
        this.currentOnboardingStep = 1;
        this.currentView = "menu";
        
        // Developer panel toggles
        this.isDevPanelMinimized = true;

        // Configuration (loaded from config.js or environment)
        const cfg = window.ALPHAPOS_CONFIG || {};
        this.supabaseUrl = cfg.supabaseUrl || 'https://sdmtkixrqkmwcpwoisrg.supabase.co';
        this.supabaseKey = cfg.supabaseKey || 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNkbXRraXhycWttd2Nwd29pc3JnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA4NDIxNjAsImV4cCI6MjA5NjQxODE2MH0.rjLwVE0ShXIFoT0k982XO_lVCQMsA4uTKMW1Su-NUws';
        this.supabase = null;
        this.merchantId = cfg.merchantId || '163350b0-056d-4d5e-b5d4-24e7aac5ab6d';
        this._submitInProgress = false;
        
        this.lastFetchedOrders = [];
        this.currentLanguage = 'th';

        // Multi-Language Translation Dictionary
        ;
    }

    // Retry wrapper with exponential backoff
    async _fetchWithRetry(fn, maxRetries = 2) {
        let lastError;
        for (let attempt = 0; attempt <= maxRetries; attempt++) {
            try {
                return await fn();
            } catch (err) {
                lastError = err;
                if (attempt < maxRetries) {
                    await new Promise(r => setTimeout(r, Math.pow(2, attempt) * 200));
                }
            }
        }
        throw lastError;
    }

    // Generic helper: try Supabase first, fall back to local Python server
    async _fetchWithFallback({ supabaseFn, localUrl, localOptions = {}, transform }) {
        let success = false;
        let result = null;

        if (this.supabase && this.supabaseKey) {
            try {
                result = await this._fetchWithRetry(supabaseFn);
                if (result != null) {
                    if (transform) result = transform(result);
                    success = true;
                }
            } catch (err) {
                console.warn('Supabase failed, trying local server:', err);
            }
        }

        if (!success && localUrl) {
            try {
                const res = await this._fetchWithRetry(async () => {
                    const r = await fetch(localUrl, {
                        headers: { 'Content-Type': 'application/json' },
                        ...localOptions
                    });
                    if (!r.ok) throw new Error(`HTTP ${r.status}`);
                    return r;
                });
                result = await (localOptions.parseJson !== false ? res.json() : res.text());
                if (transform) result = transform(result);
                success = true;
            } catch (err) {
                console.error('Local server also failed:', err);
            }
        }

        return { success, data: result };
    }

    _showToast(message, duration = 3000) {
        const toast = document.getElementById("toast");
        if (!toast) return;
        toast.textContent = message;
        toast.className = "toast show";
        setTimeout(() => { toast.className = "toast"; }, duration);
    }

    _showStatusModal(title, desc, isSuccess = false) {
        const modal = document.getElementById("statusModal");
        const spinner = document.getElementById("statusModalSpinner");
        const successIcon = document.getElementById("statusModalSuccessIcon");
        const titleEl = document.getElementById("statusModalTitle");
        const descEl = document.getElementById("statusModalDesc");

        if (!modal || !spinner || !successIcon || !titleEl || !descEl) return;

        titleEl.innerText = title;
        descEl.innerText = desc;

        if (isSuccess) {
            spinner.classList.add("hide");
            successIcon.classList.remove("hide");
        } else {
            spinner.classList.remove("hide");
            successIcon.classList.add("hide");
        }

        modal.classList.remove("hide");
        modal.offsetHeight; // trigger layout reflow
        modal.classList.add("show");
    }

    _hideStatusModal() {
        const modal = document.getElementById("statusModal");
        if (!modal) return;
        modal.classList.remove("show");
        setTimeout(() => {
            modal.classList.add("hide");
        }, 350);
    }

    saveCartToStorage() {
        if (this.tableNumber) {
            localStorage.setItem(`cart_T${this.tableNumber}`, JSON.stringify(this.cart));
        }
    }

    loadCartFromStorage() {
        if (this.tableNumber) {
            const saved = localStorage.getItem(`cart_T${this.tableNumber}`);
            if (saved) {
                try {
                    this.cart = JSON.parse(saved);
                } catch (e) {
                    console.error("Failed to parse saved cart:", e);
                    this.cart = {};
                }
            } else {
                this.cart = {};
            }
        }
    }

    unsubscribeRealtimeChannels() {
        if (this.supabase && this.realtimeChannels) {
            this.realtimeChannels.forEach(ch => {
                try {
                    this.supabase.removeChannel(ch);
                } catch (e) {
                    console.error("Failed to remove channel:", e);
                }
            });
            this.realtimeChannels = [];
        }
    }

    /**
     * GUEST COUNT PERSISTENCE (SessionStorage)
     */
     
    setGuestCount(count) {
        // Parse guest count (handle "8+" special case)
        this.selectedGuestCount = count === '8+' ? 8 : parseInt(count);
        
        // Persist to SessionStorage
        sessionStorage.setItem('alphapos_guest_count', this.selectedGuestCount);
        sessionStorage.setItem('alphapos_guest_count_timestamp', Date.now());
        
        console.log(`[Guest Count] Set to ${this.selectedGuestCount} persons`);
        
        // Update UI
        this.renderInteractiveSeats();
        this.updateTableVisualization();
    }

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

    /**
     * SEAT VISUALIZATION
     */
     
    renderInteractiveSeats() {
        const container = document.getElementById('interactiveSeatsContainer');
        if (!container) return;
        
        container.innerHTML = ''; // Clear existing
        
        const TOTAL_SEATS = 8;  // Show up to 8 seats visually
        const guestCount = this.selectedGuestCount || 2;
        
        // Create seat grid
        for (let i = 1; i <= TOTAL_SEATS; i++) {
            const seat = document.createElement('div');
            seat.className = 'interactive-seat';
            seat.setAttribute('data-seat-number', i);
            
            // Color seats based on occupancy status
            if (i <= guestCount) {
                // Active seat (guest assigned)
                seat.classList.add('seat-occupied');
                seat.style.opacity = '1';
                seat.style.cursor = 'pointer';
                seat.title = `Seat ${i} (Occupied)`;
                
                // Optional: add visual indicator
                const occupant = document.createElement('span');
                occupant.className = 'seat-occupant';
                occupant.textContent = '👤';
                seat.appendChild(occupant);
                
            } else {
                // Vacant seat (gray out)
                seat.classList.add('seat-vacant');
                seat.style.opacity = '0.4';
                seat.style.pointerEvents = 'none';
                seat.style.cursor = 'not-allowed';
                seat.style.backgroundColor = '#d3d3d3'; // Light gray
                seat.title = 'No guest assigned';
            }
            
            container.appendChild(seat);
        }
        
        console.log(`[Seats] Rendered ${TOTAL_SEATS} seats (${guestCount} occupied)`);
    }

    updateTableVisualization() {
        const tableLabel = document.getElementById('tableLabelNum');
        const guestCount = this.selectedGuestCount || 2;
        
        if (tableLabel) {
            tableLabel.textContent = guestCount;
        }
    }

    validateGuestCount() {
        const guestCount = this.getGuestCount();
        
        if (!guestCount) {
            return {
                valid: false,
                message: '❌ Please select number of guests before ordering'
            };
        }
        
        if (guestCount < 1 || guestCount > 100) {
            return {
                valid: false,
                message: '❌ Invalid guest count (must be 1-100)'
            };
        }
        
        return {
            valid: true,
            guestCount: guestCount,
            message: `✅ Order for ${guestCount} guest${guestCount > 1 ? 's' : ''}`
        };
    }

    /**
     * Initializes the Web Application
     */
    async init() {
        this.parseURLParams();
        this.loadCartFromStorage();
        
        window.addEventListener("beforeunload", () => {
            this.unsubscribeRealtimeChannels();
        });
        
        // Initialize Supabase Client with merchant ID custom header
        this.supabase = (window.supabase && this.supabaseKey) ? window.supabase.createClient(this.supabaseUrl, this.supabaseKey, {
            global: {
                headers: {
                    'x-merchant-id': this.merchantId
                }
            }
        }) : null;

        await this.checkOrOpenSession();
        await this.loadMenuFromServer();
        await this.loadModifiersConfig();
        await this.loadPromotions();
        this.renderCategories();
        this.renderMenuItems();
        this.updateCartUI();
        
        // Start status polling
        this.startStatusPolling();
        
        // Initialize Theme from localStorage (Default: Light Mode)
        const savedTheme = localStorage.getItem("theme") || "light";
        const body = document.body;
        const iconEl = document.querySelector("#themeToggleBtn .theme-toggle-icon");
        
        if (savedTheme === "dark") {
            body.classList.add("dark-theme");
            if (iconEl) iconEl.innerText = "☀️";
        } else {
            body.classList.remove("dark-theme");
            if (iconEl) iconEl.innerText = "🌙";
        }

        // Add dev-panel minimized state class initially
        document.getElementById("devPanel").classList.add("minimized");
        
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

        // ── Scroll-hide header: hide promo banner on scroll down, restore on scroll up ──
        this._initScrollHideHeader();

        // Developer auto-onboard check for headless testing
        this.autoOnboardIfRequested();
    }

    // ─────────────────────────────────────────────────────────────
    // Scroll-Hide Header
    // Hide promo banner when user scrolls down > threshold.
    // Restore when scrolled back near top.
    // ─────────────────────────────────────────────────────────────
    _initScrollHideHeader() {
        const HIDE_THRESHOLD  = 60;   // px scrolled down to trigger hide
        const SHOW_THRESHOLD  = 20;   // px from top to restore
        const body            = document.body;
        let   lastScrollY     = 0;
        let   ticking         = false;

        const onScroll = (scrollTop) => {
            if (ticking) return;
            ticking = true;

            requestAnimationFrame(() => {
                const goingDown = scrollTop > lastScrollY;
                const nearTop   = scrollTop <= SHOW_THRESHOLD;

                if (nearTop) {
                    body.classList.remove("header-scrolled-up");
                } else if (goingDown && scrollTop > HIDE_THRESHOLD) {
                    body.classList.add("header-scrolled-up");
                } else if (!goingDown) {
                    body.classList.remove("header-scrolled-up");
                }

                lastScrollY = Math.max(0, scrollTop);
                ticking     = false;
            });
        };

        const menuView = document.getElementById("menuView");
        if (menuView) {
            menuView.addEventListener("scroll", () => onScroll(menuView.scrollTop), { passive: true });
        }
        window.addEventListener("scroll", () => onScroll(window.scrollY), { passive: true });
    }

    async autoOnboardIfRequested() {
        const urlParams = new URLSearchParams(window.location.search);
        if (urlParams.get('autoOnboard') !== 'true') return;
        console.log("[AutoOnboard] Started automatic onboarding...");
        
        // Wait for the button to become enabled
        let btn1 = document.getElementById("btnOnboardingNext1");
        let attempts = 0;
        while ((!btn1 || btn1.disabled) && attempts < 100) {
            await new Promise(r => setTimeout(r, 100));
            btn1 = document.getElementById("btnOnboardingNext1");
            attempts++;
        }
        
        if (btn1 && !btn1.disabled && this.currentOnboardingStep === 1) {
            console.log("[AutoOnboard] Step 1: Clicking proceed...");
            btn1.click();
        } else {
            console.log("[AutoOnboard] Step 1: Button not enabled or step mismatch.");
            return;
        }
        
        // Wait for step 1 transition animation to complete
        await new Promise(r => setTimeout(r, 800));
        
        if (this.currentOnboardingStep === 2) {
            console.log("[AutoOnboard] Step 2: Selecting 4 guests and starting session...");
            this.setGuestCount(4);
            await new Promise(r => setTimeout(r, 500));
            const btn2 = document.getElementById("startOrderBtn");
            if (btn2) {
                console.log("[AutoOnboard] Step 2: Clicking start order button...");
                btn2.click();
            }
        }

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

    async checkOrOpenSession() {
        const urlParams = new URLSearchParams(window.location.search);
        const tableParam = urlParams.get('table');

        // Block access if table parameter is missing
        if (!tableParam) {
            const wizard = document.getElementById("onboardingWizard");
            wizard.classList.add("active");
            document.getElementById("onboardingStep1").classList.add("active");

            document.getElementById("verifyTitle").innerText = "⚠️ ไม่พบรหัสโต๊ะอาหาร";
            document.getElementById("verifyDesc").innerText = "กรุณาสแกน QR Code บนโต๊ะอาหารของคุณเพื่อเริ่มสั่งอาหาร";

            const nextBtn = document.getElementById("btnOnboardingNext1");
            if (nextBtn) {
                nextBtn.classList.add("disabled");
                nextBtn.disabled = true;
                nextBtn.innerHTML = "<span>กรุณาสแกน QR Code</span>";
            }
            return;
        }

        // Always show the onboarding wizard overlay initially
        const wizard = document.getElementById("onboardingWizard");
        wizard.classList.add("active");
        
        document.getElementById("welcomeTableNum").innerText = this.tableNumber;
        document.getElementById("tableLabelNum").innerText = this.tableNumber;
        
        // Verify token (either URL parameter or localStorage)
        const cachedToken = localStorage.getItem(`sessionToken_T${this.tableNumber}`);
        const tokenToVerify = this.sessionToken || cachedToken;
        
        if (tokenToVerify) {
            // Verify if session token is still active on the server
            const isActive = await this.verifySessionWithServer(tokenToVerify);
            if (isActive) {
                this.sessionToken = tokenToVerify;
                localStorage.setItem(`sessionToken_T${this.tableNumber}`, tokenToVerify);
                
                // Directly bypass onboarding to menu with a fast checkmark screen
                document.getElementById("onboardingStep1").classList.remove("active");
                document.getElementById("onboardingStep3").classList.add("active");
                document.getElementById("loadingStatusText").innerText = "Welcome back! Resuming session...";
                
                const progressFill = document.getElementById("setupProgressFill");
                setTimeout(() => {
                    progressFill.style.width = "100%";
                }, 50);
                
                setTimeout(() => {
                    wizard.style.opacity = "0";
                    setTimeout(() => {
                        wizard.classList.remove("active");
                        wizard.style.opacity = "";
                        this.animateMenuEntrance();
                    }, 400);
                }, 1000);
                
                console.log("Resumed session verified by server:", this.sessionToken);
                return;
            } else {
                // Clear invalid/expired session
                this.sessionToken = null;
                localStorage.removeItem(`sessionToken_T${this.tableNumber}`);
            }
        }
        
        // No valid active session -> Start Step 1
        this.currentOnboardingStep = 1;
        document.getElementById("onboardingStep1").classList.add("active");
        
        // Hook location verifier to update Step 1 status box
        if (window.locationVerifier) {
            const originalUpdateBanner = window.locationVerifier.updateBanner.bind(window.locationVerifier);
            window.locationVerifier.updateBanner = (status, title, description) => {
                originalUpdateBanner(status, title, description);
                this.updateOnboardingVerification(status, title, description);
            };
            // Re-run verification to capture initial state on wizard
            window.locationVerifier.runVerification();
        }
    }

    async verifySessionWithServer(token) {
        let success = false;
        let isActive = false;
        
        if (this.supabase) {
            try {
                const { data, error } = await this.supabase
                    .from('table_sessions')
                    .select('*')
                    .eq('table_number', this.tableNumber)
                    .eq('session_token', token)
                    .eq('is_active', 1)
                    .maybeSingle();
                
                if (!error && data) {
                    isActive = true;
                    success = true;
                }
            } catch (e) {
                console.error("Failed to verify session with Supabase, trying local server fallback:", e);
            }
        }
        
        if (!success) {
            try {
                const res = await fetch("/v1/sessions");
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

    updateOnboardingVerification(status, title, description) {
        const box = document.querySelector(".verification-status-box");
        const titleEl = document.getElementById("verifyTitle");
        const descEl = document.getElementById("verifyDesc");
        const nextBtn = document.getElementById("btnOnboardingNext1");
        
        if (!box || !titleEl || !descEl || !nextBtn) return;
        
        box.className = "verification-status-box " + status;
        titleEl.innerText = title;
        descEl.innerText = description;
        
        if (status === "checking") {
            nextBtn.classList.add("disabled");
            nextBtn.disabled = true;
        } else {
            nextBtn.classList.remove("disabled");
            nextBtn.disabled = false;
        }
    }

    nextOnboardingStep() {
        if (this.currentOnboardingStep === 1) {
            document.getElementById("onboardingStep1").classList.remove("active");
            document.getElementById("onboardingStep2").classList.add("active");
            this.currentOnboardingStep = 2;
            this.renderInteractiveSeats();
        }
    }

    prevOnboardingStep() {
        if (this.currentOnboardingStep === 2) {
            document.getElementById("onboardingStep2").classList.remove("active");
            document.getElementById("onboardingStep1").classList.add("active");
            this.currentOnboardingStep = 1;
        }
    }

    renderInteractiveSeats() {
        const container = document.getElementById("interactiveSeatsContainer");
        const textEl = document.getElementById("tableLabelNum");
        if (!container) return;
        
        container.innerHTML = "";
        textEl.innerText = this.tableNumber;
        
        const count = this.selectedGuestCount === '8+' ? 8 : parseInt(this.selectedGuestCount);
        
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
            seat.innerHTML = "🍽️";
            container.appendChild(seat);
        }
    }

    setGuestCount(count) {
        this.selectedGuestCount = count;
        const pills = document.querySelectorAll(".guest-pill");
        pills.forEach(pill => {
            if (pill.innerText === String(count)) {
                pill.classList.add("active");
            } else {
                pill.classList.remove("active");
            }
        });
        console.log("Selected guests count:", this.selectedGuestCount);
        this.renderInteractiveSeats();
    }

    async confirmGuestCount() {
        const btn = document.getElementById("startOrderBtn");
        btn.disabled = true;
        btn.querySelector("span").innerText = "Starting session...";
        
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
                const res = await fetch("/v1/sessions/open", {
                    method: "POST",
                    headers: { "Content-Type": "application/json" },
                    body: JSON.stringify({
                        table_number: this.tableNumber,
                        guest_count: guestCount
                    })
                });
                if (!res.ok) throw new Error("Local server failed to open session");
                const resData = await res.json();
                sessionToken = resData.session_token;
                success = true;
            }
            
            this.sessionToken = sessionToken;
            localStorage.setItem(`sessionToken_T${this.tableNumber}`, this.sessionToken);
            
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
            btn.disabled = false;
            btn.querySelector("span").innerText = this.translate("startOrdering");
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
                    this.supabase.from('modifiers').select('*').eq('is_deleted', false),
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
        
        if (!success) {
            try {
                const res = await fetch("/v1/modifiers-config");
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

    async loadMenuFromServer() {
        let success = false;
        if (this.supabase) {
            try {
                const { data, error } = await this.supabase
                    .from('menu_items')
                    .select('*');
                
                if (error) throw error;
                if (data && data.length > 0) {
                    this.menuItems = data.map(item => ({
                        id: item.id,
                        name: item.name,
                        desc: item.description,
                        price: parseFloat(item.price),
                        category: item.category,
                        emoji: item.emoji || "🍛",
                        imgClass: item.img_class || "img-main",
                        imageUrl: item.image_url || item.imageUrl || ""
                    }));
                    success = true;
                }
            } catch (error) {
                console.error("Failed to load menu from Supabase, trying local server fallback...", error);
            }
        }
        
        if (!success) {
            try {
                const res = await fetch("/v1/menu");
                if (res.ok) {
                    const data = await res.json();
                    if (data && data.length > 0) {
                        this.menuItems = data.map(item => ({
                            id: item.id,
                            name: item.name,
                            desc: item.desc || item.description,
                            price: parseFloat(item.price),
                            category: item.category,
                            emoji: item.emoji || "🍛",
                            imgClass: item.imgClass || item.img_class || "img-main",
                            imageUrl: item.image_url || item.imageUrl || ""
                        }));
                        success = true;
                        console.log("Loaded menu from local server fallback.");
                    }
                }
            } catch (localErr) {
                console.error("Failed to load menu from local server:", localErr);
            }
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
            if (iconEl) iconEl.innerText = "☀️";
            localStorage.setItem("theme", "dark");
        } else {
            if (iconEl) iconEl.innerText = "🌙";
            localStorage.setItem("theme", "light");
        }
    }

    /**
     * Switch UI language and dynamically update all texts
     */
    switchLanguage(lang) {
        this.currentLanguage = lang;
        localStorage.setItem("lang", lang);

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
        if (window.locationVerifier) {
            window.locationVerifier.runVerification();
        }

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
        const table = urlParams.get('table');
        const merchant = urlParams.get('merchant');
        const token = urlParams.get('token');

        // Validate table number: must be a positive integer
        if (table && /^\d+$/.test(table)) {
            this.tableNumber = table;
        }

        if (token) {
            this.sessionToken = token;
        }
        
        // Only allow merchant override if a valid config exists
        let savedMerchant = localStorage.getItem('active_merchant_id');
        if (savedMerchant === '00000000-0000-0000-0000-000000000000') {
            savedMerchant = '';
        }
        // Prefer saved merchant over URL param to prevent IDOR
        this.merchantId = savedMerchant || (merchant && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(merchant) ? merchant : (window.ALPHAPOS_CONFIG?.merchantId || ''));
        if (this.merchantId) {
            localStorage.setItem('active_merchant_id', this.merchantId);
        }

        // Update Header Badge
        const badgeText = this.translate("tableBadgeText").replace("{num}", this.tableNumber);
        document.getElementById("tableBadge").querySelector(".table-text").innerText = badgeText;
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

        this.categories.forEach(category => {
            const tab = document.createElement("button");
            tab.className = `category-tab ${this.currentCategory === category.id ? 'active' : ''}`;
            tab.innerText = this.translate('category_' + category.id, category.name);
            tab.onclick = () => this.switchCategory(category.id);
            container.appendChild(tab);
        });
    }

    /**
     * Dynamic Menu rendering
     */
    renderMenuItems() {
        const grid = document.getElementById("menuGrid");
        grid.innerHTML = "";

        const query = this.searchQuery.trim().toLowerCase();
        const isSearching = query.length > 0;

        // Update Section Title
        const activeCategory = this.categories.find(c => c.id === this.currentCategory);
        const titleEl = document.getElementById("currentCategoryTitle");
        if (isSearching) {
            titleEl.innerText = this.translate('searchResults', `Search: "${this.searchQuery}"`);
        } else {
            titleEl.innerText = activeCategory ? this.translate('category_' + activeCategory.id, activeCategory.name) : this.translate('menuTab', "Menu");
        }

        // Filter items
        let itemsToRender;
        if (isSearching) {
            itemsToRender = this.menuItems.filter(item => {
                const name = (this.translate('item_' + item.id + '_name', item.name) || item.name).toLowerCase();
                const desc = (this.translate('item_' + item.id + '_desc', item.desc) || item.desc).toLowerCase();
                return name.includes(query) || desc.includes(query);
            });
        } else {
            itemsToRender = this.menuItems.filter(item => item.category === this.currentCategory);
        }

        // Show/hide empty state
        const emptyState = document.getElementById("searchEmptyState");
        if (emptyState) {
            emptyState.classList.toggle("visible", isSearching && itemsToRender.length === 0);
        }

        itemsToRender.forEach((item, index) => {
            const card = document.createElement("div");
            const inCartQty = this.getItemTotalQuantity(item.id);
            
            card.className = `menu-item-card ${inCartQty > 0 ? 'selected' : ''}`;
            card.style.animationDelay = `${index * 0.05}s`;
            card.setAttribute("onclick", `app.openProductDetailModal('${item.id}')`);

            const disabledAttr = inCartQty === 0 ? "disabled" : "";
            const disabledClass = inCartQty === 0 ? "disabled-btn" : "";
            const actionBtnHtml = `
                <div class="quantity-control" onclick="event.stopPropagation()">
                    <button class="qty-btn dec-btn ${disabledClass}" ${disabledAttr} onclick="app.updateCartQuantity('${item.id}', -1); event.stopPropagation();">-</button>
                    <span class="qty-value">${inCartQty}</span>
                    <button class="qty-btn inc-btn" onclick="app.updateCartQuantity('${item.id}', 1); event.stopPropagation();">+</button>
                </div>
            `;

            card.innerHTML = `
                <div class="menu-item-image-container" onclick="event.stopPropagation()">
                    <img class="menu-item-img" src="${escapeHtml(item.imageUrl || '')}" alt="${escapeHtml(item.name)}" onerror="this.onerror=null; this.src='https://images.unsplash.com/photo-1546069901-ba9599a7e63c?w=400&q=80';">
                    <div class="item-actions-hud">
                        ${actionBtnHtml}
                    </div>
                </div>
                <div class="menu-item-info">
                    <div class="menu-item-header">
                        <div class="menu-item-title">${escapeHtml(this.translate('item_' + item.id + '_name', item.name))}</div>
                        <div class="menu-item-desc">${escapeHtml(this.translate('item_' + item.id + '_desc', item.desc))}</div>
                    </div>
                    <div class="menu-item-price">฿${item.price.toFixed(2)}</div>
                </div>
            `;
            grid.appendChild(card);
        });
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
        this.renderMenuItems();
        this.updateCartUI();
        this.jiggleCartNotification();
    }

    /**
     * Updates cart item quantities (supports cartKey and itemId)
     */
    updateCartQuantity(cartKeyOrItemId, change) {
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

        this.renderMenuItems();
        this.updateCartUI();
    }

    /**
     * Calculate subtotal, service charges, vat, and total
     */
    calculateTotals() {
        let subtotal = 0;

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
                subtotal += (item.price + modifierPriceSum) * qty;
            }
        });

        const serviceCharge = subtotal * 0.10; // 10% Service Charge
        const tax = (subtotal + serviceCharge) * 0.07; // 7% VAT
        const total = subtotal + serviceCharge + tax;

        return { subtotal, serviceCharge, tax, total };
    }

    /**
     * Update Floating Cart and Drawer info
     */
    updateCartUI() {
        const { subtotal, serviceCharge, tax, total } = this.calculateTotals();
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
        document.getElementById("breakdownService").innerText = `฿${serviceCharge.toFixed(2)}`;
        document.getElementById("breakdownTax").innerText = `฿${tax.toFixed(2)}`;
        document.getElementById("breakdownTotal").innerText = `฿${total.toFixed(2)}`;

        // Render items inside drawer list
        this.renderDrawerCartList();

        // Show/hide floating cart bar
        const cartBar = document.getElementById("cartBar");
        if (totalItems > 0) {
            cartBar.classList.add("show");
        } else {
            cartBar.classList.remove("show");
            this.toggleCartDrawer(false); // Auto close drawer if cart emptied
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
            row.innerHTML = `
                <div class="cart-item-details">
                    <div class="cart-item-name">${escapeHtml(this.translate('item_' + item.id + '_name', item.name))}</div>
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
        } else {
            overlay.classList.remove("show");
        }
    }

    /**
     * Toggle Developer Panel expansion
     */
    toggleDevPanel() {
        const panel = document.getElementById("devPanel");
        const icon = document.getElementById("devToggleIcon");
        this.isDevPanelMinimized = !this.isDevPanelMinimized;

        if (this.isDevPanelMinimized) {
            panel.classList.add("minimized");
            icon.innerText = "▲";
        } else {
            panel.classList.remove("minimized");
            icon.innerText = "▼";
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
        this.currentView = viewName;
        
        // Switch active tabs
        document.querySelectorAll(".nav-tab").forEach(tab => tab.classList.remove("active"));
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
    }

    async fetchOrderHistory() {
        if (!this.sessionToken) return;
        
        let success = false;
        let formattedOrders = [];
        
        if (this.supabase) {
            try {
                const { data: sessionData, error: sessionError } = await this.supabase
                    .from('table_sessions')
                    .select('*')
                    .eq('table_number', this.tableNumber)
                    .eq('session_token', this.sessionToken)
                    .eq('is_active', 1)
                    .maybeSingle();
                    
                if (sessionError) throw sessionError;
                if (sessionData) {
                    const { data: ordersData, error: ordersError } = await this.supabase
                        .from('orders')
                        .select('*, order_items(*), payments(*)')
                        .eq('table_number', this.tableNumber)
                        .gte('created_at', sessionData.created_at)
                        .order('created_at', { ascending: true });
                        
                    if (ordersError) throw ordersError;
                    
                    formattedOrders = ordersData.map(order => {
                        const items = (order.order_items || []).map(item => ({
                            id: item.id,
                            name: item.item_name,
                            quantity: item.quantity,
                            price: item.price,
                            status: item.status,
                            item_id: item.item_id
                        }));
                        const payments = (order.payments || []).map(p => ({
                            id: p.id,
                            orderId: p.order_id,
                            amount: p.amount,
                            paymentMethod: p.payment_method,
                            createdAt: p.created_at
                        }));
                        return {
                            id: order.id,
                            orderNumber: order.order_number,
                            tableNumber: order.table_number,
                            total: order.total,
                            status: order.status,
                            createdAt: order.created_at,
                            items: items,
                            payments: payments
                        };
                    });
                    success = true;
                }
            } catch (error) {
                console.error("Supabase error fetching order history, falling back to local server:", error);
            }
        }
        
        if (!success) {
            try {
                const res = await fetch(`/v1/orders?table=${this.tableNumber}&token=${this.sessionToken}`);
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
            this.renderOrderHistory(formattedOrders);
        }
    }

    renderOrderHistory(orders) {
        const activeContainer = document.getElementById("activeOrdersList");
        const pastContainer = document.getElementById("pastOrdersList");
        const grandTotalEl = document.getElementById("sessionGrandTotal");
        const badgeEl = document.getElementById("statusTabBadge");
        
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
                if (status === "cooking" || status === "preparing" || status === "ready") {
                    activeItems.push({
                        orderNumber: order.orderNumber,
                        id: item.id,
                        name: item.name,
                        quantity: item.quantity,
                        price: item.price,
                        status: status
                    });
                    activeCookingCount += item.quantity;
                } else {
                    pastItems.push({
                        orderNumber: order.orderNumber,
                        id: item.id,
                        name: item.name,
                        quantity: item.quantity,
                        price: item.price,
                        status: status
                    });
                }
            });
        });
        
        grandTotalEl.innerText = `฿${grandTotal.toFixed(2)}`;
        
        if (activeCookingCount > 0) {
            badgeEl.innerText = activeCookingCount;
            badgeEl.classList.remove("hide");
        } else {
            badgeEl.classList.add("hide");
        }
        
        if (activeItems.length === 0) {
            activeContainer.innerHTML = `<div class="empty-state">${this.translate('noActiveItems')}</div>`;
        } else {
            activeItems.forEach(item => {
                const statusEmoji = item.status === "ready" ? "🛎️" : "🍳";
                const statusLabel = item.status === "ready" ? this.translate('readyStatus') : this.translate('cookingStatus');
                const statusClass = item.status === "ready" ? "ready" : "cooking";
                
                const matchedMenuItem = this.menuItems.find(m => m.name === item.name);
                const displayName = matchedMenuItem ? this.translate('item_' + matchedMenuItem.id + '_name', item.name) : item.name;

                const el = document.createElement("div");
                el.className = "status-item-card";
                el.innerHTML = `
                    <div class="item-info">
                        <div class="item-header">
                            <span class="item-name">${escapeHtml(displayName)}</span>
                            <span class="item-qty">× ${item.quantity}</span>
                        </div>
                        <div class="item-meta">${this.translate('orderLabel')}: ${escapeHtml(item.orderNumber || '')}</div>
                      </div>
                      <span class="status-badge ${statusClass}">${statusEmoji} ${statusLabel}</span>
                  `;
                activeContainer.appendChild(el);
            });
        }
        
        if (pastItems.length === 0) {
            pastContainer.innerHTML = `<div class="empty-state">${this.translate('noServedItems')}</div>`;
        } else {
            pastItems.forEach(item => {
                const statusEmoji = item.status === "cancelled" ? "❌" : "🍽️";
                const statusLabel = item.status === "cancelled" ? this.translate('cancelledStatus') : this.translate('servedStatus');
                const statusClass = item.status === "cancelled" ? "cancelled" : "served";
                
                const matchedMenuItem = this.menuItems.find(m => m.name === item.name);
                const displayName = matchedMenuItem ? this.translate('item_' + matchedMenuItem.id + '_name', item.name) : item.name;

                const el = document.createElement("div");
                el.className = "status-item-card served-item";
                el.innerHTML = `
                    <div class="item-info">
                        <div class="item-header">
                            <span class="item-name">${escapeHtml(displayName)}</span>
                            <span class="item-qty">× ${item.quantity}</span>
                        </div>
                        <div class="item-meta">${this.translate('orderLabel')}: ${escapeHtml(item.orderNumber || '')}</div>
                    </div>
                    <div class="served-action-group">
                        <span class="status-badge ${statusClass}">${statusEmoji} ${statusLabel}</span>
                        ${item.status !== "cancelled" ? `<button class="reorder-action-btn" onclick="app.reorderItem('${escapeHtml(item.name)}')">${this.translate('orderAgainBtn')}</button>` : ''}
                    </div>
                `;
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
            
            const translatedName = this.translate('item_' + item.id + '_name', item.name);
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

    startStatusPolling() {
        // Debounce helper to prevent rapid-fire fetches from multiple Realtime events
        this._debouncedFetchHistory = this._debounce(() => {
            if (this.currentView === "status") {
                this.fetchOrderHistory();
            } else {
                this.updateStatusTabBadgeCount();
            }
        }, 1500);
        
        this.realtimeChannels = [];
        
        if (this.supabase) {
            try {
                const ch1 = this.supabase
                    .channel('status-changes')
                    .on('postgres_changes', { event: '*', schema: 'public', table: 'order_items' }, payload => {
                        console.log("Realtime order item update received:", payload);
                        this._debouncedFetchHistory();
                    });
                ch1.subscribe();
                this.realtimeChannels.push(ch1);
                    
                const ch2 = this.supabase
                    .channel('orders-changes')
                    .on('postgres_changes', { event: '*', schema: 'public', table: 'orders' }, payload => {
                        console.log("Realtime order update received:", payload);
                        this._debouncedFetchHistory();
                    });
                ch2.subscribe();
                this.realtimeChannels.push(ch2);
                
                // Listen for table_sessions changes (detect session closure from iPad POS)
                const ch3 = this.supabase
                    .channel('session-changes')
                    .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'table_sessions' }, payload => {
                        console.log("Realtime session update received:", payload);
                        const newRecord = payload.new;
                        if (newRecord && newRecord.is_active === 0 && newRecord.table_number === this.tableNumber) {
                            // Session was closed by iPad POS — notify the customer
                            console.warn("Session closed by POS for table:", this.tableNumber);
                            this.sessionToken = null;
                            localStorage.removeItem(`sessionToken_T${this.tableNumber}`);
                            this.cart = {};
                            this.saveCartToStorage(); // Clear cart on session close
                            
                            const toast = document.getElementById("toast");
                            toast.innerText = "Your session has been closed by the staff. Thank you!";
                            toast.className = "toast show";
                            setTimeout(() => { toast.className = "toast"; }, 5000);
                        }
                    });
                ch3.subscribe();
                this.realtimeChannels.push(ch3);
                
                // Listen for menu_items changes (auto-reload when menu is updated)
                const ch4 = this.supabase
                    .channel('menu-changes')
                    .on('postgres_changes', { event: '*', schema: 'public', table: 'menu_items' }, payload => {
                        console.log("Realtime menu update received:", payload);
                        // Reload entire menu from server on any menu change
                        this.loadMenuFromServer().then(() => {
                            this.renderCategories();
                            this.renderMenuItems();
                            
                            const toast = document.getElementById("toast");
                            toast.innerText = "Menu has been updated!";
                            toast.className = "toast show";
                            setTimeout(() => { toast.className = "toast"; }, 3000);
                        });
                    });
                ch4.subscribe();
                this.realtimeChannels.push(ch4);
            } catch (err) {
                console.error("Failed to initialize Supabase realtime subscriptions:", err);
            }
        }
        
        // Setup a periodic check of session validity + fetching status
        if (this.pollingInterval) {
            clearInterval(this.pollingInterval);
        }
        this.pollingInterval = setInterval(async () => {
            // Check session validity periodically (critical for local server fallback)
            if (this.sessionToken) {
                const isActive = await this.verifySessionWithServer(this.sessionToken);
                if (!isActive) {
                    console.warn("Session closed by POS/server for table:", this.tableNumber);
                    this.sessionToken = null;
                    localStorage.removeItem(`sessionToken_T${this.tableNumber}`);
                    
                    const toast = document.getElementById("toast");
                    toast.innerText = "Your session has been closed by the staff. Thank you!";
                    toast.className = "toast show";
                    setTimeout(() => { toast.className = "toast"; }, 5000);
                    
                    // Show onboarding wizard again
                    const wizard = document.getElementById("onboardingWizard");
                    wizard.style.opacity = "";
                    wizard.style.transform = "";
                    wizard.classList.add("active");
                    document.getElementById("onboardingStep1").classList.add("active");
                    document.getElementById("onboardingStep2").classList.remove("active");
                    document.getElementById("onboardingStep3").classList.remove("active");
                    this.currentOnboardingStep = 1;
                    return;
                }
            }
            
            if (this.currentView === "status") {
                this.fetchOrderHistory();
            } else {
                this.updateStatusTabBadgeCount();
            }
        }, 10000);
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
                    .eq('table_number', this.tableNumber)
                    .gte('created_at', sessionData.created_at);
                    
                if (!ordersError) {
                    ordersData = ords;
                    success = true;
                }
            } catch (e) {
                console.error("Supabase error updating status tab badge count, falling back to local server:", e);
            }
        }
        
        if (!success) {
            try {
                const res = await fetch(`/v1/orders?table=${this.tableNumber}&token=${this.sessionToken}`);
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
                    if (status === "cooking" || status === "preparing" || status === "ready") {
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
                
                const { error } = await this.supabase
                    .from('service_requests')
                    .insert([{
                        id: reqId,
                        table_number: this.tableNumber,
                        request_type: type,
                        status: 'pending',
                        created_at: new Date().toISOString(),
                        merchant_id: this.merchantId
                    }]);
                    
                if (error) throw error;
                success = true;
            } catch (error) {
                console.error("Supabase failed to submit service request, falling back to local server:", error);
            }
        }
        
        if (!success) {
            try {
                const res = await fetch("/v1/requests", {
                    method: "POST",
                    headers: { "Content-Type": "application/json" },
                    body: JSON.stringify({
                        table_number: this.tableNumber,
                        request_type: type
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
     * Submits order to kitchen (Validates location first)
     */
    async submitOrder() {
        if (this._submitInProgress) return;
        this._submitInProgress = true;

        if (!window.locationVerifier.isValid) {
            this._showToast(this.translate("orderingBlockedPremises"));
            this._submitInProgress = false;
            return;
        }

        const btn = document.getElementById("submitOrderBtn");
        const btnText = btn.querySelector(".btn-text");
        const spinner = btn.querySelector(".btn-spinner");

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

        const orderId = generateUUID();
        const orderNum = `ORD-${Math.floor(1000 + Math.random() * 9000)}`;

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

            orderItems.push({
                id: orderItemId,
                order_id: orderId,
                item_name: item.name,
                price: item.price + modifierPriceSum,
                quantity: qty,
                status: 'cooking',
                item_id: item.id,
                merchant_id: this.merchantId,
                notes: notes,
                modifiers: mappedModifiers
            });
        });

        const { total } = this.calculateTotals();
        let success = false;

        if (this.supabase) {
            try {
                const { error: orderError } = await this.supabase
                    .from('orders')
                    .insert([{
                        id: orderId,
                        order_number: orderNum,
                        table_number: this.tableNumber,
                        total: total,
                        status: 'preparing',
                        session_token: this.sessionToken,
                        guest_count: this.selectedGuestCount === '8+' ? 8 : parseInt(this.selectedGuestCount),
                        created_at: new Date().toISOString(),
                        merchant_id: this.merchantId
                    }]);
                    
                if (orderError) throw orderError;
                
                const { error: itemsError } = await this.supabase
                    .from('order_items')
                    .insert(orderItems.map(item => {
                        const { modifiers, notes, ...dbItem } = item;
                        return dbItem;
                    }));
                    
                if (itemsError) throw itemsError;

                const allModifiersToInsert = [];
                orderItems.forEach(item => {
                    if (item.modifiers && item.modifiers.length > 0) {
                        allModifiersToInsert.push(...item.modifiers);
                    }
                });

                if (allModifiersToInsert.length > 0) {
                    const { error: modsError } = await this.supabase
                        .from('order_item_modifiers')
                        .insert(allModifiersToInsert);
                    if (modsError) throw modsError;
                }
                
                success = true;
            } catch (error) {
                console.error("Supabase order submission failed, falling back to local server:", error);
            }
        }

        if (!success) {
            try {
                const res = await fetch("/v1/orders", {
                    method: "POST",
                    headers: { "Content-Type": "application/json" },
                    body: JSON.stringify({
                        id: orderId,
                        orderNumber: orderNum,
                        tableNumber: this.tableNumber,
                        total: total,
                        status: 'preparing',
                        sessionToken: this.sessionToken,
                        guestCount: this.selectedGuestCount === '8+' ? 8 : parseInt(this.selectedGuestCount),
                        createdAt: new Date().toISOString(),
                        items: orderItems
                    })
                });
                if (!res.ok) throw new Error("Local server failed to post order");
                success = true;
            } catch (localErr) {
                console.error("Local order submission failed:", localErr);
                
                // Hide status modal and notify on error
                this._hideStatusModal();
                this._showToast(this.translate("orderSentFailed"), 5000);
                
                btn.classList.remove("disabled");
                btn.removeAttribute("disabled");
                btnText.innerText = this.translate("sendToKitchen");
                spinner.classList.add("hide");
                this._submitInProgress = false;
                return;
            }
        }

        if (success) {
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
        }

        this._submitInProgress = false;
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
                    promoData = data;
                }
            } catch (e) {
                console.warn("Failed to fetch promotions from Supabase, trying local server:", e);
            }
        }
        
        // 2. If empty/failed, try local python server
        if (promoData.length === 0) {
            try {
                const res = await fetch('/v1/promotions');
                if (res.ok) {
                    const data = await res.json();
                    promoData = data.filter(p => p.isActive && !p.isDeleted);
                }
            } catch (e) {
                console.warn("Failed to fetch promotions from local server:", e);
            }
        }
        
        this.renderPromotions(promoData);
    }

    renderPromotions(promotions) {
        const slider = document.getElementById("promotionsSlider");
        const indicatorsContainer = document.getElementById("promoIndicators");
        if (!slider || !indicatorsContainer) return;
        
        slider.innerHTML = "";
        indicatorsContainer.innerHTML = "";
        
        if (!promotions || promotions.length === 0) {
            console.log("No promotions to display, using fallback slide.");
            const slide = document.createElement("div");
            slide.className = "promo-slide active";
            slide.innerHTML = `
                <div class="promo-placeholder-bg"></div>
                <div class="promo-overlay">
                    <h3 class="promo-title" data-translate-key="welcomeTitle">${this.translate ? this.translate('welcomeTitle', 'ยินดีต้อนรับสู่ AlphaPos') : 'ยินดีต้อนรับสู่ AlphaPos'}</h3>
                    <p class="promo-desc" data-translate-key="welcomeDesc">${this.translate ? this.translate('welcomeDesc', 'สัมผัสเมนูแนะนำสูตรพิเศษ ปรุงรสอย่างประณีตเพื่อคุณ') : 'สัมผัสเมนูแนะนำสูตรพิเศษ ปรุงรสอย่างประณีตเพื่อคุณ'}</p>
                </div>
            `;
            slider.appendChild(slide);
            
            const indicator = document.createElement("span");
            indicator.className = "indicator active";
            indicatorsContainer.appendChild(indicator);
            
            this.currentSlideIdx = 0;
            this.totalSlides = 1;
            this.startPromotionCarousel();
            return;
        }
        
        promotions.forEach((promo, idx) => {
            const slide = document.createElement("div");
            slide.className = `promo-slide ${idx === 0 ? 'active' : ''}`;
            
            const imgData = promo.imageData || promo.image_data;
            if (imgData) {
                const img = document.createElement("img");
                img.src = imgData.startsWith("data:") ? imgData : `data:image/jpeg;base64,${imgData}`;
                img.alt = promo.title;
                slide.appendChild(img);
            } else {
                const placeholder = document.createElement("div");
                placeholder.className = "promo-placeholder-bg";
                slide.appendChild(placeholder);
            }
            
            const overlay = document.createElement("div");
            overlay.className = "promo-overlay";
            const desc = promo.promoDescription || promo.promo_description || "";
            overlay.innerHTML = `
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
        if (slides.length === 0 || indicators.length === 0) return;
        
        slides[this.currentSlideIdx].classList.remove("active");
        indicators[this.currentSlideIdx].classList.remove("active");
        
        this.currentSlideIdx = (slideIdx + slides.length) % slides.length;
        slides[this.currentSlideIdx].classList.add("active");
        indicators[this.currentSlideIdx].classList.add("active");
    }

    startPromotionCarousel() {
        if (this.promoCarouselInterval) {
            clearInterval(this.promoCarouselInterval);
        }
        
        if (this.totalSlides <= 1) return;
        
        this.promoCarouselInterval = setInterval(() => {
            this.goToSlide(this.currentSlideIdx + 1);
        }, 4000);
    }

    /**
     * Opens product detail modal
     */
    openProductDetailModal(itemId) {
        const item = this.menuItems.find(m => m.id === itemId);
        if (!item) return;

        this.activeModalItemId = itemId;
        
        // Reset special instructions textarea
        document.getElementById("specialInstructionsInput").value = "";

        // Set content
        const modal = document.getElementById("productDetailModal");
        const titleEl = document.getElementById("modalProductTitle");
        const descEl = document.getElementById("modalProductDesc");
        const priceEl = document.getElementById("modalProductPrice");
        const imageEl = document.getElementById("modalProductImage");
        const addBtn = document.getElementById("modalAddBtn");

        titleEl.innerText = this.translate('item_' + item.id + '_name', item.name);
        descEl.innerText = this.translate('item_' + item.id + '_desc', item.desc || "");
        priceEl.innerText = `฿${item.price.toFixed(2)}`;

        // Clear previous style / set background
        const safeUrl = item.imageUrl && (item.imageUrl.startsWith('http://') || item.imageUrl.startsWith('https://'))
            ? item.imageUrl
            : "https://images.unsplash.com/photo-1546069901-ba9599a7e63c?w=600&q=80";
        imageEl.style.backgroundImage = `url('${escapeHtml(safeUrl)}')`;
        imageEl.style.backgroundSize = "cover";
        imageEl.style.backgroundPosition = "center";

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
        
        const cardEl = Array.from(document.querySelectorAll('.menu-item-card')).find(card => card.getAttribute('onclick')?.includes(itemId));
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
                alert(this.translate("validationMax").replace("{max}", max));
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

        const totalPrice = basePrice + modsPrice;
        document.getElementById("modalProductPrice").innerText = `฿${totalPrice.toFixed(2)}`;
    }

    closeProductDetailModal() {
        const modal = document.getElementById("productDetailModal");
        modal.classList.remove("active");
        this.activeModalItemId = null;
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
                alert(this.translate("validationMin").replace("{min}", min).replace("{group}", groupName));
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

        this.addToCart(itemId, 1, selectedModifiers, notes);
        this.closeProductDetailModal();
    }
}

// Instantiate app globally
window.app = new AlphaPosApp();
window.addEventListener("DOMContentLoaded", () => window.app.init());
