-- 0003_tombstone_purge.sql
--
-- Housekeeping for soft-deleted rows. Sync marks deletes as tombstones
-- (is_deleted = true, deleted_at set) so other devices can converge; once a
-- tombstone is older than the retention window no online device still needs
-- it, and a device offline longer than that takes the full initial-pull path
-- anyway. This purges them.
--
-- Safe to apply even where pg_cron is unavailable (e.g. Supabase free tier):
-- the purge function is always created; the schedule is only added when the
-- extension exists.

-- ---------------------------------------------------------------------------
-- purge function — deletes tombstones older than 30 days across every synced
-- table. Callable manually (select public.purge_sync_tombstones();) or by cron.
-- ---------------------------------------------------------------------------
create or replace function public.purge_sync_tombstones()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  t text;
begin
  foreach t in array array[
    'accounts','transactions','categories','credit_cards','loans','budgets',
    'recurring_payments','investments','goals','notes'
  ]
  loop
    execute format(
      'delete from public.%I where is_deleted = true and deleted_at is not null '
      'and deleted_at < now() - interval ''30 days''', t);
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- schedule it daily at 03:15 UTC when pg_cron is present
-- ---------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule('purge_sync_tombstones')
      where exists (select 1 from cron.job where jobname = 'purge_sync_tombstones');
    perform cron.schedule(
      'purge_sync_tombstones',
      '15 3 * * *',
      $cron$select public.purge_sync_tombstones();$cron$
    );
  else
    raise notice 'pg_cron not installed — run select public.purge_sync_tombstones(); manually or enable the extension.';
  end if;
end $$;
