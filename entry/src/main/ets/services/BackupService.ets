// 句栖 · 完整备份：PBKDF2-SHA256 310000 次 + AES-256-GCM
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { SuppressWarnings, SuppressWarningsType } from '@kit.BasicServicesKit';
import { AppData } from '../model/Types';

const ITERATIONS: number = 310000;
const SALT_LEN: number = 32;
const IV_LEN: number = 12;
const TAG_LEN: number = 16;

// 备份依赖 CryptoFramework；不支持该 syscap 的设备会在加密/解密时失败并提示。
@SuppressWarnings({ rules: [SuppressWarningsType.SYSCAP] })
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

  // 文件级流式加密：不在内存里保留整包 zip。
  static async encryptFile(plainPath: string, outPath: string, password: string): Promise<void> {
    let src: fs.File | null = null;
    let dst: fs.File | null = null;
    try {
      src = fs.openSync(plainPath, fs.OpenMode.READ_ONLY);
      dst = fs.openSync(outPath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
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
      const header = new Uint8Array(3 + SALT_LEN + IV_LEN);
      header[0] = 0x53;
      header[1] = 0x4A;
      header[2] = 0x34;
      header.set(salt, 3);
      header.set(iv, 3 + SALT_LEN);
      fs.writeSync(dst.fd, header.buffer);
      const buf = new ArrayBuffer(64 * 1024);
      let n: number = 0;
      while ((n = fs.readSync(src.fd, buf)) > 0) {
        const out = await cipher.update({ data: new Uint8Array(buf.slice(0, n)) });
        if (out !== null && out.data.length > 0) {
          fs.writeSync(dst.fd, out.data.buffer);
        }
      }
      const fin = await cipher.doFinal(null);
      if (fin !== null && fin.data.length > 0) {
        fs.writeSync(dst.fd, fin.data.buffer);
      }
    } catch (e) {
      throw new Error('加密文件失败：' + String(e));
    } finally {
      if (src !== null) {
        try { fs.closeSync(src); } catch (e) {}
      }
      if (dst !== null) {
        try { fs.closeSync(dst); } catch (e) {}
      }
    }
  }

  // 文件级流式解密：tag 从文件尾部单独读取，再逐块解密。
  static async decryptFile(inPath: string, outPath: string, password: string): Promise<void> {
    let src: fs.File | null = null;
    let dst: fs.File | null = null;
    let tagFile: fs.File | null = null;
    try {
      const st = fs.statSync(inPath);
      const headerLen: number = 3 + SALT_LEN + IV_LEN;
      if (st.size < headerLen + TAG_LEN + 1) {
        throw new Error('不是 SJ4 完整加密备份');
      }
      tagFile = fs.openSync(inPath, fs.OpenMode.READ_ONLY);
      const tagBuf = new ArrayBuffer(TAG_LEN);
      const tagRead = fs.readSync(tagFile.fd, tagBuf, { offset: st.size - TAG_LEN, length: TAG_LEN });
      if (tagRead !== TAG_LEN) {
        throw new Error('备份文件不完整');
      }
      const tag: Uint8Array = new Uint8Array(tagBuf);
      src = fs.openSync(inPath, fs.OpenMode.READ_ONLY);
      const headerBuf = new ArrayBuffer(headerLen);
      const headerRead = fs.readSync(src.fd, headerBuf, { offset: 0, length: headerLen });
      if (headerRead !== headerLen) {
        throw new Error('备份文件不完整');
      }
      const header: Uint8Array = new Uint8Array(headerBuf);
      if (header[0] !== 0x53 || header[1] !== 0x4A || header[2] !== 0x34) {
        throw new Error('不是 SJ4 完整加密备份');
      }
      const salt: Uint8Array = header.slice(3, 3 + SALT_LEN);
      const iv: Uint8Array = header.slice(3 + SALT_LEN, headerLen);
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
      dst = fs.openSync(outPath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      const remainStart: number = headerLen;
      const remainEnd: number = st.size - TAG_LEN;
      let remain: number = remainEnd - remainStart;
      const buf = new ArrayBuffer(64 * 1024);
      while (remain > 0) {
        const want: number = Math.min(buf.byteLength, remain);
        const n = fs.readSync(src.fd, buf, { length: want });
        if (n <= 0) {
          throw new Error('备份文件不完整');
        }
        const out = await cipher.update({ data: new Uint8Array(buf.slice(0, n)) });
        if (out !== null && out.data.length > 0) {
          fs.writeSync(dst.fd, out.data.buffer);
        }
        remain -= n;
      }
      await cipher.doFinal(null);
    } catch (e) {
      const msg: string = String((e as Error).message ?? '');
      if (msg.includes('不是 SJ4')) {
        throw new Error('不是 SJ4 完整加密备份');
      }
      throw new Error('密语错误或备份文件损坏');
    } finally {
      if (src !== null) {
        try { fs.closeSync(src); } catch (e) {}
      }
      if (dst !== null) {
        try { fs.closeSync(dst); } catch (e) {}
      }
      if (tagFile !== null) {
        try { fs.closeSync(tagFile); } catch (e) {}
      }
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


