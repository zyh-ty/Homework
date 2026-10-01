use crate::model::HomeworkItem;
use crate::schedule::{day_schedule, has_override, weekday_cn};
use crate::model::AppData;
use chrono::Datelike;

pub const CANVAS_W: f32 = 1920.0;
pub const CANVAS_H: f32 = 1080.0;

#[derive(Clone, Debug, PartialEq)]
pub enum DrawCmd {
    FillRoundRect { x: f32, y: f32, w: f32, h: f32, r: f32, color: [u8; 4] },
    StrokeRoundRect { x: f32, y: f32, w: f32, h: f32, r: f32, width: f32, color: [u8; 4] },
    Text { x: f32, y: f32, size: f32, color: [u8; 4], align: Align, bold: bool, text: String },
    Image { x: f32, y: f32, w: f32, h: f32 },
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Align {
    Left,
    Center,
}

pub const BG: [u8; 4] = [242, 244, 248, 255];
pub const CARD: [u8; 4] = [255, 255, 255, 255];
pub const CARD_STROKE: [u8; 4] = [226, 230, 238, 255];
pub const PRIMARY: [u8; 4] = [36, 86, 166, 255];
pub const ORANGE: [u8; 4] = [232, 131, 58, 255];
pub const RED: [u8; 4] = [208, 48, 48, 255];
pub const INK: [u8; 4] = [35, 39, 46, 255];
pub const ANN_BG: [u8; 4] = [255, 244, 224, 255];
pub const MUTED: [u8; 4] = [122, 130, 142, 255];

/// 一条展示用作业：编号 + 一至两行文本。
#[derive(Clone, Debug)]
pub struct HwLine {
    pub number: usize,
    pub lines: Vec<String>,
}

/// 把作业条目按编号合并（英语A/B 合占一个编号）。marker=true 时给"明天交"条目加标记。
pub fn merge_homework(items: &[HomeworkItem], filter: Option<&dyn Fn(&HomeworkItem) -> bool>, marker: bool) -> Vec<HwLine> {
    let visible: Vec<&HomeworkItem> = items
        .iter()
        .filter(|h| !h.text.trim().is_empty())
        .filter(|h| filter.map(|f| f(h)).unwrap_or(true))
        .collect();
    let mut out: Vec<HwLine> = Vec::new();
    let mut consumed: Vec<String> = Vec::new();
    let mark = |t: &str, m: bool| -> String {
        if marker && m {
            format!("{}（明天交）", t)
        } else {
            t.to_string()
        }
    };
    let mut i = 0;
    let mut n = 1;
    while i < visible.len() {
        let h = visible[i];
        let is_ab = h.subject == "英语A" || h.subject == "英语B";
        if is_ab {
            if consumed.iter().any(|s| s == &h.subject) {
                i += 1;
                continue;
            }
            let other_sub = if h.subject == "英语A" { "英语B" } else { "英语A" };
            let other = visible.iter().find(|x| x.subject == other_sub);
            consumed.push(h.subject.clone());
            if other.is_some() {
                consumed.push(other_sub.to_string());
            }
            let mut lines = vec![mark(&format!("{}：{}", h.subject, h.text.trim()), h.submit_next)];
            if let Some(o) = other {
                lines.push(mark(&format!("{}：{}", o.subject, o.text.trim()), o.submit_next));
            }
            out.push(HwLine { number: n, lines });
            n += 1;
            i += 1;
        } else {
            out.push(HwLine {
                number: n,
                lines: vec![mark(&format!("{}：{}", h.subject, h.text.trim()), h.submit_next)],
            });
            n += 1;
            i += 1;
        }
    }
    out
}

/// 公告在查看日是否有效。
pub fn announcement_visible(a: &crate::model::Announcement, view_date: &str) -> bool {
    a.created_date.as_str() <= view_date
        && (!a.done || a.done_date.as_deref().map(|d| d > view_date).unwrap_or(false))
}

/// 新的一天以"今天"身份打开时：把 created_date < 今天 且未完成的公告标记完成。
pub fn auto_complete_announcements(data: &mut AppData, today: &str) {
    for a in data.announcements.iter_mut() {
        if !a.done && a.created_date.as_str() < today {
            a.done = true;
            a.done_date = Some(today.to_string());
        }
    }
}

pub struct LayoutFont {
    pub regular: Option<fontdue::Font>,
    pub bold: Option<fontdue::Font>,
}

impl LayoutFont {
    fn advance(&self, text: &str, size: f32, bold: bool) -> f32 {
        let font = if bold { &self.bold } else { &self.regular };
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

    /// 让 sample 这段文字在 [y, y+h] 内视觉垂直居中时的基线位置（按实际字形包围盒计算）。
    pub fn vcenter_baseline(&self, sample: &str, y: f32, h: f32, size: f32, bold: bool) -> f32 {
        let font = if bold { &self.bold } else { &self.regular };
        if let Some(f) = font.as_ref().or(self.regular.as_ref()) {
            let mut top = f32::INFINITY;
            let mut bottom = f32::NEG_INFINITY;
            for c in sample.chars() {
                let (m, _) = f.rasterize(c, size);
                if m.height == 0 {
                    continue;
                }
                top = top.min(m.ymin as f32);
                bottom = bottom.max(m.ymin as f32 + m.height as f32);
            }
            if top.is_finite() {
                return y + h / 2.0 - (top + bottom) / 2.0;
            }
        }
        y + h / 2.0 + size * 0.15
    }

    /// 贪婪换行。
    pub fn wrap(&self, text: &str, size: f32, max_width: f32, bold: bool) -> Vec<String> {
        let mut lines = Vec::new();
        for para in text.split('\n') {
            if para.is_empty() {
                lines.push(String::new());
                continue;
            }
            let mut cur = String::new();
            for c in para.chars() {
                let t = format!("{}{}", cur, c);
                if !cur.is_empty() && self.advance(&t, size, bold) > max_width {
                    lines.push(std::mem::take(&mut cur));
                    cur.push(c);
                } else {
                    cur = t;
                }
            }
            if !cur.is_empty() {
                lines.push(cur);
            }
        }
        if lines.is_empty() {
            lines.push(String::new());
        }
        lines
    }
}

fn text_cmd(x: f32, y: f32, size: f32, color: [u8; 4], align: Align, bold: bool, text: String) -> DrawCmd {
    DrawCmd::Text { x, y, size, color, align, bold, text }
}

pub struct DayView<'a> {
    pub data: &'a AppData,
    pub date: &'a str,
    /// 要交模式：只看 filter_hw 指定的条目（通常为上一上学日要交的作业）。
    pub submit_only: Option<&'a [HomeworkItem]>,
    pub show_badge: bool,
    pub title_suffix: String,
}

/// 生成 1920×1080 的绘制指令。文本 y 坐标一律为基线。
pub fn layout_day(font: &LayoutFont, view: &DayView) -> Vec<DrawCmd> {
    let mut cmds = vec![DrawCmd::FillRoundRect {
        x: 0.0, y: 0.0, w: CANVAS_W, h: CANVAS_H, r: 0.0, color: BG,
    }];

    let data = view.data;
    let d = crate::schedule::parse_date(view.date).unwrap();
    let date_cn = format!("{}.{}.{} {}", d.year(), d.month(), d.day(), weekday_cn(d));

    // ── 页眉 ──
    let pill_h = 84.0;
    let pill_y = 40.0;
    let date_size = 50.0;
    let pill_w = font.advance(&date_cn, date_size, true) + 72.0;
    cmds.push(DrawCmd::FillRoundRect { x: 48.0, y: pill_y, w: pill_w, h: pill_h, r: pill_h / 2.0, color: ORANGE });
    let date_baseline = font.vcenter_baseline(&date_cn, pill_y, pill_h, date_size, true);
    cmds.push(text_cmd(48.0 + pill_w / 2.0, date_baseline, date_size, CARD, Align::Center, true, date_cn));
    if !view.title_suffix.is_empty() {
        cmds.push(text_cmd(48.0 + pill_w + 36.0, font.vcenter_baseline(&view.title_suffix, pill_y, pill_h, 42.0, true), 42.0, PRIMARY, Align::Left, true, view.title_suffix.clone()));
    }
    if view.show_badge {
        cmds.push(DrawCmd::Image { x: CANVAS_W - 48.0 - 110.0, y: 28.0, w: 110.0, h: 110.0 });
    }

    // ── 公告通栏（有内容才显示，高度自适应） ──
    let mut y = pill_y + pill_h + 20.0;
    let anns: Vec<&crate::model::Announcement> = data
        .announcements
        .iter()
        .filter(|a| announcement_visible(a, view.date))
        .collect();
    if !anns.is_empty() {
        let ann_size = 38.0;
        let ann_line_h = ann_size * 1.42;
        let wrapped: Vec<Vec<String>> = anns
            .iter()
            .map(|a| font.wrap(&format!("● {}", a.text), ann_size, CANVAS_W - 96.0 - 64.0, true))
            .collect();
        let total_lines: usize = wrapped.iter().map(|w| w.len()).sum();
        let h = total_lines as f32 * ann_line_h + 40.0;
        cmds.push(DrawCmd::FillRoundRect { x: 48.0, y, w: CANVAS_W - 96.0, h, r: 16.0, color: ANN_BG });
        cmds.push(DrawCmd::StrokeRoundRect { x: 48.0, y, w: CANVAS_W - 96.0, h, r: 16.0, width: 2.5, color: ORANGE });
        let mut ty = y + 20.0 + ann_size * 0.86;
        for lines in &wrapped {
            for l in lines {
                cmds.push(text_cmd(80.0, ty, ann_size, RED, Align::Left, true, l.clone()));
                ty += ann_line_h;
            }
        }
        y += h + 20.0;
    }

    // ── 主体 ──
    let body_y = y + 8.0;
    let body_h = CANVAS_H - 44.0 - body_y;
    let gap = 28.0;
    let left_w = (CANVAS_W - 96.0 - gap) * 0.63;
    let right_x = 48.0 + left_w + gap;
    let right_w = CANVAS_W - 48.0 - right_x;

    let sched = day_schedule(data, view.date);
    let over = has_override(data, view.date);
    let speech_non_empty: Vec<&crate::model::SpeechEntry> = data
        .days
        .get(view.date)
        .map(|d| d.speeches.iter().filter(|s| !s.students.trim().is_empty()).collect())
        .unwrap_or_default();

    let speech_min_h = 260.0f32;
    let speech_h = (body_h * 0.34).max(speech_min_h).min(body_h * 0.5);
    let sched_h = body_h - speech_h - gap;
    let speech_y = body_y + sched_h + gap;

    // ── 右列：今日课表 ──
    cmds.push(DrawCmd::FillRoundRect { x: right_x, y: body_y, w: right_w, h: sched_h, r: 18.0, color: CARD });
    cmds.push(DrawCmd::StrokeRoundRect { x: right_x, y: body_y, w: right_w, h: sched_h, r: 18.0, width: 2.0, color: CARD_STROKE });
    let st_size = 36.0;
    cmds.push(text_cmd(right_x + 32.0, body_y + 28.0 + st_size * 0.86, st_size, PRIMARY, Align::Left, true, "今日课表".into()));
    if over {
        let tw = font.advance("今日课表", st_size, true);
        cmds.push(text_cmd(right_x + 32.0 + tw + 16.0, body_y + 28.0 + st_size * 0.86, 30.0, RED, Align::Left, true, "（调课）".into()));
    }
    cmds.push(DrawCmd::FillRoundRect { x: right_x + 32.0, y: body_y + 82.0, w: right_w - 64.0, h: 3.0, r: 1.5, color: CARD_STROKE });
    let rows_top = body_y + 98.0;
    let rows_h = sched_h - 98.0 - 20.0;
    let row_h = rows_h / 5.0;
    let num_size = (row_h * 0.34).min(30.0);
    let subj_size = (row_h * 0.46).min(44.0);
    let col_w = (right_w - 64.0) / 2.0;
    for i in 0..9 {
        let col = if i < 5 { 0 } else { 1 };
        let row = if i < 5 { i } else { i - 5 } as f32;
        let cx = right_x + 32.0 + col as f32 * col_w;
        let base = font.vcenter_baseline("语文8", rows_top + row * row_h, row_h, subj_size, false);
        let subj = sched.get(i).cloned().unwrap_or_default();
        let ov = data
            .days
            .get(view.date)
            .and_then(|d| d.schedule_override.get(i))
            .cloned()
            .flatten();
        cmds.push(text_cmd(cx, base, num_size, MUTED, Align::Left, false, format!("{}", i + 1)));
        let (color, bold) = if ov.is_some() { (RED, true) } else { (INK, false) };
        cmds.push(text_cmd(cx + 40.0, base, subj_size, color, Align::Left, bold, subj));
    }

    // ── 右列：演讲提醒 ──
    cmds.push(DrawCmd::FillRoundRect { x: right_x, y: speech_y, w: right_w, h: speech_h, r: 18.0, color: CARD });
    cmds.push(DrawCmd::StrokeRoundRect { x: right_x, y: speech_y, w: right_w, h: speech_h, r: 18.0, width: 2.0, color: CARD_STROKE });
    cmds.push(text_cmd(right_x + 32.0, speech_y + 28.0 + st_size * 0.86, st_size, PRIMARY, Align::Left, true, "演讲提醒".into()));
    cmds.push(DrawCmd::FillRoundRect { x: right_x + 32.0, y: speech_y + 82.0, w: right_w - 64.0, h: 3.0, r: 1.5, color: CARD_STROKE });
    if speech_non_empty.is_empty() {
        cmds.push(DrawCmd::StrokeRoundRect { x: right_x + 28.0, y: speech_y + 100.0, w: right_w - 56.0, h: speech_h - 128.0, r: 14.0, width: 3.0, color: RED });
        cmds.push(text_cmd(right_x + right_w / 2.0, font.vcenter_baseline("演讲提醒未填写！", speech_y + 100.0, speech_h - 128.0, 40.0, true), 40.0, RED, Align::Center, true, "演讲提醒未填写！".into()));
    } else {
        let avail = speech_h - 98.0 - 20.0;
        let sp_size = (avail / speech_non_empty.len() as f32 / 1.5).clamp(30.0, 46.0);
        let sp_line_h = sp_size * 1.5;
        let content_h = speech_non_empty.len() as f32 * sp_line_h;
        let mut sy = speech_y + 98.0 + (avail - content_h).max(0.0) / 2.0 + sp_size * 0.86;
        for s in speech_non_empty {
            let subj = format!("{}：", s.subject);
            cmds.push(text_cmd(right_x + 32.0, sy, sp_size, INK, Align::Left, true, subj.clone()));
            let sw = font.advance(&subj, sp_size, true);
            cmds.push(text_cmd(right_x + 32.0 + sw, sy, sp_size, INK, Align::Left, false, s.students.trim().to_string()));
            sy += sp_line_h;
        }
    }

    // ── 左列：作业 ──
    cmds.push(DrawCmd::FillRoundRect { x: 48.0, y: body_y, w: left_w, h: body_h, r: 18.0, color: CARD });
    cmds.push(DrawCmd::StrokeRoundRect { x: 48.0, y: body_y, w: left_w, h: body_h, r: 18.0, width: 2.0, color: CARD_STROKE });
    let hw_title = if view.submit_only.is_some() { "今天要交的作业" } else { "今日作业" };
    let hw_title_size = 40.0;
    cmds.push(text_cmd(48.0 + 36.0, body_y + 30.0 + hw_title_size * 0.86, hw_title_size, PRIMARY, Align::Left, true, hw_title.into()));
    cmds.push(DrawCmd::FillRoundRect { x: 48.0 + 36.0, y: body_y + 88.0, w: left_w - 72.0, h: 3.0, r: 1.5, color: CARD_STROKE });

    let hw_lines: Vec<HwLine> = if let Some(items) = view.submit_only {
        merge_homework(items, None, false)
    } else {
        match data.days.get(view.date) {
            Some(day) => merge_homework(&day.homework, None, false),
            None => Vec::new(),
        }
    };

    let content_top = body_y + 108.0;
    let content_h = body_h - 108.0 - 24.0;
    if hw_lines.is_empty() {
        let msg = if view.submit_only.is_some() { "今天要交的作业已全部交齐" } else { "今天没有作业" };
        cmds.push(text_cmd(48.0 + left_w / 2.0, font.vcenter_baseline(&msg, content_top, content_h, 44.0, false), 44.0, MUTED, Align::Center, false, msg.into()));
        return cmds;
    }

    // 每条作业：编号 + 若干"学科：内容"行
    struct Item {
        number: usize,
        rows: Vec<(String, String)>, // (学科前缀, 内容)
    }
    let items: Vec<Item> = hw_lines
        .iter()
        .map(|hw| {
            let rows = hw
                .lines
                .iter()
                .map(|l| match l.split_once('：') {
                    Some((s, t)) => (format!("{}：", s), t.to_string()),
                    None => (String::new(), l.clone()),
                })
                .collect();
            Item { number: hw.number, rows }
        })
        .collect();
    // 每行对应的"明天交"标记（与 merge_homework 的合并逻辑对齐）
    let flags: Vec<Vec<bool>> = {
        let src: &[HomeworkItem] = if let Some(items) = view.submit_only {
            items
        } else {
            data.days
                .get(view.date)
                .map(|d| d.homework.as_slice())
                .unwrap_or(&[])
        };
        let mut merged: Vec<Vec<bool>> = Vec::new();
        let mut consumed: Vec<String> = Vec::new();
        let visible: Vec<&HomeworkItem> = src.iter().filter(|h| !h.text.trim().is_empty()).collect();
        let mut i = 0;
        while i < visible.len() {
            let h = visible[i];
            let is_ab = h.subject == "英语A" || h.subject == "英语B";
            if is_ab {
                if consumed.iter().any(|s| s == &h.subject) {
                    i += 1;
                    continue;
                }
                let other_sub = if h.subject == "英语A" { "英语B" } else { "英语A" };
                let other = visible.iter().find(|x| x.subject == other_sub);
                consumed.push(h.subject.clone());
                let mut f = vec![h.submit_next];
                if let Some(o) = other {
                    consumed.push(other_sub.to_string());
                    f.push(o.submit_next);
                }
                merged.push(f);
                i += 1;
            } else {
                merged.push(vec![h.submit_next]);
                i += 1;
            }
        }
        merged
    };

    let num_w = 64.0;
    let text_x = 48.0 + 36.0 + num_w;
    let wrap_w = left_w - 36.0 - num_w - 36.0 - 16.0;
    let tag_text = "（明天交）";

    let fits = |size: f32| -> f32 {
        let line_h = size * 1.45;
        let mut total = 0.0f32;
        for item in &items {
            for (s, t) in &item.rows {
                let prefix_w = font.advance(s, size, true);
                let wrapped = font.wrap(t, size, wrap_w - prefix_w, false);
                total += wrapped.len() as f32 * line_h;
            }
            total += size * 0.55;
        }
        total
    };
    let (mut lo, mut hi) = (30.0f32, 62.0f32);
    let mut size = 30.0;
    for _ in 0..14 {
        let mid = (lo + hi) / 2.0;
        if fits(mid) <= content_h {
            size = mid;
            lo = mid;
        } else {
            hi = mid;
        }
    }
    let line_h = size * 1.45;
    let total_h = fits(size);
    let start_y = content_top + (content_h - total_h).max(0.0) / 2.0;
    let mut hy = start_y;

    for (idx, item) in items.iter().enumerate() {
        let num = format!("{}.", item.number);
        let mut first_line = true;
        for (row_i, (s, t)) in item.rows.iter().enumerate() {
            let row_baseline_start = hy + size * 0.86;
            if first_line {
                cmds.push(text_cmd(48.0 + 36.0, row_baseline_start, size, PRIMARY, Align::Left, true, num.clone()));
                first_line = false;
            }
            let prefix_w = font.advance(s, size, true);
            let wrapped = font.wrap(t, size, wrap_w - prefix_w, false);
            let n_wrapped = wrapped.len();
            for (wi, wl) in wrapped.iter().enumerate() {
                let baseline = hy + size * 0.86;
                if wi == 0 && !s.is_empty() {
                    cmds.push(text_cmd(text_x, baseline, size, INK, Align::Left, true, s.clone()));
                }
                let tx = if wi == 0 { text_x + prefix_w } else { text_x };
                cmds.push(text_cmd(tx, baseline, size, INK, Align::Left, false, wl.clone()));
                // 最后一行末尾追加"明天交"标记
                let is_last = wi == n_wrapped - 1;
                if is_last && view.submit_only.is_none() {
                    let flag = flags.get(idx).and_then(|f| f.get(row_i)).copied().unwrap_or(false);
                    if flag {
                        let line_end = tx + font.advance(wl, size, false);
                        let tag_w = font.advance(tag_text, size * 0.82, true);
                        let tag_size = size * 0.82;
                        let tag_baseline = hy + size * 0.86;
                        if line_end + 12.0 + tag_w <= 48.0 + left_w - 36.0 {
                            cmds.push(text_cmd(line_end + 12.0, tag_baseline, tag_size, ORANGE, Align::Left, true, tag_text.into()));
                        } else {
                            hy += line_h;
                            cmds.push(text_cmd(text_x, hy + size * 0.86, tag_size, ORANGE, Align::Left, true, tag_text.into()));
                        }
                    }
                }
                hy += line_h;
            }
        }
        hy += size * 0.55;
    }

    cmds
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{Announcement, AppData, HomeworkItem, SpeechEntry};

    fn item(subject: &str, text: &str) -> HomeworkItem {
        HomeworkItem { subject: subject.into(), text: text.into(), submit_next: false }
    }

    #[test]
    fn english_ab_merge_one_number() {
        let items = vec![
            item("语文", "背书"),
            item("英语A", "Quiz"),
            item("英语B", "阅读"),
            item("数学", "练习册"),
        ];
        let lines = merge_homework(&items, None, false);
        assert_eq!(lines.len(), 3);
        assert_eq!(lines[0].number, 1);
        assert_eq!(lines[1].number, 2);
        assert_eq!(lines[1].lines.len(), 2);
        assert!(lines[1].lines[0].starts_with("英语A"));
        assert!(lines[1].lines[1].starts_with("英语B"));
        assert_eq!(lines[2].number, 3);
    }

    #[test]
    fn english_ab_single_occupies_one_line() {
        let items = vec![item("英语A", "Quiz")];
        let lines = merge_homework(&items, None, false);
        assert_eq!(lines.len(), 1);
        assert_eq!(lines[0].lines.len(), 1);
    }

    #[test]
    fn empty_items_hidden() {
        let items = vec![item("语文", ""), item("数学", "  ")];
        assert!(merge_homework(&items, None, false).is_empty());
    }

    #[test]
    fn announcement_visibility_rules() {
        let a = |created: &str, done: bool, done_date: Option<&str>| Announcement {
            id: 1,
            text: "x".into(),
            created_date: created.into(),
            done,
            done_date: done_date.map(|s| s.into()),
        };
        assert!(announcement_visible(&a("2026-09-30", false, None), "2026-10-01"));
        assert!(!announcement_visible(&a("2026-10-02", false, None), "2026-10-01"));
        // 已完成的，done_date > 查看日 仍可见（历史还原）
        assert!(announcement_visible(&a("2026-09-01", true, Some("2026-10-02")), "2026-10-01"));
        assert!(!announcement_visible(&a("2026-09-01", true, Some("2026-10-01")), "2026-10-01"));
    }

    #[test]
    fn auto_complete_only_past_undone() {
        let mut data = AppData::new();
        data.announcements.push(Announcement {
            id: 1,
            text: "旧".into(),
            created_date: "2026-09-30".into(),
            done: false,
            done_date: None,
        });
        data.announcements.push(Announcement {
            id: 2,
            text: "今天".into(),
            created_date: "2026-10-01".into(),
            done: false,
            done_date: None,
        });
        data.announcements.push(Announcement {
            id: 3,
            text: "已手动完成".into(),
            created_date: "2026-09-30".into(),
            done: true,
            done_date: Some("2026-09-30".into()),
        });
        auto_complete_announcements(&mut data, "2026-10-01");
        assert!(data.announcements[0].done);
        assert_eq!(data.announcements[0].done_date.as_deref(), Some("2026-10-01"));
        assert!(!data.announcements[1].done);
        assert_eq!(data.announcements[2].done_date.as_deref(), Some("2026-09-30"));
    }

    #[test]
    fn speech_empty_shows_warning_in_layout() {
        let mut data = AppData::new();
        let day = data.day("2026-10-01");
        day.speeches.push(SpeechEntry { subject: "语文".into(), students: String::new() });
        let lf = LayoutFont { regular: None, bold: None };
        let view = DayView { data: &data, date: "2026-10-01", submit_only: None, show_badge: false, title_suffix: String::new() };
        let cmds = layout_day(&lf, &view);
        assert!(cmds.iter().any(|c| matches!(c, DrawCmd::Text { text, .. } if text.contains("演讲提醒未填写"))));
        // 非空时不显示警告
        data.days.get_mut("2026-10-01").unwrap().speeches[0].students = "22 23".into();
        let view = DayView { data: &data, date: "2026-10-01", submit_only: None, show_badge: false, title_suffix: String::new() };
        let cmds = layout_day(&lf, &view);
        assert!(!cmds.iter().any(|c| matches!(c, DrawCmd::Text { text, .. } if text.contains("演讲提醒未填写"))));
    }

    #[test]
    fn empty_homework_hidden_panel_content() {
        let data = AppData::new();
        let lf = LayoutFont { regular: None, bold: None };
        let view = DayView { data: &data, date: "2026-10-01", submit_only: None, show_badge: false, title_suffix: String::new() };
        let cmds = layout_day(&lf, &view);
        assert!(cmds.iter().any(|c| matches!(c, DrawCmd::Text { text, .. } if text.contains("没有作业"))));
    }

    #[test]
    fn wrap_greedy() {
        let lf = LayoutFont { regular: None, bold: None };
        let lines = lf.wrap("一二三四五六七八九十", 20.0, 20.0 * 5.0, false);
        assert_eq!(lines.len(), 2);
    }
}
