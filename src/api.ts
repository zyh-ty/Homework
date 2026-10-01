import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { reactive, ref } from "vue";
import type {
  Announcement,
  AppData,
  Day,
  LaunchView,
  Settings,
  StatePayload,
  ViewModel,
  WeekOverview,
} from "./types";

export const store = reactive({
  data: null as AppData | null,
  dataDir: "",
  today: "",
});

export const view = reactive({
  date: "",
  submitOnly: false,
});

export const vm = ref<ViewModel | null>(null);

export const ui = reactive({
  settingsOpen: false,
  weekOpen: false,
  addDayOpen: false,
  deleteDayOpen: false,
});

export const toastState = reactive({ text: "", key: 0 });
let toastTimer: ReturnType<typeof setTimeout> | undefined;
export function showToast(text: string) {
  toastState.text = text;
  toastState.key++;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => (toastState.text = ""), 2600);
}

function applyPayload(p: StatePayload) {
  store.data = p.data;
  store.dataDir = p.data_dir;
  store.today = p.today;
  if (p.notice) showToast(p.notice);
}

export async function refreshVm() {
  if (!view.date) return;
  vm.value = await invoke<ViewModel>("get_view_model", {
    date: view.date,
    submitOnly: view.submitOnly,
  });
}

export function applyLaunch(l: LaunchView) {
  view.date = l.date;
  view.submitOnly = l.submit_only;
}

export async function initApi(onState: () => void) {
  const p = await invoke<StatePayload>("get_state");
  applyPayload(p);
  applyLaunch(p.launch);
  await refreshVm();
  await listen<StatePayload>("state-changed", async (e) => {
    applyPayload(e.payload);
    await refreshVm();
    onState();
  });
}

export const cmd = {
  setDay: (date: string, day: Day) => invoke("set_day", { date, day }),
  addDay: (date: string, copiedFromWeekday: number | null) =>
    invoke("add_day", { date, copiedFromWeekday }),
  deleteDay: (date: string) => invoke("delete_day", { date }),
  setAnnouncements: (list: Announcement[]) => invoke("set_announcements", { list }),
  addAnnouncement: (text: string) => invoke("add_announcement", { text }),
  setWeeklySchedule: (rows: string[][]) => invoke("set_weekly_schedule", { rows }),
  updateSettings: (settings: Settings) => invoke("update_settings", { settings }),
  chooseDataDir: () => invoke<string | null>("choose_data_dir"),
  saveNow: () => invoke("save_now"),
  setPresenting: (on: boolean) => invoke("set_presenting", { on }),
  exportImage: (bytes: Uint8Array) => invoke<string>("export_image", { bytes }),
  getLaunchView: () => invoke<LaunchView>("get_launch_view"),
  getWeek: (monday: string) => invoke<WeekOverview>("get_week", { monday }),
};
