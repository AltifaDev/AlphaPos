/**
 * AlphaPos Customer Feedback System
 * 
 * Post-meal rating & review module with star ratings, quick tags,
 * and comment submission to Supabase.
 * 
 * Usage:
 *   import { FeedbackSystem } from './js/feedback.js';
 *   const feedback = new FeedbackSystem();
 *   feedback.init(supabaseClient, merchantId, translateFn);
 *   feedback.showFeedbackForm(orderId, tableNumber, sessionToken);
 */

export class FeedbackSystem {
    constructor() {
        this.supabase = null;
        this.merchantId = '';
        this.translateFn = (key, fallback) => fallback || key;
        this.isVisible = false;
        this.isSubmitting = false;

        // Current feedback state
        this.currentData = {
            orderId: null,
            tableNumber: null,
            sessionToken: null
        };

        // Rating state
        this.ratings = {
            overall: 0,
            food: 0,
            service: 0,
            ambience: 0
        };

        this.selectedTags = [];
        this.comment = '';
        this.customerName = '';

        // Available quick tags
        this.quickTags = [
            { key: 'great_food', icon: '🍽️', translationKey: 'tagGreatFood', fallback: 'Great Food' },
            { key: 'fast_service', icon: '⚡', translationKey: 'tagFastService', fallback: 'Fast Service' },
            { key: 'friendly_staff', icon: '😊', translationKey: 'tagFriendlyStaff', fallback: 'Friendly Staff' },
            { key: 'clean', icon: '✨', translationKey: 'tagClean', fallback: 'Clean' },
            { key: 'good_value', icon: '💰', translationKey: 'tagGoodValue', fallback: 'Good Value' },
            { key: 'will_return', icon: '🔄', translationKey: 'tagWillReturn', fallback: 'Will Come Back' }
        ];
    }

    /**
     * Initialize the feedback system
     */
    init(supabaseClient, merchantId, translateFn) {
        this.supabase = supabaseClient;
        this.merchantId = merchantId;
        if (translateFn) this.translateFn = translateFn;

        this._injectHTML();
        this._bindEvents();
    }

    /**
     * Show the feedback form modal
     */
    showFeedbackForm(orderId, tableNumber, sessionToken) {
        this.currentData = { orderId, tableNumber, sessionToken };
        this._resetState();

        const overlay = document.getElementById('feedbackModalOverlay');
        if (!overlay) return;

        overlay.classList.add('show');
        this.isVisible = true;
        document.body.style.overflow = 'hidden';

        // Animate entrance
        requestAnimationFrame(() => {
            const card = overlay.querySelector('.feedback-card');
            if (card) card.classList.add('animate-in');
        });
    }

    /**
     * Hide the feedback form
     */
    hideFeedbackForm() {
        const overlay = document.getElementById('feedbackModalOverlay');
        if (!overlay) return;

        const card = overlay.querySelector('.feedback-card');
        if (card) card.classList.remove('animate-in');

        setTimeout(() => {
            overlay.classList.remove('show');
            this.isVisible = false;
            document.body.style.overflow = '';
        }, 300);
    }

