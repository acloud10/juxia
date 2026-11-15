// 句栖 · 本地存储：优先 RDB（加密），失败时回退 Preferences
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import {
  AppData, Settings, DayState, MetaState, OwnEntry, LibEntry,
  DislikeEntry, MaterialEntry, NoteItem, todayStr, DAY_MS, revisitAtFromDays
} from '../model/Types';
import { Repo } from './Repo';
import { clearLegacyKey } from '../services/LegacyKeyCleanup';
import { splitSentences } from '../utils/TextSplit';
import { UiState } from '../state/UiState';
import { AppError } from '../services/AppError';

const PREF_NAME: string = 'juxia_store';

interface DraftPayload {
  d: string;
  t: string;
}

interface PrefsEnvelope {
  d: string;
  t: string;
}

export class Store {
  private static instance: Store | null = null;
  data: AppData = new AppData();
  private prefs: preferences.Preferences | null = null;
  private ready: boolean = false;
  private repo: Repo | null = null;
  private useDb: boolean = false;
  private fallbackToken: string = '';
  private idSeq: number = 0;

  static get(): Store {
    if (Store.instance === null) {
      Store.instance = new Store();
    }
    return Store.instance;
  }

  private idExists(id: string): boolean {
    return this.data.own.some((e: OwnEntry) => e.id === id) ||
      this.data.lib.some((e: LibEntry) => e.id === id) ||
      this.data.materials.some((e: MaterialEntry) => e.id === id);
  }

  newId(): string {
    let id: string = '';
    do {
      this.idSeq = (this.idSeq + 1) % 46656;
      id = Date.now().toString(36) + this.idSeq.toString(36).padStart(3, '0');
    } while (this.idExists(id));
    return id;
  }

  async init(context: common.UIAbilityContext): Promise<void> {
    if (this.ready) {
      return;
    }
    try {
      this.prefs = await preferences.getPreferences(context, PREF_NAME);
    } catch (e) {
      AppError.report('本地设置读取失败。', '重启应用后再试；不要清空数据。');
      console.error('juxia prefs init fail', String(e));
      return;
    }
    let legacy: AppData | null = null;
    let raw: string = '';
    try {
      const envRaw: string = await this.prefs.get('appdata_v2', '') as string;
      if (envRaw.length > 0) {
        const env = JSON.parse(envRaw) as PrefsEnvelope;
        raw = env.d;
        this.fallbackToken = env.t;
      } else {
        raw = await this.prefs.get('appdata', '') as string;
      }
    } catch (e) {
      AppError.report('本地设置读取失败。', '重启应用后再试；不要清空数据。');
      console.error('juxia prefs read fail', String(e));
      raw = '';
    }
    if (raw.length > 0) {
      try {
        legacy = JSON.parse(raw) as AppData;
      } catch (e) {
        legacy = null;
      }
    }
    try {
      this.repo = new Repo();
      this.data = await this.repo.init(context, legacy);
      this.useDb = true;
    } catch (e) {
      AppError.report('本地数据读取失败。', '数据没有被覆盖；重启应用后再试，先不要清空数据。', true);
      console.error('juxia store init fallback', String(e));
      this.data = legacy !== null ? legacy : new AppData();
      this.useDb = false;
    }
    this.normalize();
    await clearLegacyKey();
    if (this.data.day.date.length === 0) this.data.day.date = todayStr();
    this.ready = true;
    this.rollDay();
    this.persist();
  }

  storageMode(): string {
    return this.useDb ? '本地加密存储' : '本地存储';
  }

  usesDb(): boolean {
    return this.useDb && this.repo !== null;
  }

