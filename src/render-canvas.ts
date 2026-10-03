import { fontStr, W, H, type DrawCmd } from "./layout";
import badgeUrl from "./assets/badge.png";

// textBaseline="middle" 对齐的是 em 盒中心，而中日韩字形的墨迹中心比它高约 0.07em，
// 不补这一下所有「以 y 为视觉中心」的元素都会整体偏上（换行文本的上下留白也会不等）。
const INK_SHIFT = 0.07;

let badge: HTMLImageElement | null = null;
let badgeInk: { x: number; y: number; w: number; h: number } | null = null;

/** 素材自带的透明边距会让「按框居中」变成视觉偏心，先量出真实墨迹范围 */
function measureInk(img: HTMLImageElement) {
  const c = document.createElement("canvas");
  c.width = img.naturalWidth;
  c.height = img.naturalHeight;
  const ctx = c.getContext("2d")!;
  ctx.drawImage(img, 0, 0);
  const w = c.width;
  const h = c.height;
  const d = ctx.getImageData(0, 0, w, h).data;
  let top = -1;
  let bottom = -1;
  let left = -1;
  let right = -1;
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      if (d[(y * w + x) * 4 + 3] > 8) {
        if (top < 0) top = y;
        bottom = y;
        if (left < 0 || x < left) left = x;
        if (x > right) right = x;
      }
    }
  }
  if (top < 0) return null;
  return { x: left / w, y: top / h, w: (right - left + 1) / w, h: (bottom - top + 1) / h };
}

export function loadBadge(): Promise<void> {
  return new Promise((resolve) => {
    const img = new Image();
    img.onload = () => {
      badge = img;
      badgeInk = measureInk(img);
      resolve();
    };
    img.onerror = () => resolve();
    img.src = badgeUrl;
  });
}

export function renderCmds(ctx: CanvasRenderingContext2D, cmds: DrawCmd[]) {
  for (const c of cmds) {
    if (c.kind === "rect") {
      ctx.beginPath();
      ctx.roundRect(c.x, c.y, c.w, c.h, c.r);
      if (c.fill) {
        ctx.fillStyle = c.fill;
        ctx.fill();
      }
      if (c.stroke) {
        ctx.strokeStyle = c.stroke;
        ctx.lineWidth = c.lineWidth ?? 2;
        ctx.stroke();
      }
    } else if (c.kind === "text") {
      ctx.font = fontStr(c.size, c.bold ?? false);
      ctx.fillStyle = c.color;
      ctx.textBaseline = "middle";
      ctx.textAlign = c.align ?? "left";
      ctx.fillText(c.text, c.x, c.y + c.size * INK_SHIFT);
    } else if (c.kind === "image") {
      if (!badge) continue;
      if (!badgeInk) {
        ctx.drawImage(badge, c.x, c.y, c.w, c.h);
        continue;
      }
      const sw = badgeInk.w * badge.naturalWidth;
      const sh = badgeInk.h * badge.naturalHeight;
      const k = Math.min(c.w / sw, c.h / sh);
      const tw = sw * k;
      const th = sh * k;
      ctx.drawImage(
        badge,
        badgeInk.x * badge.naturalWidth,
        badgeInk.y * badge.naturalHeight,
        sw,
        sh,
        c.x + (c.w - tw) / 2,
        c.y + (c.h - th) / 2,
        tw,
        th,
      );
    }
  }
}

export async function renderPng(cmds: DrawCmd[]): Promise<Uint8Array> {
  const canvas = document.createElement("canvas");
  canvas.width = W;
  canvas.height = H;
  const ctx = canvas.getContext("2d")!;
  renderCmds(ctx, cmds);
  const blob = await new Promise<Blob | null>((r) => canvas.toBlob(r, "image/png"));
  if (!blob) throw new Error("生成图片失败");
  return new Uint8Array(await blob.arrayBuffer());
}
