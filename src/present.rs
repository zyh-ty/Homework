use crate::layout::{Align, DrawCmd};
use crate::App;
use eframe::egui;

fn draw_cmds(app: &mut App, painter: &egui::Painter, cmds: &[DrawCmd]) {
    let rect = painter.clip_rect();
    let scale = (rect.width() / 1920.0).min(rect.height() / 1080.0);
    let ox = rect.left() + (rect.width() - 1920.0 * scale) / 2.0;
    let oy = rect.top() + (rect.height() - 1080.0 * scale) / 2.0;
    let map = |x: f32, y: f32| egui::pos2(ox + x * scale, oy + y * scale);
    // 黑边
    painter.rect_filled(rect, 0.0, egui::Color32::BLACK);
    for cmd in cmds {
        match *cmd {
            DrawCmd::FillRoundRect { x, y, w, h, r, color } => {
                painter.rect_filled(
                    egui::Rect::from_min_size(map(x, y), egui::vec2(w * scale, h * scale)),
                    (r * scale) as f32,
                    to_color(color),
                );
            }
            DrawCmd::StrokeRoundRect { x, y, w, h, r, width, color } => {
                painter.rect_stroke(
                    egui::Rect::from_min_size(map(x, y), egui::vec2(w * scale, h * scale)),
                    (r * scale) as f32,
                    egui::Stroke::new(width * scale, to_color(color)),
                    egui::StrokeKind::Inside,
                );
            }
            DrawCmd::Text { x, y, size, color, align, bold, ref text } => {
                let font_id = egui::FontId::proportional(size * scale);
                let galley = painter.layout_no_wrap(
                    text.clone(),
                    font_id,
                    to_color(color),
                );
                let w = galley.size().x;
                let px = match align {
                    Align::Left => x,
                    Align::Center => x - w / (2.0 * scale),
                };
                painter.galley(map(px, y - size * 0.8), galley, to_color(color));
                let _ = bold;
            }
            DrawCmd::Image { x, y, w, h } => {
                if let Some(tex) = app.badge_texture.clone() {
                    painter.image(
                        tex.id(),
                        egui::Rect::from_min_size(map(x, y), egui::vec2(w * scale, h * scale)),
                        egui::Rect::from_min_max(egui::pos2(0.0, 0.0), egui::pos2(1.0, 1.0)),
                        egui::Color32::WHITE,
                    );
                }
            }
        }
    }
}

fn to_color(c: [u8; 4]) -> egui::Color32 {
    egui::Color32::from_rgba_unmultiplied(c[0], c[1], c[2], c[3])
}

pub fn show(app: &mut App, ctx: &egui::Context) {
    let key = crate::schedule::fmt_date(app.view_date);
    let view = crate::layout::DayView {
        data: &app.data,
        date: &key,
        submit_only: if app.submit_only { Some(&app.prev_hw) } else { None },
        show_badge: app.data.settings.show_badge,
        title_suffix: if app.submit_only { "早上好 · 今天要交".to_string() } else { String::new() },
    };
    let cmds = crate::layout::layout_day(&app.layout_font, &view);
    egui::CentralPanel::default()
        .frame(egui::Frame::NONE.fill(egui::Color32::BLACK))
        .show(ctx, |ui| {
            draw_cmds(app, ui.painter(), &cmds);        });
}
