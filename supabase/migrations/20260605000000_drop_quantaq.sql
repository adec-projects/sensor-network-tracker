-- Remove the QuantAQ automatic issue-detection / alerting system entirely.
-- Going forward, sensor issues are noticed and logged manually (notes + the
-- manual issue statuses, which are unaffected). This drops the alerts table,
-- the scan/cron RPCs, the stored settings, and any lingering cron jobs.
--
-- Manual issue logging is untouched: the `notes` table, the 'Issue' note type,
-- and the PM/Gaseous/SD Card Issue sensor statuses all live elsewhere.

DROP TABLE IF EXISTS public.quantaq_alerts CASCADE;
DROP FUNCTION IF EXISTS public.get_quantaq_cron_info();
DROP FUNCTION IF EXISTS public.run_quantaq_check();

-- Remove only the QuantAQ keys from the shared app_settings table.
DELETE FROM public.app_settings WHERE key IN ('quantaq_last_check', 'quantaq_paused');

-- Unschedule any remaining QuantAQ cron jobs (pg_cron). Guarded so this is a
-- no-op if pg_cron isn't installed or no such job exists.
DO $$
DECLARE j bigint;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'cron') THEN
    FOR j IN SELECT jobid FROM cron.job WHERE jobname LIKE 'quantaq%' LOOP
      PERFORM cron.unschedule(j);
    END LOOP;
  END IF;
EXCEPTION WHEN OTHERS THEN
  -- ignore: nothing to unschedule
  NULL;
END $$;
