// 句栖 · 背景图配置（与 Settings 一起持久化）
export class BgImageStyle {
  path: string = '';
  brightness: number = 1.0;
  blur: number = 0;
  scrim: number = 0.38;
}

export class BackgroundStyle {
  light: BgImageStyle = new BgImageStyle();
  dark: BgImageStyle = new BgImageStyle();
  lightClassic: BgImageStyle = new BgImageStyle();
  lightPlain: BgImageStyle = new BgImageStyle();
  darkClassic: BgImageStyle = new BgImageStyle();
  darkPlain: BgImageStyle = new BgImageStyle();
  glow: string = 'normal'; // 旧字段，保留兼容
  glowValue: number = 100; // 0–100
  dither: boolean = true;
  grain: string = 'normal'; // 旧字段，保留兼容
  grainValue: number = 100; // 0–100
}
