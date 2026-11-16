// 材料索引自愈：启动时只处理中断的导入，避免每次全量扫描。
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { Store } from '../data/Store';
import { MaterialIndexer } from './MaterialIndexer';

const LEGACY_MARKER: string = '/.material-repair-v1';

export class MaterialRepair {
  private static running: boolean = false;

  static marker(path: string): string {
    return path + '.indexing';
  }

  static mark(path: string): void {
    if (path.length === 0) return;
    let f: fs.File | null = null;
    try {
      f = fs.openSync(MaterialRepair.marker(path),
        fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
    } catch (e) {
    } finally {
      if (f !== null) {
        try { fs.closeSync(f); } catch (e) {}
      }
    }
  }

  static clear(path: string): void {
    if (path.length === 0) return;
    try { fs.unlinkSync(MaterialRepair.marker(path)); } catch (e) {}
  }

  private static pending(path: string): boolean {
    try {
      fs.statSync(MaterialRepair.marker(path));
      return true;
    } catch (e) {
      return false;
    }
  }

  private static legacyDone(ctx: common.UIAbilityContext): boolean {
    try {
      fs.statSync(ctx.filesDir + LEGACY_MARKER);
      return true;
    } catch (e) {
      return false;
    }
  }

  private static markLegacyDone(ctx: common.UIAbilityContext): void {
    let f: fs.File | null = null;
    try {
      f = fs.openSync(ctx.filesDir + LEGACY_MARKER,
        fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
    } catch (e) {
    } finally {
      if (f !== null) {
        try { fs.closeSync(f); } catch (e) {}
      }
    }
  }

  static async run(ctx: common.UIAbilityContext): Promise<number> {
    if (MaterialRepair.running) return 0;
    MaterialRepair.running = true;
    let repaired: number = 0;
    try {
      const st = Store.get();
      const legacy: boolean = !MaterialRepair.legacyDone(ctx);
      for (const m of st.data.materials) {
        if (m.path.length === 0) continue;
        try {
          fs.statSync(m.path);
        } catch (e) {
          MaterialRepair.clear(m.path);
          continue;
        }
        const must: boolean = MaterialRepair.pending(m.path);
        if (!legacy && !must) continue;
        let need: boolean = must;
        if (legacy && !need) {
          const rows = await st.materialSentences(m.id, 1);
          need = rows.length === 0;
        }
        if (!need) continue;
        st.clearMaterialIndex(m.id);
        const r = await MaterialIndexer.indexFile(m.id, m.path, false, true);
        if (r.ok) {
          repaired++;
          MaterialRepair.clear(m.path);
        } else if (legacy && !must) {
          // 旧数据修复失败：留下标记，下次只重试这一份。
          MaterialRepair.mark(m.path);
        }
      }
      if (legacy) MaterialRepair.markLegacyDone(ctx);
    } catch (e) {
    } finally {
      MaterialRepair.running = false;
    }
    return repaired;
  }
}
