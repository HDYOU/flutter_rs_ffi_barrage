# 弹幕演示资源目录

## 说明

本目录用于存放弹幕演示所需的表情图片等静态资源。

由于 Demo 主要通过 **Dart 代码程序化生成 RGBA 位图** 来演示表情功能
（在 `lib/main.dart` 中的 `_customEmojiBitmapCallback` 及相关生成函数），
本目录中的图片资源为可选补充。

## 表情注册方式

Demo 中演示了三种 Emoji 注册方式：

### 1. Flutter 位图注册（代码生成）
- **标识**: `[星星]`
- **方法**: `registerEmojiFromFlutterBitmap()`
- **说明**: 通过 Dart 代码在内存中生成 RGBA 位图，直接注册到 Rust 引擎。
  适用于动态生成表情或需要 Flutter 侧预渲染的场景。

### 2. 本地文件注册（可选）
- **标识**: `[爱心]`（示例）
- **方法**: `registerEmojiFromLocalPath()`
- **说明**: 将 PNG 图片放入 `assets/` 目录，运行时通过路径注册。
  适用于应用内预置的表情包。

### 3. 网络 URL 注册（可选）
- **标识**: `[火焰]`（示例）
- **方法**: `registerEmojiFromUrl()`
- **说明**: 由 Rust 侧异步下载并解码网络图片。
  适用于远程表情包或用户上传的头像等场景。

## 添加自定义表情图片

如需添加 PNG 表情图片进行测试：

1. 将 `.png` 文件放入本目录
2. 在 `pubspec.yaml` 中声明（已配置 `assets/` 目录）
3. 在代码中调用 `registerEmojiFromLocalPath()` 注册
   （注意：需要使用运行时的真实文件路径，而非 asset key）

## 推荐做法

对于 asset 中的图片，推荐先通过 Flutter 的 `rootBundle` 加载，
再使用 `registerEmojiFromFlutterBitmap()` 注册，这样可以避免
处理平台路径差异问题。
