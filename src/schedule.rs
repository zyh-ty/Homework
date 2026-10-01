use crate::model::{AppData, Day, SpeechEntry, HomeworkItem, PERIODS, SUBJECTS};
use chrono::{Datelike, NaiveDate};

pub fn parse_date(s: &str) -> Option<NaiveDate> {
    NaiveDate::parse_from_str(s, "%Y-%m-%d").ok()
}

pub fn fmt_date(d: NaiveDate) -> String {
    d.format("%Y-%m-%d").to_string()
}

pub const WEEKDAY_CN: &[&str] = &["星期一", "星期二", "星期三", "星期四", "星期五", "星期六", "星期日"];

pub fn weekday_cn(d: NaiveDate) -> &'static str {
    WEEKDAY_CN[d.weekday().num_days_from_monday() as usize]
}

pub fn weekday_index(d: NaiveDate) -> usize {
    d.weekday().num_days_from_monday() as usize
}

/// 一天的 9 节课：override 优先，否则用周模版。
pub fn day_schedule(data: &AppData, date: &str) -> Vec<String> {
    let day = data.days.get(date);
    let weekday = parse_date(date).map(weekday_index).unwrap_or(0);
    (0..PERIODS)
        .map(|i| {
            if let Some(d) = day {
                if let Some(Some(s)) = d.schedule_override.get(i) {
                    return s.clone();
                }
            }
            data.weekly_schedule
                .get(weekday)
                .and_then(|v| v.get(i))
                .cloned()
                .unwrap_or_default()
        })
        .collect()
}

/// 当天是否有调课覆盖。
pub fn has_override(data: &AppData, date: &str) -> bool {
    data.days
        .get(date)
        .map(|d| d.schedule_override.iter().any(|o| o.is_some()))
        .unwrap_or(false)
}

/// 课表去重学科建议；"英语"展开为 英语A/英语B。
pub fn suggested_subjects(schedule: &[String]) -> Vec<String> {
    let mut out: Vec<String> = Vec::new();
    let mut push = |s: &str| {
        if !out.iter().any(|x| x == s) {
            out.push(s.to_string());
        }
    };
    for s in schedule {
        if s == "英语" {
            push("英语A");
            push("英语B");
        } else if !s.is_empty() {
            push(s);
        }
    }
    out
}

/// 其余可手动添加的学科（建议行之外的）。
pub fn remaining_subjects(suggested: &[String]) -> Vec<&'static str> {
    SUBJECTS
        .iter()
        .copied()
        .filter(|s| !suggested.iter().any(|x| x == s))
        .collect()
}

/// 确保 day.homework 覆盖建议学科（在末尾追加空行）；已有内容的行保留。
pub fn sync_homework_rows(day: &mut Day, suggested: &[String]) {
    for s in suggested {
        if !day.homework.iter().any(|h| h.subject == *s) {
            day.homework.push(HomeworkItem::new(s));
        }
    }
}

pub fn sync_speech_rows(day: &mut Day, suggested: &[String]) {
    for s in suggested {
        if !day.speeches.iter().any(|h| h.subject == *s) {
            day.speeches.push(SpeechEntry::new(s));
        }
    }
}

/// 返回当天作业建议学科（含调课联动）。
pub fn homework_suggestions(data: &AppData, date: &str) -> Vec<String> {
    suggested_subjects(&day_schedule(data, date))
}

/// 演讲建议来自明天的课表。
pub fn speech_suggestions(data: &AppData, date: &str) -> Vec<String> {
    let tomorrow = match parse_date(date) {
        Some(d) => d.succ_opt().unwrap_or(d),
        None => return Vec::new(),
    };
    suggested_subjects(&day_schedule(data, &fmt_date(tomorrow)))
}

/// 调休新增一天：按来源周几的课写入 schedule_override（视为调课）。
pub fn add_extra_day(data: &mut AppData, date: NaiveDate, from_weekday: usize) {
    let mut day = Day::new();
    day.copied_from_weekday = Some(from_weekday);
    if let Some(tpl) = data.weekly_schedule.get(from_weekday) {
        for i in 0..PERIODS {
            day.schedule_override[i] = tpl.get(i).cloned().filter(|s| !s.is_empty());
        }
    }
    data.days.insert(fmt_date(date), day);
}

pub fn remove_day(data: &mut AppData, date: &str) {
    data.days.remove(date);
}

/// 本周周一（以查看日所在周为准）。
pub fn week_monday(d: NaiveDate) -> NaiveDate {
    d - chrono::Duration::days(d.weekday().num_days_from_monday() as i64)
}

/// 上一上学日：days 中今天之前最近的一天；没有则今天。
pub fn prev_school_day(data: &AppData, today: NaiveDate) -> NaiveDate {
    data.days
        .keys()
        .filter_map(|k| parse_date(k))
        .filter(|d| *d < today)
        .max()
        .unwrap_or(today)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn english_splits_into_a_b() {
        let sched = vec!["语文".to_string(), "英语".to_string(), "英语".to_string(), "数学".to_string()];
        let s = suggested_subjects(&sched);
        assert_eq!(s, vec!["语文", "英语A", "英语B", "数学"]);
    }

    #[test]
    fn override_links_to_suggestions() {
        let mut data = AppData::new();
        let d = NaiveDate::from_ymd_opt(2026, 10, 5).unwrap(); // 周一
        let key = fmt_date(d);
        data.day(&key).schedule_override[0] = Some("体育".to_string());
        let s = homework_suggestions(&data, &key);
        assert_eq!(s[0], "体育");
        assert_eq!(s.iter().filter(|x| *x == "语文").count(), 0);
        assert!(has_override(&data, &key));
    }

    #[test]
    fn extra_day_copies_schedule() {
        let mut data = AppData::new();
        let d = NaiveDate::from_ymd_opt(2026, 10, 10).unwrap(); // 周六
        add_extra_day(&mut data, d, 0);
        let key = fmt_date(d);
        let sched = day_schedule(&data, &key);
        assert_eq!(sched[0], "语文");
        assert!(has_override(&data, &key));
        assert_eq!(data.days[&key].copied_from_weekday, Some(0));
        remove_day(&mut data, &key);
        assert!(!data.days.contains_key(&key));
    }

    #[test]
    fn speech_uses_tomorrow() {
        let data = AppData::new();
        let d = NaiveDate::from_ymd_opt(2026, 10, 5).unwrap(); // 周一
        let s = speech_suggestions(&data, &fmt_date(d));
        // 明天周二：数学 物理 英语 英语 语文 自习 信息 政治 体育
        assert!(s.contains(&"英语A".to_string()));
        assert!(s.contains(&"自习".to_string()));
    }
}