  private normalize(): void {
    const d = this.data;
    if (!d.own) d.own = [];
    if (!d.lib) d.lib = [];
    if (!d.dislikes) d.dislikes = [];
    if (!d.materials) d.materials = [];
    if (!d.settings) d.settings = new Settings();
    if (d.settings.privacyAccepted === undefined) d.settings.privacyAccepted = false;
    if (!d.day) d.day = new DayState();
    if (!d.meta) d.meta = new MetaState();
    if (d.settings.fontScale === undefined || isNaN(d.settings.fontScale)) d.settings.fontScale = 1.0;
    d.settings.fontScale = Math.max(0.85, Math.min(1.4, d.settings.fontScale));
    if (d.settings.fontScaleFollow === undefined) d.settings.fontScaleFollow = true;
    if (d.settings.bootLong === undefined) d.settings.bootLong = false;
    if (d.settings.bootText === undefined) d.settings.bootText = '';
    if (d.settings.bootHoldMs === undefined || isNaN(d.settings.bootHoldMs)) d.settings.bootHoldMs = 1200;
    d.settings.bootHoldMs = Math.max(300, Math.min(5000, d.settings.bootHoldMs));
    if (d.settings.bootFontScale === undefined || isNaN(d.settings.bootFontScale)) d.settings.bootFontScale = 1.25;
    d.settings.bootFontScale = Math.max(0.8, Math.min(2.5, d.settings.bootFontScale));
    if (d.settings.backupRemindOff === undefined) d.settings.backupRemindOff = false;
    if (d.settings.fullIncludeMaterials === undefined) d.settings.fullIncludeMaterials = true;
    if (d.settings.plainIncludeMaterials === undefined) d.settings.plainIncludeMaterials = true;
    if (d.settings.drawOwn === undefined) d.settings.drawOwn = true;
    if (d.settings.drawLib === undefined) d.settings.drawLib = true;
    if (d.settings.revisitHour === undefined) d.settings.revisitHour = 9;
    if (d.settings.revisitMinute === undefined) d.settings.revisitMinute = 0;
    if (d.settings.nickname === undefined) d.settings.nickname = '';
    if (d.settings.showGreeting === undefined) d.settings.showGreeting = false;
    if (d.settings.showReflect === undefined) d.settings.showReflect = true;
    if (d.settings.showSeal === undefined) d.settings.showSeal = true;
    if (!d.meta.openDays) d.meta.openDays = [];
    if (!d.meta.revisitReminderIds) d.meta.revisitReminderIds = {};
    // 旧数据字段兜底：缺字段的条目会在筛选/搜索时崩，先补齐
    d.lib.forEach((e: LibEntry) => {
      if (e.source === undefined) e.source = '';
      if (e.origin === undefined) e.origin = 'material';
      if (e.tag === undefined) e.tag = '';
      if (e.createdAt === undefined) e.createdAt = 0;
      if (!e.bindIds) e.bindIds = [];
    });
    d.dislikes.forEach((e: DislikeEntry) => {
      if (e.source === undefined) e.source = '';
      if (e.origin === undefined) e.origin = '';
      if (e.at === undefined) e.at = 0;
    });
    if (d.meta.firstUse === 0) d.meta.firstUse = Date.now();
    if (d.settings.skin !== 'plain') d.settings.skin = 'classic';
    if (d.settings.appName.length === 0) d.settings.appName = '句栖';
    // 内置句库已移除：旧版本收藏/排除的内置句一并清掉
    d.lib = d.lib.filter((e: LibEntry) => e.origin !== 'builtin');
    d.dislikes = d.dislikes.filter((e: DislikeEntry) => e.origin !== 'builtin');
    d.own.forEach((e: OwnEntry) => {
      if (!e.bindIds) e.bindIds = [];
      if (!e.notes) e.notes = [];
      if (e.replyToId === undefined) e.replyToId = '';
      if (e.replyFrom === undefined) e.replyFrom = '';
      // 旧数据只有单条 note：迁进 notes，之后只认 notes
      if (e.note !== undefined && e.note.length > 0 && e.notes.length === 0) {
        e.notes.push(new NoteItem(e.createdAt > 0 ? e.createdAt : Date.now(), e.note));
      }
      e.note = '';
    });
  }

  private persist(): void {
    if (this.useDb && this.repo !== null) {
      this.repo.saveAll(this.data);
      return;
    }
    this.persistPrefs();
  }

  private writeOwn(e: OwnEntry): void {
    if (this.useDb && this.repo !== null) {
      this.repo.saveOwnRow(e);
      return;
    }
    this.persistPrefs();
  }

