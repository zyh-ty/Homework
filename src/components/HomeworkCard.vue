<script setup lang="ts">
import { computed, ref } from "vue";
import { vm } from "../api";
import { draft, saveDraft, ALL_SUBJECTS } from "../draft";
import type { HomeworkItem } from "../types";

const sugg = computed(() => vm.value?.homework_suggestions ?? []);

const extras = computed(() =>
  draft.value.homework.filter((h) => !sugg.value.includes(h.subject))
);

function itemFor(subject: string): HomeworkItem {
  let it = draft.value.homework.find((h) => h.subject === subject);
  if (!it) {
    it = { subject, text: "", submit_next: false };
    draft.value.homework.push(it);
  }
  return it;
}

function onText(subject: string, e: Event) {
  itemFor(subject).text = (e.target as HTMLInputElement).value;
  saveDraft();
}

function onSubmitNext(subject: string, e: Event) {
  itemFor(subject).submit_next = (e.target as HTMLInputElement).checked;
  saveDraft();
}

function textOf(subject: string): string {
  return draft.value.homework.find((h) => h.subject === subject)?.text ?? "";
}

function submitOf(subject: string): boolean {
  return draft.value.homework.find((h) => h.subject === subject)?.submit_next ?? false;
}

function removeExtra(subject: string) {
  draft.value.homework = draft.value.homework.filter((h) => h.subject !== subject);
  saveDraft();
}

const picked = ref("");
const available = computed(() =>
  ALL_SUBJECTS.filter((s) => !sugg.value.includes(s) && !extras.value.some((h) => h.subject === s))
);

function addExtra() {
  if (!picked.value) return;
  itemFor(picked.value);
  picked.value = "";
  saveDraft();
}
</script>

<template>
  <section class="card">
    <h3>
      作业
      <span class="hint">按今天课表预填学科；留空的学科放映时不显示</span>
    </h3>
    <div v-for="s in sugg" :key="s" class="edit-row">
      <span class="sub">{{ s }}</span>
      <input
        type="text"
        :value="textOf(s)"
        placeholder="作业内容…"
        @input="onText(s, $event)"
      />
      <label class="hint" style="white-space: nowrap">
        <input type="checkbox" :checked="submitOf(s)" @change="onSubmitNext(s, $event)" />
        明天交
      </label>
    </div>
    <div v-for="h in extras" :key="h.subject" class="edit-row">
      <span class="sub">{{ h.subject }}</span>
      <input
        type="text"
        :value="h.text"
        placeholder="作业内容…"
        @input="onText(h.subject, $event)"
      />
      <label class="hint" style="white-space: nowrap">
        <input type="checkbox" :checked="h.submit_next" @change="onSubmitNext(h.subject, $event)" />
        明天交
      </label>
      <button class="danger" @click="removeExtra(h.subject)">删除</button>
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
