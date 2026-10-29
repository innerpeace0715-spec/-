import { ask } from '@tauri-apps/plugin-dialog';

/** The platform the app was built for, set by lib.rs before the page runs. */
const PLATFORM = (window as unknown as { __UFILE_PLATFORM__?: string }).__UFILE_PLATFORM__;
/** The Galaxy Tab build: storage permission, no self-update, deletions go to the U-file trash. */
export const IS_ANDROID = PLATFORM ? PLATFORM === 'android' : /Android/i.test(navigator.userAgent);
/** The iPad build. Its WebView may report a Mac, so the build's own platform decides. */
export const IS_IOS = PLATFORM ? PLATFORM === 'ios' : /iPad|iPhone|iPod/.test(navigator.userAgent);
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
