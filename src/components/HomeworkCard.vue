<script setup lang="ts">
import { computed, nextTick, ref } from "vue";
import { vm } from "../api";
import { draft, saveDraft, ALL_SUBJECTS } from "../draft";
import Select from "./ui/Select.vue";
import type { HomeworkItem } from "../types";

const sugg = computed(() => vm.value?.homework_suggestions ?? []);

const subjects = computed(() => {
  const out = [...sugg.value];
  for (const h of draft.value.homework) if (!out.includes(h.subject)) out.push(h.subject);
  return out;
});

function rowsOf(subject: string): (HomeworkItem | null)[] {
  const list = draft.value.homework.filter((h) => h.subject === subject);
  return list.length ? list : [null];
}

const groups = computed(() => subjects.value.map((subject) => ({ subject, rows: rowsOf(subject) })));

/** 空占位行首次输入/勾选时才真正落库 */
function materialize(subject: string, row: HomeworkItem | null): HomeworkItem {
  if (row) return row;
  draft.value.homework.push({ subject, text: "", submit_next: false });
  return draft.value.homework[draft.value.homework.length - 1];
}

function onText(subject: string, row: HomeworkItem | null, e: Event) {
  materialize(subject, row).text = (e.target as HTMLInputElement).value;
  saveDraft();
}

function onSubmit(subject: string, row: HomeworkItem | null, e: Event) {
  materialize(subject, row).submit_next = (e.target as HTMLInputElement).checked;
  saveDraft();
}

function addEntry(subject: string) {
  draft.value.homework.push({ subject, text: "", submit_next: false });
  saveDraft();
}

function removeEntry(row: HomeworkItem) {
  const i = draft.value.homework.indexOf(row);
  if (i >= 0) draft.value.homework.splice(i, 1);
  saveDraft();
}

const inputRefs = new Map<string, HTMLInputElement>();

function setInputRef(key: string, el: unknown) {
  if (el) inputRefs.set(key, el as HTMLInputElement);
  else inputRefs.delete(key);
}

/** Enter 紧接着加一条并聚焦；Ctrl+Enter 切换本条「明天交」 */
function onRowKey(subject: string, row: HomeworkItem | null, e: KeyboardEvent) {
  if (e.key !== "Enter") return;
  if (e.ctrlKey || e.metaKey) {
    e.preventDefault();
    const item = materialize(subject, row);
    item.submit_next = !item.submit_next;
    saveDraft();
    return;
  }
  if (e.altKey) return;
  e.preventDefault();
  addEntry(subject);
  const index = draft.value.homework.filter((h) => h.subject === subject).length - 1;
  void nextTick(() => {
    const el = inputRefs.get(`${subject}:${index}`);
    el?.focus();
    el?.select();
  });
}

const picked = ref("");
const available = computed(() => ALL_SUBJECTS.filter((s) => !subjects.value.includes(s)));
const pickOptions = computed(() => available.value.map((s) => ({ value: s, label: s })));

function addSubject() {
  if (!picked.value) return;
  const s = picked.value;
  picked.value = "";
  addEntry(s);
}
</script>

<template>
  <section class="card">
    <h3>
      <span>作业</span>
      <span class="hint">一个学科可加多条，每条单独勾「明天交」；回车加一条，Ctrl+回车切换明天交；留空不显示</span>
    </h3>
    <div class="hw-list">
      <div v-for="g in groups" :key="g.subject" class="hw-group">
        <div class="hw-label">{{ g.subject }}</div>
        <div class="hw-rows">
          <div v-for="(row, i) in g.rows" :key="i" class="edit-row hw-row">
            <span class="idx" :style="{ visibility: g.rows.length > 1 ? 'visible' : 'hidden' }">{{ i + 1 }}</span>
            <input
              type="text"
              data-nav="hw"
              :ref="(el) => setInputRef(`${g.subject}:${i}`, el)"
              :value="row?.text ?? ''"
              placeholder="作业内容…"
              @input="onText(g.subject, row, $event)"
              @keydown="onRowKey(g.subject, row, $event)"
            />
            <label class="hint nowrap">
              <input
                type="checkbox"
                :checked="row?.submit_next ?? false"
                @change="onSubmit(g.subject, row, $event)"
              />
              明天交
            </label>
            <button
              class="danger"
              :style="{ visibility: row ? 'visible' : 'hidden' }"
              @click="row && removeEntry(row)"
            >
              删除
            </button>
            <button
              v-if="i === g.rows.length - 1"
              class="add-entry"
              :title="`给${g.subject}再加一条作业（回车）`"
              @click="addEntry(g.subject)"
            >
              ＋
            </button>
          </div>
        </div>
      </div>
    </div>
    <div class="edit-row" v-if="available.length">
      <Select v-model="picked" class="grow" :options="pickOptions" placeholder="添加其他学科…" />
      <button :disabled="!picked" @click="addSubject">添加</button>
    </div>
  </section>
</template>

<style scoped>
/* 学科多了只在卡片内滚动：吃掉卡片剩余高度（见 .card-body） */
.hw-list {
  flex: 1;
  min-height: 0;
  overflow-y: auto;
}
.hw-group {
  display: grid;
  grid-template-columns: 64px 1fr;
  gap: 10px;
  padding: 2px 0;
}
.hw-group + .hw-group {
  border-top: 1px solid var(--border);
}
.hw-label {
  text-align: right;
  font-size: 14px;
  padding-top: 8px;
  white-space: nowrap;
}
.hw-rows {
  min-width: 0;
}
.hw-row {
  padding: 2px 0;
}
.idx {
  min-width: 18px;
  text-align: right;
  color: var(--blue);
  font-size: 13px;
  font-weight: bold;
  font-variant-numeric: tabular-nums;
}
.nowrap {
  white-space: nowrap;
  display: inline-flex;
  align-items: center;
  gap: 6px;
  cursor: pointer;
}
.add-entry {
  padding: 4px 10px;
  font-size: 13px;
  line-height: 1;
  color: var(--blue);
  border-style: dashed;
}
</style>
