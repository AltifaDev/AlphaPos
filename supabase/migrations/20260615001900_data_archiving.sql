-- =========================================================================
-- Migration 016: Data Archiving Strategy for High-Volume Tables
-- Created: 2026-06-15
-- Description: Creates archive tables for orders, order_items, and audit_logs
--              using LIKE ... INCLUDING ALL to preserve schema.
--              Includes a stored procedure to move records older than N months.
-- =========================================================================

BEGIN;

-- =========================================================================
-- 1. Create Archive Tables
-- =========================================================================

-- Create orders_archive
CREATE TABLE IF NOT EXISTS public.orders_archive (
    LIKE public.orders INCLUDING ALL
);

-- Create order_items_archive
CREATE TABLE IF NOT EXISTS public.order_items_archive (
    LIKE public.order_items INCLUDING ALL
);

-- Create audit_logs_archive
CREATE TABLE IF NOT EXISTS public.audit_logs_archive (
    LIKE public.audit_logs INCLUDING ALL
);


-- =========================================================================
-- 2. Stored Procedure for Archiving
-- =========================================================================
-- This procedure will move orders (and their items) and audit logs
-- that are older than the specified number of months to the archive tables.
-- It executes in a single transaction.

CREATE OR REPLACE PROCEDURE public.archive_historical_data(p_months_older_than INT DEFAULT 12)
LANGUAGE plpgsql
AS $$
DECLARE
    v_cutoff_date TIMESTAMP WITH TIME ZONE;
    v_archived_orders_count INT := 0;
    v_archived_items_count INT := 0;
    v_archived_audits_count INT := 0;
BEGIN
    -- Calculate cutoff date
    v_cutoff_date := CURRENT_TIMESTAMP - (p_months_older_than || ' months')::INTERVAL;
    
    RAISE NOTICE 'Starting archival process for data older than %', v_cutoff_date;

    -- ---------------------------------------------------------
    -- A. Archive Orders and Order Items
    -- ---------------------------------------------------------
    -- Create a temporary table to hold IDs of orders to be archived
    CREATE TEMP TABLE temp_orders_to_archive ON COMMIT DROP AS
    SELECT id FROM public.orders 
    WHERE created_at < v_cutoff_date;

    GET DIAGNOSTICS v_archived_orders_count = ROW_COUNT;

    IF v_archived_orders_count > 0 THEN
        -- Move order_items first due to foreign key constraints
        -- Insert into archive
        INSERT INTO public.order_items_archive
        SELECT oi.* FROM public.order_items oi
        JOIN temp_orders_to_archive t ON oi.order_id = t.id
        ON CONFLICT (id) DO NOTHING;
        
        GET DIAGNOSTICS v_archived_items_count = ROW_COUNT;

        -- Delete from live table
        DELETE FROM public.order_items
        WHERE order_id IN (SELECT id FROM temp_orders_to_archive);

        -- Move orders
        -- Insert into archive
        INSERT INTO public.orders_archive
        SELECT o.* FROM public.orders o
        JOIN temp_orders_to_archive t ON o.id = t.id
        ON CONFLICT (id) DO NOTHING;

        -- Delete from live table
        DELETE FROM public.orders
        WHERE id IN (SELECT id FROM temp_orders_to_archive);
        
        RAISE NOTICE 'Archived % orders and % order items', v_archived_orders_count, v_archived_items_count;
    ELSE
        RAISE NOTICE 'No orders found to archive.';
    END IF;

    -- ---------------------------------------------------------
    -- B. Archive Audit Logs
    -- ---------------------------------------------------------
    WITH moved_audits AS (
        DELETE FROM public.audit_logs
        WHERE created_at < v_cutoff_date
        RETURNING *
    )
    INSERT INTO public.audit_logs_archive
    SELECT * FROM moved_audits
    ON CONFLICT (id) DO NOTHING;
    
    GET DIAGNOSTICS v_archived_audits_count = ROW_COUNT;
    RAISE NOTICE 'Archived % audit logs', v_archived_audits_count;

END;
$$;

COMMIT;
