use crate::layout::{Align, DrawCmd};
use std::path::Path;
use tiny_skia::{FillRule, Paint, PathBuilder, Pixmap, Transform};

fn paint(color: [u8; 4]) -> Paint<'static> {
    let mut p = Paint::default();
    p.set_color_rgba8(color[0], color[1], color[2], color[3]);
    p.anti_alias = true;
    p
}

pub struct ExportFonts<'a> {
    pub regular: Option<&'a fontdue::Font>,
    pub bold: Option<&'a fontdue::Font>,
}

fn text_width(fonts: &ExportFonts, text: &str, size: f32, bold: bool) -> f32 {
    let font = if bold { fonts.bold.or(fonts.regular) } else { fonts.regular };
    match font {
        Some(f) => {
            let mut w = 0.0;
            for c in text.chars() {
                w += f.metrics(c, size).advance_width;
            }
            w
        }
        None => text.chars().count() as f32 * size,
    }
}

fn draw_text(pixmap: &mut Pixmap, fonts: &ExportFonts, x: f32, y: f32, size: f32, color: [u8; 4], align: Align, bold: bool, text: &str) {
    let font = if bold { fonts.bold.or(fonts.regular) } else { fonts.regular.or(fonts.bold) };
    let w = text_width(fonts, text, size, bold);
    let mut pen_x = match align {
        Align::Left => x,
        Align::Center => x - w / 2.0,
    };
    let font = match font {
        Some(f) => f,
        None => return,
    };
    let baseline = y;
    let (pr, pg, pb, pa) = (color[0], color[1], color[2], color[3]);
    for c in text.chars() {
        let (metrics, bitmap) = font.rasterize(c, size);
        let gx = pen_x + metrics.xmin as f32;
        let gy = baseline + metrics.ymin as f32;
        for row in 0..metrics.height {
            for col in 0..metrics.width {
                let cov = bitmap[row * metrics.width + col];
                if cov == 0 {
                    continue;
                }
                let px = (gx + col as f32) as i32;
                let py = (gy + row as f32) as i32;
                if px < 0 || py < 0 || px >= pixmap.width() as i32 || py >= pixmap.height() as i32 {
                    continue;
                }
                let idx = (py as u32 * pixmap.width() + px as u32) as usize;
                let dst = pixmap.pixels_mut()[idx];
                let a = cov as u32 * pa as u32 / 255;
                let inv = 255 - a;
                let nr = ((pr as u32 * a + dst.red() as u32 * inv) / 255) as u8;
                let ng = ((pg as u32 * a + dst.green() as u32 * inv) / 255) as u8;
                let nb = ((pb as u32 * a + dst.blue() as u32 * inv) / 255) as u8;
                pixmap.pixels_mut()[idx] =
                    tiny_skia::PremultipliedColorU8::from_rgba(nr, ng, nb, 255).unwrap();
            }
        }
        pen_x += metrics.advance_width;
    }
}

fn rounded_rect_path(x: f32, y: f32, w: f32, h: f32, r: f32) -> Option<tiny_skia::Path> {
    let r = r.min(w / 2.0).min(h / 2.0).max(0.0);
    let mut pb = PathBuilder::new();
    let (l, t, rt, b) = (x, y, x + w, y + h);
    pb.move_to(l + r, t);
    pb.line_to(rt - r, t);
    pb.quad_to(rt, t, rt, t + r);
    pb.line_to(rt, b - r);
    pb.quad_to(rt, b, rt - r, b);
    pb.line_to(l + r, b);
    pb.quad_to(l, b, l, b - r);
    pb.line_to(l, t + r);
    pb.quad_to(l, t, l + r, t);
    pb.close();
    pb.finish()
}

/// 把绘制指令渲染为 1920×1080 PNG。
pub fn export_png(
    cmds: &[DrawCmd],
    fonts: &ExportFonts,
    badge: &image::DynamicImage,
    path: &Path,
) -> Result<(), String> {
    let mut pixmap = Pixmap::new(1920, 1080).ok_or("无法创建画布")?;
    let mut badge_pixmap: Option<(Pixmap, u32, u32)> = None;
    {
        let rgba = badge.to_rgba8();
        let (w, h) = (rgba.width(), rgba.height());
        if let Some(mut pm) = Pixmap::new(w, h) {
            for (i, px) in rgba.pixels().enumerate() {
                let a = px[3];
                let f = |c: u8| -> u8 { (c as u32 * a as u32 / 255) as u8 };
                pm.pixels_mut()[i] = tiny_skia::PremultipliedColorU8::from_rgba(
                    f(px[0]), f(px[1]), f(px[2]), a,
                )
                .unwrap();
            }
            badge_pixmap = Some((pm, w, h));
        }
    }

    for cmd in cmds {
        match *cmd {
            DrawCmd::FillRoundRect { x, y, w, h, r, color } => {
                if let Some(path) = rounded_rect_path(x, y, w, h, r) {
                    pixmap.fill_path(&path, &paint(color), FillRule::Winding, Transform::identity(), None);
                }
            }
            DrawCmd::StrokeRoundRect { x, y, w, h, r, width, color } => {
                if let Some(path) = rounded_rect_path(x, y, w, h, r) {
                    let stroke = tiny_skia::Stroke {
                        width,
                        ..Default::default()
                    };
                    pixmap.stroke_path(&path, &paint(color), &stroke, Transform::identity(), None);
                }
            }
            DrawCmd::Text { x, y, size, color, align, bold, ref text } => {
                draw_text(&mut pixmap, fonts, x, y, size, color, align, bold, text);
            }
            DrawCmd::Image { x, y, w, h } => {
                if let Some((ref pm, sw, sh)) = badge_pixmap {
                    let sx = w / sw as f32;
                    let sy = h / sh as f32;
                    let tw = (w as u32).max(1);
                    let th = (h as u32).max(1);
                    if let Some(mut scaled) = Pixmap::new(tw, th) {
                        scaled.draw_pixmap(
                            0,
                            0,
                            pm.as_ref(),
                            &tiny_skia::PixmapPaint::default(),
                            Transform::from_scale(sx, sy),
                            None,
                        );
                        pixmap.draw_pixmap(
                            x as i32,
                            y as i32,
                            scaled.as_ref(),
                            &tiny_skia::PixmapPaint::default(),
                            Transform::identity(),
                            None,
                        );
                    }
                }
            }
        }
    }

    let png = pixmap.encode_png().map_err(|e| e.to_string())?;
    std::fs::write(path, png).map_err(|e| e.to_string())
}
