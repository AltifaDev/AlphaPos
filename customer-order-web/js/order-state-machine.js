export const ORDER_STATES = Object.freeze([
    'pending', 'confirmed', 'preparing', 'ready', 'served', 'completed', 'cancelled'
]);

const TRANSITIONS = Object.freeze({
    pending: new Set(['confirmed', 'preparing', 'cancelled']),
    confirmed: new Set(['preparing', 'cancelled']),
    preparing: new Set(['ready', 'cancelled']),
    ready: new Set(['served', 'cancelled']),
    served: new Set(['completed']),
    completed: new Set(),
    cancelled: new Set(),
});

export function normalizeOrderState(value) {
    const state = String(value || '').trim().toLowerCase();
    return ORDER_STATES.includes(state) ? state : null;
}

export function canTransitionOrder(from, to) {
    const current = normalizeOrderState(from);
    const next = normalizeOrderState(to);
    if (!next) return false;
    if (!current || current === next) return true;
    return TRANSITIONS[current]?.has(next) || false;
}
