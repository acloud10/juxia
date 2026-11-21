# Releases


## GitHub Release 分发

- **Android**：GitHub Releases 提供 signed release APK，并附 `SHA256SUMS.txt`。
- **HarmonyOS**：GitHub 不提供 HAP/APP 安装包；请到华为应用市场搜索「句栖」下载。
- 仓库不保存任何签名证书、Profile、私钥或密码。

> Android 版仍有功能与 UI 差异，存在未知 bug。升级、迁移或清空数据前请先导出备份。

HarmonyOS 的签名 `.app` / `.hap` 不提交到 Git，也不上传到 GitHub Release。

正式包保存在本地工作区：

```text
packages/releases/
```

## 最新版本

### 1.0.6

```text
versionCode: 1000006
targetSdkVersion: 26.0.0
compileSdkVersion: 26.0.0
compatibleSdkVersion: 6.1.0(23)
buildMode: release
```

本地包：

```text
packages/releases/1.0.6/句栖-1.0.6-release.app
6,080,773 字节
SHA-256: F8DAB343EE7F4EA4CA793F6B367B0D229B589B4B9F005CE1B61324408790A149

packages/releases/1.0.6/句栖-1.0.6-release.hap
8,770,898 字节
SHA-256: 8E0569C7E875AA0DA75E425552C61BDC7449A874203F495B124D29E73B2C21E2
```

主要更新：

```text
新手指引改为晴线 5 步、雨线 6 步的分步演示
回信区移到「我的」省身上方，默认折叠，保留独立搜索
设置 → 关于新增评价句栖
旧事回访默认改为 14 天
新手指引完整文案增加折纸开场
修复演示时序、写入弹层、回信死代码等问题
```

### 1.0.5

```text
versionCode: 1000005
targetSdkVersion: 26.0.0
compileSdkVersion: 26.0.0
compatibleSdkVersion: 6.1.0(23)
buildMode: release
```

本地包：

```text
packages/releases/1.0.5/句栖-1.0.5-release.app
6,056,386 字节
SHA-256: CEBE5ABDF99AEE74E6662F93EC476CBE24D32DDC883C173B1568830278265893

packages/releases/1.0.5/句栖-1.0.5-release.hap
8,721,612 字节
SHA-256: 29F122A919FDC20EA0BE5DA5BEB5343354CE0AED065C29F280829BE5DF7B0344
```


### Android 1.0.5

GitHub Release 附件（signed release APK）：

```text
juxia-android-1.0.5.apk
28,751,211 字节
SHA-256: B2F48213DA34F9B2741BDB21034D5224A7D7C82A5FFE53C62D726302F487177E
```

签名证书：

```text
CN=Juxia, OU=Android, O=Juxia, C=CN
证书 SHA-256: 191C4899BC862FA26AC3D6585670EA0DA7CACC7246FEB4093A9B092987A31B27
```

Android 版仍有功能与 UI 差异，存在未知 bug。升级、迁移或清空数据前请先导出备份。

### HarmonyOS 1.0.5

GitHub 不提供 HAP/APP 安装包；请到华为应用市场搜索「句栖」下载。

主要更新：

```text
审核反馈修复：数据刷新、背景刷新、导入/清空刷新
新手指引预览与收起恢复
旧版混淆 meta 的 openDays 兼容恢复
```

### 1.0.4

```text
versionCode: 1000004
targetSdkVersion: 26.0.0
compileSdkVersion: 26.0.0
compatibleSdkVersion: 6.1.0(23)
buildMode: release
```

本地包：

```text
packages/releases/1.0.4/句栖-1.0.4-release.app
6,056,387 字节
SHA-256: ACB7B57FEE5788CC28AC425BD84B7C0309E561575B2C1C78B52818FF4AB40079

packages/releases/1.0.4/句栖-1.0.4-release.hap
8,721,613 字节
SHA-256: 615885D3AA8A25CC38E1B6CD1D8699CD29ABCCE5EF32AFD561D8FB8E9BB934A6
```

AGC 上架使用 `.app`。

主要内容：

```text
HarmonyOS 7 / API 26 适配
猫啃硬笔楷书
折纸动画 + 新手指引
左上角印章开关
回访回信 / 抽签回信 / 回信搜索 / 回信删除
非对称三角关联
内层限高滚动 + 长按到顶/到底
完整备份恢复 journal + 版本化材料目录 + restore token
流式 .sj4 加解密 + 剩余空间预检
manifest v2 数据/材料 SHA-256
备份字段 keep
```

## 历史版本

| 版本 | versionCode | 状态 |
|---|---:|---|
| 1.0.6 | 1000006 | 当前 |
| 1.0.5 | 1000005 | 历史 |
| 1.0.4 | 1000004 | 历史 |
| 1.0.3 | 1000003 | 已发布 |
| 1.0.2 | 1000002 | 历史 |
| 1.0.1 | 1000001 | 历史 |
| 1.0.0 | 1000000 | 首个版本 |

## 校验

本地查看包信息：

```powershell
$env:DEVECO_SDK_HOME = "C:\DevEco Studio\sdk"
& "C:\DevEco Studio\tools\hvigor\bin\hvigorw.bat" assembleApp `
  --mode project -p product=default -p buildMode=release
```

`packages/` 不进入 Git；`.gitignore` 已忽略：

```text
*.app
*.hap
*.hsp
signing/
```

## 相关文档

- [CHANGELOG.md](CHANGELOG.md)
- [docs/BACKUP_FORMAT.md](docs/BACKUP_FORMAT.md)
- [docs/DEBUG_SEED.md](docs/DEBUG_SEED.md)
