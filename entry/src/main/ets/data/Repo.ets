// 句栖 · RDB 持久层（加密数据库；设置类数据存 kv 表）
import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import {
  AppData, Settings, DayState, MetaState, OwnEntry, LibEntry,
  DislikeEntry, MaterialEntry, NoteItem
} from '../model/Types';

const CONFIG: relationalStore.StoreConfig = {
  name: 'juxia.db',
  securityLevel: relationalStore.SecurityLevel.S3,
  encrypt: true
};

class Snapshot {
  own: relationalStore.ValuesBucket[] = [];
  lib: relationalStore.ValuesBucket[] = [];
  dislikes: relationalStore.ValuesBucket[] = [];
  materials: relationalStore.ValuesBucket[] = [];
  kv: relationalStore.ValuesBucket[] = [];
  kvOnly: boolean = false;
}

export class Repo {
  private store: relationalStore.RdbStore | null = null;
  private ftsReady: boolean = false;
  private busy: boolean = false;
  private queued: Snapshot | null = null;
  private rowTasks: Array<() => Promise<void>> = [];
  private rowBusy: boolean = false;

  async init(context: common.UIAbilityContext, legacy: AppData | null): Promise<AppData> {
    try {
      this.store = await relationalStore.getRdbStore(context, CONFIG);
      await this.createTables();
      const schema: string = await this.getKv('schema');
      if (schema === '1') {
        return await this.loadAll();
      }
      const d: AppData = legacy !== null ? legacy : new AppData();
      if (d.meta.firstUse === 0) d.meta.firstUse = Date.now();
      await this.writeSnapshot(this.makeSnapshot(d));
      return d;
    } catch (e) {
      console.error('juxia repo init fail', String(e));
      return legacy !== null ? legacy : new AppData();
    }
  }

  saveAll(d: AppData): void {
    this.queued = this.makeSnapshot(d);
    if (!this.busy) {
      this.drain();
    }
  }

  saveKv(d: AppData): void {
    const rows: relationalStore.ValuesBucket[] = this.kvRows(d);
    if (this.queued !== null && !this.queued.kvOnly) {
      // 已有待写的全量快照：只更新其中的 kv，绝不能覆盖掉 own/lib 等条目
      this.queued.kv = rows;
      return;
    }
    const snap = new Snapshot();
    snap.kvOnly = true;
    snap.kv = rows;
    this.queued = snap;
    if (!this.busy) {
      this.drain();
    }
  }

  private async drain(): Promise<void> {
    this.busy = true;
    try {
      while (this.queued !== null) {
        const snap: Snapshot = this.queued;
        this.queued = null;
        await this.writeSnapshot(snap);
      }
    } finally {
      this.busy = false;
    }
  }

  private makeSnapshot(d: AppData): Snapshot {
    const snap = new Snapshot();
    d.own.forEach((e: OwnEntry) => {
      const b: relationalStore.ValuesBucket = {
        'id': e.id,
        'kind': e.kind,
        'text': e.text,
        'note': e.note,
        'bindIds': JSON.stringify(e.bindIds),
        'createdAt': e.createdAt,
        'archCat': e.archCat,
        'archNote': e.archNote,
        'archAt': e.archAt,
        'revisitAt': e.revisitAt,
        'snoozeUntil': e.snoozeUntil,
        'foot': JSON.stringify(e.foot),
        'notes': JSON.stringify(e.notes)
      };
      snap.own.push(b);
    });
    d.lib.forEach((e: LibEntry) => {
      const b: relationalStore.ValuesBucket = {
        'id': e.id,
        'text': e.text,
        'source': e.source,
        'origin': e.origin,
        'tag': e.tag,
        'createdAt': e.createdAt,
        'bindIds': JSON.stringify(e.bindIds)
      };
      snap.lib.push(b);
    });
    d.dislikes.forEach((e: DislikeEntry) => {
      const b: relationalStore.ValuesBucket = {
        'text': e.text,
        'source': e.source,
        'origin': e.origin,
        'at': e.at
      };
      snap.dislikes.push(b);
    });
    d.materials.forEach((e: MaterialEntry) => {
      const b: relationalStore.ValuesBucket = {
        'id': e.id,
        'name': e.name,
        'text': e.text,
        'path': e.path,
        'size': e.size,
        'createdAt': e.createdAt
      };
      snap.materials.push(b);
    });
    snap.kv = this.kvRows(d);
    return snap;
  }

