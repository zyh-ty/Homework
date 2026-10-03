<script setup lang="ts">
import { computed, ref } from "vue";
import { store, cmd } from "../api";
import type { Announcement } from "../types";

const list = computed(() => store.data?.announcements ?? []);
const newText = ref("");

function save(list2: Announcement[]) {
  void cmd.setAnnouncements(list2);
}

function add() {
  const t = newText.value.trim();
  if (!t) return;
  newText.value = "";
  void cmd.addAnnouncement(t);
}

function toggle(a: Announcement) {
  save(list.value.map((x) => (x.id === a.id ? { ...x, done: !x.done } : { ...x })));
}

function remove(a: Announcement) {
  save(list.value.filter((x) => x.id !== a.id));
}

function onRowKey(a: Announcement, e: KeyboardEvent) {
  if (e.key !== "Enter") return;
  e.preventDefault();
  toggle(a);
}
</script>

<template>
  <section class="card">
    <h3>
      <span>公告</span>
      <span class="hint">所有日期共用这一份公告；勾选完成后放映不再显示；回车切换完成</span>
    </h3>
    <div class="ann-list">
      <div v-for="a in list" :key="a.id" class="edit-row ann" :class="{ done: a.done }">
        <input
          type="checkbox"
          data-nav="ann"
          :checked="a.done"
          title="完成（回车切换）"
          @change="toggle(a)"
          @keydown="onRowKey(a, $event)"
        />
        <span class="grow">{{ a.text }}</span>
        <button class="danger" @click="remove(a)">删除</button>
      </div>
    </div>
    <div class="edit-row">
      <input
        v-model="newText"
        type="text"
        class="grow"
        data-nav="ann"
        placeholder="新公告，回车添加…"
        @keydown.enter="add"
      />
      <button :disabled="!newText.trim()" @click="add">添加</button>
    </div>
  </section>
</template>

<style scoped>
/* 固定显示 4 行，多出来的在这块里滚动；行高固定，切断位置正好落在行边界上 */
.ann-list {
  max-height: 136px;
  overflow-y: auto;
}
.ann-list .edit-row {
  height: 34px;
  padding: 0;
}
.ann.done .grow {
  text-decoration: line-through;
  color: var(--gray);
}
</style>
