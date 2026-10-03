<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from "vue";

const props = defineProps<{
  modelValue: string;
  options: { value: string; label: string }[];
  placeholder?: string;
}>();

const emit = defineEmits<{ "update:modelValue": [value: string] }>();

const open = ref(false);
const active = ref(0);
const root = ref<HTMLElement | null>(null);

const current = computed(() => props.options.find((o) => o.value === props.modelValue));

function toggle() {
  if (open.value) {
    open.value = false;
    return;
  }
  active.value = Math.max(0, props.options.findIndex((o) => o.value === props.modelValue));
  open.value = true;
}

function pick(value: string) {
  emit("update:modelValue", value);
  open.value = false;
}

function onDocDown(e: MouseEvent) {
  if (root.value && !root.value.contains(e.target as Node)) open.value = false;
}

function onKey(e: KeyboardEvent) {
  if (!open.value) {
    if (e.key === "ArrowDown" || e.key === "Enter" || e.key === " ") {
      e.preventDefault();
      toggle();
    }
    return;
  }
  if (e.key === "Escape") {
    e.preventDefault();
    e.stopPropagation();
    open.value = false;
  } else if (e.key === "ArrowDown") {
    e.preventDefault();
    e.stopPropagation();
    active.value = Math.min(props.options.length - 1, active.value + 1);
  } else if (e.key === "ArrowUp") {
    e.preventDefault();
    e.stopPropagation();
    active.value = Math.max(0, active.value - 1);
  } else if (e.key === "Enter") {
    e.preventDefault();
    e.stopPropagation();
    const o = props.options[active.value];
    if (o) pick(o.value);
  }
}

onMounted(() => document.addEventListener("mousedown", onDocDown));
onBeforeUnmount(() => document.removeEventListener("mousedown", onDocDown));
</script>

<template>
  <div ref="root" class="sel" :class="{ open }" @keydown="onKey">
    <button type="button" class="sel-trigger" @click="toggle">
      <span class="sel-text" :class="{ ph: !current }">{{ current?.label ?? placeholder ?? "请选择" }}</span>
      <svg class="chev" viewBox="0 0 10 6" width="10" height="6" aria-hidden="true">
        <path
          d="M1 1l4 4 4-4"
          fill="none"
          stroke="currentColor"
          stroke-width="1.6"
          stroke-linecap="round"
          stroke-linejoin="round"
        />
      </svg>
    </button>
    <ul v-if="open" class="sel-list">
      <li
        v-for="(o, i) in options"
        :key="o.value"
        :class="{ active: i === active, selected: o.value === modelValue }"
        @mouseenter="active = i"
        @click="pick(o.value)"
      >
        {{ o.label }}
      </li>
    </ul>
  </div>
</template>

<style scoped>
.sel {
  position: relative;
  min-width: 150px;
}
.sel-trigger {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
  width: 100%;
  padding: 6px 10px;
  font-size: 14px;
  font-weight: normal;
  border-radius: 8px;
}
.sel-trigger:hover {
  background: #fff;
  border-color: var(--blue);
}
.sel-text {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.sel-text.ph {
  color: var(--gray);
}
.chev {
  flex: none;
  color: var(--gray);
  transition: transform 0.18s;
}
.sel.open .chev {
  transform: rotate(180deg);
}
.sel-list {
  position: absolute;
  z-index: 50;
  left: 0;
  right: 0;
  top: calc(100% + 4px);
  margin: 0;
  padding: 4px;
  list-style: none;
  background: #fff;
  border: 1px solid var(--border);
  border-radius: 10px;
  box-shadow: 0 10px 28px rgba(20, 26, 38, 0.16);
  max-height: 264px;
  overflow: auto;
}
.sel-list li {
  padding: 6px 10px;
  border-radius: 6px;
  font-size: 14px;
  cursor: pointer;
  white-space: nowrap;
}
.sel-list li.active {
  background: var(--blue-soft);
}
.sel-list li.selected {
  color: var(--blue);
  font-weight: bold;
}
</style>
