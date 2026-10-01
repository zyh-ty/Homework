#![windows_subsystem = "windows"]

mod edit;
mod export;
mod keys;
mod layout;
mod model;
mod present;
mod schedule;
mod store;

use chrono::{Local, NaiveDate, NaiveTime};
use eframe::egui;
use model::AppData;
use std::collections::HashSet;
use std::path::PathBuf;
use std::time::Instant;

pub const BADGE_BYTES: &[u8] = include_bytes!("../assets/badge.png");

pub struct LoadedFonts {
    pub regular: Option<fontdue::Font>,
    pub bold: Option<fontdue::Font>,
    pub regular_bytes: Option<(Vec<u8>, u32)>,
    pub bold_bytes: Option<(Vec<u8>, u32)>,
    pub missing: bool,
}

fn try_font(path: &std::path::Path) -> Option<Vec<u8>> {
    std::fs::read(path).ok().filter(|b| b.len() > 100)
}

pub fn load_fonts() -> LoadedFonts {
    let dir = std::path::Path::new(r"C:\Windows\Fonts");
    let regular_candidates: [(&str, u32); 4] = [
        ("msyh.ttc", 0),
        ("simhei.ttf", 0),
        ("simsun.ttc", 0),
        ("Deng.ttf", 0),
    ];
    let bold_candidates: [(&str, u32); 2] = [("msyhbd.ttc", 0), ("simhei.ttf", 0)];
    let regular_bytes = regular_candidates
        .iter()
        .find_map(|(n, i)| try_font(&dir.join(n)).map(|b| (b, *i)));
    let bold_bytes = bold_candidates
        .iter()
        .find_map(|(n, i)| try_font(&dir.join(n)).map(|b| (b, *i)))
        .or_else(|| regular_bytes.clone());

    let mk = |b: &Option<(Vec<u8>, u32)>| {
        b.as_ref().and_then(|(bytes, index)| {
            fontdue::Font::from_bytes(
                bytes.clone(),
                fontdue::FontSettings {
                    collection_index: *index,
                    ..Default::default()
                },
            )
            .ok()
        })
    };
    let regular = mk(&regular_bytes);
    let bold = mk(&bold_bytes).or_else(|| regular.clone());
    let missing = regular.is_none();
    LoadedFonts {
        regular,
        bold,
        regular_bytes,
        bold_bytes,
        missing,
    }
}

pub struct App {
    pub data: AppData,
    pub store: store::Store,
    pub exe_dir: PathBuf,
    pub fonts: LoadedFonts,
    pub layout_font: layout::LayoutFont,
    pub badge_image: image::DynamicImage,
    pub badge_texture: Option<egui::TextureHandle>,
    pub mode: AppMode,
    pub view_date: NaiveDate,
    pub submit_only: bool,
    pub dirty: bool,
    pub last_edit: Instant,
    pub status: String,
    pub status_until: Option<Instant>,
    pub font_missing: bool,
    pub recovered: bool,
    pub today_handled: HashSet<String>,
    pub prev_hw: Vec<model::HomeworkItem>,
    pub show_settings: bool,
    pub show_overview: bool,
    pub show_add_day: bool,
    pub confirm_delete: Option<String>,
    pub new_day: (i32, u32, u32, usize),
    pub last_time_check: chrono::DateTime<Local>,
    pub next_ann_id: u64,
}

#[derive(PartialEq, Clone, Copy)]
pub enum AppMode {
    Edit,
    Present,
}

impl App {
    fn cutoff_time(&self) -> NaiveTime {
        NaiveTime::parse_from_str(&self.data.settings.morning_cutoff, "%H:%M")
            .unwrap_or(NaiveTime::from_hms_opt(8, 0, 0).unwrap())
    }

    pub fn mark_dirty(&mut self) {
        self.dirty = true;
        self.last_edit = Instant::now();
    }

    pub fn today_str() -> String {
        Local::now().format("%Y-%m-%d").to_string()
    }

    fn apply_startup_rule(&mut self, is_new_day_open: bool) {
        let now = Local::now();
        let today = now.date_naive();
        let today_str = schedule::fmt_date(today);
        let before_cutoff = now.time() < self.cutoff_time();
        self.view_date = today;
        self.submit_only = before_cutoff;
        self.data.day(&today_str);
        if is_new_day_open {
            layout::auto_complete_announcements(&mut self.data, &today_str);
        }
        let prev = schedule::prev_school_day(&self.data, today);
        self.prev_hw = self
            .data
            .days
            .get(&schedule::fmt_date(prev))
            .map(|d| {
                d.homework
                    .iter()
                    .filter(|h| h.submit_next && !h.text.trim().is_empty())
                    .cloned()
                    .collect()
            })
            .unwrap_or_default();
    }

