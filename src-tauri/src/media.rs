//! The bridge to the FilmCraft video editor (its WebAssembly build runs in a
//! frame of the U-file page).
//!
//! FilmCraft reads a video through the asset protocol, or through
//! `read_media` when that fails. What it saves (an export, a project) would
//! be a browser download, which the Android WebView drops, so the page hands
//! those bytes to `save_download` instead.

use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use tauri::AppHandle;
#[cfg(not(target_os = "android"))]
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

/// Save a file FilmCraft wrote. The body is the raw bytes; the `x-name`
/// header carries the URI-encoded file name. Videos go to `Movies/U-file`,
/// everything else to `Download/U-file`, never replacing a file. Returns the
/// path written.
#[tauri::command]
pub async fn save_download(
    app: AppHandle,
    request: tauri::ipc::Request<'_>,
) -> Result<String, String> {
    let tauri::ipc::InvokeBody::Raw(bytes) = request.body() else {
        return Err("저장할 내용이 없습니다 / nothing to save".into());
    };
    let name = request
        .headers()
        .get("x-name")
        .and_then(|value| value.to_str().ok())
        .map(percent_decode)
        .map(|name| file_name_only(&name))
        .filter(|name| !name.is_empty())
        .unwrap_or_else(|| "U-file export".into());
    let folder = save_folder(&app, Path::new(&name))?;
    let bytes = bytes.clone();
    tauri::async_runtime::spawn_blocking(move || write_new(&folder, &name, &bytes))
        .await
        .map_err(|e| format!("작업 스레드 오류 / worker thread failed: {e}"))?
}

#[cfg(target_os = "android")]
fn save_folder(_app: &AppHandle, name: &Path) -> Result<PathBuf, String> {
    let base = if is_video(name) { "Movies" } else { "Download" };
    Ok(Path::new(crate::planner::ANDROID_STORAGE)
        .join(base)
        .join("U-file"))
}

#[cfg(not(target_os = "android"))]
fn save_folder(app: &AppHandle, _name: &Path) -> Result<PathBuf, String> {
    app.path()
        .download_dir()
        .map(|dir| dir.join("U-file"))
        .map_err(|e| format!("다운로드 폴더를 찾을 수 없습니다 / no downloads folder: {e}"))
}

fn write_new(folder: &Path, name: &str, bytes: &[u8]) -> Result<String, String> {
    fs::create_dir_all(folder)
        .map_err(|e| format!("저장 폴더를 만들 수 없습니다 / cannot create the folder: {e}"))?;
    let mut target = folder.join(name);
    for _ in 0..100 {
        match fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&target)
        {
            Ok(mut file) => {
                file.write_all(bytes)
                    .and_then(|()| file.sync_all())
                    .map_err(|e| format!("저장하지 못했습니다 / could not save: {e}"))?;
                return Ok(target.display().to_string());
            }
            Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => {
                target = crate::planner::safe_destination(target).0;
            }
            Err(error) => return Err(format!("저장하지 못했습니다 / could not save: {error}")),
        }
    }
    Err("저장할 이름을 찾지 못했습니다 / no free file name".into())
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

/// Undo `encodeURIComponent` (headers are ASCII; file names are Korean).
fn percent_decode(text: &str) -> String {
    let bytes = text.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut at = 0;
    while at < bytes.len() {
        let hex = |offset: usize| {
            bytes
                .get(at + offset)
                .and_then(|byte| (*byte as char).to_digit(16))
        };
        match (bytes[at], hex(1), hex(2)) {
            (b'%', Some(high), Some(low)) => {
                out.push((high * 16 + low) as u8);
                at += 3;
            }
            (byte, _, _) => {
                out.push(byte);
                at += 1;
            }
        }
    }
    String::from_utf8_lossy(&out).into_owned()
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
    fn saved_names_are_decoded_and_kept_inside_the_folder() {
        assert_eq!(percent_decode("%EC%98%81%EC%83%81.mp4"), "영상.mp4");
        assert_eq!(percent_decode("a%2"), "a%2");
        assert_eq!(file_name_only("../../etc/passwd"), "passwd");
        assert_eq!(file_name_only("..\\x.mp4"), "x.mp4");
        assert_eq!(file_name_only(".hidden"), "hidden");
    }

    #[test]
    fn saving_never_replaces_a_file() {
        let base = Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("target")
            .join("test-tmp");
        fs::create_dir_all(&base).expect("base");
        let dir = tempfile::Builder::new().tempdir_in(base).expect("dir");
        let first = write_new(dir.path(), "cut.mp4", b"one").expect("first");
        let second = write_new(dir.path(), "cut.mp4", b"two").expect("second");
        assert_ne!(first, second);
        assert_eq!(fs::read(&first).unwrap(), b"one");
        assert_eq!(fs::read(&second).unwrap(), b"two");
    }
}
