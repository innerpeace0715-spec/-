import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { invoke } from '@tauri-apps/api/core';
import {
  ArrowLeft,
  ArrowUp,
  Clapperboard,
  ExternalLink,
  File as FileIcon,
  FileArchive,
  FileText,
  Film,
  Folder,
  FolderOpen,
  FolderTree,
  HardDrive,
  Image as ImageIcon,
  Music,
  RefreshCw,
  Search,
  type LucideIcon,
} from 'lucide-react';
import { IS_MOBILE } from './platform';
import { formatBytes, formatDay, friendlyPath, isVideo, separatorOf } from './utils';

type Entry = { name: string; sizeBytes: number; modifiedSecs?: number | null };
type Listing = { path: string; parent: string | null; folders: string[]; files: Entry[] };
export type Place = { id: string; path: string; label: string; icon: LucideIcon };
type Sort = 'name' | 'date' | 'size';

/** How often the open folder is read again while the window is showing. */
const REFRESH_MS = 5_000;
const LAST_FOLDER = 'ufile-last-folder';

const KIND_ICONS: [RegExp, LucideIcon][] = [
  [/\.(jpe?g|png|gif|webp|heic|heif|bmp|tiff?|svg|raw|cr2|nef|dng)$/i, ImageIcon],
  [/\.(mp4|m4v|mov|3gp|mkv|webm|avi|mxf|ts|mts|m2ts|wmv|flv)$/i, Film],
  [/\.(mp3|m4a|aac|flac|wav|ogg|opus|wma)$/i, Music],
  [/\.(zip|7z|rar|tar|gz|bz2|xz|zst)$/i, FileArchive],
  [/\.(pdf|txt|md|docx?|xlsx?|pptx?|hwpx?|csv|rtf|odt|epub)$/i, FileText],
];

function kindIcon(name: string): LucideIcon {
  return KIND_ICONS.find(([pattern]) => pattern.test(name))?.[1] ?? FileIcon;
}

function readLast(): string | null {
  try {
    return localStorage.getItem(LAST_FOLDER);
  } catch {
    return null;
  }
}

function writeLast(folder: string) {
  try {
    localStorage.setItem(LAST_FOLDER, folder);
  } catch {
    // only a convenience
  }
}

/** Clickable pieces of `path`: `C:\` › `Users` › `me`, or `/` › `home` › `me`. */
function crumbs(path: string): { label: string; path: string }[] {
  const sep = separatorOf(path);
  const parts = path.split(sep).filter((part, at) => part || at === 0);
  return parts.map((part, at) => {
    const joined = parts.slice(0, at + 1).join(sep);
    const target = at === 0 ? (part ? `${part}${sep}` : sep) : joined;
    return { label: part || sep, path: target };
  });
}

/**
 * The file browser U-file opens with: the last folder (Downloads the first
 * time), read again every few seconds and whenever the window comes back, so
 * new files show up by themselves. The folder on screen is what the
 * organize and manage tabs work on.
 */
