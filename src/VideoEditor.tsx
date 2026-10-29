import { useEffect, useRef, useState } from 'react';
import { convertFileSrc, invoke } from '@tauri-apps/api/core';
import { ArrowLeft, CheckCircle2, Clapperboard, RefreshCw } from 'lucide-react';
import { IS_MOBILE, confirmBox } from './platform';
import { saveBytes } from './save';
import { basename, friendlyPath } from './utils';

/** What FilmCraft's web build puts on its window (docs/web.md in vendor/filmcraft). */
type ImportResult = { items?: unknown[]; errors?: unknown[] };
type FilmCraft = {
  importUrl(url: string, name?: string): Promise<ImportResult>;
  importFiles(files: File[]): Promise<ImportResult>;
  execute(command: string, params?: Record<string, unknown>): Promise<unknown>;
};
type FilmCraftWindow = Window & typeof globalThis & {
  filmcraft?: FilmCraft;
  filmcraftLoad?: { readyMs?: number; error?: string; fatal?: string };
};

/** FilmCraft starts with an empty project and without reopening an old one. */
const EDITOR_URL = 'filmcraft/index.html?empty&norecover&fresh';

/**
 * How FilmCraft draws, tried in order: its WebGPU compositor, WebGL2 with the
 * frames composited on the CPU, then the CPU alone. A tablet WebView can run
 * out of GPU memory (seen on the iPad simulator); the editor then reopens in
 * the next mode instead of staying dead.
 */
const RENDER_MODES = ['', '&webgl', '&cpu'];

/** FilmCraft stopped (a Rust panic or out of memory); it answers nothing after that. */
class EditorCrashed extends Error {}

/** Rejects with EditorCrashed as soon as FilmCraft reports a crash. */
function watchForCrash(win: FilmCraftWindow) {
  let timer = 0;
  const promise = new Promise<never>((_, reject) => {
    timer = window.setInterval(() => {
      const fatal = win.filmcraftLoad?.fatal;
      if (fatal) {
        window.clearInterval(timer);
        reject(new EditorCrashed(fatal));
      }
    }, 500);
  });
  // Only ever awaited inside a race; a late crash must not become an unhandled rejection.
  promise.catch(() => undefined);
  return { promise, stop: () => window.clearInterval(timer) };
}

/** What happened in the editor, as a `ufile-editor` window event (read by the self-test). */
export type EditorEvent = { phase: 'ready'; mode: string } | { phase: 'retry'; mode: string; reason: string } | { phase: 'error'; message: string } | { phase: 'saved'; path: string } | { phase: 'save-error'; message: string };

function report(detail: EditorEvent) {
  window.dispatchEvent(new CustomEvent<EditorEvent>('ufile-editor', { detail }));
}

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

async function whenReady(frame: () => HTMLIFrameElement | null, source: string, cancelled: () => boolean): Promise<FilmCraftWindow> {
  // Compiling the editor's WebAssembly takes a while on a tablet.
  for (let waited = 0; waited < 180_000 && !cancelled(); waited += 200) {
    const element = frame();
    // Until React renders the new frame, the old (possibly crashed) one is still mounted.
    const win = element?.getAttribute('src') === source ? element.contentWindow as FilmCraftWindow | null : null;
    const load = win?.filmcraftLoad;
    // A failed start (e.g. a GPU limit the WebView cannot meet) gets the next mode too.
    if (load?.fatal ?? load?.error) throw new EditorCrashed(load.fatal ?? load.error);
    if (win?.filmcraft && load?.readyMs) return win;
    await sleep(200);
  }
  throw new Error('timeout');
}

/** Item id of the first imported clip, whether FilmCraft reports ids or objects. */
function firstItem(result: ImportResult): unknown {
  const first = result.items?.[0];
  if (first && typeof first === 'object' && 'id' in first) return (first as { id: unknown }).id;
  return first;
}

/**
 * Saving in FilmCraft clicks a hidden download link, which the Android and
 * iPad WebViews ignore. Catch those clicks and write the file to the tablet.
 */
function captureDownloads(win: FilmCraftWindow, onSaved: (path: string) => void, onError: (message: string) => void) {
  const anchor = win.HTMLAnchorElement.prototype;
  const click = anchor.click;
  anchor.click = function (this: HTMLAnchorElement) {
    if (!this.download || !this.href.startsWith('blob:')) return click.call(this);
    const name = this.download;
    void (async () => {
      try {
        const bytes = new Uint8Array(await (await fetch(this.href)).arrayBuffer());
        onSaved(await saveBytes(name, bytes));
      } catch (error) {
        onError(String(error));
      }
    })();
  };
}

