<script setup lang="ts">
import { ref } from "vue";
import { store, ui, cmd, showToast } from "../api";

const interval = ref(store.data?.settings.image_interval_secs ?? 60);
const cutoff = ref(store.data?.settings.morning_cutoff ?? "08:00");
const showBadge = ref(store.data?.settings.show_badge ?? true);

async function chooseDir() {
  try {
    const dir = await cmd.chooseDataDir();
    if (dir) showToast(`数据目录已迁移到：${dir}`);
  } catch (e) {
    showToast(`迁移失败：${e}`);
  }
}

async function save() {
  if (!store.data) return;
  await cmd.updateSettings({
    ...store.data.settings,
    image_interval_secs: Math.max(10, Number(interval.value) || 60),
    morning_cutoff: cutoff.value || "08:00",
    show_badge: showBadge.value,
  });
  ui.settingsOpen = false;
  showToast("设置已保存");
}
</script>

<template>
  <div class="dialog-mask" @click.self="ui.settingsOpen = false">
    <div class="dialog">
      <h3>设置</h3>
      <label class="field">
        <span>数据目录</span>
        <input type="text" :value="store.dataDir" readonly class="grow" style="flex:1" />
        <button @click="chooseDir">更换…</button>
      </label>
      <label class="field">
        <span>出图间隔（秒）</span>
        <input v-model="interval" type="number" min="10" style="width: 100px" />
      </label>
      <label class="field">
        <span>早晨分界线</span>
        <input v-model="cutoff" type="time" style="width: 120px" />
      </label>
      <label class="field">
        <span>放映显示班徽</span>
        <input v-model="showBadge" type="checkbox" />
      </label>
      <div class="dialog-actions">
        <button @click="ui.settingsOpen = false">取消</button>
        <button class="primary" @click="save">保存</button>
      </div>
    </div>
  </div>
</template>
