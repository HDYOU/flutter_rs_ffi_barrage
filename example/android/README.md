# Android 平台配置

## 说明

本目录包含 Android 平台的基础配置骨架。

## 生成完整工程

如需生成完整的 Android 工程文件，请在 `example/` 目录下执行：

```bash
flutter create --platforms=android .
```

该命令会自动生成：
- `app/src/main/kotlin/.../MainActivity.kt`
- `app/build.gradle`（完整版本）
- `settings.gradle`
- `gradle/` wrapper 文件
- 资源文件（图标、主题等）

## FFI 插件

本插件使用 Flutter FFI 插件模式，无需额外的平台通道代码。
Rust 编译的动态库（`.so`）会通过 native assets 机制自动打包到 APK 中。

## 最低版本

- minSdk: 21
- compileSdk: 34
- Kotlin: 1.9.0
- AGP: 8.3.0
