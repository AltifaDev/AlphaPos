-- =========================================================================
-- Migration 003: Missing Tables for iPad POS Features
-- Created: 2026-06-09
-- Description: Creates tables for Purchase Orders, Purchase Order Items,
--              and Delivery Prices — features existing in SwiftData (iPad)
--              but previously absent from Supabase.
-- Status: APPLIED to Supabase (your-project-ref)
-- =========================================================================

-- -------------------------------------------------------------------------
-- 3.1 purchase_orders — Procurement / Stock Purchasing
-- Maps to SwiftData: PurchaseOrder model
-- -------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.purchase_orders (
    id UUID PRIMARY KEY,
    merchant_id UUID REFERENCES public.merchants(id) ON DELETE CASCADE NOT NULL,
    supplier_id UUID REFERENCES public.suppliers(id) ON DELETE SET NULL,
    branch_id UUID REFERENCES public.branches(id) ON DELETE SET NULL,
    po_number VARCHAR(100) NOT NULL,
    status VARCHAR(50) NOT NULL DEFAULT 'draft',  -- draft, sent, received, cancelled
    order_date TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    delivery_date TIMESTAMP WITH TIME ZONE,
    notes TEXT,
    is_synced BOOLEAN NOT NULL DEFAULT FALSE,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;

CREATE POLICY "merchant_isolation_purchase_orders" ON public.purchase_orders
    FOR ALL TO anon
    USING (merchant_id = get_active_merchant_id())
    WITH CHECK (merchant_id = get_active_merchant_id());

CREATE INDEX IF NOT EXISTS idx_purchase_orders_merchant ON public.purchase_orders (merchant_id);
CREATE INDEX IF NOT EXISTS idx_purchase_orders_supplier ON public.purchase_orders (supplier_id);
CREATE INDEX IF NOT EXISTS idx_purchase_orders_status ON public.purchase_orders (merchant_id, status);

-- -------------------------------------------------------------------------
-- 3.2 purchase_order_items — Line items in a purchase order
-- Maps to SwiftData: PurchaseOrderItem model
-- -------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.purchase_order_items (
    id UUID PRIMARY KEY,
    merchant_id UUID REFERENCES public.merchants(id) ON DELETE CASCADE NOT NULL,
    purchase_order_id UUID REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
    inventory_item_id UUID REFERENCES public.inventory_items(id) ON DELETE SET NULL,
    quantity_ordered DECIMAL(10,3) NOT NULL DEFAULT 0,
    quantity_received DECIMAL(10,3) NOT NULL DEFAULT 0,
    unit_cost DECIMAL(10,2) NOT NULL DEFAULT 0,
    is_synced BOOLEAN NOT NULL DEFAULT FALSE,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE public.purchase_order_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY "merchant_isolation_purchase_order_items" ON public.purchase_order_items
    FOR ALL TO anon
    USING (merchant_id = get_active_merchant_id())
    WITH CHECK (merchant_id = get_active_merchant_id());

CREATE INDEX IF NOT EXISTS idx_purchase_order_items_merchant ON public.purchase_order_items (merchant_id);
CREATE INDEX IF NOT EXISTS idx_purchase_order_items_po ON public.purchase_order_items (purchase_order_id);
CREATE INDEX IF NOT EXISTS idx_purchase_order_items_inventory ON public.purchase_order_items (inventory_item_id);

-- -------------------------------------------------------------------------
-- 3.3 delivery_prices — Per-platform delivery pricing for menu items
-- Maps to SwiftData: DeliveryPrice model
-- -------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.delivery_prices (
    id UUID PRIMARY KEY,
    merchant_id UUID REFERENCES public.merchants(id) ON DELETE CASCADE NOT NULL,
    menu_item_id TEXT REFERENCES public.menu_items(id) ON DELETE CASCADE,
    brand_name VARCHAR(100) NOT NULL,  -- 'GrabFood', 'LINE MAN', 'ShopeeFood', 'Foodpanda', 'Robinhood'
    price DECIMAL(10,2) NOT NULL DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE public.delivery_prices ENABLE ROW LEVEL SECURITY;

CREATE POLICY "merchant_isolation_delivery_prices" ON public.delivery_prices
    FOR ALL TO anon
    USING (merchant_id = get_active_merchant_id())
    WITH CHECK (merchant_id = get_active_merchant_id());

CREATE INDEX IF NOT EXISTS idx_delivery_prices_merchant ON public.delivery_prices (merchant_id);
CREATE INDEX IF NOT EXISTS idx_delivery_prices_menu_item ON public.delivery_prices (menu_item_id);
