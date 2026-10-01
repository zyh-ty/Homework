<script setup lang="ts">
import { nextTick, onMounted, onUnmounted, ref, watch } from "vue";
import { store, vm } from "../api";
import { layout, W, H } from "../layout";
import { renderCmds } from "../render-canvas";

const canvasRef = ref<HTMLCanvasElement | null>(null);

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

watch(vm, () => void nextTick(draw));

onMounted(() => {
  window.addEventListener("resize", draw);
  void nextTick(draw);
});

onUnmounted(() => {
  window.removeEventListener("resize", draw);
});
</script>

<template>
  <div class="present">
    <canvas ref="canvasRef" class="present-canvas"></canvas>
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
</style>
