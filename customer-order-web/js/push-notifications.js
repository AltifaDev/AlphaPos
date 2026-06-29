/**
 * AlphaPos — Web Push Notifications Module
 * 
 * Manages Web Push API subscription, permission prompts,
 * and server-side registration for order status notifications.
 */

export class PushNotificationManager {
    constructor() {
        this.isSupported = ('serviceWorker' in navigator) && ('PushManager' in window) && ('Notification' in window);
        this.subscription = null;
        this.permission = Notification.permission; // 'default', 'granted', 'denied'
        this._orderId = null;
        this._translate = (key, fallback) => {
            if (window.app && typeof window.app.translate === 'function') {
                return window.app.translate(key, fallback);
            }
            return fallback;
        };
    }

    /**
     * Initialize push notification manager
     * - Checks browser support
     * - Checks existing permission
     * - Retrieves existing subscription if any
     */
    async init() {
        if (!this.isSupported) {
            console.warn('[Push] Web Push not supported in this browser');
            return;
        }

        this.permission = Notification.permission;

        // If already granted, retrieve existing subscription
        if (this.permission === 'granted') {
            try {
                const registration = await navigator.serviceWorker.ready;
                this.subscription = await registration.pushManager.getSubscription();
                if (this.subscription) {
                    console.log('[Push] Existing subscription found');
                }
            } catch (err) {
                console.warn('[Push] Error retrieving subscription:', err);
            }
        }
    }

    /**
     * Show custom permission prompt UI (before native browser prompt)
     * Explains benefits to user to increase opt-in rate
     */
    showPermissionPrompt() {
        if (!this.isSupported) return;
        if (this.permission === 'granted') return; // Already granted
        if (this.permission === 'denied') return; // Can't ask again

        const modal = document.getElementById('pushPermissionModal');
        if (modal) {
            modal.classList.add('active');
            modal.setAttribute('aria-hidden', 'false');
        }
    }

    /**
     * Hide custom permission prompt
     */
    hidePermissionPrompt() {
        const modal = document.getElementById('pushPermissionModal');
        if (modal) {
            modal.classList.remove('active');
            modal.setAttribute('aria-hidden', 'true');
        }
    }

    /**
     * Request notification permission from browser
     * Called when user clicks "Enable Notifications" in custom prompt
     */
    async requestPermission() {
        if (!this.isSupported) return false;

        try {
            const result = await Notification.requestPermission();
            this.permission = result;

            if (result === 'granted') {
                console.log('[Push] Permission granted');
                this.hidePermissionPrompt();
                await this._subscribeAndRegister();
                return true;
            } else {
                console.log('[Push] Permission denied or dismissed:', result);
                this.hidePermissionPrompt();
                return false;
            }
        } catch (err) {
            console.error('[Push] Permission request error:', err);
            return false;
        }
    }

    /**
     * Subscribe to push and register with server
     * @param {string} orderId — current order to track
     */
    async subscribe(orderId) {
        if (!this.isSupported || this.permission !== 'granted') return false;
        this._orderId = orderId;

        try {
            await this._subscribeAndRegister();
            return true;
        } catch (err) {
            console.error('[Push] Subscribe error:', err);
            return false;
        }
    }

    /**
     * Internal: subscribe via PushManager + POST to server
     */
    async _subscribeAndRegister() {
        const registration = await navigator.serviceWorker.ready;

        // Generate VAPID public key (server should provide this)
        // For now, use a placeholder — in production, fetch from /v1/push/vapid-key
        const vapidPublicKey = await this._getVapidPublicKey();

        const subscribeOptions = {
            userVisibleOnly: true
        };

        // Only add applicationServerKey if we have a VAPID key
        if (vapidPublicKey) {
            subscribeOptions.applicationServerKey = this._urlBase64ToUint8Array(vapidPublicKey);
        }

        try {
            this.subscription = await registration.pushManager.subscribe(subscribeOptions);
            console.log('[Push] Subscribed:', this.subscription.endpoint);

            // Send subscription to server
            await this._sendSubscriptionToServer(this.subscription);
        } catch (err) {
            // If VAPID key issue, try without applicationServerKey
            if (err.name === 'InvalidStateError' || err.message.includes('applicationServerKey')) {
                console.warn('[Push] Retrying without VAPID key');
                this.subscription = await registration.pushManager.subscribe({
                    userVisibleOnly: true
                });
                await this._sendSubscriptionToServer(this.subscription);
            } else {
                throw err;
            }
        }
    }

    /**
     * Get VAPID public key from server
     */
    async _getVapidPublicKey() {
        try {
            const res = await fetch('/v1/push/vapid-key');
            if (res.ok) {
                const data = await res.json();
                return data.publicKey || null;
            }
        } catch (err) {
            console.warn('[Push] Could not fetch VAPID key, using fallback');
        }
        return null;
    }

    /**
     * Send push subscription to server for storage
     */
    async _sendSubscriptionToServer(subscription) {
        try {
            const body = {
                subscription: subscription.toJSON(),
                order_id: this._orderId,
                table_number: window.app ? window.app.tableNumber : null
            };

            const res = await fetch('/v1/push/subscribe', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(body)
            });

            if (!res.ok) {
                console.warn('[Push] Server registration failed:', res.status);
            } else {
                console.log('[Push] Subscription registered with server');
            }
        } catch (err) {
            console.error('[Push] Failed to send subscription to server:', err);
        }
    }

    /**
     * Unsubscribe from push notifications
     */
    async unsubscribe() {
        if (this.subscription) {
            try {
                await this.subscription.unsubscribe();
                this.subscription = null;
                console.log('[Push] Unsubscribed');
            } catch (err) {
                console.error('[Push] Unsubscribe error:', err);
            }
        }
    }

    /**
     * Check if push is currently active
     */
    get isActive() {
        return this.permission === 'granted' && this.subscription !== null;
    }

    /**
     * Show a local notification (fallback when push server not available)
     */
    showLocalNotification(title, body, data = {}) {
        if (this.permission !== 'granted') return;

        navigator.serviceWorker.ready.then(registration => {
            registration.showNotification(title, {
                body: body,
                icon: '/icon-192.png',
                badge: '/badge-72.png',
                vibrate: [200, 100, 200],
                tag: data.tag || 'alphapos-order',
                renotify: true,
                data: {
                    url: data.url || '/',
                    orderId: data.orderId || this._orderId,
                    type: data.type || 'order_update'
                },
                actions: [
                    { action: 'view', title: this._translate('trackMyOrder', 'Track Order') },
                    { action: 'dismiss', title: this._translate('pushLater', 'Dismiss') }
                ]
            });
        });
    }

    /**
     * Convert URL-safe base64 to Uint8Array (for VAPID key)
     */
    _urlBase64ToUint8Array(base64String) {
        const padding = '='.repeat((4 - base64String.length % 4) % 4);
        const base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/');
        const rawData = window.atob(base64);
        const outputArray = new Uint8Array(rawData.length);
        for (let i = 0; i < rawData.length; ++i) {
            outputArray[i] = rawData.charCodeAt(i);
        }
        return outputArray;
    }
}

// Singleton export
export const pushManager = new PushNotificationManager();
