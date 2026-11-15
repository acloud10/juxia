// 句栖 · 背景图裁剪：全屏预览，可见区域就是最终背景
import { common } from '@kit.AbilityKit';
import { display } from '@kit.ArkUI';
import { fileIo as fs } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { BackgroundService } from '../services/BackgroundService';
import { UiState } from '../state/UiState';
import { Store } from '../data/Store';
import { Tokens, getTokens, FONT_SANS } from '../theme/Theme';

@Entry
@ComponentV2
struct BackgroundCropPage {
  @Local src: string = '';
  @Local cropKey: string = 'light';
  @Local zoom: number = 1.0;
  @Local tx: number = 0;
  @Local ty: number = 0;
  @Local startX: number = 0;
  @Local startY: number = 0;
  @Local startZoom: number = 1;
  @Local lastX: number = 0;
  @Local lastY: number = 0;
  @Local pinchStart: number = 0;
  @Local pinchZoom: number = 1;
  @Local pinching: boolean = false;
  @Local saving: boolean = false;
  @Local dark: boolean = false;
  @Local skin: string = 'classic';
  @Local pixelMap: image.PixelMap | null = null;
  @Local vw: number = 1080;
  @Local vh: number = 2400;
  @Local frameW: number = 900;
  @Local frameH: number = 1600;
  @Local imgW: number = 0;
  @Local imgH: number = 0;

  private t(): Tokens {
    return getTokens(this.skin, this.dark);
  }

  aboutToAppear(): void {
    this.src = AppStorage.get<string>('bgCropSrc') ?? '';
    this.cropKey = AppStorage.get<string>('bgCropKey') ?? 'light';
    this.skin = AppStorage.get<string>('bgCropSkin') ?? 'classic';
    this.dark = AppStorage.get<boolean>('bgCropDark') ?? false;
    try {
      const d = display.getDefaultDisplaySync();
      this.vw = d.width;
      this.vh = d.height;
      this.frameW = d.width * 0.86;
      this.frameH = this.frameW * d.height / d.width;
    } catch (e) {
    }
    if (this.src.length === 0) {
      try {
        this.getUIContext().getPromptAction().showToast({ message: '没有选到图片' });
      } catch (e) {
      }
      this.getUIContext().getRouter().back();
    } else {
      this.loadImage();
    }
  }

  private vp(px: number): number {
    return this.getUIContext().px2vp(px);
  }

  private px(v: number): number {
    return this.getUIContext().vp2px(v);
  }

  private dispW(): number {
    if (this.imgW <= 0) return this.vp(this.vw);
    const base: number = Math.max(this.vw / this.imgW, this.vh / this.imgH);
    return this.vp(this.imgW * base * this.zoom);
  }

  private dispH(): number {
    if (this.imgH <= 0) return this.vp(this.vh);
    const base: number = Math.max(this.vw / this.imgW, this.vh / this.imgH);
    return this.vp(this.imgH * base * this.zoom);
  }

  private clamp(): void {
    if (this.imgW <= 0 || this.imgH <= 0) return;
    const sw: number = this.dispW();
    const sh: number = this.dispH();
    const mx: number = Math.max(0, (sw - this.vp(this.vw)) / 2);
    const my: number = Math.max(0, (sh - this.vp(this.vh)) / 2);
    this.tx = Math.max(-mx, Math.min(mx, this.tx));
    this.ty = Math.max(-my, Math.min(my, this.ty));
  }

  private touchDist(event: TouchEvent): number {
    if (event.touches.length < 2) return 0;
    const dx: number = event.touches[0].x - event.touches[1].x;
    const dy: number = event.touches[0].y - event.touches[1].y;
    return Math.sqrt(dx * dx + dy * dy);
  }

