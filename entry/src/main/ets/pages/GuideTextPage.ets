import { Tokens, getTokens, FONT_SANS } from '../theme/Theme';
import { FoldCover } from '../components/FoldCover';
import { UiState } from '../state/UiState';

const FULL_GUIDE: string = `这是一个越用越好用的栖息空间。你可以向树洞倾诉烦恼，完全本地，无云端；也可以把积极的能量储蓄在里面，在能量不足时提取使用；还可以尝试反省自身（省身板块可以在设置中关闭），从而在栖息中获得成长。

晴（写一句）：建议写“对自己说的一句鼓励”，储蓄自我能量
晴（抽一句）：可以抽“一件旧事”，完善心境
雨（写一句）：建议写“让自己难过的事”，倾诉树洞
雨（抽一句）：可以抽“让自己感觉好些的话”，汲取能量

省身（设置中可以关闭）：建议写“我发现了什么 + 下次怎么做”，反思进步
材料：建议只放让自己舒服的文字，详细格式见材料区的“？”，借力外界能量（材料不会直接参与抽签；先在句库收藏，并在设置 → 抽签来源中打开「句库收藏」，才会进入抽签范围）。
关联与备注：鼓励、旧事、句库三者可以互相关联，或者各自备注，留下注脚。
回信：抽到自己的话，或回访旧事时，可以回一句话。回信会独立收进「回信」，不是备注。
回忆与回访：收纳已经归档的文字；旧事按“已解决 / 已放下”分类，鼓励按“看起来很蠢 / 听腻了”分类；而且旧事可以设置回访，默认 14 天后轻轻问一次，继续打磨心境；鼓励归档后不再回访。

个性化：可调整界面（包括印章是否显示、字体大小）、外观（两套UI+自定义背景）、仪式感、抽签来源、应用名（应用内部显示的名字，也就是你给你的App起的名字）、称呼（应用对你的称呼）、启动（可设置启动显示自己喜欢的话，额外的能量）、省身和回访设置等
备份：记得定期备份；恢复会覆盖当前全部数据；没有云同步

隐私：数据只在本机加密保存，材料在应用私有目录；无账号、无广告、无云端统计，不申请网络权限；回访通知是本地提醒；备份由你主动导出！`;

@ComponentV2
export struct GuideTextOverlay {
  @Event onClose: () => void = () => {};
  @Local ui: UiState = UiState.get();
  @Local open: boolean = false;
  @Local ready: boolean = false;
  private timer: number = -1;
  private get skin(): string { return this.ui.skin; }
  private get dark(): boolean { return this.ui.dark; }
  private get safeTop(): number { return this.ui.safeTop; }
  private get safeBottom(): number { return this.ui.safeBottom; }

  private t(): Tokens {
    return getTokens(this.skin, this.dark);
  }

  aboutToDisappear(): void {
    if (this.timer >= 0) clearTimeout(this.timer);
  }

  private unfold(): void {
    if (this.open) return;
    this.open = true;
    this.timer = setTimeout(() => { this.ready = true; }, 900);
  }

  build() {
    Column() {
      if (!this.ready) {
        FoldCover({ open: this.open, hint: '点一下，展开完整文案', onUnfold: () => this.unfold() })
      } else {
        Row() {
          Text('新手指引完整文案')
            .fontFamily(FONT_SANS)
            .fontSize(17)
            .fontColor(this.t().ink)
          Blank()
          Text('返回')
            .fontFamily(FONT_SANS)
            .fontSize(13)
            .fontColor(this.t().inkSoft)
            .onClick(() => {
              this.onClose();
            })
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: this.safeTop + 10, bottom: 12 })
        .backgroundColor(this.ready ? this.t().bg : Color.Transparent)

        Scroll() {
          Text(FULL_GUIDE)
            .fontFamily(FONT_SANS)
            .fontSize(13.5)
            .lineHeight(25)
            .fontColor(this.t().ink)
            .width('100%')
            .padding({ left: 20, right: 20, top: 8, bottom: 40 + this.safeBottom })
        }
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .width('100%')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.ready ? this.t().bg : Color.Transparent)
  }

}