  private writeLib(e: LibEntry): void {
    if (this.useDb && this.repo !== null) {
      this.repo.saveLibRow(e);
      return;
    }
    this.persistPrefs();
  }

  private async persistPrefsNow(restoreToken: string = ''): Promise<void> {
    const p = this.prefs;
    if (p === null) {
      throw new Error('PREFS_NOT_READY');
    }
    this.fallbackToken = restoreToken;
    const env: PrefsEnvelope = { d: JSON.stringify(this.data), t: restoreToken };
    try {
      await p.put('appdata_v2', JSON.stringify(env));
      await p.flush();
    } catch (e) {
      throw new Error('PREFS_WRITE_FAILED');
    }
  }

  private persistPrefs(): void {
    const p = this.prefs;
    if (p === null) return;
    try {
      const env: PrefsEnvelope = { d: JSON.stringify(this.data), t: this.fallbackToken };
      p.put('appdata_v2', JSON.stringify(env)).then(() => {
        try {
          p.flush();
        } catch (e) {
          AppError.report('设置保存失败。', '检查存储空间后重试；若仍失败，重启应用。');
            console.error('juxia prefs flush fail', String(e));
        }
      }).catch((e: Error) => {
        AppError.report('设置保存失败。', '检查存储空间后重试；若仍失败，重启应用。');
      console.error('juxia prefs put fail', String(e));
      });
    } catch (e) {
      AppError.report('设置保存失败。', '重启应用后再试。');
      console.error('juxia prefs serialize fail', String(e));
    }
  }

  bump(): void {
    const v: number = UiState.get().dataVersion;
    UiState.get().dataVersion = v + 1;
  }

  // ---------- 每日 ----------
  recordOpen(): void {
    const t: string = todayStr();
    if (!this.data.meta.openDays.includes(t)) {
      this.data.meta.openDays.push(t);
      this.data.meta.openDays.sort();
      this.persist();
    }
  }

  rollDay(): boolean {
    this.recordOpen();
    const t: string = todayStr();
    if (this.data.day.date !== t) {
      this.data.day = new DayState();
      this.data.day.date = t;
      this.persist();
      this.bump();
      return true;
    }
    return false;
  }

  dayCount(): number {
    const n: number = this.data.meta.openDays.length;
    return n > 0 ? n : 1;
  }

  markDrew(): void {
    this.data.day.drew = true;
    this.saveKv();
    this.bump();
  }

  // ---------- 查询 ----------
  ownActive(kind: string): OwnEntry[] {
    return this.data.own.filter((e: OwnEntry) => e.kind === kind && e.archAt === 0);
  }

  archived(): OwnEntry[] {
    const list: OwnEntry[] = this.data.own.filter((e: OwnEntry) => e.archAt > 0);
    list.sort((a: OwnEntry, b: OwnEntry) => b.archAt - a.archAt);
    return list;
  }

  postponeMissedRevisits(): number {
    const now: number = Date.now();
    const today: string = todayStr(new Date(now));
    const hour: number = this.data.settings.revisitHour;
    const minute: number = this.data.settings.revisitMinute;
    let moved: number = 0;
    const target = new Date(now);
    this.data.own.forEach((e: OwnEntry) => {
      if (e.archAt <= 0 || e.revisitAt <= 0 || e.revisitAt > now) return;
      if (e.snoozeUntil > now) return;
      const dueDay: string = todayStr(new Date(e.revisitAt));
      if (dueDay >= today) return;
      target.setTime(now);
      target.setHours(hour, minute, 0, 0);
      if (target.getTime() <= now) {
        target.setDate(target.getDate() + 1);
      }
      e.revisitAt = target.getTime();
      e.snoozeUntil = 0;
      moved++;
    });
    if (moved > 0) {
      this.persist();
      this.bump();
    }
    return moved;
  }