    pub fn new(cc: &eframe::CreationContext<'_>) -> App {
        let fonts = load_fonts();
        let layout_font = layout::LayoutFont {
            regular: fonts.regular.clone(),
            bold: fonts.bold.clone(),
        };
        // 字体：TTC 通过 index 加载；注册 regular 与 bold 两个族
        {
            let mut defs = egui::FontDefinitions::default();
            if let Some((bytes, index)) = &fonts.regular_bytes {
                defs.font_data.insert(
                    "cn".to_owned(),
                    std::sync::Arc::new(egui::FontData {
                        font: bytes.clone().into(),
                        index: *index,
                        tweak: egui::FontTweak::default(),
                    }),
                );
                defs.families
                    .entry(egui::FontFamily::Proportional)
                    .or_default()
                    .insert(0, "cn".to_owned());
            }
            if let Some((bytes, index)) = &fonts.bold_bytes {
                defs.font_data.insert(
                    "cn-bold".to_owned(),
                    std::sync::Arc::new(egui::FontData {
                        font: bytes.clone().into(),
                        index: *index,
                        tweak: egui::FontTweak::default(),
                    }),
                );
                defs.families.insert(
                    egui::FontFamily::Name(std::sync::Arc::from("bold")),
                    vec!["cn-bold".to_owned(), "cn".to_owned()],
                );
            }
            cc.egui_ctx.set_fonts(defs);
        }
        // 浅色主题 + 大字号
        let mut style = (*cc.egui_ctx.style()).clone();
        style.text_styles = {
            use egui::TextStyle::*;
            [
                (Heading, egui::FontId::proportional(26.0)),
                (Body, egui::FontId::proportional(19.0)),
                (Monospace, egui::FontId::monospace(17.0)),
                (Button, egui::FontId::proportional(18.0)),
                (Small, egui::FontId::proportional(15.0)),
            ]
            .into()
        };
        style.spacing.item_spacing = egui::vec2(10.0, 10.0);
        style.spacing.button_padding = egui::vec2(14.0, 7.0);
        style.spacing.indent = 22.0;
        let mut v = egui::Visuals::light();
        v.panel_fill = egui::Color32::from_rgb(245, 246, 248);
        v.window_fill = egui::Color32::WHITE;
        v.extreme_bg_color = egui::Color32::from_rgb(250, 251, 253);
        v.faint_bg_color = egui::Color32::from_rgb(238, 241, 246);
        v.widgets.noninteractive.bg_stroke = egui::Stroke::new(1.0, egui::Color32::from_rgb(210, 216, 226));
        v.widgets.inactive.bg_fill = egui::Color32::WHITE;
        v.widgets.inactive.bg_stroke = egui::Stroke::new(1.0, egui::Color32::from_rgb(196, 204, 217));
        v.widgets.hovered.bg_stroke = egui::Stroke::new(1.0, egui::Color32::from_rgb(36, 86, 166));
        v.selection.bg_fill = egui::Color32::from_rgb(36, 86, 166);
        v.selection.stroke = egui::Stroke::new(1.0, egui::Color32::WHITE);
        v.hyperlink_color = egui::Color32::from_rgb(36, 86, 166);
        let rounding = egui::CornerRadius::same(8);
        v.widgets.noninteractive.corner_radius = rounding;
        v.widgets.inactive.corner_radius = rounding;
        v.widgets.hovered.corner_radius = rounding;
        v.widgets.active.corner_radius = rounding;
        v.widgets.open.corner_radius = rounding;
        v.window_corner_radius = egui::CornerRadius::same(12);
        style.visuals = v;
        cc.egui_ctx.set_style(style);

        let exe_dir = store::exe_dir();
        let store = store::Store::open(&exe_dir);
        let (data, recovered) = store.load();
        let badge_image = image::load_from_memory(BADGE_BYTES).expect("班徽解码失败");

        let mut app = App {
            next_ann_id: data.announcements.iter().map(|a| a.id).max().unwrap_or(0) + 1,
            data,
            store,
            exe_dir,
            fonts,
            layout_font,
            badge_image,
            badge_texture: None,
            mode: AppMode::Edit,
            view_date: Local::now().date_naive(),
            submit_only: false,
            dirty: false,
            last_edit: Instant::now(),
            status: String::new(),
            status_until: None,
            font_missing: false,
            recovered,
            today_handled: HashSet::new(),
            prev_hw: Vec::new(),
            show_settings: false,
            show_overview: false,
            show_add_day: false,
            confirm_delete: None,
            new_day: (2026, 10, 1, 0),
            last_time_check: Local::now(),
        };
        if app.fonts.missing {
            app.font_missing = true;
            app.set_status("未找到中文字体".to_string());
        }
        if recovered {
            app.set_status("data.json 损坏或缺失，已从备份恢复".to_string());
        }
        let today_str = App::today_str();
        app.today_handled.insert(today_str.clone());
        app.apply_startup_rule(true);
        app
    }

