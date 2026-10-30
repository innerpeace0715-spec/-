//! The bridge to the FilmCraft video editor (its WebAssembly build runs in a
//! frame of the U-file page).
//!
//! FilmCraft reads a video through the asset protocol, or through
//! `read_media` when that fails. What it saves (an export, a project) would
//! be a browser download, which tablet WebViews drop, so the page hands those
//! bytes over with `save_begin` / `save_chunk` / `save_finish` instead.

use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use tauri::AppHandle;
#[cfg(not(any(target_os = "android", target_os = "ios")))]
use tauri::Manager;

/// Extensions FilmCraft opens as video (MP4/MOV, Matroska/WebM, AVI, MXF, MPEG-TS).
pub const VIDEO_EXTENSIONS: &[&str] = &[
    "mp4", "m4v", "mov", "3gp", "mkv", "webm", "avi", "mxf", "ts", "mts", "m2ts",
];

/// Largest video `read_media` hands over in one piece; it is held in memory twice.
const READ_LIMIT: u64 = 2 << 30;

pub fn is_video(path: &Path) -> bool {
    path.extension()
        .and_then(|extension| extension.to_str())
        .is_some_and(|extension| {
            VIDEO_EXTENSIONS.contains(&extension.to_ascii_lowercase().as_str())
        })
}

/// The whole video at `path`, for when the asset protocol cannot serve it.
#[tauri::command]
pub async fn read_media(path: String) -> Result<tauri::ipc::Response, String> {
    tauri::async_runtime::spawn_blocking(move || {
        let path = PathBuf::from(path);
        if !is_video(&path) || crate::planner::is_protected_path(&path) {
            return Err("영상 파일만 열 수 있습니다 / only video files can be opened".to_string());
        }
        let size = fs::metadata(&path)
            .map_err(|e| format!("파일을 열 수 없습니다 / cannot open the file: {e}"))?
            .len();
        if size > READ_LIMIT {
            return Err("영상이 너무 큽니다(2GB 초과) / the video is larger than 2 GB".to_string());
        }
        fs::read(&path)
            .map(tauri::ipc::Response::new)
            .map_err(|e| format!("파일을 읽을 수 없습니다 / cannot read the file: {e}"))
    })
    .await
    .map_err(|e| format!("작업 스레드 오류 / worker thread failed: {e}"))?
}

/// Files being saved piece by piece, by token. Android's WebView cannot hand
/// binary request bodies to Rust (they arrive as JSON), so the page sends a
/// saved file as base64 chunks: `save_begin`, `save_chunk`…, `save_finish`.
#[derive(Default)]
pub struct Saves(std::sync::Mutex<std::collections::HashMap<String, Partial>>);

pub struct Partial {
    file: fs::File,
    temp: PathBuf,
    target: PathBuf,
}

impl Saves {
    fn lock(&self) -> std::sync::MutexGuard<'_, std::collections::HashMap<String, Partial>> {
        self.0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
    }

    /// Start `name` in `folder`; the bytes go to a hidden part file until the end.
    pub fn begin(&self, folder: &Path, name: &str) -> Result<String, String> {
        let name = file_name_only(name);
        let name = if name.is_empty() {
            "U-file export".to_string()
        } else {
            name
        };
        fs::create_dir_all(folder)
            .map_err(|e| format!("저장 폴더를 만들 수 없습니다 / cannot create the folder: {e}"))?;
        let token = uuid::Uuid::new_v4().to_string();
        let temp = folder.join(format!(".ufile-part-{token}"));
        let file = fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&temp)
            .map_err(|e| format!("저장하지 못했습니다 / could not save: {e}"))?;
        let target = folder.join(name);
        self.lock()
            .insert(token.clone(), Partial { file, temp, target });
        Ok(token)
    }

    pub fn chunk(&self, token: &str, bytes: &[u8]) -> Result<(), String> {
        let mut saves = self.lock();
        let partial = saves
            .get_mut(token)
            .ok_or("저장이 시작되지 않았습니다 / no such save")?;
        partial
            .file
            .write_all(bytes)
            .map_err(|e| format!("저장하지 못했습니다 / could not save: {e}"))
    }

    /// Give the file its name, never replacing one: `name (1).ext` when taken.
    pub fn finish(&self, token: &str) -> Result<PathBuf, String> {
        let partial = self
            .lock()
            .remove(token)
            .ok_or("저장이 시작되지 않았습니다 / no such save")?;
        let Partial { file, temp, target } = partial;
        file.sync_all()
            .map_err(|e| format!("저장하지 못했습니다 / could not save: {e}"))?;
        drop(file);
        crate::planner::move_with_unique_name(&temp, target)
            .map(|(path, _)| path)
            .map_err(|e| {
                let _ = fs::remove_file(&temp);
                format!("저장하지 못했습니다 / could not save: {e}")
            })
    }

    pub fn abort(&self, token: &str) {
        if let Some(partial) = self.lock().remove(token) {
            drop(partial.file);
            let _ = fs::remove_file(&partial.temp);
        }
    }
}

