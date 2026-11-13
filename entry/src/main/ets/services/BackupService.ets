// 句栖 · 完整备份：PBKDF2-SHA256 310000 次 + AES-256-GCM
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { AppData } from '../model/Types';

const ITERATIONS: number = 310000;
const SALT_LEN: number = 32;
const IV_LEN: number = 12;
const TAG_LEN: number = 16;

export class BackupService {
  static serialize(data: AppData): string {
    try {
      return JSON.stringify(data);
    } catch (e) {
      throw new Error('备份序列化失败：' + String(e));
    }
  }

  static async encryptBytes(plain: Uint8Array, password: string): Promise<Uint8Array> {
    try {
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
    } catch (e) {
      throw new Error('加密文件失败：' + String(e));
    }
  }

  static async decryptBytes(raw: Uint8Array, password: string): Promise<Uint8Array> {
    if (raw.length < 3 + SALT_LEN + IV_LEN + TAG_LEN + 1 ||
      raw[0] !== 0x53 || raw[1] !== 0x4A || raw[2] !== 0x34) {
      throw new Error('不是 SJ4 完整加密备份');
    }
    try {
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
    } catch (e) {
      throw new Error('密语错误或备份文件损坏');
    }
  }

  private static async deriveKey(password: string, salt: Uint8Array): Promise<Uint8Array> {
    try {
      const spec: cryptoFramework.PBKDF2Spec = {
        algName: 'PBKDF2',
        password: password,
        salt: salt,
        iterations: ITERATIONS,
        keySize: 32
      };
      const secret = await cryptoFramework.createKdf('PBKDF2|SHA256').generateSecret(spec);
      return secret.data;
    } catch (e) {
      throw new Error('派生备份密钥失败：' + String(e));
    }
  }

  static valid(d: AppData): boolean {
    if (d === null || d === undefined) return false;
    return Array.isArray(d.own) && Array.isArray(d.lib) &&
      Array.isArray(d.materials) && d.settings !== null && d.settings !== undefined;
  }
}


