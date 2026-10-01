import { ref, watch } from "vue";
import { store, view, cmd } from "./api";
import { emptyDay, type Day } from "./types";

export const draft = ref<Day>(emptyDay());
let timer: ReturnType<typeof setTimeout> | undefined;

function load() {
  const d = store.data?.days[view.date];
  draft.value = d ? structuredClone(d) : emptyDay();
}

watch(() => view.date, load, { immediate: true });

export function reloadDraft() {
  load();
}

export function saveDraft() {
  clearTimeout(timer);
  timer = setTimeout(() => {
    void cmd.setDay(view.date, structuredClone(draft.value));
  }, 300);
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
