use crate::model::{Announcement, AppData, Day, PERIODS};
use chrono::{Datelike, Local, NaiveDate, NaiveTime, Weekday};

pub fn default_weekly_schedule() -> Vec<Vec<String>> {
    let rows: [&[&str]; 7] = [
        &["语文", "数学", "历史", "物理", "地理", "体育", "美术", "英语", "班会"],
        &["数学", "物理", "英语", "英语", "语文", "自习", "信息", "政治", "体育"],
        &["数学", "语文", "劳技", "英语", "英语", "心理", "数学", "历史", "生物"],
        &["政治", "生物", "数学", "语文", "语文", "英语", "英语", "物理", "体育"],
        &["语文", "英语", "英语", "数学", "体育", "信息", "物理", "地理", "音乐"],
        &[],
        &[],
    ];
    normalize_weekly(rows.iter().map(|r| r.iter().map(|s| s.to_string()).collect()).collect())
}

pub fn normalize_weekly(mut rows: Vec<Vec<String>>) -> Vec<Vec<String>> {
    rows.resize(7, Vec::new());
    for row in rows.iter_mut() {
        row.resize(PERIODS, String::new());
    }
    rows
}

pub fn today_string() -> String {
    Local::now().format("%Y-%m-%d").to_string()
}

pub fn parse_date(s: &str) -> Option<NaiveDate> {
    NaiveDate::parse_from_str(s, "%Y-%m-%d").ok()
}

pub fn format_date(d: NaiveDate) -> String {
    d.format("%Y-%m-%d").to_string()
}

pub fn add_days(s: &str, days: i64) -> String {
    parse_date(s)
        .map(|d| format_date(d + chrono::Duration::days(days)))
        .unwrap_or_else(|| s.to_string())
}

/// 0=周一 .. 6=周日
pub fn weekday_index(s: &str) -> Option<usize> {
    let d = parse_date(s)?;
    Some(match d.weekday() {
        Weekday::Mon => 0,
        Weekday::Tue => 1,
        Weekday::Wed => 2,
        Weekday::Thu => 3,
        Weekday::Fri => 4,
        Weekday::Sat => 5,
        Weekday::Sun => 6,
    })
}

pub fn weekday_cn(s: &str) -> String {
    match weekday_index(s) {
        Some(0) => "星期一",
        Some(1) => "星期二",
        Some(2) => "星期三",
        Some(3) => "星期四",
        Some(4) => "星期五",
        Some(5) => "星期六",
        Some(6) => "星期日",
        _ => "",
    }
    .to_string()
}

#[derive(Clone, Debug, PartialEq, serde::Serialize)]
pub struct Slot {
    pub name: String,
    pub changed: bool,
}

/// 合成某天实际课表：调休来源或周模版 + 当日 override（override 节次标 changed）
pub fn effective_schedule(data: &AppData, date: &str) -> Vec<Slot> {
    let day = data.days.get(date);
    let base_idx = day
        .and_then(|d| d.copied_from_weekday)
        .or_else(|| weekday_index(date))
        .unwrap_or(0);
    let base = data.weekly_schedule.get(base_idx).cloned().unwrap_or_default();
    let mut slots = Vec::with_capacity(PERIODS);
    for i in 0..PERIODS {
        let base_name = base.get(i).cloned().unwrap_or_default();
        let ovr = day.and_then(|d| d.schedule_override.get(i).cloned().flatten());
        match ovr {
            Some(v) if v != base_name => slots.push(Slot { name: v, changed: true }),
            _ => slots.push(Slot { name: base_name, changed: false }),
        }
    }
    slots
}

/// 作业建议学科：课表去重，英语拆成 英语A/英语B
pub fn homework_suggestions(slots: &[Slot]) -> Vec<String> {
    let mut out: Vec<String> = Vec::new();
    for s in slots {
        if s.name.is_empty() {
            continue;
        }
        if s.name == "英语" {
            for e in ["英语A", "英语B"] {
                if !out.iter().any(|x| x == e) {
                    out.push(e.to_string());
                }
            }
        } else if !out.iter().any(|x| x == &s.name) {
            out.push(s.name.clone());
        }
    }
    out
}

/// 演讲建议学科：用明天课表
pub fn speech_suggestions(data: &AppData, date: &str) -> Vec<String> {
    let tomorrow = add_days(date, 1);
    homework_suggestions(&effective_schedule(data, &tomorrow))
}

/// 上一个上学日：工作日，或 days 中存在条目的调休上学日
pub fn prev_school_day(data: &AppData, today: &str) -> String {
    let mut d = parse_date(today).unwrap_or_else(|| Local::now().date_naive());
    for _ in 0..14 {
        d -= chrono::Duration::days(1);
        let s = format_date(d);
        let wd = weekday_index(&s).unwrap_or(0);
        if wd < 5 || data.days.contains_key(&s) {
            return s;
        }
    }
    format_date(d)
}

