// 句栖 · 新手指引：折纸 → 一屏说明 → 晴雨选择 → 分支演示 → 真实第一句
import { Tokens, getTokens, FONT_SERIF, FONT_SANS } from '../theme/Theme';
import { UiState } from '../state/UiState';
import { Store } from '../data/Store';
import { FoldCover } from './FoldCover';

const SUN_SAMPLE: string = '今天已经做得够好了。\n慢一点，也没有关系。';
const RAIN_SAMPLE: string = '那件事，我还是会想起。';

@ComponentV2
export struct WelcomeGuide {
  @Param replay: boolean = false;
  @Param startStage: string = '';
  @Param startBranch: string = 'sun';
  @Event onDone: () => void = () => {};
  @Event onWriteAnother: () => void = () => {};
  @Event onGoMine: () => void = () => {};
  @Event onSkip: () => void = () => {};
  @Event onBeginDemo: () => void = () => {};

  @Local ui: UiState = UiState.get();
  @Local stage: string = 'fold';
  @Local open: boolean = false;
  @Local entered: boolean = false;
  @Local branch: string = 'sun';
  @Local writeText: string = '';
  @Local writeBusy: boolean = false;
  private timer: number = -1;

  private get dark(): boolean { return this.ui.dark; }
  private get skin(): string { return this.ui.skin; }
  private t(): Tokens { return getTokens(this.skin, this.dark); }

  aboutToAppear(): void {
    if (this.startStage.length > 0) {
      this.branch = this.startBranch;
      this.stage = this.startStage;
      this.entered = true;
      return;
    }
    this.timer = setTimeout(() => { this.entered = true; }, 40);
  }

  aboutToDisappear(): void {
    if (this.timer >= 0) clearTimeout(this.timer);
  }

  private unfold(): void {
    if (this.open) return;
    this.open = true;
    this.timer = setTimeout(() => { this.stage = 'intro'; }, 900);
  }

  private startWrite(): void {
    this.writeText = '';
    this.stage = 'write';
  }

  private saveFirst(): void {
    const text = this.writeText.trim();
    if (text.length === 0) {
      this.toast('先写一句。');
      return;
    }
    if (this.writeBusy) return;
    this.writeBusy = true;
    try {
      const st = Store.get();
      st.data.day.mood = this.branch === 'rain' ? 'bad' : 'good';
      st.addOwn(this.branch === 'rain' ? 'wound' : 'encourage', text);
      this.stage = 'done';
    } catch (e) {
      this.toast('没有保存成功，再试一次。');
    } finally {
      this.writeBusy = false;
    }
  }

