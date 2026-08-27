/**
 * AlphaPos — Enhanced Bill View & Receipt Module
 * 
 * Features:
 * - Itemized bill with modifiers, tax breakdown, discounts
 * - Tip calculator (0%, 5%, 10%, 15%, Custom)
 * - Split bill (equal / by item)
 * - Post-payment receipt with QR + email
 * - PDF download (simple receipt)
 */

export class BillView {
    constructor() {
        this.supabase = null;
        this.merchantId = null;
        this.orderData = null;
        this.paymentData = null;
        this.tipPercent = 0;
        this.tipAmount = 0;
        this.splitMode = null; // null | 'equal' | 'by_item'
        this.splitCount = 2;
        this.itemAssignments = {}; // itemId -> personIndex
        this.serviceChargeRate = 0.10;
        this.vatRate = 0.07;
        this.taxType = 'inclusive';
        this._translate = (key, fallback) => fallback || key;
    }

    init(supabaseClient, merchantId, translateFn, merchantSettings = {}) {
        this.supabase = supabaseClient;
        this.merchantId = merchantId;
        if (translateFn) this._translate = translateFn;
        if (merchantSettings.service_charge_rate !== undefined) {
            this.serviceChargeRate = Number(merchantSettings.service_charge_rate) / 100;
        }
        if (merchantSettings.tax_rate !== undefined) {
            this.vatRate = Number(merchantSettings.tax_rate) / 100;
        }
        if (merchantSettings.tax_type) {
            this.taxType = String(merchantSettings.tax_type).toLowerCase();
        }
    }

    t(key, fallback) {
        return this._translate(key, fallback);
    }

    // ========================================
    // BILL CALCULATION
    // ========================================

    calculateBill(items, discounts = [], tipPercent = 0, loyaltyDiscount = 0, supportProgram = null) {
        const subtotal = items.reduce((sum, item) => {
            const itemTotal = Number(item.price || 0) * Number(item.quantity || 1);
            const modifierTotal = (item.modifiers || []).reduce((ms, mod) => ms + Number(mod.price || 0) * Number(item.quantity || 1), 0);
            return sum + itemTotal + modifierTotal;
        }, 0);

        const discountTotal = discounts.reduce((sum, d) => {
            if (d.type === 'percent') return sum + (subtotal * Number(d.value || 0) / 100);
            return sum + Number(d.value || 0);
        }, 0);

        const afterDiscount = Math.max(0, subtotal - discountTotal - loyaltyDiscount);
        const serviceCharge = Math.round(afterDiscount * this.serviceChargeRate * 100) / 100;

        let vat = 0;
        let totalBeforeSupport = 0;
        if (this.taxType === 'exclusive') {
            vat = Math.round((afterDiscount + serviceCharge) * this.vatRate * 100) / 100;
            totalBeforeSupport = afterDiscount + serviceCharge + vat;
        } else {
            totalBeforeSupport = afterDiscount + serviceCharge;
            vat = this.vatRate > 0 ? Math.round(totalBeforeSupport * this.vatRate / (1 + this.vatRate) * 100) / 100 : 0;
        }

        let supportGovAmount = 0;
        let supportCitizenAmount = totalBeforeSupport;
        if (supportProgram && supportProgram.rate > 0) {
            supportGovAmount = Math.round(totalBeforeSupport * supportProgram.rate * 100) / 100;
            supportCitizenAmount = Math.max(0, totalBeforeSupport - supportGovAmount);
        } else if (supportProgram && supportProgram.amount > 0) {
            supportGovAmount = Math.min(totalBeforeSupport, supportProgram.amount);
            supportCitizenAmount = Math.max(0, totalBeforeSupport - supportGovAmount);
        }

        const tipAmount = tipPercent > 0 ? Math.round(afterDiscount * tipPercent) / 100 : this.tipAmount;
        const grandTotal = supportCitizenAmount + tipAmount;

        return {
            subtotal,
            discountTotal,
            loyaltyDiscount,
            afterDiscount,
            serviceCharge,
            vat,
            totalBeforeSupport,
            supportGovAmount,
            supportCitizenAmount,
            tipAmount,
            grandTotal,
            itemCount: items.reduce((sum, i) => sum + (Number(i.quantity) || 1), 0)
        };
    }

