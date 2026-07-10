import { createClient } from "@supabase/supabase-js";

const supabaseUrl = import.meta.env.VITE_APP_SUPABASE_URL;
const supabaseKey = import.meta.env.VITE_APP_SUPABASE_PUBLISHABLE_KEY;

export const supabase = createClient(supabaseUrl, supabaseKey);

export type Scene = {
  id: string;
  user_id: string;
  name: string;
  folder_id: string | null;
  scene_data: string;
  version: number;
  created_at: string;
  updated_at: string;
  is_deleted: boolean;
};

export type Folder = {
  id: string;
  user_id: string;
  name: string;
  parent_id: string | null;
  created_at: string;
  updated_at: string;
};

export type Team = {
  id: string;
  name: string;
  created_at: string;
  updated_at: string;
};

export type TeamMember = {
  id: string;
  team_id: string;
  user_id: string;
  role: "owner" | "admin" | "member";
  created_at: string;
};

export type SceneShare = {
  id: string;
  scene_id: string;
  team_id: string | null;
  user_id: string | null;
  permission: "view" | "edit";
  token: string | null;
  created_at: string;
};

export type Comment = {
  id: string;
  scene_id: string;
  user_id: string;
  content: string;
  element_id: string | null;
  x: number;
  y: number;
  created_at: string;
  updated_at: string;
};
