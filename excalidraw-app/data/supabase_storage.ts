import { supabase } from "./supabase";
import { decompressData } from "@excalidraw/excalidraw/data/encode";
import { MIME_TYPES } from "@excalidraw/common";

import type { BinaryFileData, BinaryFileMetadata, DataURL } from "@excalidraw/excalidraw/types";
import type { FileId } from "@excalidraw/element/types";
import { FILE_CACHE_MAX_AGE_SEC } from "../app_constants";

export async function saveFilesToSupabase(
  prefix: string,
  files: { id: FileId; buffer: Uint8Array }[],
) {
  const erroredFiles: FileId[] = [];
  const savedFiles: FileId[] = [];

  await Promise.all(
    files.map(async ({ id, buffer }) => {
      try {
        const { error } = await supabase.storage
          .from("excalidraw-files")
          .upload(`${prefix}/${id}`, buffer, {
            contentType: "application/octet-stream",
            cacheControl: `public, max-age=${FILE_CACHE_MAX_AGE_SEC}`,
            upsert: true,
          });

        if (error) {
          erroredFiles.push(id);
        } else {
          savedFiles.push(id);
        }
      } catch {
        erroredFiles.push(id);
      }
    }),
  );

  return { savedFiles, erroredFiles };
}

export async function loadFilesFromSupabase(
  prefix: string,
  decryptionKey: string,
  filesIds: readonly FileId[],
) {
  const loadedFiles: BinaryFileData[] = [];
  const erroredFiles = new Map<FileId, true>();

  await Promise.all(
    [...new Set(filesIds)].map(async (id) => {
      try {
        const { data, error } = await supabase.storage
          .from("excalidraw-files")
          .download(`${prefix}/${id}`);

        if (error) {
          erroredFiles.set(id, true);
          return;
        }

        const arrayBuffer = await data.arrayBuffer();

        const { data: decompressedData, metadata } =
          await decompressData<BinaryFileMetadata>(
            new Uint8Array(arrayBuffer),
            { decryptionKey },
          );

        const dataURL = new TextDecoder().decode(decompressedData) as DataURL;

        loadedFiles.push({
          mimeType: metadata.mimeType || MIME_TYPES.binary,
          id,
          dataURL,
          created: metadata?.created || Date.now(),
          lastRetrieved: metadata?.created || Date.now(),
        });
      } catch {
        erroredFiles.set(id, true);
      }
    }),
  );

  return { loadedFiles, erroredFiles };
}
