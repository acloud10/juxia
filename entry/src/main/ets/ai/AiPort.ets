// 句栖 · 可选 AI 能力边界
// 正式包只使用 NoAiPort：无网络、无 Key、无入口。
// 想启用 AI 的开发者，把 optional-ai/ 的实现复制到本目录并注册。

export interface AiRequest {
  source: string;
  endpoint: string;
  apiKey: string;
  model: string;
  style: string;
  keyword: string;
  lock: string;
  mode: string;
  avoid: string;
}

export interface AiPort {
  available(): boolean;
  generate(req: AiRequest): Promise<string>;
}

export class NoAiPort implements AiPort {
  available(): boolean {
    return false;
  }

  async generate(req: AiRequest): Promise<string> {
    throw new Error('AI_DISABLED');
  }
}

export class AiRegistry {
  private static port: AiPort = new NoAiPort();

  static install(port: AiPort): void {
    AiRegistry.port = port;
  }

  static get(): AiPort {
    return AiRegistry.port;
  }

  static available(): boolean {
    return AiRegistry.port.available();
  }
}
