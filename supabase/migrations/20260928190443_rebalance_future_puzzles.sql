-- Untouched copy of every puzzle before re-ordering future days (private schema,
-- not exposed through the API).
create schema if not exists backup;
revoke all on schema backup from public, anon, authenticated;
create table if not exists backup.daily_puzzles_20260928 as table public.daily_puzzles;

-- Difficulty proxy: how many more cubes the obvious "fill every consistent cell"
-- build uses than the tightest lower bound on a perfect build. On Sept 1-28, 2026
-- it orders each day's puzzles exactly as the exact solver does.
create or replace function backup.puzzle_proxy(g jsonb, out maxfill int, out lb int, out cubes int)
language sql immutable as $$
  with n as (select jsonb_array_length(g) - 1 as m),
  cells as (
    select z, y, x, (g -> z -> y ->> x)::int as v
    from n, generate_series(0, n.m) z, generate_series(0, n.m) y, generate_series(0, n.m) x
  ),
  tv as (select y, x, max(v) as o from cells group by y, x),
  fv as (select z, x, max(v) as o from cells group by z, x),
  sv as (select z, y, max(v) as o from cells group by z, y)
  select
    (select count(*)::int from cells c
       join tv on tv.y = c.y and tv.x = c.x
       join fv on fv.z = c.z and fv.x = c.x
       join sv on sv.z = c.z and sv.y = c.y
     where tv.o = 1 and fv.o = 1 and sv.o = 1),
    greatest(
      (select sum(greatest(a, b))::int from (select z, sum(o) a, (select sum(o) from sv where sv.z = fv.z) b from fv group by z) q),
      (select sum(greatest(a, b))::int from (select x, sum(o) a, (select sum(o) from tv where tv.x = fv.x) b from fv group by x) q),
      (select sum(greatest(a, b))::int from (select y, sum(o) a, (select sum(o) from tv where tv.y = sv.y) b from sv group by y) q)
    ),
    (select sum(v)::int from cells)
$$;