  private toast(msg: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: msg });
    } catch (e) {
    }
  }

  private guideScrim(): string {
    if (this.dark) return this.skin === 'plain' ? '#F21B1A17' : '#F21C1915';
    return this.skin === 'plain' ? '#F2F5EFE2' : '#F2F6F0E3';
  }

  @Builder
  FoldStage() {
    FoldCover({
      open: this.open,
      hint: '点一下，展开',
      onUnfold: () => this.unfold()
    })
  }

  @Builder
  GuideButton(label: string, primary: boolean, action: () => void) {
    Text(label)
      .fontFamily(FONT_SANS)
      .fontSize(14)
      .letterSpacing(1)
      .fontColor(primary ? this.t().bg : this.t().seal)
      .textAlign(TextAlign.Center)
      .width('100%')
      .padding({ top: 12, bottom: 12 })
      .borderRadius(this.t().radiusBtn)
      .backgroundColor(primary ? this.t().ink : this.t().card)
      .border({ width: 1, color: primary ? this.t().ink : this.t().line })
      .onClick(action)
  }

  @Builder
  IntroStage() {
    Column() {
      Row() {
        Text('新手指引')
          .fontFamily(FONT_SERIF)
          .fontSize(30)
          .letterSpacing(5)
          .fontColor(this.t().ink)
        Blank()
        if (this.replay) {
          Text('跳过')
            .fontFamily(FONT_SANS)
            .fontSize(12)
            .fontColor(this.t().inkSoft)
            .onClick(() => this.onSkip())
        }
      }
      .width('100%')
      .padding({ top: 34, bottom: 6 })

      Text('（完整指引文案可见：设置 → 关于 → 新手指引完整文案）')
        .fontFamily(FONT_SANS)
        .fontSize(11.5)
        .lineHeight(20)
        .fontColor(this.t().inkSoft)
        .width('100%')

      Scroll() {
        Column({ space: 12 }) {
          Text('这是一个越用越好用的栖息空间。')
            .fontFamily(FONT_SANS)
            .fontSize(15)
            .lineHeight(28)
            .fontColor(this.t().inkStrong)
            .width('100%')

          Text('晴，写一句对自己的鼓励，储蓄能量；\n抽到一件旧事，完善心境。\n雨，把难过放进树洞，倾诉烦恼；\n抽到让自己感觉好些的话，汲取能量。')
            .fontFamily(FONT_SANS)
            .fontSize(13.5)
            .lineHeight(25)
            .fontColor(this.t().ink)
            .width('100%')

          Text('写下的句子会被收好。\n抽到它时，可以回一句话。\n备注随时可以留下注脚。\n回信会独立收进「回信」，不是备注。')
            .fontFamily(FONT_SANS)
            .fontSize(13.5)
            .lineHeight(25)
            .fontColor(this.t().ink)
            .width('100%')

          Text('旧事归档后，可以约一次回访，继续打磨心境。\n鼓励归档后，不再回访。')
            .fontFamily(FONT_SANS)
            .fontSize(13.5)
            .lineHeight(25)
            .fontColor(this.t().ink)
            .width('100%')

          Text('鼓励、旧事、句库可以互相关联，各自留下注脚。')
            .fontFamily(FONT_SANS)
            .fontSize(13.5)
            .lineHeight(25)
            .fontColor(this.t().ink)
            .width('100%')

          Text('数据只在本机加密保存。\n无账号，无广告，无云端统计，不申请网络权限。\n记得备份，没有云同步。')
            .fontFamily(FONT_SANS)
            .fontSize(12.5)
            .lineHeight(23)
            .fontColor(this.t().inkSoft)
            .width('100%')
        }
        .width('100%')
        .padding({ top: 12, bottom: 12 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)

      this.GuideButton('先看晴雨两条线', true, () => this.onBeginDemo())
    }
    .width('100%')
    .height('100%')
    .padding({ left: 22, right: 22, top: 8, bottom: 22 })
  }

  @Builder
  WriteStage() {
    Column() {
      Row() {
        Text('写我的第一句')
          .fontFamily(FONT_SERIF)
          .fontSize(24)
          .letterSpacing(3)
          .fontColor(this.t().ink)
        Blank()
      }
      .width('100%')
      .padding({ top: 34, bottom: 6 })

      Text(this.branch === 'rain' ? '雨 · 旧事' : '晴 · 鼓励')
        .fontFamily(FONT_SANS)
        .fontSize(12)
        .fontColor(this.t().seal)
        .width('100%')
        .margin({ bottom: 12 })

      TextArea({
        text: this.writeText,
        placeholder: this.branch === 'rain' ? '把难过放进树洞……' : '写一句对自己的鼓励……'
      })
        .height(170)
        .fontSize(17)
        .fontFamily(FONT_SERIF)
        .fontColor(this.t().ink)
        .backgroundColor(this.t().card)
        .borderRadius(this.t().radiusCard)
        .border({ width: 1, color: this.t().line })
        .padding(14)
        .onChange((v: string) => { this.writeText = v; })

      Blank()

      this.GuideButton('收好', true, () => this.saveFirst())
    }
    .width('100%')
    .height('100%')
    .padding({ left: 22, right: 22, top: 8, bottom: 22 })
  }

  @Builder
  DoneStage() {
    Column() {
      Blank()
      Text('这句话已经收好了')
        .fontFamily(FONT_SERIF)
        .fontSize(25)
        .letterSpacing(3)
        .fontColor(this.t().inkStrong)
        .width('100%')
        .textAlign(TextAlign.Center)

      Text('你可以再写一句，\n也可以去「我的」看看它。\n\n想让它更像你的空间，\n可以在设置里给它起个名字，\n或在设置里告诉我怎么称呼你。\n\n相信这个栖息的空间，你会越用越顺手的。')
        .fontFamily(FONT_SANS)
        .fontSize(13.5)
        .lineHeight(26)
        .fontColor(this.t().ink)
        .textAlign(TextAlign.Center)
        .width('100%')
        .margin({ top: 18 })

      Blank()

      Row({ space: 10 }) {
        this.GuideButton('再写一句', false, () => this.onWriteAnother())
        this.GuideButton('去「我的」看看', true, () => this.onGoMine())
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 22, right: 22, top: 20, bottom: 26 })
  }

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.stage === 'fold' && !this.open ? '#00000000' : this.guideScrim())
        .animation({ duration: 500, curve: Curve.EaseOut })
      if (this.stage === 'fold') {
        this.FoldStage()
      } else if (this.stage === 'intro') {
        this.IntroStage()
      } else if (this.stage === 'write') {
        this.WriteStage()
      } else {
        this.DoneStage()
      }
    }
    .width('100%')
    .height('100%')
  }
}
