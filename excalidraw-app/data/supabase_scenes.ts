import { supabase, type Scene, type Folder } from "./supabase";
import { reconcileElements } from "@excalidraw/excalidraw";
import { restoreElements } from "@excalidraw/excalidraw/data/restore";
import { getSceneVersion } from "@excalidraw/element";
import {
  encryptData,
  decryptData,
} from "@excalidraw/excalidraw/data/encryption";

import type { ExcalidrawElement } from "@excalidraw/element/types";
import type { AppState } from "@excalidraw/excalidraw/types";
import type { SyncableExcalidrawElement } from "./index";

export async function listScenes(folderId?: string | null) {
  let query = supabase
    .from("scenes")
    .select("id, name, folder_id, created_at, updated_at, version")
    .eq("is_deleted", false)
    .order("updated_at", { ascending: false });

  if (folderId === null) {
    query = query.is("folder_id", null);
  } else if (folderId) {
    query = query.eq("folder_id", folderId);
  }

  const { data, error } = await query;
  if (error) throw error;
  return data as Pick<Scene, "id" | "name" | "folder_id" | "created_at" | "updated_at" | "version">[];
}

export async function listFolders(parentId?: string | null) {
  let query = supabase
    .from("folders")
    .select("*")
    .order("name");

  if (parentId === null) {
    query = query.is("parent_id", null);
  } else if (parentId) {
    query = query.eq("parent_id", parentId);
  }

  const { data, error } = await query;
  if (error) throw error;
  return data as Folder[];
}

export async function createFolder(name: string, parentId?: string | null) {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw new Error("Not authenticated");

  const { data, error } = await supabase
    .from("folders")
    .insert({ name, parent_id: parentId || null, user_id: user.id })
    .select()
    .single();

  if (error) throw error;
  return data as Folder;
}

export async function createScene(name: string, folderId?: string | null) {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw new Error("Not authenticated");

  const { data, error } = await supabase
    .from("scenes")
    .insert({
      name,
      folder_id: folderId || null,
      user_id: user.id,
      scene_data: "",
      version: 0,
    })
    .select()
    .single();

  if (error) throw error;
  return data as Scene;
}

export async function saveScene(
  sceneId: string,
  elements: readonly ExcalidrawElement[],
  encryptionKey?: string,
) {
  let sceneData: string;

  if (encryptionKey) {
    const json = JSON.stringify(elements);
    const encoded = new TextEncoder().encode(json);
    const { encryptedBuffer } = await encryptData(encryptionKey, encoded);
    sceneData = btoa(String.fromCharCode(...new Uint8Array(encryptedBuffer)));
  } else {
    sceneData = JSON.stringify(elements);
  }

  const version = getSceneVersion(elements);

  const { error } = await supabase
    .from("scenes")
    .update({
      scene_data: sceneData,
      version,
      updated_at: new Date().toISOString(),
    })
    .eq("id", sceneId);

  if (error) throw error;
}

export async function loadScene(
  sceneId: string,
  encryptionKey?: string,
): Promise<readonly ExcalidrawElement[] | null> {
  const { data, error } = await supabase
    .from("scenes")
    .select("scene_data, version")
    .eq("id", sceneId)
    .single();

  if (error || !data) return null;

  try {
    let elements: readonly ExcalidrawElement[];

    if (encryptionKey) {
      const binaryStr = atob(data.scene_data);
      const bytes = new Uint8Array(binaryStr.length);
      for (let i = 0; i < binaryStr.length; i++) {
        bytes[i] = binaryStr.charCodeAt(i);
      }
      const decrypted = await decryptData(
        bytes.slice(0, 12),
        bytes.slice(12),
        encryptionKey,
      );
      const decoded = new TextDecoder("utf-8").decode(
        new Uint8Array(decrypted),
      );
      elements = JSON.parse(decoded);
    } else {
      elements = JSON.parse(data.scene_data);
    }

    return elements;
  } catch {
    return null;
  }
}

export async function deleteScene(sceneId: string) {
  const { error } = await supabase
    .from("scenes")
    .update({ is_deleted: true })
    .eq("id", sceneId);

  if (error) throw error;
}

export async function renameScene(sceneId: string, name: string) {
  const { error } = await supabase
    .from("scenes")
    .update({ name })
    .eq("id", sceneId);

  if (error) throw error;
}

export async function getCurrentUser() {
  const { data: { user } } = await supabase.auth.getUser();
  return user;
}

export async function signInWithEmail(email: string, password: string) {
  const { data, error } = await supabase.auth.signInWithPassword({
    email,
    password,
  });
  if (error) throw error;
  return data;
}

export async function signUpWithEmail(email: string, password: string) {
  const { data, error } = await supabase.auth.signUp({
    email,
    password,
  });
  if (error) throw error;
  return data;
}

export async function signOut() {
  const { error } = await supabase.auth.signOut();
  if (error) throw error;
}

// Shareable link functions
export async function createShareableLink(
  elements: readonly ExcalidrawElement[],
  appState: Partial<AppState>,
  encryptionKey: string,
): Promise<{ id: string; token: string }> {
  const { data: { user } } = await supabase.auth.getUser();
  
  // Encrypt and store scene data
  const json = JSON.stringify({ elements, appState });
  const encoded = new TextEncoder().encode(json);
  const { encryptedBuffer } = await encryptData(encryptionKey, encoded);
  const sceneData = btoa(String.fromCharCode(...new Uint8Array(encryptedBuffer)));

  // Generate random token for shareable link
  const tokenBytes = new Uint8Array(32);
  window.crypto.getRandomValues(tokenBytes);
  const token = Array.from(tokenBytes)
    .map(b => b.toString(16).padStart(2, '0'))
    .join('');

  // Create scene
  const { data: scene, error: sceneError } = await supabase
    .from("scenes")
    .insert({
      name: "Shared Scene",
      user_id: user?.id || null,
      scene_data: sceneData,
      version: getSceneVersion(elements),
    })
    .select()
    .single();

  if (sceneError) throw sceneError;

  // Create public share
  const { data: share, error: shareError } = await supabase
    .from("scene_shares")
    .insert({
      scene_id: scene.id,
      token,
      permission: "view",
    })
    .select()
    .single();

  if (shareError) throw shareError;

  return { id: scene.id, token };
}

export async function loadSceneByToken(
  token: string,
  encryptionKey: string,
): Promise<{ elements: readonly ExcalidrawElement[]; appState: Partial<AppState> } | null> {
  // Find the share by token
  const { data: share, error: shareError } = await supabase
    .from("scene_shares")
    .select("scene_id")
    .eq("token", token)
    .single();

  if (shareError || !share) return null;

  // Load the scene
  const { data: scene, error: sceneError } = await supabase
    .from("scenes")
    .select("scene_data")
    .eq("id", share.scene_id)
    .single();

  if (sceneError || !scene) return null;

  try {
    // Decrypt scene data
    const binaryStr = atob(scene.scene_data);
    const bytes = new Uint8Array(binaryStr.length);
    for (let i = 0; i < binaryStr.length; i++) {
      bytes[i] = binaryStr.charCodeAt(i);
    }
    const decrypted = await decryptData(
      bytes.slice(0, 12),
      bytes.slice(12),
      encryptionKey,
    );
    const decoded = new TextDecoder("utf-8").decode(new Uint8Array(decrypted));
    const parsed = JSON.parse(decoded);
    
    return {
      elements: parsed.elements || [],
      appState: parsed.appState || {},
    };
  } catch (err) {
    console.error("Failed to decrypt scene:", err);
    return null;
  }
}
