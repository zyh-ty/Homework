import type { ViewModel } from "./types";
import { dotDate } from "./utils";

export const W = 1920;
export const H = 1080;

export type DrawCmd =
  | { kind: "rect"; x: number; y: number; w: number; h: number; r: number; fill?: string; stroke?: string; lineWidth?: number }
  | { kind: "text"; x: number; y: number; text: string; size: number; bold?: boolean; color: string; align?: "left" | "center" | "right" }
  | { kind: "image"; x: number; y: number; w: number; h: number };

export const C = {
  bg: "#eef2f9",
  blue: "#2e5fa3",
  blueFill: "#8faadc",
  orangeFill: "#f6c796",
  red: "#c0272d",
  text: "#20242b",
  gray: "#8a93a3",
  card: "#ffffff",
  submitOrange: "#e07b00",
};

export function fontStr(size: number, bold: boolean): string {
  return `${bold ? "bold " : ""}${size}px "Microsoft YaHei", "SimHei", sans-serif`;
}

const mc = document.createElement("canvas").getContext("2d")!;

export function measure(text: string, size: number, bold = false): number {
  mc.font = fontStr(size, bold);
  return mc.measureText(text).width;
}

export function wrapText(text: string, size: number, bold: boolean, maxWidth: number): string[] {
  const lines: string[] = [];
  let cur = "";
  for (const ch of text) {
    if (ch === "\n") {
      lines.push(cur);
      cur = "";
      continue;
    }
    if (cur && measure(cur + ch, size, bold) > maxWidth) {
      lines.push(cur);
      cur = ch;
    } else {
      cur += ch;
    }
  }
  lines.push(cur);
  return lines;
}

function fitSize(need: (size: number) => number, avail: number, max: number, min: number): number {
  let lo = min;
  let hi = max;
  while (lo < hi) {
    const mid = Math.ceil((lo + hi) / 2);
    if (need(mid) <= avail) lo = mid;
    else hi = mid - 1;
  }
  return lo;
}

function dateBlock(cmds: DrawCmd[], x: number, y: number, w: number, h: number, vm: ViewModel) {
  cmds.push({ kind: "rect", x, y, w, h, r: 26, fill: C.orangeFill });
  cmds.push({ kind: "text", x: x + w / 2, y: y + h / 2 - 26, text: dotDate(vm.date), size: 46, bold: true, color: C.text, align: "center" });
  cmds.push({ kind: "text", x: x + w / 2, y: y + h / 2 + 28, text: vm.weekday, size: 34, color: C.text, align: "center" });
}

function announcementBar(cmds: DrawCmd[], x: number, y: number, w: number, vm: ViewModel, showBadge: boolean): number {
  const size = 32;
  const lineH = 46;
  const pad = 26;
  const badgeW = showBadge ? 128 : 0;
  const textW = w - pad * 2 - badgeW - 20;
  const lines: string[] = [];
  for (const a of vm.announcements) {
    const wrapped = wrapText(a.text, size, true, textW);
    wrapped.forEach((l, i) => lines.push((i === 0 ? "• " : "　") + l));
  }
  const h = Math.max(140, pad * 2 + lines.length * lineH);
  cmds.push({ kind: "rect", x, y, w, h, r: 28, fill: C.blueFill });
  if (showBadge) {
    const bs = h - 36;
    cmds.push({ kind: "image", x: x + 22, y: y + 18, w: bs, h: bs });
  }
  const tx = x + pad + badgeW + 20;
  let ty = y + (h - lines.length * lineH) / 2 + lineH / 2;
  for (const l of lines) {
    cmds.push({ kind: "text", x: tx, y: ty, text: l, size, bold: true, color: C.red });
    ty += lineH;
  }
  return h;
}

function scheduleBox(cmds: DrawCmd[], x: number, y: number, w: number, slots: { name: string; changed: boolean }[]): number {
  const entries = slots.map((s, i) => ({ ...s, idx: i + 1 })).filter((s) => s.name);
  if (entries.length === 0) {
    const h = 200;
    cmds.push({ kind: "rect", x, y, w, h, r: 24, fill: C.card, stroke: C.blue, lineWidth: 3 });
    cmds.push({ kind: "text", x: x + w / 2, y: y + h / 2, text: "今日无课", size: 32, color: C.gray, align: "center" });
    return h;
  }
  const size = 34;
  const lineH = 56;
  const padV = 22;
  const h = padV * 2 + entries.length * lineH;
  cmds.push({ kind: "rect", x, y, w, h, r: 24, fill: C.card, stroke: C.blue, lineWidth: 3 });
  let ty = y + padV + lineH / 2;
  for (const e of entries) {
    const color = e.changed ? C.red : C.text;
    cmds.push({ kind: "text", x: x + 36, y: ty, text: `${e.idx}`, size: 24, color: C.gray });
    cmds.push({ kind: "text", x: x + 92, y: ty, text: e.name, size, bold: e.changed, color });
    ty += lineH;
  }
  return h;
}

