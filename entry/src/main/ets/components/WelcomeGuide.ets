// 句栖 · 新手指引：折纸展开 → 使用说明
import { Tokens, getTokens, FONT_SERIF, FONT_SANS } from '../theme/Theme';
import { UiState } from '../state/UiState';
import { scalePath, pathScale } from '../utils/PathScale';

const FLAP_CMDS: string[] = [
  'M 0 0 L 220 0 L 110 110 Z',
  'M 220 0 L 220 220 L 110 110 Z',
  'M 0 220 L 220 220 L 110 110 Z',
  'M 0 0 L 0 220 L 110 110 Z'
];

const GUIDE_TEXT: string = `晴（写一句）：建议写“对自己说的一句鼓励”，储蓄自我能量
晴（抽一句）：可以抽“一件旧事”，完善心境
雨（写一句）：建议写“让自己难过的事”，倾诉树洞
雨（抽一句）：可以抽“让自己感觉好些的话”，汲取能量

省身（设置中可以关闭）：建议写“我发现了什么 + 下次怎么做”，反思进步
材料：建议只放让自己舒服的文字，详细格式见材料区的“？”，借力外界能量
关联与备注：鼓励、旧事、句库三者可以互相关联，或者各自备注，留下注脚。
回忆与回访：收纳已经归档的文字；旧事按“已解决 / 已放下”分类，鼓励按“看起来很蠢 / 听腻了”分类；而且旧事可以设置回访，继续打磨心境。

个性化：可调整界面（包括印章是否显示、字体大小）、外观（两套UI）、仪式感、抽签来源、应用名（应用内部显示的名字，也就是你给你的App起的名字）、称呼（应用对你的称呼）、启动（可设置启动显示自己喜欢的话，额外的能量）、省身和回访设置等
备份：记得定期备份；恢复会覆盖当前全部数据；没有云同步

隐私：数据只在本机加密保存，材料在应用私有目录；无账号、无广告、无云端统计，不申请网络权限；回访通知是本地提醒；备份由你主动导出！`;

@ComponentV2
export struct WelcomeGuide {
  @Local ui: UiState = UiState.get();
  @Event onDone: () => void = () => {};
  @Local stage: string = 'fold'; // fold、guide
  @Local open: boolean = false;
  @Local entered: boolean = false;
  private timer: number = -1;

  private get dark(): boolean { return this.ui.dark; }
  private get skin(): string { return this.ui.skin; }

  private t(): Tokens {
    return getTokens(this.skin, this.dark);
  }

  aboutToAppear(): void {
    this.timer = setTimeout(() => {
      this.entered = true;
    }, 40);
  }

  aboutToDisappear(): void {
    if (this.timer >= 0) {
      clearTimeout(this.timer);
    }
  }

  private unfold(): void {
    if (this.open) return;
    this.open = true;
    this.timer = setTimeout(() => {
      this.stage = 'guide';
    }, 1100);
  }

  private flapFill(index: number): string {
    if (this.skin === 'plain') {
      return this.dark ? '#3a3327' : this.t().cardSolid;
    }
    const cols: string[] = ['#fdf9ee', '#f9f5ea', '#f7f2e6', '#fbf6ec'];
    return cols[index];
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

  @Builder
  FoldStage() {
    Column({ space: 22 }) {
      Stack() {
        Column()
          .width(220)
          .height(220)
          .borderRadius(4)
          .backgroundColor(this.skin === 'plain' ? (this.dark ? '#3a3327' : this.t().cardSolid) : '#fdf9ee')
          .border({ width: 1, color: this.dark ? '#44e9e4d5' : '#1a5a5032' })
          .shadow({ radius: 34, color: this.dark ? '#66000000' : '#3d5a5032', offsetY: 12 })

        this.Flap(0)
        this.Flap(1)
        this.Flap(2)
        this.Flap(3)

        Column()
          .width(1)
          .height(220)
          .backgroundColor(this.dark ? '#33e9e4d5' : '#175a5032')
          .opacity(this.open ? 0 : 1)
          .animation({ duration: 300 })
        Column()
          .width(220)
          .height(1)
          .backgroundColor(this.dark ? '#33e9e4d5' : '#175a5032')
          .opacity(this.open ? 0 : 1)
          .animation({ duration: 300 })

        Text('展开')
          .fontSize(14)
          .fontFamily(FONT_SERIF)
          .letterSpacing(8)
          .fontColor(this.skin === 'plain' ? this.t().inkSoft : '#6b5a5032')
          .opacity(this.open ? 0 : 1)
          .animation({ duration: 300 })
      }
      .width(220)
      .height(220)
      .onClick(() => {
        this.unfold();
      })

      Text('点一下，展开')
        .fontFamily(FONT_SANS)
        .fontSize(12)
        .letterSpacing(3)
        .fontColor(this.t().inkSoft)
        .opacity(this.open ? 0 : 1)
        .animation({ duration: 300 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .opacity(this.entered ? 1 : 0)
    .scale({ x: this.entered ? 1 : 0.88, y: this.entered ? 1 : 0.88 })
    .animation({ duration: 500, curve: Curve.EaseOut })
    .transition(TransitionEffect.OPACITY.animation({ duration: 220, curve: Curve.EaseOut }))
  }

  @Builder
  GuideStage() {
    Column() {
      Column({ space: 8 }) {
        Text('新手指引')
          .fontFamily(FONT_SERIF)
          .fontSize(32)
          .letterSpacing(6)
          .fontColor(this.t().inkStrong)
        Text('（建议耐心看完，对于日后大有助益哦！）')
          .fontFamily(FONT_SANS)
          .fontSize(13)
          .lineHeight(22)
          .fontColor(this.t().inkSoft)
          .textAlign(TextAlign.Center)
      }
      .width('100%')
      .padding({ top: 30, bottom: 14 })

      Scroll() {
        Text(GUIDE_TEXT)
          .fontFamily(FONT_SANS)
          .fontSize(13.5)
          .lineHeight(25)
          .fontColor(this.t().ink)
          .width('100%')
          .textAlign(TextAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
      .padding({ left: 24, right: 24 })

      Text('开始使用')
        .fontFamily(FONT_SANS)
        .fontSize(14)
        .letterSpacing(2)
        .fontColor(this.t().bg)
        .textAlign(TextAlign.Center)
        .width('100%')
        .padding({ top: 14, bottom: 14 })
        .backgroundColor(this.t().ink)
        .borderRadius(this.t().radiusBtn)
        .margin({ top: 16, bottom: 22 })
        .onClick(() => {
          this.onDone();
        })
    }
    .width('100%')
    .height('100%')
    .padding({
      left: 18,
      right: 18,
      top: this.ui.safeTop + 18,
      bottom: this.ui.safeBottom + 10
    })
    .backgroundColor(this.t().bg)
    .transition(TransitionEffect.OPACITY.animation({ duration: 220, curve: Curve.EaseOut }))
  }

  build() {
    Stack() {
      if (this.stage === 'fold') {
        this.FoldStage()
      } else {
        this.GuideStage()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.t().bg)
    .transition(TransitionEffect.OPACITY.animation({ duration: 220, curve: Curve.EaseOut }))
  }
}
