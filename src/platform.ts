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
/**
 * Every U-file build (Windows too) keeps the user's files on the device: no
 * cloud AI and no self-update. The desktop keeps FileMoa's AI suggestions
 * through Ollama running on the same computer.
 */
export const LOCAL_ONLY = true;
/** AI suggestions: Ollama on this computer only, so the desktop alone has them. */
export const LOCAL_AI = !IS_MOBILE;

type AndroidBridge = { hasAllFilesAccess(): boolean; openAllFilesAccessSettings(): void };
/** Added by MainActivity.kt; missing on the desktop and the iPad. */
export function androidBridge(): AndroidBridge | undefined {
  return (window as unknown as { FileMoaAndroid?: AndroidBridge }).FileMoaAndroid;
}

/**
 * Ask through the dialog plugin: tablet WebViews have no reliable `confirm()`,
 * and on Windows it stopped answering while the editor's frame was open.
 */
export async function confirmBox(message: string, lang: 'ko' | 'en'): Promise<boolean> {
  return ask(message, { title: 'U-file', kind: 'warning', okLabel: lang === 'ko' ? '확인' : 'OK', cancelLabel: lang === 'ko' ? '취소' : 'Cancel' });
}
