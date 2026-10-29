mod ai;
mod journal;
mod media;
mod plan_store;
mod planner;
mod progress;
mod recycle;
mod scan_store;

use plan_store::PlanStore;
use planner::{OrganizationPlan, PlanRequest};
use progress::{Ctl, Operations, Progress};
use scan_store::ScanStore;
use serde::Serialize;
use std::path::PathBuf;
#[cfg(desktop)]
use tauri::Emitter;
use tauri::{ipc::Channel, AppHandle, Manager};

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct KnownFolder {
    id: String,
    path: String,
}

#[cfg(not(any(target_os = "android", target_os = "ios")))]
#[tauri::command]
fn known_folders(app: AppHandle) -> Vec<KnownFolder> {
    let locations = [
        ("desktop", app.path().desktop_dir()),
        ("downloads", app.path().download_dir()),
        ("documents", app.path().document_dir()),
        ("pictures", app.path().picture_dir()),
        ("videos", app.path().video_dir()),
        ("music", app.path().audio_dir()),
    ];
    locations
        .into_iter()
        .filter_map(|(id, path)| {
            let path = path.ok()?;
            path.is_dir().then(|| KnownFolder {
                id: id.into(),
                path: path.display().to_string(),
            })
        })
        .collect()
}

/// Shared-storage folders a Galaxy Tab fills by itself. The path API would
/// answer with app-private folders here, so the public ones are named directly.
#[cfg(target_os = "android")]
#[tauri::command]
fn known_folders(_app: AppHandle) -> Vec<KnownFolder> {
    let root = std::path::Path::new(planner::ANDROID_STORAGE);
    [
        ("downloads", "Download"),
        ("camera", "DCIM/Camera"),
        ("screenshots", "DCIM/Screenshots"),
        ("screenshots", "Pictures/Screenshots"),
        ("pictures", "Pictures"),
        ("documents", "Documents"),
        ("videos", "Movies"),
        ("music", "Music"),
    ]
    .into_iter()
    .filter_map(|(id, relative)| {
        let path = root.join(relative);
        path.is_dir().then(|| KnownFolder {
            id: id.into(),
            path: path.display().to_string(),
        })
    })
    .fold(Vec::new(), |mut found, folder| {
        // One Screenshots entry: One UI keeps them in DCIM, older versions in Pictures.
        if !found
            .iter()
            .any(|known: &KnownFolder| known.id == folder.id)
        {
            found.push(folder);
        }
        found
    })
}

/// On the iPad: U-file's Documents folder ("On My iPad > U-file" in the
/// Files app) and the usual sub-folders when they exist.
#[cfg(target_os = "ios")]
#[tauri::command]
fn known_folders(_app: AppHandle) -> Vec<KnownFolder> {
    let Some(documents) = planner::ios_documents() else {
        return Vec::new();
    };
    let mut found = vec![KnownFolder {
        id: "documents".into(),
        path: documents.display().to_string(),
    }];
    for (id, name) in [
        ("downloads", "Download"),
        ("pictures", "Pictures"),
        ("videos", "Movies"),
        ("music", "Music"),
    ] {
        let path = documents.join(name);
        if path.is_dir() {
            found.push(KnownFolder {
                id: id.into(),
                path: path.display().to_string(),
            });
        }
    }
    found
}