  revisitDue(): OwnEntry[] {
    const now: number = Date.now();
    const list: OwnEntry[] = this.data.own.filter((e: OwnEntry) =>
      e.archAt > 0 && e.revisitAt > 0 && e.revisitAt <= now &&
      (e.snoozeUntil === 0 || e.snoozeUntil <= now));
    list.sort((a: OwnEntry, b: OwnEntry) => a.revisitAt - b.revisitAt);
    return list;
  }

  dislikedSet(): Set<string> {
    const s = new Set<string>();
    this.data.dislikes.forEach((d: DislikeEntry) => {
      s.add(d.text);
    });
    return s;
  }

  libPool(): LibEntry[] {
    const dis = this.dislikedSet();
    return this.data.lib.filter((e: LibEntry) => !dis.has(e.text));
  }

  // ---------- 写入 ----------
  addOwn(kind: string, text: string): void {
    const e = new OwnEntry();
    e.id = this.newId();
    e.kind = kind;
    e.text = text;
    e.createdAt = Date.now();
    this.data.own.unshift(e);
    this.data.day.wrote = true;
    this.writeOwn(e);
    this.bump();
  }

  addReply(sourceId: string, text: string, from: string = ''): boolean {
    const body: string = text.trim();
    if (body.length === 0) return false;
    const e = new OwnEntry();
    e.id = this.newId();
    e.kind = 'reply';
    e.text = body;
    e.replyToId = sourceId;
    e.replyFrom = from;
    e.createdAt = Date.now();
    this.data.own.unshift(e);
    this.writeOwn(e);
    this.bump();
    return true;
  }

  repliesOf(sourceId: string): OwnEntry[] {
    return this.data.own.filter((e: OwnEntry) => e.kind === 'reply' && e.replyToId === sourceId);
  }

  addReflect(text: string): boolean {
    const body: string = text.trim();
    if (body.length === 0) return false;
    const e = new OwnEntry();
    e.id = this.newId();
    e.kind = 'reflect';
    e.text = body;
    e.createdAt = Date.now();
    this.data.own.unshift(e);
    this.writeOwn(e);
    this.bump();
    return true;
  }

  reflects(): OwnEntry[] {
    return this.data.own
      .filter((e: OwnEntry) => e.kind === 'reflect')
      .sort((a: OwnEntry, b: OwnEntry) => b.createdAt - a.createdAt);
  }

  updateOwnText(id: string, text: string): boolean {
    const body: string = text.trim();
    if (body.length === 0) return false;
    const e = this.data.own.find((x: OwnEntry) => x.id === id);
    if (e === undefined) return false;
    e.text = body;
    this.writeOwn(e);
    this.bump();
    return true;
  }

  addLib(text: string, source: string, origin: string, tag: string): boolean {
    const exists: boolean = this.data.lib.some((e: LibEntry) => e.text === text);
    if (exists) return false;
    const e = new LibEntry();
    e.id = this.newId();
    e.text = text;
    e.source = source;
    e.origin = origin;
    e.tag = tag;
    e.createdAt = Date.now();
    this.data.lib.unshift(e);
    this.writeLib(e);
    this.bump();
    return true;
  }

  addDislike(text: string, source: string, origin: string): void {
    if (text.length === 0) return;
    const exists: boolean = this.data.dislikes.some((d: DislikeEntry) => d.text === text);
    let added: DislikeEntry | null = null;
    if (!exists) {
      const d = new DislikeEntry();
      d.text = text;
      d.source = source;
      d.origin = origin;
      d.at = Date.now();
      this.data.dislikes.push(d);
      added = d;
    }
    const removed: LibEntry[] = this.data.lib.filter((e: LibEntry) => e.text === text);
    this.data.lib = this.data.lib.filter((e: LibEntry) => e.text !== text);
    if (this.useDb && this.repo !== null) {
      if (added !== null) this.repo.saveDislikeRow(added);
      removed.forEach((e: LibEntry) => {
        this.repo?.deleteLibRow(e.id);
      });
    } else {
      this.persistPrefs();
    }
    this.bump();
  }

  addMaterial(name: string, text: string): MaterialEntry {
    const m = new MaterialEntry();
    m.id = this.newId();
    m.name = name;
    m.text = text;
    m.createdAt = Date.now();
    this.data.materials.push(m);
    this.persist();
    this.bump();
    return m;
  }

