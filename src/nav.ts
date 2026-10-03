export type Section = "ann" | "hw" | "speech" | "sched";

export const SECTION_KEYS: Record<string, Section> = {
  "1": "ann",
  "2": "hw",
  "3": "speech",
  "4": "sched",
};

function reveal(el: HTMLElement | undefined) {
  el?.focus();
  el?.scrollIntoView({ block: "nearest" });
}

export function focusSection(section: Section) {
  reveal(document.querySelector<HTMLElement>(`[data-nav="${section}"]`) ?? undefined);
}

export function moveRow(delta: number) {
  const rows = [...document.querySelectorAll<HTMLElement>("[data-nav]")];
  if (rows.length === 0) return;
  const cur = document.activeElement as HTMLElement | null;
  const i = cur ? rows.indexOf(cur) : -1;
  if (i < 0) {
    reveal(rows[delta > 0 ? 0 : rows.length - 1]);
    return;
  }
  reveal(rows[Math.max(0, Math.min(rows.length - 1, i + delta))]);
}
