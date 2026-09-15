CREATE TABLE IF NOT EXISTS public.inventory_lots (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id uuid NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
    branch_id uuid REFERENCES public.branches(id) ON DELETE SET NULL,
    inventory_item_id uuid NOT NULL REFERENCES public.inventory_items(id) ON DELETE CASCADE,
    lot_number varchar(100),
    received_date timestamptz NOT NULL DEFAULT now(),
    expiry_date date,
    initial_quantity decimal(12,4) NOT NULL CHECK (initial_quantity > 0),
    remaining_quantity decimal(12,4) NOT NULL DEFAULT 0 CHECK (remaining_quantity >= 0),
    lot_cost_price decimal(12,4) NOT NULL DEFAULT 0,
    source_transaction_id uuid,
    is_deleted boolean NOT NULL DEFAULT false,
    is_synced boolean NOT NULL DEFAULT false,
    updated_at timestamptz NOT NULL DEFAULT now(),
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT remaining_le_initial CHECK (remaining_quantity <= initial_quantity)
);
ALTER TABLE public.inventory_lots ENABLE ROW LEVEL SECURITY;