    pub fn set_status(&mut self, msg: String) {
        self.status = msg;
        self.status_until = Some(Instant::now() + std::time::Duration::from_secs(8));
    }

    pub fn sync_day_rows(&mut self) {
        let key = schedule::fmt_date(self.view_date);
        let hs = schedule::homework_suggestions(&self.data, &key);
        let ss = schedule::speech_suggestions(&self.data, &key);
        let day = self.data.day(&key);
        schedule::sync_homework_rows(day, &hs);
        schedule::sync_speech_rows(day, &ss);
    }

    pub fn save_now(&mut self) {
        match self.store.save(&self.data) {
            Ok(()) => {
                self.dirty = false;
                self.set_status("已保存".to_string());
            }
            Err(e) => self.set_status(format!("保存失败：{}", e)),
        }
    }

    /// 生成 exe同级/家庭作业_YYYY-MM-DD.png（今天的"显示全部"画面）。
    pub fn generate_image(&mut self) -> Result<PathBuf, String> {
        let today = schedule::fmt_date(Local::now().date_naive());
        let view = layout::DayView {
            data: &self.data,
            date: &today,
            submit_only: None,
            show_badge: self.data.settings.show_badge,
            title_suffix: String::new(),
        };
        let cmds = layout::layout_day(&self.layout_font, &view);
        let fonts = export::ExportFonts {
            regular: self.fonts.regular.as_ref(),
            bold: self.fonts.bold.as_ref(),
        };
        let path = self.exe_dir.join(format!("家庭作业_{}.png", today));
        export::export_png(&cmds, &fonts, &self.badge_image, &path)?;
        // 清理旧图片
        if let Ok(rd) = std::fs::read_dir(&self.exe_dir) {
            for e in rd.flatten() {
                let name = e.file_name().to_string_lossy().to_string();
                if name.starts_with("家庭作业_") && name.ends_with(".png") && e.path() != path {
                    std::fs::remove_file(e.path()).ok();
                }
            }
        }
        Ok(path)
    }

    fn maybe_autosave(&mut self) {
        if self.dirty && self.last_edit.elapsed().as_secs_f32() > 1.0 {
            if let Err(e) = self.store.save(&self.data) {
                self.set_status(format!("自动保存失败：{}", e));
            } else {
                self.dirty = false;
            }
        }
    }

    fn maybe_auto_image(&mut self) {
        if self.mode == AppMode::Present || !self.dirty {
            return;
        }
        let interval = self.data.settings.image_interval_secs;
        if interval > 0 && self.last_edit.elapsed().as_secs() >= interval {
            if let Err(e) = self.generate_image() {
                self.set_status(format!("图片生成失败：{}", e));
            }
            self.dirty = false;
        }
    }

    fn check_time(&mut self) {
        let now = Local::now();
        if now.format("%M").to_string() == self.last_time_check.format("%M").to_string() {
            return;
        }
        let crossed_day = now.date_naive() != self.last_time_check.date_naive();
        let cutoff = self.cutoff_time();
        let crossed_cutoff = (self.last_time_check.time() < cutoff) != (now.time() < cutoff);
        self.last_time_check = now;
        if crossed_day {
            let today_str = schedule::fmt_date(now.date_naive());
            if !self.today_handled.contains(&today_str) {
                self.today_handled.insert(today_str);
                self.apply_startup_rule(true);
                self.mark_dirty();
                self.set_status("已自动切换到新的一天".to_string());
            }
        } else if crossed_cutoff {
            self.apply_startup_rule(false);
            self.set_status("已按时间切换显示模式".to_string());
        }
    }
}