pub fn cutoff_time(s: &str) -> NaiveTime {
    NaiveTime::parse_from_str(s, "%H:%M").unwrap_or_else(|_| NaiveTime::from_hms_opt(8, 0, 0).unwrap())
}

#[derive(Clone, Debug, PartialEq, serde::Serialize)]
pub struct LaunchView {
    pub date: String,
    pub submit_only: bool,
    pub homework_date: String,
}

/// 启动/重定位：早于 cutoff → 只显示要交（作业来自上一上学日）；否则今天全部
pub fn launch_view(data: &AppData, today: &str, now_time: NaiveTime) -> LaunchView {
    if now_time < cutoff_time(&data.settings.morning_cutoff) {
        LaunchView {
            date: today.to_string(),
            submit_only: true,
            homework_date: prev_school_day(data, today),
        }
    } else {
        LaunchView {
            date: today.to_string(),
            submit_only: false,
            homework_date: today.to_string(),
        }
    }
}

/// 公告可见性：创建日 <= 查看日，且未完成或完成日晚于查看日
pub fn announcement_visible(a: &Announcement, view_date: &str) -> bool {
    a.created_date.as_str() <= view_date && (!a.done || a.done_date.as_deref().unwrap_or("") > view_date)
}

/// 每天首次打开今天：把更早创建且未完成的公告自动标记完成
pub fn auto_done_announcements(data: &mut AppData, today: &str) -> bool {
    let mut changed = false;
    for a in data.announcements.iter_mut() {
        if !a.done && a.created_date.as_str() < today {
            a.done = true;
            a.done_date = Some(today.to_string());
            changed = true;
        }
    }
    changed
}

/// 演讲提醒是否完全未填写
pub fn speeches_empty(day: &Day) -> bool {
    day.speeches.iter().all(|s| s.students.trim().is_empty())
}

