export function cartStorageKey(tableNumber) {
    return `cart_T${tableNumber}`;
}

export function saveCart(tableNumber, cart) {
    if (!tableNumber) return;
    localStorage.setItem(cartStorageKey(tableNumber), JSON.stringify(cart));
}

export function loadCart(tableNumber) {
    if (!tableNumber) return {};
    const saved = localStorage.getItem(cartStorageKey(tableNumber));
    if (!saved) return {};
    return JSON.parse(saved);
}

export function clearCart(tableNumber) {
    if (!tableNumber) return;
    localStorage.removeItem(cartStorageKey(tableNumber));
}
