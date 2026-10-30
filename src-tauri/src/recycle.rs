//! Explicit, recoverable removal helpers.
//!
//! The UI must pass an explicit list of files. Windows' shell operation is used
//! so the files go to the Recycle Bin rather than being permanently deleted.
//!
//! Windows deletes permanently, without a prompt, when an item cannot be
//! recycled (network and removable drives, files larger than the bin). To keep
//! "Recycle Bin" honest this module (1) refuses drives that have no bin,
//! (2) asks the shell to warn before any permanent delete, and (3) verifies
//! afterwards which items are really gone and reports the rest.
//!
//! Android has no Recycle Bin for files reached by path, so there the items
//! move into a `U-file_휴지통` folder at the top of their storage, from where
//! the Files app can put them back or delete them for good.

use serde::Serialize;
use std::path::Path;

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct RecycleSkip {
    pub path: String,
    pub reason: String,
}

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct RecycleOutcome {
    pub recycled: Vec<String>,
    pub skipped: Vec<RecycleSkip>,
}

/// Only fixed local drives have a Recycle Bin that reliably keeps deleted
/// items. Values are the Win32 `GetDriveType` results.
#[cfg(any(windows, test))]
fn drive_type_blocker(drive_type: u32) -> Option<&'static str> {
    match drive_type {
        3 => None,
        2 => Some("이동식 드라이브는 휴지통이 없어 영구 삭제됩니다 / removable drive: items would be deleted permanently"),
        4 => Some("네트워크 드라이브는 휴지통이 없어 영구 삭제됩니다 / network drive: items would be deleted permanently"),
        5 => Some("광학 드라이브의 항목은 삭제할 수 없습니다 / optical drive"),
        6 => Some("RAM 디스크는 휴지통이 없어 영구 삭제됩니다 / RAM disk: items would be deleted permanently"),
        _ => Some("드라이브 종류를 확인할 수 없어 건너뜀 / drive type could not be determined"),
    }
}

/// Decide, after the shell call, what really happened. `exists` is injected
/// so the logic is testable without touching the file system.
#[cfg(any(windows, test))]
fn settle(
    accepted: Vec<String>,
    mut skipped: Vec<RecycleSkip>,
    aborted: bool,
    result: i32,
    exists: impl Fn(&str) -> bool,
) -> RecycleOutcome {
    let mut recycled = Vec::new();
    for path in accepted {
        if exists(&path) {
            let reason = if aborted {
                "취소되어 삭제되지 않았습니다 / not deleted: the operation was cancelled"
                    .to_string()
            } else if result != 0 {
                format!("휴지통으로 이동하지 못했습니다 (Windows 오류 {result}) / could not be moved to the Recycle Bin")
            } else {
                "휴지통으로 이동하지 못했습니다 / could not be moved to the Recycle Bin".to_string()
            };
            skipped.push(RecycleSkip { path, reason });
        } else {
            recycled.push(path);
        }
    }
    RecycleOutcome { recycled, skipped }
}

#[cfg(windows)]
mod win {
    use std::os::windows::ffi::OsStrExt;
    use std::path::Path;
    use windows_sys::Win32::Storage::FileSystem::{GetDriveTypeW, GetVolumePathNameW};

    pub fn wide(path: &Path) -> Vec<u16> {
        path.as_os_str().encode_wide().chain([0]).collect()
    }

    /// Mount point or drive root that holds `path` (handles mounted folders).
    pub fn volume_root(path: &Path) -> Option<Vec<u16>> {
        let input = wide(path);
        let mut buffer = vec![0_u16; 1024];
        let ok =
            unsafe { GetVolumePathNameW(input.as_ptr(), buffer.as_mut_ptr(), buffer.len() as u32) };
        if ok == 0 {
            return None;
        }
        let length = buffer.iter().position(|&unit| unit == 0)?;
        buffer.truncate(length + 1);
        Some(buffer)
    }

    pub fn drive_type(path: &Path) -> u32 {
        match volume_root(path) {
            Some(root) => unsafe { GetDriveTypeW(root.as_ptr()) },
            None => 0,
        }
    }
}

