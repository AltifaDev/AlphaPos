/**
 * AlphaPos — Service Requests Module
 * Handles call staff, request bill, and other service requests.
 */

export const ServiceRequestsMixin = {
    async sendServiceRequest(type) {
        try {
            const response = await fetch('/v1/requests', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    table_number: this.tableNumber,
                    request_type: type
                })
            });

            if (response.ok) {
                const typeMap = {
                    'call_staff': this.translate('staffCalled', 'Staff has been called'),
                    'request_bill': this.translate('billRequested', 'Bill has been requested'),
                    'water': this.translate('waterRequested', 'Water requested'),
                    'napkin': this.translate('napkinRequested', 'Napkins requested'),
                    'cutlery': this.translate('cutleryRequested', 'Cutlery requested'),
                };
                this._showToast(typeMap[type] || 'Request sent', 'success');
            } else {
                throw new Error('Request failed');
            }
        } catch (e) {
            console.error('[Request] Failed:', e);
            this._showToast('Failed to send request', 'error');
        }
    },

    callStaff() {
        this.sendServiceRequest('call_staff');
    },

    requestBill() {
        this.sendServiceRequest('request_bill');
    },

    requestWater() {
        this.sendServiceRequest('water');
    }
};
