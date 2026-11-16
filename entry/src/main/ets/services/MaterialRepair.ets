// 材料索引自愈：启动时修复中断的导入，避免“材料在、搜不到”。
import { fileIo as fs } from '@kit.CoreFileKit';
import { Store } from '../data/Store';
import { MaterialIndexer } from './MaterialIndexer';

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

  static async run(): Promise<number> {
    if (MaterialRepair.running) return 0;
    MaterialRepair.running = true;
    let repaired: number = 0;
    try {
      const st = Store.get();
      for (const m of st.data.materials) {
        if (m.path.length === 0) continue;
        try {
          fs.statSync(m.path);
        } catch (e) {
          MaterialRepair.clear(m.path);
          continue;
        }
        const must = MaterialRepair.pending(m.path);
        const rows = await st.materialSentences(m.id, 1);
        if (!must && rows.length > 0) continue;
        st.clearMaterialIndex(m.id);
        const r = await MaterialIndexer.indexFile(m.id, m.path, false, true);
        if (r.ok) {
          repaired++;
          MaterialRepair.clear(m.path);
        }
      }
    } catch (e) {
    } finally {
      MaterialRepair.running = false;
    }
    return repaired;
  }
}
