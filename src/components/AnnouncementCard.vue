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
  const copy = list.value.map((x) => ({ ...x }));
  const it = copy.find((x) => x.id === a.id)!;
  it.done = !it.done;
  it.done_date = it.done ? store.today : null;
  save(copy);
}

function remove(a: Announcement) {
  save(list.value.filter((x) => x.id !== a.id));
}
</script>

<template>
  <section class="card">
    <h3>
      公告
      <span class="hint">勾选完成后放映不再显示；新的一天会自动完成昨天的公告</span>
    </h3>
    <div v-for="a in list" :key="a.id" class="edit-row ann" :class="{ done: a.done }">
      <input type="checkbox" :checked="a.done" title="完成" @change="toggle(a)" />
      <span class="grow">{{ a.text }}</span>
      <span class="hint">{{ a.created_date.slice(5) }}</span>
      <button class="danger" @click="remove(a)">删除</button>
    </div>
    <div class="edit-row">
      <input
        v-model="newText"
        type="text"
        class="grow"
        placeholder="新公告，回车添加…"
        @keydown.enter="add"
      />
      <button :disabled="!newText.trim()" @click="add">添加</button>
    </div>
  </section>
</template>

<style scoped>
.ann.done .grow {
  text-decoration: line-through;
  color: var(--gray);
}
</style>
