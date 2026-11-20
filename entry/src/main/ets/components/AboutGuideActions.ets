import { common } from '@kit.AbilityKit';
import { Tokens, getTokens, FONT_SANS } from '../theme/Theme';
import { UiState } from '../state/UiState';
import { ReviewService } from '../services/ReviewService';

@ComponentV2
export struct AboutGuideActions {
  @Local ui: UiState = UiState.get();
  @Local reviewBusy: boolean = false;

  private t(): Tokens {
    return getTokens(this.ui.skin, this.ui.dark);
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (e) {
    }
  }

  private openReview(): void {
    if (this.reviewBusy) return;
    this.reviewBusy = true;
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    ReviewService.open(ctx, (message: string) => this.toast(message));
    setTimeout(() => { this.reviewBusy = false; }, 600);
  }

  @Builder
  LinkRow(label: string, value: string, action: () => void) {
    Row() {
      Text(label)
        .fontFamily(FONT_SANS)
        .fontSize(12)
        .fontColor(this.t().seal)
      Blank()
      Text(value)
        .fontFamily(FONT_SANS)
        .fontSize(12)
        .fontColor(this.t().seal)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding({ top: 6, bottom: 6 })
    .onClick(action)
  }

  build() {
    Column({ space: 2 }) {
      this.LinkRow('新手指引完整文案', '›', () => {
        this.getUIContext().getRouter().pushUrl({ url: 'pages/GuideTextPage' }).catch(() => {});
      })
      Row() {
        Column({ space: 2 }) {
          Text('评价句栖')
            .fontFamily(FONT_SANS)
            .fontSize(13.5)
            .fontColor(this.t().seal)
          Text('如果它陪到过你，可以留一句真实评价')
            .fontFamily(FONT_SANS)
            .fontSize(12.5)
            .lineHeight(20)
            .fontColor(this.t().inkSoft)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Text('›')
          .fontFamily(FONT_SANS)
          .fontSize(16)
          .margin({ top: 1 })
          .fontColor(this.t().seal)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      .padding({ top: 8, bottom: 4 })
      .onClick(() => this.openReview())
    }
    .width('100%')
  }
}