    // ========================================
    // SHOW BILL (Before Payment)
    // ========================================

    showBill(orderData, options = {}) {
        this.orderData = orderData;
        this.tipPercent = 0;
        this.tipAmount = 0;
        this.splitMode = null;

        const items = orderData.items || [];
        const discounts = orderData.discounts || [];
        const loyaltyDiscount = options.loyaltyDiscount || 0;
        const loyaltyPointsEarn = options.loyaltyPointsEarn || 0;
        const supportProgram = orderData.support_program_name ? {
            name: orderData.support_program_name,
            rate: Number(orderData.support_government_rate || 0),
            amount: Number(orderData.support_government_amount || 0),
            citizenAmount: Number(orderData.support_citizen_amount || 0)
        } : null;

        const calc = this.calculateBill(items, discounts, this.tipPercent, loyaltyDiscount, supportProgram);

        const panel = document.getElementById('billViewPanel');
        if (!panel) return;

        panel.innerHTML = this._renderBillHTML(items, discounts, calc, loyaltyPointsEarn, loyaltyDiscount, supportProgram);
        panel.classList.remove('hidden');
        panel.classList.add('active');
        document.body.classList.add('bill-open');

        // Bind events
        this._bindBillEvents(items, discounts, loyaltyDiscount, loyaltyPointsEarn, supportProgram);
    }

