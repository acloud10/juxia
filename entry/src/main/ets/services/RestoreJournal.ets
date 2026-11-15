// 句栖 · 恢复 journal：记录跨文件系统/数据库的恢复阶段
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';

export class RestoreJournalData {
  format: string = 'juxia-restore-journal';
  version: number = 1;
  token: string = '';
  phase: string = 'prepared';
  newDir: string = '';
  createdAt: number = 0;
}

export class RestoreJournal {
  static path(ctx: common.UIAbilityContext): string {
    return ctx.filesDir + '/restore-journal.json';
  }

  static tmpPath(ctx: common.UIAbilityContext): string {
    return ctx.filesDir + '/restore-journal.tmp';
  }

  static read(ctx: common.UIAbilityContext): RestoreJournalData | null {
    const p: string = RestoreJournal.path(ctx);
    try {
      if (!fs.accessSync(p)) {
        // 上次只写完了 tmp、还没 rename：视为没有提交，清掉半成品。
        const tmp: string = RestoreJournal.tmpPath(ctx);
        if (fs.accessSync(tmp)) {
          fs.unlinkSync(tmp);
        }
        return null;
      }
      const text: string = fs.readTextSync(p);
      const d = JSON.parse(text) as RestoreJournalData;
      if (d.format !== 'juxia-restore-journal' || d.version !== 1 ||
        d.token.length === 0 || d.newDir.length === 0) {
        throw new Error('JOURNAL_SHAPE');
      }
      const root: string = ctx.filesDir + '/materials/';
      if (!d.newDir.startsWith(root)) {
        throw new Error('JOURNAL_PATH');
      }
      return d;
    } catch (e) {
      console.error('juxia restore journal read fail', String(e));
      throw new Error('JOURNAL_CORRUPT');
    }
  }

  static write(ctx: common.UIAbilityContext, d: RestoreJournalData): void {
    const p: string = RestoreJournal.path(ctx);
    const tmp: string = RestoreJournal.tmpPath(ctx);
    let f: fs.File | null = null;
    try {
      f = fs.openSync(tmp, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      fs.writeSync(f.fd, JSON.stringify(d));
      fs.fsyncSync(f.fd);
      try { fs.closeSync(f); } catch (e) {}
      f = null;
      fs.renameSync(tmp, p);
    } catch (e) {
      throw new Error('JOURNAL_WRITE_FAILED');
    } finally {
      if (f !== null) {
        try { fs.closeSync(f); } catch (e) {}
      }
      try {
        if (fs.accessSync(tmp)) {
          fs.unlinkSync(tmp);
        }
      } catch (e) {}
    }
  }

  static remove(ctx: common.UIAbilityContext): void {
    const p: string = RestoreJournal.path(ctx);
    const tmp: string = RestoreJournal.tmpPath(ctx);
    try {
      if (fs.accessSync(p)) {
        fs.unlinkSync(p);
      }
    } catch (e) {
      console.error('juxia restore journal remove fail', String(e));
    }
    try {
      if (fs.accessSync(tmp)) {
        fs.unlinkSync(tmp);
      }
    } catch (e) {}
  }

  static removeDir(dir: string): void {
    try {
      const names: string[] = fs.listFileSync(dir);
      names.forEach((name: string) => {
        const p: string = dir + '/' + name;
        try {
          if (fs.statSync(p).isDirectory()) {
            RestoreJournal.removeDir(p);
          } else {
            fs.unlinkSync(p);
          }
        } catch (e) {}
      });
      fs.rmdirSync(dir);
    } catch (e) {}
  }

  // 只保留当前 generation，清掉旧 generation / 旧平铺文件。
  static cleanupOldMaterials(ctx: common.UIAbilityContext, keepDir: string): void {
    const root: string = ctx.filesDir + '/materials';
    try {
      if (!fs.accessSync(root)) {
        return;
      }
      const names: string[] = fs.listFileSync(root);
      names.forEach((name: string) => {
        const p: string = root + '/' + name;
        if (p === keepDir) {
          return;
        }
        try {
          if (fs.statSync(p).isDirectory()) {
            RestoreJournal.removeDir(p);
          } else {
            fs.unlinkSync(p);
          }
        } catch (e) {}
      });
    } catch (e) {
      console.error('juxia cleanup old materials fail', String(e));
    }
  }
}
