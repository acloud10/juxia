// 句栖 · 全局外观组件：顶栏、导航、晴雨图标
import { Tokens, getTokens, FONT_SERIF } from '../theme/Theme';
import { weekdayCN } from '../model/Types';
import { scalePath, pathScale } from '../utils/PathScale';
import { UiState } from '../state/UiState';

@ComponentV2
export struct TopBar {
  @Local ui: UiState = UiState.get();
  private get skin(): string { return this.ui.skin; }
  private get dark(): boolean { return this.ui.dark; }
  private get appName(): string { return this.ui.appName; }
  private get dayCount(): number { return this.ui.dayCount; }
  private get showDays(): boolean { return this.ui.showDays; }

  private t(): Tokens {
    return getTokens(this.skin, this.dark);
  }

  private dateText(): string {
    const d = new Date();
    return `${d.getMonth() + 1}月${d.getDate()}日 · 星期${weekdayCN(d)}`;
  }

  @Builder
  SealBadge() {
    Stack() {
      Column() {
        Text(this.appName.slice(0, 1))
          .fontSize(15)
          .fontColor(this.t().sealInk)
          .fontFamily(FONT_SERIF)
          .fontWeight(FontWeight.Medium)
          .lineHeight(16)
        Text(this.appName.slice(1, 2))
          .fontSize(15)
          .fontColor(this.t().sealInk)
          .fontFamily(FONT_SERIF)
          .fontWeight(FontWeight.Medium)
          .lineHeight(16)
      }
      .justifyContent(FlexAlign.Center)

      Column()
        .width(33)
        .height(33)
        .borderRadius(6.5)
        .border({ width: 1.2, color: '#8cfdf6ea' })
    }
    .width(40)
    .height(40)
    .borderRadius(10)
    .linearGradient({
      angle: 150,
      colors: [['#c45155', 0.0], ['#b8434a', 0.58], ['#a83b42', 1.0]]
    })
    .shadow({ radius: 7, color: '#3d963237', offsetY: 2 })
    .rotate({ angle: -1.2 })
  }

  build() {
    Row({ space: 12 }) {
      if (this.skin !== 'plain') {
        this.SealBadge()
      }
      Column({ space: 3 }) {
        Text(this.appName)
          .fontFamily(FONT_SERIF)
          .fontSize(this.skin === 'plain' ? 22 : 24)
          .fontWeight(FontWeight.Medium)
          .letterSpacing(this.skin === 'plain' ? 10 : 7)
          .fontColor(this.t().inkStrong)
      }
      .alignItems(HorizontalAlign.Start)

      Blank()

      Column({ space: 4 }) {
        Text(this.dateText())
          .fontSize(10.5)
          .letterSpacing(2.4)
          .fontColor(this.t().inkSoft)
        if (this.showDays) {
          Text(`相伴第 ${this.dayCount} 天`)
            .fontSize(10.5)
            .letterSpacing(2.4)
            .fontColor(this.t().inkSoft)
        }
      }
      .alignItems(HorizontalAlign.End)
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 26, bottom: 18 })
  }
}

@ComponentV2
export struct TabIcon {
  @Param index: number = 0;
  @Param color: string = '#666257';

