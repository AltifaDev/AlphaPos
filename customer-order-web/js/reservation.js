/**
 * AlphaPos - Table Reservation System
 * 
 * Allows customers to reserve tables in advance.
 * Uses Supabase `table_reservations` table + `check_table_availability` RPC.
 */

export class ReservationSystem {
    constructor() {
        this.supabase = null;
        this.merchantId = '';
        this.settings = {
            maxPartySize: 12,
            slotDuration: 90,
            advanceDays: 30,
            openTime: '10:00',
            closeTime: '22:00',
            slotInterval: 30 // minutes between slots
        };
        this.selectedDate = null;
        this.selectedTime = null;
        this.selectedPartySize = 2;
        this.availableSlots = [];
        this.myReservations = [];
        this._translate = (key, fallback) => {
            if (window.app && typeof window.app.translate === 'function') {
                return window.app.translate(key, fallback);
            }
            return fallback;
        };
    }

    /**
     * Initialize the reservation system
     */
    async init(supabaseClient, merchantId) {
        this.supabase = supabaseClient;
        this.merchantId = merchantId;

        // Fetch merchant reservation settings
        if (this.supabase) {
            try {
                const { data } = await this.supabase
                    .from('merchants')
                    .select('reservation_enabled, max_party_size, slot_duration_minutes, reservation_advance_days')
                    .eq('id', merchantId)
                    .single();

                if (data) {
                    if (data.max_party_size) this.settings.maxPartySize = data.max_party_size;
                    if (data.slot_duration_minutes) this.settings.slotDuration = data.slot_duration_minutes;
                    if (data.reservation_advance_days) this.settings.advanceDays = data.reservation_advance_days;
                }
            } catch (e) {
                console.warn('[Reservation] Failed to fetch merchant settings:', e);
            }
        }
    }

    /**
     * Show the reservation form (injected as overlay)
     */
    showReservationForm() {
        this._injectDOM();
        const panel = document.getElementById('reservationPanel');
        if (panel) {
            panel.classList.remove('hidden');
            panel.classList.add('active');
            document.body.style.overflow = 'hidden';
            this._renderDatePicker();
            this._renderPartySizeSelector();
        }
    }

    /**
     * Hide reservation form
     */
    hideReservationForm() {
        const panel = document.getElementById('reservationPanel');
        if (panel) {
            panel.classList.remove('active');
            setTimeout(() => panel.classList.add('hidden'), 300);
            document.body.style.overflow = '';
        }
    }

    /**
     * Check table availability for a given date + party size
     */
    async checkAvailability(date, partySize) {
        this.availableSlots = [];
        const container = document.getElementById('reservationTimeSlots');
        if (container) {
            container.innerHTML = '<div class="reservation-loading"><div class="reservation-spinner"></div></div>';
        }

        try {
            // Try Supabase RPC
            if (this.supabase && this.merchantId) {
                const { data, error } = await this.supabase.rpc('check_table_availability', {
                    p_merchant_id: this.merchantId,
                    p_date: date,
                    p_party_size: partySize,
                    p_duration: this.settings.slotDuration
                });

                if (!error && data) {
                    this.availableSlots = data.available_slots || [];
                    this._renderTimeSlots();
                    return;
                }
            }

            // Fallback: try local API
            const res = await fetch(`/v1/reservations/availability?date=${date}&party_size=${partySize}`);
            if (res.ok) {
                const result = await res.json();
                this.availableSlots = result.available_slots || [];
            } else {
                // Generate default slots
                this.availableSlots = this._generateDefaultSlots();
            }
        } catch (e) {
            console.warn('[Reservation] Availability check failed:', e);
            this.availableSlots = this._generateDefaultSlots();
        }

        this._renderTimeSlots();
    }