    _renderBillHTML(items, discounts, calc, loyaltyPointsEarn, loyaltyDiscount, supportProgram = null) {
        const itemsHTML = items.map(item => {
            const modifiersHTML = (item.modifiers || []).map(mod => 
                `<div class="bill-modifier">+ ${this._escape(mod.name)} ${mod.price > 0 ? `<span>+฿${mod.price.toFixed(2)}</span>` : ''}</div>`
            ).join('');

            return `
                <div class="bill-item-row">
                    <div class="bill-item-info">
                        <span class="bill-item-name">${this._escape(item.name)}</span>
                        <span class="bill-item-qty">×${item.quantity}</span>
                    </div>
                    <span class="bill-item-price">฿${(item.price * item.quantity).toFixed(2)}</span>
                </div>
                ${modifiersHTML}
            `;
        }).join('');

        const discountsHTML = discounts.map(d => `
            <div class="bill-discount-row">
                <span>🏷️ ${this._escape(d.name || this.t('discountApplied', 'Discount'))}</span>
                <span>-฿${(d.type === 'percent' ? (calc.subtotal * d.value / 100) : d.value).toFixed(2)}</span>
            </div>
        `).join('');

        const loyaltyHTML = loyaltyDiscount > 0 ? `
            <div class="bill-discount-row loyalty">
                <span>🎁 ${this.t('pointsRedeemed', 'Points Redeemed')}</span>
                <span>-฿${loyaltyDiscount.toFixed(2)}</span>
            </div>
        ` : '';

        const supportHTML = (supportProgram && calc.supportGovAmount > 0) ? `
            <div class="bill-discount-row support-program">
                <span>🏛️ ${this._escape(supportProgram.name)}</span>
                <span>-฿${calc.supportGovAmount.toFixed(2)}</span>
            </div>
        ` : '';

        const earnHTML = loyaltyPointsEarn > 0 ? `
            <div class="bill-earn-row">
                <span>⭐ ${this.t('pointsEarned', 'Points Earned')}</span>
                <span class="earn-value">+${loyaltyPointsEarn}</span>
            </div>
        ` : '';

        const scRateDisplay = Math.round(this.serviceChargeRate * 100);
        const vatRateDisplay = Math.round(this.vatRate * 100);
        const vatLabel = this.taxType === 'inclusive' ? `${this.t('vat', 'VAT')} (${vatRateDisplay}% ${this.t('inclusiveTax', 'incl.')})` : `${this.t('vat', 'VAT')} (${vatRateDisplay}%)`;

        return `
            <div class="bill-view">
                <div class="bill-header">
                    <button class="bill-close-btn" onclick="window._billView.hideBill()">✕</button>
                    <h2 class="bill-title">${this.t('viewBill', 'Your Bill')}</h2>
                    <span class="bill-table-badge">${this.t('tableBadgeText', 'Table').replace('{num}', this.orderData.tableNumber || '--')}</span>
                </div>

                <div class="bill-items-section">
                    ${itemsHTML}
                </div>

                ${discountsHTML ? `<div class="bill-discounts-section">${discountsHTML}</div>` : ''}
                ${loyaltyHTML}
                ${supportHTML}

                <div class="bill-subtotal-section">
                    <div class="bill-line"><span>${this.t('subtotal', 'Subtotal')}</span><span>฿${calc.afterDiscount.toFixed(2)}</span></div>
                    ${this.serviceChargeRate > 0 ? `<div class="bill-line"><span>${this.t('serviceCharge', 'Service Charge')} (${scRateDisplay}%)</span><span>฿${calc.serviceCharge.toFixed(2)}</span></div>` : ''}
                    ${this.vatRate > 0 ? `<div class="bill-line"><span>${vatLabel}</span><span>฿${calc.vat.toFixed(2)}</span></div>` : ''}
                    ${supportProgram ? `<div class="bill-line bill-order-total"><span>${this.t('billTotal', 'Order Total')}</span><span>฿${calc.totalBeforeSupport.toFixed(2)}</span></div>` : ''}
                </div>

                <!-- Tip Section -->
                <div class="bill-tip-selector">
                    <h3 class="bill-section-title">${this.t('addTip', 'Add Tip')}</h3>
                    <div class="bill-tip-pills">
                        <button class="bill-tip-pill ${this.tipPercent === 0 ? 'active' : ''}" data-tip="0">0%</button>
                        <button class="bill-tip-pill ${this.tipPercent === 5 ? 'active' : ''}" data-tip="5">5%</button>
                        <button class="bill-tip-pill ${this.tipPercent === 10 ? 'active' : ''}" data-tip="10">10%</button>
                        <button class="bill-tip-pill ${this.tipPercent === 15 ? 'active' : ''}" data-tip="15">15%</button>
                        <button class="bill-tip-pill custom" data-tip="custom">${this.t('customAmount', 'Custom')}</button>
                    </div>
                    <div class="bill-tip-custom hidden" id="billTipCustom">
                        <input type="number" id="billTipCustomInput" placeholder="฿0" min="0" max="9999" step="10">
                    </div>
                    <div class="bill-tip-amount" id="billTipDisplay">
                        ${calc.tipAmount > 0 ? `฿${calc.tipAmount.toFixed(2)}` : ''}
                    </div>
                </div>

                ${earnHTML}

                <!-- Grand Total / Citizen Amount -->
                <div class="bill-total-row">
                    <span>${supportProgram ? this.t('payableTotal', 'Payable Amount') : this.t('grandTotal', 'Total')}</span>
                    <span id="billGrandTotal">฿${calc.grandTotal.toFixed(2)}</span>
                </div>

                <!-- Actions -->
                <div class="bill-actions">
                    <button class="bill-split-btn" onclick="window._billView.showSplitBill()">
                        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 2v20M2 12h20"/></svg>
                        ${this.t('splitBill', 'Split Bill')}
                    </button>
                    <button class="bill-pay-btn" onclick="window._billView.requestPayment()">
                        ${this.t('payNow', 'Pay Now')}
                    </button>
                </div>

                <!-- Split Bill Section (hidden by default) -->
                <div class="bill-split-section hidden" id="billSplitSection">
                </div>
            </div>
        `;
    }