  async reindexMaterial(id: string, text: string): Promise<void> {
    if (this.repo === null) return;
    const sentences: string[] = splitSentences(text);
    await this.repo.replaceSentences(id, sentences);
  }

  addMaterialFile(name: string, path: string, size: number): MaterialEntry {
    const m = new MaterialEntry();
    m.id = this.newId();
    m.name = name;
    m.path = path;
    m.size = size;
    m.text = '';
    m.createdAt = Date.now();
    this.data.materials.push(m);
    this.persist();
    this.bump();
    return m;
  }

  indexMaterial(id: string, text: string): void {
    if (this.repo === null) return;
    const sentences: string[] = splitSentences(text);
    this.repo.replaceSentences(id, sentences);
  }

  materialSentences(materialId: string, limit: number = 0): Promise<string[]> {
    if (this.repo !== null) {
      return this.repo.allSentences(materialId, limit);
    }
    return Promise.resolve([]);
  }

  searchMaterial(keywords: string[], materialId: string): Promise<string[]> {
    if (this.repo !== null) {
      return this.repo.searchSentences(keywords, materialId);
    }
    return Promise.resolve([]);
  }

  async appendMaterialSentences(id: string, startOrd: number, sentences: string[]): Promise<number> {
    if (this.repo !== null) {
      return await this.repo.appendSentences(id, startOrd, sentences);
    }
    return 0;
  }

  clearMaterialIndex(id: string): void {
    if (this.repo !== null) {
      this.repo.clearSentences(id);
    }
  }

  updateMaterial(id: string, name: string, text: string): void {
    const m = this.data.materials.find((x: MaterialEntry) => x.id === id);
    if (!m) return;
    m.name = name;
    m.text = text;
    this.persist();
    this.bump();
  }

  attachMaterialFile(id: string, name: string, path: string, size: number): void {
    const m = this.data.materials.find((x: MaterialEntry) => x.id === id);
    if (m !== undefined) {
      m.name = name;
      m.path = path;
      m.size = size;
      m.text = '';
    } else {
      const n = new MaterialEntry();
      n.id = id;
      n.name = name;
      n.path = path;
      n.size = size;
      n.createdAt = Date.now();
      this.data.materials.push(n);
    }
    this.persist();
    this.bump();
  }

  deleteMaterial(id: string): void {
    this.data.materials = this.data.materials.filter((x: MaterialEntry) => x.id !== id);
    this.clearMaterialIndex(id);
    if (this.useDb && this.repo !== null) {
      this.repo.deleteMaterialRow(id);
    } else {
      this.persistPrefs();
    }
    this.bump();
  }

  resetAll(): void {
    this.data = new AppData();
    this.data.meta.firstUse = Date.now();
    this.data.day = new DayState();
    this.data.day.date = todayStr();
    this.normalize();
    clearLegacyKey();
    if (this.repo !== null) {
      this.repo.clearAllSentences();
    }
    this.persist();
    this.bump();
  }

  async replaceAll(d: AppData, restoreToken: string): Promise<void> {
    const previous: AppData = this.data;
    const previousToken: string = this.fallbackToken;
    this.data = d;
    this.normalize();
    try {
      if (this.useDb && this.repo !== null) {
        await this.repo.replaceAll(this.data, restoreToken);
      } else {
        await this.persistPrefsNow(restoreToken);
      }
    } catch (e) {
      this.data = previous;
      this.fallbackToken = previousToken;
      throw new Error('REPLACE_ALL_FAILED');
    }
    this.rollDay();
    this.bump();
  }

  async restoreToken(): Promise<string> {
    if (this.repo !== null) {
      return await this.repo.restoreToken();
    }
    return this.fallbackToken;
  }

  async flush(): Promise<void> {
    if (this.useDb && this.repo !== null) {
      await this.repo.flush();
      return;
    }
    if (this.prefs !== null) {
      await this.persistPrefsNow(this.fallbackToken);
    }
  }

