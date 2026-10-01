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

function onCopyChange(e: Event) {
  const v = (e.target as HTMLSelectElement).value;
  draft.value.copied_from_weekday = v === "" ? null : Number(v);
  saveDraft();
}
</script>

<template>
  <section class="card">
    <h3>
      课表（{{ WEEKDAYS[baseIdx] }}）
      <span class="hint">修改自动标红，改回模版自动取消</span>
    </h3>
    <div class="edit-row">
      <span class="sub">调休</span>
      <select :value="draft.copied_from_weekday ?? ''" @change="onCopyChange">
        <option value="">按当天星期</option>
        <option v-for="(w, i) in WEEKDAYS.slice(0, 5)" :key="i" :value="i">上{{ w }}的课</option>
      </select>
    </div>
    <div v-for="i in 9" :key="i" class="edit-row">
      <span class="sub">{{ i }}</span>
      <input
        type="text"
        class="grow"
        :class="{ overridden: overrideOf(i - 1) !== '' }"
        :value="overrideOf(i - 1)"
        :placeholder="baseOf(i - 1) || '（空）'"
        @input="onInput(i - 1, $event)"
      />
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
