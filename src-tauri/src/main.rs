#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod model;
mod schedule;
mod store;

use model::{Announcement, AppData, Day, HomeworkItem, Settings, SpeechEntry, PERIODS};
use schedule::{LaunchView, Slot};
use serde::Serialize;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use tauri::{AppHandle, Emitter, Manager, State, Window};
use tauri_plugin_dialog::DialogExt;

struct Inner {
    data: AppData,
    dirty: bool,
    last_edit: Instant,
    image_dirty: bool,
    last_image: Instant,
    presenting: bool,
}

struct Shared {
    inner: Mutex<Inner>,
    data_dir: Mutex<PathBuf>,
    notice: Mutex<Option<String>>,
}

#[derive(Serialize, Clone)]
struct StatePayload {
    data: AppData,
    data_dir: String,
    today: String,
    launch: LaunchView,
    notice: Option<String>,
}

fn payload(shared: &Shared) -> StatePayload {
    let inner = shared.inner.lock().unwrap();
    let today = schedule::today_string();
    StatePayload {
        launch: schedule::launch_view(&inner.data, &today, chrono::Local::now().time()),
        data: inner.data.clone(),
        data_dir: shared.data_dir.lock().unwrap().display().to_string(),
        today,
        notice: shared.notice.lock().unwrap().clone(),
    }
}

fn emit_state(app: &AppHandle, shared: &Shared) {
    let _ = app.emit("state-changed", payload(shared));
}

fn mark_changed(app: &AppHandle, shared: &Shared) {
    {
        let mut inner = shared.inner.lock().unwrap();
        inner.dirty = true;
        inner.image_dirty = true;
        inner.last_edit = Instant::now();
    }
    emit_state(app, shared);
}

#[derive(Serialize, Clone)]
struct ViewModel {
    /// 页面日 = 作业所属日（编辑页正在编辑的那天）
    date: String,
    /// 画面上显示的日期：全部 = 页面日；仅要交 = 页面日的下一个上学日
    display_date: String,
    weekday: String,
    submit_only: bool,
    homework_date: String,
    slots: Vec<Slot>,
    announcements: Vec<Announcement>,
    homework: Vec<HomeworkItem>,
    speeches: Vec<SpeechEntry>,
    speech_warn: bool,
    homework_suggestions: Vec<String>,
    speech_suggestions: Vec<String>,
}

#[tauri::command]
fn get_view_model(state: State<Arc<Shared>>, date: String, submit_only: bool) -> ViewModel {
    let inner = state.inner.lock().unwrap();
    let data = &inner.data;
    // 页面日固定是作业所属的那一天；「仅要交」只改变画面上的日期和作业过滤，
    // 因此切换全部/仅要交不会换天，编辑中的草稿不会被切走。
    let display_date = if submit_only {
        schedule::next_school_day(data, &date)
    } else {
        date.clone()
    };
    let day = data.days.get(&date);
    let display_slots = schedule::effective_schedule(data, &display_date);
    let page_slots = schedule::effective_schedule(data, &date);
    let announcements = data.announcements.iter().filter(|a| schedule::announcement_visible(a)).cloned().collect();
    ViewModel {
        weekday: schedule::weekday_cn(&display_date),
        slots: display_slots,
        announcements,
        homework: schedule::present_homework(data, &date, submit_only),
        speeches: day.map(|d| d.speeches.clone()).unwrap_or_default(),
        speech_warn: day.map(|d| schedule::speeches_empty(d)).unwrap_or(true),
        homework_suggestions: schedule::homework_suggestions(&page_slots),
        speech_suggestions: schedule::speech_suggestions(data, &date),
        homework_date: date.clone(),
        display_date,
        date,
        submit_only,
    }
}

#[derive(Serialize, Clone)]
struct WeekOverview {
    dates: Vec<String>,
    rows: Vec<Vec<Slot>>,
}

