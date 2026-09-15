-- Enable Realtime on sync_outbox so the receipt-station iPad can drain
-- Staff-requested print jobs (pre-bill / receipt) with low latency.

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
        IF NOT EXISTS (
            SELECT 1
              FROM pg_publication_tables
             WHERE pubname = 'supabase_realtime'
               AND schemaname = 'public'
               AND tablename = 'sync_outbox'
        ) THEN
            ALTER PUBLICATION supabase_realtime ADD TABLE public.sync_outbox;
        END IF;
    END IF;
END $$;
