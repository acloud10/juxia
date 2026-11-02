// 材料文件的分块索引：导入、恢复后都可复用
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { Store } from '../data/Store';
import { splitSentences, stripMarkdown } from '../utils/TextSplit';

export class MaterialIndexer {
  private static lastBreak(s: string): number {
    let last: number = -1;
    for (let i = s.length - 1; i >= 0; i--) {
      if (s.charAt(i) === '\n') {
        let j: number = i - 1;
        while (j >= 0 && (s.charAt(j) === ' ' || s.charAt(j) === '\t')) {
          j--;
        }
        if (j >= 0 && s.charAt(j) === '\n') {
          last = i;
          break;
        }
      }
    }
    if (last < 0 && s.length > 40000) {
      const nl: number = s.lastIndexOf('\n');
      last = nl >= 0 ? nl : s.length - 1;
    }
    return last;
  }

  private static async yieldUi(): Promise<void> {
    await new Promise<void>((resolve) => {
      setTimeout(() => resolve(), 0);
    });
  }

  private static detectEncoding(path: string): string {
    let file: fs.File | null = null;
    try {
      file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      const buf = new ArrayBuffer(4096);
      const n = fs.readSync(file.fd, buf);
      if (n <= 0) return 'utf-8';
      const bytes = new Uint8Array(buf.slice(0, n));
      if (n >= 3 && bytes[0] === 0xEF && bytes[1] === 0xBB && bytes[2] === 0xBF) return 'utf-8';
      if (n >= 2 && bytes[0] === 0xFF && bytes[1] === 0xFE) return 'utf-16le';
      if (n >= 2 && bytes[0] === 0xFE && bytes[1] === 0xFF) return 'utf-16be';
      if (n >= 4 && bytes[1] === 0 && bytes[3] === 0) return 'utf-16le';
      if (n >= 4 && bytes[0] === 0 && bytes[2] === 0) return 'utf-16be';
      try {
        const probe = util.TextDecoder.create('utf-8', { fatal: true });
        probe.decodeToString(bytes, { stream: true });
        return 'utf-8';
      } catch (e) {
        return 'gb18030';
      }
    } catch (e) {
      return 'utf-8';
    } finally {
      if (file !== null) {
        try {
          fs.closeSync(file);
        } catch (e) {
          console.error('juxia material close fail', String(e));
        }
      }
    }
  }

  static async indexFile(id: string, path: string, markdown: boolean = false): Promise<number> {
    let file: fs.File | null = null;
    try {
      file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      const encoding = MaterialIndexer.detectEncoding(path);
      let decoder: util.TextDecoder;
      try {
        decoder = util.TextDecoder.create(encoding);
      } catch (e) {
        decoder = util.TextDecoder.create('utf-8');
      }
      const buf = new ArrayBuffer(64 * 1024);
      let pending: string = '';
      let ord: number = 0;
      let batch: string[] = [];
      let n: number = 0;
      const clean = (s: string): string => markdown ? stripMarkdown(s) : s;
      while ((n = fs.readSync(file.fd, buf)) > 0) {
        const bytes = new Uint8Array(buf.slice(0, n));
        pending += decoder.decodeToString(bytes, { stream: true });
        const cut: number = MaterialIndexer.lastBreak(pending);
        if (cut >= 0) {
          const complete: string = pending.slice(0, cut + 1);
          pending = pending.slice(cut + 1);
          batch = batch.concat(splitSentences(clean(complete)));
        }
        if (batch.length >= 250) {
          await Store.get().appendMaterialSentences(id, ord, batch);
          ord += batch.length;
          batch = [];
          await MaterialIndexer.yieldUi();
        }
      }
      pending += decoder.decodeToString(new Uint8Array(0), { stream: false });
      batch = batch.concat(splitSentences(clean(pending)));
      if (batch.length > 0) {
        await Store.get().appendMaterialSentences(id, ord, batch);
        ord += batch.length;
      }
      return ord;
    } catch (e) {
      return 0;
    } finally {
      if (file !== null) {
        try {
          fs.closeSync(file);
        } catch (e) {
          console.error('juxia material close fail', String(e));
        }
      }
    }
  }
}
