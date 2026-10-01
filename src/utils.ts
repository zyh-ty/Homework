export function parseDate(s: string): Date {
  const [y, m, d] = s.split("-").map(Number);
  return new Date(y, m - 1, d);
}

export function fmt(d: Date): string {
  const p = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}

export function addDays(s: string, n: number): string {
  const d = parseDate(s);
  d.setDate(d.getDate() + n);
  return fmt(d);
}

export function mondayOf(s: string): string {
  const d = parseDate(s);
  const wd = (d.getDay() + 6) % 7;
  d.setDate(d.getDate() - wd);
  return fmt(d);
}

export function dotDate(s: string): string {
  const [y, m, d] = s.split("-");
  return `${y}.${Number(m)}.${Number(d)}`;
}
