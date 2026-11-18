# 句栖 / Juxia

句栖是一个本地优先的句子记录与回看工具，HarmonyOS 主版本使用 ArkTS / ArkUI 编写，另有 Android 版。

它把想对自己说的话收好，在需要的时候重新遇见：写一句鼓励、把旧事放进树洞、归档后约定回访，也可以在句库和材料里找一句陪自己待一会儿。

## 下载

### Android

到 GitHub Releases 下载最新 **signed release APK**：

```text
https://github.com/acloud10/juxia/releases
```

Android 版目前仍不完备，功能和 UI 可能与鸿蒙版存在差异，不能保证没有 bug。升级、迁移或清空数据前请先导出备份；重要数据不要只留一份。

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

- 仍不完备，不能保证没有 bug。
- 备份 `.sj4` 与鸿蒙版共享格式，但真实跨端互导仍需自行验证。
- 正式 APK 由固定 release keystore 签名；仓库不包含密钥。
- 构建与签名说明见 `android/README.md`。

## 关于 AI（历史备选）

AI 是过去的备选方案。后来项目更看重离线与隐私安全，因此做减法，把 AI 从正式应用中删去。

但这条路线确实做出来过。完全不公开、任由经验消失有些可惜，所以把当时的实现与接入说明放在 optional-ai/，仅作存档和自行构建参考。正式包不包含 AI，也不申请网络权限。

## 特点

- 本地优先：句子、旧事、省身、备注、材料和设置只保存在本机
- 不联网、无账号、无广告、无统计 SDK
- 无 AI 功能、无 AI 接口、无 AI Key
- 鼓励、旧事、句库形成非对称三角关联
- 旧事归档与回访
- 独立的省身记录，可按年月折叠、搜索
- `.txt` / `.md` / `.markdown` 材料导入、分句、检索
- 完整加密备份 `.sj4`、完整不加密备份 `.zip`、材料包
- 本地系统提醒回访；未获得代理提醒能力时，App 内仍显示到期回访卡
- 首次使用：隐私协议 → 折纸动画 → 新手指引
- 设置中可隐藏左上角印章，可重看新手指引

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
