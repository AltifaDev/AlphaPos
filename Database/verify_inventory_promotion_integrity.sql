-- AlphaPos production verification for migrations 019/020.
-- Run in Supabase SQL Editor after applying 020_validate_inventory_promotion_integrity.sql.

WITH checks AS (
    SELECT
        'table:order_discounts' AS check_name,
        to_regclass('public.order_discounts') IS NOT NULL AS passed,
        COALESCE(to_regclass('public.order_discounts')::text, 'missing') AS detail
    UNION ALL
    SELECT
        'table:promotion_bundle_items',
        to_regclass('public.promotion_bundle_items') IS NOT NULL,
        COALESCE(to_regclass('public.promotion_bundle_items')::text, 'missing')
    UNION ALL
    SELECT
        'constraint:promotions_applies_to_menu_item_fk',
        EXISTS (
            SELECT 1 FROM pg_constraint
            WHERE conname = 'promotions_applies_to_menu_item_fk'
              AND convalidated = TRUE
        ),
        COALESCE((
            SELECT CASE WHEN convalidated THEN 'validated' ELSE 'not validated' END
            FROM pg_constraint
            WHERE conname = 'promotions_applies_to_menu_item_fk'
            LIMIT 1
        ), 'missing')
    UNION ALL
    SELECT
        'constraint:promotions_reward_menu_item_fk',
        EXISTS (
            SELECT 1 FROM pg_constraint
            WHERE conname = 'promotions_reward_menu_item_fk'
              AND convalidated = TRUE
        ),
        COALESCE((
            SELECT CASE WHEN convalidated THEN 'validated' ELSE 'not validated' END
            FROM pg_constraint
            WHERE conname = 'promotions_reward_menu_item_fk'
            LIMIT 1
        ), 'missing')
    UNION ALL
    SELECT
        'constraint:promotions_product_rule_check',
        EXISTS (
            SELECT 1 FROM pg_constraint
            WHERE conname = 'promotions_product_rule_check'
              AND convalidated = TRUE
        ),
        COALESCE((
            SELECT CASE WHEN convalidated THEN 'validated' ELSE 'not validated' END
            FROM pg_constraint
            WHERE conname = 'promotions_product_rule_check'
            LIMIT 1
        ), 'missing')
    UNION ALL
    SELECT
        'constraint:promotions_redemption_limits_check',
        EXISTS (
            SELECT 1 FROM pg_constraint
            WHERE conname = 'promotions_redemption_limits_check'
              AND convalidated = TRUE
        ),
        COALESCE((
            SELECT CASE WHEN convalidated THEN 'validated' ELSE 'not validated' END
            FROM pg_constraint
            WHERE conname = 'promotions_redemption_limits_check'
            LIMIT 1
        ), 'missing')
    UNION ALL
    SELECT
        'constraint:order_discounts_promotion_fk',
        EXISTS (
            SELECT 1 FROM pg_constraint
            WHERE conname = 'order_discounts_promotion_fk'
              AND convalidated = TRUE
        ),
        COALESCE((
            SELECT CASE WHEN convalidated THEN 'validated' ELSE 'not validated' END
            FROM pg_constraint
            WHERE conname = 'order_discounts_promotion_fk'
            LIMIT 1
        ), 'missing')
    UNION ALL
    SELECT
        'trigger:trg_deduct_stock_on_order_item',
        EXISTS (
            SELECT 1 FROM pg_trigger
            WHERE tgname = 'trg_deduct_stock_on_order_item'
              AND NOT tgisinternal
        ),
        CASE WHEN EXISTS (
            SELECT 1 FROM pg_trigger
            WHERE tgname = 'trg_deduct_stock_on_order_item'
              AND NOT tgisinternal
        ) THEN 'present' ELSE 'missing' END
    UNION ALL
    SELECT
        'orphan:promotions.applies_to_menu_item_id',
        NOT EXISTS (
            SELECT 1
            FROM public.promotions p
            LEFT JOIN public.menu_items mi ON mi.id = p.applies_to_menu_item_id
            WHERE p.applies_to_menu_item_id IS NOT NULL
              AND mi.id IS NULL
        ),
        COUNT(*)::text
        FROM public.promotions p
        LEFT JOIN public.menu_items mi ON mi.id = p.applies_to_menu_item_id
        WHERE p.applies_to_menu_item_id IS NOT NULL
          AND mi.id IS NULL
    UNION ALL
    SELECT
        'orphan:promotions.reward_menu_item_id',
        NOT EXISTS (
            SELECT 1
            FROM public.promotions p
            LEFT JOIN public.menu_items mi ON mi.id = p.reward_menu_item_id
            WHERE p.reward_menu_item_id IS NOT NULL
              AND mi.id IS NULL
        ),
        COUNT(*)::text
        FROM public.promotions p
        LEFT JOIN public.menu_items mi ON mi.id = p.reward_menu_item_id
        WHERE p.reward_menu_item_id IS NOT NULL
          AND mi.id IS NULL
    UNION ALL
    SELECT
        'orphan:promotion_bundle_items.menu_item_id',
        NOT EXISTS (
            SELECT 1
            FROM public.promotion_bundle_items pbi
            LEFT JOIN public.menu_items mi ON mi.id = pbi.menu_item_id
            WHERE COALESCE(pbi.is_deleted, FALSE) = FALSE
              AND mi.id IS NULL
        ),
        COUNT(*)::text
        FROM public.promotion_bundle_items pbi
        LEFT JOIN public.menu_items mi ON mi.id = pbi.menu_item_id
        WHERE COALESCE(pbi.is_deleted, FALSE) = FALSE
          AND mi.id IS NULL
    UNION ALL
    SELECT
        'orphan:order_discounts.promotion_id',
        NOT EXISTS (
            SELECT 1
            FROM public.order_discounts od
            LEFT JOIN public.promotions p ON p.id = od.promotion_id
            WHERE od.promotion_id IS NOT NULL
              AND p.id IS NULL
        ),
        COUNT(*)::text
        FROM public.order_discounts od
        LEFT JOIN public.promotions p ON p.id = od.promotion_id
        WHERE od.promotion_id IS NOT NULL
          AND p.id IS NULL
    UNION ALL
    SELECT
        'duplicate:inventory_transactions_reference',
        NOT EXISTS (
            SELECT 1
            FROM public.inventory_transactions
            WHERE reference_id IS NOT NULL
              AND item_id IS NOT NULL
              AND COALESCE(is_deleted, FALSE) = FALSE
            GROUP BY merchant_id, transaction_type, reference_id, item_id
            HAVING COUNT(*) > 1
        ),
        COUNT(*)::text
        FROM (
            SELECT 1
            FROM public.inventory_transactions
            WHERE reference_id IS NOT NULL
              AND item_id IS NOT NULL
              AND COALESCE(is_deleted, FALSE) = FALSE
            GROUP BY merchant_id, transaction_type, reference_id, item_id
            HAVING COUNT(*) > 1
        ) d
)
SELECT
    check_name,
    CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS status,
    detail
FROM checks
ORDER BY status, check_name;
