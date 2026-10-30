// 清理旧版本遗留的第三方服务密钥；当前版本不包含任何在线服务
import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';

const LEGACY_ALIAS: string = 'juxia.ai.key';

function bytes(s: string): Uint8Array {
  return new util.TextEncoder().encodeInto(s);
}

export async function clearLegacyKey(): Promise<void> {
  const q: asset.AssetMap = new Map();
  q.set(asset.Tag.ALIAS, bytes(LEGACY_ALIAS));
  try {
    await asset.remove(q);
  } catch (e) {
    // 不存在时忽略
  }
}
