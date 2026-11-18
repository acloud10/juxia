# SJ4 备份格式的 JSON 字段名跨版本兼容：全部保留，不许混淆
-keepclassmembernames class com.juxia.app.model.** { *; }
-keepnames class com.juxia.app.model.**

# kotlinx.serialization（release 必需；缺了会在序列化时 ClassNotFoundException）
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.**
-keepclassmembers class kotlinx.serialization.json.** { *** Companion; }
-keepclasseswithmembers class kotlinx.serialization.json.** {
    kotlinx.serialization.KSerializer serializer(...);
}
# 插件生成的 $$serializer 嵌套类与 Companion 序列化器入口
-keepclassmembers class com.juxia.app.model.** { *** Companion; }
-keep class com.juxia.app.model.**$* { *; }

# SQLCipher（native 库与反射入口）
-keep class net.sqlcipher.** { *; }
-keep class net.zetetic.database.** { *; }
-keep class net.zetetic.** { *; }
-keepclasseswithmembernames class * { native <methods>; }
