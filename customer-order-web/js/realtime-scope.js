const normalize = value => String(value ?? '').trim().toLowerCase();

export function belongsToCustomerSession(row, scope, requireIdentity = true) {
    if (!row || !normalize(scope.merchantId) || !normalize(scope.branchId) || !scope.sessionToken) return false;
    if (row.merchant_id && normalize(row.merchant_id) !== normalize(scope.merchantId)) return false;
    if (row.branch_id && normalize(row.branch_id) !== normalize(scope.branchId)) return false;
    if (row.table_session_id && normalize(row.table_session_id) !== normalize(scope.tableSessionId)) return false;
    if (row.session_token && row.session_token !== scope.sessionToken) return false;
    if (requireIdentity && !row.table_session_id && !row.session_token) return false;
    return true;
}

export function acceptOrderRevision(row, revisions) {
    if (!row?.id) return false;
    const next = Number(row.row_version || 0);
    if (!Number.isFinite(next) || next < 0) return false;
    const current = revisions.get(row.id) || 0;
    if (current > 0 && next === 0) return false;
    if (next > 0 && next <= current) return false;
    if (next > 0) revisions.set(row.id, next);
    return true;
}
