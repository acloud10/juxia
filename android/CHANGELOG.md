# 句栖安卓版 · 变更日志

格式：日期 · 类别。对应鸿蒙版 CHANGELOG 的家风——每条记录一个真实的坑或决策。

## 2026-11-18（与鸿蒙 1.0.5 全面对齐）
### 备份互通（此前两端备份互不可导入）
- 完整备份清单改写为鸿蒙 `juxia-full` v3（dataBytes / dataSha256 / materialCount / materials[{id,bytes,sha256}] / backgrounds[{key,bytes,sha256}]），鸿蒙端可直接导入安卓产物
- 读取端两种格式都认：`juxia-full` v1–3 与旧 `juxia-backup-manifest` v1–3；manifest/data.json 兼容一层目录前缀
- 背景文件名从 `bg_<原名>` 改为六槽位 `<key>.jpg`，还原时按 key 重新指向——鸿蒙备份里存的是旧设备绝对路径，跨设备必须重映射
- 不含材料导出时同步清空 data.json 的 materials；材料复制失败改为整包不生成（与鸿蒙「材料复制失败，完整备份未生成」一致）
- 删除"同名同尺寸就跳过"的判重：恢复是整库替换，跳过等于把这份材料丢掉

### 功能对齐
- 提醒调度改为排「将来」到期的回访（此前只排已到期的，90 天后的约定当天不会响）
- findOne 补排除名单过滤（否则「不喜欢」在材料检索里等于没生效）+ 连续两次不重复同一句
- 内置句库清理：normalize 清掉 origin=builtin 的句库/排除项，去掉「内置句库」标签
- 新增跨午夜自动滚日期（对齐鸿蒙 Index.scheduleDayTick；此前只在 ON_RESUME 滚）
- 补「显示「相伴第 N 天」」开关（鸿蒙有这个开关，安卓此前只有默认值、无法关闭）

### 语义对齐
- 钳制范围：字号 0.85–1.4（原 1.3）、开机字号 0.8–2.5（原 1.0–2.0）、停留 300–5000（原 200–8000）
- newId 加碰撞比对；postponeMissedRevisits 加「只处理已归档」守卫
- 删除 repairLostOpenDays：凭空补 22 个随机打开日等于伪造「相伴第 N 天」
- 背景只保留四张，normalize 清空 lightClassic/darkClassic

### 界面对齐
- 顶栏印章补回红底渐变 + 投影 + -1.2° 倾斜（此前近白字落在浅底上，浅色几乎看不见）；朴素皮不显示印章
- 顶栏字距 7（朴素 10）、字重 Medium、内边距 20/26/18、日期块字距 2.4 且用无衬线
- 底栏改竖排等分玻璃胶囊：92% 宽 / max 440 / 圆角 999（朴素 12）/ 模糊 18 / 描边 / 投影；深色选中改用印章色底线而非实心胶囊
- 暗色卡片不再毛玻璃（鸿蒙 47 处卡片均为 `backdropBlur(dark ? 0 : 10)`）
- 隐私政策改为 12 节全文（对齐 PrivacyText.ets），设置页与隐私门共用同一弹窗
- 字号改为四个预设（0.9 小 / 1.0 标准 / 1.1 大 / 1.25 特大）
- 材料检索出处补「· 原文检索」后缀

### 工程
- 新增 `BackupInteropTest`：用手工构造的鸿蒙 `juxia-full` 包验证读取链路，而不是用本端写出的包自证
  （junit 未缓存，改用 jshell 对已编译类实测：鸿蒙格式包被接受，篡改包被 `备份校验失败` 拒绝）
- 补启动图标（沿用鸿蒙 app_icon.png）：此前 manifest 未声明 icon，装上去是系统默认图标
- 启动窗口底色日间 #EDE6D3 / 夜间 #191712（values-night），修深色冷启动闪白
- 版本对齐 1.0.5（versionCode 3）；assembleDebug 通过

## 2026-11-17（移植完成日）
### 修复（真编译战役，39 个真 bug，全部编译阻断级）
- 核心层：类内 typealias / reified import×2 / Float→Double / val 重赋值 / List→MutableList / 包路径错 / Log.e 第三参类型
- UI 层第一役：返回分发器块悬出类体 / Typeface 误导包 / 重复参数 / 48 行文本污染 / scaledSp 整型字面量 / collectAsState 静态式扩展调用×37 / contract 小写 import×2 / 孤儿括号 / 函数丢失×4 / import 缺失×6 / HazeStyle 构造歧义 / 智能转换×2 / 局部函数前向引用×2 / 型别错配×2
- 附带语言教训：Kotlin 局部函数不前向引用；Kotlin 类不合成 getX() 属性

### 对齐（与鸿蒙仓库裁决式对比）
- 采用鸿蒙 9：postponeMissedRevisits 真语义（只顺延过期日到今天回访时刻）/ newId 去随机 / storageMode 中文 / short 60ms / drawCount 死字段 / 句库徽章二分 / findOne 洗牌 8 份 / 提醒去 kind 过滤 / rollDay 内调 recordOpen（修复相伴天数永为 1 的零调用 bug）
- 保留安卓 3：prefs 防抖 / prefs 信封直编 / rollDay 用 saveKv（语义等价、更优）

### 工程
- 备份全链路流式化（两遍法 manifest + 懒读解压 + 临时目录载荷）
- 磁盘余量双段预检（对齐鸿蒙 assertFreeSpace + getOriginalSize），256MB 硬顶降级为兜底闸门
- 单条目 64MB 预检（中央目录，不解压）
- 全工程真编译通过（沙箱 kotlinc：核心 0 错误 + UI 1 预期 desktop 工件）
- SJ4 执行回归 PASS（编译产物直跑）

## 2026-11-16（移植主体日）
- 鸿蒙仓库全量翻译（37 文件 / 9300 行）：五页面 / 仪式 / 服务层 / SQLCipher(D2-A) / haze 毛玻璃
- 三轮外部审查 32 条全修复；六页文案程序化 diff 收敛；材料包跨端互通
