/**
 * AlphaPos — Service Requests Module
 * Handles call staff, request bill, and other service requests.
 * Uses PostgreSQL RPC create_customer_service_request with idempotency keys.
 */

export const ServiceRequestsMixin = {
    async sendServiceRequest(rawType) {
        const canonicalTypeMap = {
            'call_staff': 'General Help',
            'general_help': 'General Help',
            'request_bill': 'Bill (QR)',
            'bill_cash': 'Bill (Cash)',
            'bill_card': 'Bill (Card)',
            'bill_qr': 'Bill (QR)',
            'water': 'Ice/Water',
            'ice_water': 'Ice/Water',
            'napkin': 'Extra Utensils',
            'cutlery': 'Extra Utensils',
            'utensils': 'Extra Utensils'
        };

        const canonicalType = canonicalTypeMap[rawType] || rawType;
        const validTypes = new Set(['Bill (Cash)', 'Bill (Card)', 'Bill (QR)', 'Ice/Water', 'Extra Utensils', 'General Help']);
        const requestType = validTypes.has(canonicalType) ? canonicalType : 'General Help';

        const labelKeyMap = {
            'Bill (Cash)': 'payCash',
            'Bill (Card)': 'payCard',
            'Bill (QR)': 'payQR',
            'Ice/Water': 'getWater',
            'Extra Utensils': 'utensils',
            'General Help': 'callStaffBtn'
        };

        const label = this.translate(labelKeyMap[requestType] || requestType, requestType);
        this._showStatusModal?.(this.translate('callingStaff', 'Calling staff...'), this.translate('callingStaffDesc', 'Please wait a moment.'), false);

        const idempotencyKey = (typeof crypto !== 'undefined' && crypto.randomUUID)
            ? crypto.randomUUID()
            : 'req-' + Date.now() + '-' + Math.random().toString(36).slice(2, 9);

        let success = false;

        if (this.supabase) {
            try {
                const { data, error } = await this.supabase.rpc('create_customer_service_request', {
                    p_request_type: requestType,
                    p_idempotency_key: idempotencyKey
                });
                if (error) throw error;
                success = true;
            } catch (err) {
                console.warn('[ServiceRequest] Supabase RPC failed, trying local fallback:', err);
            }
        }

        if (!success && this.isLocalServerAvailable && !window.ALPHAPOS_CONFIG?.isProduction) {
            try {
                const res = await fetch(`${this.localServerURL || ''}/v1/requests`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({
                        table_number: this.tableNumber,
                        request_type: requestType,
                        id: idempotencyKey,
                        merchant_id: this.merchantId,
                        branch_id: this.branchId,
                        branch_code: this.branchCode
                    })
                });
                if (res.ok) {
                    success = true;
                }
            } catch (localErr) {
                console.error('[ServiceRequest] Local server fallback failed:', localErr);
            }
        }

        if (success) {
            const activeNotif = document.getElementById('activeRequestNotification');
            const activeType = document.getElementById('activeRequestType');
            if (activeType && activeNotif) {
                activeType.innerText = label;
                activeNotif.classList.remove('hide');
                if (this._serviceRequestTimeout) clearTimeout(this._serviceRequestTimeout);
                this._serviceRequestTimeout = setTimeout(() => activeNotif.classList.add('hide'), 10000);
            }
            this._showStatusModal?.(
                this.translate('staffCalledSuccess', 'Staff notified!'),
                `${this.translate('staffCalled', 'Requested')}: ${label}. ${this.translate('staffCalledSuccessDesc', 'Staff is on their way.')}`,
                true
            );
            setTimeout(() => this._hideStatusModal?.(), 2000);
        } else {
            this._hideStatusModal?.();
            this._showToast?.(this.translate('serviceCallFailed', 'Could not reach staff. Please call directly.'), 5000);
        }
    },

    callStaff() {
        this.sendServiceRequest('General Help');
    },

    requestBill(method = 'QR') {
        if (method === 'Cash') this.sendServiceRequest('Bill (Cash)');
        else if (method === 'Card') this.sendServiceRequest('Bill (Card)');
        else this.sendServiceRequest('Bill (QR)');
    },

    requestWater() {
        this.sendServiceRequest('Ice/Water');
    },

    requestUtensils() {
        this.sendServiceRequest('Extra Utensils');
    }
};