/// 放映用作业列表：submit_only 时取作业来源日的 submit_next 条目
pub fn present_homework(data: &AppData, homework_date: &str, submit_only: bool) -> Vec<crate::model::HomeworkItem> {
    let day = match data.days.get(homework_date) {
        Some(d) => d,
        None => return Vec::new(),
    };
    day.homework
        .iter()
        .filter(|h| !h.text.trim().is_empty())
        .filter(|h| !submit_only || h.submit_next)
        .cloned()
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{Announcement, HomeworkItem, SpeechEntry};

    fn data() -> AppData {
        AppData::default()
    }

    #[test]
    fn default_weekly_is_7x9() {
        let w = default_weekly_schedule();
        assert_eq!(w.len(), 7);
        for r in &w {
            assert_eq!(r.len(), PERIODS);
        }
        assert_eq!(w[0][0], "语文");
        assert!(w[5].iter().all(|s| s.is_empty()));
        assert!(w[6].iter().all(|s| s.is_empty()));
    }

    #[test]
    fn weekday_helpers() {
        assert_eq!(weekday_index("2026-10-01"), Some(3)); // 周四
        assert_eq!(weekday_cn("2026-10-01"), "星期四");
        assert_eq!(add_days("2026-10-01", 1), "2026-10-02");
        assert_eq!(add_days("2026-10-01", -3), "2026-09-28");
    }

    #[test]
    fn effective_uses_template() {
        let d = data();
        let slots = effective_schedule(&d, "2026-10-01");
        assert_eq!(slots[0].name, "政治");
        assert!(!slots[0].changed);
    }

    #[test]
    fn override_marks_changed() {
        let mut d = data();
        let mut day = Day::default();
        day.schedule_override[0] = Some("数学".into());
        d.days.insert("2026-10-01".into(), day);
        let slots = effective_schedule(&d, "2026-10-01");
        assert_eq!(slots[0].name, "数学");
        assert!(slots[0].changed);
        assert!(!slots[1].changed);
    }

    #[test]
    fn override_same_as_base_not_changed() {
        let mut d = data();
        let mut day = Day::default();
        day.schedule_override[0] = Some("政治".into());
        d.days.insert("2026-10-01".into(), day);
        assert!(!effective_schedule(&d, "2026-10-01")[0].changed);
    }

    #[test]
    fn copied_from_weekday() {
        let mut d = data();
        let day = Day { copied_from_weekday: Some(0), ..Day::default() };
        d.days.insert("2026-10-03".into(), day); // 周六补周一的课
        let slots = effective_schedule(&d, "2026-10-03");
        assert_eq!(slots[0].name, "语文");
    }

    #[test]
    fn suggestions_dedup() {
        let d = data();
        let s = homework_suggestions(&effective_schedule(&d, "2026-10-01")); // 周四
        assert_eq!(s, vec!["政治", "生物", "数学", "语文", "英语A", "英语B", "物理", "体育"]);
    }

    #[test]
    fn suggestions_english_split_once() {
        let d = data();
        let s = homework_suggestions(&effective_schedule(&d, "2026-09-30")); // 周三 两节英语
        let count = s.iter().filter(|x| x.starts_with("英语")).count();
        assert_eq!(count, 2);
        assert!(s.contains(&"英语A".to_string()) && s.contains(&"英语B".to_string()));
    }

    #[test]
    fn speech_uses_tomorrow() {
        let d = data();
        let today = homework_suggestions(&effective_schedule(&d, "2026-10-01"));
        let speech = speech_suggestions(&d, "2026-10-01");
        let friday = homework_suggestions(&effective_schedule(&d, "2026-10-02"));
        assert_eq!(speech, friday);
        assert_ne!(speech, today);
    }

    #[test]
    fn prev_school_day_skips_weekend() {
        let d = data();
        assert_eq!(prev_school_day(&d, "2026-10-05"), "2026-10-02"); // 周一 → 上周五
        assert_eq!(prev_school_day(&d, "2026-10-02"), "2026-10-01");
    }

    #[test]
    fn prev_school_day_uses_makeup() {
        let mut d = data();
        d.days.insert("2026-10-04".into(), Day::default()); // 周日调休上学
        assert_eq!(prev_school_day(&d, "2026-10-05"), "2026-10-04");
    }

    #[test]
    fn launch_before_cutoff() {
        let d = data();
        let t = chrono::NaiveTime::from_hms_opt(7, 30, 0).unwrap();
        let v = launch_view(&d, "2026-10-02", t);
        assert!(v.submit_only);
        assert_eq!(v.date, "2026-10-02");
        assert_eq!(v.homework_date, "2026-10-01");
    }

    #[test]
    fn launch_after_cutoff() {
        let d = data();
        let t = chrono::NaiveTime::from_hms_opt(8, 0, 0).unwrap();
        let v = launch_view(&d, "2026-10-02", t);
        assert!(!v.submit_only);
        assert_eq!(v.homework_date, "2026-10-02");
    }

    #[test]
    fn announcement_visibility() {
        let a = Announcement {
            id: 1,
            text: "x".into(),
            created_date: "2026-09-30".into(),
            done: false,
            done_date: None,
        };
        assert!(announcement_visible(&a, "2026-09-30"));
        assert!(announcement_visible(&a, "2026-10-01"));
        assert!(!announcement_visible(&a, "2026-09-29"));
        let done = Announcement { done: true, done_date: Some("2026-10-02".into()), ..a.clone() };
        assert!(announcement_visible(&done, "2026-10-01")); // 完成日晚于查看日仍可见
        assert!(!announcement_visible(&done, "2026-10-02"));
    }

    #[test]
    fn auto_done_marks_old() {
        let mut d = data();
        d.announcements.push(Announcement {
            id: 1,
            text: "旧".into(),
            created_date: "2026-09-30".into(),
            done: false,
            done_date: None,
        });
        d.announcements.push(Announcement {
            id: 2,
            text: "新".into(),
            created_date: "2026-10-01".into(),
            done: false,
            done_date: None,
        });
        assert!(auto_done_announcements(&mut d, "2026-10-01"));
        assert!(d.announcements[0].done);
        assert_eq!(d.announcements[0].done_date.as_deref(), Some("2026-10-01"));
        assert!(!d.announcements[1].done);
        assert!(!auto_done_announcements(&mut d, "2026-10-01"));
    }

    #[test]
    fn speeches_empty_check() {
        let mut day = Day::default();
        assert!(speeches_empty(&day));
        day.speeches.push(SpeechEntry { subject: "语文".into(), students: "".into() });
        assert!(speeches_empty(&day));
        day.speeches.push(SpeechEntry { subject: "数学".into(), students: "24".into() });
        assert!(!speeches_empty(&day));
    }

    #[test]
    fn present_homework_filters() {
        let mut d = data();
        let day = Day {
            homework: vec![
                HomeworkItem { subject: "语文".into(), text: "背书".into(), submit_next: true },
                HomeworkItem { subject: "数学".into(), text: "练习册".into(), submit_next: false },
                HomeworkItem { subject: "物理".into(), text: "  ".into(), submit_next: true },
            ],
            ..Day::default()
        };
        d.days.insert("2026-10-01".into(), day);
        assert_eq!(present_homework(&d, "2026-10-01", false).len(), 2);
        let sub = present_homework(&d, "2026-10-01", true);
        assert_eq!(sub.len(), 1);
        assert_eq!(sub[0].subject, "语文");
        assert!(present_homework(&d, "2026-10-09", false).is_empty());
    }
}