/// Where the folder browser starts and stops: the shared storage on
/// Android, U-file's Documents folder on the iPad, the home folder elsewhere.
fn browse_root(app: &AppHandle) -> Result<PathBuf, String> {
    #[cfg(target_os = "ios")]
    {
        let _ = app;
        planner::ios_documents()
            .ok_or_else(|| "문서 폴더를 찾을 수 없습니다 / no Documents folder".into())
    }
    #[cfg(target_os = "android")]
    {
        let _ = app;
        Ok(PathBuf::from(planner::ANDROID_STORAGE))
    }
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    {
        app.path()
            .home_dir()
            .map_err(|e| format!("홈 폴더를 찾을 수 없습니다 / home folder unavailable: {e}"))
    }
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct StorageInfo {
    /// Top of what U-file browses.
    root: String,
    /// Where "Recycle Bin" moves go on a tablet.
    trash: String,
}

#[tauri::command]
fn storage_info(app: AppHandle) -> Result<StorageInfo, String> {
    let root = browse_root(&app)?;
    Ok(StorageInfo {
        trash: root.join(planner::TRASH_FOLDER).display().to_string(),
        root: root.display().to_string(),
    })
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct FolderListing {
    path: String,
    parent: Option<String>,
    folders: Vec<String>,
    files: Vec<FileEntry>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct FileEntry {
    name: String,
    size_bytes: u64,
}

/// The sub-folders of `path` for the in-app folder browser. Android has no
/// system folder picker that returns a real path, so the app browses itself.
/// Without a path it starts at the shared storage (or the home folder).
#[tauri::command]
fn list_folders(app: AppHandle, path: Option<String>) -> Result<FolderListing, String> {
    let root = browse_root(&app)?;
    let start = match path {
        Some(path) if !path.is_empty() => PathBuf::from(path),
        _ => root.clone(),
    };
    let entries = std::fs::read_dir(&start).map_err(|error| {
        format!(
            "폴더를 열 수 없습니다: {} ({error}) / cannot open the folder",
            start.display()
        )
    })?;
    let mut folders = Vec::new();
    let mut files = Vec::new();
    for entry in entries.filter_map(Result::ok) {
        let Ok(name) = entry.file_name().into_string() else {
            continue;
        };
        if name.starts_with('.') || planner::is_protected_path(&start.join(&name)) {
            continue;
        }
        match entry.metadata() {
            Ok(metadata) if metadata.is_dir() => folders.push(name),
            Ok(metadata) if metadata.is_file() => files.push(FileEntry {
                name,
                size_bytes: metadata.len(),
            }),
            _ => {}
        }
    }
    folders.sort_by_key(|name| name.to_lowercase());
    files.sort_by_key(|file| file.name.to_lowercase());
    // Stop at the top of the shared storage: above it nothing can be organised.
    let at_top = planner::is_storage_root(&start)
        || (cfg!(mobile) && planner::path_key(&start) == planner::path_key(&root));
    Ok(FolderListing {
        parent: (!at_top)
            .then(|| start.parent().map(|parent| parent.display().to_string()))
            .flatten(),
        path: start.display().to_string(),
        folders,
        files,
    })
}

fn startup_candidate<I>(mut arguments: I) -> Result<Option<PathBuf>, String>
where
    I: Iterator<Item = std::ffi::OsString>,
{
    while let Some(argument) = arguments.next() {
        if !argument
            .to_string_lossy()
            .eq_ignore_ascii_case("--organize")
        {
            continue;
        }
        let Some(candidate) = arguments.next() else {
            return Err(
                "U-file 셸 실행 인자에 폴더 경로가 없습니다. / The shell launch did not include a folder path."
                    .into(),
            );
        };
        return Ok(Some(PathBuf::from(candidate)));
    }
    Ok(None)
}

/// Return the single folder passed by an Explorer/Desktop shell verb. The
/// explicit marker prevents unrelated runtime arguments from being treated as
/// a folder, and invalid paths fail before the planner can perform any work.
#[tauri::command]
fn startup_path() -> Result<Option<String>, String> {
    let Some(path) = startup_candidate(std::env::args_os().skip(1))? else {
        return Ok(None);
    };
    if !path.is_dir() {
        return Err(format!(
            "셸에서 전달된 폴더를 찾을 수 없습니다: {} / The shell folder is not available: {}",
            path.display(),
            path.display()
        ));
    }
    Ok(Some(path.display().to_string()))
}

/// Start the one allowed long operation; progress goes to `channel`.
fn begin(ops: &Operations, channel: Option<Channel<Progress>>) -> Result<Ctl, String> {
    ops.begin(channel.map(|channel| {
        Box::new(move |progress: Progress| {
            let _ = channel.send(progress);
        }) as Box<dyn Fn(Progress) + Send + Sync>
    }))
}

/// Run blocking work off the UI thread: a plain `fn` command would run on it
/// and freeze the window for as long as a big folder takes.
async fn blocking<T: Send + 'static>(
    work: impl FnOnce() -> Result<T, String> + Send + 'static,
) -> Result<T, String> {
    tauri::async_runtime::spawn_blocking(work)
        .await
        .map_err(|error| format!("작업 스레드 오류 / worker thread failed: {error}"))?
}

/// Ask the running operation to stop at its next checkpoint.
#[tauri::command]
fn cancel_operation(ops: tauri::State<'_, Operations>) {
    ops.cancel();
}

#[tauri::command]
async fn plan_organization(
    store: tauri::State<'_, PlanStore>,
    ops: tauri::State<'_, Operations>,
    request: PlanRequest,
    on_progress: Channel<Progress>,
) -> Result<OrganizationPlan, String> {
    let ctl = begin(&ops, Some(on_progress))?;
    let mut plan = blocking(move || planner::create_plan_ctl(request, &ctl)).await?;
    store.insert(&mut plan);
    Ok(plan)
}

#[tauri::command]
async fn plan_multiple_organizations(
    store: tauri::State<'_, PlanStore>,
    ops: tauri::State<'_, Operations>,
    requests: Vec<PlanRequest>,
    on_progress: Channel<Progress>,
) -> Result<OrganizationPlan, String> {
    let ctl = begin(&ops, Some(on_progress))?;
    let mut plan = blocking(move || planner::create_multi_plan_ctl(requests, &ctl)).await?;
    store.insert(&mut plan);
    Ok(plan)
}

fn runs_dir(app: &AppHandle) -> Result<PathBuf, String> {
    app.path()
        .app_data_dir()
        .map(|dir| dir.join("runs"))
        .map_err(|e| {
            format!("앱 데이터 경로를 확인할 수 없습니다 / app data path unavailable: {e}")
        })
}

/// Runs the plan the backend stored under `plan_id`. The renderer never
/// supplies the paths that get moved.
#[tauri::command]
async fn execute_organization(
    app: AppHandle,
    store: tauri::State<'_, PlanStore>,
    ops: tauri::State<'_, Operations>,
    plan_id: String,
    excluded: Option<Vec<usize>>,
    on_progress: Channel<Progress>,
) -> Result<OrganizationPlan, String> {
    let dir = runs_dir(&app)?;
    let ctl = begin(&ops, Some(on_progress))?;
    // A plan can be claimed once: a double click cannot run it twice.
    let mut plan = store.claim(&plan_id)?;
    // Keep the plan as previewed, so a failed start can be retried with another selection.
    let backup = plan.clone();
    if let Err(error) = planner::exclude_by_user(&mut plan, &excluded.unwrap_or_default()) {
        store.restore(backup);
        return Err(error);
    }
    if !plan
        .actions
        .iter()
        .any(|action| action.status == "proposed")
    {
        store.restore(backup);
        return Err("이동할 항목이 선택되지 않았습니다 / nothing is selected to move".into());
    }
    planner::mark_changed_since_preview(&mut plan);
    match blocking(move || journal::execute_with_journal_ctl(&dir, plan, &ctl)).await {
        Ok(done) => Ok(done),
        Err(error) => {
            // Nothing was moved when the run could not even start; keep the plan.
            store.restore(backup);
            Err(error)
        }
    }
}

/// Runs that were still in progress when the app last stopped, with every
/// journaled move applied so they can be reviewed or undone.
#[tauri::command]
fn recover_interrupted_runs(app: AppHandle) -> Result<Vec<OrganizationPlan>, String> {
    journal::recover(&runs_dir(&app)?)
}

/// Undo reads the run from the backend's own record; the renderer only names it.
#[tauri::command]
async fn undo_organization(
    app: AppHandle,
    ops: tauri::State<'_, Operations>,
    run_id: String,
    only: Option<Vec<usize>>,
) -> Result<OrganizationPlan, String> {
    let dir = runs_dir(&app)?;
    let ctl = begin(&ops, None)?;
    blocking(move || {
        let _running = ctl;
        let plan = journal::load_run(&dir, &run_id)?;
        if let Some(rows) = &only {
            let wanted = rows
                .iter()
                .filter(|row| {
                    plan.actions
                        .get(**row)
                        .is_some_and(|a| a.status == "executed")
                })
                .count();
            if wanted == 0 {
                return Err(
                    "되돌릴 항목이 선택되지 않았습니다 / nothing is selected to undo".into(),
                );
            }
        }
        let mut undone = planner::undo_plan_only(plan, only.as_deref())?;
        // Files are already restored; a record that cannot be saved must not turn
        // that success into an error, so surface it as a warning instead.
        if let Err(error) = journal::save_finished(&dir, &undone) {
            undone.warnings.push(error);
        }
        Ok(undone)
    })
    .await
}

#[tauri::command]
fn list_runs(app: AppHandle) -> Result<Vec<journal::RunSummary>, String> {
    journal::list_runs(&runs_dir(&app)?, 30)
}

#[tauri::command]
fn load_run(app: AppHandle, run_id: String) -> Result<OrganizationPlan, String> {
    journal::load_run(&runs_dir(&app)?, &run_id)
}

#[tauri::command]
fn delete_run(app: AppHandle, run_id: String) -> Result<(), String> {
    journal::delete_run(&runs_dir(&app)?, &run_id)
}

#[tauri::command]
fn import_legacy_runs(app: AppHandle, runs: Vec<OrganizationPlan>) -> Result<usize, String> {
    journal::import_legacy(&runs_dir(&app)?, runs)
}

#[tauri::command]
async fn find_duplicates(
    scans: tauri::State<'_, ScanStore>,
    ops: tauri::State<'_, Operations>,
    root_path: String,
    include_subfolders: bool,
    on_progress: Channel<Progress>,
) -> Result<planner::ScanResult<planner::DuplicateGroup>, String> {
    let ctl = begin(&ops, Some(on_progress))?;
    let result =
        blocking(move || planner::find_duplicates_ctl(&root_path, include_subfolders, &ctl))
            .await?;
    scans.register_duplicates(&result.items);
    Ok(result)
}

#[tauri::command]
async fn find_large_files(
    scans: tauri::State<'_, ScanStore>,
    ops: tauri::State<'_, Operations>,
    root_path: String,
    include_subfolders: bool,
    minimum_size_bytes: u64,
    on_progress: Channel<Progress>,
) -> Result<planner::ScanResult<planner::LargeFile>, String> {
    let ctl = begin(&ops, Some(on_progress))?;
    let result = blocking(move || {
        planner::find_large_files_ctl(&root_path, include_subfolders, minimum_size_bytes, &ctl)
    })
    .await?;
    scans.register_large(&result.items);
    Ok(result)
}

#[tauri::command]
async fn find_empty_folders(
    scans: tauri::State<'_, ScanStore>,
    ops: tauri::State<'_, Operations>,
    root_path: String,
    include_subfolders: bool,
    on_progress: Channel<Progress>,
) -> Result<Vec<String>, String> {
    let ctl = begin(&ops, Some(on_progress))?;
    let folders =
        blocking(move || planner::find_empty_folders_ctl(&root_path, include_subfolders, &ctl))
            .await?;
    scans.register_empty(&folders);
    Ok(folders)
}

/// Only items a scan listed, unchanged since, and never the last copy of a
/// duplicate group, may go to the Recycle Bin.
#[tauri::command]
fn recycle_files(
    window: tauri::WebviewWindow,
    scans: tauri::State<'_, ScanStore>,
    paths: Vec<String>,
) -> Result<recycle::RecycleOutcome, String> {
    if paths.is_empty() {
        return Err("휴지통으로 보낼 파일을 하나 이상 선택하세요.".into());
    }
    let (accepted, mut skipped) = scans.authorize(&paths);
    if accepted.is_empty() {
        return Ok(recycle::RecycleOutcome {
            recycled: Vec::new(),
            skipped,
        });
    }
    // The shell's "permanent delete" warning needs an owner window to appear on top.
    #[cfg(windows)]
    let owner = window
        .hwnd()
        .map(|handle| handle.0 as windows_sys::Win32::Foundation::HWND)
        .unwrap_or(std::ptr::null_mut());
    #[cfg(not(windows))]
    let owner = {
        let _ = &window;
        std::ptr::null_mut()
    };
    let outcome = recycle::recycle_files(accepted, owner)?;
    scans.forget(&outcome.recycled);
    skipped.extend(outcome.skipped);
    Ok(recycle::RecycleOutcome {
        recycled: outcome.recycled,
        skipped,
    })
}

/// What a second launch asks the already running window to do. A plain second
/// launch (no folder) only brings the window forward.
#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
#[cfg_attr(not(desktop), allow(dead_code))]
struct OpenFolderRequest {
    path: Option<String>,
    error: Option<String>,
}

/// Read the `--organize <folder>` a second launch was started with. The first
/// argument is the executable itself.
#[cfg(desktop)]
fn folder_request(args: &[String]) -> OpenFolderRequest {
    let arguments = args.iter().skip(1).map(std::ffi::OsString::from);
    match startup_candidate(arguments) {
        Ok(None) => OpenFolderRequest {
            path: None,
            error: None,
        },
        Ok(Some(path)) if path.is_dir() => OpenFolderRequest {
            path: Some(path.display().to_string()),
            error: None,
        },
        Ok(Some(path)) => OpenFolderRequest {
            path: None,
            error: Some(format!(
                "셸에서 전달된 폴더를 찾을 수 없습니다: {} / The shell folder is not available: {}",
                path.display(),
                path.display()
            )),
        },
        Err(error) => OpenFolderRequest {
            path: None,
            error: Some(error),
        },
    }
}

/// Logical size to open the window with: the design size, but never more than
/// the usable part of the screen (so a laptop does not push it off-screen).
#[cfg(desktop)]
fn start_size(work_width: f64, work_height: f64) -> (f64, f64) {
    const DESIGN: (f64, f64) = (1200.0, 960.0);
    const MIN: (f64, f64) = (940.0, 620.0);
    // Room for the title bar, the window border and a little air around it.
    let width = DESIGN.0.min(work_width - 48.0).max(MIN.0);
    let height = DESIGN.1.min(work_height - 80.0).max(MIN.1);
    (width, height)
}

/// Shrink the window to the screen it opens on when the design size does not
/// fit; on a large screen nothing changes.
#[cfg(desktop)]
fn fit_window_to_screen(window: &tauri::WebviewWindow) {
    let monitor = window
        .current_monitor()
        .ok()
        .flatten()
        .or_else(|| window.primary_monitor().ok().flatten());
    let Some(monitor) = monitor else { return };
    let scale = monitor.scale_factor();
    let area = monitor.work_area();
    let (width, height) = start_size(
        f64::from(area.size.width) / scale,
        f64::from(area.size.height) / scale,
    );
    let _ = window.set_size(tauri::LogicalSize::new(width, height));
    let _ = window.center();
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let builder = tauri::Builder::default();
    // Must be the first plugin. A second launch (the Explorer context menu,
    // a shortcut) exits at once; this running window receives its folder.
    #[cfg(desktop)]
    let builder = builder
        .plugin(tauri_plugin_single_instance::init(
            |app, args, _working_dir| {
                if let Some(window) = app.get_webview_window("main") {
                    let _ = window.unminimize();
                    let _ = window.show();
                    let _ = window.set_focus();
                }
                let _ = app.emit("open-folder", folder_request(&args));
            },
        ))
        .setup(|app| {
            if let Some(window) = app.get_webview_window("main") {
                fit_window_to_screen(&window);
            }
            Ok(())
        })
        .plugin(tauri_plugin_updater::Builder::new().build());
    builder
        .manage(PlanStore::default())
        .manage(ScanStore::default())
        .manage(Operations::default())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_store::Builder::default().build())
        .plugin(tauri_plugin_process::init())
        .invoke_handler(tauri::generate_handler![
            known_folders,
            list_folders,
            storage_info,
            media::read_media,
            media::save_download,
            cancel_operation,
            startup_path,
            plan_organization,
            plan_multiple_organizations,
            execute_organization,
            recover_interrupted_runs,
            list_runs,
            load_run,
            delete_run,
            import_legacy_runs,
            undo_organization,
            find_duplicates,
            find_large_files,
            find_empty_folders,
            recycle_files,
            ai::detect_ollama,
            ai::get_ai_provider_settings,
            ai::save_ai_provider,
            ai::remove_ai_provider_key,
            ai::test_ai_provider_connection,
            ai::classify_files,
            ai::list_ai_models,
            ai::apply_ai_suggestions
        ])
        .run(tauri::generate_context!())
        .expect("error while running U-file");
}

#[cfg(test)]
mod tests {
    use super::startup_candidate;
    use std::ffi::OsString;

    #[test]
    fn shell_parser_requires_explicit_marker() {
        let args = vec![OsString::from(r"C:\not-a-folder")].into_iter();
        assert!(startup_candidate(args).expect("parse").is_none());
    }

    #[test]
    fn shell_parser_preserves_unicode_and_spaces() {
        let expected = r"C:\Users\demo\바탕 화면\작업 폴더";
        let args = vec![OsString::from("--organize"), OsString::from(expected)].into_iter();
        let actual = startup_candidate(args).expect("parse").expect("path");
        assert_eq!(actual.to_string_lossy(), expected);
    }

    #[test]
    fn shell_parser_rejects_missing_path_argument() {
        let args = vec![OsString::from("--organize")].into_iter();
        assert!(startup_candidate(args).is_err());
    }

    #[test]
    fn the_window_opens_at_the_design_size_unless_the_screen_is_smaller() {
        use super::start_size;
        // A large work area: the design size, untouched.
        assert_eq!(start_size(2560.0, 1400.0), (1200.0, 960.0));
        assert_eq!(start_size(1920.0, 1040.0), (1200.0, 960.0));
        // A laptop: as tall as fits, still wide enough.
        assert_eq!(start_size(1366.0, 728.0), (1200.0, 648.0));
        // A tiny or odd work area never goes below the minimum window.
        assert_eq!(start_size(800.0, 600.0), (940.0, 620.0));
    }

    #[test]
    fn a_second_launch_names_the_folder_to_open() {
        use super::{folder_request, OpenFolderRequest};
        let folder = std::env::temp_dir();
        let exe = "C:\\Program Files\\FileMoa\\filemoa.exe".to_string();

        // Only the executable: just bring the window forward.
        assert_eq!(
            folder_request(std::slice::from_ref(&exe)),
            OpenFolderRequest {
                path: None,
                error: None
            }
        );
        // The Explorer verb: --organize <existing folder>.
        let ok = folder_request(&[
            exe.clone(),
            "--organize".into(),
            folder.display().to_string(),
        ]);
        assert_eq!(
            ok.path.as_deref(),
            Some(folder.display().to_string().as_str())
        );
        assert!(ok.error.is_none());
        // A folder that is gone, and a marker without a path, are reported, not opened.
        let missing = folder_request(&[
            exe.clone(),
            "--organize".into(),
            "N:\\no\\such\\folder".into(),
        ]);
        assert!(missing.path.is_none() && missing.error.is_some());
        let dangling = folder_request(&[exe, "--organize".into()]);
        assert!(dangling.path.is_none() && dangling.error.is_some());
    }
}