#[cfg(windows)]
fn recycle_with_owner(
    paths: Vec<String>,
    owner: windows_sys::Win32::Foundation::HWND,
) -> Result<RecycleOutcome, String> {
    use std::ptr::null;
    use windows_sys::Win32::UI::Shell::{
        SHFileOperationW, FOF_ALLOWUNDO, FOF_NOCONFIRMATION, FOF_NOERRORUI, FOF_SILENT,
        FOF_WANTNUKEWARNING, FO_DELETE, SHFILEOPSTRUCTW,
    };

    if paths.is_empty() {
        return Err("휴지통으로 보낼 파일을 하나 이상 선택하세요.".into());
    }
    let mut accepted: Vec<String> = Vec::with_capacity(paths.len());
    let mut skipped = Vec::new();
    let mut from: Vec<u16> = Vec::new();
    for value in paths {
        if accepted.contains(&value) {
            continue;
        }
        let path = Path::new(&value);
        let mut skip = |reason: &str| {
            skipped.push(RecycleSkip {
                path: value.clone(),
                reason: reason.into(),
            });
        };
        if !path.is_absolute() {
            skip("전체 경로가 아니어서 건너뜀 / not an absolute path");
            continue;
        }
        if !path.is_file() && !path.is_dir() {
            skip("항목을 찾을 수 없어 건너뜀 / not found");
            continue;
        }
        if crate::planner::is_protected_path(path) {
            skip("보호된 경로는 휴지통으로 보낼 수 없습니다 / protected path");
            continue;
        }
        if let Some(reason) = drive_type_blocker(win::drive_type(path)) {
            skip(reason);
            continue;
        }
        from.extend(value.encode_utf16());
        from.push(0);
        accepted.push(value);
    }
    if accepted.is_empty() {
        return Ok(RecycleOutcome {
            recycled: Vec::new(),
            skipped,
        });
    }
    // SHFileOperation requires a double-NUL-terminated list of source paths.
    from.push(0);
    // FOF_WANTNUKEWARNING partially overrides FOF_NOCONFIRMATION: the shell
    // still asks before an item that cannot be recycled (for example one
    // larger than the bin) would be destroyed.
    let mut operation = SHFILEOPSTRUCTW {
        hwnd: owner,
        wFunc: FO_DELETE,
        pFrom: from.as_ptr(),
        pTo: null(),
        fFlags: (FOF_ALLOWUNDO
            | FOF_NOCONFIRMATION
            | FOF_WANTNUKEWARNING
            | FOF_NOERRORUI
            | FOF_SILENT) as u16,
        fAnyOperationsAborted: 0,
        hNameMappings: std::ptr::null_mut(),
        lpszProgressTitle: null(),
    };
    let result = unsafe { SHFileOperationW(&mut operation) };
    Ok(settle(
        accepted,
        skipped,
        operation.fAnyOperationsAborted != 0,
        result,
        |path| Path::new(path).exists(),
    ))
}

#[cfg(windows)]
pub fn recycle_files(
    paths: Vec<String>,
    owner: windows_sys::Win32::Foundation::HWND,
) -> Result<RecycleOutcome, String> {
    recycle_with_owner(paths, owner)
}

#[cfg(not(windows))]
pub fn recycle_files(
    paths: Vec<String>,
    _: *mut std::ffi::c_void,
) -> Result<RecycleOutcome, String> {
    // One folder per run, so a batch can be found and restored together.
    let batch = chrono::Local::now().format("%Y-%m-%d_%H%M%S").to_string();
    move_to_trash(paths, |path| {
        volume_root(path).map(|root| root.join(crate::planner::TRASH_FOLDER).join(&batch))
    })
}

/// The storage volume `path` lives on: internal storage
/// (`/storage/emulated/0`, `/sdcard`) or an SD card (`/storage/1234-ABCD`).
/// Elsewhere there is no place for a trash folder.
#[cfg(not(any(windows, target_os = "ios")))]
fn volume_root(path: &Path) -> Option<std::path::PathBuf> {
    path.ancestors()
        .find(|ancestor| {
            crate::planner::is_storage_root(ancestor)
                && !matches!(
                    ancestor.to_str(),
                    Some("/storage" | "/storage/emulated" | "/storage/self")
                )
        })
        .map(Path::to_path_buf)
}

/// On the iPad everything U-file can reach is inside its Documents folder.
#[cfg(target_os = "ios")]
fn volume_root(path: &Path) -> Option<std::path::PathBuf> {
    crate::planner::ios_documents().filter(|documents| path.starts_with(documents))
}