  private handleTouch(event: TouchEvent): void {
    const n: number = event.touches.length;
    console.info('juxia-touch type=' + event.type + ' n=' + n + ' tx=' + this.tx.toFixed(1) +
      ' ty=' + this.ty.toFixed(1) + ' zoom=' + this.zoom.toFixed(2) + ' pm=' + (this.pixelMap !== null));
    if (this.pixelMap === null) return;
    if (event.type === TouchType.Down) {
      if (n >= 2) {
        this.pinching = true;
        this.pinchStart = this.touchDist(event);
        this.pinchZoom = this.zoom;
      } else if (n === 1) {
        this.pinching = false;
        this.lastX = event.touches[0].x;
        this.lastY = event.touches[0].y;
      }
      return;
    }
    if (event.type === TouchType.Move) {
      if (n >= 2) {
        const d: number = this.touchDist(event);
        if (this.pinchStart > 0) {
          this.zoom = Math.max(1, Math.min(4, this.pinchZoom * d / this.pinchStart));
          this.clamp();
        }
      } else if (n === 1) {
        const x: number = event.touches[0].x;
        const y: number = event.touches[0].y;
        if (this.pinching) {
          this.pinching = false;
          this.lastX = x;
          this.lastY = y;
          return;
        }
        this.tx += x - this.lastX;
        this.ty += y - this.lastY;
        this.lastX = x;
        this.lastY = y;
        this.clamp();
      }
      return;
    }
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      if (n < 2) {
        this.pinchStart = 0;
        this.pinching = false;
      }
      this.clamp();
    }
  }

  private async loadImage(): Promise<void> {
    let f: fs.File | null = null;
    try {
      f = fs.openSync(this.src, fs.OpenMode.READ_ONLY);
      const src = image.createImageSource(f.fd);
      const info = await src.getImageInfo();
      this.imgW = info.size.width;
      this.imgH = info.size.height;
      this.pixelMap = await src.createPixelMap();
    } catch (e) {
      try { this.getUIContext().getPromptAction().showToast({ message: '无法读取图片' }); } catch (e2) {}
      this.getUIContext().getRouter().back();
    } finally {
      if (f !== null) {
        try { fs.closeSync(f); } catch (e) {}
      }
    }
  }

  private async confirm(): Promise<void> {
    if (this.saving) return;
    this.saving = true;
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      let path: string = '';
      try {
        if (this.pixelMap === null || this.imgW <= 0 || this.imgH <= 0) {
          throw new Error('NO_PIXEL');
        }
        const base: number = Math.max(this.vw / this.imgW, this.vh / this.imgH);
        const scale: number = base * this.zoom;
        const cw: number = Math.min(this.imgW, this.vw / scale);
        const ch: number = Math.min(this.imgH, this.vh / scale);
        const cx: number = this.imgW / 2 - this.px(this.tx) / scale;
        const cy: number = this.imgH / 2 - this.px(this.ty) / scale;
        const left: number = Math.max(0, Math.min(this.imgW - cw, cx - cw / 2));
        const top: number = Math.max(0, Math.min(this.imgH - ch, cy - ch / 2));
        const region: image.Region = {
          x: Math.round(left),
          y: Math.round(top),
          size: { width: Math.round(cw), height: Math.round(ch) }
        };
        console.info('juxia-crop region x=' + region.x + ' y=' + region.y +
          ' w=' + region.size.width + ' h=' + region.size.height +
          ' zoom=' + this.zoom.toFixed(2) + ' tx=' + this.tx.toFixed(1) +
          ' ty=' + this.ty.toFixed(1));
        const out = await this.pixelMap.createCroppedAndScaledPixelMap(
          region, this.vw / cw, this.vh / ch);
        path = await BackgroundService.savePixelMap(ctx, out, this.cropKey);
      } catch (e) {
        console.error('juxia-crop crop fail, fallback full image: ' + String(e));
        if (this.pixelMap !== null) {
          path = await BackgroundService.savePixelMap(ctx, this.pixelMap, this.cropKey);
        }
      }
      if (path.length === 0) {
        throw new Error('EMPTY_PATH');
      }
      Store.get().setBackgroundPath(this.cropKey, path);
      await Store.get().flush();
      const b = Store.get().data.settings.background;
      const keep: string[] = [b.light.path, b.dark.path, b.lightPlain.path, b.darkPlain.path]
        .filter((p: string) => p.length > 0);
      BackgroundService.cleanup(ctx, keep);
      UiState.get().bgSavedRev = UiState.get().bgSavedRev + 1;
      try {
        const st = fs.statSync(path);
        console.info('juxia-bg saved key=' + this.cropKey + ' path=' + path + ' size=' + st.size);
      } catch (e) {
        console.error('juxia-bg saved file missing ' + path);
      }
      this.getUIContext().getRouter().back();
    } catch (e) {
      console.error('juxia bg crop save fail', String(e));
      this.saving = false;
      try { this.getUIContext().getPromptAction().showToast({ message: '保存背景失败' }); } catch (e2) {}
    }
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Stack({ alignContent: Alignment.Center }) {
        Image(this.pixelMap !== null ? this.pixelMap : this.src)
          .id('bgCropImage')
          .width(this.pixelMap !== null ? this.dispW() : '100%')
          .height(this.pixelMap !== null ? this.dispH() : '100%')
          .objectFit(ImageFit.Cover)
          .translate({ x: this.tx, y: this.ty })
      }
      .width('100%')
      .height('100%')
      .clip(true)

      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Transparent)
        .onTouch((event: TouchEvent) => {
          this.handleTouch(event);
        })

      Column() {
        Text('背景预览')
          .fontFamily(FONT_SANS)
          .fontSize(13)
          .fontColor(this.t().ink)
          .backgroundColor(this.t().card)
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .borderRadius(999)

      }
      .margin({ bottom: 120 })

      if (this.saving) {
        Column({ space: 10 }) {
          LoadingProgress().width(34).height(34).color(this.t().sealInk)
          Text('正在应用…').fontSize(13).fontColor(this.t().ink)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#66000000')
      }

      Row({ space: 12 }) {
        Text('取消')
          .layoutWeight(1)
          .height(46)
          .textAlign(TextAlign.Center)
          .fontSize(14)
          .fontColor(this.t().ink)
          .backgroundColor(this.t().card)
          .borderRadius(14)
          .onClick(() => {
            this.getUIContext().getRouter().back();
          })
        Text(this.saving ? '保存中…' : '使用这张')
          .layoutWeight(1)
          .height(46)
          .textAlign(TextAlign.Center)
          .fontSize(14)
          .fontColor(this.t().bg)
          .backgroundColor(this.t().ink)
          .borderRadius(14)
          .onClick(() => {
            this.confirm();
          })
      }
      .width('88%')
      .constraintSize({ maxWidth: 440 })
      .margin({ bottom: 42 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.t().bg)
  }

  pageTransition(): void {
    PageTransitionEnter({ duration: 200, curve: Curve.EaseOut }).opacity(0)
    PageTransitionExit({ duration: 200, curve: Curve.EaseOut }).opacity(0)
  }
}
