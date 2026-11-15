// 句栖 · 背景图裁剪：全屏预览，可见区域就是最终背景
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
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

  private t(): Tokens {
    return getTokens('classic', this.dark);
  }

  aboutToAppear(): void {
    this.src = AppStorage.get<string>('bgCropSrc') ?? '';
    this.cropKey = AppStorage.get<string>('bgCropKey') ?? 'light';
    let ok: boolean = false;
    try {
      ok = this.src.length > 0 && fs.accessSync(this.src);
    } catch (e) {
      ok = false;
    }
    if (!ok) {
      try {
        this.getUIContext().getPromptAction().showToast({ message: '没有选到图片' });
      } catch (e) {
      }
      this.getUIContext().getRouter().back();
    }
  }

  private async confirm(): Promise<void> {
    if (this.saving) return;
    this.saving = true;
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const pm = await this.getUIContext().getComponentSnapshot().get('bgCropImage');
      const path: string = await BackgroundService.savePixelMap(ctx, pm, this.cropKey);
      Store.get().setBackgroundPath(this.cropKey, path);
      try { fs.unlinkSync(this.src); } catch (e) {}
      this.getUIContext().getRouter().back();
    } catch (e) {
      this.saving = false;
      try { this.getUIContext().getPromptAction().showToast({ message: '保存背景失败' }); } catch (e2) {}
    }
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Image(this.src)
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
            try { fs.unlinkSync(this.src); } catch (e) {}
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
    .backgroundColor(this.dark ? '#14110b' : '#F6F0E3')
  }
}
