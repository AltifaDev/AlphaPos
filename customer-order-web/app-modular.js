/**
 * AlphaPos — Modular Entry Point
 * 
 * Alternative to monolithic app.js. Uses ES modules.
 * To use: change index.html script src from "app.js" to "app-modular.js"
 * 
 * Architecture:
 *   app-core.js          → Class skeleton + utilities
 *   ├── onboarding.js    → Check-in wizard
 *   ├── menu-renderer.js → Menu display + filtering
 *   ├── cart-manager.js  → Cart state + UI
 *   ├── order-submission.js → Order creation + history
 *   ├── payment-handler.js  → Payment flow
 *   ├── service-requests.js → Staff calls
 *   ├── realtime-manager.js → WebSocket + polling
 *   └── theme-manager.js    → Theme + i18n
 *
 * Existing P0 modules (loaded independently):
 *   ├── order-tracker.js → Order progress timeline
 *   ├── allergen-filter.js → Allergen/dietary badges
 *   ├── feedback.js      → Customer rating
 *   └── wait-time.js     → Estimated wait time
 */

import { AlphaPosApp } from './js/app-core.js';

// P0 Feature modules (optional, load if available)
let OrderTracker, AllergenFilter, FeedbackSystem, WaitTimeWidget;
try { ({ OrderTracker } = await import('./js/order-tracker.js')); } catch(e) {}
try { ({ AllergenFilter } = await import('./js/allergen-filter.js')); } catch(e) {}
try { ({ FeedbackSystem } = await import('./js/feedback.js')); } catch(e) {}
try { ({ WaitTimeWidget } = await import('./js/wait-time.js')); } catch(e) {}

// ==========================================
// Initialize Application
// ==========================================
const app = new AlphaPosApp();

// Attach P0 feature instances
if (AllergenFilter) {
    app._allergenFilter = new AllergenFilter();
}
if (WaitTimeWidget) {
    app._waitTimeWidget = new WaitTimeWidget();
    app.showWaitTime = function() {
        if (this._waitTimeWidget && window.ALPHAPOS_CONFIG) {
            this._waitTimeWidget.init(this.supabase, window.ALPHAPOS_CONFIG.merchantId);
            this._waitTimeWidget.renderFull('waitTimeFullContainer');
            this._waitTimeWidget.renderMini('waitTimeMiniContainer');
        }
    };
    app.hideWaitTime = function() {
        if (this._waitTimeWidget) this._waitTimeWidget.stopPolling();
    };
}
if (OrderTracker) {
    app._orderTracker = new OrderTracker();
    app.showOrderTracker = function(orderId) {
        if (this._orderTracker) {
            this._orderTracker.init(orderId, this.supabase);
            this._orderTracker.render('orderTrackerPanel');
            const panel = document.getElementById('orderTrackerPanel');
            if (panel) panel.classList.add('active');
        }
    };
    app.hideOrderTracker = function() {
        const panel = document.getElementById('orderTrackerPanel');
        if (panel) panel.classList.remove('active');
        if (this._orderTracker) this._orderTracker.destroy();
    };
}
if (FeedbackSystem) {
    app._feedbackSystem = new FeedbackSystem();
    if (window.ALPHAPOS_CONFIG) {
        app._feedbackSystem.init(app.supabase, window.ALPHAPOS_CONFIG.merchantId);
    }
}

// Expose globally for onclick handlers in HTML
window.app = app;

// ==========================================
// DOM Ready → Init
// ==========================================
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => app.init());
} else {
    app.init();
}

// Cleanup on page unload
window.addEventListener('pagehide', () => {
    app.shutdownRealtime();
});
window.addEventListener('beforeunload', () => {
    app.shutdownRealtime();
});
