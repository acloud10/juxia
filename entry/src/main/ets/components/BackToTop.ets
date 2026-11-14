// 长按回顶部，避免普通点击误触
import { Tokens, getTokens, FONT_SANS } from '../theme/Theme';
import { UiState } from '../state/UiState';

@ComponentV2
export struct BackToTop {
  @Local ui: UiState = UiState.get();
  @Event onJump: () => void = () => {};

  private get dark(): boolean { return this.ui.dark; }
  private get skin(): string { return this.ui.skin; }

  private t(): Tokens {
    return getTokens(this.skin, this.dark);
  }

  build() {
    Column({ space: 0 }) {
      Text('↑')
        .fontFamily(FONT_SANS)
        .fontSize(18)
        .fontColor(this.t().ink)
      Text('长按')
        .fontFamily(FONT_SANS)
        .fontSize(9)
        .fontColor(this.t().inkSoft)
    }
    .width(50)
    .height(50)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.t().cardSolid)
    .borderRadius(24)
    .border({ width: 1, color: this.t().line })
    .shadow({ radius: 12, color: this.t().shadowLift, offsetY: 4 })
    .position({ right: 16, bottom: 260 })
    .zIndex(20)
    .accessibilityText('长按回到顶部')
    .gesture(LongPressGesture({ repeat: false, duration: 500 }).onAction(() => {
      this.onJump();
    }))
  }
}
