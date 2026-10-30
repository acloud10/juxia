// 把设计网格里的 SVG Path 命令换算成设备像素；只缩放坐标，不动 A 命令的弧标志位。
import { display } from '@kit.ArkUI';

let cachedDensity: number = -1;

function density(): number {
  if (cachedDensity > 0) return cachedDensity;
  try {
    cachedDensity = display.getDefaultDisplaySync().densityPixels;
  } catch (e) {
    cachedDensity = 1;
  }
  return cachedDensity;
}

export function scalePath(cmd: string, scale: number): string {
  const tokens: string[] = cmd.match(/[MLAQZ]|-?\d+(\.\d+)?/g) ?? [];
  let out: string = '';
  let i: number = 0;
  while (i < tokens.length) {
    const t: string = tokens[i];
    if (t === 'M' || t === 'L') {
      out += `${t} ${(parseFloat(tokens[i + 1]) * scale).toFixed(2)} ${(parseFloat(tokens[i + 2]) * scale).toFixed(2)} `;
      i += 3;
    } else if (t === 'Q') {
      out += `Q ${(parseFloat(tokens[i + 1]) * scale).toFixed(2)} ${(parseFloat(tokens[i + 2]) * scale).toFixed(2)} ` +
        `${(parseFloat(tokens[i + 3]) * scale).toFixed(2)} ${(parseFloat(tokens[i + 4]) * scale).toFixed(2)} `;
      i += 5;
    } else if (t === 'A') {
      out += `A ${(parseFloat(tokens[i + 1]) * scale).toFixed(2)} ${(parseFloat(tokens[i + 2]) * scale).toFixed(2)} ` +
        `${tokens[i + 3]} ${tokens[i + 4]} ${tokens[i + 5]} ` +
        `${(parseFloat(tokens[i + 6]) * scale).toFixed(2)} ${(parseFloat(tokens[i + 7]) * scale).toFixed(2)} `;
      i += 8;
    } else if (t === 'Z') {
      out += 'Z ';
      i += 1;
    } else {
      i += 1;
    }
  }
  return out;
}

export function pathScale(sizeVp: number, grid: number): number {
  return sizeVp * density() / grid;
}