  private kvRows(d: AppData): relationalStore.ValuesBucket[] {
    const rows: relationalStore.ValuesBucket[] = [];
    rows.push({ 'k': 'schema', 'v': '1' });
    rows.push({ 'k': 'settings', 'v': JSON.stringify(d.settings) });
    rows.push({ 'k': 'day', 'v': JSON.stringify(d.day) });
    rows.push({ 'k': 'meta', 'v': JSON.stringify(d.meta) });
    return rows;
  }

  async replaceSentences(materialId: string, sentences: string[]): Promise<void> {
    const s = this.store;
    if (s === null) return;
    await this.clearSentences(materialId);
    await this.appendSentences(materialId, 0, sentences);
  }

  async appendSentences(materialId: string, startOrd: number, sentences: string[]): Promise<number> {
    const s = this.store;
    if (s === null || sentences.length === 0) return 0;
    let written: number = 0;
    try {
      for (let i = 0; i < sentences.length; i += 200) {
        const chunk: string[] = sentences.slice(i, i + 200);
        const rows: relationalStore.ValuesBucket[] = [];
        const ftsRows: relationalStore.ValuesBucket[] = [];
        chunk.forEach((text: string, j: number) => {
          rows.push({ 'material_id': materialId, 'ord': startOrd + i + j, 'text': text });
          ftsRows.push({ 'material_id': materialId, 'ord': startOrd + i + j, 'text': text });
        });
        await s.batchInsert('material_sentences', rows);
        if (this.ftsReady) {
          try {
            await s.batchInsert('material_fts', ftsRows);
          } catch (e) {
            console.error('juxia fts append fail', String(e));
          }
        }
        written += rows.length;
      }
    } catch (e) {
      console.error('juxia sentence append fail', String(e));
    }
    return written;
  }

  async clearSentences(materialId: string): Promise<void> {
    const s = this.store;
    if (s === null) return;
    try {
      await s.executeSql('DELETE FROM material_sentences WHERE material_id = ?', [materialId]);
      if (this.ftsReady) {
        try {
          await s.executeSql('DELETE FROM material_fts WHERE material_id = ?', [materialId]);
        } catch (e) {
        }
      }
    } catch (e) {
    }
  }

  async clearAllSentences(): Promise<void> {
    const s = this.store;
    if (s === null) return;
    try {
      await s.executeSql('DELETE FROM material_sentences');
      if (this.ftsReady) {
        try {
          await s.executeSql('DELETE FROM material_fts');
        } catch (e) {
          console.error('juxia fts clear fail', String(e));
        }
      }
    } catch (e) {
      console.error('juxia sentences clear fail', String(e));
    }
  }

