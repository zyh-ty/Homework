import { ref, watch } from "vue";
import { store, view, cmd } from "./api";
import { emptyDay, type Day } from "./types";

export const draft = ref<Day>(emptyDay());

let pending: { date: string; day: Day } | null = null;
let timer: ReturnType<typeof setTimeout> | undefined;

function flush() {
  if (timer) clearTimeout(timer);
  timer = undefined;
  if (pending) {
    const p = pending;
    pending = null;
    void cmd.setDay(p.date, p.day);
  }
}

watch(
  () => view.date,
  () => {
    flush();
    const d = store.data?.days[view.date];
    draft.value = d ? structuredClone(d) : emptyDay();
  },
  { immediate: true }
);

export function saveDraft() {
  pending = { date: view.date, day: structuredClone(draft.value) };
  clearTimeout(timer);
  timer = setTimeout(flush, 300);
}

export const ALL_SUBJECTS = [
  "语文",
  "数学",
  "英语A",
  "英语B",
  "物理",
  "化学",
  "生物",
  "历史",
  "地理",
  "政治",
  "体育",
  "美术",
  "音乐",
  "信息",
  "心理",
  "劳技",
  "自习",
  "班会",
];
