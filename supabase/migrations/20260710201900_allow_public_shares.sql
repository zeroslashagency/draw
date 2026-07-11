-- Allow anonymous/public shareable link creation and loading

-- Drop existing policies that conflict
drop policy if exists "Allow public to create share scenes" on scenes;
drop policy if exists "Allow public to view scenes by share token" on scenes;

-- Allow anonymous users to insert scenes for public sharing
create policy "Allow public to create share scenes"
  on scenes for insert
  with check (user_id is null);

-- Allow public to select scenes created anonymously
-- (used for loading shared scenes where the user has the token)
create policy "Allow public to view scenes by share token"
  on scenes for select
  using (user_id is null);

-- Allow anonymous users to create share tokens for their scenes
drop policy if exists "Allow public to create share tokens" on scene_shares;
create policy "Allow public to create share tokens"
  on scene_shares for insert
  with check (
    exists (
      select 1 from scenes
      where scenes.id = scene_id
      and scenes.user_id is null
    )
  );

-- Allow public to view share tokens (by token lookup)
drop policy if exists "Allow public to view share tokens" on scene_shares;
create policy "Allow public to view share tokens"
  on scene_shares for select
  using (true);
