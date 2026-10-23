const SESSION_ERROR_PATTERN = /(?:session_(?:closed|inactive|invalid|is_closed)|invalid_session|order_requires_exactly_one_open_register|order_register_is_closed_or_outside_window|register_scope_mismatch|expired|jwt expired|unauthori[sz]ed|permission denied|row-level security|\b401\b|\b403\b)/i;

/**
 * Turn PostgREST/network failures into a customer-safe state. Unknown failures
 * are deliberately "uncertain": the request may have committed before the
 * browser lost the response, so the same saved idempotency key must be reused.
 */
export function classifyOrderFailure(error) {
    const detail = [error?.code, error?.message, error?.details, error?.hint, error?.status]
        .filter(Boolean)
        .join(' ');

    if (SESSION_ERROR_PATTERN.test(detail)) return 'session-closed';
    return 'uncertain';
}

/** Persist before HTTP; changed cart cannot replace a request with an unknown outcome. */
export function freezeCustomerRequest(attempt, fingerprint, payload) {
    if (attempt.fingerprint !== fingerprint) throw new Error('unconfirmed_order_changed');
    return attempt.payload ? attempt : { ...attempt, payload };
}
