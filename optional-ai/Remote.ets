// 句匣 · 网络能力：一言 + OpenAI 兼容接口
import { http } from '@kit.NetworkKit';
import { AiConfig } from './AiConfig';

const SYSTEM_PROMPT: string = '你是一个克制的句子写作者。只输出一句中文，不加引号、不加解释、不署名、不写出处。';

interface HitoJson {
  hitokoto?: string;
  from_who?: string;
  from?: string;
  uuid?: string;
}

interface AiMessage {
  content?: string;
  reasoning_content?: string;
}

interface AiChoice {
  message?: AiMessage;
}

interface AiResp {
  choices?: AiChoice[];
}

interface ChatMessage {
  role: string;
  content: string;
}

interface ThinkingMode {
  type: string;
}

interface ChatBody {
  model: string;
  messages: ChatMessage[];
  temperature: number;
  max_tokens: number;
  thinking: ThinkingMode;
}

export class Hitokoto {
  text: string = '';
  source: string = '';
  uuid: string = '';
}

export class Remote {
  static async hitokoto(cats: string[], endpoint: string = 'https://v1.hitokoto.cn/'): Promise<Hitokoto> {
    const valid: string[] = cats.filter((c: string) => c === 'd' || c === 'i' || c === 'k');
    const use: string[] = valid.length > 0 ? valid : ['d', 'i', 'k'];
    const query: string = use.map((c: string) => 'c=' + c).join('&');
    let base: string = endpoint.trim();
    if (base.length === 0) base = 'https://v1.hitokoto.cn/';
    const url: string = base + (base.indexOf('?') >= 0 ? '&' : '?') + query;
    const req = http.createHttp();
    try {
      const resp = await req.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 6000,
        readTimeout: 6000
      });
      if (resp.responseCode !== 200) {
        throw new Error('HTTP ' + resp.responseCode);
      }
      const text: string = resp.result as string;
      const obj = JSON.parse(text) as HitoJson;
      const out = new Hitokoto();
      out.text = String(obj.hitokoto ?? '');
      out.uuid = String(obj.uuid ?? '');
      const who: string = String(obj.from_who ?? '');
      const from: string = String(obj.from ?? '');
      out.source = [who, from].filter((s: string) => s.length > 0).join(' · ');
      if (out.source.length === 0) out.source = '一言';
      if (out.text.length === 0) throw new Error('empty');
      return out;
    } finally {
      req.destroy();
    }
  }

  static async aiGenerate(cfg: AiConfig, key: string, keyword: string, lock: string, mode: string, avoid: string = ''): Promise<string> {
    let base: string = cfg.endpoint.replace(/\/+$/, '');
    if (base.endsWith('/v1')) {
      base = base.slice(0, base.length - 3);
    }
    let model: string = cfg.model.trim();
    if (model === 'deepseek-chat' || model === 'deepseek-v4-flash' || model.length === 0) {
      model = 'deepseek-flash';
    }
    const style: string = cfg.style.trim();
    const tail: string = style.length > 0 ? `风格补充：${style}。` : '';
    const avoidLine: string = avoid.trim().length > 0 ? `不要重复这句，也不要改写它：${avoid.trim()}。` : '';
    const nonce: string = Math.random().toString(36).slice(2, 8);
    let prompt: string = '';
    if (mode === 'quote') {
      prompt = lock.length > 0
        ? `请凭你的训练记忆，从《${lock}》中找出一句真实原文${keyword.length > 0 ? `，主题贴近「${keyword}」` : ''}。要求：确实出自该书；只输出这句话本身，不解释、不加引号、不附出处。若你不能确定原文，只输出四个字：不能确定。换一句不同的。${avoidLine}标记：${nonce}。`
        : `请凭你的训练记忆，找出一句真实存在、流传较广的名言或诗文原文${keyword.length > 0 ? `，主题贴近「${keyword}」` : ''}。只输出这句话本身，不解释、不加引号、不附出处。若你不能确定，只输出四个字：不能确定。换一句不同的。${avoidLine}标记：${nonce}。`;
    } else {
      prompt = lock.length > 0
        ? `你深读《${lock}》。请依其思想与语气，写一句不超过40字的话${keyword.length > 0 ? `，围绕「${keyword}」` : ''}。真诚、克制，不喊口号，不是鸡汤。这是仿写，不是原文。只输出这句话本身，不要解释、引号或出处。${tail}${avoidLine}标记：${nonce}。`
        : `写一句不超过40字的话${keyword.length > 0 ? `，围绕「${keyword}」` : ''}。真诚、克制、具体，不喊口号，不是鸡汤。只输出这句话本身，不要解释和引号。${tail}${avoidLine}标记：${nonce}。`;
    }
    const sysMsg: ChatMessage = { role: 'system', content: SYSTEM_PROMPT };
    const userMsg: ChatMessage = { role: 'user', content: prompt };
    const bodyObj: ChatBody = {
      model: model,
      messages: [sysMsg, userMsg],
      temperature: 0.9,
      max_tokens: 320,
      thinking: { type: 'disabled' }
    };
    const body: string = JSON.stringify(bodyObj);
    const req = http.createHttp();
    try {
      const resp = await req.request(base + '/chat/completions', {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ' + key
        },
        extraData: body,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 10000,
        readTimeout: 25000
      });
      if (resp.responseCode !== 200) {
        throw new Error('HTTP ' + resp.responseCode);
      }
      const text: string = resp.result as string;
      const obj = JSON.parse(text) as AiResp;
      let content: string = '';
      if (obj.choices !== undefined && obj.choices.length > 0) {
        const msg = obj.choices[0].message;
        if (msg !== undefined) {
          content = String(msg.content ?? '');
          if (content.trim().length === 0 && msg.reasoning_content !== undefined) {
            content = String(msg.reasoning_content);
          }
        }
      }
      content = content.trim().replace(/^["「『“”]+|["」』“”]+$/g, '');
      return content.slice(0, 90);
    } finally {
      req.destroy();
    }
  }

  static aiError(e: Object): string {
    const msg: string = String((e as Error).message ?? '');
    if (msg.includes('401') || msg.includes('403')) return 'Key 无效或没有权限';
    if (msg.includes('429')) return '请求太频繁，稍等一会儿';
    if (msg.startsWith('HTTP 5')) return '接口暂时不可用';
    if (msg.includes('timeout') || msg.includes('Timeout')) return '请求超时，接口可能太慢';
    if (msg.includes('empty')) return '接口没有返回内容';
    if (msg.includes('2300') || msg.includes('201') || msg.includes('network')) return '连不上接口，检查地址或网络';
    return msg.length > 0 ? msg : '未知错误';
  }
}
