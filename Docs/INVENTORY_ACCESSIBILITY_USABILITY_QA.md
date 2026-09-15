# Inventory Accessibility and Usability Acceptance

Applies to the iPad Inventory stock workspace. Run in both Thai and English,
Light and Dark appearance, and with Increase Contrast enabled.

## Automated/source checks

- Swift source parses without syntax errors.
- Every status includes text and an SF Symbol; color is supplementary.
- Semantic foreground tokens meet WCAG 2.2 AA against their intended surface:
  primary 16.12:1/18.84:1, secondary 7.56:1/6.96:1,
  tertiary 4.83:1/8.02:1, teal 6.31:1/8.63:1,
  amber 5.43:1/10.59:1, and destructive red on dark 5.10:1
  (light/dark respectively where applicable).

## Dynamic Type

Test Settings > Accessibility > Display & Text Size > Larger Text at default,
XXXL, Accessibility 3, and the maximum (approximately 200%). At accessibility
sizes the fixed-column table must switch to cards. Confirm that:

- no title, quantity, unit, status, filter, or action is clipped;
- KPI and filter rows scroll horizontally and retain every control;
- sheets remain scrollable and the confirm/cancel actions remain reachable;
- changing text size while Inventory is open does not lose selection or branch.

## Accessibility Inspector and VoiceOver

Run Xcode Accessibility Inspector Audit with the stock workspace visible. There
must be no contrast, hit-region, missing-label, or clipped-text failures. With
VoiceOver enabled, traverse in this order:

1. screen title and active branch/location;
2. pending count and last sync time;
3. primary sections;
4. KPI filters;
5. search, saved filter, sort, layout, and multi-select;
6. inventory rows, each announced as name, tracking mode, on-hand quantity,
   status, and expiry;
7. row and bulk actions.

Verify that quarantine, low, expired, and synced states remain distinguishable
with Differentiate Without Color enabled.

## Keyboard and pointer

- Command-F focuses inventory search.
- Tab and Shift-Tab reach every interactive control in visual order.
- Space/Return activates the focused KPI, row, menu, and confirmation button.
- Default action confirms quarantine only when a reason and eligible lot exist.
- Pointer hover/focus does not change layout or hide labels.

## Task-based usability study

Recruit at least five representative warehouse/store users who did not implement
the feature. Do not coach them after giving the task. Record completion, errors,
interactions, time, and a 1–5 confidence score.

| Task | Acceptance target |
| --- | --- |
| Identify the active branch and last sync | <= 1 interaction, >= 90% success |
| Find an out-of-stock item | <= 2 interactions, >= 90% success |
| Find an item expiring in three days | <= 2 interactions, >= 90% success |
| Receive selected stock | <= 3 interactions after selecting the item |
| Transfer one selected item | <= 3 interactions before entering destination/quantity |
| Quarantine selected active lots | <= 3 interactions before entering the required reason |
| Start a stock count | <= 2 interactions, >= 90% success |

Release requires every critical task to reach 90% success, no participant to
modify the wrong branch, and no unresolved severity-high Inspector finding.
