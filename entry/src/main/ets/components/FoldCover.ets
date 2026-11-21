import { Tokens, getTokens, FONT_SERIF, FONT_SANS } from '../theme/Theme';
import { UiState } from '../state/UiState';
import { scalePath, pathScale } from '../utils/PathScale';

const FLAP_CMDS: string[] = [
  'M 0 0 L 220 0 L 110 110 Z',
  'M 220 0 L 220 220 L 110 110 Z',
  'M 0 220 L 220 220 L 110 110 Z',
  'M 0 0 L 0 220 L 110 110 Z'
];

@ComponentV2
export struct FoldCover {
  @Param open: boolean = false;
  @Param hint: string = '点一下，展开';
  @Event onUnfold: () => void = () => {};
  @Local ui: UiState = UiState.get();

  private t(): Tokens {
    return getTokens(this.ui.skin, this.ui.dark);
  }

  private flapFill(index: number): string {
    if (this.ui.skin === 'plain') {
      if (this.ui.dark) {
        const p: string[] = ['#332E26', '#2B261F', '#373229', '#302B23'];
        return p[index];
      }
      return this.t().cardSolid;
    }
    if (this.ui.dark) {
      const c: string[] = ['#2E2E29', '#272722', '#31312B', '#2A2A25'];
      return c[index];
    }
    const cols: string[] = ['#fdf9ee', '#f9f5ea', '#f7f2e6', '#fbf6ec'];
    return cols[index];
  }

  private packetFill(): string {
    if (this.ui.dark) return this.ui.skin === 'plain' ? '#2F2A22' : '#2B2B26';
    return this.ui.skin === 'plain' ? this.t().cardSolid : '#fdf9ee';
  }

  @Builder
  Flap(index: number) {
    Shape() {
      Path()
        .commands(scalePath(FLAP_CMDS[index], pathScale(220, 220)))
        .fill(this.flapFill(index))
        .stroke(Color.Transparent)
        .strokeWidth(0)
    }
    .width(`${this.getUIContext().vp2px(220)}px`)
    .height(`${this.getUIContext().vp2px(220)}px`)
    .rotate({
      x: (index === 0 || index === 2) ? 1 : 0,
      y: (index === 1 || index === 3) ? 1 : 0,
      z: 0,
      angle: this.open ? (index === 2 || index === 1 ? -178 : 178) : 0,
      centerX: index === 1 ? 220 : (index === 3 ? 0 : 110),
      centerY: index === 0 ? 0 : (index === 2 ? 220 : 110),
      perspective: 900
    })
    .animation({ duration: 850, delay: index * 80, curve: Curve.EaseInOut })
  }

  build() {
    Column({ space: 22 }) {
      Stack() {
        Column()
          .width(220)
          .height(220)
          .borderRadius(4)
          .backgroundColor(this.packetFill())
          .onClick(() => this.onUnfold())
        ForEach([0, 1, 2, 3], (i: number) => {
          Column() { this.Flap(i) }
            .width(220)
            .height(220)
            .hitTestBehavior(HitTestMode.Transparent)
        }, (i: number) => `flap-${i}`)
        if (!this.open) {
          Text('展开')
            .fontFamily(FONT_SERIF)
            .fontSize(14)
            .letterSpacing(8)
            .fontColor(this.t().inkSoft)
        }
      }
      .width(220)
      .height(220)
      .alignContent(Alignment.Center)
      if (!this.open) {
        Text(this.hint)
          .fontFamily(FONT_SANS)
          .fontSize(12)
          .letterSpacing(2)
          .fontColor(this.t().inkSoft)
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(Color.Transparent)
  }
}
