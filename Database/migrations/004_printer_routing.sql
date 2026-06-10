-- =========================================================================
-- Migration 004: Printer Management & Routing Rules System
-- Created: 2026-06-10
-- Description: Creates tables for Printers and Print Routing Rules, supporting
--              multi-printer topologies and categorised print jobs.
-- Status: Draft
-- =========================================================================

-- -------------------------------------------------------------------------
-- 4.1 printers — Connection settings and roles for printers
-- Maps to SwiftData: Printer model
-- -------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.printers (
    id UUID PRIMARY KEY,
    merchant_id UUID REFERENCES public.merchants(id) ON DELETE CASCADE NOT NULL,
    name VARCHAR(100) NOT NULL,
    connection_type VARCHAR(50) NOT NULL DEFAULT 'network',  -- network, bluetooth, usb
    ip_address VARCHAR(45),
    port INTEGER DEFAULT 9100,
    bluetooth_name VARCHAR(255),
    paper_width VARCHAR(20) NOT NULL DEFAULT '80mm',          -- 80mm, 58mm
    status VARCHAR(50) NOT NULL DEFAULT 'unknown',            -- online, offline, error
    role VARCHAR(50) NOT NULL DEFAULT 'kitchen',              -- receipt, kitchen, label
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    is_synced BOOLEAN NOT NULL DEFAULT FALSE,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE public.printers ENABLE ROW LEVEL SECURITY;

CREATE POLICY "merchant_isolation_printers" ON public.printers
    FOR ALL TO anon
    USING (merchant_id = get_active_merchant_id())
    WITH CHECK (merchant_id = get_active_merchant_id());

CREATE INDEX IF NOT EXISTS idx_printers_merchant ON public.printers (merchant_id);
CREATE INDEX IF NOT EXISTS idx_printers_role ON public.printers (merchant_id, role);

-- -------------------------------------------------------------------------
-- 4.2 print_routing_rules — Rules linking categories to specific printers
-- Maps to SwiftData: PrintRoutingRule model
-- -------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.print_routing_rules (
    id UUID PRIMARY KEY,
    merchant_id UUID REFERENCES public.merchants(id) ON DELETE CASCADE NOT NULL,
    printer_id UUID REFERENCES public.printers(id) ON DELETE CASCADE NOT NULL,
    category_id VARCHAR(100), -- Textual category slug (e.g. 'mains', 'drinks')
    print_on_order BOOLEAN NOT NULL DEFAULT TRUE,
    print_on_payment BOOLEAN NOT NULL DEFAULT FALSE,
    is_synced BOOLEAN NOT NULL DEFAULT FALSE,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE public.print_routing_rules ENABLE ROW LEVEL SECURITY;

CREATE POLICY "merchant_isolation_print_routing_rules" ON public.print_routing_rules
    FOR ALL TO anon
    USING (merchant_id = get_active_merchant_id())
    WITH CHECK (merchant_id = get_active_merchant_id());

CREATE INDEX IF NOT EXISTS idx_print_routing_rules_merchant ON public.print_routing_rules (merchant_id);
CREATE INDEX IF NOT EXISTS idx_print_routing_rules_printer ON public.print_routing_rules (printer_id);
CREATE INDEX IF NOT EXISTS idx_print_routing_rules_category ON public.print_routing_rules (category_id);
