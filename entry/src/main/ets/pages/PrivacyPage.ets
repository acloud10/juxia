import { Tokens, getTokens, FONT_SERIF } from '../theme/Theme';
import { PRIVACY_TEXT } from './PrivacyText';
import { UiState } from '../state/UiState';

@Entry
@ComponentV2
struct PrivacyPage {
  @Local ui: UiState = UiState.get();
  private get skin(): string { return this.ui.skin; }
  private get dark(): boolean { return this.ui.dark; }
  private get safeTop(): number { return this.ui.safeTop; }
  private get safeBottom(): number { return this.ui.safeBottom; }

  private t(): Tokens {
    return getTokens(this.skin, this.dark);
  }

  build() {
    Column() {
      Row() {
        Text('隐私政策')
          .fontFamily(FONT_SERIF)
          .fontSize(18)
          .fontColor(this.t().ink)
        Blank()
        Text('返回')
          .fontSize(13)
          .fontColor(this.t().inkSoft)
          .onClick(() => {
            this.getUIContext().getRouter().back();
          })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: this.safeTop + 10, bottom: 12 })
      .backgroundColor(this.t().bg)

      Scroll() {
        Text(PRIVACY_TEXT)
          .fontSize(14)
          .lineHeight(24)
          .fontColor(this.t().ink)
          .width('100%')
          .padding({ left: 20, right: 20, top: 8, bottom: 40 + this.safeBottom })
      }
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.t().bg)
  }

  onBackPress(): boolean {
    this.getUIContext().getRouter().back();
    return true;
  }
}

