import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fadeContent } from './motion.js';

test('reduced motion never starts a fade, including missing targets', () => {
    globalThis.window = { matchMedia: () => ({ matches: true }) };
    try {
        fadeContent(null);
        fadeContent({ animate() { assert.fail('animation must not start'); } });
    } finally {
        delete globalThis.window;
    }
});

test('category changes preserve controls and repeated selection does not redraw', () => {
    const source = readFileSync(new URL('../app.js', import.meta.url), 'utf8');
    const body = source.split('    switchCategory(categoryId) {')[1].split('\n    }')[0];
    const tabs = ['foods', 'drinks'].map(id => ({
        dataset: { categoryId: id },
        classList: { toggle(name, active) { this.active = active; } },
        setAttribute(name, value) { this[name] = value; },
    }));
    let renders = 0;
    const app = { currentCategory: 'foods', renderMenuItems() { renders++; } };
    const document = { querySelectorAll: () => tabs, getElementById: () => null };
    const change = new Function('categoryId', 'document', 'fadeContent', body);
    change.call(app, 'drinks', document, () => {});
    assert.equal(renders, 1);
    assert.equal(tabs[1]['aria-pressed'], 'true');
    assert.equal(tabs[0].classList.active, false);
    change.call(app, 'drinks', document, () => {});
    assert.equal(renders, 1);
});

test('cart quantity updates retain the row and controls, and removed items leave the DOM', () => {
    const source = readFileSync(new URL('../app.js', import.meta.url), 'utf8');
    const body = source.split('    renderDrawerCartList() {')[1].split('\n    }')[0];
    const price = { innerHTML: '' };
    const quantity = { textContent: '1' };
    const row = {
        dataset: { cartKey: 'dish' },
        querySelector(selector) { return selector === '.qty-value' ? quantity : price; },
        remove() { this.removed = true; },
    };
    const container = {
        querySelectorAll: () => [row],
        querySelector: () => null,
        appendChild() { assert.fail('existing row should not be replaced'); },
    };
    const document = {
        getElementById: id => id === 'cartItemsList' ? container : {},
        createElement() { assert.fail('existing row should be reused'); },
    };
    const app = {
        cart: { dish: { itemId: 'dish', quantity: 2 } },
        menuItems: [{ id: 'dish', price: 20 }],
        translate: key => key,
        getItemName: () => 'Dish',
    };
    const render = new Function('document', 'escapeHtml', body);
    render.call(app, document, value => value);
    assert.equal(quantity.textContent, 2);
    assert.match(price.innerHTML, /40\.00/);
    assert.equal(row.removed, undefined);
    app.menuItems = [];
    render.call(app, document, value => value);
    assert.equal(row.removed, true);
});
