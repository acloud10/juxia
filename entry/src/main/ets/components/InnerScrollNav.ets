// 内层滚动导航：长按到顶 / 到底
import { Tokens, getTokens, FONT_SANS } from '../theme/Theme';
import { UiState } from '../state/UiState';

@ComponentV2
export struct InnerScrollNav {
  @Local ui: UiState = UiState.get();
  @Event onTop: () => void = () => {};
  @Event onBottom: () => void = () => {};

  private get dark(): boolean { return this.ui.dark; }
  private get skin(): string { return this.ui.skin; }

  private t(): Tokens {
    return getTokens(this.skin, this.dark);
  }

  @Builder
  NavButton(label: string, action: () => void) {
    Text(label)
      .fontFamily(FONT_SANS)
      .fontSize(11)
      .fontColor(this.t().inkSoft)
      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      .backgroundColor(this.t().card)
      .border({ width: 1, color: this.t().line })
      .borderRadius(999)
      .gesture(LongPressGesture({ repeat: false, duration: 500 }).onAction(() => {
        action();
      }))
  }

  build() {
    Row({ space: 8 }) {
      this.NavButton('↑ 长按到顶', () => this.onTop())
      this.NavButton('↓ 长按到底', () => this.onBottom())
    }
    .width('100%')
    .justifyContent(FlexAlign.End)
    .padding({ top: 4, bottom: 2 })
  }
}