/// Start saving a file FilmCraft wrote. Videos go to `Movies/U-file`,
/// everything else to `Download/U-file` (Documents/U-file on the iPad).
#[tauri::command]
pub fn save_begin(
    app: AppHandle,
    saves: tauri::State<'_, Saves>,
    name: String,
) -> Result<String, String> {
    let folder = save_folder(&app, Path::new(&name))?;
    saves.begin(&folder, &name)
}

/// One base64 piece of the file.
#[tauri::command]
pub fn save_chunk(
    saves: tauri::State<'_, Saves>,
    token: String,
    data: String,
) -> Result<(), String> {
    use base64::Engine;
    let bytes = base64::engine::general_purpose::STANDARD
        .decode(data.as_bytes())
        .map_err(|e| format!("잘못된 데이터 / bad data: {e}"))?;
    saves.chunk(&token, &bytes)
}

/// Finish the save; returns the path written.
#[tauri::command]
pub fn save_finish(saves: tauri::State<'_, Saves>, token: String) -> Result<String, String> {
    saves.finish(&token).map(|path| path.display().to_string())
}

#[tauri::command]
pub fn save_abort(saves: tauri::State<'_, Saves>, token: String) {
    saves.abort(&token);
}

#[cfg(target_os = "android")]
fn save_folder(_app: &AppHandle, name: &Path) -> Result<PathBuf, String> {
    let base = if is_video(name) { "Movies" } else { "Download" };
    Ok(Path::new(crate::planner::ANDROID_STORAGE)
        .join(base)
        .join("U-file"))
}

#[cfg(target_os = "ios")]
fn save_folder(_app: &AppHandle, _name: &Path) -> Result<PathBuf, String> {
    crate::planner::ios_documents()
        .map(|documents| documents.join("U-file"))
        .ok_or_else(|| "문서 폴더를 찾을 수 없습니다 / no Documents folder".into())
}

#[cfg(not(any(target_os = "android", target_os = "ios")))]
fn save_folder(app: &AppHandle, _name: &Path) -> Result<PathBuf, String> {
    app.path()
        .download_dir()
        .map(|dir| dir.join("U-file"))
        .map_err(|e| format!("다운로드 폴더를 찾을 수 없습니다 / no downloads folder: {e}"))
}

/// The last path component, so a name like `../../x` cannot leave the folder.
fn file_name_only(name: &str) -> String {
    name.rsplit(['/', '\\'])
        .next()
        .unwrap_or_default()
        .trim()
        .trim_start_matches('.')
        .to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn videos_are_recognised_by_extension() {
        assert!(is_video(Path::new(
            "/storage/emulated/0/DCIM/Camera/20261029_101500.mp4"
        )));
        assert!(is_video(Path::new("clip.MOV")));
        assert!(!is_video(Path::new("photo.jpg")));
        assert!(!is_video(Path::new("mp4")));
    }

    #[test]
    fn saved_names_stay_inside_the_folder() {
        assert_eq!(file_name_only("../../etc/passwd"), "passwd");
        assert_eq!(file_name_only("..\\x.mp4"), "x.mp4");
        assert_eq!(file_name_only(".hidden"), "hidden");
    }

    #[test]
    fn saving_in_pieces_never_replaces_a_file() {
        let base = Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("target")
            .join("test-tmp");
        fs::create_dir_all(&base).expect("base");
        let dir = tempfile::Builder::new().tempdir_in(base).expect("dir");
        let saves = Saves::default();
        let save = |parts: &[&[u8]]| {
            let token = saves.begin(dir.path(), "cut.mp4").expect("begin");
            for part in parts {
                saves.chunk(&token, part).expect("chunk");
            }
            saves.finish(&token).expect("finish")
        };
        let first = save(&[b"o", b"ne"]);
        let second = save(&[b"two"]);
        assert_eq!(first, dir.path().join("cut.mp4"));
        assert_eq!(second, dir.path().join("cut (1).mp4"));
        assert_eq!(fs::read(&first).unwrap(), b"one");
        assert_eq!(fs::read(&second).unwrap(), b"two");

        let token = saves.begin(dir.path(), "dropped.mp4").expect("begin");
        saves.abort(&token);
        assert!(saves.finish(&token).is_err());
        let left: Vec<_> = fs::read_dir(dir.path())
            .unwrap()
            .filter_map(Result::ok)
            .map(|e| e.file_name())
            .collect();
        assert_eq!(left.len(), 2, "{left:?}");
    }
}
