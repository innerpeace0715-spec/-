import { Channel, invoke } from '@tauri-apps/api/core';
import { IS_IOS } from './platform';
import type { EditorEvent } from './VideoEditor';

/**
 * End-to-end check of the installed app, run by CI on an Android emulator and
 * an iPad simulator (.github/workflows/android.yml). It starts only when the
 * test folder holds a RUN_SELFTEST file, works only inside that folder, and
 * writes its report as U-file-selftest.json to where U-file saves files
 * (Download/U-file on Android, Documents/U-file on the iPad).
 *
 * The test folder is Download/ufile-selftest on Android and
 * Documents/ufile-selftest on the iPad.
 */
type StorageInfo = { root: string; trash: string };
let storage: StorageInfo | null = null;

async function dirs() {
  storage ??= await invoke<StorageInfo>('storage_info');
  const base = IS_IOS ? `${storage.root}/ufile-selftest` : `${storage.root}/Download/ufile-selftest`;
  return { base, data: `${base}/data`, trash: storage.trash };
}

type Listing = { path: string; folders: string[]; files: { name: string; sizeBytes: number }[] };
type Action = { status: string; destinationPath: string };
type Plan = { planId?: string; runId?: string; actions: Action[]; errors: string[] };
type Step = { name: string; ok: boolean; detail: string };

const listing = (path: string) => invoke<Listing>('list_folders', { path });
const progress = () => new Channel<unknown>();

function editorEvent(phases: EditorEvent['phase'][], timeoutMs: number): Promise<EditorEvent> {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      window.removeEventListener('ufile-editor', listener);
      reject(new Error(`no ${phases.join('/')} within ${timeoutMs / 1000}s`));
    }, timeoutMs);
    function listener(event: Event) {
      const detail = (event as CustomEvent<EditorEvent>).detail;
      if (!phases.includes(detail.phase)) return;
      clearTimeout(timer);
      window.removeEventListener('ufile-editor', listener);
      resolve(detail);
    }
    window.addEventListener('ufile-editor', listener);
  });
}

/** One line in progress.log (CI prints it; a no-op outside a self-test). */
function log(line: string) {
  void invoke('selftest_log', { line }).catch(() => undefined);
}

export async function selfTestRequested(): Promise<boolean> {
  log(`page loaded · ios=${IS_IOS} · ${navigator.userAgent}`);
  try {
    return (await listing((await dirs()).base)).files.some((file) => file.name === 'RUN_SELFTEST');
  } catch {
    return false;
  }
}

