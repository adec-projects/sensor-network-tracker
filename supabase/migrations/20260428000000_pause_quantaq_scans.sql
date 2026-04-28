-- EMERGENCY PAUSE — QuantAQ asked us to stop hitting their API.
--
-- Two things happen here:
--   1. The 'quantaq-every-2h' cron job is unscheduled so the server-side
--      scanner stops calling QuantAQ on its own.
--   2. An app_settings flag `quantaq_paused = 'true'` is written so the
--      edge function (and the dashboard's Run Check Now button) can
--      short-circuit before any HTTP request goes out.
--
-- Code, secrets, and edge-function deployment are intentionally left
-- intact so this is reversible: drop the flag and re-schedule the cron
-- when QuantAQ gives the go-ahead.

DO $$
DECLARE
    job_id bigint;
BEGIN
    SELECT jobid INTO job_id FROM cron.job WHERE jobname = 'quantaq-every-2h';
    IF job_id IS NOT NULL THEN
        PERFORM cron.unschedule(job_id);
    END IF;
END;
$$;

-- Belt-and-suspenders: drop the legacy job too, in case it survived an
-- earlier silent unschedule failure.
DO $$
DECLARE
    job_id bigint;
BEGIN
    SELECT jobid INTO job_id FROM cron.job WHERE jobname = 'quantaq-weekday-check';
    IF job_id IS NOT NULL THEN
        PERFORM cron.unschedule(job_id);
    END IF;
END;
$$;

-- Kill-switch flag that the edge function reads on every invocation. The
-- function returns immediately when this is 'true', preventing the manual
-- Run Check Now button from triggering any QuantAQ request.
INSERT INTO public.app_settings (key, value)
VALUES ('quantaq_paused', 'true')
ON CONFLICT (key) DO UPDATE SET value = excluded.value, updated_at = now();
