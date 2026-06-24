-- =========================================================================
-- Migration 021: Enterprise Database Fixes
-- Created: 2026-06-17
-- Description: Fixes global UNIQUE constraints to be merchant-isolated,
--              adds Soft Delete (is_deleted) to payments table, removes
--              CASCADE deletion of payments, hardens audit logs, and adds
--              financial auto-audit triggers.
-- =========================================================================

BEGIN;

-- =========================================================================
-- 1. Fix UNIQUE Constraints (Merchant Isolation)
-- =========================================================================

-- orders.order_number
ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS orders_order_number_key;
ALTER TABLE public.orders ADD CONSTRAINT orders_merchant_order_number_key UNIQUE (merchant_id, order_number);

-- employees.username
ALTER TABLE public.employees DROP CONSTRAINT IF EXISTS employees_username_key;
ALTER TABLE public.employees ADD CONSTRAINT employees_merchant_username_key UNIQUE (merchant_id, username);


-- =========================================================================
-- 2. Prevent Financial Data Hard Deletion (Payments)
-- =========================================================================

-- Add is_deleted column
ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN NOT NULL DEFAULT FALSE;

-- Replace ON DELETE CASCADE with ON DELETE RESTRICT for payments.order_id
ALTER TABLE public.payments DROP CONSTRAINT IF EXISTS payments_order_id_fkey;
ALTER TABLE public.payments
    ADD CONSTRAINT payments_order_id_fkey
    FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE RESTRICT;

-- Index for soft deleted payments
CREATE INDEX IF NOT EXISTS idx_payments_active ON public.payments (merchant_id, is_deleted);


-- =========================================================================
-- 3. Harden Audit Logs (Append-only)
-- =========================================================================

-- Drop the old overly-permissive policy
DROP POLICY IF EXISTS "merchant_isolation_audit_logs" ON public.audit_logs;

-- Create restrictive policies (INSERT and SELECT only)
CREATE POLICY "merchant_isolation_audit_logs_select" ON public.audit_logs
    FOR SELECT TO anon
    USING (merchant_id = get_active_merchant_id());

CREATE POLICY "merchant_isolation_audit_logs_insert" ON public.audit_logs
    FOR INSERT TO anon
    WITH CHECK (merchant_id = get_active_merchant_id());

-- Prevent UPDATE or DELETE completely via trigger
CREATE OR REPLACE FUNCTION public.prevent_audit_log_modification()
RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'Audit logs are append-only and cannot be modified or deleted.';
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_prevent_audit_log_update ON public.audit_logs;
CREATE TRIGGER trg_prevent_audit_log_update
    BEFORE UPDATE OR DELETE ON public.audit_logs
    FOR EACH ROW EXECUTE FUNCTION public.prevent_audit_log_modification();


-- =========================================================================
-- 4. Financial Auto-Audit Triggers
-- =========================================================================

-- A. Auto-Audit Payments
CREATE OR REPLACE FUNCTION public.audit_payments()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO public.audit_logs (merchant_id, action_type, details, new_value)
        VALUES (NEW.merchant_id, 'payment_created', 'Payment ' || NEW.id || ' created for order ' || NEW.order_id, NEW.amount);
        RETURN NEW;
    ELSIF TG_OP = 'UPDATE' THEN
        IF OLD.amount IS DISTINCT FROM NEW.amount OR OLD.status IS DISTINCT FROM NEW.status OR OLD.is_deleted IS DISTINCT FROM NEW.is_deleted THEN
            INSERT INTO public.audit_logs (merchant_id, action_type, details, original_value, new_value)
            VALUES (NEW.merchant_id, 'payment_updated', 'Payment ' || NEW.id || ' status: ' || OLD.status || '->' || NEW.status || ', deleted: ' || NEW.is_deleted, OLD.amount, NEW.amount);
        END IF;
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        -- Though DELETE shouldn't happen due to RESTRICT, log it just in case
        INSERT INTO public.audit_logs (merchant_id, action_type, details, original_value)
        VALUES (OLD.merchant_id, 'payment_deleted', 'Payment ' || OLD.id || ' hard deleted for order ' || OLD.order_id, OLD.amount);
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_audit_payments ON public.payments;
CREATE TRIGGER trg_audit_payments
    AFTER INSERT OR UPDATE OR DELETE ON public.payments
    FOR EACH ROW EXECUTE FUNCTION public.audit_payments();

-- B. Auto-Audit Refund Transactions
CREATE OR REPLACE FUNCTION public.audit_refund_transactions()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO public.audit_logs (merchant_id, employee_id, action_type, details, new_value)
        VALUES (NEW.merchant_id, NEW.refunded_by_employee_id, 'refund_created', 'Refund ' || NEW.id || ' created for order ' || NEW.order_id || ' (Reason: ' || NEW.reason_code || ')', NEW.refund_amount);
        RETURN NEW;
    ELSIF TG_OP = 'UPDATE' THEN
        IF OLD.status IS DISTINCT FROM NEW.status OR OLD.refund_amount IS DISTINCT FROM NEW.refund_amount THEN
            INSERT INTO public.audit_logs (merchant_id, employee_id, action_type, details, original_value, new_value)
            VALUES (NEW.merchant_id, COALESCE(NEW.approved_by_employee_id, NEW.refunded_by_employee_id), 'refund_updated', 'Refund ' || NEW.id || ' status changed to ' || NEW.status, OLD.refund_amount, NEW.refund_amount);
        END IF;
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_audit_refund_transactions ON public.refund_transactions;
CREATE TRIGGER trg_audit_refund_transactions
    AFTER INSERT OR UPDATE ON public.refund_transactions
    FOR EACH ROW EXECUTE FUNCTION public.audit_refund_transactions();


COMMIT;
