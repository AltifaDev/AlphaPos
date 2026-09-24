import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const styles = readFileSync(new URL('../styles.css', import.meta.url), 'utf8');
const app = readFileSync(new URL('../app.js', import.meta.url), 'utf8');

test('featured card image resets legacy overlapping offsets', () => {
    const rules = [...styles.matchAll(/#menuView \.featured-item-img-container\s*\{([^}]*)\}/g)];
    assert.ok(rules.length > 0, 'expected an authoritative featured image rule');

    const authoritativeRule = rules
        .map((match) => match[1])
        .find((rule) => /width:\s*100%\s*!important/.test(rule));
    assert.ok(authoritativeRule, 'expected the full-width featured image rule');
    assert.match(authoritativeRule, /top:\s*auto\s*!important/);
    assert.match(authoritativeRule, /left:\s*auto\s*!important/);
    assert.match(authoritativeRule, /transform:\s*none\s*!important/);
});

test('menu media uses native loading hints instead of preloading the full catalog', () => {
    assert.match(app, /loading="lazy" decoding="async"/);
    assert.match(app, /fetchpriority="\$\{index === 0 \? 'high' : 'auto'\}"/);
    assert.doesNotMatch(app, /prefetchMenuImages\(\)/);
    assert.doesNotMatch(app, /class="list-item-img" autoplay/);
});
