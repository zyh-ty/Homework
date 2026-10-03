<script setup lang="ts">
import { onMounted, ref } from "vue";
import { store, view, ui, cmd, showToast } from "../api";
import { mondayOf } from "../utils";
import type { WeekOverview } from "../types";

const WEEKDAYS = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"];

const overview = ref<WeekOverview | null>(null);
const editing = ref(false);
const templateRows = ref<string[][]>([]);

async function load() {
  overview.value = await cmd.getWeek(mondayOf(view.date));
}

onMounted(load);

function startEdit() {
  templateRows.value = structuredClone(store.data?.weekly_schedule ?? []);
  editing.value = true;
}

async function saveTemplate() {
  await cmd.setWeeklySchedule(templateRows.value);
  editing.value = false;
  showToast("周课表模版已更新");
  await load();
}
</script>

<template>
  <div class="page">
    <header class="page-head">
      <button @click="ui.page = 'edit'">← 返回</button>
      <h2>课表总览</h2>
      <span class="spacer" />
      <span class="hint">本周（{{ mondayOf(view.date) }} 起）；调课显示为红色</span>
      <button v-if="!editing" @click="startEdit">修改周课表模版</button>
    </header>
    <div class="page-body">
      <div class="weekwrap">
        <table v-if="overview && !editing" class="week">
          <thead>
            <tr>
              <th class="p"></th>
              <th
                v-for="(d, i) in overview.dates"
                :key="d"
                :class="{ today: d === store.today }"
              >
                {{ WEEKDAYS[i] }}<br /><span class="dt">{{ d.slice(5) }}</span>
              </th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="p in 9" :key="p">
              <td class="p">{{ p }}</td>
              <td
                v-for="(row, i) in overview.rows"
                :key="i"
                :class="{ changed: row[p - 1]?.changed, today: overview.dates[i] === store.today }"
              >
                {{ row[p - 1]?.name || "" }}
              </td>
            </tr>
          </tbody>
        </table>

        <table v-else-if="editing" class="week">
          <thead>
            <tr>
              <th class="p"></th>
              <th v-for="w in WEEKDAYS" :key="w">{{ w }}</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="p in 9" :key="p">
              <td class="p">{{ p }}</td>
              <td v-for="(_, i) in WEEKDAYS" :key="i">
                <input v-model="templateRows[i][p - 1]" type="text" />
              </td>
            </tr>
          </tbody>
        </table>
        <div v-else class="empty">正在加载本周课表…</div>

        <div v-if="editing" class="row-end">
          <button @click="editing = false">取消</button>
          <button class="primary" @click="saveTemplate">保存模版</button>
        </div>
        <div v-if="!editing && overview" class="legend">
          <span class="dot" /> 红色 = 该日单独调课（在编辑页或设置 → 天数管理中修改）
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.hint {
  color: var(--gray);
  font-size: 12px;
}
.weekwrap {
  max-width: 1180px;
  margin: 0 auto;
  display: flex;
  flex-direction: column;
  gap: 12px;
}
table.week {
  border-collapse: separate;
  border-spacing: 0;
  width: 100%;
  background: #fff;
  border: 1px solid var(--border);
  border-radius: 12px;
  overflow: hidden;
}
table.week th,
table.week td {
  border-right: 1px solid var(--border);
  border-bottom: 1px solid var(--border);
  padding: 8px 10px;
  font-size: 15px;
  text-align: center;
}
table.week tr > *:last-child {
  border-right: 0;
}
table.week tbody tr:last-child td {
  border-bottom: 0;
}
table.week th {
  background: #f7f9fc;
  color: var(--blue);
  font-size: 13px;
  font-weight: bold;
}
table.week th .dt {
  color: var(--gray);
  font-weight: normal;
}
table.week td.today,
table.week th.today {
  background: var(--blue-soft);
}
table.week td.changed {
  color: var(--red);
  font-weight: bold;
}
table.week td.p {
  color: var(--gray);
  font-size: 13px;
  background: #fbfcfe;
}
table.week input {
  width: 100%;
  min-width: 84px;
  text-align: center;
  padding: 4px 6px;
}
.row-end {
  display: flex;
  justify-content: flex-end;
  gap: 10px;
}
.legend {
  color: var(--gray);
  font-size: 12px;
  display: flex;
  align-items: center;
  gap: 6px;
}
.dot {
  width: 10px;
  height: 10px;
  border-radius: 3px;
  background: var(--red);
  opacity: 0.65;
}
</style>
