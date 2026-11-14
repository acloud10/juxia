# 备份格式

本文只说明格式与兼容性，不包含任何密钥、证书或真实用户数据。

## 1. 完整加密备份 `.sj4`

`.sj4` 是二进制文件，不是可以直接解压的 ZIP。

### 文件头

```text
"SJ4"       3 字节
salt       32 字节
iv         12 字节
ciphertext 变长
tag        16 字节
```

### 加密

```text
PBKDF2-HMAC-SHA256
迭代次数：310000
salt：32 字节随机
输出：32 字节密钥

AES-256-GCM
IV：12 字节随机
Tag：16 字节
AAD：空
```

### 明文载荷

加密前是整个 ZIP：

```text
data.json
manifest.json
materials/       可选
```

材料文件名：

```text
materials/<material id>.txt
```

### 解密失败

```text
密语错误
文件损坏
不是 .sj4
```

三种情况都会失败；原文件不要删除。

## 2. 完整不加密备份 `.zip`

与 `.sj4` 的明文载荷相同，只是不加密：

```text
data.json
manifest.json
materials/       可选
```

拿到文件的人可以直接查看。

## 3. 完整备份 manifest

```json
{
  "format": "juxia-full",
  "version": 1,
  "createdAt": 0,
  "dataBytes": 0,
  "materialCount": 0,
  "includeMaterials": false
}
```

字段说明：

| 字段 | 说明 |
|---|---|
| `format` | 固定 `juxia-full` |
| `version` | 当前为 1 |
| `createdAt` | 导出时间戳 |
| `dataBytes` | `data.json` 字节数 |
| `materialCount` | 材料数量 |
| `includeMaterials` | 是否包含材料 |

恢复时会校验：

```text
format
version
dataBytes
materialCount
```

## 4. 材料包 `.zip`

材料包只包含材料文件与一个 manifest：

```text
manifest.json
<materials>.txt
```

当前 manifest：

```json
{
  "format": "juxia-materials",
  "version": 1,
  "createdAt": 0,
  "items": [
    {
      "id": "材料 id",
      "name": "材料名",
      "size": 0
    }
  ]
}
```

旧版本材料包 manifest 是纯数组：

```json
[
  {
    "id": "材料 id",
    "name": "材料名",
    "size": 0
  }
]
```

导入端仍然兼容旧数组；新导出使用带 `format` / `version` 的对象。

## 5. `data.json`

`data.json` 是完整的 `AppData`：

```text
version
own
lib
dislikes
materials
settings
day
meta
```

备份字段名通过 `entry/obfuscation-rules.txt` 中的 `-keep-property-name` 保持稳定。

包括：

```text
own / lib / dislikes / materials
settings
day
meta
note / notes / bindIds
archCat / archNote / archAt
revisitAt / snoozeUntil
replyToId / replyFrom
format / dataBytes / materialCount / includeMaterials
items
```

## 6. 恢复顺序

完整备份恢复不是先删后写。

当前逻辑：

```text
校验备份
→ 新材料复制到临时目录
→ 旧材料目录改名备份
→ 临时目录切换为正式目录
→ 替换数据库
→ 成功后再删除旧目录
```

任一步失败：

```text
删除临时目录
恢复旧材料目录
不替换数据库
```

## 7. 兼容性

```text
.sj4             当前版本
.zip 完整备份    当前版本
材料包 .zip      新旧 manifest 均支持
.sj3             旧文本密语包，已移除用户入口
```

新增字段时：

```text
data.json 缺字段 → normalize 使用默认值
旧材料包数组   → 导入时识别为旧格式
新导出对象     → 带 format / version
```

## 8. 注意

```text
密语不保存
密语丢失后 .sj4 无法恢复
恢复会覆盖当前全部数据
恢复前先导出当前备份
```