-- Sunday specials: hand-built shapes in the Medium slot for the next 12 Sundays.
update public.daily_puzzles d
   set grid = s.grid, fingerprint = s.fp, name = s.name
  from (values
  ('2026-10-04','The Table','[[[1,0,1],[0,0,0],[1,0,1]],[[1,1,1],[1,1,1],[1,1,1]],[[0,0,0],[0,0,0],[0,0,0]]]'::jsonb,'[[[1,1,1],[1,1,1],[1,1,1]],[[0,0,0],[1,1,1],[1,0,1]],[[0,0,0],[1,1,1],[1,0,1]]]'),
  ('2026-10-11','The Colonnade','[[[1,0,1],[0,0,0],[1,0,1]],[[1,0,1],[0,0,0],[1,0,1]],[[1,0,1],[0,0,0],[1,0,1]]]'::jsonb,'[[[1,0,1],[0,0,0],[1,0,1]],[[1,0,1],[1,0,1],[1,0,1]],[[1,0,1],[1,0,1],[1,0,1]]]'),
  ('2026-10-18','The Podium','[[[0,0,0],[1,1,1],[1,1,1]],[[0,0,0],[1,1,0],[1,1,0]],[[0,0,0],[0,1,0],[0,1,0]]]'::jsonb,'[[[0,0,0],[1,1,1],[1,1,1]],[[0,1,0],[1,1,0],[1,1,1]],[[0,1,1],[0,1,1],[0,1,1]]]'),
  ('2026-10-25','The Well','[[[1,1,1],[1,0,1],[1,1,1]],[[1,1,1],[1,0,1],[1,1,1]],[[0,0,0],[0,0,0],[0,0,0]]]'::jsonb,'[[[1,1,1],[1,0,1],[1,1,1]],[[0,0,0],[1,1,1],[1,1,1]],[[0,0,0],[1,1,1],[1,1,1]]]'),
  ('2026-11-01','The Chair','[[[1,0,1],[0,0,0],[1,0,1]],[[1,1,1],[1,1,1],[1,1,1]],[[1,1,1],[0,0,0],[0,0,0]]]'::jsonb,'[[[1,1,1],[1,1,1],[1,1,1]],[[1,1,1],[1,1,1],[1,0,1]],[[1,0,0],[1,1,1],[1,0,1]]]'),
  ('2026-11-08','The Gateway','[[[0,0,0],[1,0,1],[0,0,0]],[[0,0,0],[1,0,1],[0,0,0]],[[0,0,0],[1,1,1],[0,0,0]]]'::jsonb,'[[[0,0,0],[1,1,1],[0,0,0]],[[1,1,1],[1,0,1],[1,0,1]],[[0,1,0],[0,1,0],[0,1,0]]]'),
  ('2026-11-15','The Crown','[[[1,1,1],[1,0,1],[1,1,1]],[[1,0,1],[0,0,0],[1,0,1]],[[0,0,0],[0,0,0],[0,0,0]]]'::jsonb,'[[[1,1,1],[1,0,1],[1,1,1]],[[0,0,0],[1,0,1],[1,1,1]],[[0,0,0],[1,0,1],[1,1,1]]]'),
  ('2026-11-22','The Grand Stairs','[[[0,0,0],[1,1,1],[1,1,1]],[[0,0,0],[0,1,1],[0,1,1]],[[0,0,0],[0,0,1],[0,0,1]]]'::jsonb,'[[[0,0,0],[1,1,1],[1,1,1]],[[0,0,1],[0,1,1],[1,1,1]],[[0,1,1],[0,1,1],[0,1,1]]]'),
  ('2026-11-29','The Bench','[[[0,0,0],[1,0,1],[1,0,1]],[[0,0,0],[1,1,1],[1,1,1]],[[0,0,0],[0,0,0],[0,0,0]]]'::jsonb,'[[[0,0,0],[1,1,1],[1,1,1]],[[0,0,0],[1,1,1],[1,0,1]],[[0,0,0],[0,1,1],[0,1,1]]]'),
  ('2026-12-06','The Tunnel','[[[0,0,0],[1,0,1],[1,0,1]],[[0,0,0],[1,0,1],[1,0,1]],[[0,0,0],[1,1,1],[1,1,1]]]'::jsonb,'[[[0,0,0],[1,1,1],[1,1,1]],[[1,1,1],[1,0,1],[1,0,1]],[[0,1,1],[0,1,1],[0,1,1]]]'),
  ('2026-12-13','The Tower','[[[1,1,1],[1,1,1],[1,1,1]],[[0,0,0],[0,1,0],[0,0,0]],[[0,0,0],[0,1,0],[0,0,0]]]'::jsonb,'[[[1,1,1],[1,1,1],[1,1,1]],[[0,1,0],[0,1,0],[1,1,1]],[[0,1,0],[0,1,0],[1,1,1]]]'),
  ('2026-12-20','The Sofa','[[[1,1,1],[1,1,1],[1,1,1]],[[1,1,1],[1,0,1],[1,0,1]],[[0,0,0],[0,0,0],[0,0,0]]]'::jsonb,'[[[1,1,1],[1,1,1],[1,1,1]],[[0,0,0],[1,1,1],[1,1,1]],[[0,0,0],[1,1,1],[1,1,1]]]')
  ) as s(date, name, grid, fp)
 where d.date = s.date and d.difficulty = 'medium'
   and s.date > to_char((now() at time zone 'America/New_York')::date, 'YYYY-MM-DD');

-- Re-order every future day's generated 3x3x3 puzzles so Easy < Medium < Hard.
-- On days with a Sunday special, only Easy and Hard are re-ordered.
with m as (
  select p.id, p.date, p.grid, p.fingerprint, q.maxfill, q.lb, q.cubes
  from public.daily_puzzles p, lateral backup.puzzle_proxy(p.grid) q
  where p.date > to_char((now() at time zone 'America/New_York')::date, 'YYYY-MM-DD')
    and p.difficulty in ('easy', 'medium', 'hard')
    and p.name is null
),
ranked as (
  select m.*,
         row_number() over (partition by m.date order by (m.maxfill - m.lb), m.maxfill, m.cubes, m.id) as rk,
         exists (select 1 from public.daily_puzzles s where s.date = m.date and s.name is not null) as has_special
  from m
),
target as (
  select date, grid, fingerprint,
         case when has_special then (array['easy', 'hard'])[rk]
              else (array['easy', 'medium', 'hard'])[rk] end as difficulty
  from ranked
)
update public.daily_puzzles d
   set grid = t.grid, fingerprint = t.fingerprint
  from target t
 where d.date = t.date and d.difficulty = t.difficulty and d.grid is distinct from t.grid;

drop function backup.puzzle_proxy(jsonb);
