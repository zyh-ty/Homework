<script setup lang="ts">
import { computed, ref } from "vue";
import { store, ui, view, vm, cmd, showToast, refreshVm } from "../api";
import { addDays, parseDate } from "../utils";
import Select from "../components/ui/Select.vue";

const WD = ["日", "一", "二", "三", "四", "五", "六"];

const version = __APP_VERSION__;

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
  showToast("设置已保存");
}

const days = computed(() => Object.keys(store.data?.days ?? {}).sort());

function dayLabel(d: string): string {
  return `${d}　周${WD[parseDate(d).getDay()]}`;
}

const newDate = ref(addDays(store.today || new Date().toISOString().slice(0, 10), 1));
const newCopyFrom = ref("");

const copyOptions = [
  { value: "", label: "按当天星期" },
  { value: "0", label: "上周一的课" },
  { value: "1", label: "上周二的课" },
  { value: "2", label: "上周三的课" },
  { value: "3", label: "上周四的课" },
  { value: "4", label: "上周五的课" },
];

async function addDay() {
  if (!newDate.value) return;
  try {
    await cmd.addDay(newDate.value, newCopyFrom.value === "" ? null : Number(newCopyFrom.value));
    view.date = newDate.value;
    view.submitOnly = false;
    await refreshVm();
    showToast(`已新增 ${newDate.value}`);
  } catch (e) {
    showToast(`新增失败：${e}`);
  }
}

const confirming = ref("");

async function removeDay(d: string) {
  await cmd.deleteDay(d);
  confirming.value = "";
  if (view.date === d) {
    view.date = store.today;
    view.submitOnly = false;
    await refreshVm();
  }
  showToast(`已删除 ${d}`);
}

function copyFromOf(d: string): string {
  const v = store.data?.days[d]?.copied_from_weekday;
  return v == null ? "" : String(v);
}

async function setCopyFrom(d: string, value: string) {
  const day = store.data?.days[d];
  if (!day) return;
  await cmd.setDay(d, { ...day, copied_from_weekday: value === "" ? null : Number(value) });
  showToast(value === "" ? `${d} 的课表已按当天星期` : `${d} 的课表已按${copyOptions.find((o) => o.value === value)?.label}`);
}
</script>

<template>
  <div class="page">
    <header class="page-head">
      <button @click="ui.page = 'edit'">← 返回</button>
      <h2>设置</h2>
    </header>
    <div class="page-body">
      <div class="wrap">
        <section class="card">
          <h3><span>常规</span></h3>
          <label class="field">
            <span>数据目录</span>
            <input class="grow" type="text" :value="store.dataDir" readonly />
            <button @click="chooseDir">更换…</button>
          </label>
          <label class="field">
            <span>出图间隔（秒）</span>
            <input v-model="interval" type="number" min="10" style="width: 110px" />
            <span class="note">修改后超过该时长自动生成家庭作业图片</span>
          </label>
          <label class="field">
            <span>早晨分界线</span>
            <input v-model="cutoff" type="time" style="width: 130px" />
            <span class="note">早于该时间打开自动进入「仅要交」</span>
          </label>
          <label class="field">
            <span>放映显示班徽</span>
            <input v-model="showBadge" type="checkbox" />
          </label>
          <div class="row-end">
            <button class="primary" @click="save">保存设置</button>
          </div>
        </section>

        <section class="card">
          <h3>
            <span>天数管理</span>
            <span class="hint">调休补课日用；「上哪天的课」决定课表模版来源</span>
          </h3>
          <div class="field">
            <span>新增日期</span>
            <input v-model="newDate" type="date" />
            <Select v-model="newCopyFrom" :options="copyOptions" />
            <button class="primary" :disabled="!newDate" @click="addDay">新增</button>
          </div>
          <div v-if="days.length === 0" class="empty">还没有单独编辑过的日期。</div>
          <div v-for="d in days" :key="d" class="field">
            <span>{{ dayLabel(d) }}</span>
            <Select :model-value="copyFromOf(d)" :options="copyOptions" @update:model-value="setCopyFrom(d, $event)" />
            <template v-if="confirming === d">
              <button class="danger" @click="removeDay(d)">确认删除</button>
              <button @click="confirming = ''">取消</button>
            </template>
            <button v-else class="danger" @click="confirming = d">删除</button>
            <span v-if="d === vm?.date" class="note">当前正在编辑</span>
          </div>
        </section>

        <section class="card">
          <h3>
            <span>快捷键</span>
            <span class="hint">编辑时可以不离开键盘：Alt+数字跳区、回车加条目、Ctrl+回车标记</span>
          </h3>
          <div class="keys">
            <div><kbd>Alt</kbd>+<kbd>1</kbd>~<kbd>4</kbd> 跳到 公告 / 作业 / 演讲 / 课表</div>
            <div><kbd>Enter</kbd> 在输入框里新建下一条（课表为下一节）</div>
            <div><kbd>Ctrl</kbd>+<kbd>Enter</kbd> 标记当前条目（明天交 / 公告完成）</div>
            <div><kbd>Alt</kbd>+<kbd>↑</kbd><kbd>↓</kbd> 在条目之间上下切换</div>
            <div><kbd>←</kbd><kbd>→</kbd> 切换上一天 / 下一天</div>
            <div><kbd>F5</kbd> 进入放映 / 退出放映</div>
            <div><kbd>Esc</kbd> 退出放映 / 从设置、课表总览返回</div>
            <div><kbd>Ctrl</kbd>+<kbd>T</kbd> 回到今天</div>
            <div><kbd>Ctrl</kbd>+<kbd>S</kbd> 立即保存</div>
            <div><kbd>Ctrl</kbd>+<kbd>D</kbd> 立即生成图片</div>
            <div><kbd>Ctrl</kbd>+<kbd>K</kbd> 课表总览</div>
            <div><kbd>Ctrl</kbd>+<kbd>,</kbd> 设置</div>
          </div>
        </section>

        <section class="card">
          <h3><span>关于</span></h3>
          <div class="about">
            <div>每日作业 v{{ version }}</div>
            <div class="note">数据文件：{{ store.dataDir }}\data.json（自动备份至 backups\）</div>
          </div>
        </section>
      </div>
    </div>
  </div>
</template>

<style scoped>
.note {
  color: var(--gray);
  font-size: 12px;
}
.row-end {
  display: flex;
  justify-content: flex-end;
  margin-top: 14px;
}
.keys {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 6px 18px;
  font-size: 13px;
  color: var(--text);
}
kbd {
  display: inline-block;
  min-width: 22px;
  text-align: center;
  padding: 1px 6px;
  margin-right: 4px;
  border: 1px solid var(--border);
  border-bottom-width: 2px;
  border-radius: 5px;
  background: #f7f9fc;
  font-family: inherit;
  font-size: 12px;
  color: var(--blue);
}
.about {
  display: flex;
  flex-direction: column;
  gap: 6px;
  font-size: 13px;
}
</style>
