<script setup lang="ts">
import { ref } from "vue";
import { view, ui, cmd, refreshVm, showToast } from "../api";
import { addDays } from "../utils";

const date = ref(addDays(view.date || new Date().toISOString().slice(0, 10), 1));
const copyFrom = ref<string>("");

async function confirm() {
  try {
    await cmd.addDay(date.value, copyFrom.value === "" ? null : Number(copyFrom.value));
    ui.addDayOpen = false;
    view.date = date.value;
    view.submitOnly = false;
    await refreshVm();
    showToast(`已新增 ${date.value}`);
  } catch (e) {
    showToast(`新增失败：${e}`);
  }
}
</script>

<template>
  <div class="dialog-mask" @click.self="ui.addDayOpen = false">
    <div class="dialog">
      <h3>新增天数（调休补课等）</h3>
      <label class="field">
        <span>日期</span>
        <input v-model="date" type="date" />
      </label>
      <label class="field">
        <span>上哪天的课</span>
        <select v-model="copyFrom">
          <option value="">按当天星期</option>
          <option :value="0">周一</option>
          <option :value="1">周二</option>
          <option :value="2">周三</option>
          <option :value="3">周四</option>
          <option :value="4">周五</option>
        </select>
      </label>
      <div class="dialog-actions">
        <button @click="ui.addDayOpen = false">取消</button>
        <button class="primary" :disabled="!date" @click="confirm">新增</button>
      </div>
    </div>
  </div>
</template>
