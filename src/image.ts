import { invoke } from "@tauri-apps/api/core";
import { cmd, store, showToast } from "./api";
import { layout } from "./layout";
import { renderPng } from "./render-canvas";
import type { ViewModel } from "./types";

let running = false;

export async function generateTodayImage(manual: boolean): Promise<void> {
  if (!store.data || running) return;
  running = true;
  try {
    const v = await invoke<ViewModel>("get_view_model", {
      date: store.today,
      submitOnly: false,
    });
    const cmds = layout(v, store.data.settings.show_badge);
    const png = await renderPng(cmds);
    const path = await cmd.exportImage(png);
    if (manual) showToast(`已生成：${path}`);
  } catch (e) {
    if (manual) showToast(`生成图片失败：${e}`);
  } finally {
    running = false;
  }
}
