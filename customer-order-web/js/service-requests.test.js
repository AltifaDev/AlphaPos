import test from 'node:test';
import assert from 'node:assert/strict';
import { isMerchantTenderEnabled, ServiceRequestsMixin } from './service-requests.js';

test('merchant tender settings default to enabled for older or missing config', () => {
    assert.equal(isMerchantTenderEnabled({}, 'payment_method_cash_enabled'), true);
    assert.equal(isMerchantTenderEnabled(null, 'payment_method_cash_enabled'), true);
});

test('merchant tender settings accept booleans and SQLite values', () => {
    assert.equal(isMerchantTenderEnabled({ cash: true }, 'cash'), true);
    assert.equal(isMerchantTenderEnabled({ cash: 1 }, 'cash'), true);
    assert.equal(isMerchantTenderEnabled({ cash: false }, 'cash'), false);
    assert.equal(isMerchantTenderEnabled({ cash: 0 }, 'cash'), false);
    assert.equal(isMerchantTenderEnabled({ cash: 'false' }, 'cash'), false);
});

test('closed tender requests stop before reaching checkout services', async () => {
    const messages = [];
    const app = {
        merchantSettings: { payment_method_card_enabled: false },
        translate: (_key, fallback) => fallback,
        _showToast: message => messages.push(message)
    };

    await ServiceRequestsMixin.sendServiceRequest.call(app, 'Bill (Card)');

    assert.deepEqual(messages, ['This payment method is unavailable. Please ask staff for help.']);
});
