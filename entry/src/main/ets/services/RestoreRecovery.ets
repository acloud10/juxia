// 句栖 · 启动时恢复检查：回滚未提交的恢复，或补完已提交的恢复
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { Store } from '../data/Store';
import { MaterialIndexer } from './MaterialIndexer';
import { RestoreJournal, RestoreJournalData } from './RestoreJournal';
import { AppError } from './AppError';

export class RestoreRecovery {
  private static exists(path: string): boolean {
    try {
      return fs.accessSync(path);
    } catch (e) {
      return false;
    }
  }

  static async recover(ctx: common.UIAbilityContext): Promise<void> {
    let journal: RestoreJournalData | null = null;
    try {
      journal = RestoreJournal.read(ctx);
    } catch (e) {
      AppError.report('恢复日志损坏。', '请重新恢复备份；不要继续修改当前数据。');
      return;
    }
    if (journal === null) {
      return;
    }
    if (journal.phase === 'done') {
      if (RestoreRecovery.exists(journal.newDir)) {
        RestoreJournal.cleanupOldMaterials(ctx, journal.newDir);
      }
      RestoreJournal.remove(ctx);
      return;
    }
    const store: Store = Store.get();
    let dbToken: string = '';
    try {
      dbToken = await store.restoreToken();
    } catch (e) {
      console.error('juxia restore recovery token fail', String(e));
      return;
    }
    if (dbToken !== journal.token) {
      // DB 没有提交：新材料目录作废，旧数据保持原样。
      RestoreJournal.removeDir(journal.newDir);
      RestoreJournal.remove(ctx);
      return;
    }
    // DB 已提交：先确认新材料目录还在，再补索引和清理。
    if (!RestoreRecovery.exists(journal.newDir)) {
      AppError.report('上次恢复未完成。', '材料目录缺失；请重新恢复备份，不要继续修改当前数据。');
      return;
    }
    let failed: number = 0;
    for (const m of store.data.materials) {
      try {
        store.clearMaterialIndex(m.id);
        const r = await MaterialIndexer.indexFile(m.id, m.path);
        if (!r.ok) {
          failed++;
        }
      } catch (e) {
        failed++;
      }
    }
    if (failed > 0) {
      AppError.report('上次恢复未完成。', '材料索引还没建完；重启应用后会继续重试。');
      return;
    }
    RestoreJournal.cleanupOldMaterials(ctx, journal.newDir);
    journal.phase = 'done';
    RestoreJournal.write(ctx, journal);
    RestoreJournal.remove(ctx);
  }
}
