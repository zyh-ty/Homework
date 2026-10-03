use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

pub const PERIODS: usize = 9;

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct HomeworkItem {
    pub subject: String,
    pub text: String,
    pub submit_next: bool,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct SpeechEntry {
    pub subject: String,
    pub students: String,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct Day {
    #[serde(default = "default_override")]
    pub schedule_override: Vec<Option<String>>,
    #[serde(default)]
    pub homework: Vec<HomeworkItem>,
    #[serde(default)]
    pub speeches: Vec<SpeechEntry>,
    #[serde(default)]
    pub copied_from_weekday: Option<usize>,
}

fn default_override() -> Vec<Option<String>> {
    vec![None; PERIODS]
}

impl Default for Day {
    fn default() -> Self {
        Day {
            schedule_override: default_override(),
            homework: Vec::new(),
            speeches: Vec::new(),
            copied_from_weekday: None,
        }
    }
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct Announcement {
    pub id: u64,
    pub text: String,
    pub done: bool,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
#[serde(default)]
pub struct Settings {
    pub data_dir: Option<String>,
    pub image_interval_secs: u64,
    pub morning_cutoff: String,
    pub show_badge: bool,
}

impl Default for Settings {
    fn default() -> Self {
        Settings {
            data_dir: None,
            image_interval_secs: 60,
            morning_cutoff: "08:00".into(),
            show_badge: true,
        }
    }
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
#[serde(default)]
pub struct AppData {
    pub version: u32,
    pub weekly_schedule: Vec<Vec<String>>,
    pub days: BTreeMap<String, Day>,
    pub announcements: Vec<Announcement>,
    pub settings: Settings,
}

impl Default for AppData {
    fn default() -> Self {
        AppData {
            version: 1,
            weekly_schedule: crate::schedule::default_weekly_schedule(),
            days: BTreeMap::new(),
            announcements: Vec::new(),
            settings: Settings::default(),
        }
    }
}

impl AppData {
    pub fn normalize(&mut self) {
        self.weekly_schedule = crate::schedule::normalize_weekly(std::mem::take(&mut self.weekly_schedule));
        for day in self.days.values_mut() {
            day.schedule_override.resize(PERIODS, None);
        }
    }

    pub fn next_announcement_id(&self) -> u64 {
        self.announcements.iter().map(|a| a.id).max().unwrap_or(0) + 1
    }
}
