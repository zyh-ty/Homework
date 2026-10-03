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
  band: "#5f8bcc",
  bandSub: "#e3edfa",
  blue: "#2e5fa3",
  blueSoft: "#e8f0fb",
  card: "#ffffff",
  line: "#dbe3f0",
  divider: "#e6ecf6",
  amber: "#f6c796",
  annText: "#7a1f14",
  red: "#c0272d",
  redSoft: "#fdecec",
  orange: "#e07b00",
  orangeSoft: "#fff3e3",
  text: "#20242b",
  gray: "#8a93a3",
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

/* ---------- 版式常量 ---------- */

const M = 28;
const GAP = 20;
const HEAD_H = 112;
const PAD = 24;
const TITLE_H = 96;
const CONTENT_W = W - M * 2;
const LEFT_W = 1464;
const RIGHT_X = M + LEFT_W + GAP;
const RIGHT_W = CONTENT_W - LEFT_W - GAP;
/** 作业正文与演讲学号共用的内容缩进（编号徽章 56 + 间隔 24） */
const INDENT = 80;
/** 演讲学科标签字号固定，长学科只压缩标签盒宽度 */
const TAG_FONT = 24;

function panel(cmds: DrawCmd[], x: number, y: number, w: number, h: number, title: string) {
  cmds.push({ kind: "rect", x, y, w, h, r: 24, fill: C.card, stroke: C.line, lineWidth: 1.5 });
  cmds.push({ kind: "rect", x: x + PAD, y: y + 26, w: 8, h: 36, r: 4, fill: C.blue });
  cmds.push({ kind: "text", x: x + PAD + 20, y: y + 44, text: title, size: 36, bold: true, color: C.blue });
  cmds.push({ kind: "rect", x: x + PAD, y: y + 80, w: w - PAD * 2, h: 2, r: 0, fill: C.divider });
}

function centered(cmds: DrawCmd[], x: number, y: number, w: number, h: number, text: string, size: number) {
  cmds.push({ kind: "text", x: x + w / 2, y: y + h / 2, text, size, color: C.gray, align: "center" });
}

function headerBand(cmds: DrawCmd[], vm: ViewModel, showBadge: boolean) {
  const bandY = M;
  const cy = bandY + HEAD_H / 2;
  cmds.push({ kind: "rect", x: M, y: bandY, w: CONTENT_W, h: HEAD_H, r: 26, fill: C.band });
  let tx = M + PAD;
  if (showBadge) {
    cmds.push({ kind: "image", x: tx, y: cy - 39, w: 78, h: 78 });
    tx += 78 + 24;
  }
  cmds.push({ kind: "text", x: tx, y: cy, text: "每日作业", size: 44, bold: true, color: "#ffffff" });
  const rx = M + CONTENT_W - 26;
  cmds.push({ kind: "text", x: rx, y: bandY + 42, text: dotDate(vm.display_date), size: 44, bold: true, color: "#ffffff", align: "right" });
  cmds.push({ kind: "text", x: rx, y: bandY + 86, text: vm.weekday, size: 32, color: C.bandSub, align: "right" });
}

function announcementPanel(cmds: DrawCmd[], x: number, y: number, w: number, vm: ViewModel): number {
  const size = 52;
  const lineH = 66;
  const padV = 24;
  const textX = x + PAD;
  // 行首的「• 」/「　」是换行后拼上的，预留宽度否则整行会顶出公告栏右边界
  const maxW = x + w - PAD - textX - measure("• ", size, true);
  const lines: { text: string; indent: boolean }[] = [];
  for (const a of vm.announcements) {
    wrapText(a.text, size, true, maxW).forEach((l, i) => lines.push({ text: l, indent: i > 0 }));
  }
  const h = Math.max(104, padV * 2 + lines.length * lineH);
  cmds.push({ kind: "rect", x, y, w, h, r: 20, fill: C.amber });
  const firstY = y + (h - lines.length * lineH) / 2 + lineH / 2;
  lines.forEach((l, i) => {
    cmds.push({
      kind: "text",
      x: textX,
      y: firstY + i * lineH,
      text: (l.indent ? "　" : "• ") + l.text,
      size,
      bold: true,
      color: C.annText,
    });
  });
  return h;
}