export default function FileBrowser({ lang, places, busy, refreshKey, onFolder, onOrganize, onEdit }: {
  lang: 'ko' | 'en';
  places: Place[];
  busy: boolean;
  /** Changes when U-file itself moved files (organize, undo, trash). */
  refreshKey: number;
  onFolder: (folder: string) => void;
  onOrganize: (folder: string) => void;
  onEdit: (file: string) => void;
}) {
  const ko = lang === 'ko';
  const [listing, setListing] = useState<Listing | null>(null);
  const [drives, setDrives] = useState<string[]>([]);
  const [error, setError] = useState('');
  const [filter, setFilter] = useState('');
  const [selected, setSelected] = useState<string | null>(null);
  const [sort, setSort] = useState<Sort>('name');
  const history = useRef<string[]>([]);
  const current = useRef<string | null>(null);

  const load = useCallback(async (target: string | null, quiet = false) => {
    try {
      const next = await invoke<Listing>('list_folders', { path: target });
      setListing(next);
      setError('');
      if (next.path !== current.current) {
        current.current = next.path;
        setSelected(null);
        setFilter('');
        writeLast(next.path);
        onFolder(next.path);
      }
    } catch (failure) {
      // A folder that went away while it was open: say so, keep the old list.
      if (!quiet) setError(String(failure));
      else if (target === current.current) setError(String(failure));
    }
  }, [onFolder]);

  const go = useCallback((target: string) => {
    if (current.current && current.current !== target) history.current.push(current.current);
    void load(target);
  }, [load]);

  // Start where the user left off, else Downloads, else the home folder.
  useEffect(() => {
    void invoke<string[]>('list_drives').then(setDrives).catch(() => undefined);
    const downloads = places.find((place) => place.id === 'downloads')?.path ?? null;
    void (async () => {
      for (const candidate of [readLast(), downloads, null]) {
        try {
          const next = await invoke<Listing>('list_folders', { path: candidate });
          current.current = next.path;
          setListing(next);
          writeLast(next.path);
          onFolder(next.path);
          return;
        } catch {
          // try the next place
        }
      }
    })();
    // Only once: places arrive with the first render on every platform.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [places.length > 0]);

  // New files appear by themselves: on return to the window and every few seconds.
  useEffect(() => {
    const again = () => {
      if (current.current && document.visibilityState === 'visible') void load(current.current, true);
    };
    const timer = window.setInterval(again, REFRESH_MS);
    window.addEventListener('focus', again);
    document.addEventListener('visibilitychange', again);
    return () => {
      window.clearInterval(timer);
      window.removeEventListener('focus', again);
      document.removeEventListener('visibilitychange', again);
    };
  }, [load]);

  useEffect(() => {
    if (refreshKey && current.current) void load(current.current, true);
  }, [refreshKey, load]);

  const rows = useMemo(() => {
    if (!listing) return [];
    const needle = filter.trim().toLowerCase();
    const match = (name: string) => !needle || name.toLowerCase().includes(needle);
    const files = listing.files.filter((file) => match(file.name));
    files.sort((a, b) => sort === 'size' ? b.sizeBytes - a.sizeBytes
      : sort === 'date' ? (b.modifiedSecs ?? 0) - (a.modifiedSecs ?? 0)
      : a.name.localeCompare(b.name, lang));
    return [
      ...listing.folders.filter(match).map((name) => ({ name, folder: true as const })),
      ...files.map((file) => ({ ...file, folder: false as const })),
    ];
  }, [listing, filter, sort, lang]);

  const sep = listing ? separatorOf(listing.path) : '/';
  const full = (name: string) => listing ? `${listing.path.replace(/[\\/]$/, '')}${sep}${name}` : name;

  function back() {
    const previous = history.current.pop();
    if (previous) void load(previous);
  }

  function openFile(name: string, reveal = false) {
    const path = full(name);
    if (!reveal && isVideo(name) && IS_MOBILE) {
      onEdit(path);
      return;
    }
    void invoke('open_path', { path, reveal }).catch((failure) => setError(String(failure)));
  }

  const chosen = rows.find((row) => !row.folder && row.name === selected);
  const sortButton = (key: Sort, label: string) => <button className={`sort-button ${sort === key ? 'active' : ''}`} onClick={() => setSort(key)} aria-pressed={sort === key}>{label}</button>;

  return (
    <section className="files">
      <aside className="files-places" aria-label={ko ? '위치' : 'Places'}>
        {places.map(({ id, path, label, icon: Icon }) => <button key={`${id}-${path}`} className={listing?.path === path ? 'active' : ''} onClick={() => go(path)} title={path}><Icon size={17} aria-hidden="true" /><span>{label}</span></button>)}
        {drives.length > 0 && <p className="files-places-label">{ko ? '드라이브' : 'Drives'}</p>}
        {drives.map((drive) => <button key={drive} className={listing?.path === drive ? 'active' : ''} onClick={() => go(drive)}><HardDrive size={17} aria-hidden="true" /><span>{IS_MOBILE ? friendlyPath(drive, lang) : drive}</span></button>)}
      </aside>

      <div className="files-main">
        <div className="files-toolbar">
          <button className="icon-action" onClick={back} disabled={!history.current.length} aria-label={ko ? '뒤로' : 'Back'} title={ko ? '뒤로' : 'Back'}><ArrowLeft size={18} /></button>
          <button className="icon-action" onClick={() => listing?.parent && go(listing.parent)} disabled={!listing?.parent} aria-label={ko ? '상위 폴더' : 'Up'} title={ko ? '상위 폴더' : 'Up'}><ArrowUp size={18} /></button>
          <button className="icon-action" onClick={() => listing && void load(listing.path)} aria-label={ko ? '새로 고침' : 'Refresh'} title={ko ? '새로 고침' : 'Refresh'}><RefreshCw size={18} /></button>
          <nav className="files-crumbs" aria-label={ko ? '현재 위치' : 'Location'}>
            {listing && crumbs(listing.path).map((crumb, at, all) => <span key={crumb.path}>
              {at === all.length - 1
                ? <b aria-current="location">{IS_MOBILE && at === 0 ? friendlyPath(crumb.path, lang) : crumb.label}</b>
                : <button onClick={() => go(crumb.path)}>{IS_MOBILE && at === 0 ? friendlyPath(crumb.path, lang) : crumb.label}</button>}
              {at < all.length - 1 && <span className="crumb-sep" aria-hidden="true">›</span>}
            </span>)}
          </nav>
          <label className="files-search"><Search size={16} aria-hidden="true" /><input value={filter} onChange={(event) => setFilter(event.target.value)} placeholder={ko ? '이 폴더에서 찾기' : 'Filter this folder'} aria-label={ko ? '이 폴더에서 찾기' : 'Filter this folder'} /></label>
          <button className="primary-action files-organize" onClick={() => listing && onOrganize(listing.path)} disabled={busy || !listing} title={ko ? '이 폴더를 정리 미리보기로' : 'Preview organizing this folder'}><FolderTree size={17} /> {ko ? '정리' : 'Organize'}</button>
        </div>

        {error && <p className="notice files-error">{error}</p>}

        <div className="files-head" role="row">
          <span>{sortButton('name', ko ? '이름' : 'Name')}</span>
          <span>{sortButton('date', ko ? '수정한 날짜' : 'Modified')}</span>
          <span>{sortButton('size', ko ? '크기' : 'Size')}</span>
        </div>
        <div className="files-list" role="grid" aria-label={ko ? '파일 목록' : 'Files'}>
          {rows.map((row) => {
            const Icon = row.folder ? Folder : kindIcon(row.name);
            return <div
              key={`${row.folder ? 'd' : 'f'}-${row.name}`}
              role="row"
              tabIndex={0}
              className={`files-row ${!row.folder && selected === row.name ? 'selected' : ''} ${row.folder ? 'is-folder' : ''}`}
              onClick={() => (row.folder ? go(full(row.name)) : setSelected(row.name))}
              onDoubleClick={() => !row.folder && openFile(row.name)}
              onKeyDown={(event) => {
                if (event.key !== 'Enter') return;
                if (row.folder) go(full(row.name)); else openFile(row.name);
              }}
            >
              <span className="files-name"><Icon size={18} aria-hidden="true" className={row.folder ? 'folder-icon' : ''} /><span>{row.name}</span>
                {!row.folder && isVideo(row.name) && <button className="edit-chip" onClick={(event) => { event.stopPropagation(); onEdit(full(row.name)); }} disabled={busy} title={ko ? 'FilmCraft로 수정' : 'Edit in FilmCraft'}><Clapperboard size={14} /> {ko ? '수정' : 'Edit'}</button>}
              </span>
              <span className="muted">{row.folder ? '' : formatDay(row.modifiedSecs ?? 0)}</span>
              <span className="muted">{row.folder ? '' : formatBytes(row.sizeBytes)}</span>
            </div>;
          })}
          {listing && !rows.length && <p className="muted files-empty">{filter ? (ko ? '찾는 이름이 없습니다.' : 'Nothing matches.') : (ko ? '빈 폴더입니다.' : 'This folder is empty.')}</p>}
        </div>

        <footer className="files-status">
          <span>{listing ? (ko ? `폴더 ${listing.folders.length}개 · 파일 ${listing.files.length}개` : `${listing.folders.length} folders · ${listing.files.length} files`) : (ko ? '불러오는 중…' : 'Loading…')}</span>
          {chosen && !IS_MOBILE && <span className="files-actions">
            <b>{chosen.name}</b>
            <button className="icon-action" onClick={() => openFile(chosen.name)} aria-label={ko ? '열기' : 'Open'} title={ko ? '기본 프로그램으로 열기' : 'Open with the default program'}><ExternalLink size={16} /></button>
            <button className="icon-action" onClick={() => openFile(chosen.name, true)} aria-label={ko ? '탐색기에서 보기' : 'Show in folder'} title={ko ? '탐색기에서 보기' : 'Show in folder'}><FolderOpen size={16} /></button>
          </span>}
        </footer>
      </div>
    </section>
  );
}

