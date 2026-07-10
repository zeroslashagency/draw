-- Excalidraw Supabase Schema

-- 1. FOLDERS (must be created before scenes)
create table if not exists folders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  parent_id uuid references folders(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_folders_user_id on folders(user_id);
create index if not exists idx_folders_parent_id on folders(parent_id);

-- 2. SCENES
create table if not exists scenes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null default 'Untitled',
  folder_id uuid references folders(id) on delete set null,
  scene_data text not null default '',
  version integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  is_deleted boolean not null default false
);

create index if not exists idx_scenes_user_id on scenes(user_id);
create index if not exists idx_scenes_folder_id on scenes(folder_id);
create index if not exists idx_scenes_updated_at on scenes(updated_at desc);

-- 3. TEAMS
create table if not exists teams (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 4. TEAM MEMBERS
create table if not exists team_members (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references teams(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('owner', 'admin', 'member')),
  created_at timestamptz not null default now(),
  unique(team_id, user_id)
);

create index if not exists idx_team_members_team_id on team_members(team_id);
create index if not exists idx_team_members_user_id on team_members(user_id);

-- 5. SCENE SHARES (permissions + share links)
create table if not exists scene_shares (
  id uuid primary key default gen_random_uuid(),
  scene_id uuid not null references scenes(id) on delete cascade,
  team_id uuid references teams(id) on delete cascade,
  user_id uuid references auth.users(id) on delete cascade,
  permission text not null check (permission in ('view', 'edit')),
  token text unique,
  created_at timestamptz not null default now()
);

create index if not exists idx_scene_shares_scene_id on scene_shares(scene_id);
create index if not exists idx_scene_shares_token on scene_shares(token);

-- 6. COMMENTS
create table if not exists comments (
  id uuid primary key default gen_random_uuid(),
  scene_id uuid not null references scenes(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  content text not null,
  element_id text,
  x float8 not null default 0,
  y float8 not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_comments_scene_id on comments(scene_id);

-- Enable RLS
alter table scenes enable row level security;
alter table folders enable row level security;
alter table teams enable row level security;
alter table team_members enable row level security;
alter table scene_shares enable row level security;
alter table comments enable row level security;

-- RLS: scenes
create policy "Users can CRUD own scenes"
  on scenes for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy "Users can view shared scenes"
  on scenes for select
  using (
    exists (
      select 1 from scene_shares
      where scene_shares.scene_id = scenes.id
      and (
        scene_shares.user_id = auth.uid()
        or scene_shares.team_id in (
          select team_id from team_members where user_id = auth.uid()
        )
      )
    )
  );

-- RLS: folders
create policy "Users can CRUD own folders"
  on folders for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- RLS: teams
create policy "Team members can view team"
  on teams for select
  using (
    exists (
      select 1 from team_members
      where team_members.team_id = teams.id
      and team_members.user_id = auth.uid()
    )
  );

create policy "Team owners/admins can update team"
  on teams for update
  using (
    exists (
      select 1 from team_members
      where team_members.team_id = teams.id
      and team_members.user_id = auth.uid()
      and team_members.role in ('owner', 'admin')
    )
  );

-- RLS: team_members
create policy "Team members can view members"
  on team_members for select
  using (
    exists (
      select 1 from team_members tm
      where tm.team_id = team_members.team_id
      and tm.user_id = auth.uid()
    )
  );

create policy "Team owners/admins can manage members"
  on team_members for all
  using (
    exists (
      select 1 from team_members tm
      where tm.team_id = team_members.team_id
      and tm.user_id = auth.uid()
      and tm.role in ('owner', 'admin')
    )
  );

-- RLS: scene_shares
create policy "Scene owners can manage shares"
  on scene_shares for all
  using (
    exists (
      select 1 from scenes
      where scenes.id = scene_shares.scene_id
      and scenes.user_id = auth.uid()
    )
  );

create policy "Users can view shares for their scenes"
  on scene_shares for select
  using (
    scene_id in (
      select id from scenes where user_id = auth.uid()
    )
  );

-- RLS: comments
create policy "Users can view comments on accessible scenes"
  on comments for select
  using (
    exists (
      select 1 from scenes
      where scenes.id = comments.scene_id
      and (
        scenes.user_id = auth.uid()
        or exists (
          select 1 from scene_shares
          where scene_shares.scene_id = comments.scene_id
          and scene_shares.user_id = auth.uid()
        )
      )
    )
  );

create policy "Users can insert comments on accessible scenes"
  on comments for insert
  with check (
    exists (
      select 1 from scenes
      where scenes.id = comments.scene_id
      and (
        scenes.user_id = auth.uid()
        or exists (
          select 1 from scene_shares
          where scene_shares.scene_id = comments.scene_id
          and scene_shares.user_id = auth.uid()
          and scene_shares.permission = 'edit'
        )
      )
    )
  );

--- Enable realtime for comments
alter publication supabase_realtime add table comments;

-- Storage bucket for excalidraw files
insert into storage.buckets (id, name, public) values ('excalidraw-files', 'excalidraw-files', false)
on conflict (id) do nothing;

create policy "Users can CRUD own files"
  on storage.objects for all
  using (auth.uid() = owner)
  with check (auth.uid() = owner);

-- Auto-update updated_at
create or replace function update_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

create trigger scenes_updated_at
  before update on scenes
  for each row execute function update_updated_at();

create trigger folders_updated_at
  before update on folders
  for each row execute function update_updated_at();

create trigger teams_updated_at
  before update on teams
  for each row execute function update_updated_at();

create trigger comments_updated_at
  before update on comments
  for each row execute function update_updated_at();
