// 可选 AI 实现：一言 / OpenAI 兼容 API 两种来源并列。
// 复制到 entry/src/main/ets/ai/ 后，在应用启动时调用 installOptionalAi()。
import { AiPort, AiRegistry, AiRequest } from './AiPort';
import { AiConfig } from './AiConfig';
import { Remote } from './Remote';
import { KeyStore } from './KeyStore';

export class OptionalAi implements AiPort {
  available(): boolean {
    return true;
  }

  async generate(req: AiRequest): Promise<string> {
    if (req.source === 'hitokoto') {
      const h = await Remote.hitokoto(['d', 'i', 'k'], req.endpoint);
      return h.text;
    }
    let key: string = req.apiKey.trim();
    if (key.length === 0) key = await KeyStore.load();
    if (key.length === 0) throw new Error('NO_AI_KEY');
    const cfg = new AiConfig();
    cfg.endpoint = req.endpoint;
    cfg.model = req.model;
    cfg.style = req.style;
    cfg.keySession = false;
    return await Remote.aiGenerate(cfg, key, req.keyword, req.lock, req.mode, req.avoid);
  }
}

export function installOptionalAi(): void {
  AiRegistry.install(new OptionalAi());
}
