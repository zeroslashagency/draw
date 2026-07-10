-- Drop ALL existing policies on affected tables
drop policy if exists "Users can CRUD own scenes" on scenes;
drop policy if exists "Users can view shared scenes" on scenes;
drop policy if exists "Scene owners can manage shares" on scene_shares;
drop policy if exists "Users can view shares for their scenes" on scene_shares;
drop policy if exists "Users can view comments on accessible scenes" on comments;
drop policy if exists "Users can insert comments on accessible scenes" on comments;

-- Helper: check if user owns a scene (bypasses RLS)
create or replace function owns_scene(scene_id uuid, user_id uuid)
returns boolean
language sql
security definer
stable
as $$
  select exists (
    select 1 from public.scenes s
    where s.id = $1
    and s.user_id = $2
  );
$$;

-- Helper: check if user has access to scene via shares (bypasses RLS)
create or replace function can_access_scene(scene_id uuid, user_id uuid)
returns boolean
language sql
security definer
stable
as $$
  select exists (
    select 1 from public.scenes s
    where s.id = $1
    and (
      s.user_id = $2
      or exists (
        select 1 from public.scene_shares ss
        where ss.scene_id = s.id
        and (
          ss.user_id = $2
          or exists (
            select 1 from public.team_members tm
            where tm.team_id = ss.team_id
            and tm.user_id = $2
          )
        )
      )
    )
  );
$$;

-- Helper: check if user can edit scene (bypasses RLS)
create or replace function can_edit_scene(scene_id uuid, user_id uuid)
returns boolean
language sql
security definer
stable
as $$
  select exists (
    select 1 from public.scenes s
    where s.id = $1
    and (
      s.user_id = $2
      or exists (
        select 1 from public.scene_shares ss
        where ss.scene_id = s.id
        and ss.permission = 'edit'
        and (
          ss.user_id = $2
          or exists (
            select 1 from public.team_members tm
            where tm.team_id = ss.team_id
            and tm.user_id = $2
          )
        )
      )
    )
  );
$$;

-- scenes RLS
create policy "Users can CRUD own scenes"
  on scenes for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy "Users can view shared scenes"
  on scenes for select
  using (can_access_scene(id, auth.uid()));

-- scene_shares RLS
create policy "Scene owners can manage shares"
  on scene_shares for all
  using (owns_scene(scene_id, auth.uid()));

create policy "Users can view shares for shared scenes"
  on scene_shares for select
  using (can_access_scene(scene_id, auth.uid()));

-- comments RLS
create policy "Users can view comments on accessible scenes"
  on comments for select
  using (can_access_scene(scene_id, auth.uid()));

create policy "Users can insert comments on editable scenes"
  on comments for insert
  with check (can_edit_scene(scene_id, auth.uid()));
