export interface HomeworkItem {
  subject: string;
  text: string;
  submit_next: boolean;
}

export interface SpeechEntry {
  subject: string;
  students: string;
}

export interface Day {
  schedule_override: (string | null)[];
  homework: HomeworkItem[];
  speeches: SpeechEntry[];
  copied_from_weekday: number | null;
}

export interface Announcement {
  id: number;
  text: string;
  done: boolean;
}

export interface Settings {
  data_dir: string | null;
  image_interval_secs: number;
  morning_cutoff: string;
  show_badge: boolean;
}

export interface AppData {
  version: number;
  weekly_schedule: string[][];
  days: Record<string, Day>;
  announcements: Announcement[];
  settings: Settings;
}

export interface LaunchView {
  date: string;
  submit_only: boolean;
}

export interface StatePayload {
  data: AppData;
  data_dir: string;
  today: string;
  launch: LaunchView;
  notice: string | null;
}

export interface Slot {
  name: string;
  changed: boolean;
}

export interface ViewModel {
  date: string;
  display_date: string;
  weekday: string;
  submit_only: boolean;
  homework_date: string;
  slots: Slot[];
  announcements: Announcement[];
  homework: HomeworkItem[];
  speeches: SpeechEntry[];
  speech_warn: boolean;
  homework_suggestions: string[];
  speech_suggestions: string[];
}

export interface WeekOverview {
  dates: string[];
  rows: Slot[][];
}

export function emptyDay(): Day {
  return {
    schedule_override: Array(9).fill(null),
    homework: [],
    speeches: [],
    copied_from_weekday: null,
  };
}
