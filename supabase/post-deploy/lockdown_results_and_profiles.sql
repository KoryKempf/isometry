-- Run this AFTER the new index.html is live. The previous client wrote results
-- and streaks straight from the browser; once every player loads the new one,
-- results can only be saved through public.submit_result (which checks the
-- build against the puzzle) and streaks can only be changed by it.

-- Results: no direct inserts from the browser.
drop policy if exists "Users insert own results" on public.puzzle_results;
revoke insert, update, delete on public.puzzle_results from anon, authenticated;

-- Profiles: players may only change their display name.
revoke update on public.profiles from anon, authenticated;
grant update (display_name) on public.profiles to authenticated;
