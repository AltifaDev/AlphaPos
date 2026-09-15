\set ON_ERROR_STOP on
BEGIN;
DO $$
DECLARE
    row record;
    actual text;
    checked integer := 0;
BEGIN
    FOR row IN SELECT * FROM (VALUES
        ('online_subscription', 'trial', '2026-09-08Z', 'allowed'),
        ('online_subscription', 'trial', '2026-09-07Z', 'trial_expired'),
        ('online_subscription', 'trial', '2026-09-06Z', 'trial_expired'),
        ('online_subscription', 'active', '2026-09-08Z', 'allowed'),
        ('online_subscription', 'active', '2026-09-07Z', 'expired'),
        ('online_subscription', 'active', NULL, 'invalid_subscription'),
        ('online_subscription', 'trial', NULL, 'invalid_subscription'),
        ('online_subscription', 'active', 'infinity', 'invalid_subscription'),
        ('online_subscription', 'pending_payment', '2026-09-08Z', 'pending_payment'),
        ('online_subscription', 'expired', '2026-09-08Z', 'expired'),
        ('online_subscription', 'suspended', '2026-09-08Z', 'inactive'),
        ('online_subscription', 'cancelled', '2026-09-08Z', 'inactive'),
        ('online_subscription', 'unexpected', '2026-09-08Z', 'invalid_subscription'),
        ('online_subscription', NULL, '2026-09-08Z', 'invalid_subscription'),
        (NULL, 'active', '2026-09-08Z', 'invalid_subscription'),
        ('', 'active', '2026-09-08Z', 'invalid_subscription'),
        ('offline_perpetual', 'active', NULL, 'plan_not_supported'),
        ('offline_subscription', 'trial', '2026-09-08Z', 'plan_not_supported'),
        (' ONLINE_SUBSCRIPTION ', ' TRIAL ', '2026-09-08T07:00:00+07:00', 'allowed'),
        ('online_subscription', 'trial', '2026-09-07T00:00:00.001Z', 'allowed')
    ) AS cases(tier, status, expiry, expected)
    LOOP
        actual := public.staff_subscription_access_reason(row.tier, row.status, row.expiry::timestamptz, '2026-09-07T00:00:00Z');
        IF actual IS DISTINCT FROM row.expected THEN
            RAISE EXCEPTION 'Expected %, got % for %', row.expected, actual, row;
        END IF;
        checked := checked + 1;
    END LOOP;
    RAISE NOTICE '% subscription cases passed', checked;
END;
$$;
ROLLBACK;