function speechBox(cmds: DrawCmd[], x: number, y: number, w: number, h: number, vm: ViewModel) {
  cmds.push({ kind: "rect", x, y, w, h, r: 24, fill: C.card, stroke: C.blue, lineWidth: 3 });
  const pad = 24;
  cmds.push({ kind: "text", x: x + pad, y: y + pad + 18, text: "演讲提醒", size: 30, bold: true, color: C.blue });
  if (vm.speech_warn) {
    cmds.push({ kind: "text", x: x + w / 2, y: y + h / 2 + 16, text: "⚠ 演讲提醒未填写", size: 32, bold: true, color: C.red, align: "center" });
    return;
  }
  const size = 27;
  const lineH = 40;
  const textW = w - pad * 2;
  const lines: { text: string; color: string }[] = [];
  for (const s of vm.speeches) {
    if (!s.students.trim()) continue;
    const wrapped = wrapText(`${s.subject}：${s.students.trim()}`, size, false, textW);
    wrapped.forEach((l) => lines.push({ text: l, color: C.text }));
  }
  if (lines.length === 0) return;
  let ty = y + pad + 48 + lineH / 2;
  for (const l of lines) {
    if (ty > y + h - pad) break;
    cmds.push({ kind: "text", x: x + pad, y: ty, text: l.text, size, color: l.color });
    ty += lineH;
  }
}

interface HwLine {
  text: string;
  num: number | null;
  submitNext: boolean;
}

function homeworkBox(cmds: DrawCmd[], x: number, y: number, w: number, h: number, vm: ViewModel) {
  cmds.push({ kind: "rect", x, y, w, h, r: 24, fill: C.card, stroke: C.blue, lineWidth: 3 });
  const pad = 30;
  const title = vm.submit_only ? `今天要交的作业（来自 ${vm.homework_date}）` : "家庭作业";
  cmds.push({ kind: "text", x: x + pad, y: y + pad + 16, text: title, size: 30, bold: true, color: C.blue });

  interface Group {
    entries: { label: string; text: string; submitNext: boolean }[];
  }
  const groups: Group[] = [];
  const engGroup: Group = { entries: [] };
  for (const it of vm.homework) {
    if (it.subject === "英语A" || it.subject === "英语B") {
      engGroup.entries.push({ label: it.subject, text: it.text, submitNext: it.submit_next });
    } else {
      groups.push({ entries: [{ label: it.subject, text: it.text, submitNext: it.submit_next }] });
    }
  }
  if (engGroup.entries.length > 0) {
    const firstEngIdx = vm.homework.findIndex((it) => it.subject === "英语A" || it.subject === "英语B");
    const before = vm.homework
      .slice(0, firstEngIdx)
      .filter((it) => it.subject !== "英语A" && it.subject !== "英语B").length;
    groups.splice(before, 0, engGroup);
  }

  const areaY = y + pad + 48;
  const areaH = y + h - pad - areaY;
  const numW = 84;
  const textW = w - pad * 2 - numW - 110;

  if (groups.length === 0) {
    cmds.push({ kind: "text", x: x + w / 2, y: y + h / 2 + 20, text: vm.submit_only ? "今天没有要交的作业" : "今天还没有作业", size: 34, color: C.gray, align: "center" });
    return;
  }

  const need = (size: number): number => {
    const lineH = size * 1.5;
    let total = 0;
    for (const g of groups) {
      for (const e of g.entries) {
        total += wrapText(`${e.label}：${e.text}`, size, false, textW).length * lineH;
      }
      total += lineH * 0.35;
    }
    return total;
  };
  const size = fitSize(need, areaH, 42, 24);
  const lineH = size * 1.5;

  let ty = areaY + lineH / 2;
  let num = 0;
  for (const g of groups) {
    num++;
    const groupStartY = ty;
    let first = true;
    let groupSubmit = false;
    for (const e of g.entries) {
      const lines = wrapText(`${e.label}：${e.text}`, size, false, textW);
      for (const l of lines) {
        if (first) {
          cmds.push({ kind: "text", x: x + pad, y: ty, text: `${num}.`, size, bold: true, color: C.blue });
          first = false;
        }
        cmds.push({ kind: "text", x: x + pad + numW, y: ty, text: l, size, color: C.text });
        ty += lineH;
      }
      if (e.submitNext) groupSubmit = true;
    }
    if (groupSubmit && !vm.submit_only) {
      cmds.push({ kind: "text", x: x + w - pad, y: groupStartY, text: "明天交", size: Math.round(size * 0.72), bold: true, color: C.submitOrange, align: "right" });
    }
    ty += lineH * 0.35;
  }
}

export function layout(vm: ViewModel, showBadge: boolean): DrawCmd[] {
  const cmds: DrawCmd[] = [];
  cmds.push({ kind: "rect", x: 0, y: 0, w: W, h: H, r: 0, fill: C.bg });

  const rightX = 1520;
  const rightW = 360;
  dateBlock(cmds, rightX, 36, rightW, 140, vm);
  const schedY = 196;
  const schedH = scheduleBox(cmds, rightX, schedY, rightW, vm.slots);
  const speechY = schedY + schedH + 20;
  speechBox(cmds, rightX, speechY, rightW, H - 36 - speechY, vm);

  const annH = announcementBar(cmds, 40, 36, 1460, vm, showBadge);
  const hwY = 36 + annH + 20;
  homeworkBox(cmds, 40, hwY, 1460, H - 36 - hwY, vm);

  return cmds;
}