    _bindBillEvents(items, discounts, loyaltyDiscount, loyaltyPointsEarn) {
        // Tip pills
        document.querySelectorAll('.bill-tip-pill').forEach(pill => {
            pill.addEventListener('click', (e) => {
                const tip = e.currentTarget.dataset.tip;
                document.querySelectorAll('.bill-tip-pill').forEach(p => p.classList.remove('active'));
                e.currentTarget.classList.add('active');

                const customDiv = document.getElementById('billTipCustom');
                if (tip === 'custom') {
                    customDiv?.classList.remove('hidden');
                    this.tipPercent = 0;
                    const input = document.getElementById('billTipCustomInput');
                    input?.focus();
                } else {
                    customDiv?.classList.add('hidden');
                    this.tipPercent = parseInt(tip);
                    this.tipAmount = 0;
                    this._updateBillTotal(items, discounts, loyaltyDiscount);
                }
            });
        });

        // Custom tip input
        const customInput = document.getElementById('billTipCustomInput');
        if (customInput) {
            customInput.addEventListener('input', () => {
                this.tipAmount = parseFloat(customInput.value) || 0;
                this.tipPercent = 0;
                this._updateBillTotal(items, discounts, loyaltyDiscount);
            });
        }
    }

    _updateBillTotal(items, discounts, loyaltyDiscount) {
        const calc = this.calculateBill(items, discounts, this.tipPercent, loyaltyDiscount);
        // Override tip if custom
        const finalTip = this.tipPercent > 0 ? calc.tipAmount : this.tipAmount;
        const finalTotal = calc.grandTotal - calc.tipAmount + finalTip;

        const totalEl = document.getElementById('billGrandTotal');
        if (totalEl) totalEl.textContent = `฿${finalTotal.toFixed(2)}`;

        const tipDisplay = document.getElementById('billTipDisplay');
        if (tipDisplay) tipDisplay.textContent = finalTip > 0 ? `฿${finalTip.toFixed(2)}` : '';
    }

    hideBill() {
        const panel = document.getElementById('billViewPanel');
        if (panel) {
            panel.classList.remove('active');
            setTimeout(() => panel.classList.add('hidden'), 300);
        }
        document.body.classList.remove('bill-open');
    }

    // ========================================
    // SPLIT BILL
    // ========================================

    showSplitBill(orderData) {
        if (orderData) this.orderData = orderData;
        const section = document.getElementById('billSplitSection');
        if (!section) return;

        section.classList.remove('hidden');
        section.innerHTML = this._renderSplitHTML();
        this._bindSplitEvents();
    }

    _renderSplitHTML() {
        return `
            <div class="split-header">
                <h3>${this.t('splitBill', 'Split Bill')}</h3>
                <button class="split-close" onclick="document.getElementById('billSplitSection').classList.add('hidden')">✕</button>
            </div>
            <div class="split-mode-pills">
                <button class="split-mode-pill ${this.splitMode === 'equal' ? 'active' : ''}" data-mode="equal">
                    ${this.t('equalSplit', 'Split Equally')}
                </button>
                <button class="split-mode-pill ${this.splitMode === 'by_item' ? 'active' : ''}" data-mode="by_item">
                    ${this.t('byItem', 'By Item')}
                </button>
            </div>
            <div id="splitContent" class="split-content">
                ${this.splitMode === 'equal' ? this._renderEqualSplit() : ''}
                ${this.splitMode === 'by_item' ? this._renderByItemSplit() : ''}
                ${!this.splitMode ? `<p class="split-hint">${this.t('splitBillHint', 'Choose a split method above')}</p>` : ''}
            </div>
        `;
    }

