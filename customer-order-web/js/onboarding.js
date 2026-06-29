/**
 * AlphaPos — Onboarding Module
 * Handles the check-in wizard: location verification, guest count, session opening.
 */
import { fetchWithFallback } from './api.js';

export const OnboardingMixin = {
    showOnboardingPanel() {
        const el = document.getElementById('onboardingWizard');
        if (el) el.classList.add('active');
        this.updateOnboardingVerification();
    },

    hideOnboardingPanel() {
        const el = document.getElementById('onboardingWizard');
        if (el) el.classList.remove('active');
    },

    updateOnboardingVerification() {
        // If we have location verifier, run it
        if (window.locationVerifier) {
            window.locationVerifier.runVerification();
        }
        // Auto-allow after 2s for dev
        setTimeout(() => {
            const btn = document.getElementById('btnOnboardingNext1');
            if (btn) {
                btn.disabled = false;
                btn.classList.remove('disabled');
            }
            const title = document.getElementById('verifyTitle');
            if (title) title.textContent = this.translate('locationVerified', 'Location Verified ✓');
        }, 2000);
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
        const steps = document.querySelectorAll('.onboarding-card');
        let currentIdx = -1;
        steps.forEach((step, i) => {
            if (step.classList.contains('active')) currentIdx = i;
        });
        if (currentIdx > 0) {
            steps[currentIdx].classList.remove('active');
            steps[currentIdx - 1].classList.add('active');
        }
    },

    setGuestCount(count) {
        if (count === '8+') count = 8;
        this.guestCount = parseInt(count) || 1;
        // Update UI pills
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
            seat.className = 'seat occupied';
            seat.style.transform = `rotate(${(360 / count) * i}deg) translateY(-60px)`;
            container.appendChild(seat);
        }
    },

    async confirmGuestCount() {
        // Open session on server
        try {
            const { success, data } = await fetchWithFallback({
                localUrl: '/v1/sessions/open',
                localOptions: {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({
                        table_number: this.tableNumber,
                        guest_count: this.guestCount
                    })
                }
            });
            if (success && data) {
                this.sessionToken = data.session_token || '';
            }
        } catch (e) {
            console.error('[Onboarding] Session open failed:', e);
        }

        // Advance to step 3 (loading) then hide
        this.nextOnboardingStep();
        setTimeout(() => {
            this.hideOnboardingPanel();
            this.renderCategories();
            this.renderMenuItems();
        }, 2500);
    },

    autoOnboardIfRequested() {
        const params = new URLSearchParams(window.location.search);
        if (params.get('autoOnboard') === 'true') {
            this.guestCount = 2;
            this.confirmGuestCount();
        }
    }
};
