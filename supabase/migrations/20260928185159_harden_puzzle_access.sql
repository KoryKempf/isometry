-- The puzzle generator edge function no longer exists (the daily cron job that
-- called it gets a 404), and anything that does need to write puzzles should use
-- the service role, which bypasses RLS. These policies only let anyone holding
-- the public anon key insert rows.
drop policy if exists "Service insert daily_puzzles" on public.daily_puzzles;
drop policy if exists "Service insert fingerprints" on public.puzzle_fingerprints;

-- Only release puzzles once their day has started in US Eastern time, so
-- tomorrow's puzzle can't be fetched (and solved) ahead of time.
drop policy if exists "Public read daily_puzzles" on public.daily_puzzles;
create policy "Public read released daily_puzzles" on public.daily_puzzles
  for select
  using (date <= to_char((now() at time zone 'America/New_York')::date, 'YYYY-MM-DD'));