    /**
     * Submit a reservation
     */
    async submitReservation(data) {
        const { customerName, customerPhone, customerEmail, date, time, partySize, specialRequests } = data;

        const reservation = {
            id: crypto.randomUUID ? crypto.randomUUID() : this._generateUUID(),
            merchant_id: this.merchantId,
            customer_name: customerName,
            customer_phone: customerPhone,
            customer_email: customerEmail || null,
            reservation_date: date,
            reservation_time: time,
            party_size: partySize,
            duration_minutes: this.settings.slotDuration,
            special_requests: specialRequests || null,
            status: 'pending'
        };

        try {
            // Try Supabase
            if (this.supabase) {
                const { data: result, error } = await this.supabase
                    .from('table_reservations')
                    .insert(reservation)
                    .select()
                    .single();

                if (!error && result) {
                    this._showConfirmation(result);
                    return result;
                }
            }

            // Fallback: local API
            const res = await fetch('/v1/reservations', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(reservation)
            });

            if (res.ok) {
                const result = await res.json();
                this._showConfirmation(result);
                return result;
            } else {
                const err = await res.json();
                this._showError(err.error || 'Failed to create reservation');
                return null;
            }
        } catch (e) {
            console.error('[Reservation] Submit failed:', e);
            this._showError('Network error. Please try again.');
            return null;
        }
    }

    /**
     * Show my reservations
     */
    async showMyReservations() {
        const phone = localStorage.getItem('alphapos_reservation_phone');
        if (!phone) {
            this._showMyReservationsEmpty();
            return;
        }

        try {
            if (this.supabase) {
                const { data } = await this.supabase
                    .from('table_reservations')
                    .select('*')
                    .eq('merchant_id', this.merchantId)
                    .eq('customer_phone', phone)
                    .neq('status', 'cancelled')
                    .gte('reservation_date', new Date().toISOString().split('T')[0])
                    .order('reservation_date', { ascending: true });

                if (data) {
                    this.myReservations = data;
                    this._renderMyReservations();
                    return;
                }
            }

            // Fallback local
            const res = await fetch(`/v1/reservations?phone=${encodeURIComponent(phone)}`);
            if (res.ok) {
                this.myReservations = await res.json();
                this._renderMyReservations();
            }
        } catch (e) {
            console.warn('[Reservation] Fetch reservations failed:', e);
        }
    }

    /**
     * Cancel a reservation
     */
    async cancelReservation(id) {
        try {
            if (this.supabase) {
                await this.supabase
                    .from('table_reservations')
                    .update({ status: 'cancelled', updated_at: new Date().toISOString() })
                    .eq('id', id);
            } else {
                await fetch(`/v1/reservations/${id}`, { method: 'DELETE' });
            }
            // Refresh list
            this.myReservations = this.myReservations.filter(r => r.id !== id);
            this._renderMyReservations();
            if (window.app) window.app.showToast(this._translate('reservationCancelled', 'Reservation cancelled'));
        } catch (e) {
            console.error('[Reservation] Cancel failed:', e);
        }
    }

    /**
     * Generate Google Calendar link
     */
    generateCalendarLink(reservation) {
        const date = reservation.reservation_date;
        const time = reservation.reservation_time;
        const duration = reservation.duration_minutes || 90;
        
        const startDT = new Date(`${date}T${time}`);
        const endDT = new Date(startDT.getTime() + duration * 60000);

        const fmt = (d) => d.toISOString().replace(/[-:]/g, '').replace(/\.\d{3}/, '');
        
        const title = encodeURIComponent(`Table Reservation - AlphaPos`);
        const details = encodeURIComponent(
            `Party size: ${reservation.party_size}\n` +
            `Booking ref: ${reservation.id.slice(0, 8).toUpperCase()}\n` +
            (reservation.special_requests ? `Requests: ${reservation.special_requests}` : '')
        );

        return `https://calendar.google.com/calendar/render?action=TEMPLATE&text=${title}&dates=${fmt(startDT)}/${fmt(endDT)}&details=${details}`;
    }

    // ======================
    // Private: DOM Injection
    // ======================

    _injectDOM() {
        if (document.getElementById('reservationPanel')) return;

        const html = `
        <div id="reservationPanel" class="reservation-panel hidden" role="dialog" aria-modal="true" aria-label="Table Reservation">
            <div class="reservation-backdrop" onclick="window._reservationSystem.hideReservationForm()"></div>
            <div class="reservation-content">
                <!-- Header -->
                <div class="reservation-header">
                    <button class="reservation-close-btn" onclick="window._reservationSystem.hideReservationForm()" aria-label="Close">
                        <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M18 6L6 18M6 6l12 12"/></svg>
                    </button>
                    <h2 class="reservation-title">${this._translate('reserveTable', 'Reserve a Table')}</h2>
                    <p class="reservation-subtitle">${this._translate('reserveSubtitle', 'Book your table in advance')}</p>
                </div>

                <!-- Form Steps -->
                <div class="reservation-body" id="reservationBody">
                    <!-- Step 1: Date + Party Size -->
                    <div id="reservationStep1" class="reservation-step active">
                        <div class="reservation-section">
                            <label class="reservation-label">${this._translate('partySize', 'Party Size')}</label>
                            <div class="reservation-party-selector" id="reservationPartySelector"></div>
                        </div>
                        <div class="reservation-section">
                            <label class="reservation-label">${this._translate('selectDate', 'Select Date')}</label>
                            <div class="reservation-date-picker" id="reservationDatePicker"></div>
                        </div>
                        <div class="reservation-section">
                            <label class="reservation-label">${this._translate('selectTime', 'Select Time')}</label>
                            <div class="reservation-time-slots" id="reservationTimeSlots">
                                <div class="reservation-hint">${this._translate('selectDateFirst', 'Select a date to see available times')}</div>
                            </div>
                        </div>
                    </div>

                    <!-- Step 2: Contact Info -->
                    <div id="reservationStep2" class="reservation-step">
                        <div class="reservation-section">
                            <label class="reservation-label">${this._translate('yourName', 'Your Name')} *</label>
                            <input type="text" id="reservationName" class="reservation-input" placeholder="John Doe" required maxlength="100">
                        </div>
                        <div class="reservation-section">
                            <label class="reservation-label">${this._translate('phoneNumber', 'Phone Number')} *</label>
                            <input type="tel" id="reservationPhone" class="reservation-input" placeholder="0812345678" required maxlength="15">
                        </div>
                        <div class="reservation-section">
                            <label class="reservation-label">${this._translate('email', 'Email')} (${this._translate('optional', 'optional')})</label>
                            <input type="email" id="reservationEmail" class="reservation-input" placeholder="email@example.com" maxlength="255">
                        </div>
                        <div class="reservation-section">
                            <label class="reservation-label">${this._translate('specialRequests', 'Special Requests')}</label>
                            <textarea id="reservationRequests" class="reservation-textarea" placeholder="${this._translate('specialRequestsPlaceholder', 'Allergies, occasion, seating preferences...')}" maxlength="500" rows="3"></textarea>
                        </div>
                    </div>

                    <!-- Step 3: Confirmation -->
                    <div id="reservationStep3" class="reservation-step">
                        <div class="reservation-confirmation" id="reservationConfirmation"></div>
                    </div>

                    <!-- My Reservations View -->
                    <div id="reservationMyList" class="reservation-step">
                        <div class="reservation-my-list" id="reservationMyListContent"></div>
                    </div>
                </div>

                <!-- Footer Actions -->
                <div class="reservation-footer" id="reservationFooter">
                    <button class="reservation-btn-secondary" id="reservationBackBtn" onclick="window._reservationSystem._prevStep()" style="display:none">
                        ${this._translate('back', 'Back')}
                    </button>
                    <button class="reservation-btn-primary" id="reservationNextBtn" onclick="window._reservationSystem._nextStep()">
                        ${this._translate('checkAvailability', 'Check Availability')}
                    </button>
                    <button class="reservation-btn-link" id="reservationMyBtn" onclick="window._reservationSystem._showMyReservationsView()">
                        ${this._translate('myReservations', 'My Reservations')}
                    </button>
                </div>
            </div>
        </div>`;

        document.body.insertAdjacentHTML('beforeend', html);
    }

    // ======================
    // Private: Date Picker
    // ======================

    _renderDatePicker() {
        const container = document.getElementById('reservationDatePicker');
        if (!container) return;

        const today = new Date();
        const maxDate = new Date(today);
        maxDate.setDate(maxDate.getDate() + this.settings.advanceDays);

        let html = '<div class="reservation-date-grid">';
        
        const current = new Date(today);
        const dayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

        for (let i = 0; i < Math.min(this.settings.advanceDays, 14); i++) {
            const d = new Date(current);
            d.setDate(d.getDate() + i);
            const dateStr = d.toISOString().split('T')[0];
            const isToday = i === 0;
            const dayName = dayNames[d.getDay()];
            const dayNum = d.getDate();
            const monthName = d.toLocaleString('default', { month: 'short' });

            html += `
                <button class="reservation-date-card ${isToday ? 'today' : ''} ${this.selectedDate === dateStr ? 'selected' : ''}"
                        onclick="window._reservationSystem._selectDate('${dateStr}')"
                        data-date="${dateStr}">
                    <span class="reservation-date-day">${dayName}</span>
                    <span class="reservation-date-num">${dayNum}</span>
                    <span class="reservation-date-month">${monthName}</span>
                </button>`;
        }

        html += '</div>';
        container.innerHTML = html;
    }

    _selectDate(dateStr) {
        this.selectedDate = dateStr;
        this.selectedTime = null;
        
        // Update selected state
        document.querySelectorAll('.reservation-date-card').forEach(el => {
            el.classList.toggle('selected', el.dataset.date === dateStr);
        });

        // Check availability
        this.checkAvailability(dateStr, this.selectedPartySize);
    }

    // ======================
    // Private: Party Size
    // ======================

    _renderPartySizeSelector() {
        const container = document.getElementById('reservationPartySelector');
        if (!container) return;

        let html = '';
        for (let i = 1; i <= Math.min(this.settings.maxPartySize, 12); i++) {
            html += `
                <button class="reservation-party-pill ${i === this.selectedPartySize ? 'selected' : ''}"
                        onclick="window._reservationSystem._selectPartySize(${i})">
                    ${i}${i >= 10 ? '+' : ''}
                </button>`;
        }
        container.innerHTML = html;
    }

    _selectPartySize(size) {
        this.selectedPartySize = size;
        document.querySelectorAll('.reservation-party-pill').forEach(el => {
            el.classList.toggle('selected', parseInt(el.textContent) === size);
        });

        // Re-check if date already selected
        if (this.selectedDate) {
            this.checkAvailability(this.selectedDate, size);
        }
    }

    // ======================
    // Private: Time Slots
    // ======================

    _renderTimeSlots() {
        const container = document.getElementById('reservationTimeSlots');
        if (!container) return;

        if (this.availableSlots.length === 0) {
            container.innerHTML = `
                <div class="reservation-no-slots">
                    <span class="reservation-no-slots-icon">📅</span>
                    <p>${this._translate('noAvailability', 'No tables available for this date')}</p>
                </div>`;
            return;
        }

        let html = '<div class="reservation-time-grid">';
        for (const slot of this.availableSlots) {
            const time = typeof slot === 'string' ? slot : slot.time;
            const available = typeof slot === 'object' ? slot.available !== false : true;
            const tables = typeof slot === 'object' ? slot.tables_available : null;

            html += `
                <button class="reservation-time-slot ${available ? 'available' : 'unavailable'} ${this.selectedTime === time ? 'selected' : ''}"
                        onclick="window._reservationSystem._selectTime('${time}')"
                        ${!available ? 'disabled' : ''}>
                    <span class="reservation-time-text">${time}</span>
                    ${tables !== null ? `<span class="reservation-time-tables">${tables} ${this._translate('tablesLeft', 'left')}</span>` : ''}
                </button>`;
        }
        html += '</div>';
        container.innerHTML = html;
    }

    _selectTime(time) {
        this.selectedTime = time;
        document.querySelectorAll('.reservation-time-slot').forEach(el => {
            el.classList.toggle('selected', el.querySelector('.reservation-time-text')?.textContent === time);
        });
    }

    // ======================
    // Private: Steps
    // ======================

    _currentStep = 1;

    _nextStep() {
        if (this._currentStep === 1) {
            // Validate date + time selected
            if (!this.selectedDate || !this.selectedTime) {
                if (window.app) window.app.showToast(this._translate('selectDateAndTime', 'Please select a date and time'), 'warning');
                return;
            }
            this._currentStep = 2;
            this._showStep(2);
            document.getElementById('reservationBackBtn').style.display = '';
            document.getElementById('reservationNextBtn').textContent = this._translate('confirmReservation', 'Confirm Reservation');
            document.getElementById('reservationMyBtn').style.display = 'none';
        } else if (this._currentStep === 2) {
            // Validate contact info
            const name = document.getElementById('reservationName')?.value?.trim();
            const phone = document.getElementById('reservationPhone')?.value?.trim();

            if (!name || !phone) {
                if (window.app) window.app.showToast(this._translate('fillRequired', 'Please fill in required fields'), 'warning');
                return;
            }

            if (!/^\d{9,15}$/.test(phone.replace(/[-\s]/g, ''))) {
                if (window.app) window.app.showToast(this._translate('invalidPhone', 'Invalid phone number'), 'warning');
                return;
            }

            // Save phone for future lookups
            localStorage.setItem('alphapos_reservation_phone', phone);

            // Submit
            this.submitReservation({
                customerName: name,
                customerPhone: phone,
                customerEmail: document.getElementById('reservationEmail')?.value?.trim() || '',
                date: this.selectedDate,
                time: this.selectedTime,
                partySize: this.selectedPartySize,
                specialRequests: document.getElementById('reservationRequests')?.value?.trim() || ''
            });
        }
    }

    _prevStep() {
        if (this._currentStep === 2) {
            this._currentStep = 1;
            this._showStep(1);
            document.getElementById('reservationBackBtn').style.display = 'none';
            document.getElementById('reservationNextBtn').textContent = this._translate('checkAvailability', 'Check Availability');
            document.getElementById('reservationMyBtn').style.display = '';
        } else if (this._currentStep === 4) {
            // From my reservations back to form
            this._currentStep = 1;
            this._showStep(1);
            document.getElementById('reservationBackBtn').style.display = 'none';
            document.getElementById('reservationNextBtn').style.display = '';
            document.getElementById('reservationMyBtn').style.display = '';
            document.getElementById('reservationFooter').style.display = '';
        }
    }

    _showStep(step) {
        document.querySelectorAll('.reservation-step').forEach(el => el.classList.remove('active'));
        const stepEl = document.getElementById(`reservationStep${step}`);
        if (stepEl) stepEl.classList.add('active');
        if (step === 4) {
            document.getElementById('reservationMyList')?.classList.add('active');
        }
    }

    _showMyReservationsView() {
        this._currentStep = 4;
        this._showStep(4);
        document.getElementById('reservationBackBtn').style.display = '';
        document.getElementById('reservationNextBtn').style.display = 'none';
        document.getElementById('reservationMyBtn').style.display = 'none';
        this.showMyReservations();
    }

    // ======================
    // Private: Confirmation
    // ======================

    _showConfirmation(reservation) {
        this._currentStep = 3;
        this._showStep(3);
        document.getElementById('reservationFooter').style.display = 'none';

        const container = document.getElementById('reservationConfirmation');
        const calLink = this.generateCalendarLink(reservation);
        const refCode = (reservation.id || '').slice(0, 8).toUpperCase();

        container.innerHTML = `
            <div class="reservation-success-anim">
                <div class="reservation-success-circle">
                    <svg class="reservation-checkmark" viewBox="0 0 52 52">
                        <circle cx="26" cy="26" r="25" fill="none" stroke="var(--success)" stroke-width="2"/>
                        <path fill="none" stroke="var(--success)" stroke-width="3" stroke-linecap="round" d="M14.1 27.2l7.1 7.2 16.7-16.8"/>
                    </svg>
                </div>
                <h3 class="reservation-success-title">${this._translate('reservationConfirmed', 'Reservation Confirmed!')}</h3>
            </div>
            <div class="reservation-summary-card">
                <div class="reservation-summary-row">
                    <span class="reservation-summary-label">${this._translate('bookingRef', 'Booking Reference')}</span>
                    <span class="reservation-summary-value reservation-ref-code">${refCode}</span>
                </div>
                <div class="reservation-summary-row">
                    <span class="reservation-summary-label">${this._translate('selectDate', 'Date')}</span>
                    <span class="reservation-summary-value">${this._formatDate(reservation.reservation_date)}</span>
                </div>
                <div class="reservation-summary-row">
                    <span class="reservation-summary-label">${this._translate('selectTime', 'Time')}</span>
                    <span class="reservation-summary-value">${reservation.reservation_time}</span>
                </div>
                <div class="reservation-summary-row">
                    <span class="reservation-summary-label">${this._translate('partySize', 'Party Size')}</span>
                    <span class="reservation-summary-value">${reservation.party_size} ${this._translate('guests', 'guests')}</span>
                </div>
                ${reservation.special_requests ? `
                <div class="reservation-summary-row">
                    <span class="reservation-summary-label">${this._translate('specialRequests', 'Special Requests')}</span>
                    <span class="reservation-summary-value">${reservation.special_requests}</span>
                </div>` : ''}
            </div>
            <div class="reservation-actions-row">
                <a href="${calLink}" target="_blank" class="reservation-btn-calendar">
                    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="4" width="18" height="18" rx="2"/><path d="M16 2v4M8 2v4M3 10h18"/></svg>
                    ${this._translate('addToCalendar', 'Add to Calendar')}
                </a>
                <button class="reservation-btn-done" onclick="window._reservationSystem.hideReservationForm()">
                    ${this._translate('done', 'Done')}
                </button>
            </div>
        `;
    }

    _showError(message) {
        if (window.app) {
            window.app.showToast(message, 'error');
        } else {
            alert(message);
        }
    }

    // ======================
    // Private: My Reservations
    // ======================

    _renderMyReservations() {
        const container = document.getElementById('reservationMyListContent');
        if (!container) return;

        if (!this.myReservations || this.myReservations.length === 0) {
            this._showMyReservationsEmpty();
            return;
        }

        let html = `<h3 class="reservation-my-title">${this._translate('myReservations', 'My Reservations')}</h3>`;
        
        for (const r of this.myReservations) {
            const refCode = (r.id || '').slice(0, 8).toUpperCase();
            const statusClass = r.status === 'confirmed' ? 'confirmed' : r.status === 'pending' ? 'pending' : 'cancelled';
            const statusText = this._translate(`status_${r.status}`, r.status);

            html += `
                <div class="reservation-card" data-id="${r.id}">
                    <div class="reservation-card-header">
                        <span class="reservation-card-ref">#${refCode}</span>
                        <span class="reservation-status-badge ${statusClass}">${statusText}</span>
                    </div>
                    <div class="reservation-card-body">
                        <div class="reservation-card-detail">
                            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="4" width="18" height="18" rx="2"/><path d="M16 2v4M8 2v4M3 10h18"/></svg>
                            <span>${this._formatDate(r.reservation_date)} at ${r.reservation_time}</span>
                        </div>
                        <div class="reservation-card-detail">
                            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M17 21v-2a4 4 0 00-4-4H5a4 4 0 00-4 4v2"/><circle cx="9" cy="7" r="4"/></svg>
                            <span>${r.party_size} ${this._translate('guests', 'guests')}</span>
                        </div>
                    </div>
                    ${r.status !== 'cancelled' ? `
                    <div class="reservation-card-actions">
                        <button class="reservation-cancel-btn" onclick="window._reservationSystem.cancelReservation('${r.id}')">
                            ${this._translate('cancelReservation', 'Cancel')}
                        </button>
                    </div>` : ''}
                </div>`;
        }

        container.innerHTML = html;
    }

    _showMyReservationsEmpty() {
        const container = document.getElementById('reservationMyListContent');
        if (!container) return;
        container.innerHTML = `
            <div class="reservation-empty">
                <span class="reservation-empty-icon">📋</span>
                <p>${this._translate('noReservations', 'No upcoming reservations')}</p>
            </div>`;
    }

    // ======================
    // Private: Helpers
    // ======================

    _generateDefaultSlots() {
        const slots = [];
        const [openH, openM] = this.settings.openTime.split(':').map(Number);
        const [closeH, closeM] = this.settings.closeTime.split(':').map(Number);
        let h = openH, m = openM;

        while (h < closeH || (h === closeH && m < closeM)) {
            const time = `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}`;
            slots.push({ time, available: true });
            m += this.settings.slotInterval;
            if (m >= 60) { h++; m -= 60; }
        }
        return slots;
    }

    _formatDate(dateStr) {
        try {
            const d = new Date(dateStr + 'T00:00:00');
            return d.toLocaleDateString(undefined, { weekday: 'short', month: 'short', day: 'numeric' });
        } catch {
            return dateStr;
        }
    }

    _generateUUID() {
        return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, c => {
            const r = Math.random() * 16 | 0;
            return (c === 'x' ? r : (r & 0x3 | 0x8)).toString(16);
        });
    }
}

// Singleton export
export const reservationSystem = new ReservationSystem();

// Expose globally for onclick handlers
window._reservationSystem = reservationSystem;
