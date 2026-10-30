// 句栖 · 密语备份：PBKDF2-SHA256 15 万次 + AES-256-GCM
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { AppData } from '../model/Types';

const ITERATIONS: number = 310000;
const SALT_LEN: number = 32;
const IV_LEN: number = 12;
const TAG_LEN: number = 16;

export class BackupService {
  static serialize(data: AppData): string {
    return JSON.stringify(data, (key: string, value: Object): Object | undefined => {
      if (typeof key === 'string' && (key === 'ai' || key.startsWith('ai'))) return undefined;
      return value;
    });
  }

  static async encrypt(data: AppData, password: string): Promise<string> {
    const random = cryptoFramework.createRandom();
    const salt: Uint8Array = random.generateRandomSync(SALT_LEN).data;
    const iv: Uint8Array = random.generateRandomSync(IV_LEN).data;
    const key: Uint8Array = await BackupService.deriveKey(password, salt);
    const symKey = await cryptoFramework.createSymKeyGenerator('AES256').convertKey({ data: key });
    const cipher = cryptoFramework.createCipher('AES256|GCM|NoPadding');
    const params: cryptoFramework.GcmParamsSpec = {
      algName: 'GcmParamsSpec',
      iv: { data: iv },
      aad: { data: new Uint8Array(0) },
      authTag: { data: new Uint8Array(0) }
    };
    cipher.initSync(cryptoFramework.CryptoMode.ENCRYPT_MODE, symKey, params);
    let plain: Uint8Array = new Uint8Array(0);
    try {
      plain = BackupService.utf8(BackupService.serialize(data));
    } catch (e) {
      throw new Error(String((e as Error).message ?? 'encode failed'));
    }
    let out: cryptoFramework.DataBlob = { data: new Uint8Array(0) };
    try {
      out = cipher.doFinalSync({ data: plain });
    } catch (e) {
      throw new Error(String((e as Error).message ?? 'final failed'));
    }
    const all = new Uint8Array(SALT_LEN + IV_LEN + out.data.length);
    all.set(salt, 0);
    all.set(iv, SALT_LEN);
    all.set(out.data, SALT_LEN + IV_LEN);
    return 'SJ3.' + new util.Base64Helper().encodeToStringSync(all);
  }

  static async decrypt(payload: string, password: string): Promise<AppData> {
    let text: string = payload.trim();
    if (text.startsWith('SJ3.')) {
      text = text.slice(4);
    }
    const raw: Uint8Array = new util.Base64Helper().decodeSync(text);
    if (raw.length < SALT_LEN + IV_LEN + TAG_LEN + 1) {
      throw new Error('密语包长度不对');
    }
    const salt: Uint8Array = raw.slice(0, SALT_LEN);
    const iv: Uint8Array = raw.slice(SALT_LEN, SALT_LEN + IV_LEN);
    const body: Uint8Array = raw.slice(SALT_LEN + IV_LEN);
    const ct: Uint8Array = body.slice(0, body.length - TAG_LEN);
    const tag: Uint8Array = body.slice(body.length - TAG_LEN);
    const key: Uint8Array = await BackupService.deriveKey(password, salt);
    const symKey = await cryptoFramework.createSymKeyGenerator('AES256').convertKey({ data: key });
    const cipher = cryptoFramework.createCipher('AES256|GCM|NoPadding');
    const params: cryptoFramework.GcmParamsSpec = {
      algName: 'GcmParamsSpec',
      iv: { data: iv },
      aad: { data: new Uint8Array(0) },
      authTag: { data: tag }
    };
    cipher.initSync(cryptoFramework.CryptoMode.DECRYPT_MODE, symKey, params);
    const out = cipher.doFinalSync({ data: ct });
    const decoder = util.TextDecoder.create('utf-8');
    const json: string = decoder.decodeToString(out.data);
    return JSON.parse(json) as AppData;
  }