  private catLabel(cat: string): string {
    if (cat === 'resolved') return '已解决';
    if (cat === 'letgo') return '已放下';
    if (cat === 'silly') return '看起来很蠢';
    if (cat === 'tired') return '听腻了';
    return cat;
  }

  footLines(e: OwnEntry): string[] {
    const out: string[] = [];
    const seen: string[] = [];
    e.bindIds.forEach((id: string) => {
      if (seen.includes(id)) return;
      seen.push(id);
      const w = this.data.own.find((x: OwnEntry) => x.id === id);
      if (!w || w.kind !== 'wound' || w.archAt <= 0) return;
      const short: string = w.text.length > 30 ? w.text.slice(0, 30) + '…' : w.text;
      const dt = new Date(w.archAt);
      const md: string = `${dt.getMonth() + 1}月${dt.getDate()}日`;
      out.push(`它曾陪我度过「${short}」，那件事于 ${md} 标记为「${this.catLabel(w.archCat)}」。`);
    });
    return out;
  }

  archiveOwn(id: string, cat: string, note: string, revisitDays: number): void {
    const e = this.data.own.find((x: OwnEntry) => x.id === id);
    if (!e) return;
    e.archCat = cat;
    e.archNote = note;
    e.archAt = Date.now();
    if (e.kind === 'wound' && revisitDays > 0) {
      e.revisitAt = revisitAtFromDays(revisitDays, this.data.settings.revisitHour, this.data.settings.revisitMinute);
    } else if (e.kind === 'wound') {
      e.revisitAt = 0;
      e.snoozeUntil = 0;
    }
    this.writeOwn(e);
    this.bump();
  }

  addNote(id: string, text: string): void {
    const e = this.data.own.find((x: OwnEntry) => x.id === id);
    if (!e) return;
    e.notes.push(new NoteItem(Date.now(), text));
    this.writeOwn(e);
    this.bump();
  }

  setNote(id: string, text: string): boolean {
    const e = this.data.own.find((x: OwnEntry) => x.id === id);
    if (!e) return false;
    if (e.notes.length > 0) {
      e.notes[e.notes.length - 1].text = text;
      e.notes[e.notes.length - 1].at = Date.now();
    } else {
      e.notes.push(new NoteItem(Date.now(), text));
    }
    e.note = '';
    this.writeOwn(e);
    this.bump();
    return true;
  }

  toggleBind(encId: string, woundId: string): boolean {
    const enc = this.data.own.find((x: OwnEntry) => x.id === encId);
    if (!enc) return false;
    if (enc.bindIds.includes(woundId)) {
      enc.bindIds = enc.bindIds.filter((x: string) => x !== woundId);
      this.writeOwn(enc);
      this.bump();
      return false;
    }
    enc.bindIds.push(woundId);
    this.writeOwn(enc);
    this.bump();
    return true;
  }

  toggleLibBind(libId: string, ownId: string): boolean {
    const e = this.data.lib.find((x: LibEntry) => x.id === libId);
    if (!e) return false;
    if (e.bindIds.includes(ownId)) {
      e.bindIds = e.bindIds.filter((x: string) => x !== ownId);
      this.writeLib(e);
      this.bump();
      return false;
    }
    e.bindIds.push(ownId);
    this.writeLib(e);
    this.bump();
    return true;
  }

  libBoundTo(ownId: string): LibEntry[] {
    return this.data.lib.filter((e: LibEntry) => e.bindIds.includes(ownId));
  }

  removeLib(id: string): void {
    this.data.lib = this.data.lib.filter((e: LibEntry) => e.id !== id);
    if (this.useDb && this.repo !== null) {
      this.repo.deleteLibRow(id);
    } else {
      this.persistPrefs();
    }
    this.bump();
  }

