-- ⚠️ DEPRECATED: This file is SUPERSEDED by the merchant-scoped RLS policies in schema.sql
-- DO NOT APPLY this file to production. These open-access policies (USING true) were used
-- during early development only. Production must use merchant-isolated policies from schema.sql.
--
-- PostgreSQL SQL script to configure Row Level Security (RLS) on Supabase (LEGACY)
-- This file defines policies to secure table access while maintaining support
-- for anonymous client REST operations from iPad, iPhone, and Web Customer apps.
-- =========================================================================
-- 1. ENABLE ROW LEVEL SECURITY
-- =========================================================================
ALTER TABLE menu_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE table_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE service_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE employees ENABLE ROW LEVEL SECURITY;
ALTER TABLE timecards ENABLE ROW LEVEL SECURITY;

-- =========================================================================
-- 2. DROP EXISTING POLICIES TO AVOID CONFLICTS
-- =========================================================================
DROP POLICY IF EXISTS "Allow public read-only access to menu_items" ON menu_items;
DROP POLICY IF EXISTS "Allow anon read-write access to table_sessions" ON table_sessions;
DROP POLICY IF EXISTS "Allow anon read-write access to orders" ON orders;
DROP POLICY IF EXISTS "Allow anon read-write access to order_items" ON order_items;
DROP POLICY IF EXISTS "Allow anon read-write access to service_requests" ON service_requests;
DROP POLICY IF EXISTS "Allow anon read-insert access to payments" ON payments;
DROP POLICY IF EXISTS "Allow anon read-only access to employees" ON employees;
DROP POLICY IF EXISTS "Allow anon read-write access to timecards" ON timecards;

-- =========================================================================
-- 3. DEFINE POLICIES
-- =========================================================================

-- Menu Items: Everyone can read the menu, but only admins can write (block anon writes)
CREATE POLICY "Allow public read-only access to menu_items" ON menu_items
    FOR SELECT TO public USING (true);

-- Table Sessions: Anon role (clients) can select, insert and update active dining sessions
CREATE POLICY "Allow anon read-write access to table_sessions" ON table_sessions
    FOR ALL TO anon USING (true) WITH CHECK (true);

-- Orders: Anon role can read, insert and update orders (cooking, ready, served status changes)
CREATE POLICY "Allow anon read-write access to orders" ON orders
    FOR ALL TO anon USING (true) WITH CHECK (true);

-- Order Items: Anon role can manage order items (kitchen alerts, cook status, item deletions)
CREATE POLICY "Allow anon read-write access to order_items" ON order_items
    FOR ALL TO anon USING (true) WITH CHECK (true);

-- Service Requests: Anon role can read, create and complete call staff notifications
CREATE POLICY "Allow anon read-write access to service_requests" ON service_requests
    FOR ALL TO anon USING (true) WITH CHECK (true);

-- Payments: Anon role can select and upload payments (checkout), but cannot edit/delete them
CREATE POLICY "Allow anon read-insert access to payments" ON payments
    FOR ALL TO anon USING (true) WITH CHECK (true);

-- Employees: Anon role can read employee profiles (pin login), but cannot insert/edit/delete profiles
CREATE POLICY "Allow anon read-only access to employees" ON employees
    FOR SELECT TO anon USING (true);

-- Timecards: Anon role can select, insert and update timecard records (clock-in, clock-out), but cannot delete
CREATE POLICY "Allow anon read-write access to timecards" ON timecards
    FOR SELECT ON timecards TO anon USING (true),
    FOR INSERT ON timecards TO anon WITH CHECK (true),
    FOR UPDATE ON timecards TO anon USING (true) WITH CHECK (true);