/// Move each item into the folder `bin_for` names for it, never replacing a
/// file already there.
#[cfg(any(not(windows), test))]
fn move_to_trash(
    paths: Vec<String>,
    bin_for: impl Fn(&Path) -> Option<std::path::PathBuf>,
) -> Result<RecycleOutcome, String> {
    if paths.is_empty() {
        return Err("휴지통으로 보낼 파일을 하나 이상 선택하세요.".into());
    }
    let mut recycled: Vec<String> = Vec::new();
    let mut skipped = Vec::new();
    for value in paths {
        if recycled.contains(&value) {
            continue;
        }
        let path = Path::new(&value);
        let mut skip = |reason: String| {
            skipped.push(RecycleSkip {
                path: value.clone(),
                reason,
            });
        };
        if !path.is_absolute() {
            skip("전체 경로가 아니어서 건너뜀 / not an absolute path".into());
            continue;
        }
        if !path.is_file() && !path.is_dir() {
            skip("항목을 찾을 수 없어 건너뜀 / not found".into());
            continue;
        }
        if crate::planner::is_protected_path(path) {
            skip("보호된 경로는 휴지통으로 보낼 수 없습니다 / protected path".into());
            continue;
        }
        let (Some(bin), Some(name)) = (bin_for(path), path.file_name()) else {
            skip(
                "휴지통 폴더를 둘 저장소를 찾을 수 없습니다 / no trash folder for this location"
                    .into(),
            );
            continue;
        };
        if let Err(error) = std::fs::create_dir_all(&bin) {
            skip(format!(
                "휴지통 폴더를 만들 수 없습니다 / cannot create the trash folder: {error}"
            ));
            continue;
        }
        match crate::planner::move_with_unique_name(path, bin.join(name)) {
            Ok(_) => recycled.push(value),
            Err(error) => skip(format!(
                "휴지통으로 옮기지 못했습니다 / could not be moved to the trash: {error}"
            )),
        }
    }
    Ok(RecycleOutcome { recycled, skipped })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_fixed_drives_are_recycled() {
        assert_eq!(drive_type_blocker(3), None);
        for blocked in [0, 1, 2, 4, 5, 6] {
            assert!(drive_type_blocker(blocked).is_some(), "type {blocked}");
        }
    }

    #[test]
    fn items_that_survive_the_shell_call_are_reported_not_counted() {
        let outcome = settle(
            vec!["C:\\a.bin".into(), "C:\\b.bin".into()],
            Vec::new(),
            false,
            0,
            |path| path == "C:\\b.bin",
        );
        assert_eq!(outcome.recycled, vec!["C:\\a.bin".to_string()]);
        assert_eq!(outcome.skipped.len(), 1);
        assert_eq!(outcome.skipped[0].path, "C:\\b.bin");
    }

    #[test]
    fn cancelled_operation_is_labelled_as_cancelled() {
        let outcome = settle(vec!["C:\\a.bin".into()], Vec::new(), true, 0, |_| true);
        assert!(outcome.recycled.is_empty());
        assert!(outcome.skipped[0].reason.contains("cancelled"));
    }

    #[test]
    fn shell_error_code_is_included_when_nothing_was_removed() {
        let outcome = settle(vec!["C:\\a.bin".into()], Vec::new(), false, 124, |_| true);
        assert!(outcome.skipped[0].reason.contains("124"));
    }

    #[cfg(windows)]
    #[test]
    fn relative_or_missing_inputs_are_skipped_without_touching_the_shell() {
        let outcome = recycle_with_owner(
            vec![
                "relative\\file.txt".into(),
                "C:\\definitely\\missing\\x.bin".into(),
            ],
            std::ptr::null_mut(),
        )
        .expect("outcome");
        assert!(outcome.recycled.is_empty());
        assert_eq!(outcome.skipped.len(), 2);
    }

    #[test]
    fn trash_moves_files_and_folders_without_replacing() {
        let base = Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("target")
            .join("test-tmp");
        std::fs::create_dir_all(&base).expect("base");
        let root = tempfile::Builder::new().tempdir_in(base).expect("dir");
        let bin = root.path().join("bin");
        std::fs::create_dir_all(&bin).expect("bin");
        std::fs::write(bin.join("a.txt"), b"already in the bin").expect("old");
        let file = root.path().join("a.txt");
        let folder = root.path().join("empty");
        std::fs::write(&file, b"new").expect("file");
        std::fs::create_dir(&folder).expect("folder");
        let text = |path: &Path| path.display().to_string();

        let outcome = move_to_trash(
            vec![text(&file), text(&folder), "relative.txt".into()],
            |_| Some(bin.clone()),
        )
        .expect("outcome");
        assert_eq!(outcome.recycled, vec![text(&file), text(&folder)]);
        assert_eq!(outcome.skipped.len(), 1);
        assert!(!file.exists() && !folder.exists());
        assert_eq!(
            std::fs::read(bin.join("a.txt")).unwrap(),
            b"already in the bin"
        );
        assert_eq!(std::fs::read(bin.join("a (1).txt")).unwrap(), b"new");
        assert!(bin.join("empty").is_dir());

        // Without a place for the bin nothing moves.
        std::fs::write(&file, b"again").expect("file");
        let outcome = move_to_trash(vec![text(&file)], |_| None).expect("outcome");
        assert!(outcome.recycled.is_empty() && file.exists());
    }

    /// Sends one throwaway file to the real Recycle Bin. Run on demand:
    /// `cargo test --lib -- --ignored recycles_a_real_file`.
    #[cfg(windows)]
    #[test]
    #[ignore]
    fn recycles_a_real_file() {
        let base = Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("target")
            .join("test-tmp");
        std::fs::create_dir_all(&base).expect("base");
        let directory = tempfile::Builder::new().tempdir_in(base).expect("dir");
        let file = directory.path().join("filemoa-recycle-test.txt");
        std::fs::write(&file, b"safe to delete").expect("file");
        let value = file.display().to_string();
        let outcome =
            recycle_with_owner(vec![value.clone()], std::ptr::null_mut()).expect("outcome");
        assert_eq!(outcome.recycled, vec![value], "{:?}", outcome.skipped);
        assert!(!file.exists());
    }
}
