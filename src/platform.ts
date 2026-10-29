import { ask } from '@tauri-apps/plugin-dialog';

/** The Galaxy Tab build: storage permission, no self-update, deletions go to the U-file trash. */
export const IS_ANDROID = /Android/i.test(navigator.userAgent);
/** The iPad build. iPadOS WebViews report a Mac, so a touch screen tells them apart. */
export const IS_IOS = /iPad|iPhone|iPod/.test(navigator.userAgent) || (/Macintosh/.test(navigator.userAgent) && navigator.maxTouchPoints > 1);
/**
 * A tablet build (Galaxy Tab or iPad): no system folder picker, no
 * self-update, and nothing is ever sent off the device.
 */
export const IS_MOBILE = IS_ANDROID || IS_IOS;

type AndroidBridge = { hasAllFilesAccess(): boolean; openAllFilesAccessSettings(): void };
/** Added by MainActivity.kt; missing on the desktop and the iPad. */
export function androidBridge(): AndroidBridge | undefined {
  return (window as unknown as { FileMoaAndroid?: AndroidBridge }).FileMoaAndroid;
}

/** Tablet WebViews have no reliable `confirm()`, so ask through the dialog plugin there. */
export async function confirmBox(message: string, lang: 'ko' | 'en'): Promise<boolean> {
  if (!IS_MOBILE) return confirm(message);
  return ask(message, { title: 'U-file', kind: 'warning', okLabel: lang === 'ko' ? '확인' : 'OK', cancelLabel: lang === 'ko' ? '취소' : 'Cancel' });
}
