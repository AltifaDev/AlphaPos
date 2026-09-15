-- ============================================================
-- Migration: Inventory Transaction Audit Signature Column
-- AlphaPos — Audit Trail Hardening (ISO 27001)
-- ============================================================
-- Moves the tamper-evident transaction signature out of the mutable `notes`
-- field into its own `audit_signature` column (see InventoryAuditSigner.swift).
-- Keeping the signature separate from `notes` means user-editable remarks can
-- no longer silently invalidate or forge the audit record.
--
-- NOTE: full cryptographic *verification* must happen where the secret salt
-- lives. The client already stores the signature here; a server-side
-- verification function should be added once the signing secret is moved out
-- of the client binary (defense-in-depth follow-up). Until then this column +
-- the coverage view below give us an audit-coverage metric and a clean,
-- tamper-evident storage location.
-- ============================================================

ALTER TABLE public.inventory_transactions
    ADD COLUMN IF NOT EXISTS audit_signature TEXT;

CREATE INDEX IF NOT EXISTS idx_inventory_transactions_audit_signature
    ON public.inventory_transactions (audit_signature);

-- Audit-coverage view: rows that are still missing a signature (legacy rows
-- created before this column existed, or clients that haven't upgraded).
-- Useful as an audit KPI — "X% of movements are signed".
CREATE OR REPLACE VIEW public.unsigned_inventory_txns AS
SELECT id, merchant_id, item_id, transaction_type, quantity, created_at
FROM public.inventory_transactions
WHERE is_deleted = FALSE
  AND audit_signature IS NULL;

GRANT SELECT ON public.unsigned_inventory_txns TO authenticated;
