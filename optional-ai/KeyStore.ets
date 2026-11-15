// 句匣 · AI Key 的系统密钥库封装（Asset Store，避免明文进数据库）
import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';

const ALIAS: string = 'juxia.ai.key';

function toBytes(s: string): Uint8Array {
  return new util.TextEncoder().encodeInto(s);
}

function fromBytes(b: Uint8Array): string {
  return util.TextDecoder.create('utf-8').decodeToString(b);
}

export class KeyStore {
  static async save(key: string): Promise<boolean> {
    await KeyStore.clear();
    const attr: asset.AssetMap = new Map();
    attr.set(asset.Tag.ALIAS, toBytes(ALIAS));
    attr.set(asset.Tag.SECRET, toBytes(key));
    attr.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
    try {
      await asset.add(attr);
      return true;
    } catch (e) {
      return false;
    }
  }

  static async load(): Promise<string> {
    const q: asset.AssetMap = new Map();
    q.set(asset.Tag.ALIAS, toBytes(ALIAS));
    q.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
    try {
      const rows: asset.AssetMap[] = await asset.query(q);
      if (rows.length === 0) return '';
      const sec = rows[0].get(asset.Tag.SECRET);
      if (sec === undefined) return '';
      return fromBytes(sec as Uint8Array);
    } catch (e) {
      return '';
    }
  }

  static async clear(): Promise<void> {
    const q: asset.AssetMap = new Map();
    q.set(asset.Tag.ALIAS, toBytes(ALIAS));
    try {
      await asset.remove(q);
    } catch (e) {
      // 不存在时忽略
    }
  }
}
