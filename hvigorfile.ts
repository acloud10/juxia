import { appTasks } from '@ohos/hvigor-ohos-plugin';
import * as path from 'path';
import * as fs from 'fs';

// DevEco 的 PackageHap 会直接 spawn "java"。
// 如果 IDE 进程的 PATH 没有带 JBR，就在 hvigor 进程里补上，
// 避免出现 spawn java ENOENT。
const sdkHome: string = process.env.DEVECO_SDK_HOME ?? '';
const jbrBin: string = sdkHome.length > 0 ? path.resolve(sdkHome, '..', 'jbr', 'bin') : '';
const javaExe: string = jbrBin.length > 0 ? path.join(jbrBin, 'java.exe') : '';
if (javaExe.length > 0 && fs.existsSync(javaExe)) {
  const current: string = process.env.PATH ?? '';
  const parts: string[] = current.split(path.delimiter);
  if (!parts.includes(jbrBin)) {
    process.env.PATH = jbrBin + path.delimiter + current;
  }
}

export default {
    system: appTasks,  /* Built-in plugin of Hvigor. It cannot be modified. */
    plugins:[]         /* Custom plugin to extend the functionality of Hvigor. */
}
