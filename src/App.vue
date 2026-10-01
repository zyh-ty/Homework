<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref } from "vue";
import { listen } from "@tauri-apps/api/event";
import { initApi, store, view, ui, applyLaunch, refreshVm, cmd, toastState, showToast } from "./api";
import { loadBadge } from "./render-canvas";
import { generateTodayImage } from "./image";
import { addDays } from "./utils";
import type { LaunchView } from "./types";
import EditView from "./views/EditView.vue";
import PresentView from "./views/PresentView.vue";

const mode = ref<"edit" | "present">("edit");
const ready = ref(false);

const dayList = computed(() => {
  const set = new Set<string>(Object.keys(store.data?.days ?? {}));
  if (store.today) {
    set.add(store.today);
    set.add(addDays(store.today, 1));
  }
  return [...set].sort();
});

function navDays(delta: number) {
  const list = dayList.value;
  if (list.length === 0) return;
  const i = list.indexOf(view.date);
  const next = i < 0 ? list.indexOf(store.today) : i + delta;
  const clamped = Math.max(0, Math.min(list.length - 1, next));
  view.date = list[clamped];
  view.submitOnly = false;
  void refreshVm();
}

async function goToday() {
  const l = await cmd.getLaunchView();
  applyLaunch(l);
  lastLaunch = l;
  await refreshVm();
}

async function enterPresent() {
  await refreshVm();
  await cmd.setPresenting(true);
  mode.value = "present";
}

async function exitPresent() {
  mode.value = "edit";
  await cmd.setPresenting(false);
}

let lastLaunch: LaunchView | null = null;

async function tickRelocate() {
  if (mode.value === "present") return;
  const l = await cmd.getLaunchView();
  if (!lastLaunch) {
    lastLaunch = l;
    return;
  }
  const crossed = l.date !== lastLaunch.date || l.submit_only !== lastLaunch.submit_only;
  const userFollowsAuto = view.date === lastLaunch.date && view.submitOnly === lastLaunch.submit_only;
  if (crossed && userFollowsAuto) {
    applyLaunch(l);
    await refreshVm();
    showToast(l.submit_only ? "已切换到今天早上（仅显示要交）" : "已切换到今天（显示全部）");
  }
  lastLaunch = l;
}

function onKey(e: KeyboardEvent) {
  const t = e.target as HTMLElement | null;
  const typing =
    !!t && (t.tagName === "INPUT" || t.tagName === "TEXTAREA" || t.tagName === "SELECT" || t.isContentEditable);
  if (mode.value === "present") {
    if (e.key === "Escape" || e.key === "F5") {
      e.preventDefault();
      void exitPresent();
    }
    return;
  }
  if (e.key === "F5") {
    e.preventDefault();
    void enterPresent();
    return;
  }
  if (e.ctrlKey || e.metaKey) {
    const k = e.key.toLowerCase();
    if (k === "s") {
      e.preventDefault();
      void cmd.saveNow().then(() => showToast("已保存"));
    } else if (k === "d") {
      e.preventDefault();
      void generateTodayImage(true);
    } else if (k === "t") {
      e.preventDefault();
      void goToday();
    } else if (k === "k") {
      e.preventDefault();
      ui.weekOpen = true;
    } else if (k === ",") {
      e.preventDefault();
      ui.settingsOpen = true;
    }
    return;
  }
  if (typing) return;
  if (e.key === "ArrowLeft") {
    e.preventDefault();
    navDays(-1);
  } else if (e.key === "ArrowRight") {
    e.preventDefault();
    navDays(1);
  }
}

let timer: ReturnType<typeof setInterval> | undefined;
let unlisten: (() => void) | undefined;

onMounted(async () => {
  await loadBadge();
  await initApi(() => {});
  lastLaunch = await cmd.getLaunchView();
  unlisten = await listen("auto-image-request", () => void generateTodayImage(false));
  timer = setInterval(() => void tickRelocate(), 30_000);
  window.addEventListener("keydown", onKey);
  ready.value = true;
});

onUnmounted(() => {
  clearInterval(timer);
  unlisten?.();
  window.removeEventListener("keydown", onKey);
});
</script>

<template>
  <div v-if="!ready || !store.data" class="loading">加载中…</div>
  <template v-else>
    <PresentView v-if="mode === 'present'" />
    <EditView
      v-else
      :day-list="dayList"
      @present="enterPresent"
      @nav="navDays"
      @today="goToday"
    />
  </template>
  <div v-if="toastState.text" :key="toastState.key" class="toast">{{ toastState.text }}</div>
</template>
