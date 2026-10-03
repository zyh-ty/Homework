<script setup lang="ts">
import { computed } from "vue";

const props = defineProps<{
  modelValue: string;
  options: { value: string; label: string }[];
}>();

const emit = defineEmits<{ "update:modelValue": [value: string] }>();

const index = computed(() => Math.max(0, props.options.findIndex((o) => o.value === props.modelValue)));
</script>

<template>
  <div class="segmented">
    <span
      class="indicator"
      :style="{ width: `calc((100% - 6px) / ${options.length})`, transform: `translateX(calc(${index} * 100%))` }"
    />
    <button
      v-for="o in options"
      :key="o.value"
      type="button"
      class="seg"
      :class="{ on: o.value === modelValue }"
      @click="emit('update:modelValue', o.value)"
    >
      {{ o.label }}
    </button>
  </div>
</template>

<style scoped>
.segmented {
  position: relative;
  display: inline-flex;
  padding: 3px;
  border-radius: 999px;
  background: var(--bg);
  border: 1px solid var(--border);
}
.indicator {
  position: absolute;
  top: 3px;
  bottom: 3px;
  left: 3px;
  border-radius: 999px;
  background: #fff;
  box-shadow: 0 1px 3px rgba(20, 26, 38, 0.18);
  transition: transform 0.2s cubic-bezier(0.4, 0, 0.2, 1);
}
.seg {
  position: relative;
  z-index: 1;
  border: 0;
  background: transparent;
  padding: 4px 16px;
  font-size: 13px;
  border-radius: 999px;
  color: var(--gray);
  transition: color 0.15s;
}
.seg:hover {
  background: transparent;
  border-color: transparent;
  color: var(--blue);
}
.seg.on {
  color: var(--blue);
  font-weight: bold;
}
</style>
