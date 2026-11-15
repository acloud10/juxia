// 句栖 · 背景图裁剪：全屏预览，可见区域就是最终背景
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { BackgroundService } from '../services/BackgroundService';
import { Store } from '../data/Store';
import { Tokens, getTokens, FONT_SANS } from '../theme/Theme';

@Entry
@ComponentV2
struct BackgroundCropPage {
  @Local src: string = '';
  @Local cropKey: string = 'light';
  @Local zoom: number = 1;
  @Local tx: number = 0;
  @Local ty: number = 0;
  @Local saving: boolean = false;
  @Local dark: boolean = false;
  @Local skin: string = 'classic';
  @Local pixelMap: image.PixelMap | null = null;

  private t(): Tokens {
    return getTokens(this.skin, this.dark);
  }

  aboutToAppear(): void {
    this.src = AppStorage.get<string>('bgCropSrc') ?? '';
    this.cropKey = AppStorage.get<string>('bgCropKey') ?? 'light';
    this.skin = AppStorage.get<string>('bgCropSkin') ?? 'classic';
    this.dark = AppStorage.get<boolean>('bgCropDark') ?? false;
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

  private async loadImage(): Promise<void> {
    let f: fs.File | null = null;
    try {
      f = fs.openSync(this.src, fs.OpenMode.READ_ONLY);
      const src = image.createImageSource(f.fd);
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
        const pm = await this.getUIContext().getComponentSnapshot().get('bgCropImage');
        path = await BackgroundService.savePixelMap(ctx, pm, this.cropKey);
      } catch (e) {
        if (this.pixelMap !== null) {
          path = await BackgroundService.savePixelMap(ctx, this.pixelMap, this.cropKey);
        }
      }
      if (path.length === 0) {
        throw new Error('EMPTY_PATH');
      }
      Store.get().setBackgroundPath(this.cropKey, path);
      this.getUIContext().getRouter().back();
    } catch (e) {
      console.error('juxia bg crop save fail', String(e));
      this.saving = false;
      try { this.getUIContext().getPromptAction().showToast({ message: '保存背景失败' }); } catch (e2) {}
    }
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Image(this.pixelMap !== null ? this.pixelMap : this.src)
        .id('bgCropImage')
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
        .scale({ x: this.zoom, y: this.zoom })
        .translate({ x: this.tx, y: this.ty })
        .gesture(
          GestureGroup(GestureMode.Parallel,
            PinchGesture()
              .onActionUpdate((e: GestureEvent) => {
                this.zoom = Math.max(1, Math.min(4, this.zoom * e.scale));
              }),
            PanGesture()
              .onActionUpdate((e: GestureEvent) => {
                this.tx += e.offsetX;
                this.ty += e.offsetY;
              })
          )
        )

      Column() {
        Text('背景预览')
          .fontFamily(FONT_SANS)
          .fontSize(13)
          .fontColor(this.t().ink)
          .backgroundColor(this.t().card)
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .borderRadius(999)
        Text('双指缩放 · 单指拖动')
          .fontFamily(FONT_SANS)
          .fontSize(11)
          .fontColor(this.t().inkSoft)
          .margin({ top: 6 })
      }
      .margin({ bottom: 120 })

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
