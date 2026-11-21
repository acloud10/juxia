# 句栖 / Juxia

句栖是一个只对自己开放的、和未来的自己保持对话的私人仪式空间。

它不把句子寄给未来，也不是按日期翻的日记。你写下一句，句子留在本机；以后某天抽到它，可以回一句话；旧事归档后，可以在约定时间轻轻回访。全部本地，无账号、无广告、不联网。

HarmonyOS 主版本使用 ArkTS / ArkUI 编写，另有 Android 版。

## 下载

### Android

到 GitHub Releases 下载最新 **signed release APK**：

```text
https://github.com/acloud10/juxia/releases
```

Android 版仍有功能与 UI 差异，存在未知 bug。升级、迁移或清空数据前请先导出备份；重要数据不要只留一份。

### HarmonyOS

GitHub 不提供 HAP/APP 安装包。

请到 **华为应用市场搜索「句栖」** 下载。

### 官方渠道

以上是句栖仅有的两个官方渠道。

句栖官方版本目前不向用户收费。其他应用商店、下载站或收费包均非官方发布，请勿把它们当作官方版本。

Android 官方签名证书 SHA-256：

```text
191C4899BC862FA26AC3D6585670EA0DA7CACC7246FEB4093A9B092987A31B27
```

## 源码拉取

### 只拉鸿蒙

```powershell
git clone --filter=blob:none --sparse https://github.com/acloud10/juxia.git
cd juxia
git sparse-checkout set AppScope entry hvigor optional-ai docs
```

### 只拉 Android

```powershell
git clone --filter=blob:none --sparse https://github.com/acloud10/juxia.git
cd juxia
git sparse-checkout set android
```

### 全拉

```powershell
git clone https://github.com/acloud10/juxia.git
```

GitHub 网页的 **Download ZIP** 会下载整个仓库；只有 `git clone` + `sparse-checkout` 能只拉一部分。

## Android 版说明

Android 工程在 `android/`，使用 Kotlin + Jetpack Compose。

- 仍有功能与 UI 差异，存在未知 bug。
- 备份 `.sj4` 与鸿蒙版共享格式，但真实跨端互导仍需自行验证。
- 正式 APK 由固定 release keystore 签名；仓库不包含密钥。
- 构建与签名说明见 `android/README.md`。

## 关于 AI（历史备选）

AI 是过去的备选方案。后来项目更看重离线与隐私安全，因此做减法，把 AI 从正式应用中删去。

但这条路线确实做出来过。完全不公开、任由经验消失有些可惜，所以把当时的实现与接入说明放在 optional-ai/，仅作存档和自行构建参考。正式包不包含 AI，也不申请网络权限。

## 它不是什么

- 不是普通的日记本：不按日期翻，靠抽签重遇
- 不是常见的时间胶囊：不把句子定时寄出，只有旧事才有回访
- 不是树洞社交：不交给陌生人，不上云
- 不是 AI 回信：正式包无 AI、无网络权限，回信由用户自己写

## 核心闭环

```text
写一句 → 收好 → 抽到 → 回一句 → 归档 → 回访 → 再回一句
```

不是“寄出去”，是“存起来，在某个需要的时刻重新遇见，并能回应它”。

## 产品能力

- 晴雨双线：晴写鼓励，雨写旧事；晴天可抽旧事，雨天可抽鼓励或句库材料
- 抽签重遇：从自己的句子和已收藏材料中随机抽取，不是信息流推荐
- 回信：抽到或回访时可以回一句；回信独立保存，不是备注
- 归档与回访：旧事按已解决 / 已放下归档，可约 14 天后回访；鼓励归档后不再回访
- 备注与关联：鼓励、旧事、句库可以互相关联，各自留下注脚
- 省身：不参与抽签和关联的旁观记录
- 句库与材料：收藏句子、导入 txt/md、自动分句、检索；材料先收藏才进入抽签
- 空间 DIY：应用名、称呼、启动文案、主题、背景、字体、印章、抽签来源
- 本地优先：加密数据库、SJ4 / ZIP 备份，无账号、广告、统计或云同步

## 环境要求

- DevEco Studio 26.0.0 或兼容版本
- HarmonyOS SDK API 26
- `compileSdkVersion`：26.0.0
- `targetSdkVersion`：26.0.0
- `compatibleSdkVersion`：6.1.0(23)
- Windows / macOS 均可构建
- 真机或模拟器用于运行

## 构建

在项目根目录执行：

```powershell
$env:DEVECO_SDK_HOME = "C:\DevEco Studio\sdk"

& "C:\DevEco Studio\tools\hvigor\bin\hvigorw.bat" `
  assembleHap `
  --mode module `
  -p product=default `
  -p module=entry@default `
  -p buildMode=debug
```

构建产物位于：

```text
entry/build/default/outputs/default/
```

## 签名

本仓库**不包含**任何签名证书、Profile 或私钥。

请自行在 DevEco Studio 中配置签名：

```text
File → Project Structure → Signing Configs
```

或在本地创建不纳入 Git 的 `build-profile.local.json5`，不要把以下内容提交到仓库：

```text
*.p12
*.p7b
*.cer
*.jks
*.keystore
signing/
```

使用代理提醒能力时，需要在 AGC 单独申请「代理提醒」开放能力，并使用包含该能力的 Profile 手动签名。没有该能力时，系统提醒配额为 0，App 会退回到「打开 App 时查看到期回访卡」。

## 目录

```text
AppScope/                 应用级配置与图标
android/                  Android 工程（Kotlin + Compose）
entry/
  src/main/ets/           ArkTS 页面、组件、状态、服务
  src/main/resources/     字符串、颜色、媒体、字体、隐私页
  src/main/module.json5   模块与权限声明
hvigor/                   Hvigor 配置
build-profile.json5       产品与 SDK 配置（不含签名）
oh-package.json5          依赖声明
docs/
  BACKUP_FORMAT.md        备份格式与兼容说明
  DEBUG_SEED.md           Debug 演示种子记录
RELEASES.md               版本与本地包说明
CHANGELOG.md              版本记录
```

## 备份与恢复

- `.sj4`：完整加密备份，PBKDF2-SHA256 + AES-256-GCM，需要密语
- `.zip`：完整不加密备份，拿到文件的人可以直接查看
- 材料包 `.zip`：单独搬运材料，有 `format` / `version` 校验
- 恢复会覆盖当前全部数据；恢复前请先导出当前备份

详细格式见 [docs/BACKUP_FORMAT.md](docs/BACKUP_FORMAT.md)。

## 隐私

- 不申请网络权限
- 不读取通讯录、短信、位置、相册或麦克风
- 文件选择器只在主动导入材料或备份时打开
- 通知只包含「有旧事到了回看时间」，不包含句子、备注、材料或省身正文
- 备份由用户主动导出；密语不保存，遗失无法恢复

## 许可

代码以 [MIT](LICENSE) 许可证开源。

「句栖」名称、应用图标、应用商店条目和官方身份不属于代码许可证的授权范围；未经许可，不得用于冒充官方版本。

第三方基于本项目发布时，请使用自己的名称和图标，并明确标注为非官方版本。

详见 [TRADEMARK.md](TRADEMARK.md)。

字体和第三方组件说明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

## 安全

如果你发现安全问题，请不要公开提交可利用细节，先通过仓库 Issue 或维护者公开邮箱联系。
