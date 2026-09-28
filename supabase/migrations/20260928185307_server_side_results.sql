-- Hand-built puzzles carry a name that the game reveals after solving.
alter table public.daily_puzzles add column if not exists name text;

-- Results scored by cubes (v2): the structure is stored and checked server-side.
alter table public.puzzle_results
  add column if not exists min_cubes smallint,
  add column if not exists hints smallint not null default 0,
  add column if not exists checks smallint not null default 0,
  add column if not exists assisted boolean,
  add column if not exists grid text,
  add column if not exists verified boolean not null default false,
  add column if not exists version smallint not null default 1;

-- Save a result for the signed-in player. When p_grid is given (z,y,x order,
-- '0'/'1' per cell) it must cast exactly the puzzle's three views, and the cube
-- count is taken from it. Without a grid (results imported from an old local
-- save) the row is stored unverified. Streaks only advance on a verified
-- result for today's puzzle.
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
           streak_last_date = v_today
     where id = v_uid
    returning streak_count into v_streak;
  end if;

  return jsonb_build_object('saved', v_inserted > 0, 'verified', v_verified,
                            'placed', v_placed, 'min_cubes', v_min, 'streak', v_streak);
end;
$$;

revoke all on function public.submit_result(text, text, text, integer, integer, integer, integer, boolean, integer, integer) from public, anon;
grant execute on function public.submit_result(text, text, text, integer, integer, integer, integer, boolean, integer, integer) to authenticated;
