import test from 'node:test';
import assert from 'node:assert/strict';
import { classifyOrderFailure } from './order-failure-state.js';

test('classifies closed and unauthorized sessions as blocked', () => {
    assert.equal(classifyOrderFailure({ message: 'session_closed' }), 'session-closed');
    assert.equal(classifyOrderFailure({ status: 401 }), 'session-closed');
    assert.equal(classifyOrderFailure({ message: 'permission denied for function create_customer_order' }), 'session-closed');
});

test('treats timeouts and unknown server failures as uncertain', () => {
    assert.equal(classifyOrderFailure(new TypeError('Failed to fetch')), 'uncertain');
    assert.equal(classifyOrderFailure({ status: 503, message: 'upstream timeout' }), 'uncertain');
});
