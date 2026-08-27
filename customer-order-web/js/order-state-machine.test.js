import test from 'node:test';
import assert from 'node:assert/strict';
import { canTransitionOrder, normalizeOrderState } from './order-state-machine.js';

test('accepts canonical committed order progression', () => {
    assert.equal(canTransitionOrder('pending', 'preparing'), true);
    assert.equal(canTransitionOrder('preparing', 'ready'), true);
    assert.equal(canTransitionOrder('ready', 'served'), true);
    assert.equal(canTransitionOrder('served', 'completed'), true);
});

test('rejects regression and changes after terminal states', () => {
    assert.equal(canTransitionOrder('ready', 'preparing'), false);
    assert.equal(canTransitionOrder('completed', 'pending'), false);
    assert.equal(canTransitionOrder('cancelled', 'preparing'), false);
});

test('normalizes known states and rejects unknown values', () => {
    assert.equal(normalizeOrderState(' READY '), 'ready');
    assert.equal(normalizeOrderState('paid'), null);
});
