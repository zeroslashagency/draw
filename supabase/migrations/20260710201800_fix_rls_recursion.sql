-- Fix infinite RLS recursion by using security definer helpers

-- Helper: check if user is team member (bypasses RLS)
create or replace function is_team_member(team_id uuid, user_id uuid)
returns boolean
language sql
security definer
stable
as $$
  select exists (
    select 1 from public.team_members tm
    where tm.team_id = $1
    and tm.user_id = $2
  );
$$;

-- Helper: check if user is team owner/admin (bypasses RLS)
create or replace function is_team_admin(team_id uuid, user_id uuid)
returns boolean
language sql
security definer
stable
as $$
  select exists (
    select 1 from public.team_members tm
    where tm.team_id = $1
    and tm.user_id = $2
    and tm.role in ('owner', 'admin')
  );
$$;

-- Drop recursive policies
drop policy if exists "Team members can view members" on team_members;
drop policy if exists "Team owners/admins can manage members" on team_members;
drop policy if exists "Team members can view team" on teams;
drop policy if exists "Team owners/admins can update team" on teams;
drop policy if exists "Users can view shared scenes" on scenes;

-- team_members RLS
create policy "Users can view own memberships"
  on team_members for select
  using (user_id = auth.uid());

create policy "Users can view other members in same team"
  on team_members for select
  using (
    is_team_member(team_id, auth.uid())
    and user_id != auth.uid()
  );

create policy "Team admins can insert members"
  on team_members for insert
  with check (
    is_team_admin(team_id, auth.uid())
  );

create policy "Team admins can update members"
  on team_members for update
  using (
    is_team_admin(team_id, auth.uid())
  );

create policy "Team admins can delete members"
  on team_members for delete
  using (
    is_team_admin(team_id, auth.uid())
  );

-- Teams RLS
create policy "Team members can view team"
  on teams for select
  using (
    is_team_member(id, auth.uid())
  );

create policy "Team admins can update team"
  on teams for update
  using (
    is_team_admin(id, auth.uid())
  );

-- Scenes: shared scenes view (fixed: use helper instead of inline subquery to scene_shares.team_id join)
create policy "Users can view shared scenes"
  on scenes for select
  using (
    exists (
      select 1 from scene_shares ss
      where ss.scene_id = scenes.id
      and (
        ss.user_id = auth.uid()
        or is_team_member(ss.team_id, auth.uid())
      )
    )
  );
