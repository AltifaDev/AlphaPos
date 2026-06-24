BEGIN;

-- Clean up orphaned modifiers first to prevent FK violation on alter
DELETE FROM public.order_item_modifiers 
WHERE order_item_id IS NOT NULL 
  AND order_item_id NOT IN (SELECT id FROM public.order_items);

-- Add the foreign key constraint properly
ALTER TABLE public.order_item_modifiers 
    DROP CONSTRAINT IF EXISTS order_item_modifiers_order_item_id_fkey;

ALTER TABLE public.order_item_modifiers 
    ADD CONSTRAINT order_item_modifiers_order_item_id_fkey 
    FOREIGN KEY (order_item_id) 
    REFERENCES public.order_items(id) 
    ON DELETE CASCADE;

COMMIT;