    _renderEqualSplit() {
        const items = this.orderData?.items || [];
        const calc = this.calculateBill(items, this.orderData?.discounts || [], this.tipPercent, 0);
        const perPerson = calc.grandTotal / this.splitCount;

        let peopleHTML = '';
        for (let i = 1; i <= this.splitCount; i++) {
            peopleHTML += `
                <div class="split-person-row">
                    <span class="split-person-avatar">${i}</span>
                    <span class="split-person-label">${this.t('person', 'Person')} ${i}</span>
                    <span class="split-person-amount">฿${perPerson.toFixed(2)}</span>
                </div>
            `;
        }

        return `
            <div class="split-equal-controls">
                <label>${this.t('numberOfPeople', 'Number of people')}</label>
                <div class="split-stepper">
                    <button class="split-stepper-btn" onclick="window._billView.adjustSplitCount(-1)">−</button>
                    <span class="split-stepper-value" id="splitCountValue">${this.splitCount}</span>
                    <button class="split-stepper-btn" onclick="window._billView.adjustSplitCount(1)">+</button>
                </div>
            </div>
            <div class="split-persons">${peopleHTML}</div>
            <div class="split-total-row">
                <span>${this.t('eachPays', 'Each pays')}</span>
                <span class="split-each-amount">฿${perPerson.toFixed(2)}</span>
            </div>
        `;
    }

    _renderByItemSplit() {
        const items = this.orderData?.items || [];
        let itemsHTML = items.map((item, idx) => {
            const assigned = this.itemAssignments[idx] || 0;
            return `
                <div class="split-item-assign-row">
                    <span class="split-item-name">${this._escape(item.name)} ×${item.quantity}</span>
                    <div class="split-item-person-pills">
                        ${Array.from({length: this.splitCount}, (_, i) => `
                            <button class="split-person-pill ${assigned === i+1 ? 'active' : ''}" 
                                    onclick="window._billView.assignItem(${idx}, ${i+1})">
                                ${i+1}
                            </button>
                        `).join('')}
                    </div>
                </div>
            `;
        }).join('');

        return `
            <div class="split-equal-controls">
                <label>${this.t('numberOfPeople', 'Number of people')}</label>
                <div class="split-stepper">
                    <button class="split-stepper-btn" onclick="window._billView.adjustSplitCount(-1)">−</button>
                    <span class="split-stepper-value">${this.splitCount}</span>
                    <button class="split-stepper-btn" onclick="window._billView.adjustSplitCount(1)">+</button>
                </div>
            </div>
            <div class="split-items-assign">${itemsHTML}</div>
            <div class="split-summary" id="splitByItemSummary">${this._calcByItemSummary()}</div>
        `;
    }

    _calcByItemSummary() {
        const items = this.orderData?.items || [];
        const personTotals = {};
        for (let i = 1; i <= this.splitCount; i++) personTotals[i] = 0;

        items.forEach((item, idx) => {
            const person = this.itemAssignments[idx] || 1;
            personTotals[person] += item.price * item.quantity;
        });

        return Object.entries(personTotals).map(([p, total]) => `
            <div class="split-person-row">
                <span class="split-person-avatar">${p}</span>
                <span class="split-person-label">${this.t('person', 'Person')} ${p}</span>
                <span class="split-person-amount">฿${total.toFixed(2)}</span>
            </div>
        `).join('');
    }

    adjustSplitCount(delta) {
        this.splitCount = Math.max(2, Math.min(10, this.splitCount + delta));
        const content = document.getElementById('splitContent');
        if (content) {
            content.innerHTML = this.splitMode === 'equal' ? this._renderEqualSplit() : this._renderByItemSplit();
        }
    }

    assignItem(itemIdx, personIdx) {
        this.itemAssignments[itemIdx] = personIdx;
        const content = document.getElementById('splitContent');
        if (content) content.innerHTML = this._renderByItemSplit();
    }

