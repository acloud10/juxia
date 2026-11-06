// 句栖 · 设置（皮肤 / 主题 / 仪式 / 应用名 / 密语备份）

import { common } from '@kit.AbilityKit';
import { picker, fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { zlib } from '@kit.BasicServicesKit';
import { Store } from '../data/Store';
import { AppData, MaterialEntry, uid } from '../model/Types';
import { BackupService } from '../services/BackupService';
import { ReminderService } from '../services/ReminderService';
import { MaterialIndexer } from '../services/MaterialIndexer';
import { Tokens, getTokens, FONT_SERIF } from '../theme/Theme';
import { UiState } from '../state/UiState';
import { AppError } from '../services/AppError';


class MatPackItem {
  id: string = '';
  name: string = '';
  size: number = 0;
}

class FullManifest {
  format: string = 'juxia-full';
  version: number = 1;
  createdAt: number = 0;
  dataBytes: number = 0;
  materialCount: number = 0;
  includeMaterials: boolean = false;
}

@ComponentV2
export struct SettingsPage {
  @Param skin: string = 'classic';
  @Param dark: boolean = false;
  @Local ui: UiState = UiState.get();
  private get appName(): string { return this.ui.appName; }
  private get settingsSection(): string { return this.ui.settingsSection; }
  @Local openSection: string = 'ui';
  @Local theme: string = 'system';
  @Local fontScale: number = 1.0;
  @Local fontScaleFollow: boolean = true;
  @Local ritualMode: string = 'full';
  @Local showDays: boolean = true;
  @Local backupRemindOff: boolean = false;
  @Local bootLong: boolean = false;
  @Local bootTextInput: string = '';
  @Local bootHold: number = 1200;
  @Local bootFont: number = 1.25;
  private bootSaveTimer: number = -1;
  @Local bootTuning: boolean = false;
  @Local nameInput: string = '';
  @Local fullPw: string = '';
  @Local fullPw2: string = '';
  @Local fullPanel: string = '';
  @Local fullIncludeMaterials: boolean = true;
  @Local plainPanel: string = '';
  @Local plainIncludeMaterials: boolean = true;
  @Local busy: boolean = false;
  @Local selfTestMsg: string = '';
  @Local revisitDays: number = 90;
  @Local revisitHour: number = 9;
  @Local revisitMinute: number = 0;
  @Local draftHour: number = 9;
  @Local draftMinute: number = 0;
  @Local clockOpen: boolean = false;
  @Local daysInput: string = '';
  @Local nickname: string = '';
  @Local showGreeting: boolean = false;
  @Local showReflect: boolean = true;
  @Local drawOwn: boolean = true;
  @Local drawLib: boolean = true;

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (e) {
      console.error('juxia toast fail', String(e));
    }
  }

  aboutToAppear(): void {
    this.load();
  }

  @Monitor('ui.settingsSection')
  onSectionReq(monitor: IMonitor): void {
    this.openSection = this.ui.settingsSection;
  }

  private load(): void {
    const s = Store.get().data.settings;
    this.theme = s.theme;
    this.fontScale = s.fontScale;
    this.fontScaleFollow = s.fontScaleFollow;
    this.ritualMode = s.ritualMode;
    this.showDays = s.showDays;
    this.backupRemindOff = s.backupRemindOff;
    this.bootLong = s.bootLong;
    this.bootTextInput = s.bootText;
    this.bootHold = s.bootHoldMs;
    this.bootFont = s.bootFontScale;
    this.nameInput = s.appName;
    this.revisitDays = s.revisitDays;
    this.revisitHour = s.revisitHour;
    this.revisitMinute = s.revisitMinute;
    this.draftHour = s.revisitHour;
    this.draftMinute = s.revisitMinute;
    this.nickname = s.nickname;
    this.showGreeting = s.showGreeting;
    this.showReflect = s.showReflect;
    this.drawOwn = s.drawOwn;
    this.drawLib = s.drawLib;
  }

  private t(): Tokens {
    return getTokens(this.skin, this.dark);
  }

  private applyDark(theme: string): void {
    const sys: boolean = this.ui.systemDark;
    const d: boolean = theme === 'dark' || (theme === 'system' && sys);
    this.ui.dark = d;
  }

  private setSkin(v: string): void {
    Store.get().data.settings.skin = v;
    Store.get().saveKv();
    this.ui.skin = v;
  }

  private setTheme(v: string): void {
    Store.get().data.settings.theme = v;
    Store.get().saveKv();
    this.theme = v;
    this.ui.themeMode = v;
    this.applyDark(v);
  }

  private setFontScale(v: number): void {
    this.fontScale = v;
    this.fontScaleFollow = false;
    UiState.get().fontFollow = false;
    const st = Store.get();
    st.data.settings.fontScale = v;
    st.data.settings.fontScaleFollow = false;
    st.saveKv();
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      setTimeout(() => {
        ctx.getApplicationContext().setFontSizeScale(v);
      }, 30) as number;
    } catch (e) {
      // 旧系统不支持时保持原字号
    }
  }

  private followSystemFont(): void {
    this.fontScaleFollow = true;
    UiState.get().fontFollow = true;
    const st = Store.get();
    st.data.settings.fontScaleFollow = true;
    st.saveKv();
    const sys: number = UiState.get().systemFontScale;
    setTimeout(() => {
      try {
        const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
        ctx.getApplicationContext().setFontSizeScale(sys);
      } catch (e) {
        console.error('juxia system font scale fail', String(e));
      }
    }, 30) as number;
  }

  private setRitual(v: string): void {
    Store.get().data.settings.ritualMode = v;
    Store.get().saveKv();
    this.ritualMode = v;
  }

  private setDays(v: number): void {
    if (v < 1 || v > 3650) {
      this.toast('天数要在 1 到 3650 之间');
      return;
    }
    Store.get().data.settings.revisitDays = v;
    Store.get().saveKv();
    this.revisitDays = v;
    this.daysInput = '';
  }

  private confirmRevisitClock(): void {
    this.revisitHour = this.draftHour;
    this.revisitMinute = this.draftMinute;
    const st = Store.get();
    st.data.settings.revisitHour = this.draftHour;
    st.data.settings.revisitMinute = this.draftMinute;
    // 已经约好的回访跟着改到新时刻，否则只改设置对它们无效
    const now: number = Date.now();
    st.data.own.forEach((e) => {
      if (e.revisitAt <= now) return;
      const d = new Date(e.revisitAt);
      d.setHours(this.draftHour, this.draftMinute, 0, 0);
      e.revisitAt = d.getTime();
      e.snoozeUntil = 0;
    });
    st.saveKv();
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    ReminderService.rescheduleAll(ctx);
    this.toast(`回访时间已定为 ${this.draftHour.toString().padStart(2, '0')}:${this.draftMinute.toString().padStart(2, '0')}`);
  }

  private saveNickname(): void {
    const v: string = this.nickname.trim().slice(0, 12);
    Store.get().data.settings.nickname = v;
    Store.get().data.settings.showGreeting = v.length > 0 ? this.showGreeting : false;
    Store.get().saveKv();
    this.nickname = v;
    this.showGreeting = Store.get().data.settings.showGreeting;
    UiState.get().nickname = v;
    this.toast(v.length > 0 ? `好，以后叫你「${v}」` : '已清除称呼');
  }

  private toggleGreeting(): void {
    if (this.nickname.trim().length === 0) {
      this.toast('先在上面写一个称呼');
      return;
    }
    this.showGreeting = !this.showGreeting;
    Store.get().data.settings.showGreeting = this.showGreeting;
    Store.get().saveKv();
  }

  private toggleShowReflect(): void {
    this.showReflect = !this.showReflect;
    Store.get().data.settings.showReflect = this.showReflect;
    Store.get().saveKv();
  }

  private toggleDrawOwn(): void {
    if (this.drawOwn && !this.drawLib) {
      this.toast('至少留一个来源；想关掉它，先打开「句库收藏」');
      return;
    }
    this.drawOwn = !this.drawOwn;
    Store.get().data.settings.drawOwn = this.drawOwn;
    Store.get().saveKv();
  }

  private toggleDrawLib(): void {
    if (this.drawLib && !this.drawOwn) {
      this.toast('至少留一个来源；想关掉它，先打开「自己的话」');
      return;
    }
    this.drawLib = !this.drawLib;
    Store.get().data.settings.drawLib = this.drawLib;
    Store.get().saveKv();
  }

  private toggleBootLong(): void {
    this.bootLong = !this.bootLong;
    const st = Store.get();
    st.data.settings.bootLong = this.bootLong;
    st.data.settings.bootText = this.bootTextInput.trim();
    st.saveKv();
    if (this.bootLong && st.data.settings.bootText.length === 0) {
      this.toast('已开启，但文案为空，启动不会停留');
    }
  }

  private saveBootText(): void {
    const v: string = this.bootTextInput.trim().slice(0, 24);
    this.bootTextInput = v;
    const st = Store.get();
    st.data.settings.bootText = v;
    st.saveKv();
    this.toast(v.length > 0 ? '启动文案已保存' : '启动文案已清空');
  }

  private queueBootSave(): void {
    if (this.bootSaveTimer >= 0) {
      clearTimeout(this.bootSaveTimer);
    }
    this.bootSaveTimer = setTimeout(() => {
      this.saveBootHold(this.bootHold);
      this.saveBootFont(this.bootFont);
    }, 400) as number;
  }

  private saveBootHold(v: number): void {
    const t: number = Math.max(300, Math.min(5000, v));
    this.bootHold = t;
    const st = Store.get();
    st.data.settings.bootHoldMs = t;
    st.saveKv();
  }

  private saveBootFont(v: number): void {
    const t: number = Math.max(0.8, Math.min(2.5, v));
    this.bootFont = t;
    const st = Store.get();
    st.data.settings.bootFontScale = t;
    st.saveKv();
  }

  private saveName(): void {
    const v: string = this.nameInput.trim().slice(0, 6);
    Store.get().data.settings.appName = v.length > 0 ? v : '句栖';
    Store.get().saveKv();
    UiState.get().appName = Store.get().data.settings.appName;
    this.nameInput = Store.get().data.settings.appName;
    this.toast(`好，就叫「${this.nameInput}」`);
  }

  private applyLoadedSettings(): void {
    const st = Store.get();
    UiState.get().skin = st.data.settings.skin;
    UiState.get().appName = st.data.settings.appName;
    UiState.get().showDays = st.data.settings.showDays;
    UiState.get().dayCount = st.dayCount();
    this.applyDark(st.data.settings.theme);
    this.load();
  }

  private pwWeak(pw: string): boolean {
    const list: string[] = ['我爱你', '密码', '123456', '12345678', '123456789', 'password',
      'qwerty', 'abc123', '111111', '000000', '5201314', 'woaini', 'admin'];
    return list.indexOf(pw) >= 0;
  }

  private pwScore(pw: string): number {
    let s: number = 0;
    if (pw.length >= 6) s++;
    if (pw.length >= 10) s++;
    if (pw.length >= 16) s++;
    let digit: boolean = false;
    let lower: boolean = false;
    let upper: boolean = false;
    let cjk: boolean = false;
    let sym: boolean = false;
    for (let i = 0; i < pw.length; i++) {
      const c: number = pw.charCodeAt(i);
      if (c >= 48 && c <= 57) digit = true;
      else if (c >= 97 && c <= 122) lower = true;
      else if (c >= 65 && c <= 90) upper = true;
      else if (c >= 0x4e00 && c <= 0x9fff) cjk = true;
      else sym = true;
    }
    let classes: number = 0;
    if (digit) classes++;
    if (lower) classes++;
    if (upper) classes++;
    if (cjk) classes++;
    if (sym) classes++;
    if (classes >= 2) s++;
    if (classes >= 3) s++;
    return Math.max(1, Math.min(4, s));
  }

  private findFile(root: string, name: string): string {
    try {
      const files: string[] = fs.listFileSync(root, { recursion: true });
      for (const f of files) {
        if (f === name || f.endsWith('/' + name)) {
          return f.startsWith('/') ? root + f : root + '/' + f;
        }
      }
    } catch (e) {
      console.error('juxia backup file search fail', String(e));
    }
    return '';
  }

  private writeFullManifest(dir: string, dataPath: string, materialCount: number,
    includeMaterials: boolean, createdAt: number): void {
    const st = fs.statSync(dataPath);
    const m: FullManifest = new FullManifest();
    m.createdAt = createdAt;
    m.dataBytes = st.size;
    m.materialCount = materialCount;
    m.includeMaterials = includeMaterials;
    const f = fs.openSync(dir + '/manifest.json', fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
    fs.writeSync(f.fd, JSON.stringify(m));
    fs.closeSync(f);
  }

  private verifyFullManifest(baseDir: string, dataPath: string, d: AppData): void {
    const manifestPath: string = this.findFile(baseDir, 'manifest.json');
    if (manifestPath.length === 0) return;
    let m: FullManifest;
    try {
      const text: string = util.TextDecoder.create('utf-8').decodeToString(this.readAllBytes(manifestPath));
      m = JSON.parse(text) as FullManifest;
    } catch (e) {
      throw new Error('备份清单损坏');
    }
    if (m.format !== 'juxia-full' || m.version !== 1) {
      throw new Error('备份清单版本不兼容');
    }
    const st = fs.statSync(dataPath);
    if (st.size !== m.dataBytes) {
      throw new Error('备份校验失败：数据大小不一致');
    }
    if (d.materials.length !== m.materialCount) {
      throw new Error('备份校验失败：材料数量不一致');
    }
  }

  private purgeBackupDir(dir: string): void {
    const matDir: string = dir + '/materials';
    try {
      const names: string[] = fs.listFileSync(matDir);
      names.forEach((name: string) => {
        try {
          fs.unlinkSync(matDir + '/' + name);
        } catch (e) {
        }
      });
    } catch (e) {
    }
    try {
      fs.rmdirSync(matDir);
    } catch (e) {
    }
    try {
      fs.unlinkSync(dir + '/data.json');
    } catch (e) {
    }
    try {
      fs.rmdirSync(dir);
    } catch (e) {
    }
  }

  private readAllBytes(path: string): Uint8Array {
    try {
    const f = fs.openSync(path, fs.OpenMode.READ_ONLY);
    const chunks: Uint8Array[] = [];
    let total: number = 0;
    const buf = new ArrayBuffer(64 * 1024);
    let n: number = 0;
    while ((n = fs.readSync(f.fd, buf)) > 0) {
      const c = new Uint8Array(buf.slice(0, n));
      chunks.push(c);
      total += n;
    }
    fs.closeSync(f);
    const out = new Uint8Array(total);
    let at: number = 0;
    chunks.forEach((c: Uint8Array) => {
      out.set(c, at);
      at += c.length;
    });
    return out;
    } catch (e) {
      console.error('juxia read file fail', String(e));
      AppError.report('读取备份文件失败。', '确认文件仍在原位置，重新选择；不要删除原文件。');
      return new Uint8Array(0);
    }
  }

  private async exportFull(): Promise<void> {
    if (this.fullPw.length === 0 || this.fullPw !== this.fullPw2) {
      this.toast('两次密语要一致，且不能为空');
      return;
    }
    if (this.pwWeak(this.fullPw)) {
      this.toast('这句密语太常见，换一句');
      return;
    }
    if (this.pwScore(this.fullPw) <= 1) {
      this.toast('密语偏弱，建议更长或混合字符');
    }
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const stamp: number = Date.now();
      const dir: string = ctx.cacheDir + '/full_' + stamp;
      fs.mkdirSync(dir);
      const matDir: string = dir + '/materials';
      fs.mkdirSync(matDir);
      const raw: string = BackupService.serialize(Store.get().data);
      const obj = JSON.parse(raw) as AppData;
      if (!this.fullIncludeMaterials) {
        obj.materials = [];
      }
      const mf = fs.openSync(dir + '/data.json', fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      fs.writeSync(mf.fd, JSON.stringify(obj));
      fs.closeSync(mf);
      this.writeFullManifest(dir, dir + '/data.json', obj.materials.length, this.fullIncludeMaterials, stamp);
      if (this.fullIncludeMaterials) {
        let failedMaterials: number = 0;
        obj.materials.forEach((m: MaterialEntry) => {
          if (m.path.length > 0) {
            try {
              fs.copyFileSync(m.path, matDir + '/' + m.id + '.txt');
            } catch (e) {
              failedMaterials++;
            }
          }
        });
        if (failedMaterials > 0) {
          this.purgeBackupDir(dir);
          AppError.report('材料复制失败，完整备份未生成。', `有 ${failedMaterials} 份材料无法复制；请检查材料文件是否还在，或先不勾选材料导出。`);
          return;
        }
      }
      const zip: string = ctx.cacheDir + '/full_' + stamp + '.zip';
      await zlib.compressFile(dir, zip, { level: zlib.CompressLevel.COMPRESS_LEVEL_DEFAULT_COMPRESSION });
      const enc: Uint8Array = await BackupService.encryptBytes(this.readAllBytes(zip), this.fullPw);
      const pickerCtx = new picker.DocumentViewPicker(ctx);
      const opts = new picker.DocumentSaveOptions();
      opts.newFileNames = [`句栖完整备份-${stamp}.sj4`];
      const uris: string[] = await pickerCtx.save(opts);
      if (uris.length === 0) {
        try { fs.unlinkSync(zip); } catch (e) {}
        this.purgeBackupDir(dir);
        return;
      }
      const wf = fs.openSync(uris[0], fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(wf.fd, enc.buffer);
      fs.closeSync(wf);
      try { fs.unlinkSync(zip); } catch (e) {}
      this.purgeBackupDir(dir);
      this.markBackedUp();
      this.toast(this.fullIncludeMaterials ? '加密备份已导出（含材料）' : '加密备份已导出（不含材料）');
    } catch (e) {
      console.error('juxia export full fail', String((e as Error).message ?? ''));
      AppError.report('完整备份导出失败。', '检查手机存储空间后重试；材料过多时先不勾选材料，分批导出。');
    }
  }

  private confirmRestore(kind: string): void {
    const encrypted: boolean = kind === 'sj4';
    this.getUIContext().showAlertDialog({
      title: '恢复完整备份？',
      message: '恢复会覆盖当前全部数据：句子、旧事、回忆、备注、省身、句库、设置和材料。若备份不含材料，材料库会为空。建议先导出当前备份；此操作不可撤销。',
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '继续恢复',
        action: () => {
          if (encrypted) {
            this.importFull();
          } else {
            this.importPlainFull();
          }
        }
      }
    });
  }

  private async importFull(): Promise<void> {
    if (this.fullPw.length === 0) {
      this.toast('先输入密语');
      return;
    }
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const pickerCtx = new picker.DocumentViewPicker(ctx);
      const opt = new picker.DocumentSelectOptions();
      opt.maxSelectNumber = 1;
      opt.fileSuffixFilters = ['.sj4'];
      const uris: string[] = await pickerCtx.select(opt);
      if (!uris || uris.length === 0) return;
      const stamp: number = Date.now();
      const local: string = ctx.cacheDir + '/fullin_' + stamp + '.sj4';
      const plain: Uint8Array = await BackupService.decryptBytes(this.readAllBytes(uris[0]), this.fullPw);
      const zf = fs.openSync(local, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      fs.writeSync(zf.fd, plain.buffer);
      fs.closeSync(zf);
      const dest: string = ctx.cacheDir + '/fullin_' + stamp;
      fs.mkdirSync(dest);
      await zlib.decompressFile(local, dest, {});
      const dataPath: string = this.findFile(dest, 'data.json');
      if (dataPath.length === 0) throw new Error('missing data.json');
      const baseDir: string = dataPath.substring(0, dataPath.lastIndexOf('/'));
      const text: string = util.TextDecoder.create('utf-8').decodeToString(this.readAllBytes(dataPath));
      const d = JSON.parse(text) as AppData;
      if (!BackupService.valid(d)) throw new Error('shape');
      this.verifyFullManifest(baseDir, dataPath, d);
      const matDir: string = ctx.filesDir + '/materials';
      // 覆盖前先清掉旧材料文件，否则每恢复一次就留下一批孤儿
      try {
        const olds: string[] = fs.listFileSync(matDir);
        olds.forEach((name: string) => {
          try {
            fs.unlinkSync(matDir + '/' + name);
          } catch (e) {
            console.error('juxia old material unlink fail', name, String(e));
          }
        });
      } catch (e) {
        console.error('juxia old material list fail', String(e));
      }
      await Store.get().replaceAll(d);
      try {
        fs.mkdirSync(matDir);
      } catch (e) {
        console.error('juxia material dir ensure fail', String(e));
      }
      if (Store.get().data.materials.length > 0) {
      }
      let failedMaterials: number = 0;
      for (const m of Store.get().data.materials) {
        const src: string = baseDir + '/materials/' + m.id + '.txt';
        const target: string = matDir + '/' + m.id + '.txt';
        try {
          fs.copyFileSync(src, target);
          const st = fs.statSync(target);
          Store.get().attachMaterialFile(m.id, m.name, target, st.size);
          Store.get().clearMaterialIndex(m.id);
          await MaterialIndexer.indexFile(m.id, target);
        } catch (e) {
          failedMaterials++;
        }
      }
      const lost: number = this.pruneMissingMaterials();
      this.applyLoadedSettings();
      this.load();
      try { fs.unlinkSync(local); } catch (e) {}
      this.purgeBackupDir(dest);
      const ctx2 = this.getUIContext().getHostContext() as common.UIAbilityContext;
      ReminderService.rescheduleAll(ctx2, false);
      this.toast(failedMaterials > 0
        ? `完整备份已恢复；${failedMaterials} 份材料恢复失败，已移除`
        : (lost > 0 ? `完整备份已恢复；${lost} 份材料原文缺失，已移除` : '完整备份已恢复，材料与索引一并回来'));
    } catch (e) {
      const message: string = String((e as Error).message ?? '');
      if (message.includes('不是 SJ4')) {
        AppError.report('选择的不是 .sj4 完整加密备份。', '请选择由句栖导出的 .sj4 文件；不要把 .zip 改名成 .sj4。');
      } else if (message.includes('密语')) {
        AppError.report('密语不对，或备份文件已损坏。', '确认密语正确；若仍失败，换一个备份文件。原文件不要删除。');
      } else {
        AppError.report('完整备份恢复失败。', '确认文件完整、格式正确后重试；不要删除原文件。');
      }
    }
  }

  private async exportPlainFull(): Promise<void> {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const stamp: number = Date.now();
      const dir: string = ctx.cacheDir + '/plain_' + stamp;
      fs.mkdirSync(dir);
      const matDir: string = dir + '/materials';
      fs.mkdirSync(matDir);
      const raw: string = BackupService.serialize(Store.get().data);
      const obj = JSON.parse(raw) as AppData;
      if (!this.plainIncludeMaterials) {
        obj.materials = [];
      }
      const mf = fs.openSync(dir + '/data.json', fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      fs.writeSync(mf.fd, JSON.stringify(obj));
      fs.closeSync(mf);
      this.writeFullManifest(dir, dir + '/data.json', obj.materials.length, this.plainIncludeMaterials, stamp);
      if (this.plainIncludeMaterials) {
        let failedMaterials: number = 0;
        obj.materials.forEach((m: MaterialEntry) => {
          if (m.path.length > 0) {
            try {
              fs.copyFileSync(m.path, matDir + '/' + m.id + '.txt');
            } catch (e) {
              failedMaterials++;
            }
          }
        });
        if (failedMaterials > 0) {
          this.purgeBackupDir(dir);
          AppError.report('材料复制失败，完整备份未生成。', `有 ${failedMaterials} 份材料无法复制；请检查材料文件是否还在，或先不勾选材料导出。`);
          return;
        }
      }
      const zip: string = ctx.cacheDir + '/plain_' + stamp + '.zip';
      await zlib.compressFile(dir, zip, { level: zlib.CompressLevel.COMPRESS_LEVEL_DEFAULT_COMPRESSION });
      const pickerCtx = new picker.DocumentViewPicker(ctx);
      const opts = new picker.DocumentSaveOptions();
      opts.newFileNames = [`句栖完整不加密备份-${stamp}.zip`];
      const uris: string[] = await pickerCtx.save(opts);
      if (uris.length === 0) {
        try { fs.unlinkSync(zip); } catch (e) {}
        this.purgeBackupDir(dir);
        return;
      }
      const bytes: Uint8Array = this.readAllBytes(zip);
      const wf = fs.openSync(uris[0], fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(wf.fd, bytes.buffer);
      fs.closeSync(wf);
      try { fs.unlinkSync(zip); } catch (e) {}
      this.purgeBackupDir(dir);
      this.markBackedUp();
      this.toast(this.plainIncludeMaterials ? '完整不加密备份已导出（含材料）' : '完整不加密备份已导出（不含材料）');
    } catch (e) {
      console.error('juxia export plain fail', String((e as Error).message ?? ''));
      AppError.report('完整不加密备份导出失败。', '检查存储空间后重试；材料过多时先不勾选材料。');
    }
  }

  private async importPlainFull(): Promise<void> {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const pickerCtx = new picker.DocumentViewPicker(ctx);
      const opt = new picker.DocumentSelectOptions();
      opt.maxSelectNumber = 1;
      opt.fileSuffixFilters = ['.zip'];
      const uris: string[] = await pickerCtx.select(opt);
      if (!uris || uris.length === 0) return;
      const stamp: number = Date.now();
      const local: string = ctx.cacheDir + '/plainin_' + stamp + '.zip';
      const bytes: Uint8Array = this.readAllBytes(uris[0]);
      const zf = fs.openSync(local, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      fs.writeSync(zf.fd, bytes.buffer);
      fs.closeSync(zf);
      const dest: string = ctx.cacheDir + '/plainin_' + stamp;
      fs.mkdirSync(dest);
      await zlib.decompressFile(local, dest, {});
      const dataPath: string = this.findFile(dest, 'data.json');
      if (dataPath.length === 0) throw new Error('missing data.json');
      const baseDir: string = dataPath.substring(0, dataPath.lastIndexOf('/'));
      const text: string = util.TextDecoder.create('utf-8').decodeToString(this.readAllBytes(dataPath));
      const d = JSON.parse(text) as AppData;
      if (!BackupService.valid(d)) throw new Error('shape');
      this.verifyFullManifest(baseDir, dataPath, d);
      const matDir: string = ctx.filesDir + '/materials';
      try {
        const olds: string[] = fs.listFileSync(matDir);
        olds.forEach((name: string) => {
          try {
            fs.unlinkSync(matDir + '/' + name);
          } catch (e) {
            console.error('juxia old material unlink fail', name, String(e));
          }
        });
      } catch (e) {
        console.error('juxia old material list fail', String(e));
      }
      await Store.get().replaceAll(d);
      try {
        fs.mkdirSync(matDir);
      } catch (e) {
        console.error('juxia material dir ensure fail', String(e));
      }
      let failedMaterials: number = 0;
      for (const m of Store.get().data.materials) {
        const src: string = baseDir + '/materials/' + m.id + '.txt';
        const target: string = matDir + '/' + m.id + '.txt';
        try {
          fs.copyFileSync(src, target);
          const st = fs.statSync(target);
          Store.get().attachMaterialFile(m.id, m.name, target, st.size);
          Store.get().clearMaterialIndex(m.id);
          await MaterialIndexer.indexFile(m.id, target);
        } catch (e) {
          failedMaterials++;
        }
      }
      const lost: number = this.pruneMissingMaterials();
      this.applyLoadedSettings();
      this.load();
      try { fs.unlinkSync(local); } catch (e) {}
      this.purgeBackupDir(dest);
      const ctx2 = this.getUIContext().getHostContext() as common.UIAbilityContext;
      ReminderService.rescheduleAll(ctx2, false);
      this.toast(failedMaterials > 0
        ? `不加密备份已恢复；${failedMaterials} 份材料恢复失败，已移除`
        : (lost > 0 ? `不加密备份已恢复；${lost} 份材料缺失，已移除` : '不加密备份已恢复'));
    } catch (e) {
      AppError.report('不加密备份恢复失败。', '确认备份文件完整、格式正确后重试；不要删除原文件。');
    }
  }

  private sameMaterialExists(name: string, size: number): boolean {
    const found = Store.get().data.materials.find((m: MaterialEntry) =>
      m.name === name && m.size === size && m.path.length > 0);
    if (found === undefined) return false;
    try {
      fs.statSync(found.path);
      return true;
    } catch (e) {
      return false;
    }
  }

  private newMaterialId(): string {
    let id: string = uid();
    while (Store.get().data.materials.some((m: MaterialEntry) => m.id === id)) {
      id = uid();
    }
    return id;
  }

  private pruneMissingMaterials(): number {
    let lost: number = 0;
    const list = Store.get().data.materials.slice();
    for (const m of list) {
      if (m.path.length === 0) continue;
      try {
        fs.statSync(m.path);
      } catch (e) {
        Store.get().deleteMaterial(m.id);
        lost++;
      }
    }
    return lost;
  }

  private async exportMaterials(): Promise<void> {
    const mats: MaterialEntry[] = Store.get().data.materials.filter((m: MaterialEntry) => m.path.length > 0);
    if (mats.length === 0) {
      this.toast('没有文件型材料可导出');
      return;
    }
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const stamp: number = Date.now();
      const dir: string = ctx.cacheDir + '/matpack_' + stamp;
      fs.mkdirSync(dir);
      const items: MatPackItem[] = [];
      let failedMaterials: number = 0;
      mats.forEach((m: MaterialEntry) => {
        try {
          fs.copyFileSync(m.path, dir + '/' + m.id + '.txt');
          const it = new MatPackItem();
          it.id = m.id;
          it.name = m.name;
          it.size = m.size;
          items.push(it);
        } catch (e) {
          failedMaterials++;
        }
      });
      const mf = fs.openSync(dir + '/manifest.json', fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      fs.writeSync(mf.fd, JSON.stringify(items));
      fs.closeSync(mf);
      const zip: string = ctx.cacheDir + '/matpack_' + stamp + '.zip';
      await zlib.compressFile(dir, zip, { level: zlib.CompressLevel.COMPRESS_LEVEL_DEFAULT_COMPRESSION });
      const pickerCtx = new picker.DocumentViewPicker(ctx);
      const opts = new picker.DocumentSaveOptions();
      opts.newFileNames = [`句栖材料包-${stamp}.zip`];
      const uris: string[] = await pickerCtx.save(opts);
      if (uris.length === 0) return;
      const stat = fs.statSync(zip);
      const rf = fs.openSync(zip, fs.OpenMode.READ_ONLY);
      const wf = fs.openSync(uris[0], fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      const buf = new ArrayBuffer(64 * 1024);
      let n: number = 0;
      while ((n = fs.readSync(rf.fd, buf)) > 0) {
        fs.writeSync(wf.fd, buf.slice(0, n));
      }
      fs.closeSync(rf);
      fs.closeSync(wf);
      this.toast(failedMaterials > 0
        ? `已导出 ${items.length} 份，${failedMaterials} 份失败（${Math.round(stat.size / 1024)} KB）`
        : `已导出 ${items.length} 份材料（${Math.round(stat.size / 1024)} KB）`);
    } catch (e) {
      AppError.report('材料包导出失败。', '检查存储空间后重试；文件过多时先分批。');
    }
  }

  private async importMaterials(): Promise<void> {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const pickerCtx = new picker.DocumentViewPicker(ctx);
      const opt = new picker.DocumentSelectOptions();
      opt.maxSelectNumber = 1;
      opt.fileSuffixFilters = ['.zip'];
      const uris: string[] = await pickerCtx.select(opt);
      if (!uris || uris.length === 0) return;
      const stamp: number = Date.now();
      const local: string = ctx.cacheDir + '/matimport_' + stamp + '.zip';
      const rf = fs.openSync(uris[0], fs.OpenMode.READ_ONLY);
      const wf = fs.openSync(local, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      const buf = new ArrayBuffer(64 * 1024);
      let n: number = 0;
      while ((n = fs.readSync(rf.fd, buf)) > 0) {
        fs.writeSync(wf.fd, buf.slice(0, n));
      }
      fs.closeSync(rf);
      fs.closeSync(wf);
      const dest: string = ctx.cacheDir + '/matimport_' + stamp;
      fs.mkdirSync(dest);
      await zlib.decompressFile(local, dest, {});
      const manifestPath: string = this.findFile(dest, 'manifest.json');
      if (manifestPath.length === 0) throw new Error('missing manifest');
      const packDir: string = manifestPath.substring(0, manifestPath.lastIndexOf('/'));
      const mf = fs.openSync(manifestPath, fs.OpenMode.READ_ONLY);
      const mst = fs.statSync(mf.fd);
      const mbuf = new ArrayBuffer(mst.size);
      fs.readSync(mf.fd, mbuf);
      fs.closeSync(mf);
      const text: string = util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(mbuf));
      const items = JSON.parse(text) as MatPackItem[];
      const matDir: string = ctx.filesDir + '/materials';
      try {
        fs.mkdirSync(matDir);
      } catch (e) {
        console.error('juxia material dir ensure fail', String(e));
      }
      let count: number = 0;
      let skipped: number = 0;
      let failed: number = 0;
      if (items.length > 0) {
      }
      for (const it of items) {
        const src: string = packDir + '/' + it.id + '.txt';
        try {
          const srcStat = fs.statSync(src);
          if (this.sameMaterialExists(it.name, srcStat.size)) {
            skipped++;
            continue;
          }
          // 不复用分享包里的 id：避免覆盖接收方已有材料
          const newId: string = this.newMaterialId();
          const dst: string = matDir + '/' + newId + '.txt';
          fs.copyFileSync(src, dst);
          Store.get().attachMaterialFile(newId, it.name, dst, srcStat.size);
          Store.get().clearMaterialIndex(newId);
          await MaterialIndexer.indexFile(newId, dst);
          count++;
        } catch (e) {
          failed++;
        }
      }
      this.toast(failed > 0
        ? `已恢复 ${count} 份，跳过 ${skipped} 份，失败 ${failed} 份`
        : (skipped > 0 ? `已恢复 ${count} 份材料，跳过 ${skipped} 份已存在` : `已恢复 ${count} 份材料并重建索引`));
    } catch (e) {
      AppError.report('材料包导入失败。', '确认压缩包完整、未被修改后重试。');
    }
  }

  private backupDaysText(): string {
    const last: number = Store.get().data.meta.lastBackupAt;
    if (last <= 0) {
      return '上次备份：从未';
    }
    const days: number = Math.floor((Date.now() - last) / 86400000);
    return days <= 0 ? '上次备份：今天' : `上次备份：${days} 天前`;
  }

  private toggleBackupRemind(): void {
    if (this.backupRemindOff) {
      this.backupRemindOff = false;
      Store.get().data.settings.backupRemindOff = false;
      Store.get().saveKv();
      this.toast('备份提醒已重新开启');
      return;
    }
    this.getUIContext().showAlertDialog({
      title: '彻底关闭备份提醒？',
      message: '关闭后，句栖不再提醒你备份。数据只在这台设备上（自己导出的数据除外，取决于自己存放的位置），误删、卸载或换机都可能无法恢复。可以随时回来重新开启。',
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '仍然关闭',
        action: () => {
          this.backupRemindOff = true;
          Store.get().data.settings.backupRemindOff = true;
          Store.get().saveKv();
          this.toast('已彻底关闭备份提醒');
        }
      }
    });
  }

  private async confirmWipe(step: number): Promise<void> {
    if (step >= 3) {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const mats = Store.get().data.materials;
      mats.forEach((m) => {
        if (m.path.length > 0) {
          try {
            fs.unlinkSync(m.path);
          } catch (e) {
          }
        }
      });
      await ReminderService.cancelAll(ctx);
      Store.get().resetAll();
      this.applyLoadedSettings();
      this.load();
      this.toast('已清空，一切重新开始');
      return;
    }
    this.getUIContext().showAlertDialog({
      title: step === 1 ? '清空全部数据？' : '真的清空？',
      message: step === 1 ? '此操作不可撤销，建议先导出密语备份。' : '所有句子、备注、回忆与天数都会消失，无法找回。',
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: step === 1 ? '继续' : '确认清空',
        action: () => {
          this.confirmWipe(step + 1);
        }
      }
    });
  }

  private markBackedUp(): void {
    Store.get().data.meta.lastBackupAt = Date.now();
    Store.get().saveKv();
  }

  private async selfTest(): Promise<void> {
    const pass: string = 'juxia-selftest-2026';
    let msg: string = '正在检查备份…';
    this.selfTestMsg = msg;
    try {
      const enc: string = await BackupService.encrypt(Store.get().data, pass);
      const dec: AppData = await BackupService.decrypt(enc, pass);
      const ok: boolean = BackupService.valid(dec) &&
        dec.own.length === Store.get().data.own.length &&
        dec.lib.length === Store.get().data.lib.length &&
        dec.materials.length === Store.get().data.materials.length;
      msg = ok
        ? '备份自检通过。'
        : '备份自检失败。数据没有通过一致性检查。';
    } catch (e) {
      msg = '备份自检失败，请重启应用后再试。';
    }
    this.selfTestMsg = msg;
  }

  private async testReminder(): Promise<void> {
    this.selfTestMsg = '正在检查提醒状态…';
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    await ReminderService.rescheduleAll(ctx, true);
    this.selfTestMsg = await ReminderService.status(ctx);
  }

  @Builder
  Btn(label: string, primary: boolean, action: () => void) {
    Text(label)
      .fontSize(12.5)
      .fontColor(primary ? this.t().bg : this.t().ink)
      .backgroundColor(primary ? this.t().ink : this.t().card)
      .border({ width: primary ? 0 : 1, color: this.t().line })
      .borderRadius(this.t().radiusBtn)
      .padding({ left: 16, right: 16, top: 10, bottom: 10 })
      .margin({ right: 8, bottom: 6 })
      .onClick(action)
  }

  @Builder
  GroupTitle(text: string) {
    Row({ space: 10 }) {
      Text(text)
        .fontSize(12.5)
        .letterSpacing(4)
        .fontColor(this.t().seal)
        .fontFamily(FONT_SERIF)
      Divider()
        .layoutWeight(1)
        .color(this.t().line)
    }
    .width('100%')
    .margin({ top: 30, bottom: 10 })
  }

  @Builder
  Chip(label: string, active: boolean, action: () => void) {
    Text(label)
      .fontSize(11.5)
      .letterSpacing(1.5)
      .fontColor(active ? this.t().sealInk : this.t().inkSoft)
      .backgroundColor(active ? this.t().seal : this.t().card)
      .border({ width: 1, color: active ? Color.Transparent : this.t().line })
      .borderRadius(999)
      .padding({ left: 16, right: 16, top: 10, bottom: 10 })
      .margin({ right: 6, bottom: 6 })
      .onClick(action)
  }

  @Builder
  SkinChip(v: string, label: string) {
    Text(label)
      .fontSize(11.5)
      .letterSpacing(1.5)
      .fontColor(this.skin === v ? this.t().sealInk : this.t().inkSoft)
      .backgroundColor(this.skin === v ? this.t().seal : this.t().card)
      .border({ width: 1, color: this.skin === v ? Color.Transparent : this.t().line })
      .borderRadius(999)
      .padding({ left: 20, right: 20, top: 10, bottom: 10 })
      .margin({ right: 6, bottom: 6 })
      .onClick(() => {
        this.setSkin(v);
      })
  }

  @Builder
  ThemeChip(v: string, label: string) {
    Text(label)
      .fontSize(11.5)
      .letterSpacing(1.5)
      .fontColor(this.theme === v ? this.t().sealInk : this.t().inkSoft)
      .backgroundColor(this.theme === v ? this.t().seal : this.t().card)
      .border({ width: 1, color: this.theme === v ? Color.Transparent : this.t().line })
      .borderRadius(999)
      .padding({ left: 20, right: 20, top: 10, bottom: 10 })
      .margin({ right: 6, bottom: 6 })
      .onClick(() => {
        this.setTheme(v);
      })
  }

  @Builder
  FollowFontChip() {
    Text('跟随系统')
      .fontSize(11.5)
      .letterSpacing(1.5)
      .fontColor(this.fontScaleFollow ? this.t().sealInk : this.t().inkSoft)
      .backgroundColor(this.fontScaleFollow ? this.t().seal : this.t().card)
      .border({ width: 1, color: this.fontScaleFollow ? Color.Transparent : this.t().line })
      .borderRadius(999)
      .padding({ left: 20, right: 20, top: 10, bottom: 10 })
      .margin({ right: 6, bottom: 6 })
      .onClick(() => {
        this.followSystemFont();
      })
  }

  @Builder
  ScaleChip(v: number, label: string) {
    Text(label)
      .fontSize(11.5)
      .letterSpacing(1.5)
      .fontColor(!this.fontScaleFollow && Math.abs(this.fontScale - v) < 0.001 ? this.t().sealInk : this.t().inkSoft)
      .backgroundColor(!this.fontScaleFollow && Math.abs(this.fontScale - v) < 0.001 ? this.t().seal : this.t().card)
      .border({
        width: 1,
        color: !this.fontScaleFollow && Math.abs(this.fontScale - v) < 0.001 ? Color.Transparent : this.t().line
      })
      .borderRadius(999)
      .padding({ left: 20, right: 20, top: 10, bottom: 10 })
      .margin({ right: 6, bottom: 6 })
      .onClick(() => {
        this.setFontScale(v);
      })
  }

  @Builder
  RitualChip(v: string, label: string) {
    Text(label)
      .fontSize(11.5)
      .letterSpacing(1.5)
      .fontColor(this.ritualMode === v ? this.t().sealInk : this.t().inkSoft)
      .backgroundColor(this.ritualMode === v ? this.t().seal : this.t().card)
      .border({ width: 1, color: this.ritualMode === v ? Color.Transparent : this.t().line })
      .borderRadius(999)
      .padding({ left: 18, right: 18, top: 10, bottom: 10 })
      .margin({ right: 6, bottom: 6 })
      .onClick(() => {
        this.setRitual(v);
      })
  }

  @Builder
  SectionHeader(key: string, title: string) {
    Row() {
      Text(title)
        .fontSize(16)
        .letterSpacing(2)
        .fontFamily(FONT_SERIF)
        .fontColor(this.t().inkStrong)
      Blank()
      Text(this.openSection === key ? '收起' : '展开')
        .fontSize(11.5)
        .fontColor(this.t().inkSoft)
    }
    .width('100%')
    .padding({ top: 18, bottom: 8 })
    .onClick(() => {
      this.openSection = this.openSection === key ? '' : key;
    })
  }

  build() {
    Scroll() {
      Column() {
        this.SectionHeader('ui', '界面与常规')
        if (this.openSection === 'ui') {
        this.GroupTitle('界面')
        Column() {
          Text('经典：帘后日光，折纸取信。朴素：素纸一页，只留字。两套界面功能完全相同，随时可换。')
            .fontSize(12.5)
            .lineHeight(22)
            .fontColor(this.t().inkSoft)
            .width('100%')
            .margin({ bottom: 10 })
          Row({ space: 6 }) {
            this.SkinChip('classic', '经典')
            this.SkinChip('plain', '朴素')
          }
          Divider().color(this.t().lineSoft).margin({ top: 8, bottom: 12 })
          Row() {
            Text('显示「相伴第 N 天」')
              .fontSize(13.5)
              .fontColor(this.t().ink)
            Blank()
            Text(this.showDays ? '显示中' : '已隐藏')
              .fontSize(11.5)
              .fontColor(this.showDays ? this.t().sealInk : this.t().ink)
              .backgroundColor(this.showDays ? this.t().seal : this.t().card)
              .border({
                width: 1,
                color: this.showDays ? Color.Transparent : this.t().line
              })
              .borderRadius(999)
              .padding({ left: 14, right: 14, top: 8, bottom: 8 })
              .onClick(() => {
                this.showDays = !this.showDays;
                Store.get().data.settings.showDays = this.showDays;
                Store.get().saveKv();
                UiState.get().showDays = this.showDays;
              })
          }
          .width('100%')
        }
        .width('100%')
        .padding(20)
        .backgroundColor(this.t().card).backdropBlur(this.dark ? 0 : 10)
        .borderRadius(this.t().radiusCard)
        .border({ width: 1, color: this.t().line })

        this.GroupTitle('外观')
        Column() {
          Row({ space: 6 }) {
            this.ThemeChip('system', '跟随系统')
            this.ThemeChip('light', '日间')
            this.ThemeChip('dark', '夜间')
          }
          Text('字号（全局，随系统一起缩放）')
            .fontSize(11.5)
            .fontColor(this.t().inkSoft)
            .width('100%')
            .margin({ top: 10, bottom: 6 })
          Flex({ wrap: FlexWrap.Wrap }) {
            this.FollowFontChip()
            this.ScaleChip(0.9, '小')
            this.ScaleChip(1.0, '标准')
            this.ScaleChip(1.1, '大')
            this.ScaleChip(1.25, '特大')
          }
          .width('100%')
        }
        .width('100%')
        .padding(20)
        .backgroundColor(this.t().card).backdropBlur(this.dark ? 0 : 10)
        .borderRadius(this.t().radiusCard)
        .border({ width: 1, color: this.t().line })

        this.GroupTitle('仪式感')
        Column() {
          Text('抽签前的折纸仪式帮助开始，不必每次完整执行——觉得成了负担就调短或关掉。')
            .fontSize(12.5)
            .lineHeight(22)
            .fontColor(this.t().inkSoft)
            .width('100%')
            .margin({ bottom: 10 })
          Row({ space: 6 }) {
            this.RitualChip('full', '完整仪式')
            this.RitualChip('short', '简短')
            this.RitualChip('off', '关闭')
          }
        }
        .width('100%')
        .padding(20)
        .backgroundColor(this.t().card).backdropBlur(this.dark ? 0 : 10)
        .borderRadius(this.t().radiusCard)
        .border({ width: 1, color: this.t().line })

        this.GroupTitle('回访')
        Column() {
          Text('「已解决 / 已放下」的事，可选在若干天后轻轻问一次。如果回访时发现还没准备好，可以回到台前。')
            .fontSize(12.5)
            .lineHeight(22)
            .fontColor(this.t().inkSoft)
            .width('100%')
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach([7, 30, 90, 180, 365], (d: number) => {
              Text(`${d} 天`)
                .fontSize(12.5)
                .fontColor(this.revisitDays === d ? this.t().bg : this.t().ink)
                .backgroundColor(this.revisitDays === d ? this.t().seal : this.t().card)
                .border({ width: 1, color: this.revisitDays === d ? this.t().seal : this.t().line })
                .borderRadius(this.t().radiusBtn)
                .padding({ left: 12, right: 12, top: 7, bottom: 7 })
                .margin({ right: 6, top: 6 })
                .onClick(() => {
                  this.setDays(d);
                })
            }, (d: number) => `${d}`)
          }
          .width('100%')
          Row({ space: 8 }) {
            TextInput({ text: this.daysInput, placeholder: '自定义天数' })
              .type(InputType.Number)
              .fontSize(13.5)
              .fontColor(this.t().ink)
              .placeholderColor(this.t().inkSoft)
              .backgroundColor(this.t().inputBg)
              .borderRadius(this.t().radiusInput)
              .border({ width: 1, color: this.t().line })
              .height(40)
              .layoutWeight(1)
              .onChange((v: string) => {
                this.daysInput = v;
              })
            Text('保存天数')
              .fontSize(12.5)
              .fontColor(this.t().ink)
              .backgroundColor(this.t().card)
              .border({ width: 1, color: this.t().line })
              .borderRadius(this.t().radiusBtn)
              .padding({ left: 14, right: 14, top: 9, bottom: 9 })
              .onClick(() => {
                this.setDays(Number(this.daysInput));
              })
          }
          .width('100%')
          .margin({ top: 10 })
          Row({ space: 10 }) {
            Text('回访时间')
              .fontSize(13)
              .fontColor(this.t().ink)
            Blank()
            Text(`${this.revisitHour.toString().padStart(2, '0')}:${this.revisitMinute.toString().padStart(2, '0')}`)
              .fontSize(15)
              .fontFamily(FONT_SERIF)
              .fontColor(this.t().inkStrong)
            Text(this.clockOpen ? '收起' : '调整')
              .fontSize(12)
              .fontColor(this.t().seal)
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .border({ width: 1, color: this.t().line })
              .borderRadius(this.t().radiusBtn)
              .onClick(() => {
                this.clockOpen = !this.clockOpen;
                if (this.clockOpen) {
                  this.draftHour = this.revisitHour;
                  this.draftMinute = this.revisitMinute;
                }
              })
          }
          .width('100%')
          .margin({ top: 10 })

          if (this.clockOpen) {
            TimePicker({
              selected: new Date(2000, 0, 1, this.draftHour, this.draftMinute)
            })
              .useMilitaryTime(true)
              .height(140)
              .disappearTextStyle({ color: this.t().inkSoft, font: { size: 14 } })
              .textStyle({ color: this.t().inkSoft, font: { size: 16 } })
              .selectedTextStyle({ color: this.t().inkStrong, font: { size: 20, weight: FontWeight.Medium } })
              .onChange((v: TimePickerResult) => {
                this.draftHour = v.hour;
                this.draftMinute = v.minute;
              })
            Row({ space: 8 }) {
              this.Btn('确定这个时间', true, () => {
                this.confirmRevisitClock();
                this.clockOpen = false;
              })
              Text(this.draftHour === this.revisitHour && this.draftMinute === this.revisitMinute
                ? '与当前一致' : '未确定，滚动不会保存')
                .fontSize(11)
                .fontColor(this.t().inkSoft)
            }
            .width('100%')
            .margin({ top: 4 })
          }

          Text(`当前：${this.revisitDays} 天（默认 90 天），回访时间 ${this.revisitHour.toString().padStart(2, '0')}:${this.revisitMinute.toString().padStart(2, '0')}。所有约定都收在「回忆 · 回访一览」里，可提前或取消。`)
            .fontSize(11.5)
            .lineHeight(20)
            .fontColor(this.t().inkSoft)
            .width('100%')
            .margin({ top: 8 })
        }
        .width('100%')
        .padding(20)
        .backgroundColor(this.t().card).backdropBlur(this.dark ? 0 : 10)
        .borderRadius(this.t().radiusCard)
        .border({ width: 1, color: this.t().line })

        this.GroupTitle('抽签来源')
        Column({ space: 0 }) {
          Text('决定「抽一句」从哪里取。至少开一个；关掉的内容仍会保留在列表里。')
            .fontSize(12)
            .lineHeight(21)
            .fontColor(this.t().inkSoft)
            .width('100%')
            .margin({ bottom: 6 })
          Row() {
            Text('自己的话')
              .fontSize(13)
              .fontColor(this.t().ink)
            Blank()
            Text(this.drawOwn ? '参与' : '不参与')
              .fontSize(12.5)
              .fontColor(this.drawOwn ? this.t().sealInk : this.t().inkSoft)
              .backgroundColor(this.drawOwn ? this.t().seal : this.t().card)
              .border({ width: 1, color: this.drawOwn ? Color.Transparent : this.t().line })
              .borderRadius(this.t().radiusBtn)
              .padding({ left: 16, right: 16, top: 9, bottom: 9 })
              .onClick(() => {
                this.toggleDrawOwn();
              })
          }
          .width('100%')
          .padding({ top: 8, bottom: 8 })
          Row() {
            Text('句库收藏')
              .fontSize(13)
              .fontColor(this.t().ink)
            Blank()
            Text(this.drawLib ? '参与' : '不参与')
              .fontSize(12.5)
              .fontColor(this.drawLib ? this.t().sealInk : this.t().inkSoft)
              .backgroundColor(this.drawLib ? this.t().seal : this.t().card)
              .border({ width: 1, color: this.drawLib ? Color.Transparent : this.t().line })
              .borderRadius(this.t().radiusBtn)
              .padding({ left: 16, right: 16, top: 9, bottom: 9 })
              .onClick(() => {
                this.toggleDrawLib();
              })
          }
          .width('100%')
          .padding({ top: 8, bottom: 4 })
          .border({ width: { top: 1 }, color: this.t().lineSoft })
          Text('句库收藏包括从材料收入的内容；材料原文本身不直接进抽签。')
            .fontSize(11.5)
            .lineHeight(20)
            .fontColor(this.t().inkSoft)
            .width('100%')
            .margin({ top: 6 })
        }
        .width('100%')
        .padding(20)
        .backgroundColor(this.t().card).backdropBlur(this.dark ? 0 : 10)
        .borderRadius(this.t().radiusCard)
        .border({ width: 1, color: this.t().line })

        }
        this.SectionHeader('name', '名称与启动')
        if (this.openSection === 'name') {
        this.GroupTitle('应用名')
        Column() {
          Text('默认「句栖」。改名后，应用内的标题、印章、页脚与文案一起换，最多 6 个字。桌面图标名由系统在安装时确定，不会随应用内改名同步。')
            .fontSize(12.5)
            .lineHeight(22)
            .fontColor(this.t().inkSoft)
            .width('100%')
            .margin({ bottom: 10 })
          TextInput({ text: this.nameInput, placeholder: '自定义（最多 6 字）' })
            .fontSize(14.5)
            .fontColor(this.t().ink)
            .placeholderColor(this.t().inkSoft)
            .backgroundColor(this.t().inputBg)
            .borderRadius(this.t().radiusInput)
            .border({ width: 1, color: this.t().line })
            .height(44)
            .onChange((v: string) => {
              this.nameInput = v;
            })
          Row({ space: 8 }) {
            Text('保存名字')
              .fontSize(13)
              .fontColor(this.t().ink)
              .backgroundColor(this.t().card)
              .border({ width: 1, color: this.t().line })
              .borderRadius(this.t().radiusBtn)
              .padding({ left: 20, right: 20, top: 10, bottom: 10 })
              .onClick(() => {
                this.saveName();
              })
            Text('恢复默认')
              .fontSize(12.5)
              .fontColor(this.t().inkSoft)
              .padding({ left: 10, right: 10, top: 10, bottom: 10 })
              .onClick(() => {
                this.nameInput = '句栖';
                this.saveName();
              })
          }
          .margin({ top: 10 })
        }
        .width('100%')
        .padding(20)
        .backgroundColor(this.t().card).backdropBlur(this.dark ? 0 : 10)
        .borderRadius(this.t().radiusCard)
        .border({ width: 1, color: this.t().line })

        this.GroupTitle('称呼')
        Column() {
          Text('只影响应用内。今日页会显示「你好，XXX」；可以随时关掉称呼。')
            .fontSize(12.5)
            .lineHeight(21)
            .fontColor(this.t().inkSoft)
            .width('100%')
            .margin({ bottom: 10 })
          TextInput({ text: this.nickname, placeholder: '写一个你喜欢的称呼' })
            .height(42)
            .fontSize(14)
            .fontColor(this.t().ink)
            .placeholderColor(this.t().inkSoft)
            .backgroundColor(this.t().inputBg)
            .borderRadius(this.t().radiusInput)
            .border({ width: 1, color: this.t().line })
            .onChange((v: string) => {
              this.nickname = v;
            })
          Row({ space: 8 }) {
            this.Btn('保存称呼', false, () => {
              this.saveNickname();
            })
            Text(this.showGreeting ? '称呼已开启' : '称呼已关闭')
              .fontSize(12)
              .fontColor(this.showGreeting ? this.t().seal : this.t().inkSoft)
              .border({ width: 1, color: this.showGreeting ? this.t().seal : this.t().line })
              .borderRadius(this.t().radiusBtn)
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .onClick(() => {
                this.toggleGreeting();
              })
          }
          .width('100%')
          .margin({ top: 8 })
        }
        .width('100%')
        .padding(20)
        .backgroundColor(this.t().card).backdropBlur(this.dark ? 0 : 10)
        .borderRadius(this.t().radiusCard)
        .border({ width: 1, color: this.t().line })

        this.GroupTitle('省身')
        Column() {
          Text('在「我的」里显示省身区。关闭后数据保留，只是不再显示入口。')
            .fontSize(12.5)
            .lineHeight(21)
            .fontColor(this.t().inkSoft)
            .width('100%')
            .margin({ bottom: 10 })
          Row() {
            Text('显示省身区')
              .fontSize(13.5)
              .fontColor(this.t().ink)
            Blank()
            Text(this.showReflect ? '已开启' : '已关闭')
              .fontSize(12)
              .fontColor(this.showReflect ? this.t().seal : this.t().inkSoft)
              .border({ width: 1, color: this.showReflect ? this.t().seal : this.t().line })
              .borderRadius(this.t().radiusBtn)
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .onClick(() => {
                this.toggleShowReflect();
              })
          }
          .width('100%')
        }
        .width('100%')
        .padding(20)
        .backgroundColor(this.t().card).backdropBlur(this.dark ? 0 : 10)
        .borderRadius(this.t().radiusCard)
        .border({ width: 1, color: this.t().line })

        this.GroupTitle('启动')
        Column() {
          Text('默认启动很快淡出。开启后停留更久，显示你写的一句话；不写就不停留。')
            .fontSize(12.5)
            .lineHeight(22)
            .fontColor(this.t().inkSoft)
            .width('100%')
            .margin({ bottom: 10 })
          Row() {
            Text('长时启动')
              .fontSize(13.5)
              .fontColor(this.t().ink)
            Blank()
            Text(this.bootLong ? '已开启' : '开启')
              .fontSize(11.5)
              .fontColor(this.bootLong ? this.t().sealInk : this.t().ink)
              .backgroundColor(this.bootLong ? this.t().seal : this.t().card)
              .border({
                width: 1,
                color: this.bootLong ? Color.Transparent : this.t().line
              })
              .borderRadius(999)
              .padding({ left: 14, right: 14, top: 8, bottom: 8 })
              .onClick(() => {
                this.toggleBootLong();
              })
          }
          .width('100%')
          Row() {
            Text('停留与字号')
              .fontSize(12.5)
              .fontColor(this.t().inkSoft)
            Blank()
            Text(this.bootTuning ? '完成' : '调整')
              .fontSize(12.5)
              .fontColor(this.t().sealInk)
              .backgroundColor(this.t().seal)
              .borderRadius(999)
              .padding({ left: 16, right: 16, top: 6, bottom: 6 })
              .onClick(() => {
                if (this.bootTuning) {
                  this.saveBootHold(this.bootHold);
                  this.saveBootFont(this.bootFont);
                  this.bootTuning = false;
                } else {
                  this.bootTuning = true;
                }
              })
          }
          .width('100%')
          .margin({ top: 12 })
          if (this.bootTuning) {
            Column({ space: 6 }) {
            Row() {
              Text('停留时长')
                .fontSize(12.5)
                .fontColor(this.t().inkSoft)
              Blank()
              Text('短')
                .fontSize(11)
                .fontColor(this.t().inkSoft)
              Text('长')
                .fontSize(11)
                .fontColor(this.t().inkSoft)
                .margin({ left: 10 })
            }
            .width('100%')
            Slider({ value: this.bootHold, min: 300, max: 5000, step: 10 })
              .selectedColor(this.t().seal)
              .trackColor(this.t().line)
              .blockColor(this.t().seal)
              .onChange((v: number, mode: SliderChangeMode) => {
                this.bootHold = v;
                this.queueBootSave();
                if (mode === SliderChangeMode.End) {
                  this.saveBootHold(v);
                }
              })
          }
          .width('100%')
          .margin({ top: 12 })
          Column({ space: 6 }) {
            Row() {
              Text('文字大小')
                .fontSize(12.5)
                .fontColor(this.t().inkSoft)
              Blank()
              Text('小')
                .fontSize(11)
                .fontColor(this.t().inkSoft)
              Text('大')
                .fontSize(11)
                .fontColor(this.t().inkSoft)
                .margin({ left: 10 })
            }
            .width('100%')
            Slider({ value: this.bootFont, min: 0.8, max: 2.5, step: 0.01 })
              .selectedColor(this.t().seal)
              .trackColor(this.t().line)
              .blockColor(this.t().seal)
              .onChange((v: number, mode: SliderChangeMode) => {
                this.bootFont = v;
                this.queueBootSave();
                if (mode === SliderChangeMode.End) {
                  this.saveBootFont(v);
                }
              })
          }
          .width('100%')
          .margin({ top: 10 })
          }
          TextInput({ text: this.bootTextInput, placeholder: '写一句给自己的话（最多 24 字）' })
            .fontSize(14)
            .fontColor(this.t().ink)
            .placeholderColor(this.t().inkSoft)
            .backgroundColor(this.t().inputBg)
            .borderRadius(this.t().radiusInput)
            .border({ width: 1, color: this.t().line })
            .height(44)
            .maxLength(24)
            .margin({ top: 12 })
            .onChange((v: string) => {
              this.bootTextInput = v;
            })
          Row({ space: 8 }) {
            Text('保存文案')
              .fontSize(13)
              .fontColor(this.t().ink)
              .backgroundColor(this.t().card)
              .border({ width: 1, color: this.t().line })
              .borderRadius(this.t().radiusBtn)
              .padding({ left: 20, right: 20, top: 10, bottom: 10 })
              .onClick(() => {
                this.saveBootText();
              })
            Text('清空')
              .fontSize(12.5)
              .fontColor(this.t().inkSoft)
              .padding({ left: 10, right: 10, top: 10, bottom: 10 })
              .onClick(() => {
                this.bootTextInput = '';
                this.saveBootText();
              })
          }
          .width('100%')
          .margin({ top: 10 })
          Text('下次启动生效。')
            .fontSize(11.5)
            .fontColor(this.t().inkSoft)
            .width('100%')
            .margin({ top: 8 })
        }
        .width('100%')
        .padding(20)
        .backgroundColor(this.t().card).backdropBlur(this.dark ? 0 : 10)
        .borderRadius(this.t().radiusCard)
        .border({ width: 1, color: this.t().line })

        }
        this.SectionHeader('data', '数据与备份')
        if (this.openSection === 'data') {
        this.GroupTitle('完整加密备份')
        Column({ space: 8 }) {
          Text('数据、句子关系、省身与备注、材料一起打包，再用备份密码（密语）加密成 .sj4。')
            .fontSize(13)
            .lineHeight(22)
            .fontColor(this.t().inkStrong)
            .width('100%')
          Row() {
            Text('同时备份材料包')
              .fontSize(13)
              .fontColor(this.t().ink)
            Blank()
            Text(this.fullIncludeMaterials ? '✓ 包含' : '不包含')
              .fontSize(12)
              .fontColor(this.fullIncludeMaterials ? this.t().sealInk : this.t().inkSoft)
              .backgroundColor(this.fullIncludeMaterials ? this.t().seal : this.t().card)
              .border({ width: 1, color: this.fullIncludeMaterials ? Color.Transparent : this.t().line })
              .borderRadius(999)
              .padding({ left: 12, right: 12, top: 7, bottom: 7 })
              .onClick(() => {
                this.fullIncludeMaterials = !this.fullIncludeMaterials;
              })
          }
          .width('100%')
          Row({ space: 8 }) {
            this.Btn('导出加密备份', true, () => {
              this.fullPanel = 'out';
              this.fullPw = '';
              this.fullPw2 = '';
            })
            this.Btn('导入加密备份', false, () => {
              this.fullPanel = 'in';
              this.fullPw = '';
            })
          }
          .width('100%')
          if (this.fullPanel === 'out') {
            TextInput({ text: this.fullPw, placeholder: '密语' })
              .type(InputType.Password)
              .width('100%')
              .height(42)
              .fontSize(14)
              .fontColor(this.t().ink)
              .placeholderColor(this.t().inkSoft)
              .backgroundColor(this.t().inputBg)
              .borderRadius(this.t().radiusInput)
              .border({ width: 1, color: this.t().line })
              .onChange((v: string) => {
                this.fullPw = v;
              })
            TextInput({ text: this.fullPw2, placeholder: '再输一遍' })
              .type(InputType.Password)
              .width('100%')
              .height(42)
              .fontSize(14)
              .fontColor(this.t().ink)
              .placeholderColor(this.t().inkSoft)
              .backgroundColor(this.t().inputBg)
              .borderRadius(this.t().radiusInput)
              .border({ width: 1, color: this.t().line })
              .onChange((v: string) => {
                this.fullPw2 = v;
              })
            Row({ space: 8 }) {
              this.Btn('生成加密备份', true, () => {
                this.exportFull();
              })
              this.Btn('关闭', false, () => {
                this.fullPanel = '';
              })
            }
            .width('100%')
          }
          if (this.fullPanel === 'in') {
            TextInput({ text: this.fullPw, placeholder: '输入这个包的密语' })
              .type(InputType.Password)
              .width('100%')
              .height(42)
              .fontSize(14)
              .fontColor(this.t().ink)
              .placeholderColor(this.t().inkSoft)
              .backgroundColor(this.t().inputBg)
              .borderRadius(this.t().radiusInput)
              .border({ width: 1, color: this.t().line })
              .onChange((v: string) => {
                this.fullPw = v;
              })
            Row({ space: 8 }) {
              this.Btn('选择 .sj4 导入', true, () => {
                this.confirmRestore('sj4');
              })
              this.Btn('关闭', false, () => {
                this.fullPanel = '';
              })
            }
            .width('100%')
            Text('恢复会覆盖当前全部数据；若包内不含材料，材料库会为空。建议先导出当前备份。')
              .fontSize(11.5)
              .lineHeight(20)
              .fontColor(this.t().inkSoft)
              .width('100%')
          }
        }
        .width('100%')
        .padding(20)
        .backgroundColor(this.t().card).backdropBlur(this.dark ? 0 : 10)
        .borderRadius(this.t().radiusCard)
        .border({ width: 1, color: this.t().line })

        this.GroupTitle('完整不加密备份')
        Column({ space: 8 }) {
          Text('数据、句子关系、省身与备注、材料一起打包成 .zip，不加密；拿到文件的人可以直接查看。')
            .fontSize(13)
            .lineHeight(22)
            .fontColor(this.t().inkStrong)
            .width('100%')
          Row() {
            Text('同时备份材料包')
              .fontSize(13)
              .fontColor(this.t().ink)
            Blank()
            Text(this.plainIncludeMaterials ? '✓ 包含' : '不包含')
              .fontSize(12)
              .fontColor(this.plainIncludeMaterials ? this.t().sealInk : this.t().inkSoft)
              .backgroundColor(this.plainIncludeMaterials ? this.t().seal : this.t().card)
              .border({ width: 1, color: this.plainIncludeMaterials ? Color.Transparent : this.t().line })
              .borderRadius(999)
              .padding({ left: 12, right: 12, top: 7, bottom: 7 })
              .onClick(() => {
                this.plainIncludeMaterials = !this.plainIncludeMaterials;
              })
          }
          .width('100%')
          Row({ space: 8 }) {
            this.Btn('导出不加密备份', true, () => {
              this.plainPanel = 'out';
            })
            this.Btn('导入不加密备份', false, () => {
              this.plainPanel = 'in';
            })
          }
          .width('100%')
          if (this.plainPanel === 'out') {
            Row({ space: 8 }) {
              this.Btn('生成不加密备份', true, () => {
                this.exportPlainFull();
              })
              this.Btn('关闭', false, () => {
                this.plainPanel = '';
              })
            }
            .width('100%')
            Text('不加密备份不需要密语，请自行保管。')
              .fontSize(11.5)
              .fontColor(this.t().inkSoft)
              .width('100%')
          }
          if (this.plainPanel === 'in') {
            Row({ space: 8 }) {
              this.Btn('选择 .zip 导入', true, () => {
                this.confirmRestore('zip');
              })
              this.Btn('关闭', false, () => {
                this.plainPanel = '';
              })
            }
            .width('100%')
            Text('恢复将覆盖当前全部数据；若包内不含材料，材料库会为空。')
              .fontSize(11.5)
              .fontColor(this.t().inkSoft)
              .width('100%')
          }
        }
        .width('100%')
        .padding(20)
        .backgroundColor(this.t().card).backdropBlur(this.dark ? 0 : 10)
        .borderRadius(this.t().radiusCard)
        .border({ width: 1, color: this.t().line })

        this.GroupTitle('材料包 · 单独搬材料')
        Column({ space: 8 }) {
          Text('只包含材料原文，不含句子、省身、设置和关系；不加密。')
            .fontSize(13)
            .lineHeight(22)
            .fontColor(this.t().inkStrong)
            .width('100%')
          Text('适合只迁移材料，不动现有数据。拿到文件的人可以直接查看材料原文。')
            .fontSize(11.5)
            .lineHeight(20)
            .fontColor(this.t().inkSoft)
            .width('100%')
          Row({ space: 8 }) {
            this.Btn('导出材料包', false, () => {
              this.exportMaterials();
            })
            this.Btn('导入材料包', false, () => {
              this.importMaterials();
            })
          }
          .width('100%')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(20)
        .backgroundColor(this.t().card).backdropBlur(this.dark ? 0 : 10)
        .borderRadius(this.t().radiusCard)
        .border({ width: 1, color: this.t().line })

        this.GroupTitle('备份提醒')
        Column({ space: 8 }) {
          Row() {
            Column({ space: 4 }) {
              Text(this.backupRemindOff ? '提醒已关闭' : '提醒已开启')
                .fontSize(13.5)
                .fontColor(this.t().ink)
              Text(this.backupDaysText())
                .fontSize(11.5)
                .fontColor(this.t().inkSoft)
            }
            .alignItems(HorizontalAlign.Start)
            Blank()
            Text(this.backupRemindOff ? '重新开启' : '彻底关闭')
              .fontSize(12.5)
              .fontColor(this.backupRemindOff ? this.t().sealInk : this.t().ink)
              .backgroundColor(this.backupRemindOff ? this.t().seal : this.t().card)
              .border({
                width: 1,
                color: this.backupRemindOff ? Color.Transparent : this.t().line
              })
              .borderRadius(999)
              .padding({ left: 16, right: 16, top: 8, bottom: 8 })
              .onClick(() => {
                this.toggleBackupRemind();
              })
          }
          .width('100%')
          Text('关闭后不再提醒；数据只在这台设备上（自己导出的数据除外，取决于自己存放的位置），误删、卸载或换机都可能无法恢复。')
            .fontSize(11.5)
            .lineHeight(20)
            .fontColor(this.t().inkSoft)
            .width('100%')
        }
        .width('100%')
        .padding(20)
        .backgroundColor(this.t().card).backdropBlur(this.dark ? 0 : 10)
        .borderRadius(this.t().radiusCard)
        .border({ width: 1, color: this.t().line })

        this.GroupTitle('清空数据')
        Column({ space: 8 }) {
          Text('清空后所有句子、省身、备注、材料和设置都会消失，无法恢复。')
            .fontSize(12)
            .lineHeight(21)
            .fontColor(this.t().inkSoft)
            .width('100%')
          Text('清空全部数据')
            .fontSize(12.5)
            .fontColor(this.t().seal)
            .padding({ top: 8, bottom: 4 })
            .onClick(() => {
              this.confirmWipe(1);
            })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(20)
        .backgroundColor(this.t().card).backdropBlur(this.dark ? 0 : 10)
        .borderRadius(this.t().radiusCard)
        .border({ width: 1, color: this.t().line })

        }
        this.SectionHeader('about', '关于')
        if (this.openSection === 'about') {
        this.GroupTitle('关于')
        Column({ space: 6 }) {
          Text('句栖')
            .fontSize(13)
            .fontColor(this.t().ink)
            .gesture(LongPressGesture().onAction(() => {
              this.selfTest();
            }))
          Text(`存储：${Store.get().storageMode()} · 备份由你导出`)
            .fontSize(12)
            .lineHeight(22)
            .fontColor(this.t().inkSoft)
            .gesture(LongPressGesture().onAction(() => {
              this.testReminder();
            }))
          Text('今日 / 我的 / 句库 / 回忆 / 设置 五页已接通。')
            .fontSize(12)
            .lineHeight(22)
            .fontColor(this.t().inkSoft)
          Text('句栖是记录与回看的工具，不是心理治疗、诊断或危机干预服务，也不能替代专业帮助。\n如果你持续感到痛苦、影响到日常生活，或出现伤害自己的念头，请联系专业心理/精神科医生，或拨打当地紧急服务。\n中国大陆心理援助热线：12356；紧急情况：110 / 120。')
            .fontSize(12)
            .lineHeight(23)
            .fontColor(this.t().inkSoft)
            .width('100%')
            .margin({ top: 6, bottom: 4 })
          Text('隐私政策')
            .fontSize(12.5)
            .fontColor(this.t().seal)
            .onClick(() => {
              this.getUIContext().getRouter().pushUrl({ url: 'pages/PrivacyPage' }).catch(() => {});
            })
          if (this.selfTestMsg.length > 0) {
            Text(this.selfTestMsg)
              .fontSize(11.5)
              .lineHeight(22)
              .fontColor(this.t().seal)
              .width('100%')
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(20)
        .backgroundColor(this.t().card).backdropBlur(this.dark ? 0 : 10)
        .borderRadius(this.t().radiusCard)
        .border({ width: 1, color: this.t().line })
        .margin({ bottom: 40 })
        }
      }
      .width('100%')
      .constraintSize({ minHeight: '100%' })
      .padding({ left: 20, right: 20, top: 4, bottom: 140 })
    }
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
  }
}




