// 句栖 · 自定义背景：选图、复制、压缩、存储
import { common } from '@kit.AbilityKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';

export class BackgroundService {
  static async pick(ctx: common.UIAbilityContext): Promise<string> {
    try {
      const picker = new photoAccessHelper.PhotoViewPicker();
      const opts = new photoAccessHelper.PhotoSelectOptions();
      opts.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      opts.maxSelectNumber = 1;
      const result = await picker.select(opts);
      return result.photoUris.length > 0 ? result.photoUris[0] : '';
    } catch (e) {
      throw new Error('PICK_IMAGE_FAILED');
    }
  }

  static cachePath(ctx: common.UIAbilityContext, stamp: number): string {
    return ctx.cacheDir + '/bg_pick_' + stamp + '.img';
  }

  static imagePath(ctx: common.UIAbilityContext, key: string): string {
    return ctx.filesDir + '/backgrounds/' + key + '.jpg';
  }

  static copyToCache(ctx: common.UIAbilityContext, uri: string, dest: string): void {
    let copied: boolean = false;
    try {
      fs.copyFileSync(uri, dest);
      copied = fs.statSync(dest).size > 0;
    } catch (e) {
      copied = false;
    }
    if (!copied) {
      let src: fs.File | null = null;
      let dst: fs.File | null = null;
      try {
        src = fs.openSync(uri, fs.OpenMode.READ_ONLY);
        dst = fs.openSync(dest, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
        const buf = new ArrayBuffer(64 * 1024);
        let n: number = 0;
        while ((n = fs.readSync(src.fd, buf)) > 0) {
          fs.writeSync(dst.fd, buf.slice(0, n));
        }
      } catch (e) {
        throw new Error('COPY_IMAGE_FAILED');
      } finally {
        if (src !== null) {
          try { fs.closeSync(src); } catch (e) {}
        }
        if (dst !== null) {
          try { fs.closeSync(dst); } catch (e) {}
        }
      }
    }
    try {
      if (fs.statSync(dest).size === 0) throw new Error('EMPTY_IMAGE');
    } catch (e) {
      throw new Error('COPY_IMAGE_FAILED');
    }
  }

  static async savePixelMap(ctx: common.UIAbilityContext, pm: image.PixelMap, key: string): Promise<string> {
    const dir: string = ctx.filesDir + '/backgrounds';
    try {
      fs.mkdirSync(dir);
    } catch (e) {
    }
    const dest: string = BackgroundService.imagePath(ctx, key);
    let f: fs.File | null = null;
    try {
      const packer = image.createImagePacker();
      f = fs.openSync(dest, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      await packer.packToFile(pm, f.fd, { format: 'image/jpeg', quality: 85 });
      fs.fsyncSync(f.fd);
      return dest;
    } catch (e) {
      console.error('juxia bg save fail', String(e));
      throw new Error('SAVE_IMAGE_FAILED');
    } finally {
      if (f !== null) {
        try { fs.closeSync(f); } catch (e) {}
      }
    }
  }

  static remove(ctx: common.UIAbilityContext, path: string): void {
    if (path.length === 0) return;
    try {
      fs.unlinkSync(path);
    } catch (e) {
    }
  }
}
