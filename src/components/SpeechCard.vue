<script setup lang="ts">
import { computed, nextTick, ref } from "vue";
import { vm } from "../api";
import { draft, saveDraft, ALL_SUBJECTS } from "../draft";
import Select from "./ui/Select.vue";
import type { SpeechEntry } from "../types";

const sugg = computed(() => vm.value?.speech_suggestions ?? []);
const warn = computed(() => vm.value?.speech_warn ?? false);

const subjects = computed(() => {
  const out = [...sugg.value];
  for (const s of draft.value.speeches) if (!out.includes(s.subject)) out.push(s.subject);
  return out;
});

const extras = computed(() =>
  draft.value.speeches.filter((s) => !sugg.value.includes(s.subject))
);

function entryFor(subject: string): SpeechEntry {
  let it = draft.value.speeches.find((s) => s.subject === subject);
  if (!it) {
    it = { subject, students: "" };
    draft.value.speeches.push(it);
  }
  return it;
}

function onInput(subject: string, e: Event) {
  entryFor(subject).students = (e.target as HTMLInputElement).value;
  saveDraft();
}

function studentsOf(subject: string): string {
  return draft.value.speeches.find((s) => s.subject === subject)?.students ?? "";
}

function removeExtra(subject: string) {
  draft.value.speeches = draft.value.speeches.filter((s) => s.subject !== subject);
  saveDraft();
}

const picked = ref("");
const available = computed(() =>
  ALL_SUBJECTS.filter((s) => !sugg.value.includes(s) && !extras.value.some((x) => x.subject === s))
);
const pickOptions = computed(() => available.value.map((s) => ({ value: s, label: s })));

function addExtra() {
  if (!picked.value) return;
  entryFor(picked.value);
  picked.value = "";
  saveDraft();
}

const inputRefs = new Map<string, HTMLInputElement>();

function setInputRef(subject: string, el: unknown) {
  if (el) inputRefs.set(subject, el as HTMLInputElement);
  else inputRefs.delete(subject);
}

/** 回车再补一个学科并聚焦 */
function onRowKey(e: KeyboardEvent) {
  if (e.key !== "Enter" || e.ctrlKey || e.metaKey || e.altKey) return;
  e.preventDefault();
  const next = ALL_SUBJECTS.find((s) => !subjects.value.includes(s));
  if (!next) return;
  entryFor(next);
  saveDraft();
  void nextTick(() => inputRefs.get(next)?.focus());
}
</script>

<template>
  <section class="card">
    <h3>
      <span>演讲提醒</span>
      <span class="hint">按明天课表预填学科；同学科多学号用空格分隔；回车补一个学科</span>
    </h3>
    <div v-if="warn" class="warn-banner">⚠ 演讲提醒未填写，请填写明天演讲的学号</div>
    <div class="card-body">
      <div v-for="s in sugg" :key="s" class="edit-row">
        <span class="sub">{{ s }}</span>
        <input
          type="text"
          data-nav="speech"
          :ref="(el) => setInputRef(s, el)"
          :value="studentsOf(s)"
          placeholder="学号"
          @input="onInput(s, $event)"
          @keydown="onRowKey"
        />
      </div>
      <div v-for="sp in extras" :key="sp.subject" class="edit-row">
        <span class="sub">{{ sp.subject }}</span>
        <input
          type="text"
          data-nav="speech"
          :ref="(el) => setInputRef(sp.subject, el)"
          :value="sp.students"
          placeholder="学号"
          @input="onInput(sp.subject, $event)"
          @keydown="onRowKey"
        />
        <button class="danger" @click="removeExtra(sp.subject)">删除</button>
      </div>
    </div>
    <div class="edit-row" v-if="available.length">
      <Select
        v-model="picked"
        class="grow"
        :options="pickOptions"
        placeholder="添加其他学科…"
      />
      <button :disabled="!picked" @click="addExtra">添加</button>
    </div>
  </section>
</template>
