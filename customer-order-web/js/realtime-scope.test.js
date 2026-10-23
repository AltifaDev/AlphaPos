import test from 'node:test';
import assert from 'node:assert/strict';
import { belongsToCustomerSession, acceptOrderRevision } from './realtime-scope.js';

const scope = { merchantId: 'merchant-a', branchId: 'branch-a', tableSessionId: 'visit-a', sessionToken: 'token-a' };
const row = { id: 'order-a', merchant_id: 'merchant-a', branch_id: 'branch-a', table_session_id: 'visit-a', session_token: 'token-a' };

test('reused table names do not authorize another merchant, branch or visit', () => {
    assert.equal(belongsToCustomerSession(row, scope), true);
    for (const [key, value] of [['merchant_id','merchant-b'], ['branch_id','branch-b'], ['table_session_id','visit-b'], ['session_token','token-b']]) {
        assert.equal(belongsToCustomerSession({ ...row, [key]: value }, scope), false);
    }
    assert.equal(belongsToCustomerSession({ id: 'other' }, scope), false);
});

test('duplicate or out-of-order realtime notifications cannot rewind an order', () => {
    const revisions = new Map();
    assert.equal(acceptOrderRevision({ ...row, row_version: 5 }, revisions), true);
    assert.equal(acceptOrderRevision({ ...row, row_version: 4 }, revisions), false);
    assert.equal(acceptOrderRevision({ ...row, row_version: 5 }, revisions), false);
    assert.equal(acceptOrderRevision({ ...row, row_version: 6 }, revisions), true);
});
