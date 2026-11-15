// 句栖 · 背景层（纸基 / 自定义照片 / 光晕 / 纹理）
import { Store } from '../data/Store';
import { BackgroundStyle, BgImageStyle } from '../model/BackgroundStyle';
import { Tokens, getTokens } from '../theme/Theme';

@ComponentV2
export struct BackgroundStage {
  @Param skin: string = 'classic';
  @Param dark: boolean = false;

  private t(): Tokens {
    return getTokens(this.skin, this.dark);
  }

  private bg(): BackgroundStyle {
    return Store.get().data.settings.background;
  }

  private style(): BgImageStyle {
    const b = this.bg();
    if (this.dark) {
      if (this.skin === 'plain' && b.darkPlain.path.length > 0) return b.darkPlain;
      if (this.skin !== 'plain' && b.darkClassic.path.length > 0) return b.darkClassic;
      return b.dark;
    }
    if (this.skin === 'plain' && b.lightPlain.path.length > 0) return b.lightPlain;
    if (this.skin !== 'plain' && b.lightClassic.path.length > 0) return b.lightClassic;
    return b.light;
  }

  private hasImage(): boolean {
    return this.style().path.length > 0;
  }

  private grainOpacity(): number {
    const g: string = this.bg().grain;
    if (g === 'off') return 0;
    if (g === 'weak') return this.skin === 'plain' ? 0.1 : 0.24;
    return this.skin === 'plain' ? 0.22 : 0.5;
  }

  private glowOn(): boolean {
    return this.bg().glow !== 'off';
  }

  private glowAlpha(): number {
    return this.bg().glow === 'normal' ? 1 : 0.55;
  }

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.dark ? '#14110b' : '#F6F0E3')

      if (this.hasImage()) {
        Image(this.style().path)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .brightness(this.style().brightness)
          .blur(this.style().blur)
      } else {
        Column()
          .width('100%')
          .height('100%')
          .linearGradient({
            angle: 180,
            colors: [[this.dark ? '#201c15' : '#f3eddc', 0.0],
              [this.dark ? '#14110b' : '#e9e0cb', 1.0]]
          })
        if (this.skin !== 'plain' && this.glowOn()) {
          Column()
            .width('100%')
            .height('100%')
            .radialGradient({
              center: ['74%', '4%'],
              radius: '78%',
              colors: [[this.dark ? '#571e1834' : '#ccfff3c4', 0.0], ['#00FFFFFF', 1.0]]
            })
            .opacity(this.glowAlpha())
          Column()
            .width('100%')
            .height('100%')
            .radialGradient({
              center: ['8%', '92%'],
              radius: '70%',
              colors: [[this.dark ? '#5c36422e' : '#8ce4e9c5', 0.0], ['#00FFFFFF', 1.0]]
            })
            .opacity(this.glowAlpha())
          Column()
            .width('100%')
            .height('100%')
            .radialGradient({
              center: ['92%', '84%'],
              radius: '68%',
              colors: [[this.dark ? '#5754402e' : '#80d5c2ad', 0.0], ['#00FFFFFF', 1.0]]
            })
            .opacity(this.glowAlpha())
        }
      }

      if (this.hasImage()) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(this.dark ? '#000000' : '#F6F0E3')
          .opacity(this.style().scrim)
      }

      if (this.dark && this.bg().dither) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundImage($r('app.media.dither'), ImageRepeat.XY)
          .backgroundImageSize({ width: 4, height: 4 })
      }

      if (this.grainOpacity() > 0) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundImage(this.dark ? $r('app.media.grain_night') : $r('app.media.grain'),
            this.dark ? ImageRepeat.NoRepeat : ImageRepeat.XY)
          .backgroundImageSize({ width: this.dark ? '100%' : 140, height: this.dark ? '100%' : 140 })
          .opacity(this.grainOpacity())
      }
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.None)
  }
}
