<script setup lang="ts">
import { onMounted, ref, watch } from "vue";
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
watch(() => store.data, load);

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
  <div class="dialog-mask" @click.self="ui.weekOpen = false">
    <div class="dialog" style="min-width: 720px">
      <h3>
        课表总览
        <button v-if="!editing" style="float: right" @click="startEdit">修改周课表模版</button>
      </h3>
      <table v-if="overview && !editing" class="week">
        <thead>
          <tr>
            <th></th>
            <th v-for="(d, i) in overview.dates" :key="d">
              {{ WEEKDAYS[i] }}<br />{{ d.slice(5) }}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="p in 9" :key="p">
            <td class="p">{{ p }}</td>
            <td
              v-for="(row, i) in overview.rows"
              :key="i"
              :class="{ changed: row[p - 1]?.changed }"
            >
              {{ row[p - 1]?.name || "" }}
            </td>
          </tr>
        </tbody>
      </table>
      <template v-if="editing">
        <table class="week">
          <thead>
            <tr>
              <th></th>
              <th v-for="w in WEEKDAYS" :key="w">{{ w }}</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="p in 9" :key="p">
              <td class="p">{{ p }}</td>
              <td v-for="(_, i) in WEEKDAYS" :key="i">
                <input v-model="templateRows[i][p - 1]" type="text" style="width: 72px" />
              </td>
            </tr>
          </tbody>
        </table>
      </template>
      <div class="dialog-actions">
        <template v-if="editing">
          <button @click="editing = false">取消</button>
          <button class="primary" @click="saveTemplate">保存模版</button>
        </template>
        <button v-else class="primary" @click="ui.weekOpen = false">关闭</button>
      </div>
    </div>
  </div>
</template>

<style scoped>
table.week {
  border-collapse: collapse;
  width: 100%;
}
table.week th,
table.week td {
  border: 1px solid var(--border);
  padding: 4px 8px;
  font-size: 13px;
  text-align: center;
}
table.week td.changed {
  color: var(--red);
  font-weight: bold;
}
table.week td.p {
  color: var(--gray);
}
</style>
