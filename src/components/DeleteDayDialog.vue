<script setup lang="ts">
import { computed, ref } from "vue";
import { store, view, ui, cmd, refreshVm, showToast } from "../api";

const days = computed(() => Object.keys(store.data?.days ?? {}).sort());
const picked = ref("");

async function confirm() {
  if (!picked.value) return;
  await cmd.deleteDay(picked.value);
  ui.deleteDayOpen = false;
  showToast(`已删除 ${picked.value}`);
  if (view.date === picked.value) {
    view.date = store.today;
    view.submitOnly = false;
    await refreshVm();
  }
}
</script>

<template>
  <div class="dialog-mask" @click.self="ui.deleteDayOpen = false">
    <div class="dialog">
      <h3>删除天数</h3>
      <label class="field">
        <span>日期</span>
        <select v-model="picked">
          <option value="" disabled>选择要删除的日期…</option>
          <option v-for="d in days" :key="d" :value="d">{{ d }}</option>
        </select>
      </label>
      <div class="dialog-actions">
        <button @click="ui.deleteDayOpen = false">取消</button>
        <button class="danger" :disabled="!picked" @click="confirm">删除</button>
      </div>
    </div>
  </div>
</template>
