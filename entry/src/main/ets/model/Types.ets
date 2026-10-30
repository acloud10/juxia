// 句栖 · 数据模型（从 HTML 版逐字段迁移）
export const DAY_MS: number = 86400000;

export class Settings {
  ritualMode: string = 'full'; // 可选：full、short、off
  revisitDays: number = 90;
  revisitHour: number = 9;
  revisitMinute: number = 0;
  theme: string = 'system'; // 可选：system、light、dark
  skin: string = 'classic'; // 可选：classic、plain
  showDays: boolean = true;
  appName: string = '句栖';
  bootLong: boolean = false;
  bootText: string = '';
  bootHoldMs: number = 1200;
  bootFontScale: number = 1.25;
  backupRemindOff: boolean = false;
  drawCount: number = 0;
  drawOwn: boolean = true;
  drawLib: boolean = true;
  nickname: string = '';
  showGreeting: boolean = false;
  showReflect: boolean = true;
  fontScale: number = 1.0;
  fontScaleFollow: boolean = true;
  privacyAccepted: boolean = false;
}

export class DayState {
  date: string = '';
  mood: string = ''; // 可选：空、good、bad
  wrote: boolean = false;
  drew: boolean = false;
  backupDismissed: boolean = false;
}

export class MetaState {
  firstUse: number = 0;
  seen: boolean = false;
  lastBackupAt: number = 0;
  openDays: string[] = [];
  revisitReminderIds: Record<string, number> = {};
}

export class NoteItem {
  at: number = 0;
  text: string = '';
  constructor(at: number, text: string) {
    this.at = at;
    this.text = text;
  }
}

export class OwnEntry {
  id: string = '';
  kind: string = 'encourage'; // 可选：encourage、wound
  text: string = '';
  note: string = '';
  bindIds: string[] = [];
  createdAt: number = 0;
  archCat: string = '';
  archNote: string = '';
  archAt: number = 0;
  revisitAt: number = 0;
  snoozeUntil: number = 0;
  foot: string[] = [];
  notes: NoteItem[] = [];
  replyToId: string = '';

  isArchived(): boolean {
    return this.archAt > 0;
  }
}

export class LibEntry {
  id: string = '';
  text: string = '';
  source: string = '';
  origin: string = 'material';
  tag: string = '';
  createdAt: number = 0;
  bindIds: string[] = [];
}

export class DislikeEntry {
  text: string = '';
  source: string = '';
  origin: string = '';
  at: number = 0;
}

export class MaterialEntry {
  id: string = '';
  name: string = '';
  text: string = '';
  path: string = '';
  size: number = 0;
  createdAt: number = 0;
}

export class AppData {
  version: number = 2;
  own: OwnEntry[] = [];
  lib: LibEntry[] = [];
  dislikes: DislikeEntry[] = [];
  materials: MaterialEntry[] = [];
  settings: Settings = new Settings();
  day: DayState = new DayState();
  meta: MetaState = new MetaState();
}

// 抽签上下文：own（自己的话）/ lib（句库）
export class RitualCtx {
  type: string = 'lib';
  badge: string = '';
  tag: string = '';
  text: string = '';
  source: string = '';
  origin: string = '';
  entry: OwnEntry | null = null;
  todayFlow: boolean = false;
}

export function todayStr(d: Date = new Date()): string {
  const y: number = d.getFullYear();
  const m: string = (d.getMonth() + 1).toString().padStart(2, '0');
  const day: string = d.getDate().toString().padStart(2, '0');
  return `${y}-${m}-${day}`;
}

export function fmtDate(ts: number): string {
  const d = new Date(ts);
  return `${d.getFullYear()}年${d.getMonth() + 1}月${d.getDate()}日`;
}

export function fmtMD(ts: number): string {
  const d = new Date(ts);
  return `${d.getMonth() + 1}月${d.getDate()}日`;
}

// N 天后的指定时刻；时间点由设置里的回访时间决定
export function revisitAtFromDays(days: number, hour: number = 9, minute: number = 0): number {
  const d = new Date();
  d.setDate(d.getDate() + Math.max(1, days));
  d.setHours(hour, minute, 0, 0);
  return d.getTime();
}

export function uid(): string {
  return Date.now().toString(36) + Math.random().toString(36).slice(2, 8);
}

export function weekdayCN(d: Date): string {
  const names: string[] = ['日', '一', '二', '三', '四', '五', '六'];
  return names[d.getDay()];
}

const CND: string[] = ['〇', '一', '二', '三', '四', '五', '六', '七', '八', '九'];

export function sealCN(ds: string): string {
  const parts: string[] = ds.split('-');
  const out: string[] = [];
  for (let i = 0; i < parts.length; i++) {
    let s: string = '';
    const chars: string[] = parts[i].split('');
    for (let j = 0; j < chars.length; j++) {
      const n: number = Number(chars[j]);
      s += (n >= 0 && n <= 9) ? CND[n] : chars[j];
    }
    out.push(s);
  }
  return out.join('·');
}


