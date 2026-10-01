import { fontStr, W, H, type DrawCmd } from "./layout";
import badgeUrl from "./assets/badge.png";

let badge: HTMLImageElement | null = null;

export function loadBadge(): Promise<void> {
  return new Promise((resolve) => {
    const img = new Image();
    img.onload = () => {
      badge = img;
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
      ctx.fillText(c.text, c.x, c.y);
    } else if (c.kind === "image") {
      if (badge) ctx.drawImage(badge, c.x, c.y, c.w, c.h);
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