/* 两栏编号课表：1-5 在左列、6-9 在右列，与原始模版一致 */
function schedulePanel(cmds: DrawCmd[], x: number, y: number, w: number, h: number, slots: ViewModel["slots"]) {
  panel(cmds, x, y, w, h, "今日课表");
  const ax = x + PAD;
  const ay = y + TITLE_H;
  const aw = w - PAD * 2;
  const ah = h - TITLE_H - PAD;
  const entries = slots.map((s, i) => ({ ...s, idx: i + 1 })).filter((s) => s.name).slice(0, 9);
  if (entries.length === 0) {
    centered(cmds, ax, ay, aw, ah, "今日无课", 40);
    return;
  }
  const cols = 2;
  const perCol = Math.ceil(entries.length / cols);
  // 行距随可用高度自适应，保证 9 节全部落在卡片内；字号跟着行距缩，避免行间重叠
  const pitch = Math.min(48, (ah - 4) / perCol);
  const rowSize = Math.max(21, Math.min(35, Math.round(pitch * 0.78)));
  const numSize = Math.max(16, Math.round(rowSize * 0.68));
  const colW = (aw - 24) / cols;
  const blockH = perCol * pitch;
  const topY = ay + Math.max(0, (ah - blockH) / 2);
  entries.forEach((e, i) => {
    const col = Math.floor(i / perCol);
    const row = i % perCol;
    const cx = ax + col * (colW + 24);
    const cy = topY + row * pitch + pitch / 2;
    const main = e.changed ? C.red : C.text;
    cmds.push({ kind: "text", x: cx + 6, y: cy, text: String(e.idx), size: numSize, bold: e.changed, color: e.changed ? C.red : C.gray });
    cmds.push({ kind: "text", x: cx + 40, y: cy, text: e.name, size: rowSize, bold: true, color: main });
  });
}

function speechPanel(cmds: DrawCmd[], x: number, y: number, w: number, h: number, vm: ViewModel) {
  panel(cmds, x, y, w, h, "演讲提醒");
  const ax = x + PAD;
  const ay = y + TITLE_H;
  const aw = w - PAD * 2;
  const ah = h - TITLE_H - PAD;
  const entries = vm.speeches.filter((s) => s.students.trim());
  if (entries.length === 0) {
    const bh = 100;
    const by = ay + (ah - bh) / 2;
    cmds.push({ kind: "rect", x: ax, y: by, w: aw, h: bh, r: 18, fill: C.redSoft });
    cmds.push({ kind: "text", x: ax + aw / 2, y: by + bh / 2, text: "⚠ 演讲提醒未填写", size: 36, bold: true, color: C.red, align: "center" });
    return;
  }
  const limit = ay + ah;
  const rowGap = 14;
  const textX = ax + INDENT;

  // 从大到小挑一个能让所有条目都放下的字号，实在放不下才截断
  type Row = { subject: string; tagW: number; tagH: number; lines: string[] };
  let size = 36;
  let lineH = 45;
  let rows: Row[] = [];
  for (const cand of [36, 32, 28, 26, 24]) {
    const lh = Math.round(cand * 1.25);
    const th = Math.round(cand * 1.05);
    rows = entries.map((s) => ({
      subject: s.subject,
      // 学科字号固定，不因为「英语A/B」多一个字就缩小；只把标签盒宽度限制在缩进之内
      tagW: Math.min(INDENT - 4, measure(s.subject, TAG_FONT, true) + 22),
      tagH: th,
      lines: wrapText(s.students.trim(), cand, true, ax + aw - textX),
    }));
    size = cand;
    lineH = lh;
    if (rows.reduce((n, r) => n + r.lines.length * lh + rowGap, 0) <= ah) break;
  }
  // 顶部对齐：条目紧贴标题分隔线，不在卡片里做垂直居中（否则首行离标题太远）
  let ty = ay;

  for (const r of rows) {
    if (ty + lineH > limit) break;
    const firstCenter = ty + lineH / 2;
    cmds.push({ kind: "rect", x: ax, y: firstCenter - r.tagH / 2, w: r.tagW, h: r.tagH, r: 12, fill: C.blueSoft });
    cmds.push({ kind: "text", x: ax + r.tagW / 2, y: firstCenter, text: r.subject, size: TAG_FONT, bold: true, color: C.blue, align: "center" });
    r.lines.forEach((l, i) => {
      const ly = firstCenter + i * lineH;
      if (ly > limit - 8) return;
      cmds.push({ kind: "text", x: i === 0 ? textX : ax, y: ly, text: l, size, bold: true, color: C.text });
    });
    ty += r.lines.length * lineH + rowGap;
  }
}

