# 句栖 Android

这是句栖的 Android 版（Kotlin + Jetpack Compose），与鸿蒙版共享同一套数据模型、备份格式和产品文案。

## 重要说明

Android 版仍有功能与 UI 差异，存在未知 bug。

- 功能和 UI 可能与鸿蒙版存在差异。
- 存在未知 bug。
- 升级、迁移或清空数据前，请先导出备份。
- 重要数据不要只留一份。

正式 release APK 由维护者使用固定 release keystore 签名；源码不包含任何密钥。

## 环境

- JDK 21
- Android SDK，compileSdk 35
- 项目自带 Gradle Wrapper

## 构建 Debug

```powershell
cd android
./gradlew :app:assembleDebug
```

Windows：

```powershell
.\gradlew.bat :app:assembleDebug
```

产物：

```text
app/build/outputs/apk/debug/app-debug.apk
```

Debug 包可调试，不能作为正式发布包。

## 构建 Release

Release 需要本地 `keystore.properties`，该文件不进 Git：

```properties
storeFile=.signing/juxia-release.jks
storePassword=你的密码
keyAlias=juxia
keyPassword=你的密码
```

然后：

```powershell
.\gradlew.bat :app:assembleRelease
```

产物：

```text
app/build/outputs/apk/release/app-release.apk
```

`app/build.gradle.kts` 只在 `keystore.properties` 存在时启用 release 签名；没有它时会产出 unsigned release。

## 源码拉取

完整仓库：

```powershell
git clone https://github.com/acloud10/juxia.git
```

只拉 Android：

```powershell
git clone --filter=blob:none --sparse https://github.com/acloud10/juxia.git
cd juxia
git sparse-checkout set android
```

只拉鸿蒙、以及完整说明，见仓库根目录 `README.md`。

## 数据与备份

- 数据库使用 SQLCipher，密钥由 Android Keystore 托管。
- 备份 `.sj4` 使用 PBKDF2-HMAC-SHA256 + AES-256-GCM，与鸿蒙版共享格式。
- 不申请 INTERNET 权限，不包含广告、统计或在线服务 SDK。

## 许可与第三方

见仓库根目录 `LICENSE` 和 `THIRD_PARTY_NOTICES.md`。
