/**
 * AlphaPos — Ordering Session Gate
 *
 * Client-side gate for table-session lifecycle (not GPS / Wi-Fi):
 * - Ordering allowed while the table session is open
 * - Blocked after payment or when POS/staff closes the session
 *
 * Server still requires an active session_token on submit; kitchen print
 * still waits for staff confirmation on web orders.
 */

export class OrderingSessionGate {
    constructor() {
        this.isValid = true;
        this._sessionClosed = false;
    }

    init() {
        if (!this._sessionClosed) {
            this.isValid = true;
            this.toggleOrderingButton(true);
        }
    }

    /**
     * @returns {boolean} true when the guest may submit orders
     */
    canOrder() {
        return this.isValid && !this._sessionClosed;
    }

    toggleOrderingButton(enabled) {
        const btn = document.getElementById("submitOrderBtn");
        const warning = document.getElementById("btnWarningText");
        if (!btn) return;

        if (enabled) {
            btn.classList.remove("disabled");
            btn.removeAttribute("disabled");
            if (warning) {
                warning.classList.add("hide");
                warning.style.opacity = "0";
            }
        } else {
            btn.classList.add("disabled");
            btn.setAttribute("disabled", "true");
            if (warning) {
                warning.classList.remove("hide");
                warning.style.opacity = "1";
            }
        }
    }

    /**
     * Called after payment or when the table session is closed by staff/POS.
     * Blocks further ordering until the guest starts a new session (new QR scan).
     */
    markSessionClosed() {
        this._sessionClosed = true;
        this.isValid = false;
        this.toggleOrderingButton(false);
    }

    /** @deprecated Use markSessionClosed() — kept for older call sites */
    markPaymentCompleted() {
        this.markSessionClosed();
    }
}

export const orderingSessionGate = new OrderingSessionGate();