#[tauri::command]
fn get_week(state: State<Arc<Shared>>, monday: String) -> WeekOverview {
    let inner = state.inner.lock().unwrap();
    let mut dates = Vec::with_capacity(7);
    let mut rows = Vec::with_capacity(7);
    for i in 0..7 {
        let d = schedule::add_days(&monday, i);
        rows.push(schedule::effective_schedule(&inner.data, &d));
        dates.push(d);
    }
    WeekOverview { dates, rows }
}

#[tauri::command]
fn get_state(state: State<Arc<Shared>>) -> StatePayload {
    payload(&state)
}

#[tauri::command]
fn get_launch_view(state: State<Arc<Shared>>) -> LaunchView {
    let inner = state.inner.lock().unwrap();
    let today = schedule::today_string();
    schedule::launch_view(&inner.data, &today, chrono::Local::now().time())
}

#[tauri::command]
fn set_day(app: AppHandle, state: State<Arc<Shared>>, date: String, mut day: Day) {
    day.schedule_override.resize(PERIODS, None);
    state.inner.lock().unwrap().data.days.insert(date, day);
    mark_changed(&app, &state);
}

#[tauri::command]
fn add_day(app: AppHandle, state: State<Arc<Shared>>, date: String, copied_from_weekday: Option<usize>) -> Result<(), String> {
    if schedule::parse_date(&date).is_none() {
        return Err("日期格式不正确".into());
    }
    let mut inner = state.inner.lock().unwrap();
    if inner.data.days.contains_key(&date) {
        return Err("该日期已存在".into());
    }
    let day = Day {
        copied_from_weekday: copied_from_weekday.filter(|i| *i < 7),
        ..Day::default()
    };
    inner.data.days.insert(date, day);
    drop(inner);
    mark_changed(&app, &state);
    Ok(())
}

#[tauri::command]
fn delete_day(app: AppHandle, state: State<Arc<Shared>>, date: String) {
    state.inner.lock().unwrap().data.days.remove(&date);
    mark_changed(&app, &state);
}

#[tauri::command]
fn set_announcements(app: AppHandle, state: State<Arc<Shared>>, list: Vec<Announcement>) {
    state.inner.lock().unwrap().data.announcements = list;
    mark_changed(&app, &state);
}

/// 公告是全局一列（所有日期共用），只有完成状态
#[tauri::command]
fn add_announcement(app: AppHandle, state: State<Arc<Shared>>, text: String) {
    let mut inner = state.inner.lock().unwrap();
    let id = inner.data.next_announcement_id();
    inner.data.announcements.push(Announcement { id, text, done: false });
    drop(inner);
    mark_changed(&app, &state);
}

#[tauri::command]
fn set_weekly_schedule(app: AppHandle, state: State<Arc<Shared>>, rows: Vec<Vec<String>>) {
    state.inner.lock().unwrap().data.weekly_schedule = schedule::normalize_weekly(rows);
    mark_changed(&app, &state);
}

#[tauri::command]
fn update_settings(app: AppHandle, state: State<Arc<Shared>>, settings: Settings) {
    let mut inner = state.inner.lock().unwrap();
    let data_dir = inner.data.settings.data_dir.clone();
    inner.data.settings = settings;
    inner.data.settings.data_dir = data_dir;
    drop(inner);
    mark_changed(&app, &state);
}

#[tauri::command]
fn choose_data_dir(app: AppHandle, state: State<Arc<Shared>>) -> Result<Option<String>, String> {
    let picked = app.dialog().file().blocking_pick_folder();
    let Some(new_dir) = picked else {
        return Ok(None);
    };
    let new_path = new_dir.into_path().map_err(|e| e.to_string())?;
    let current = state.data_dir.lock().unwrap().clone();
    let migrated = store::migrate_data_dir(&current, &new_path)?;
    *state.data_dir.lock().unwrap() = migrated.clone();
    state.inner.lock().unwrap().data.settings.data_dir = Some(migrated.display().to_string());
    mark_changed(&app, &state);
    Ok(Some(migrated.display().to_string()))
}

#[tauri::command]
fn save_now(state: State<Arc<Shared>>) -> Result<(), String> {
    let mut inner = state.inner.lock().unwrap();
    let dir = state.data_dir.lock().unwrap().clone();
    store::save(&dir, &inner.data)?;
    inner.dirty = false;
    Ok(())
}