    /**
     * Submit feedback to Supabase
     */
    async submitFeedback() {
        if (this.isSubmitting) return;
        if (this.ratings.overall === 0) {
            this._shakeStars('overall');
            return;
        }

        this.isSubmitting = true;
        this._setSubmitLoading(true);

        const payload = {
            merchant_id: this.merchantId,
            order_id: this.currentData.orderId || null,
            table_number: this.currentData.tableNumber || null,
            session_token: this.currentData.sessionToken || null,
            overall_rating: this.ratings.overall,
            food_rating: this.ratings.food || null,
            service_rating: this.ratings.service || null,
            ambience_rating: this.ratings.ambience || null,
            comment: this.comment.trim() || null,
            customer_name: this.customerName.trim() || null,
            tags: this.selectedTags.length > 0 ? this.selectedTags : null
        };

        try {
            let success = false;

            // Try Supabase direct insert
            if (this.supabase) {
                const { error } = await this.supabase
                    .from('customer_feedback')
                    .insert(payload);

                if (!error) {
                    success = true;
                } else {
                    console.warn('[Feedback] Supabase insert failed:', error.message);
                }
            }

            // Fallback: POST to local server
            if (!success) {
                const res = await fetch('/v1/feedback', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify(payload)
                });
                if (res.ok) success = true;
            }

            if (success) {
                this._showThankYou();
            } else {
                throw new Error('Failed to submit feedback');
            }
        } catch (err) {
            console.error('[Feedback] Submit error:', err);
            // Still show thank you — don't punish the user for server issues
            this._showThankYou();
        } finally {
            this.isSubmitting = false;
            this._setSubmitLoading(false);
        }
    }

    // ========================
    // Private Methods
    // ========================

    _resetState() {
        this.ratings = { overall: 0, food: 0, service: 0, ambience: 0 };
        this.selectedTags = [];
        this.comment = '';
        this.customerName = '';
        this.isSubmitting = false;

        // Reset UI
        document.querySelectorAll('.feedback-star-group').forEach(group => {
            group.querySelectorAll('.feedback-star').forEach(star => {
                star.classList.remove('active', 'hover');
            });
        });
        document.querySelectorAll('.feedback-tag').forEach(tag => {
            tag.classList.remove('selected');
        });
        const textarea = document.getElementById('feedbackComment');
        if (textarea) textarea.value = '';
        const nameInput = document.getElementById('feedbackName');
        if (nameInput) nameInput.value = '';

        // Show form, hide thank you
        const formContent = document.getElementById('feedbackFormContent');
        const thankYou = document.getElementById('feedbackThankYou');
        if (formContent) formContent.classList.remove('hide');
        if (thankYou) thankYou.classList.add('hide');
    }

    _injectHTML() {
        // Don't inject if already exists
        if (document.getElementById('feedbackModalOverlay')) return;

        const t = (key, fallback) => this.translateFn(key, fallback);

        const html = `
        <div id="feedbackModalOverlay" class="feedback-modal-overlay" role="dialog" aria-modal="true" aria-label="Customer feedback">
            <div class="feedback-card">
                <!-- Form Content -->
                <div id="feedbackFormContent" class="feedback-form-content">
                    <!-- Header -->
                    <div class="feedback-header">
                        <div class="feedback-emoji">🌟</div>
                        <h2 class="feedback-title" data-feedback-translate="feedbackTitle">${t('feedbackTitle', 'How was your experience?')}</h2>
                    </div>

                    <!-- Overall Rating (Required) -->
                    <div class="feedback-rating-section feedback-rating-main">
                        <label class="feedback-rating-label" data-feedback-translate="rateOverall">${t('rateOverall', 'Overall')}</label>
                        <div class="feedback-star-group feedback-stars-large" data-rating-key="overall">
                            ${this._generateStars(5, 'overall')}
                        </div>
                        <div class="feedback-rating-text" id="feedbackOverallText"></div>
                    </div>

                    <!-- Sub-Ratings (Optional) -->
                    <div class="feedback-sub-ratings">
                        <div class="feedback-rating-section">
                            <label class="feedback-rating-label" data-feedback-translate="rateFood">${t('rateFood', 'Food')}</label>
                            <div class="feedback-star-group" data-rating-key="food">
                                ${this._generateStars(5, 'food')}
                            </div>
                        </div>
                        <div class="feedback-rating-section">
                            <label class="feedback-rating-label" data-feedback-translate="rateService">${t('rateService', 'Service')}</label>
                            <div class="feedback-star-group" data-rating-key="service">
                                ${this._generateStars(5, 'service')}
                            </div>
                        </div>
                        <div class="feedback-rating-section">
                            <label class="feedback-rating-label" data-feedback-translate="rateAmbience">${t('rateAmbience', 'Ambience')}</label>
                            <div class="feedback-star-group" data-rating-key="ambience">
                                ${this._generateStars(5, 'ambience')}
                            </div>
                        </div>
                    </div>

                    <!-- Quick Tags -->
                    <div class="feedback-tags-section">
                        <div class="feedback-tags" id="feedbackTags">
                            ${this.quickTags.map(tag => `
                                <button class="feedback-tag" data-tag="${tag.key}" data-feedback-translate="${tag.translationKey}">
                                    <span class="feedback-tag-icon">${tag.icon}</span>
                                    <span class="feedback-tag-text">${t(tag.translationKey, tag.fallback)}</span>
                                </button>
                            `).join('')}
                        </div>
                    </div>

                    <!-- Comment -->
                    <div class="feedback-comment-section">
                        <textarea 
                            id="feedbackComment" 
                            class="feedback-textarea" 
                            placeholder="${t('feedbackComment', 'Any comments?')}"
                            maxlength="500"
                            rows="3"
                        ></textarea>
                        <div class="feedback-char-count"><span id="feedbackCharCount">0</span>/500</div>
                    </div>

                    <!-- Customer Name (Optional) -->
                    <div class="feedback-name-section">
                        <input 
                            type="text" 
                            id="feedbackName" 
                            class="feedback-name-input" 
                            placeholder="${t('feedbackNamePlaceholder', 'Your name (optional)')}"
                            maxlength="100"
                        />
                    </div>

                    <!-- Actions -->
                    <div class="feedback-actions">
                        <button id="feedbackSubmitBtn" class="feedback-submit-btn">
                            <span class="feedback-submit-text" data-feedback-translate="feedbackSubmit">${t('feedbackSubmit', 'Submit Feedback')}</span>
                            <span class="feedback-submit-spinner hide">
                                <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
                                    <path d="M12 2v4M12 18v4M4.93 4.93l2.83 2.83M16.24 16.24l2.83 2.83M2 12h4M18 12h4M4.93 19.07l2.83-2.83M16.24 7.76l2.83-2.83">
                                        <animateTransform attributeName="transform" type="rotate" from="0 12 12" to="360 12 12" dur="1s" repeatCount="indefinite"/>
                                    </path>
                                </svg>
                            </span>
                        </button>
                        <button id="feedbackSkipBtn" class="feedback-skip-btn" data-feedback-translate="feedbackSkip">${t('feedbackSkip', 'Maybe later')}</button>
                    </div>
                </div>

                <!-- Thank You Screen -->
                <div id="feedbackThankYou" class="feedback-thank-you hide">
                    <div class="feedback-success-animation">
                        <div class="feedback-confetti-container">
                            <span class="confetti c1">🎉</span>
                            <span class="confetti c2">⭐</span>
                            <span class="confetti c3">✨</span>
                            <span class="confetti c4">🎊</span>
                            <span class="confetti c5">💫</span>
                        </div>
                        <div class="feedback-success-checkmark">
                            <svg viewBox="0 0 52 52" width="72" height="72">
                                <circle class="feedback-check-circle" cx="26" cy="26" r="25" fill="none"/>
                                <path class="feedback-check-path" fill="none" d="M14.1 27.2l7.1 7.2 16.7-16.8"/>
                            </svg>
                        </div>
                    </div>
                    <h2 class="feedback-thanks-title" data-feedback-translate="feedbackThanks">${t('feedbackThanks', 'Thank you for your feedback!')}</h2>
                    <p class="feedback-thanks-desc" data-feedback-translate="feedbackThanksDesc">${t('feedbackThanksDesc', 'Your feedback helps us improve.')}</p>
                </div>
            </div>
        </div>`;

        document.body.insertAdjacentHTML('beforeend', html);
    }

    _generateStars(count, key) {
        let html = '';
        for (let i = 1; i <= count; i++) {
            html += `<button class="feedback-star" data-value="${i}" data-key="${key}" aria-label="Rate ${i} of ${count}">
                <svg viewBox="0 0 24 24" width="100%" height="100%">
                    <path d="M12 2l3.09 6.26L22 9.27l-5 4.87 1.18 6.88L12 17.77l-6.18 3.25L7 14.14 2 9.27l6.91-1.01L12 2z"/>
                </svg>
            </button>`;
        }
        return html;
    }

    _bindEvents() {
        // Star click/hover events
        document.addEventListener('click', (e) => {
            const star = e.target.closest('.feedback-star');
            if (star) {
                const key = star.dataset.key;
                const value = parseInt(star.dataset.value);
                this._setRating(key, value);
            }

            // Tag toggle
            const tag = e.target.closest('.feedback-tag');
            if (tag) {
                this._toggleTag(tag.dataset.tag);
                tag.classList.toggle('selected');
            }

            // Submit button
            if (e.target.closest('#feedbackSubmitBtn')) {
                this.submitFeedback();
            }

            // Skip button
            if (e.target.closest('#feedbackSkipBtn')) {
                this.hideFeedbackForm();
            }

            // Click overlay to close
            if (e.target.id === 'feedbackModalOverlay') {
                this.hideFeedbackForm();
            }
        });

        // Star hover effects
        document.addEventListener('mouseover', (e) => {
            const star = e.target.closest('.feedback-star');
            if (star) {
                const group = star.closest('.feedback-star-group');
                const value = parseInt(star.dataset.value);
                this._highlightStars(group, value);
            }
        });

        document.addEventListener('mouseout', (e) => {
            const star = e.target.closest('.feedback-star');
            if (star) {
                const group = star.closest('.feedback-star-group');
                const key = group.dataset.ratingKey;
                this._highlightStars(group, this.ratings[key]);
            }
        });

        // Comment textarea
        document.addEventListener('input', (e) => {
            if (e.target.id === 'feedbackComment') {
                this.comment = e.target.value;
                const counter = document.getElementById('feedbackCharCount');
                if (counter) counter.textContent = e.target.value.length;
            }
            if (e.target.id === 'feedbackName') {
                this.customerName = e.target.value;
            }
        });

        // Escape key to close
        document.addEventListener('keydown', (e) => {
            if (e.key === 'Escape' && this.isVisible) {
                this.hideFeedbackForm();
            }
        });
    }

    _setRating(key, value) {
        this.ratings[key] = value;
        const group = document.querySelector(`.feedback-star-group[data-rating-key="${key}"]`);
        if (group) {
            this._highlightStars(group, value);
            // Add pop animation
            const stars = group.querySelectorAll('.feedback-star');
            stars.forEach((star, i) => {
                if (i < value) {
                    star.classList.add('pop');
                    setTimeout(() => star.classList.remove('pop'), 300);
                }
            });
        }

        // Update rating text for overall
        if (key === 'overall') {
            const textEl = document.getElementById('feedbackOverallText');
            if (textEl) {
                const labels = ['', '😞 Poor', '😐 Fair', '🙂 Good', '😊 Great', '🤩 Excellent'];
                textEl.textContent = labels[value] || '';
                textEl.classList.add('show');
            }
        }
    }

    _highlightStars(group, upToValue) {
        const stars = group.querySelectorAll('.feedback-star');
        stars.forEach((star, i) => {
            if (i < upToValue) {
                star.classList.add('active');
            } else {
                star.classList.remove('active');
            }
        });
    }

    _toggleTag(tagKey) {
        const idx = this.selectedTags.indexOf(tagKey);
        if (idx === -1) {
            this.selectedTags.push(tagKey);
        } else {
            this.selectedTags.splice(idx, 1);
        }
    }

    _shakeStars(key) {
        const group = document.querySelector(`.feedback-star-group[data-rating-key="${key}"]`);
        if (group) {
            group.classList.add('shake');
            setTimeout(() => group.classList.remove('shake'), 500);
        }
    }

    _setSubmitLoading(loading) {
        const btn = document.getElementById('feedbackSubmitBtn');
        if (!btn) return;
        const text = btn.querySelector('.feedback-submit-text');
        const spinner = btn.querySelector('.feedback-submit-spinner');
        if (loading) {
            btn.classList.add('loading');
            btn.disabled = true;
            if (text) text.classList.add('hide');
            if (spinner) spinner.classList.remove('hide');
        } else {
            btn.classList.remove('loading');
            btn.disabled = false;
            if (text) text.classList.remove('hide');
            if (spinner) spinner.classList.add('hide');
        }
    }

    _showThankYou() {
        const formContent = document.getElementById('feedbackFormContent');
        const thankYou = document.getElementById('feedbackThankYou');
        if (formContent) formContent.classList.add('hide');
        if (thankYou) thankYou.classList.remove('hide');

        // Auto-close after 3 seconds
        setTimeout(() => {
            this.hideFeedbackForm();
        }, 3000);
    }

    /**
     * Update translations when language changes
     */
    updateTranslations(translateFn) {
        this.translateFn = translateFn;
        const t = translateFn;

        // Update all translatable elements
        document.querySelectorAll('[data-feedback-translate]').forEach(el => {
            const key = el.dataset.feedbackTranslate;
            const fallbacks = {
                feedbackTitle: 'How was your experience?',
                rateOverall: 'Overall',
                rateFood: 'Food',
                rateService: 'Service',
                rateAmbience: 'Ambience',
                feedbackSubmit: 'Submit Feedback',
                feedbackSkip: 'Maybe later',
                feedbackThanks: 'Thank you for your feedback!',
                tagGreatFood: 'Great Food',
                tagFastService: 'Fast Service',
                tagFriendlyStaff: 'Friendly Staff',
                tagClean: 'Clean',
                tagGoodValue: 'Good Value',
                tagWillReturn: 'Will Come Back'
            };
            el.textContent = t(key, fallbacks[key] || key);
        });

        // Update placeholders
        const textarea = document.getElementById('feedbackComment');
        if (textarea) textarea.placeholder = t('feedbackComment', 'Any comments?');
        const nameInput = document.getElementById('feedbackName');
        if (nameInput) nameInput.placeholder = t('feedbackNamePlaceholder', 'Your name (optional)');
    }
}
