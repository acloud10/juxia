// 句栖 · 背景图配置（普通可序列化对象；刷新由 bgRev / UiState 驱动）
export class BgImageStyle {
  path: string = '';
  brightness: number = 1.0;
  blur: number = 0;
  scrim: number = 0;
  glowValue: number = 100;
  grainValue: number = 100;
  ditherValue: number = 100;

  constructor(glowValue: number = 100, grainValue: number = 100) {
    this.glowValue = glowValue;
    this.grainValue = grainValue;
  }

  static from(src: BgImageStyle | null | undefined, glowDefault: number, grainDefault: number): BgImageStyle {
    const x = new BgImageStyle(glowDefault, grainDefault);
    if (src === null || src === undefined) return x;
    x.path = src.path === undefined ? '' : src.path;
    x.brightness = src.brightness === undefined || isNaN(src.brightness) ? 1.0 : src.brightness;
    x.brightness = Math.max(0, Math.min(1.5, x.brightness));
    x.blur = src.blur === undefined || isNaN(src.blur) ? 0 : src.blur;
    x.blur = Math.max(0, Math.min(100, x.blur));
    x.scrim = src.scrim === undefined || isNaN(src.scrim) ? 0 : src.scrim;
    x.scrim = Math.max(0, Math.min(1, x.scrim));
    x.glowValue = src.glowValue === undefined || isNaN(src.glowValue) ? glowDefault : src.glowValue;
    x.glowValue = Math.max(0, Math.min(100, x.glowValue));
    x.grainValue = src.grainValue === undefined || isNaN(src.grainValue) ? grainDefault : src.grainValue;
    x.grainValue = Math.max(0, Math.min(150, x.grainValue));
    x.ditherValue = src.ditherValue === undefined || isNaN(src.ditherValue) ? 100 : src.ditherValue;
    x.ditherValue = Math.max(0, Math.min(100, x.ditherValue));
    return x;
  }
}

export class BackgroundStyle {
  light: BgImageStyle = new BgImageStyle(100, 0);
  dark: BgImageStyle = new BgImageStyle(100, 100);
  lightClassic: BgImageStyle = new BgImageStyle(100, 0);
  lightPlain: BgImageStyle = new BgImageStyle(0, 0);
  darkClassic: BgImageStyle = new BgImageStyle(100, 100);
  darkPlain: BgImageStyle = new BgImageStyle(100, 100);
  glow: string = 'normal';
  glowValue: number = 100;
  dither: boolean = true;
  ditherValue: number = 100;
  grain: string = 'normal';
  grainValue: number = 100;

  static from(src: BackgroundStyle | null | undefined): BackgroundStyle {
    const x = new BackgroundStyle();
    if (src === null || src === undefined) return x;
    x.light = BgImageStyle.from(src.light, 100, 0);
    x.dark = BgImageStyle.from(src.dark, 100, 100);
    x.lightClassic = BgImageStyle.from(src.lightClassic, 100, 0);
    x.lightPlain = BgImageStyle.from(src.lightPlain, 0, 0);
    x.darkClassic = BgImageStyle.from(src.darkClassic, 100, 100);
    x.darkPlain = BgImageStyle.from(src.darkPlain, 100, 100);
    x.glow = src.glow === undefined ? 'normal' : src.glow;
    if (x.glow !== 'off' && x.glow !== 'weak' && x.glow !== 'normal') x.glow = 'normal';
    x.glowValue = src.glowValue === undefined || isNaN(src.glowValue) ? 100 : src.glowValue;
    x.glowValue = Math.max(0, Math.min(100, x.glowValue));
    x.dither = src.dither === undefined ? true : src.dither;
    x.ditherValue = src.ditherValue === undefined || isNaN(src.ditherValue)
      ? (x.dither ? 100 : 0) : src.ditherValue;
    x.ditherValue = Math.max(0, Math.min(100, x.ditherValue));
    x.grain = src.grain === undefined ? 'normal' : src.grain;
    if (x.grain !== 'off' && x.grain !== 'weak' && x.grain !== 'normal') x.grain = 'normal';
    x.grainValue = src.grainValue === undefined || isNaN(src.grainValue) ? 100 : src.grainValue;
    x.grainValue = Math.max(0, Math.min(150, x.grainValue));
    return x;
  }
}