    _bindSplitEvents() {
        document.querySelectorAll('.split-mode-pill').forEach(pill => {
            pill.addEventListener('click', (e) => {
                const mode = e.currentTarget.dataset.mode;
                this.splitMode = mode;
                document.querySelectorAll('.split-mode-pill').forEach(p => p.classList.remove('active'));
                e.currentTarget.classList.add('active');
                const content = document.getElementById('splitContent');
                if (content) {
                    content.innerHTML = mode === 'equal' ? this._renderEqualSplit() : this._renderByItemSplit();
                }
            });
        });
    }

    // ========================================
    // RECEIPT (After Payment)
    // ========================================

    showReceipt(orderData, paymentData) {
        this.orderData = orderData;
        this.paymentData = paymentData;

        const panel = document.getElementById('billViewPanel');
        if (!panel) return;

        panel.innerHTML = this._renderReceiptHTML(orderData, paymentData);
        panel.classList.remove('hidden');
        panel.classList.add('active');
        document.body.classList.add('bill-open');
    }

    _renderReceiptHTML(orderData, paymentData) {
        const items = orderData.items || [];
        const calc = this.calculateBill(items, orderData.discounts || [], 0, 0);
        const now = new Date();
        const timeStr = now.toLocaleString('th-TH', { dateStyle: 'medium', timeStyle: 'short' });

        const paymentMethod = paymentData?.method || 'cash';
        const methodIcons = { cash: '💵', card: '💳', qr: '📱', promptpay: '📱' };
        const methodNames = { cash: 'Cash', card: 'Credit Card', qr: 'QR Payment', promptpay: 'PromptPay' };

        const itemsHTML = items.map(item => `
            <div class="receipt-item-row">
                <span>${this._escape(item.name)} ×${item.quantity}</span>
                <span>฿${(item.price * item.quantity).toFixed(2)}</span>
            </div>
        `).join('');

        return `
            <div class="receipt-view">
                <div class="receipt-paper">
                    <div class="receipt-header">
                        <div class="receipt-logo">A</div>
                        <h2>AlphaPos</h2>
                        <p class="receipt-subtitle">${this.t('receipt', 'Receipt')}</p>
                    </div>

                    <div class="receipt-meta">
                        <div class="receipt-meta-row"><span>${this.t('transactionId', 'Transaction')}</span><span>#${paymentData?.transactionId || orderData.orderNumber || '---'}</span></div>
                        <div class="receipt-meta-row"><span>${this.t('tableBadgeText', 'Table {num}').replace('{num}', orderData.tableNumber || '--')}</span><span>${timeStr}</span></div>
                    </div>

                    <div class="receipt-divider"></div>

                    <div class="receipt-items">${itemsHTML}</div>

                    <div class="receipt-divider"></div>

                    <div class="receipt-totals">
                        <div class="receipt-line"><span>${this.t('subtotal', 'Subtotal')}</span><span>฿${calc.subtotal.toFixed(2)}</span></div>
                        <div class="receipt-line"><span>${this.t('serviceCharge', 'Service Charge')}</span><span>฿${calc.serviceCharge.toFixed(2)}</span></div>
                        <div class="receipt-line"><span>${this.t('vat', 'VAT')}</span><span>฿${calc.vat.toFixed(2)}</span></div>
                        ${calc.tipAmount > 0 ? `<div class="receipt-line"><span>${this.t('addTip', 'Tip')}</span><span>฿${calc.tipAmount.toFixed(2)}</span></div>` : ''}
                        <div class="receipt-line total"><span>${this.t('grandTotal', 'Total')}</span><span>฿${calc.grandTotal.toFixed(2)}</span></div>
                    </div>

                    <div class="receipt-divider"></div>

                    <div class="receipt-payment-info">
                        <span class="receipt-method-icon">${methodIcons[paymentMethod] || '💵'}</span>
                        <span class="receipt-method-name">${methodNames[paymentMethod] || paymentMethod}</span>
                        <span class="receipt-paid-badge">✓ ${this.t('paid', 'Paid')}</span>
                    </div>

                    <div class="receipt-qr" id="receiptQR">
                        <canvas id="receiptQRCanvas" width="120" height="120"></canvas>
                        <p class="receipt-qr-label">${this.t('scanForDigitalReceipt', 'Scan for digital receipt')}</p>
                    </div>

                    <div class="receipt-footer-text">
                        <p>${this.t('feedbackThanks', 'Thank you for dining with us!')}</p>
                    </div>
                </div>

                <div class="receipt-actions">
                    <button class="receipt-action-btn email" onclick="window._billView.showEmailPrompt()">
                        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="2" y="4" width="20" height="16" rx="2"/><path d="m22 7-10 5L2 7"/></svg>
                        ${this.t('emailReceipt', 'Email Receipt')}
                    </button>
                    <button class="receipt-action-btn close" onclick="window._billView.hideBill()">
                        ${this.t('done', 'Done')}
                    </button>
                </div>
            </div>
        `;
    }