export async function runSelfTest(openEditor: (path: string) => void): Promise<void> {
  const { data: DATA, trash: TRASH } = await dirs();
  const steps: Step[] = [];
  async function step(name: string, check: () => Promise<string>) {
    log(`start: ${name}`);
    try {
      steps.push({ name, ok: true, detail: await check() });
    } catch (error) {
      steps.push({ name, ok: false, detail: error instanceof Error ? error.message : String(error) });
    }
    const last = steps[steps.length - 1];
    log(`${last.ok ? 'ok' : 'FAIL'}: ${name} · ${last.detail}`);
  }
  window.addEventListener('error', (event) => log(`page error: ${event.message}`));
  window.addEventListener('unhandledrejection', (event) => log(`unhandled: ${String(event.reason)}`));
  window.addEventListener('ufile-editor', (event) => log(`editor: ${JSON.stringify((event as CustomEvent).detail)}`));
  const expect = (condition: boolean, message: string) => {
    if (!condition) throw new Error(message);
  };

  const before = await listing(DATA).catch(() => null);
  let plan: Plan | null = null;

  await step('read the test folder', async () => {
    expect(before !== null && before.files.length >= 4, `files: ${before?.files.map((file) => file.name).join(', ')}`);
    return `${before?.files.length} files`;
  });

  await step('no network access', async () => {
    const reached = await fetch('https://www.google.com/generate_204', { mode: 'no-cors' }).then(() => true, () => false);
    expect(!reached, 'an outside address answered');
    return 'outside requests are blocked';
  });

  await step('preview the organization', async () => {
    plan = await invoke<Plan>('plan_organization', {
      request: { rootPath: DATA, includeSubfolders: false, language: 'ko', basis: 'type', mode: 'safe' },
      onProgress: progress(),
    });
    expect(plan.actions.length >= 4, `${plan.actions.length} actions, errors: ${plan.errors.join('; ')}`);
    expect(plan.actions.every((action) => !action.destinationPath.includes('\\')), 'a destination has a backslash');
    return plan.actions.map((action) => action.destinationPath.slice(DATA.length + 1)).join(', ');
  });

  await step('move the files', async () => {
    expect(plan !== null, 'no plan');
    const done = await invoke<Plan>('execute_organization', { planId: plan!.planId, excluded: [], onProgress: progress() });
    plan = done;
    const moved = done.actions.filter((action) => action.status === 'executed').length;
    expect(moved >= 4, `${moved} moved`);
    const after = await listing(DATA);
    expect(after.folders.length > 0, 'no category folders');
    return `${moved} moved into ${after.folders.join(', ')}`;
  });

  await step('undo the move', async () => {
    expect(plan?.runId !== undefined, 'no run id');
    const undone = await invoke<Plan>('undo_organization', { runId: plan!.runId, only: null });
    const left = undone.actions.filter((action) => action.status === 'executed').length;
    const after = await listing(DATA);
    expect(left === 0 && after.files.length === before?.files.length, `${left} still moved, ${after.files.length} files back`);
    return `${after.files.length} files back in place`;
  });

  let copy = '';
  await step('find duplicates', async () => {
    const result = await invoke<{ items: { filePaths: string[] }[] }>('find_duplicates', { rootPath: DATA, includeSubfolders: false, onProgress: progress() });
    expect(result.items.length === 1 && result.items[0].filePaths.length === 2, JSON.stringify(result.items));
    copy = result.items[0].filePaths[1];
    return copy;
  });

  await step('send a duplicate to the U-file trash', async () => {
    const outcome = await invoke<{ recycled: string[]; skipped: { reason: string }[] }>('recycle_files', { paths: [copy] });
    expect(outcome.recycled.length === 1, JSON.stringify(outcome.skipped));
    const trash = await listing(TRASH);
    expect(trash.folders.length > 0, 'trash folder is empty');
    return `trash: ${trash.folders.join(', ')}`;
  });

  await step('open the video in FilmCraft', async () => {
    const video = before?.files.find((file) => file.name.endsWith('.mp4'));
    expect(video !== undefined, 'no test video');
    const ready = editorEvent(['ready', 'error'], 10 * 60_000);
    openEditor(`${DATA}/${video!.name}`);
    const watch = setInterval(() => {
      const frame = document.querySelector<HTMLIFrameElement>('.editor-frame');
      const inner = frame?.contentWindow as { filmcraftLoad?: unknown; document?: Document } | null;
      const status = document.querySelector('.editor-status')?.textContent ?? '';
      const loading = inner?.document?.getElementById('status')?.textContent ?? '';
      log(`editor waiting · status="${status}" · load=${JSON.stringify(inner?.filmcraftLoad ?? null)} · page="${loading}"`);
    }, 30_000);
    const event = await ready.finally(() => clearInterval(watch));
    expect(event.phase === 'ready', event.phase === 'error' ? event.message : event.phase);
    const frame = document.querySelector<HTMLIFrameElement>('.editor-frame');
    const info = (frame?.contentWindow as { filmcraft?: { info(): unknown } } | null)?.filmcraft?.info();
    return `editor ready: ${JSON.stringify(info)}`;
  });

  await step('export from FilmCraft and save to the tablet', async () => {
    const frame = document.querySelector<HTMLIFrameElement>('.editor-frame');
    const filmcraft = (frame?.contentWindow as { filmcraft?: { execute(command: string, params: unknown): Promise<unknown> } } | null)?.filmcraft;
    expect(filmcraft !== undefined, 'editor not open');
    const saved = editorEvent(['saved', 'save-error'], 15 * 60_000);
    await filmcraft!.execute('file.exportMedia', { path: '/exports/selftest.mp4', format: 'h264' });
    const event = await saved;
    expect(event.phase === 'saved', event.phase === 'save-error' ? event.message : event.phase);
    const path = event.phase === 'saved' ? event.path : '';
    const folder = await listing(path.slice(0, path.lastIndexOf('/')));
    const file = folder.files.find((entry) => path.endsWith(`/${entry.name}`));
    expect(file !== undefined && file.sizeBytes > 1000, `saved file missing or empty: ${path}`);
    return `${path} (${file!.sizeBytes} bytes)`;
  });

  log('writing the report');
  const report = { ok: steps.every((entry) => entry.ok), userAgent: navigator.userAgent, steps, finishedAt: new Date().toISOString() };
  const bytes = new TextEncoder().encode(JSON.stringify(report, null, 2));
  await invoke('save_download', bytes, { headers: { 'x-name': encodeURIComponent('U-file-selftest.json') } });
}
