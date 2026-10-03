<script setup lang="ts">
import { nextTick, onMounted, onUnmounted, ref, watch } from "vue";
import { store, view, vm, refreshVm, showToast } from "../api";
import { generateImage } from "../image";
import { layout, W, H } from "../layout";
import { renderCmds } from "../render-canvas";

const emit = defineEmits<{ exit: [] }>();

const canvasRef = ref<HTMLCanvasElement | null>(null);
const rootRef = ref<HTMLElement | null>(null);
const menu = ref<{ x: number; y: number } | null>(null);

function draw() {
  const canvas = canvasRef.value;
  if (!canvas || !vm.value || !store.data) return;
  const cw = canvas.clientWidth;
  const ch = canvas.clientHeight;
  if (cw === 0 || ch === 0) return;
  const dpr = window.devicePixelRatio || 1;
  canvas.width = Math.round(cw * dpr);
  canvas.height = Math.round(ch * dpr);
  const ctx = canvas.getContext("2d")!;
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  ctx.fillStyle = "#000";
  ctx.fillRect(0, 0, cw, ch);
  const scale = Math.min(cw / W, ch / H);
  ctx.translate((cw - W * scale) / 2, (ch - H * scale) / 2);
  ctx.scale(scale, scale);
  renderCmds(ctx, layout(vm.value, store.data.settings.show_badge));
}

function closeMenu() {
  menu.value = null;
}

function onContextMenu(e: MouseEvent) {
  e.preventDefault();
  const w = 232;
  const h = 168;
  menu.value = {
    x: Math.max(8, Math.min(e.clientX, window.innerWidth - w - 8)),
    y: Math.max(8, Math.min(e.clientY, window.innerHeight - h - 8)),
  };
}

async function toggleMode() {
  closeMenu();
  view.submitOnly = !view.submitOnly;
  await refreshVm();
  showToast(view.submitOnly ? "已切换为仅要交" : "已切换为显示全部");
}

function exportImage() {
  closeMenu();
  void generateImage(true);
}

function onExit() {
  closeMenu();
  emit("exit");
}

function onDocDown(e: MouseEvent) {
  if (!menu.value) return;
  const el = rootRef.value?.querySelector(".menu");
  if (el && el.contains(e.target as Node)) return;
  closeMenu();
}

/** 菜单打开时 Esc 先关菜单，不再触发退出放映 */
function onKeyCapture(e: KeyboardEvent) {
  if (menu.value && e.key === "Escape") {
    e.preventDefault();
    e.stopPropagation();
    closeMenu();
  }
}

watch(vm, () => void nextTick(draw));

onMounted(() => {
  window.addEventListener("resize", draw);
  document.addEventListener("mousedown", onDocDown);
  window.addEventListener("keydown", onKeyCapture, true);
  void nextTick(draw);
});

onUnmounted(() => {
  window.removeEventListener("resize", draw);
  document.removeEventListener("mousedown", onDocDown);
  window.removeEventListener("keydown", onKeyCapture, true);
});
</script>

<template>
  <div ref="rootRef" class="present" @contextmenu="onContextMenu">
    <canvas ref="canvasRef" class="present-canvas"></canvas>
    <div v-if="menu" class="menu" :style="{ left: menu.x + 'px', top: menu.y + 'px' }">
      <button @click="toggleMode">{{ view.submitOnly ? "切换为显示全部" : "切换为仅要交" }}</button>
      <button @click="exportImage">生成作业图片</button>
      <div class="sep"></div>
      <button class="danger" @click="onExit">退出放映</button>
    </div>
  </div>
</template>

<style scoped>
.present {
  position: fixed;
  inset: 0;
  background: #000;
  cursor: none;
}
.present-canvas {
  width: 100%;
  height: 100%;
  display: block;
}
.menu {
  position: fixed;
  z-index: 20;
  min-width: 216px;
  padding: 6px;
  border-radius: 12px;
  background: #fff;
  box-shadow: 0 14px 36px rgba(0, 0, 0, 0.38);
  display: flex;
  flex-direction: column;
  gap: 2px;
  cursor: default;
}
.menu button {
  border: 0;
  background: transparent;
  text-align: left;
  padding: 9px 12px;
  border-radius: 8px;
  font-size: 14px;
  color: var(--text);
  cursor: pointer;
}
.menu button:hover {
  background: var(--blue-soft);
  border-color: transparent;
  color: var(--blue);
}
.menu button.danger {
  color: var(--red);
}
.menu button.danger:hover {
  background: #fdecec;
  color: var(--red);
}
.menu .sep {
  height: 1px;
  background: var(--border);
  margin: 4px 6px;
}
</style>