    // ========================================
    // EMAIL RECEIPT
    // ========================================

    showEmailPrompt() {
        const existing = document.getElementById('emailPromptOverlay');
        if (existing) existing.remove();

        const overlay = document.createElement('div');
        overlay.id = 'emailPromptOverlay';
        overlay.className = 'email-prompt-overlay';
        overlay.innerHTML = `
            <div class="email-prompt-card">
                <h3>${this.t('emailReceipt', 'Email Receipt')}</h3>
                <input type="email" id="emailReceiptInput" placeholder="your@email.com" autocomplete="email">
                <div class="email-prompt-actions">
                    <button class="email-cancel" onclick="document.getElementById('emailPromptOverlay').remove()">${this.t('cancel', 'Cancel')}</button>
                    <button class="email-send" onclick="window._billView.sendEmailReceipt()">${this.t('send', 'Send')}</button>
                </div>
            </div>
        `;
        document.body.appendChild(overlay);
        setTimeout(() => overlay.classList.add('active'), 10);
        document.getElementById('emailReceiptInput')?.focus();
    }

    async sendEmailReceipt() {
        const email = document.getElementById('emailReceiptInput')?.value?.trim();
        if (!email || !email.includes('@')) return;

        try {
            // Send to server (placeholder endpoint)
            await fetch('/v1/receipt/email', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    email,
                    order_id: this.orderData?.orderId,
                    merchant_id: this.merchantId
                })
            });
        } catch (e) {
            console.warn('Email receipt send failed:', e);
        }

        // Remove prompt + show success
        document.getElementById('emailPromptOverlay')?.remove();
        if (window.app?.showToast) {
            window.app.showToast(`📧 ${this.t('receiptSent', 'Receipt sent to')} ${email}`);
        }
    }

    // ========================================
    // PAYMENT REQUEST (trigger app payment flow)
    // ========================================

    requestPayment() {
        const items = this.orderData?.items || [];
        const calc = this.calculateBill(items, this.orderData?.discounts || [], this.tipPercent, 0);
        const finalTip = this.tipPercent > 0 ? calc.tipAmount : this.tipAmount;

        // Dispatch custom event for app to handle payment
        const event = new CustomEvent('billPaymentRequested', {
            detail: {
                grandTotal: calc.grandTotal - calc.tipAmount + finalTip,
                tipAmount: finalTip,
                splitMode: this.splitMode,
                splitCount: this.splitCount,
                itemAssignments: this.itemAssignments
            }
        });
        window.dispatchEvent(event);

        this.hideBill();
    }

    // ========================================
    // UTILITIES
    // ========================================

    _escape(str) {
        if (!str) return '';
        const div = document.createElement('div');
        div.textContent = str;
        return div.innerHTML;
    }
}

// Singleton export
export const billView = new BillView();
window._billView = billView;
