use crate::{App, AppMode};
use chrono::Duration;
use eframe::egui;

pub fn handle_keys(app: &mut App, ctx: &egui::Context) {
    match app.mode {
        AppMode::Present => {
            let exit = ctx.input(|i| i.key_pressed(egui::Key::F5) || i.key_pressed(egui::Key::Escape));
            if exit {
                app.mode = AppMode::Edit;
                ctx.send_viewport_cmd(egui::ViewportCommand::Fullscreen(false));
                ctx.send_viewport_cmd(egui::ViewportCommand::Decorations(true));
            }
        }
        AppMode::Edit => {
            let focus_in_text = ctx.wants_keyboard_input();
            let (f5, ctrl_t, ctrl_k, ctrl_comma, ctrl_s, ctrl_d, left, right) = ctx.input(|i| {
                (
                    i.key_pressed(egui::Key::F5),
                    i.modifiers.ctrl && i.key_pressed(egui::Key::T),
                    i.modifiers.ctrl && i.key_pressed(egui::Key::K),
                    i.modifiers.ctrl && i.key_pressed(egui::Key::Comma),
                    i.modifiers.ctrl && i.key_pressed(egui::Key::S),
                    i.modifiers.ctrl && i.key_pressed(egui::Key::D),
                    i.key_pressed(egui::Key::ArrowLeft),
                    i.key_pressed(egui::Key::ArrowRight),
                )
            });
            if f5 {
                app.sync_day_rows();
                app.mode = AppMode::Present;
                ctx.send_viewport_cmd(egui::ViewportCommand::Fullscreen(true));
                return;
            }
            if ctrl_t {
                app.submit_only = !app.submit_only;
            }
            if ctrl_k {
                app.show_overview = !app.show_overview;
            }
            if ctrl_comma {
                app.show_settings = !app.show_settings;
            }
            if ctrl_s {
                app.save_now();
                match app.generate_image() {
                    Ok(p) => app.set_status(format!("已保存并生成图片：{}", p.display())),
                    Err(e) => app.set_status(format!("图片生成失败：{}", e)),
                }
            }
            if ctrl_d {
                app.show_add_day = true;
            }
            if !focus_in_text {
                if left {
                    app.view_date -= Duration::days(1);
                    app.sync_day_rows();
                }
                if right {
                    app.view_date += Duration::days(1);
                    app.data.day(&crate::schedule::fmt_date(app.view_date));
                    app.sync_day_rows();
                }
            }
        }
    }
}
