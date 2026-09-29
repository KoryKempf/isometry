-- Longest streak per account, kept by the server alongside the running streak.
alter table public.profiles add column if not exists best_streak integer not null default 0;
update public.profiles set best_streak = greatest(best_streak, streak_count);

-- Same as before, but also keeps best_streak and returns the account's streak.
create or replace function public.submit_result(
  p_date text,
  p_difficulty text,
  p_grid text default null,
  p_time_seconds integer default 0,
  p_moves integer default 0,
  p_hints integer default 0,
  p_checks integer default 1,
  p_assisted boolean default null,
  p_min_cubes integer default null,
  p_placed integer default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_today text := to_char((now() at time zone 'America/New_York')::date, 'YYYY-MM-DD');
  v_yesterday text := to_char((now() at time zone 'America/New_York')::date - 1, 'YYYY-MM-DD');
  v_puzzle jsonb;
  v_name text;
  v_n int;
  v_mismatch int;
  v_lb int;
  v_placed int;
  v_min int;
  v_verified boolean := false;
  v_secs int := greatest(coalesce(p_time_seconds, 0), 0);
  v_inserted int;
  v_streak int;
  v_last text;
  v_best int;
begin
  if v_uid is null then
    raise exception 'sign in required' using errcode = '42501';
  end if;
  if p_date is null or p_date !~ '^\d{4}-\d{2}-\d{2}$' or p_date < '2026-04-14' or p_date > v_today then
    raise exception 'invalid puzzle date' using errcode = '22023';
  end if;

  select grid, name into v_puzzle, v_name
  from daily_puzzles where date = p_date and difficulty = p_difficulty;
  if v_puzzle is null then
    raise exception 'unknown puzzle' using errcode = '22023';
  end if;
  v_n := jsonb_array_length(v_puzzle);

  if p_grid is not null then
    if length(p_grid) <> v_n * v_n * v_n or p_grid !~ '^[01]+$' then
      raise exception 'malformed grid' using errcode = '22023';
    end if;
    with cells as (
      select z, y, x,
             (v_puzzle -> z -> y ->> x)::int as t,
             substr(p_grid, z * v_n * v_n + y * v_n + x + 1, 1)::int as u
      from generate_series(0, v_n - 1) z, generate_series(0, v_n - 1) y, generate_series(0, v_n - 1) x
    ),
    tv as (select max(t) t, max(u) u from cells group by y, x),
    fv as (select max(t) t, max(u) u from cells group by z, x),
    sv as (select max(t) t, max(u) u from cells group by z, y)
    select (select count(*) from tv where t <> u)
         + (select count(*) from fv where t <> u)
         + (select count(*) from sv where t <> u),
           greatest((select count(*) from tv where t = 1),
                    (select count(*) from fv where t = 1),
                    (select count(*) from sv where t = 1))
      into v_mismatch, v_lb;
    if v_mismatch > 0 then
      raise exception 'submission does not match the puzzle views' using errcode = '22023';
    end if;
    v_placed := length(replace(p_grid, '0', ''));
    v_verified := true;
    -- The minimum is computed by the client; clamp it to what the server can
    -- prove: no build beats the busiest view, and this build is itself valid.
    v_min := least(greatest(coalesce(p_min_cubes, v_placed), v_lb), v_placed);
  else
    v_placed := greatest(coalesce(p_placed, 0), 0);
  end if;

  insert into puzzle_results (
    user_id, date, difficulty, moves, time_seconds, time_display, placed, par, ratio,
    is_daily, puzzle_name, min_cubes, hints, checks, assisted, grid, verified, version
  ) values (
    v_uid, p_date, p_difficulty, greatest(coalesce(p_moves, 0), 0), v_secs,
    (v_secs / 60)::text || ':' || lpad((v_secs % 60)::text, 2, '0'),
    v_placed, coalesce(v_min, v_placed),
    case when coalesce(v_min, v_placed) > 0 then round(v_placed::numeric / coalesce(v_min, v_placed), 3) else 1 end,
    true, coalesce(v_name, ''), v_min,
    least(greatest(coalesce(p_hints, 0), 0), 32767), least(greatest(coalesce(p_checks, 0), 0), 32767),
    p_assisted, case when v_verified then p_grid end, v_verified, 2
  )
  on conflict (user_id, date, difficulty) do nothing;
  get diagnostics v_inserted = row_count;

  if v_verified and v_inserted > 0 and p_date = v_today then
    update profiles
       set streak_count = case when streak_last_date = v_today then streak_count
                               when streak_last_date = v_yesterday then streak_count + 1
                               else 1 end,
           streak_last_date = v_today,
           best_streak = greatest(best_streak, case when streak_last_date = v_today then streak_count
                                                    when streak_last_date = v_yesterday then streak_count + 1
                                                    else 1 end)
     where id = v_uid
    returning streak_count, streak_last_date, best_streak into v_streak, v_last, v_best;
  else
    select streak_count, streak_last_date, best_streak into v_streak, v_last, v_best
    from profiles where id = v_uid;
  end if;

  return jsonb_build_object('saved', v_inserted > 0, 'verified', v_verified,
                            'placed', v_placed, 'min_cubes', v_min,
                            'streak', v_streak, 'streak_last_date', v_last, 'best_streak', v_best);
end;
$$;

revoke all on function public.submit_result(text, text, text, integer, integer, integer, integer, boolean, integer, integer) from public, anon;
grant execute on function public.submit_result(text, text, text, integer, integer, integer, integer, boolean, integer, integer) to authenticated;

-- When a player signs in on a device where they had a streak going while
-- signed out, keep the longer of the two. Only a running streak (last solve
-- today or yesterday, US Eastern) is considered.
create or replace function public.merge_guest_streak(p_count integer, p_last_date text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_today date := (now() at time zone 'America/New_York')::date;
  v_guest_last date;
  v_row profiles%rowtype;
  v_acct int;
  v_count int;
  v_last date;
begin
  if v_uid is null then
    raise exception 'sign in required' using errcode = '42501';
  end if;
  select * into v_row from profiles where id = v_uid for update;
  if not found then
    raise exception 'no profile' using errcode = '22023';
  end if;
  begin
    v_guest_last := p_last_date::date;
  exception when others then
    v_guest_last := null;
  end;
  if v_guest_last is not null and v_guest_last in (v_today, v_today - 1)
     and p_count between 1 and (v_today - date '2026-04-14') + 1 then
    v_acct := case when v_row.streak_last_date in (to_char(v_today, 'YYYY-MM-DD'), to_char(v_today - 1, 'YYYY-MM-DD'))
                   then v_row.streak_count else 0 end;
    if p_count > v_acct then
      v_count := p_count;
      v_last := v_guest_last;
      -- A solve on the account today extends a signed-out streak that ended yesterday.
      if v_guest_last = v_today - 1 and v_row.streak_last_date = to_char(v_today, 'YYYY-MM-DD') then
        v_count := p_count + 1;
        v_last := v_today;
      end if;
      update profiles
         set streak_count = v_count, streak_last_date = to_char(v_last, 'YYYY-MM-DD'),
             best_streak = greatest(best_streak, v_count)
       where id = v_uid
      returning * into v_row;
    end if;
  end if;
  return jsonb_build_object('streak', v_row.streak_count, 'streak_last_date', v_row.streak_last_date,
                            'best_streak', v_row.best_streak);
end;
$$;

revoke all on function public.merge_guest_streak(integer, text) from public, anon;
grant execute on function public.merge_guest_streak(integer, text) to authenticated;