  private commands(): string {
    if (this.index === 0) {
      return 'M 16.2 12 A 4.2 4.2 0 1 1 7.8 12 A 4.2 4.2 0 1 1 16.2 12 Z ' +
        'M 12 3 L 12 5.4 M 12 18.6 L 12 21 M 3 12 L 5.4 12 M 18.6 12 L 21 12 ' +
        'M 5.8 5.8 L 7.5 7.5 M 16.5 16.5 L 18.2 18.2 M 18.2 5.8 L 16.5 7.5 M 7.5 16.5 L 5.8 18.2';
    }
    if (this.index === 1) {
      return 'M 5 5.5 L 19 5.5 M 5 12 L 19 12 M 5 18.5 L 14 18.5';
    }
    if (this.index === 2) {
      return 'M 4.5 19 L 4.5 6.8 A 1.8 1.8 0 0 1 6.3 5 L 19.5 5 L 19.5 17.6 ' +
        'L 6.3 17.6 A 1.8 1.8 0 0 0 4.5 19 Z M 4.5 19 A 1.8 1.8 0 0 0 6.3 20.6 L 19.5 20.6';
    }
    if (this.index === 3) {
      return 'M 4 8.5 L 20 8.5 L 20 18.5 A 1.5 1.5 0 0 1 18.5 20 L 5.5 20 ' +
        'A 1.5 1.5 0 0 1 4 18.5 Z M 3 4.5 L 21 4.5 L 21 8.5 L 3 8.5 Z M 10 12 L 14 12';
    }
    return 'M 4 7 L 14 7 M 18 7 L 20 7 M 4 17 L 8 17 M 12 17 L 20 17 ' +
      'M 18.2 7 A 2.2 2.2 0 1 1 13.8 7 A 2.2 2.2 0 1 1 18.2 7 Z ' +
      'M 12.2 17 A 2.2 2.2 0 1 1 7.8 17 A 2.2 2.2 0 1 1 12.2 17 Z';
  }

  build() {
    Shape() {
      Path()
        .commands(scalePath(this.commands(), pathScale(19, 24)))
        .fill(Color.Transparent)
        .stroke(this.color)
        .strokeWidth(1.3)
        .strokeLineCap(LineCapStyle.Round)
        .strokeLineJoin(LineJoinStyle.Round)
    }
    .width(`${this.getUIContext().vp2px(19)}px`)
    .height(`${this.getUIContext().vp2px(19)}px`)
  }
}

// 两套晴雨图标：经典 24 网格 / 朴素 48 网格
@ComponentV2
export struct MoodIcon {
  @Param kind: string = 'good';
  @Param plain: boolean = false;
  @Param color: string = '#666257';

  private commands(): string {
    if (this.plain) {
      if (this.kind === 'good') {
        return 'M 16 24 A 8 8 0 1 1 32 24 A 8 8 0 1 1 16 24 Z ' +
          'M 37 24 L 42 24 M 33.2 14.8 L 36.7 11.3 M 24 11 L 24 6 M 14.8 14.8 L 11.3 11.3 ' +
          'M 11 24 L 6 24 M 14.8 33.2 L 11.3 36.7 M 24 37 L 24 42 M 33.2 33.2 L 36.7 36.7';
      }
      return 'M 9 15 Q 13 9 21 10 Q 24 3 33 6 Q 41 8 39 15 ' +
        'M 15 24 L 12 32 M 25 24 L 22 32 M 35 24 L 32 32';
    }
    if (this.kind === 'good') {
      return 'M 8 13 A 4 4 0 1 1 16 13 A 4 4 0 1 1 8 13 Z ' +
        'M 12 4 L 12 6.5 M 5 13 L 2.5 13 M 21.5 13 L 19 13 ' +
        'M 6.3 7.3 L 4.5 5.5 M 17.7 7.3 L 19.5 5.5 M 4 20 L 20 20';
    }
    return 'M 18 10 A 6 6 0 0 0 6.5 8.5 A 4.5 4.5 0 0 0 7 17.5 L 18 17.5 A 3.5 3.5 0 0 0 18 10 Z ' +
      'M 8 20 L 9 22 M 12 20 L 13 22 M 16 20 L 17 22';
  }

  private iconSize(): number {
    return this.plain ? 26 : 22;
  }

  build() {
    Shape() {
      Path()
        .commands(scalePath(this.commands(), pathScale(this.iconSize(), this.plain ? 48 : 24)))
        .fill(Color.Transparent)
        .stroke(this.color)
        .strokeWidth(this.plain ? 1.6 : 1.3)
        .strokeLineCap(LineCapStyle.Round)
        .strokeLineJoin(LineJoinStyle.Round)
    }
    .width(`${this.getUIContext().vp2px(this.iconSize())}px`)
    .height(`${this.getUIContext().vp2px(this.iconSize())}px`)
  }
}