  static async encryptBytes(plain: Uint8Array, password: string): Promise<Uint8Array> {
    const random = cryptoFramework.createRandom();
    const salt: Uint8Array = random.generateRandomSync(SALT_LEN).data;
    const iv: Uint8Array = random.generateRandomSync(IV_LEN).data;
    const key: Uint8Array = await BackupService.deriveKey(password, salt);
    const symKey = await cryptoFramework.createSymKeyGenerator('AES256').convertKey({ data: key });
    const cipher = cryptoFramework.createCipher('AES256|GCM|NoPadding');
    const params: cryptoFramework.GcmParamsSpec = {
      algName: 'GcmParamsSpec',
      iv: { data: iv },
      aad: { data: new Uint8Array(0) },
      authTag: { data: new Uint8Array(0) }
    };
    cipher.initSync(cryptoFramework.CryptoMode.ENCRYPT_MODE, symKey, params);
    const out = cipher.doFinalSync({ data: plain });
    const all = new Uint8Array(3 + SALT_LEN + IV_LEN + out.data.length);
    all[0] = 0x53;
    all[1] = 0x4A;
    all[2] = 0x34;
    all.set(salt, 3);
    all.set(iv, 3 + SALT_LEN);
    all.set(out.data, 3 + SALT_LEN + IV_LEN);
    return all;
  }

  static async decryptBytes(raw: Uint8Array, password: string): Promise<Uint8Array> {
    if (raw.length < 3 + SALT_LEN + IV_LEN + TAG_LEN + 1 ||
      raw[0] !== 0x53 || raw[1] !== 0x4A || raw[2] !== 0x34) {
      throw new Error('不是 SJ4 完整加密包');
    }
    const salt: Uint8Array = raw.slice(3, 3 + SALT_LEN);
    const iv: Uint8Array = raw.slice(3 + SALT_LEN, 3 + SALT_LEN + IV_LEN);
    const body: Uint8Array = raw.slice(3 + SALT_LEN + IV_LEN);
    const ct: Uint8Array = body.slice(0, body.length - TAG_LEN);
    const tag: Uint8Array = body.slice(body.length - TAG_LEN);
    const key: Uint8Array = await BackupService.deriveKey(password, salt);
    const symKey = await cryptoFramework.createSymKeyGenerator('AES256').convertKey({ data: key });
    const cipher = cryptoFramework.createCipher('AES256|GCM|NoPadding');
    const params: cryptoFramework.GcmParamsSpec = {
      algName: 'GcmParamsSpec',
      iv: { data: iv },
      aad: { data: new Uint8Array(0) },
      authTag: { data: tag }
    };
    cipher.initSync(cryptoFramework.CryptoMode.DECRYPT_MODE, symKey, params);
    const out = cipher.doFinalSync({ data: ct });
    return out.data;
  }

  private static utf8(text: string): Uint8Array {
    const out: number[] = [];
    for (let i = 0; i < text.length; i++) {
      const code: number = text.charCodeAt(i);
      if (code < 0x80) {
        out[out.length] = code;
      } else if (code < 0x800) {
        out[out.length] = 0xC0 | (code >> 6);
        out[out.length] = 0x80 | (code & 0x3F);
      } else if (code >= 0xD800 && code <= 0xDBFF && i + 1 < text.length) {
        const low: number = text.charCodeAt(i + 1);
        if (low >= 0xDC00 && low <= 0xDFFF) {
          const cp: number = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00);
          out[out.length] = 0xF0 | (cp >> 18);
          out[out.length] = 0x80 | ((cp >> 12) & 0x3F);
          out[out.length] = 0x80 | ((cp >> 6) & 0x3F);
          out[out.length] = 0x80 | (cp & 0x3F);
          i++;
        } else {
          out[out.length] = 0xEF;
          out[out.length] = 0xBF;
          out[out.length] = 0xBD;
        }
      } else if (code >= 0xDC00 && code <= 0xDFFF) {
        out[out.length] = 0xEF;
        out[out.length] = 0xBF;
        out[out.length] = 0xBD;
      } else {
        out[out.length] = 0xE0 | (code >> 12);
        out[out.length] = 0x80 | ((code >> 6) & 0x3F);
        out[out.length] = 0x80 | (code & 0x3F);
      }
    }
    return new Uint8Array(out);
  }

  private static async deriveKey(password: string, salt: Uint8Array): Promise<Uint8Array> {
    const spec: cryptoFramework.PBKDF2Spec = {
      algName: 'PBKDF2',
      password: password,
      salt: salt,
      iterations: ITERATIONS,
      keySize: 32
    };
    const secret = await cryptoFramework.createKdf('PBKDF2|SHA256').generateSecret(spec);
    return secret.data;
  }

  static valid(d: AppData): boolean {
    if (d === null || d === undefined) return false;
    return Array.isArray(d.own) && Array.isArray(d.lib) &&
      Array.isArray(d.materials) && d.settings !== null && d.settings !== undefined;
  }
}