#[tauri::command]
fn frontend_ready(window: Window) {
    let _ = window.show();
    let _ = window.set_focus();
}

#[tauri::command]
fn set_presenting(window: Window, state: State<Arc<Shared>>, on: bool) -> Result<(), String> {
    state.inner.lock().unwrap().presenting = on;
    window.set_fullscreen(on).map_err(|e| e.to_string())?;
    Ok(())
}

#[tauri::command]
fn export_image(app: AppHandle, state: State<Arc<Shared>>, bytes: Vec<u8>) -> Result<String, String> {
    let today = schedule::today_string();
    let dir = store::exe_dir();
    let name = format!("家庭作业_{today}.png");
    let path = dir.join(&name);
    std::fs::write(&path, &bytes).map_err(|e| format!("写入图片失败：{e}"))?;
    if let Ok(rd) = std::fs::read_dir(&dir) {
        for e in rd.flatten() {
            let p = e.path();
            let fname = e.file_name().to_string_lossy().to_string();
            if fname.starts_with("家庭作业_") && fname.ends_with(".png") && fname != name {
                let _ = std::fs::remove_file(p);
            }
        }
    }
    {
        let mut inner = state.inner.lock().unwrap();
        inner.image_dirty = false;
        inner.last_image = Instant::now();
    }
    let _ = app.emit("image-exported", path.display().to_string());
    Ok(path.display().to_string())
}

fn background_loop(app: AppHandle, shared: Arc<Shared>) {
    loop {
        std::thread::sleep(Duration::from_millis(500));
        let mut inner = shared.inner.lock().unwrap();
        if inner.dirty && inner.last_edit.elapsed() >= Duration::from_secs(1) {
            let dir = shared.data_dir.lock().unwrap().clone();
            if store::save(&dir, &inner.data).is_ok() {
                inner.dirty = false;
            }
        }
        if inner.image_dirty && !inner.presenting {
            let interval = Duration::from_secs(inner.data.settings.image_interval_secs.max(10));
            if inner.last_image.elapsed() >= interval {
                inner.last_image = Instant::now();
                let _ = app.emit("auto-image-request", ());
            }
        }
    }
}

fn main() {
    let dir = store::data_dir();
    let (data, notice) = store::load_or_recover(&dir);
    let shared = Arc::new(Shared {
        inner: Mutex::new(Inner {
            data,
            dirty: false,
            last_edit: Instant::now(),
            image_dirty: false,
            last_image: Instant::now(),
            presenting: false,
        }),
        data_dir: Mutex::new(dir),
        notice: Mutex::new(notice),
    });

    let shared_for_setup = shared.clone();
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .manage(shared)
        .invoke_handler(tauri::generate_handler![
            get_state,
            get_launch_view,
            get_view_model,
            get_week,
            set_day,
            add_day,
            delete_day,
            set_announcements,
            add_announcement,
            set_weekly_schedule,
            update_settings,
            choose_data_dir,
            save_now,
            set_presenting,
            frontend_ready,
            export_image,
        ])
        .setup(move |app| {
            let handle = app.handle().clone();
            let bg = shared_for_setup.clone();
            std::thread::spawn(move || background_loop(handle, bg));
            let fallback = app.handle().clone();
            std::thread::spawn(move || {
                std::thread::sleep(Duration::from_secs(3));
                if let Some(win) = fallback.get_webview_window("main") {
                    let _ = win.show();
                }
            });
            Ok(())
        })
        .on_window_event(|window, event| {
            if let tauri::WindowEvent::CloseRequested { .. } = event {
                let shared = window.state::<Arc<Shared>>();
                let inner = shared.inner.lock().unwrap();
                if inner.dirty {
                    let dir = shared.data_dir.lock().unwrap().clone();
                    let _ = store::save(&dir, &inner.data);
                }
            }
        })
        .run(tauri::generate_context!())
        .expect("运行应用失败");
}
