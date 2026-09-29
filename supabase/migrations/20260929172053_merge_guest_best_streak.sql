-- Signing in also carries over the longest streak played signed out, so it
-- isn't lost from the account's best. Replaces the two-argument version,
-- which no released client calls yet.
drop function if exists public.merge_guest_streak(integer, text);

create or replace function public.merge_guest_streak(p_count integer, p_last_date text, p_best integer default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_today date := (now() at time zone 'America/New_York')::date;
  v_max int := (v_today - date '2026-04-14') + 1;
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
  -- Only a running streak (last solve today or yesterday, US Eastern) is considered.
  if v_guest_last is not null and v_guest_last in (v_today, v_today - 1)
     and p_count between 1 and v_max then
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
  if p_best is not null and least(p_best, v_max) > v_row.best_streak then
    update profiles set best_streak = least(p_best, v_max) where id = v_uid
    returning * into v_row;
  end if;
  return jsonb_build_object('streak', v_row.streak_count, 'streak_last_date', v_row.streak_last_date,
                            'best_streak', v_row.best_streak);
end;
$$;

revoke all on function public.merge_guest_streak(integer, text, integer) from public, anon;
grant execute on function public.merge_guest_streak(integer, text, integer) to authenticated;