export default function VideoEditor({ path, lang, onClose }: { path: string; lang: 'ko' | 'en'; onClose: () => void }) {
  const frame = useRef<HTMLIFrameElement>(null);
  const [status, setStatus] = useState(lang === 'ko' ? '편집기를 여는 중…' : 'Starting the editor…');
  const [error, setError] = useState('');
  const [saved, setSaved] = useState<string[]>([]);
  // Set once the editor is known to be bundled, so a build without it never frames another page.
  const [source, setSource] = useState<string | null>(null);
  const name = basename(path);

  /** Load FilmCraft in the current frame and put the video on a new sequence. */
  async function openVideo(source: string, cancelled: () => boolean) {
    const win = await whenReady(() => frame.current, source, cancelled);
    if (cancelled()) return;
    if (IS_MOBILE) {
      captureDownloads(win, (file) => {
        setSaved((list) => [...list, file]);
        report({ phase: 'saved', path: file });
      }, (message) => {
        setError(message);
        report({ phase: 'save-error', message });
      });
    }
    setStatus(lang === 'ko' ? '영상을 불러오는 중…' : 'Loading the video…');
    const filmcraft = win.filmcraft as FilmCraft;
    const crash = watchForCrash(win);
    try {
      let result: ImportResult;
      try {
        result = await Promise.race([crash.promise, filmcraft.importUrl(convertFileSrc(path), name)]);
      } catch (failure) {
        if (failure instanceof EditorCrashed) throw failure;
        // The asset protocol could not serve it: hand the bytes over directly.
        const bytes = await invoke<ArrayBuffer>('read_media', { path });
        result = await Promise.race([crash.promise, filmcraft.importFiles([new win.File([bytes], name)])]);
      }
      if (result.errors?.length) throw new Error(result.errors.map(String).join('; '));
      const item = firstItem(result);
      if (item !== undefined) {
        // A sequence made from the clip, so editing can start on the timeline.
        await Promise.race([crash.promise, filmcraft.execute('file.newSequence', { name: name.replace(/\.[^.]+$/, ''), fromItem: item }).catch(() => undefined)]);
      }
    } finally {
      crash.stop();
    }
  }

  useEffect(() => {
    let cancelled = false;
    void (async () => {
      try {
        // A build without scripts/build-filmcraft.sh has no editor to load.
        // (Look at the page itself: a missing file may be answered with U-file's own index.html.)
        const bundled = await fetch(EDITOR_URL.split('?')[0]).then(async (response) => response.ok && (await response.text()).includes('filmcraft_canvas'), () => false);
        if (!bundled) throw new Error(lang === 'ko' ? '이 빌드에는 FilmCraft 편집기가 포함되지 않았습니다.' : 'This build does not include the FilmCraft editor.');
        let opened = '';
        for (let mode = 0; !opened && !cancelled; mode += 1) {
          // A fresh frame per attempt, so a crashed editor's window is never read again.
          const source = `${EDITOR_URL}${RENDER_MODES[mode]}`;
          setSource(source);
          try {
            await openVideo(source, () => cancelled);
            opened = RENDER_MODES[mode].replace('&', '') || 'webgpu';
          } catch (failure) {
            if (!(failure instanceof EditorCrashed) || mode + 1 >= RENDER_MODES.length) throw failure;
            report({ phase: 'retry', mode: RENDER_MODES[mode + 1].replace('&', ''), reason: failure.message.split('\n')[0] });
            setStatus(lang === 'ko' ? '편집기를 다른 방식으로 다시 여는 중…' : 'Reopening the editor in a safer mode…');
          }
        }
        if (cancelled) return;
        setStatus('');
        report({ phase: 'ready', mode: opened });
      } catch (failure) {
        if (cancelled) return;
        setStatus('');
        const message = failure instanceof Error ? failure.message : String(failure);
        report({ phase: 'error', message });
        setError(message === 'timeout'
          ? (lang === 'ko' ? '편집기가 시작되지 않았습니다. 앱을 다시 열어 보세요.' : 'The editor did not start. Try reopening the app.')
          : message);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [path]);

  async function close() {
    if (await confirmBox(lang === 'ko'
      ? '편집 화면을 닫을까요? 저장하지 않은 편집 내용은 사라집니다.\n(편집기의 내보내기·저장으로 만든 파일은 이미 기기에 저장되어 있습니다.)'
      : 'Close the editor? Unsaved edits are lost.\n(Files you exported or saved in the editor are already on the device.)', lang)) onClose();
  }

  return (
    <div className="editor-screen" role="dialog" aria-modal="true" aria-label={lang === 'ko' ? '영상 수정' : 'Edit video'}>
      <header className="editor-bar">
        <button className="secondary-action" onClick={() => void close()}><ArrowLeft size={20} /> U-file</button>
        <div className="editor-title">
          <Clapperboard size={20} aria-hidden="true" />
          <b>{name}</b>
          <span className="muted">{friendlyPath(path, lang)}</span>
        </div>
        {status && <span className="editor-status"><RefreshCw size={16} className="spin" /> {status}</span>}
      </header>
      {error && <p className="notice editor-message">{lang === 'ko' ? '편집기 오류: ' : 'Editor error: '}{error}</p>}
      {saved.length > 0 && <p className="inline-message editor-message"><CheckCircle2 size={16} /> {lang === 'ko' ? '기기에 저장했습니다: ' : 'Saved to the device: '}{saved.map((file) => friendlyPath(file, lang)).join(', ')}</p>}
      {source ? <iframe key={source} ref={frame} className="editor-frame" src={source} title="FilmCraft" allow="fullscreen; autoplay" /> : <div className="editor-frame" />}
    </div>
  );
}