type Piece =
  | { kind: "text"; text: string; color: string; bold: boolean; size: number }
  | { kind: "tag"; text: string; color: string; bg: string; border: string; size: number };

/** 行内流式排布：文字片段按字符贪心换行，tag 片段整体不拆；返回占用行数 */
function flow(
  y0: number,
  lineH: number,
  x0: number,
  right: number,
  pieces: Piece[],
  maxLine: number,
  emit?: (c: DrawCmd) => void,
): number {
  const put = (c: DrawCmd, line: number) => {
    if (line <= maxLine) emit?.(c);
  };
  let x = x0;
  let line = 0;
  let run = "";
  let runX = x0;
  let st: { color: string; bold: boolean; size: number } | null = null;

  const flush = () => {
    if (run && st) put({ kind: "text", x: runX, y: y0 + line * lineH, text: run, size: st.size, bold: st.bold, color: st.color }, line);
    run = "";
    st = null;
  };

  for (const p of pieces) {
    if (p.kind === "tag") {
      const tw = measure(p.text, p.size, true) + 18;
      const th = Math.round(p.size * 1.75);
      if (x + tw > right && x > x0) {
        flush();
        line++;
        x = x0;
      }
      const cy = y0 + line * lineH;
      put({ kind: "rect", x, y: cy - th / 2, w: tw, h: th, r: th / 2, fill: p.bg, stroke: p.border, lineWidth: 2 }, line);
      put({ kind: "text", x: x + tw / 2, y: cy, text: p.text, size: p.size, bold: true, color: p.color, align: "center" }, line);
      x += tw;
      continue;
    }
    const style = { color: p.color, bold: p.bold, size: p.size };
    for (const ch of p.text) {
      if (st && (st.color !== style.color || st.bold !== style.bold || st.size !== style.size)) flush();
      if (!run) {
        runX = x;
        st = style;
      }
      const w = measure(run + ch, style.size, style.bold) - measure(run, style.size, style.bold);
      if (x + w > right && (run !== "" || x > x0)) {
        flush();
        line++;
        x = x0;
        runX = x;
        st = style;
      }
      run += ch;
      x += w;
    }
  }
  flush();
  return line + 1;
}

interface HwSub {
  label: string;
  entries: { text: string; submitNext: boolean }[];
}

/** 一个学科内的多条作业：序号 + 空格分隔，行内排布；只有一条时不显示序号 */
function subPieces(sub: HwSub, size: number, hideSubmit: boolean): Piece[] {
  const sep: Piece = { kind: "text", text: "　", color: C.text, bold: false, size };
  const space: Piece = { kind: "text", text: " ", color: C.text, bold: false, size };
  const numbered = sub.entries.length > 1;
  const pieces: Piece[] = [];
  sub.entries.forEach((e, i) => {
    if (i > 0) pieces.push(sep);
    if (numbered) {
      pieces.push({ kind: "text", text: String(i + 1), color: C.blue, bold: true, size });
      pieces.push(space);
    }
    pieces.push({ kind: "text", text: e.text, color: C.text, bold: false, size });
    if (e.submitNext && !hideSubmit) {
      pieces.push(space);
      pieces.push({ kind: "tag", text: "明天交", color: C.orange, bg: C.orangeSoft, border: C.orange, size: Math.round(size * 0.6) });
    }
  });
  return pieces;
}

