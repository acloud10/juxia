# Releases

本仓库只保存源码。签名后的 `.app` / `.hap` 不提交到 Git，也不上传到 GitHub Release。

正式包保存在本地工作区：

```text
packages/releases/
```

## 最新版本

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
5,384,687 字节
SHA-256: 343C9BCFC924EF8B59A2EA3D46B8FCDBC1B0AC85509AD02F26D6DB9B094DEE3C

packages/releases/1.0.4/句栖-1.0.4-release.hap
7,989,363 字节
SHA-256: D2716162B1368456CD74EB5ACDFC78444169E944E4BF77F151D7ECE724DFA1E9
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
| 1.0.4 | 1000004 | 当前 |
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

- [CHANGELOG.md](../CHANGELOG.md)
- [docs/BACKUP_FORMAT.md](BACKUP_FORMAT.md)
- [docs/DEBUG_SEED.md](DEBUG_SEED.md)
