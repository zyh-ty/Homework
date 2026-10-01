use crate::model::HomeworkItem;
use crate::schedule::{day_schedule, has_override, weekday_cn};
use crate::model::AppData;

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
    Right,
}

pub const BG: [u8; 4] = [245, 246, 248, 255];
pub const CARD: [u8; 4] = [255, 255, 255, 255];
pub const PRIMARY: [u8; 4] = [46, 90, 172, 255];
pub const ORANGE: [u8; 4] = [232, 131, 58, 255];
pub const RED: [u8; 4] = [208, 48, 48, 255];
pub const INK: [u8; 4] = [34, 38, 43, 255];
pub const ANN_BG: [u8; 4] = [255, 247, 230, 255];
pub const MUTED: [u8; 4] = [120, 128, 138, 255];

/// 一条展示用作业：编号 + 一至两行文本。
#[derive(Clone, Debug)]
pub struct HwLine {
    pub number: usize,
    pub lines: Vec<String>,
    pub submit_next: bool,
}

/// 把作业条目按编号合并（英语A/B 合占一个编号）。
pub fn merge_homework(items: &[HomeworkItem], filter: Option<&dyn Fn(&HomeworkItem) -> bool>) -> Vec<HwLine> {
    let visible: Vec<&HomeworkItem> = items
        .iter()
        .filter(|h| !h.text.trim().is_empty())
        .filter(|h| filter.map(|f| f(h)).unwrap_or(true))
        .collect();
    let mut out: Vec<HwLine> = Vec::new();
    let mut i = 0;
    let mut n = 1;
    while i < visible.len() {
        let h = visible[i];
        let is_ab = h.subject == "英语A" || h.subject == "英语B";
        if is_ab {
            let other_sub = if h.subject == "英语A" { "英语B" } else { "英语A" };
            let other = visible.iter().find(|x| x.subject == other_sub);
            let mut lines = vec![format!("{}：{}", h.subject, h.text.trim())];
            if let Some(o) = other {
                lines.push(format!("{}：{}", o.subject, o.text.trim()));
            }
            out.push(HwLine {
                number: n,
                lines,
                submit_next: h.submit_next,
            });
            n += 1;
            i += 1;
        } else {
            out.push(HwLine {
                number: n,
                lines: vec![format!("{}：{}", h.subject, h.text.trim())],
                submit_next: h.submit_next,
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
    fn metrics_for(&self, size: f32, bold: bool) -> (f32, f32) {
        let font = if bold { &self.bold } else { &self.regular };
        match font {
            Some(f) => {
                let m = f.horizontal_line_metrics(size).unwrap();
                (m.ascent, m.descent)
            }
            None => (size * 0.88, -size * 0.24),
        }
    }

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

/// 生成 1920×1080 的绘制指令。
pub fn layout_day(font: &LayoutFont, view: &DayView) -> Vec<DrawCmd> {
    let mut cmds = vec![DrawCmd::FillRoundRect {
        x: 0.0, y: 0.0, w: CANVAS_W, h: CANVAS_H, r: 0.0, color: BG,
    }];

    let data = view.data;
    let d = crate::schedule::parse_date(view.date).unwrap();
    let date_cn = format!("{}.{}.{} {}", d.year(), d.month(), d.day(), weekday_cn(d));

    // 页眉
    let header_h = 120.0;
    let pill_w = 30.0 + font.advance(&date_cn, 46.0, true);
    cmds.push(DrawCmd::FillRoundRect { x: 40.0, y: 30.0, w: pill_w, h: 64.0, r: 32.0, color: ORANGE });
    cmds.push(text_cmd(40.0 + pill_w / 2.0, 62.0, 46.0, CARD, Align::Center, true, date_cn.clone()));
    if !view.title_suffix.is_empty() {
        cmds.push(text_cmd(40.0 + pill_w + 24.0, 62.0, 34.0, PRIMARY, Align::Left, true, view.title_suffix.clone()));
    }
    if view.show_badge {
        cmds.push(DrawCmd::Image { x: CANVAS_W - 40.0 - 72.0, y: 20.0, w: 72.0, h: 72.0 });
    }

    // 公告通栏
    let mut y = header_h;
    let anns: Vec<&crate::model::Announcement> = data
        .announcements
        .iter()
        .filter(|a| announcement_visible(a, view.date))
        .collect();
    let ann_size = 30.0;
    if !anns.is_empty() {
        let wrapped: Vec<Vec<String>> = anns
            .iter()
            .map(|a| font.wrap(&format!("• {}", a.text), ann_size, CANVAS_W - 220.0, false))
            .collect();
        let line_h = ann_size * 1.45;
        let total_lines: usize = wrapped.iter().map(|w| w.len()).sum();
        let h = 24.0 + total_lines as f32 * line_h;
        cmds.push(DrawCmd::FillRoundRect { x: 40.0, y, w: CANVAS_W - 80.0, h, r: 12.0, color: ANN_BG });
        cmds.push(DrawCmd::StrokeRoundRect { x: 40.0, y, w: CANVAS_W - 80.0, h, r: 12.0, width: 2.0, color: ORANGE });
        let mut ty = y + 12.0 + ann_size;
        for lines in &wrapped {
            for l in lines {
                cmds.push(text_cmd(64.0, ty, ann_size, RED, Align::Left, false, l.clone()));
                ty += line_h;
            }
        }
        y += h + 16.0;
    }

    // 主体区域
    let body_y = y + 8.0;
    let body_h = CANVAS_H - body_y - 30.0;
    let gap = 24.0;
    let left_w = (CANVAS_W - 80.0 - gap) * 0.62;
    let right_x = 40.0 + left_w + gap;
    let right_w = CANVAS_W - 40.0 - right_x;

    // 右列：今日课表 + 演讲提醒
    let sched = day_schedule(data, view.date);
    let over = has_override(data, view.date);
    let speech_non_empty: Vec<&crate::model::SpeechEntry> = data
        .days
        .get(view.date)
        .map(|d| d.speeches.iter().filter(|s| !s.students.trim().is_empty()).collect())
        .unwrap_or_default();
    let speech_panel_ratio = if speech_non_empty.is_empty() { 0.32 } else { 0.36 };
    let sched_h = body_h * (1.0 - speech_panel_ratio) - 12.0;
    let speech_y = body_y + sched_h + 12.0;
    let speech_h = body_h - sched_h - 12.0;

    // 课表卡片
    cmds.push(DrawCmd::FillRoundRect { x: right_x, y: body_y, w: right_w, h: sched_h, r: 12.0, color: CARD });
    let sched_title = if over { "今日课表（调课）" } else { "今日课表" };
    cmds.push(text_cmd(right_x + 20.0, body_y + 38.0, 30.0, PRIMARY, Align::Left, true, sched_title.into()));
    let sched_size = 27.0f32.min((sched_h - 90.0) / 9.0 / 1.5);
    let col_w = (right_w - 40.0) / 2.0;
    let row_h = (sched_h - 70.0) / 9.0;
    for i in 0..9 {
        let cx = right_x + 20.0 + if i < 5 { 0.0 } else { col_w };
        let cy = body_y + 66.0 + (i % 5) as f32 * row_h;
        let subj = sched.get(i).cloned().unwrap_or_default();
        let color = if over {
            let ov = data.days.get(view.date).and_then(|d| d.schedule_override.get(i)).cloned().flatten();
            match ov {
                Some(_) => RED,
                None => INK,
            }
        } else {
            INK
        };
        cmds.push(text_cmd(cx, cy + sched_size * 0.8, sched_size, MUTED, Align::Left, false, format!("{} {}", i + 1, "")));
        cmds.push(text_cmd(cx + 36.0, cy + sched_size * 0.8, sched_size, color, Align::Left, color == RED, subj));
    }

    // 演讲卡片
    cmds.push(DrawCmd::FillRoundRect { x: right_x, y: speech_y, w: right_w, h: speech_h, r: 12.0, color: CARD });
    cmds.push(text_cmd(right_x + 20.0, speech_y + 38.0, 30.0, PRIMARY, Align::Left, true, "演讲提醒".into()));
    if speech_non_empty.is_empty() {
        let warn = "⚠ 演讲提醒未填写";
        cmds.push(DrawCmd::StrokeRoundRect { x: right_x + 16.0, y: speech_y + 56.0, w: right_w - 32.0, h: speech_h - 72.0, r: 12.0, width: 3.0, color: RED });
        cmds.push(text_cmd(right_x + right_w / 2.0, speech_y + 56.0 + (speech_h - 72.0) / 2.0 + 14.0, 34.0, RED, Align::Center, true, warn.into()));
    } else {
        let sp_size = 28.0f32.min((speech_h - 90.0) / speech_non_empty.len().max(1) as f32 / 1.5);
        let mut sy = speech_y + 56.0 + sp_size;
        for s in speech_non_empty {
            let t = if s.students.trim().is_empty() { s.subject.clone() } else { format!("{}：{}", s.subject, s.students.trim()) };
            for l in font.wrap(&t, sp_size, right_w - 48.0, false) {
                cmds.push(text_cmd(right_x + 24.0, sy, sp_size, INK, Align::Left, false, l));
                sy += sp_size * 1.5;
            }
        }
    }

    // 左列：作业
    cmds.push(DrawCmd::FillRoundRect { x: 40.0, y: body_y, w: left_w, h: body_h, r: 12.0, color: CARD });
    let hw_title = if view.submit_only.is_some() { "要交的作业" } else { "今日作业" };
    cmds.push(text_cmd(64.0, body_y + 42.0, 34.0, PRIMARY, Align::Left, true, hw_title.into()));

    let hw_lines: Vec<HwLine> = if let Some(items) = view.submit_only {
        merge_homework(items, None)
    } else {
        match data.days.get(view.date) {
            Some(day) => merge_homework(&day.homework, None),
            None => Vec::new(),
        }
    };

    if hw_lines.is_empty() {
        let msg = if view.submit_only.is_some() { "今天要交的作业已全部交齐 🎉" } else { "今天没有作业 🎉" };
        cmds.push(text_cmd(40.0 + left_w / 2.0, body_y + body_h / 2.0, 40.0, MUTED, Align::Center, false, msg.into()));
    } else {
        // 二分查找刚好放得下的字号
        let max_size = 44.0f32;
        let min_size = 22.0f32;
        let avail_h = body_h - 90.0;
        let num_w = 60.0;
        let fits = |size: f32| -> bool {
            let line_h = size * 1.5;
            let mut total = 0.0f32;
            for hw in &hw_lines {
                for (i, l) in hw.lines.iter().enumerate() {
                    let prefix = if i == 0 { format!("{}. ", hw.number) } else { String::new() };
                    let wrapped = font.wrap(&format!("{}{}", prefix, l), size, left_w - 80.0 - num_w, false);
                    total += wrapped.len() as f32 * line_h;
                }
                total += size * 0.35;
            }
            total <= avail_h
        };
        let mut lo = min_size;
        let mut hi = max_size;
        let mut best = min_size;
        for _ in 0..12 {
            let mid = (lo + hi) / 2.0;
            if fits(mid) {
                best = mid;
                lo = mid;
            } else {
                hi = mid;
            }
        }
        let size = best;
        let line_h = size * 1.5;
        let mut hy = body_y + 84.0 + size;
        for hw in &hw_lines {
            for (i, l) in hw.lines.iter().enumerate() {
                let prefix = if i == 0 { format!("{}. ", hw.number) } else { String::new() };
                let wrapped = font.wrap(&format!("{}{}", prefix, l), size, left_w - 80.0 - num_w, false);
                for wl in &wrapped {
                    if i == 0 && wl.starts_with(&format!("{}.", hw.number)) {
                        cmds.push(text_cmd(64.0, hy, size, PRIMARY, Align::Left, true, wl.clone()));
                    } else {
                        let indent = if i == 0 { 0.0 } else { num_w };
                        cmds.push(text_cmd(64.0 + indent, hy, size, INK, Align::Left, false, wl.clone()));
                    }
                    hy += line_h;
                }
            }
            hy += size * 0.35;
        }
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
        let lines = merge_homework(&items, None);
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
        let lines = merge_homework(&items, None);
        assert_eq!(lines.len(), 1);
        assert_eq!(lines[0].lines.len(), 1);
    }

    #[test]
    fn empty_items_hidden() {
        let items = vec![item("语文", ""), item("数学", "  ")];
        assert!(merge_homework(&items, None).is_empty());
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
