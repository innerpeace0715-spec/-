import { ask } from '@tauri-apps/plugin-dialog';

/** The Galaxy Tab build: no self-update, no system folder picker, deletions go to the U-file trash. */
export const IS_ANDROID = /Android/i.test(navigator.userAgent);
type AndroidBridge = { hasAllFilesAccess(): boolean; openAllFilesAccessSettings(): void };
/** Added by MainActivity.kt; missing on the desktop. */
export function androidBridge(): AndroidBridge | undefined {
  return (window as unknown as { FileMoaAndroid?: AndroidBridge }).FileMoaAndroid;
}

/** Android's WebView has no reliable `confirm()`, so ask through the dialog plugin there. */
export async function confirmBox(message: string, lang: 'ko' | 'en'): Promise<boolean> {
  if (!IS_ANDROID) return confirm(message);
  return ask(message, { title: 'U-file', kind: 'warning', okLabel: lang === 'ko' ? '확인' : 'OK', cancelLabel: lang === 'ko' ? '취소' : 'Cancel' });
}
