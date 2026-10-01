<script setup lang="ts">
import { computed, ref } from "vue";
import { vm } from "../api";
import { draft, saveDraft, ALL_SUBJECTS } from "../draft";
import type { SpeechEntry } from "../types";

const sugg = computed(() => vm.value?.speech_suggestions ?? []);
const warn = computed(() => vm.value?.speech_warn ?? false);

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

function addExtra() {
  if (!picked.value) return;
  entryFor(picked.value);
  picked.value = "";
  saveDraft();
}
</script>

<template>
  <section class="card">
    <h3>
      演讲提醒
      <span class="hint">按明天课表预填学科；同学科多学号用空格分隔</span>
    </h3>
    <div v-if="warn" class="warn-banner">⚠ 演讲提醒未填写，请填写明天演讲的学号</div>
    <div v-for="s in sugg" :key="s" class="edit-row">
      <span class="sub">{{ s }}</span>
      <input
        type="text"
        :value="studentsOf(s)"
        placeholder="学号，如：24 33 2"
        @input="onInput(s, $event)"
      />
    </div>
    <div v-for="sp in extras" :key="sp.subject" class="edit-row">
      <span class="sub">{{ sp.subject }}</span>
      <input
        type="text"
        :value="sp.students"
        placeholder="学号，如：24 33 2"
        @input="onInput(sp.subject, $event)"
      />
      <button class="danger" @click="removeExtra(sp.subject)">删除</button>
    </div>
    <div class="edit-row" v-if="available.length">
      <select v-model="picked">
        <option value="" disabled>添加其他学科…</option>
        <option v-for="s in available" :key="s" :value="s">{{ s }}</option>
      </select>
      <button :disabled="!picked" @click="addExtra">添加</button>
    </div>
  </section>
</template>
