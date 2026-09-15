-- Preserve complete source invoice data for reliable, auditable receiving.
-- The shape follows the core Peppol BIS Billing / UBL invoice business terms
-- while remaining backward-compatible with existing AlphaPos purchase orders.

ALTER TABLE public.purchase_orders
    ADD COLUMN IF NOT EXISTS document_type TEXT,
    ADD COLUMN IF NOT EXISTS invoice_number VARCHAR(100),
    ADD COLUMN IF NOT EXISTS tax_invoice_number VARCHAR(100),
    ADD COLUMN IF NOT EXISTS supplier_name_raw TEXT,
    ADD COLUMN IF NOT EXISTS supplier_tax_id VARCHAR(50),
    ADD COLUMN IF NOT EXISTS supplier_branch_code VARCHAR(50),
    ADD COLUMN IF NOT EXISTS customer_reference VARCHAR(100),
    ADD COLUMN IF NOT EXISTS invoice_date DATE,
    ADD COLUMN IF NOT EXISTS currency_code CHAR(3) NOT NULL DEFAULT 'THB',
    ADD COLUMN IF NOT EXISTS subtotal NUMERIC(14,2),
    ADD COLUMN IF NOT EXISTS tax_amount NUMERIC(14,2),
    ADD COLUMN IF NOT EXISTS grand_total NUMERIC(14,2),
    ADD COLUMN IF NOT EXISTS extraction_confidence NUMERIC(5,4),
    ADD COLUMN IF NOT EXISTS validation_warnings JSONB NOT NULL DEFAULT '[]'::jsonb,
    ADD COLUMN IF NOT EXISTS source_document_hash TEXT;

ALTER TABLE public.purchase_order_items
    ADD COLUMN IF NOT EXISTS line_number VARCHAR(50),
    ADD COLUMN IF NOT EXISTS source_item_name TEXT,
    ADD COLUMN IF NOT EXISTS seller_item_id VARCHAR(100),
    ADD COLUMN IF NOT EXISTS barcode VARCHAR(100),
    ADD COLUMN IF NOT EXISTS source_unit VARCHAR(50),
    ADD COLUMN IF NOT EXISTS unit_code VARCHAR(20),
    ADD COLUMN IF NOT EXISTS price_base_quantity NUMERIC(12,4) NOT NULL DEFAULT 1,
    ADD COLUMN IF NOT EXISTS line_net_amount NUMERIC(14,2),
    ADD COLUMN IF NOT EXISTS vat_rate NUMERIC(7,4),
    ADD COLUMN IF NOT EXISTS vat_code VARCHAR(20),
    ADD COLUMN IF NOT EXISTS tax_amount NUMERIC(14,2),
    ADD COLUMN IF NOT EXISTS line_total NUMERIC(14,2),
    ADD COLUMN IF NOT EXISTS line_confidence NUMERIC(5,4),
    ADD COLUMN IF NOT EXISTS expiry_date DATE,
    ADD COLUMN IF NOT EXISTS lot_number VARCHAR(100);

CREATE UNIQUE INDEX IF NOT EXISTS uq_purchase_orders_source_document
    ON public.purchase_orders (merchant_id, source_document_hash)
    WHERE source_document_hash IS NOT NULL AND is_deleted = FALSE;

CREATE UNIQUE INDEX IF NOT EXISTS uq_purchase_order_line_number
    ON public.purchase_order_items (purchase_order_id, line_number)
    WHERE line_number IS NOT NULL AND is_deleted = FALSE;

CREATE INDEX IF NOT EXISTS idx_purchase_orders_invoice_number
    ON public.purchase_orders (merchant_id, invoice_number)
    WHERE invoice_number IS NOT NULL AND is_deleted = FALSE;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'purchase_orders_currency_code_format') THEN
        ALTER TABLE public.purchase_orders
            ADD CONSTRAINT purchase_orders_currency_code_format
            CHECK (currency_code ~ '^[A-Z]{3}$');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'purchase_orders_confidence_range') THEN
        ALTER TABLE public.purchase_orders
            ADD CONSTRAINT purchase_orders_confidence_range
            CHECK (extraction_confidence IS NULL OR extraction_confidence BETWEEN 0 AND 1);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'purchase_order_items_positive_base_quantity') THEN
        ALTER TABLE public.purchase_order_items
            ADD CONSTRAINT purchase_order_items_positive_base_quantity
            CHECK (price_base_quantity > 0);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'purchase_order_items_confidence_range') THEN
        ALTER TABLE public.purchase_order_items
            ADD CONSTRAINT purchase_order_items_confidence_range
            CHECK (line_confidence IS NULL OR line_confidence BETWEEN 0 AND 1);
    END IF;
END $$;