function homeworkPanel(cmds: DrawCmd[], x: number, y: number, w: number, h: number, vm: ViewModel) {
  const title = vm.submit_only ? `今天要交的作业 · 来自 ${vm.homework_date.slice(5)}` : "家庭作业";
  panel(cmds, x, y, w, h, title);
  const ax = x + PAD;
  const ay = y + TITLE_H;
  const aw = w - PAD * 2;
  const ah = h - TITLE_H - PAD;
  const limit = ay + ah;

  // 同一学科可有多条作业，各自记 submit_next；英语A/英语B 共用一个编号，各自从 1 编号
  const subs = new Map<string, HwSub>();
  const order: string[] = [];
  for (const it of vm.homework) {
    let sub = subs.get(it.subject);
    if (!sub) {
      sub = { label: it.subject, entries: [] };
      subs.set(it.subject, sub);
      order.push(it.subject);
    }
    sub.entries.push({ text: it.text, submitNext: it.submit_next });
  }
  const groups: HwSub[][] = [];
  let eng: HwSub[] | null = null;
  for (const label of order) {
    const sub = subs.get(label)!;
    if (label === "英语A" || label === "英语B") {
      if (!eng) {
        eng = [];
        groups.push(eng);
      }
      eng.push(sub);
    } else {
      groups.push([sub]);
    }
  }
  if (groups.length === 0) {
    centered(cmds, ax, ay, aw, ah, vm.submit_only ? "今天没有要交的作业" : "今天还没有作业", 40);
    return;
  }

  const badge = 56;
  const textX = ax + INDENT;
  const right = ax + aw;
  // 标签列固定为「英语A：」的宽度，让每个学科的内容（含序号）首个字符对齐
  const labelW = (s: number) => measure("英语A：", s, true);

  const need = (size: number): number => {
    const lineH = size * 1.4;
    const x0 = textX + labelW(size);
    let total = 0;
    for (const g of groups) {
      for (const sub of g) total += flow(0, lineH, x0, right, subPieces(sub, size, vm.submit_only), Infinity) * lineH;
      total += lineH * 0.35;
    }
    return total;
  };
  const size = fitSize(need, ah, 46, 28);
  const lineH = size * 1.4;
  const contentX = textX + labelW(size);

  let ty = ay;
  let num = 0;
  for (const g of groups) {
    if (ty + lineH > limit) break;
    num++;
    const badgeCenter = ty + lineH / 2;
    cmds.push({ kind: "rect", x: ax, y: badgeCenter - badge / 2, w: badge, h: badge, r: 17, fill: C.blueSoft });
    cmds.push({ kind: "text", x: ax + badge / 2, y: badgeCenter, text: String(num), size: 32, bold: true, color: C.blue, align: "center" });
    for (const sub of g) {
      cmds.push({ kind: "text", x: textX, y: ty + lineH / 2, text: `${sub.label}：`, size, bold: true, color: C.text });
      const lines = flow(ty + lineH / 2, lineH, contentX, right, subPieces(sub, size, vm.submit_only), Math.floor((limit - ty) / lineH) - 1, (c) =>
        cmds.push(c),
      );
      ty += lines * lineH;
    }
    ty += lineH * 0.35;
  }
}

export function layout(vm: ViewModel, showBadge: boolean): DrawCmd[] {
  const cmds: DrawCmd[] = [];
  cmds.push({ kind: "rect", x: 0, y: 0, w: W, h: H, r: 0, fill: C.bg });
  headerBand(cmds, vm, showBadge);

  let y = M + HEAD_H + GAP;
  if (vm.announcements.length > 0) {
    y += announcementPanel(cmds, M, y, CONTENT_W, vm) + GAP;
  }

  const bottom = H - M;
  const contentH = bottom - y;
  homeworkPanel(cmds, M, y, LEFT_W, contentH, vm);

  // 右列：课表按内容需要取高度（两栏编号行，每行 48），余量留给演讲卡；
  // 高度不够时按需要比例压缩，两边都优先保住内容而不是固定比例。
  const speechRows = Math.max(1, vm.speeches.filter((s) => s.students.trim()).length);
  const availH = contentH - GAP;
  const schedNeed = TITLE_H + PAD + Math.ceil(Math.min(vm.slots.filter((s) => s.name).length || 1, 9) / 2) * 48;
  const speechNeed = TITLE_H + PAD + speechRows * 60;
  const sum = schedNeed + speechNeed;
  let schedH = sum <= availH ? schedNeed : Math.round(schedNeed * (availH / sum));
  const minSpeech = TITLE_H + PAD + 60;
  schedH = Math.max(TITLE_H + PAD + 48, Math.min(schedH, availH - minSpeech));

  schedulePanel(cmds, RIGHT_X, y, RIGHT_W, schedH, vm.slots);
  speechPanel(cmds, RIGHT_X, y + schedH + GAP, RIGHT_W, availH - schedH, vm);

  return cmds;
}
