# AlphaPos Promotion Guide

This guide explains how to create promotions that affect POS totals, stock deduction, and reporting correctly.

## Supported Promotion Types

| Type | Example | POS effect | Stock effect |
| --- | --- | --- | --- |
| Banner only | New branch opening banner | No discount | No stock effect |
| Percentage discount | 10% off all orders | Discounts order subtotal | Stock follows sold items |
| Fixed discount | 50 baht off | Discounts order subtotal | Stock follows sold items |
| Bundle price | Buy 3 beers for 299 | Discounts matching item groups to fixed bundle price | Stock deducts actual item quantity sold |
| Buy X Get Y | Buy 1 get 1 free | Discounts free units in each group | Stock deducts paid and free units |
| Buy X Pay Y | Buy 3 pay 2 | Discounts unpaid units in each group | Stock deducts all units taken |

## Recommended Setup

1. Create or verify the Menu Item first.
2. Link the Menu Item to inventory or a recipe before running product-level promotions.
3. Create the promotion from `Manage Promotions`.
4. Use `Quick Templates` when possible:
   - `3 for 299` for fixed bundle pricing.
   - `Buy 1 Get 1` for free item campaigns.
   - `Buy 3 Pay 2` for quantity discount campaigns.
5. Choose the product that the rule applies to.
6. Set the schedule if the promotion must start or stop automatically.
7. Save and let sync complete.

## Media Standard

Use one consistent banner format across the app, customer ordering screen, and in-store display.

| Media | Recommended format |
| --- | --- |
| Image | JPG or PNG, 1600 x 600 px, 8:3 ratio |
| Video | MP4/H.264, 1600 x 600 px, 6-15 seconds |
| Text safety | Keep important text centered with left/right margins |
| Playback | Videos are muted and loop automatically in promotion previews |

Avoid uploading tall mobile stories, very small images, or videos with important text near the edges. They may be cropped on iPad, kiosk, or customer ordering screens.

## How Stock Is Calculated

Promotions do not create fake stock movements. The POS cart quantity is the source of truth.

Example: Buy 1 Get 1 beer

- Cashier adds 2 beers to the cart.
- POS discounts 1 beer.
- Inventory deducts 2 beers.
- OrderDiscount records the promotion impact.

Example: Buy 3 beers for 299

- Cashier adds 3 beers to the cart.
- POS compares the normal price of 3 beers with 299 and records the difference as discount.
- Inventory deducts 3 beers.

## Performance Reading

Each promotion card shows:

- number of orders that used the promotion
- total discount given by that promotion

Use this to compare whether a campaign is actually being used. For deeper marketing analysis, compare gross sales, margin, item quantity sold, and stock cost before and after the campaign window.