  private ftsQuery(keywords: string[]): string {
    const parts: string[] = [];
    keywords.forEach((kw: string) => {
      const clean: string = kw.replace(/"/g, '""');
      parts.push(`"${clean}"`);
    });
    return parts.join(' AND ');
  }

  async allSentences(materialId: string, limit: number = 0): Promise<string[]> {
    const s = this.store;
    if (s === null) return [];
    const out: string[] = [];
    try {
      let sql: string = 'SELECT text FROM material_sentences WHERE material_id = ? ORDER BY ord';
      const args: relationalStore.ValueType[] = [materialId];
      if (limit > 0) {
        sql += ' LIMIT ?';
        args.push(limit);
      }
      const rs = await s.querySql(sql, args);
      while (rs.goToNextRow()) {
        out.push(rs.getString(rs.getColumnIndex('text')));
      }
      rs.close();
    } catch (e) {
      console.error('juxia sentences read fail', String(e));
    }
    return out;
  }

  async searchSentences(keywords: string[], materialId: string): Promise<string[]> {
    const s = this.store;
    if (s === null) return [];
    try {
      if (this.ftsReady && keywords.length > 0) {
        try {
          let fsql: string = 'SELECT text FROM material_fts WHERE material_fts MATCH ?';
          const fargs: relationalStore.ValueType[] = [this.ftsQuery(keywords)];
          if (materialId.length > 0) {
            fsql += ' AND material_id = ?';
            fargs.push(materialId);
          }
          fsql += ' LIMIT 120';
          const frs = await s.querySql(fsql, fargs);
          const fout: string[] = [];
          while (frs.goToNextRow()) {
            fout.push(frs.getString(frs.getColumnIndex('text')));
          }
          frs.close();
          if (fout.length > 0) return fout;
        } catch (e) {
          console.error('juxia fts search fail', String(e));
        }
      }
      let sql: string = 'SELECT text FROM material_sentences WHERE 1=1';
      const args: relationalStore.ValueType[] = [];
      keywords.forEach((kw: string) => {
        sql += ' AND text LIKE ?';
        args.push('%' + kw + '%');
      });
      if (materialId.length > 0) {
        sql += ' AND material_id = ?';
        args.push(materialId);
      }
      sql += ' LIMIT 120';
      const rs = await s.querySql(sql, args);
      const out: string[] = [];
      while (rs.goToNextRow()) {
        out.push(rs.getString(rs.getColumnIndex('text')));
      }
      rs.close();
      return out;
    } catch (e) {
      console.error('juxia sentence search fail', String(e));
      return [];
    }
  }

  private async writeSnapshot(snap: Snapshot): Promise<void> {
    const s = this.store;
    if (s === null) return;
    try {
      s.beginTransaction();
      if (snap.kvOnly) {
        await s.executeSql('DELETE FROM kv');
        for (const b of snap.kv) {
          await s.insert('kv', b, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
        }
      } else {
        await s.executeSql('DELETE FROM own');
        await s.executeSql('DELETE FROM lib');
        await s.executeSql('DELETE FROM dislikes');
        await s.executeSql('DELETE FROM materials');
        await s.executeSql('DELETE FROM kv');
        for (const b of snap.own) {
          await s.insert('own', b, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
        }
        for (const b of snap.lib) {
          await s.insert('lib', b, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
        }
        for (const b of snap.dislikes) {
          await s.insert('dislikes', b, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
        }
        for (const b of snap.materials) {
          await s.insert('materials', b, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
        }
        for (const b of snap.kv) {
          await s.insert('kv', b, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
        }
      }
      s.commit();
    } catch (e) {
      try {
        s.rollBack();
      } catch (e2) {
        console.error('juxia rollback fail', String(e2));
      }
      console.error('juxia write snapshot fail', String(e));
    }
  }

  private async createTables(): Promise<void> {
    const s = this.store;
    if (s === null) return;
    try {
      await s.executeSql(
        'CREATE TABLE IF NOT EXISTS own (' +
        'id TEXT PRIMARY KEY, kind TEXT, text TEXT, note TEXT, bindIds TEXT, ' +
        'createdAt INTEGER, archCat TEXT, archNote TEXT, archAt INTEGER, ' +
        'revisitAt INTEGER, snoozeUntil INTEGER, foot TEXT, notes TEXT, replyToId TEXT)'
      );
      await s.executeSql(
        'CREATE TABLE IF NOT EXISTS lib (' +
        'id TEXT PRIMARY KEY, text TEXT, source TEXT, origin TEXT, tag TEXT, createdAt INTEGER, bindIds TEXT)'
      );
      try {
        await s.executeSql('ALTER TABLE lib ADD COLUMN bindIds TEXT');
      } catch (e) {
        // 列已存在：忽略
      }
      try {
        await s.executeSql('ALTER TABLE own ADD COLUMN replyToId TEXT');
      } catch (e) {
        // 列已存在：忽略
      }
      await s.executeSql(
        'CREATE TABLE IF NOT EXISTS dislikes (text TEXT PRIMARY KEY, source TEXT, origin TEXT, at INTEGER)'
      );
      await s.executeSql(
        'CREATE TABLE IF NOT EXISTS materials (id TEXT PRIMARY KEY, name TEXT, text TEXT, path TEXT, size INTEGER, createdAt INTEGER)'
      );
      await s.executeSql(
        'CREATE TABLE IF NOT EXISTS material_sentences (material_id TEXT, ord INTEGER, text TEXT, PRIMARY KEY(material_id, ord))'
      );
      try {
        await s.executeSql(
          'CREATE VIRTUAL TABLE IF NOT EXISTS material_fts USING fts5(text, material_id UNINDEXED, ord UNINDEXED, tokenize=trigram)'
        );
        this.ftsReady = true;
      } catch (e) {
        this.ftsReady = false;
      }
      if (this.ftsReady) {
        await this.rebuildFtsIfNeeded();
      }
      await s.executeSql('CREATE TABLE IF NOT EXISTS kv (k TEXT PRIMARY KEY, v TEXT)');
    } catch (e) {
      console.error('juxia create tables fail', String(e));
    }
  }

  private async rebuildFtsIfNeeded(): Promise<void> {
    const s = this.store;
    if (s === null) return;
    try {
      const a = await s.querySql('SELECT COUNT(*) AS c FROM material_sentences');
      let sentenceCount: number = 0;
      if (a.goToFirstRow()) sentenceCount = a.getLong(a.getColumnIndex('c'));
      a.close();
      const b = await s.querySql('SELECT COUNT(*) AS c FROM material_fts');
      let ftsCount: number = 0;
      if (b.goToFirstRow()) ftsCount = b.getLong(b.getColumnIndex('c'));
      b.close();
      if (sentenceCount !== ftsCount) {
        await s.executeSql('DELETE FROM material_fts');
        await s.executeSql('INSERT INTO material_fts(material_id, ord, text) SELECT material_id, ord, text FROM material_sentences');
      }
    } catch (e) {
    }
  }

  private async getKv(key: string): Promise<string> {
    const s = this.store;
    if (s === null) return '';
    try {
      const rs = await s.querySql('SELECT v FROM kv WHERE k = ?', [key]);
      let v: string = '';
      if (rs.goToFirstRow()) {
        v = rs.getString(rs.getColumnIndex('v'));
      }
      rs.close();
      return v;
    } catch (e) {
      console.error('juxia kv read fail', String(e));
      return '';
    }
  }

  private parseStrings(s: string): string[] {
    try {
      const v = JSON.parse(s) as string[];
      return Array.isArray(v) ? v : [];
    } catch (e) {
      return [];
    }
  }

  private parseNotes(s: string): NoteItem[] {
    try {
      const v = JSON.parse(s) as NoteItem[];
      return Array.isArray(v) ? v : [];
    } catch (e) {
      return [];
    }
  }

  private async loadAll(): Promise<AppData> {
    const d = new AppData();
    const s = this.store;
    if (s === null) return d;
    try {
    const own = await s.querySql('SELECT * FROM own ORDER BY createdAt DESC');
    while (own.goToNextRow()) {
      const e = new OwnEntry();
      e.id = own.getString(own.getColumnIndex('id'));
      e.kind = own.getString(own.getColumnIndex('kind'));
      e.text = own.getString(own.getColumnIndex('text'));
      e.note = own.getString(own.getColumnIndex('note'));
      e.bindIds = this.parseStrings(own.getString(own.getColumnIndex('bindIds')));
      e.createdAt = own.getLong(own.getColumnIndex('createdAt'));
      e.archCat = own.getString(own.getColumnIndex('archCat'));
      e.archNote = own.getString(own.getColumnIndex('archNote'));
      e.archAt = own.getLong(own.getColumnIndex('archAt'));
      e.revisitAt = own.getLong(own.getColumnIndex('revisitAt'));
      e.snoozeUntil = own.getLong(own.getColumnIndex('snoozeUntil'));
      e.foot = this.parseStrings(own.getString(own.getColumnIndex('foot')));
      e.notes = this.parseNotes(own.getString(own.getColumnIndex('notes')));
      e.replyToId = own.getString(own.getColumnIndex('replyToId'));
      d.own.push(e);
    }
    own.close();

    const lib = await s.querySql('SELECT * FROM lib ORDER BY createdAt DESC');
    while (lib.goToNextRow()) {
      const e = new LibEntry();
      e.id = lib.getString(lib.getColumnIndex('id'));
      e.text = lib.getString(lib.getColumnIndex('text'));
      e.source = lib.getString(lib.getColumnIndex('source'));
      e.origin = lib.getString(lib.getColumnIndex('origin'));
      e.tag = lib.getString(lib.getColumnIndex('tag'));
      e.createdAt = lib.getLong(lib.getColumnIndex('createdAt'));
      const bi: number = lib.getColumnIndex('bindIds');
      if (bi >= 0) e.bindIds = this.parseStrings(lib.getString(bi));
      d.lib.push(e);
    }
    lib.close();

    const dis = await s.querySql('SELECT * FROM dislikes ORDER BY at DESC');
    while (dis.goToNextRow()) {
      const e = new DislikeEntry();
      e.text = dis.getString(dis.getColumnIndex('text'));
      e.source = dis.getString(dis.getColumnIndex('source'));
      e.origin = dis.getString(dis.getColumnIndex('origin'));
      e.at = dis.getLong(dis.getColumnIndex('at'));
      d.dislikes.push(e);
    }
    dis.close();

    const mat = await s.querySql('SELECT * FROM materials ORDER BY createdAt ASC');
    while (mat.goToNextRow()) {
      const e = new MaterialEntry();
      e.id = mat.getString(mat.getColumnIndex('id'));
      e.name = mat.getString(mat.getColumnIndex('name'));
      e.text = mat.getString(mat.getColumnIndex('text'));
      e.path = mat.getString(mat.getColumnIndex('path'));
      e.size = mat.getLong(mat.getColumnIndex('size'));
      e.createdAt = mat.getLong(mat.getColumnIndex('createdAt'));
      d.materials.push(e);
    }
    mat.close();

    const kv = await s.querySql('SELECT * FROM kv');
    while (kv.goToNextRow()) {
      const k = kv.getString(kv.getColumnIndex('k'));
      const v = kv.getString(kv.getColumnIndex('v'));
      try {
        if (k === 'settings') d.settings = JSON.parse(v) as Settings;
        else if (k === 'day') d.day = JSON.parse(v) as DayState;
        else if (k === 'meta') d.meta = JSON.parse(v) as MetaState;
      } catch (e) {
      }
    }
    kv.close();
    } catch (e) {
      console.error('juxia load all fail', String(e));
    }
    return d;
  }

  // ---------- 单行增量写入（避免每次保存全量重写） ----------
  private ownBucket(e: OwnEntry): relationalStore.ValuesBucket {
    const b: relationalStore.ValuesBucket = {
      'id': e.id,
      'kind': e.kind,
      'text': e.text,
      'note': e.note,
      'bindIds': JSON.stringify(e.bindIds),
      'createdAt': e.createdAt,
      'archCat': e.archCat,
      'archNote': e.archNote,
      'archAt': e.archAt,
      'revisitAt': e.revisitAt,
      'snoozeUntil': e.snoozeUntil,
      'foot': JSON.stringify(e.foot),
      'notes': JSON.stringify(e.notes),
      'replyToId': e.replyToId
    };
    return b;
  }

  private libBucket(e: LibEntry): relationalStore.ValuesBucket {
    const b: relationalStore.ValuesBucket = {
      'id': e.id,
      'text': e.text,
      'source': e.source,
      'origin': e.origin,
      'tag': e.tag,
      'createdAt': e.createdAt,
      'bindIds': JSON.stringify(e.bindIds)
    };
    return b;
  }

  private pushRow(task: () => Promise<void>): void {
    this.rowTasks.push(task);
    this.drainRows();
  }

  private async drainRows(): Promise<void> {
    if (this.rowBusy) return;
    this.rowBusy = true;
    while (this.rowTasks.length > 0) {
      const t = this.rowTasks.shift();
      if (t !== undefined) {
        try {
          await t();
        } catch (e) {
        }
      }
    }
    this.rowBusy = false;
  }

  private upsert(table: string, b: relationalStore.ValuesBucket): void {
    const s = this.store;
    if (s === null) return;
    this.pushRow(async () => {
      try {
        await s.insert(table, b, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
      } catch (e) {
        console.error('juxia upsert fail', table, String(e));
      }
    });
  }

  private deleteById(table: string, id: string): void {
    const s = this.store;
    if (s === null) return;
    this.pushRow(async () => {
      try {
        const p = new relationalStore.RdbPredicates(table);
        p.equalTo('id', id);
        await s.delete(p);
      } catch (e) {
        console.error('juxia delete fail', table, String(e));
      }
    });
  }

  saveOwnRow(e: OwnEntry): void {
    this.upsert('own', this.ownBucket(e));
  }

  saveLibRow(e: LibEntry): void {
    this.upsert('lib', this.libBucket(e));
  }

  deleteLibRow(id: string): void {
    this.deleteById('lib', id);
  }

  deleteOwnRow(id: string): void {
    this.deleteById('own', id);
  }

  deleteMaterialRow(id: string): void {
    this.deleteById('materials', id);
  }

  saveDislikeRow(e: DislikeEntry): void {
    const b: relationalStore.ValuesBucket = {
      'text': e.text,
      'source': e.source,
      'origin': e.origin,
      'at': e.at
    };
    this.upsert('dislikes', b);
  }

  deleteDislikeRow(text: string): void {
    const s = this.store;
    if (s === null) return;
    this.pushRow(async () => {
      try {
        const p = new relationalStore.RdbPredicates('dislikes');
        p.equalTo('text', text);
        await s.delete(p);
      } catch (e) {
        console.error('juxia dislike delete fail', String(e));
      }
    });
  }
}