  removeOwn(id: string): void {
    const e = this.data.own.find((x: OwnEntry) => x.id === id);
    if (!e) return;
    this.data.own = this.data.own.filter((x: OwnEntry) => x.id !== id);
    const touchedLib: LibEntry[] = [];
    this.data.lib.forEach((l: LibEntry) => {
      if (l.bindIds.includes(id)) {
        l.bindIds = l.bindIds.filter((b: string) => b !== id);
        touchedLib.push(l);
      }
    });
    if (this.useDb && this.repo !== null) {
      this.repo.deleteOwnRow(id);
      touchedLib.forEach((l: LibEntry) => this.repo?.saveLibRow(l));
    } else {
      this.persistPrefs();
    }
    this.clearDraft('note_' + id);
    this.bump();
  }

  removeLatestNote(id: string): boolean {
    const e = this.data.own.find((x: OwnEntry) => x.id === id);
    if (!e || e.notes.length === 0) return false;
    e.notes.pop();
    e.note = '';
    this.writeOwn(e);
    this.bump();
    return true;
  }

  revive(id: string): void {
    const e = this.data.own.find((x: OwnEntry) => x.id === id);
    if (!e) return;
    e.archAt = 0;
    e.archCat = '';
    e.archNote = '';
    e.revisitAt = 0;
    e.snoozeUntil = 0;
    this.writeOwn(e);
    this.bump();
  }

  setRevisit(id: string, days: number): void {
    const e = this.data.own.find((x: OwnEntry) => x.id === id);
    if (!e) return;
    e.revisitAt = revisitAtFromDays(days, this.data.settings.revisitHour, this.data.settings.revisitMinute);
    e.snoozeUntil = 0;
    this.writeOwn(e);
    this.bump();
  }

  setRevisitAt(id: string, at: number): void {
    const e = this.data.own.find((x: OwnEntry) => x.id === id);
    if (!e) return;
    e.revisitAt = at;
    e.snoozeUntil = 0;
    this.writeOwn(e);
    this.bump();
  }

  clearRevisit(id: string): void {
    const e = this.data.own.find((x: OwnEntry) => x.id === id);
    if (!e) return;
    e.revisitAt = 0;
    e.snoozeUntil = 0;
    this.writeOwn(e);
    this.bump();
  }

  snoozeRevisit(id: string, days: number): void {
    const e = this.data.own.find((x: OwnEntry) => x.id === id);
    if (!e) return;
    e.snoozeUntil = Date.now() + days * DAY_MS;
    this.writeOwn(e);
    this.bump();
  }

  saveKv(): void {
    if (this.useDb && this.repo !== null) {
      this.repo.saveKv(this.data);
      this.bump();
      return;
    }
    this.persistPrefs();
    this.bump();
  }

  saveSettings(): void {
    this.persist();
    this.bump();
  }

  guideDone(): boolean {
    const p = this.prefs;
    if (p === null) return false;
    try {
      return (p.getSync('guide_done', '0') as string) === '1';
    } catch (e) {
      return false;
    }
  }

  markGuideDone(): void {
    const p = this.prefs;
    if (p === null) return;
    try {
      p.putSync('guide_done', '1');
      p.flushSync();
    } catch (e) {
      console.error('juxia guide flag fail', String(e));
    }
  }

  // ---------- 草稿（只写 Preferences，不进主数据，避免全量重写） ----------
  saveDraft(kind: string, text: string): void {
    const p = this.prefs;
    if (p === null) return;
    try {
      p.putSync('draft_' + kind, JSON.stringify({ d: todayStr(), t: text }));
      p.flushSync();
    } catch (e) {
      console.error('juxia draft save fail', kind, String(e));
    }
  }

  loadDraft(kind: string): string {
    const p = this.prefs;
    if (p === null) return '';
    try {
      const raw: string = p.getSync('draft_' + kind, '') as string;
      if (raw.length === 0) return '';
      const o = JSON.parse(raw) as DraftPayload;
      if (o.d === todayStr()) return o.t ?? '';
    } catch (e) {
      console.error('juxia draft load fail', kind, String(e));
    }
    return '';
  }

  clearDraft(kind: string): void {
    const p = this.prefs;
    if (p === null) return;
    try {
      p.deleteSync('draft_' + kind);
      p.flushSync();
    } catch (e) {
      console.error('juxia draft clear fail', kind, String(e));
    }
  }
}


