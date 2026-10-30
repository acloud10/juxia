// 句栖 · 主题令牌（经典 / 朴素 × 日间 / 夜间）
export class Tokens {
  bg: string = '#ede6d3';
  ink: string = '#4f4f4c';
  inkStrong: string = '#3a3a37';
  inkSoft: string = '#666257';
  line: string = '#244f4f4c';
  lineSoft: string = '#144f4f4c';
  card: string = '#9efffdf6';
  cardSolid: string = '#fbf7ec';
  seal: string = '#b8434a';
  sealSoft: string = '#1ab8434a';
  sealInk: string = '#fdf6ea';
  inputBg: string = '#6bffffff';
  shadowColor: string = '#14483f2a';
  shadowLift: string = '#1e483f2a';
  radiusCard: number = 18;
  radiusBtn: number = 999;
  radiusInput: number = 14;
  serif: string = 'JuxiaSerif';
  sans: string = 'HarmonyOS Sans SC';
  plain: boolean = false;
  blurCard: number = 10;
  tabBg: string = '#c7fbf7ec';
  toastBottom: number = 110;
}

export function getTokens(skin: string, dark: boolean): Tokens {
  const t = new Tokens();
  t.plain = skin === 'plain';
  if (t.plain) {
    t.serif = 'JuxiaSerif';
    t.sans = 'JuxiaSerif';
    t.radiusCard = 10;
    t.radiusBtn = 8;
    t.radiusInput = 8;
    t.blurCard = 0;
    t.toastBottom = 64;
    if (dark) {
      t.bg = '#1b1a17';
      t.ink = '#efe9dc';
      t.inkStrong = '#f7f2e6';
      t.inkSoft = '#b8b0a2';
      t.line = '#26ffffff';
      t.lineSoft = '#14ffffff';
      t.card = '#ff262420';
      t.cardSolid = '#262420';
      t.seal = '#c25a44';
      t.sealSoft = '#24c25a44';
      t.sealInk = '#f4efe4';
      t.inputBg = '#33ffffff';
      t.shadowColor = '#33000000';
      t.shadowLift = '#3d000000';
      t.tabBg = '#ff242422';
    } else {
      t.bg = '#f5efe2';
      t.ink = '#362f26';
      t.inkStrong = '#2f2921';
      t.inkSoft = '#666257';
      t.line = '#ffded2b8';
      t.lineSoft = '#1a362f26';
      t.card = '#fffaf5ea';
      t.cardSolid = '#faf5ea';
      t.seal = '#b3432b';
      t.sealSoft = '#17b3432b';
      t.sealInk = '#f7f1e4';
      t.inputBg = '#b3f5efe2';
      t.shadowColor = '#0d362f26';
      t.shadowLift = '#12362f26';
      t.tabBg = '#fffaf5ea';
    }
    return t;
  }
  if (dark) {
    t.bg = '#1c1915';
    t.ink = '#e9e4d5';
    t.inkStrong = '#f4efe2';
    t.inkSoft = '#a39c89';
    t.line = '#26e9e4d5';
    t.lineSoft = '#14e9e4d5';
    t.card = '#d92b261d';
    t.cardSolid = '#2b271e';
    t.seal = '#b04f3b';
    t.sealSoft = '#2bb04f3b';
    t.sealInk = '#fdf6ea';
    t.inputBg = '#38000000';
    t.shadowColor = '#52000000';
    t.shadowLift = '#5c000000';
    t.tabBg = '#d92b271e';
  } else {
    t.bg = '#ede6d3';
    t.ink = '#4f4f4c';
    t.inkStrong = '#3a3a37';
    t.inkSoft = '#666257';
    t.line = '#244f4f4c';
    t.lineSoft = '#144f4f4c';
    t.card = '#a8f7f1e2';
    t.cardSolid = '#f7f1e2';
    t.seal = '#bd5238';
    t.sealSoft = '#17bd5238';
    t.sealInk = '#fdf6ea';
    t.inputBg = '#6bfaf4e6';
    t.shadowColor = '#14483f2a';
    t.shadowLift = '#1e483f2a';
    t.tabBg = '#c7f7f1e2';
  }
  return t;
}

export const FONT_SERIF: string = 'JuxiaSerif';
export const FONT_SANS: string = 'HarmonyOS Sans SC';


