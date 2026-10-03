<script setup lang="ts">
import { computed } from "vue";
import { store, view, vm, refreshVm, openPage } from "../api";
import { generateTodayImage } from "../image";
import { parseDate } from "../utils";
import AnnouncementCard from "../components/AnnouncementCard.vue";
import HomeworkCard from "../components/HomeworkCard.vue";
import SpeechCard from "../components/SpeechCard.vue";
import ScheduleCard from "../components/ScheduleCard.vue";
import Segmented from "../components/ui/Segmented.vue";

defineProps<{ dayList: string[] }>();
const emit = defineEmits<{ present: []; nav: [delta: number]; today: [] }>();

const WD = ["日", "一", "二", "三", "四", "五", "六"];

function chipLabel(d: string): string {
  return `${Number(d.slice(5, 7))}.${Number(d.slice(8, 10))} 周${WD[parseDate(d).getDay()]}`;
}

function pickDay(d: string) {
  view.date = d;
  view.submitOnly = false;
  void refreshVm();
}

const modeOptions = [
  { value: "all", label: "全部" },
  { value: "submit", label: "仅要交" },
];

const mode = computed({
  get: () => (view.submitOnly ? "submit" : "all"),
  set: (v: string) => {
    const wantSubmit = v === "submit";
    if (wantSubmit === view.submitOnly) return;
    // 模式只是显示过滤：页面日不变，避免切换时把正在编辑的草稿切走
    view.submitOnly = wantSubmit;
    void refreshVm();
  },
});
</script>

<template>
  <div class="edit">
    <header class="toolbar">
      <span class="brand">每日作业</span>
      <nav class="days">
        <button
          v-for="d in dayList"
          :key="d"
          class="chip"
          :class="{ today: d === store.today, current: d === view.date }"
          @click="pickDay(d)"
        >
          {{ chipLabel(d) }}
        </button>
      </nav>
      <Segmented v-model="mode" :options="modeOptions" />
      <div class="actions">
        <button title="Ctrl+T" @click="emit('today')">今天</button>
        <button class="primary" title="F5" @click="emit('present')">放映</button>
        <button title="Ctrl+D：生成今天的家庭作业图片" @click="generateTodayImage(true)">出图</button>
        <button title="Ctrl+K" @click="openPage('week')">课表总览</button>
        <button title="Ctrl+," @click="openPage('settings')">设置</button>
      </div>
    </header>
    <main class="cards">
      <AnnouncementCard class="span-all" />
      <HomeworkCard />
      <div class="rightcol">
        <SpeechCard />
        <ScheduleCard />
      </div>
    </main>
  </div>
</template>

<style scoped>
.edit {
  display: flex;
  flex-direction: column;
  height: 100%;
}
.toolbar {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 8px 16px;
  background: #fff;
  border-bottom: 1px solid var(--border);
}
.brand {
  font-weight: bold;
  color: var(--blue);
  font-size: 16px;
  white-space: nowrap;
}
.days {
  flex: 1;
  display: flex;
  gap: 6px;
  overflow-x: auto;
  padding: 2px;
}
.chip {
  white-space: nowrap;
  font-size: 13px;
  padding: 4px 10px;
  border-radius: 999px;
}
.chip.today {
  border-color: var(--blue);
  color: var(--blue);
  font-weight: bold;
}
.chip.current {
  background: var(--blue);
  border-color: var(--blue);
  color: #fff;
}
.actions {
  display: flex;
  gap: 8px;
  white-space: nowrap;
}
.cards {
  flex: 1;
  min-height: 0;
  overflow: auto;
  display: grid;
  grid-template-columns: 1.6fr 1fr;
  /* 第一行按公告卡内容自适应，第二行吃掉剩余高度：卡片内部滚动，页面永不滚动 */
  grid-template-rows: auto minmax(0, 1fr);
  gap: 12px;
  padding: 12px 16px;
}
.span-all {
  grid-column: 1 / -1;
}
/* 演讲提醒与课表上下排布，各自内部两列 */
.rightcol {
  display: flex;
  flex-direction: column;
  gap: 12px;
  min-height: 0;
}
</style>
