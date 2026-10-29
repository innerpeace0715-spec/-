import { invoke } from '@tauri-apps/api/core';

/** Bytes per save_chunk call (sent as base64, so about 1.4 MB of text). */
const CHUNK = 1 << 20;

function base64(bytes: Uint8Array): string {
  // String.fromCharCode takes a limited number of arguments, so go in slices.
  let binary = '';
  for (let at = 0; at < bytes.length; at += 0x8000) {
    binary += String.fromCharCode(...bytes.subarray(at, at + 0x8000));
  }
  return btoa(binary);
}

/**
 * Save `bytes` as `name` where U-file keeps files (Movies/U-file for videos,
 * Download/U-file otherwise; Documents/U-file on the iPad) and return the
 * path. The Android WebView cannot send binary bodies to Rust, so the file
 * travels as base64 pieces.
 */
export async function saveBytes(name: string, bytes: Uint8Array): Promise<string> {
  const token = await invoke<string>('save_begin', { name });
  try {
    for (let at = 0; at < bytes.length; at += CHUNK) {
      await invoke('save_chunk', { token, data: base64(bytes.subarray(at, at + CHUNK)) });
    }
    return await invoke<string>('save_finish', { token });
  } catch (error) {
    await invoke('save_abort', { token }).catch(() => undefined);
    throw error;
  }
}
