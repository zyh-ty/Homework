import { invoke } from "@tauri-apps/api/core";
import { cmd, store, view, vm, showToast } from "./api";
import { layout } from "./layout";
import { renderPng } from "./render-canvas";
import type { ViewModel } from "./types";

let running = false;

/** 自动出图固定「今天 · 全部」；手动出图导出当前屏幕所见（页面日 + 当前模式）。
 *  文件名一律用页面日（作业所属的那一天），「仅要交」时画面日期不作为文件名。 */
export async function generateImage(manual: boolean): Promise<void> {
  if (!store.data || running) return;
  running = true;
  try {
    const v = manual
      ? vm.value ??
        (await invoke<ViewModel>("get_view_model", {
          date: view.date,
          submitOnly: view.submitOnly,
        }))
      : await invoke<ViewModel>("get_view_model", {
          date: store.today,
          submitOnly: false,
        });
    const cmds = layout(v, store.data.settings.show_badge);
    const png = await renderPng(cmds);
    const path = await cmd.exportImage(png, v.date);
    if (manual) showToast(`已生成：${path}`);
  } catch (e) {
    if (manual) showToast(`生成图片失败：${e}`);
  } finally {
    running = false;
  }
}
