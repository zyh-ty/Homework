use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

pub const PERIODS: usize = 9;

pub const SUBJECTS: &[&str] = &[
    "语文", "数学", "英语", "英语A", "英语B", "物理", "历史", "地理", "生物", "政治", "体育", "美术",
    "音乐", "信息", "心理", "劳技", "自习", "班会",
];

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct HomeworkItem {
    pub subject: String,
    pub text: String,
    pub submit_next: bool,
}

impl HomeworkItem {
    pub fn new(subject: &str) -> Self {
        HomeworkItem {
            subject: subject.to_string(),
            text: String::new(),
            submit_next: false,
        }
    }
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct SpeechEntry {
    pub subject: String,
    pub students: String,
}

impl SpeechEntry {
    pub fn new(subject: &str) -> Self {
        SpeechEntry {
            subject: subject.to_string(),
            students: String::new(),
        }
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Announcement {
    pub id: u64,
    pub text: String,
    pub created_date: String,
    pub done: bool,
    pub done_date: Option<String>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Day {
    #[serde(default)]
    pub schedule_override: Vec<Option<String>>,
    #[serde(default)]
    pub homework: Vec<HomeworkItem>,
    #[serde(default)]
    pub speeches: Vec<SpeechEntry>,
    #[serde(default)]
    pub copied_from_weekday: Option<usize>,
}

impl Day {
    pub fn new() -> Self {
        Day {
            schedule_override: vec![None; PERIODS],
            homework: Vec::new(),
            speeches: Vec::new(),
            copied_from_weekday: None,
        }
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Settings {
    #[serde(default)]
    pub data_dir: Option<String>,
    #[serde(default = "default_image_interval")]
    pub image_interval_secs: u64,
    #[serde(default = "default_morning_cutoff")]
    pub morning_cutoff: String,
    #[serde(default = "default_true")]
    pub show_badge: bool,
}

fn default_image_interval() -> u64 {
    60
}
fn default_morning_cutoff() -> String {
    "08:00".to_string()
}
fn default_true() -> bool {
    true
}

impl Default for Settings {
    fn default() -> Self {
        Settings {
            data_dir: None,
            image_interval_secs: default_image_interval(),
            morning_cutoff: default_morning_cutoff(),
            show_badge: true,
        }
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct AppData {
    pub version: u32,
    #[serde(default = "default_weekly_schedule")]
    pub weekly_schedule: Vec<Vec<String>>,
    #[serde(default)]
    pub days: BTreeMap<String, Day>,
    #[serde(default)]
    pub announcements: Vec<Announcement>,
    #[serde(default)]
    pub settings: Settings,
}

pub fn default_weekly_schedule() -> Vec<Vec<String>> {
    let mut v: Vec<Vec<String>> = Vec::new();
    for d in 0..7 {
        let subjects: &[&str] = match d {
            0 => &["语文", "数学", "历史", "物理", "地理", "体育", "美术", "英语", "班会"],
            1 => &["数学", "物理", "英语", "英语", "语文", "自习", "信息", "政治", "体育"],
            2 => &["数学", "语文", "劳技", "英语", "英语", "心理", "数学", "历史", "生物"],
            3 => &["政治", "生物", "数学", "语文", "语文", "英语", "英语", "物理", "体育"],
            4 => &["语文", "英语", "英语", "数学", "体育", "信息", "物理", "地理", "音乐"],
            _ => &[],
        };
        v.push(subjects.iter().map(|s| s.to_string()).collect());
    }
    v
}

impl AppData {
    pub fn new() -> Self {
        AppData {
            version: 1,
            weekly_schedule: default_weekly_schedule(),
            days: BTreeMap::new(),
            announcements: Vec::new(),
            settings: Settings::default(),
        }
    }

    pub fn day(&mut self, date: &str) -> &mut Day {
        self.days.entry(date.to_string()).or_insert_with(Day::new)
    }
}
