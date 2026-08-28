const SESSION_ERROR_PATTERN = /(?:session_(?:closed|inactive|invalid)|invalid_session|expired|jwt expired|unauthori[sz]ed|permission denied|row-level security|\b401\b|\b403\b)/i;

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

