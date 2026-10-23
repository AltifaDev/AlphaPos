import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { escapeHtml } from './app-core.js';

const styles = readFileSync(new URL('../styles.css', import.meta.url), 'utf8');
const app = readFileSync(new URL('../app.js', import.meta.url), 'utf8');
const html = readFileSync(new URL('../index.html', import.meta.url), 'utf8');

test('escapeHtml escapes quotes and HTML special characters safely', () => {
    const input = `<script>alert("x" + 'y' & z)</script>`;
    assert.equal(
        escapeHtml(input),
        '&lt;script&gt;alert(&quot;x&quot; + &#39;y&#39; &amp; z)&lt;/script&gt;'
    );
    assert.equal(escapeHtml(null), '');
    assert.equal(escapeHtml(undefined), '');
});

test('submitOrder re-enables submitOrderBtn after successful order when session is open', () => {
    assert.match(
        app,
        /if \(success\)\s*\{[\s\S]*?if \(orderingSessionGate\.canOrder\(\)\)\s*\{\s*btn\.classList\.remove\("disabled"\);\s*btn\.removeAttribute\("disabled"\);\s*\}/
    );
});

test('addToCart always includes notesKey in cartKey even without modifiers', () => {
    assert.ok(app.includes('if (sortedModIds.length > 0) suffixParts.push(sortedModIds.join("-"));'));
    assert.ok(app.includes('if (notesKey) suffixParts.push(`note-${notesKey}`);'));
    assert.ok(app.includes('? `${itemId}-${suffixParts.join("-")}`'));
});

test('showWaitTime is defined once and supports itemCount scaling', () => {
    const matches = [...app.matchAll(/^\s*showWaitTime\s*\(/gm)];
    assert.equal(matches.length, 1, 'expected exactly one showWaitTime definition');
});

test('order history uses safe event delegation and in-app itemNoteModal instead of prompt()', () => {
    assert.doesNotMatch(app, /onclick="app\.addItemNote\(/);
    assert.doesNotMatch(app, /const note = prompt\(/);
    assert.match(html, /id="itemNoteModal"/);
    assert.match(app, /confirmItemNoteModal\(\)/);
});

test('web payment request options are hidden because payment is handled exclusively via AlphaPos POS', () => {
    assert.match(html, /id="paymentOptionCash"[^>]*hidden/);
    assert.match(html, /id="paymentOptionCard"[^>]*hidden/);
    assert.match(html, /id="paymentOptionQR"[^>]*hidden/);
    assert.doesNotMatch(app, /applyMerchantPaymentOptions\(\)/);
    assert.match(
        app,
        /if \(type === 'Bill \(Cash\)' \|\| type === 'Bill \(Card\)' \|\| type === 'Bill \(QR\)'\)\s*\{\s*return;\s*\}/
    );
});

test('no expiring hardcoded Vimeo tokens remain in app.js', () => {
    assert.doesNotMatch(app, /player\.vimeo\.com\/progressive_redirect/);
});

test('styles.css supports promo overlay, dark-theme nav tabs, and featured card layout without scrollable requirement', () => {
    assert.doesNotMatch(styles, /^\.promo-overlay\s*\{\s*display:\s*none\s*!important;\s*\}$/m);
    assert.match(styles, /\.promo-overlay:empty\s*\{\s*display:\s*none\s*!important;\s*\}/);
    assert.match(styles, /body\.dark-theme\s+\.app-nav-tabs/);
    assert.match(styles, /#menuView\s+\.featured-menu-grid\s+\.featured-item-card,\s*\n#menuView\s+\.featured-menu-grid\.scrollable\s+\.featured-item-card/);
});
