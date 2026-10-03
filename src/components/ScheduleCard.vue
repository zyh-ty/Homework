<script setup lang="ts">
import { computed } from "vue";
import { store, view } from "../api";
import { draft, saveDraft } from "../draft";
import { parseDate } from "../utils";

const WEEKDAYS = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"];

const baseIdx = computed(() => {
  if (draft.value.copied_from_weekday != null) return draft.value.copied_from_weekday;
  return (parseDate(view.date).getDay() + 6) % 7;
});

const title = computed(
  () => `课表（${WEEKDAYS[baseIdx.value]}${draft.value.copied_from_weekday != null ? "·调休" : ""}）`
);

function baseOf(i: number): string {
  return store.data?.weekly_schedule?.[baseIdx.value]?.[i] ?? "";
}

function overrideOf(i: number): string {
  return draft.value.schedule_override[i] ?? "";
}

function onInput(i: number, e: Event) {
  const v = (e.target as HTMLInputElement).value.trim();
  draft.value.schedule_override[i] = v === "" || v === baseOf(i) ? null : v;
  saveDraft();
}

const inputRefs = new Map<number, HTMLInputElement>();

function setInputRef(i: number, el: unknown) {
  if (el) inputRefs.set(i, el as HTMLInputElement);
  else inputRefs.delete(i);
}

/** 回车顺次跳到下一节课 */
function onKey(i: number, e: KeyboardEvent) {
  if (e.key !== "Enter" || e.ctrlKey || e.metaKey || e.altKey) return;
  e.preventDefault();
  const next = inputRefs.get(i + 1);
  next?.focus();
  next?.select();
}
</script>

<template>
  <section class="card">
    <h3>
      <span>{{ title }}</span>
      <span class="hint">修改自动标红，改回模版自动取消；回车跳下一节</span>
    </h3>
    <div class="card-body">
      <div v-for="i in 9" :key="i" class="edit-row">
        <span class="sub">{{ i }}</span>
        <input
          type="text"
          class="grow"
          data-nav="sched"
          :ref="(el) => setInputRef(i - 1, el)"
          :class="{ overridden: overrideOf(i - 1) !== '' }"
          :value="overrideOf(i - 1)"
          :placeholder="baseOf(i - 1) || '（空）'"
          @input="onInput(i - 1, $event)"
          @keydown="onKey(i - 1, $event)"
        />
      </div>
    </div>
  </section>
</template>

<style scoped>
.overridden {
  border-color: var(--red);
  color: var(--red);
  font-weight: bold;
}
</style>