impl eframe::App for App {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        if self.badge_texture.is_none() {
            let img = self.badge_image.to_rgba8();
            let size = [img.width() as usize, img.height() as usize];
            let tex = ctx.load_texture("badge", egui::ColorImage::from_rgba_unmultiplied(size, &img), egui::TextureOptions::LINEAR);
            self.badge_texture = Some(tex);
        }
        self.check_time();
        self.maybe_autosave();
        self.maybe_auto_image();
        keys::handle_keys(self, ctx);
        match self.mode {
            AppMode::Edit => edit::show(self, ctx),
            AppMode::Present => present::show(self, ctx),
        }
        if let Some(deadline) = self.status_until {
            if Instant::now() > deadline {
                self.status.clear();
                self.status_until = None;
            }
        }
        ctx.request_repaint_after(std::time::Duration::from_millis(500));
    }

    fn on_exit(&mut self, _gl: Option<&eframe::glow::Context>) {
        let _ = self.store.save(&self.data);
    }
}

fn run_selftest() -> i32 {
    let dir = std::env::temp_dir().join(format!("hw_selftest_{}", std::process::id()));
    std::fs::remove_dir_all(&dir).ok();
    std::fs::create_dir_all(&dir).unwrap();
    let store = store::Store { dir: dir.clone() };
    let mut data = AppData::new();
    let key = "2026-10-01";
    let day = data.day(key);
    day.homework.push(model::HomeworkItem {
        subject: "语文".into(),
        text: "完成第十一课补充习题全部，背诵《三峡》第3-4段".into(),
        submit_next: true,
    });
    day.homework.push(model::HomeworkItem {
        subject: "数学".into(),
        text: "试卷一张（辅导课写，可提前完成）".into(),
        submit_next: false,
    });
    day.homework.push(model::HomeworkItem {
        subject: "英语A".into(),
        text: "家庭反馈本默写U3词单".into(),
        submit_next: true,
    });
    day.homework.push(model::HomeworkItem {
        subject: "英语B".into(),
        text: "重写作文".into(),
        submit_next: true,
    });
    day.homework.push(model::HomeworkItem {
        subject: "物理".into(),
        text: "1.4学评、南外作业本".into(),
        submit_next: true,
    });
    day.homework.push(model::HomeworkItem {
        subject: "历史".into(),
        text: "自批伴你学".into(),
        submit_next: false,
    });
    day.speeches.push(model::SpeechEntry { subject: "语文".into(), students: "12".into() });
    day.speeches.push(model::SpeechEntry { subject: "英语A".into(), students: "5组".into() });
    day.speeches.push(model::SpeechEntry { subject: "英语B".into(), students: "29 37".into() });
    data.announcements.push(model::Announcement {
        id: 1,
        text: "明天早读默写《答谢中书书》".into(),
        created_date: key.into(),
        done: false,
        done_date: None,
    });
    data.announcements.push(model::Announcement {
        id: 2,
        text: "周四选修课开始，注意上课时间地点".into(),
        created_date: key.into(),
        done: false,
        done_date: None,
    });
    if let Err(e) = store.save(&data) {
        eprintln!("selftest save failed: {}", e);
        return 1;
    }
    let (mut loaded, recovered) = store.load();
    if recovered || !loaded.day(key).homework[0].text.contains("补充习题") {
        eprintln!("selftest reload mismatch");
        return 1;
    }
    let fonts = load_fonts();
    let layout_font = layout::LayoutFont {
        regular: fonts.regular.clone(),
        bold: fonts.bold.clone(),
    };
    let view = layout::DayView {
        data: &loaded,
        date: key,
        submit_only: None,
        show_badge: true,
        title_suffix: String::new(),
    };
    let cmds = layout::layout_day(&layout_font, &view);
    let fonts_ref = export::ExportFonts {
        regular: fonts.regular.as_ref(),
        bold: fonts.bold.as_ref(),
    };
    let badge = image::load_from_memory(BADGE_BYTES).unwrap();
    let png = dir.join("selftest.png");
    if let Err(e) = export::export_png(&cmds, &fonts_ref, &badge, &png) {
        eprintln!("selftest export failed: {}", e);
        return 1;
    }
    if !png.exists() {
        eprintln!("selftest png missing");
        return 1;
    }
    println!("selftest ok: {}", png.display());
    if let Ok(out) = std::env::var("SELFTEST_OUT") {
        std::fs::copy(&png, out).ok();
    }
    let _ = std::fs::remove_dir_all(&dir);
    0
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.iter().any(|a| a == "--selftest") {
        std::process::exit(run_selftest());
    }
    let options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default()
            .with_title("每日作业")
            .with_inner_size([1280.0, 800.0])
            .with_min_inner_size([960.0, 600.0]),
        ..Default::default()
    };
    let _ = eframe::run_native("每日作业", options, Box::new(|cc| Ok(Box::new(App::new(cc)))));
}
