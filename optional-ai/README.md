# 句栖 · 可选 AI（一言 / API）

> AI 是过去的备选方案。后来项目更看重离线与隐私安全，因此做减法，把 AI 从正式应用中删去。
>
> 但这条路线确实做出来过。完全不公开、任由经验消失有些可惜，所以把当时的实现与接入说明放在这里，仅作存档和自行构建参考。
>
> 正式包**不包含**本目录，也不申请网络权限。

只有想自行构建 AI 版本的人，才按下面步骤接入。

## AI 只做两件事

```text
抽句子（一言或 API）
预览后，用户点“收藏入库”才写入句库
```

不做聊天、不做多轮对话、不自动保存。

## 两种来源并列

```text
hitokoto  一言
api       OpenAI 兼容 /chat/completions
```

由用户选择，不自动兜底。

## 接入步骤

### 1. 复制文件

把本目录的：

```text
AiConfig.ets
AiDrawService.ets
KeyStore.ets
Remote.ets
```

复制到：

```text
entry/src/main/ets/ai/
```

`AiPort.ets` 已经在核心目录，不要覆盖。

### 2. 注册实现

在应用启动、UI 之前调用一次：

```ts
import { installOptionalAi } from './ai/AiDrawService';

installOptionalAi();
```

放在 `EntryAbility.onCreate()` 或 `Index.aboutToAppear()` 开头均可。  
不调用时，正式包仍然使用 `NoAiPort`。

### 3. 添加网络权限

在：

```text
entry/src/main/module.json5
```

的 `requestPermissions` 中加入：

```json
{ "name": "ohos.permission.INTERNET" }
```

不加权限，AI 请求会失败。

### 4. 在 UI 里抽句并入库

```ts
import { AiRegistry, AiRequest } from './ai/AiPort';
import { Store } from '../data/Store';

const req: AiRequest = {
  source: 'hitokoto',        // 或 'api'
  endpoint: 'https://v1.hitokoto.cn/',
  apiKey: '',
  model: 'deepseek-flash',
  style: '',
  keyword: '',
  lock: '',
  mode: 'imitate',
  avoid: ''
};

const text = await AiRegistry.get().generate(req);
// 只显示预览，不直接入库

// 用户点“收藏入库”后：
Store.get().addLib(text, '一言', 'ai', 'AI 引文');
```

API 来源时，`source` 设为 `'api'`，并填 `endpoint`、`model`、`apiKey`。

## Key 保存

### 仅本次会话

不要把 Key 写入 Store；只放内存变量。杀进程即失效。

### 本机加密保存

```ts
import { KeyStore } from './ai/KeyStore';

await KeyStore.save(key);   // 写入系统 Asset Store
await KeyStore.load();      // 读取
await KeyStore.clear();     // 清除全部数据时调用
```

规则：

```text
ai.key 永远不写 settings 数据库
备份导出时清空 ai.key
日志不打印 Key
设置页不回显完整 Key
```

## 预览与收藏

```text
生成 → 预览
用户确认 → Store.addLib(...)
取消 → 丢弃
```

不要自动入库。

## 构建

```text
默认 release：不含 AI，无 INTERNET 权限
自行构建：复制文件 + 注册 + 加权限 + 用自己的签名
```
