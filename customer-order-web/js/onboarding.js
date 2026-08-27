/**
 * AlphaPos — Onboarding Module
 * Check-in wizard: guest count → open table session (no GPS / Wi-Fi gate).
 */
import { fetchWithFallback } from './api.js';

export const OnboardingMixin = {
    showOnboardingPanel() {
        const el = document.getElementById('onboardingWizard');
        if (el) el.classList.add('active');
    },

    hideOnboardingPanel() {
        const el = document.getElementById('onboardingWizard');
        if (el) el.classList.remove('active');
    },

    nextOnboardingStep() {
        const steps = document.querySelectorAll('.onboarding-card');
        let currentIdx = -1;
        steps.forEach((step, i) => {
            if (step.classList.contains('active')) currentIdx = i;
        });
        if (currentIdx >= 0 && currentIdx < steps.length - 1) {
            steps[currentIdx].classList.remove('active');
            steps[currentIdx + 1].classList.add('active');
        }
    },

    prevOnboardingStep() {
        // Guest count is the first step; nothing to go back to.
    },

    setGuestCount(count) {
        if (count === '8+') count = 8;
        this.guestCount = parseInt(count) || 1;
        document.querySelectorAll('.guest-pill').forEach(pill => {
            pill.classList.remove('active');
            if (pill.textContent.trim() === String(this.guestCount) ||
                (this.guestCount >= 8 && pill.textContent.trim() === '8+')) {
                pill.classList.add('active');
            }
        });
        this.renderInteractiveSeats();
    },

    renderInteractiveSeats() {
        const container = document.getElementById('interactiveSeatsContainer');
        if (!container) return;
        container.innerHTML = '';
        const count = Math.min(this.guestCount, 8);
        for (let i = 0; i < count; i++) {
            const seat = document.createElement('div');
            seat.className = 'seat';
            seat.style.setProperty('--i', i);
            container.appendChild(seat);
        }
    },

    async confirmGuestCount() {
        // Delegated to AlphaPosApp.confirmGuestCount in app.js when using the main entry.
        if (typeof this.openTableSession === 'function') {
            return this.openTableSession();
        }
    },

    async openTableSession() {
        const guestCount = this.guestCount || 2;
        const tableNumber = this.tableNumber;
        const merchantId = this.merchantId;
        try {
            const data = await fetchWithFallback('/v1/sessions/open', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    table_number: tableNumber,
                    guest_count: guestCount,
                    merchant_id: merchantId
                })
            });
            if (data && data.session_token) {
                this.sessionToken = data.session_token;
                localStorage.setItem(`sessionToken_T${tableNumber}`, data.session_token);
            }
        } catch (e) {
            console.error('[Onboarding] Failed to open session:', e);
        }
    }
};
