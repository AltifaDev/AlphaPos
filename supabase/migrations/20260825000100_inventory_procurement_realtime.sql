-- Multi-device inventory and procurement consistency.
-- Idempotently publish the operational ledger, FEFO lots, and purchase orders.
DO $$
DECLARE
    v_table text;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
        RETURN;
    END IF;

    FOREACH v_table IN ARRAY ARRAY[
        'inventory_transactions',
        'inventory_lots',
        'purchase_orders',
        'purchase_order_items'
    ] LOOP
        IF to_regclass(format('public.%I', v_table)) IS NOT NULL
           AND NOT EXISTS (
               SELECT 1
                 FROM pg_publication_tables
                WHERE pubname = 'supabase_realtime'
                  AND schemaname = 'public'
                  AND tablename = v_table
           ) THEN
            EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', v_table);
        END IF;
    END LOOP;
END
$$;

-- UPDATE/DELETE realtime payloads need stable row identity on self-hosted
-- Postgres configurations where only key columns are emitted by default.
ALTER TABLE IF EXISTS public.inventory_transactions REPLICA IDENTITY FULL;
ALTER TABLE IF EXISTS public.inventory_lots REPLICA IDENTITY FULL;
ALTER TABLE IF EXISTS public.purchase_orders REPLICA IDENTITY FULL;
ALTER TABLE IF EXISTS public.purchase_order_items REPLICA IDENTITY FULL;
