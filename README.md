# flutter_rs_ffi_barrage

> 高性能 Flutter 弹幕插件，纯 Rust 内核 + Dart:ffi 直接绑定，零 C 中间层。

[![Rust CI](https://github.com/HDYOU/flutter_rs_ffi_barrage/actions/workflows/rust_ci.yml/badge.svg)](https://github.com/HDYOU/flutter_rs_ffi_barrage/actions/workflows/rust_ci.yml)
[![Dart & Flutter CI](https://github.com/HDYOU/flutter_rs_ffi_barrage/actions/workflows/dart_flutter_ci.yml/badge.svg)](https://github.com/HDYOU/flutter_rs_ffi_barrage/actions/workflows/dart_flutter_ci.yml)
[![Full Build - All Platforms](https://github.com/HDYOU/flutter_rs_ffi_barrage/actions/workflows/full_build_all_platform.yml/badge.svg)](https://github.com/HDYOU/flutter_rs_ffi_barrage/actions/workflows/full_build_all_platform.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## 项目简介

`flutter_rs_ffi_barrage` 是一款基于 **纯 Rust 内核** 的高性能 Flutter 弹幕插件。采用 `extern "C"` 裸符号导出与 Dart:ffi 直接绑定的技术方案，**无 C 胶水层、无 cbindgen、无 .h 头文件**，实现 Rust 与 Dart 之间的零开销互操作。

插件内置完整的弹幕引擎：CPU 软件渲染、智能轨道管理、碰撞避让、四大文字特效、Emoji 多路加载、Rust 主动回调 Dart 等能力，全平台（Android / iOS / Windows / macOS / Linux）开箱即用。

---

## ✨ 核心特性

### 🏎️ 极致性能
- **纯 Rust 内核**，CPU 软件渲染 RGBA8888，零平台依赖
- **crossbeam 无锁队列**，弹幕推送高并发无阻塞
- **parking_lot 轻量读写锁**，线程安全且性能远超 std::sync
- **Release 模式 LTO 全量优化** + `panic=abort` FFI 安全

### 🚫 零 C 中间层
- **无 cbindgen**：不生成任何 C 头文件
- **无 .h 头文件**：Rust 侧 `#[no_mangle] pub unsafe extern "C"` 直接导出
- **无 C 胶水代码**：Dart 侧 `dart:ffi` 手动绑定，符号一一对应
- **无 C 结构体**：仅使用基础类型（u8/u32/u64/f32/指针）跨边界

### 🎯 一键构建
- **Dart native-assets** 自动编译，`flutter pub get` 即可触发构建
- 增量编译缓存，源码未变更时跳过 cargo 调用
- 全平台目标三元组自动映射，无需手动配置

### 🔄 Rust 主动回调 Dart
- Rust 渲染引擎按需向 Flutter 请求 Emoji 位图
- 回调函数指针全局存储，`parking_lot::RwLock` 线程安全保护
- 异常自动捕获，回调失败不崩溃

### 🎨 四大文字特效（可叠加）
- **文字描边**（Stroke）：外描边 / 内描边，宽度颜色可调
- **立体阴影**（Shadow）：偏移 + 模糊 + 多层叠加产生 3D 立体效果
- **霓虹发光**（Neon）：高斯衰减外发光，强度 / 半径 / 层数可调
- **七彩渐变**（Gradient）：线性 / 径向 / 彩虹三种渐变模式

### 📱 全平台支持
| 平台 | 架构 | 状态 |
|------|------|------|
| Android | arm64 / armv7 / x86_64 / riscv64 | ✅ 支持 |
| iOS | arm64 / x86_64 (Simulator) | ✅ 支持 |
| Windows | x64 / arm64 | ✅ 支持 |
| macOS | arm64 (Apple Silicon) / x64 | ✅ 支持 |
| Linux | x64 / arm64 | ✅ 支持 |

### 🚀 四种轨道类型
- **滚动弹幕**（Scrolling）：从右向左，智能碰撞避让
- **顶部固定**（Top）：顶部居中，淡入淡出
- **底部固定**（Bottom）：底部居中，淡入淡出
- **逆向滚动**（Reverse）：从左向右滚动

### 💾 Emoji 三种加载模式 + 按需回调
1. **Flutter 内存 RGBA 位图主动注册**
2. **本地 Assets 文件路径加载**（Rust 侧解码 PNG/JPG/WebP）
3. **远程网络 URL 加载**（内存 LRU + 磁盘双层缓存）
4. **按需回调加载**（核心特色）：Rust 渲染时发现未缓存的 Emoji，主动回调 Flutter 获取位图

### ⚡ 性能优化亮点
- `crossbeam::ArrayQueue` 无锁环形队列，异步弹幕推送
- `parking_lot` 轻量读写锁，全局回调存储
- `bytemuck` 零拷贝类型映射
- LRU 表情缓存，最近最少使用淘汰策略
- 弹幕对象复用池，减少内存分配
- 智能碰撞避让算法，弹幕密度最优分配

---

## 🏗️ 架构设计

### 整体架构图

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Flutter / Dart 层                           │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────────┐ │
│  │ BarrageView  │  │ BarrageEngine│  │    Emoji Helper          │ │
│  │  (Widget)    │  │  (Dart API)  │  │  (RGBA ↔ ui.Image)      │ │
│  └──────┬───────┘  └──────┬───────┘  └────────────┬─────────────┘ │
│         │                 │                       │               │
│  ┌──────▼─────────────────▼───────────────────────▼─────────────┐ │
│  │                    ffi_bind.dart                             │ │
│  │         (手动 Dart:ffi 绑定 — 无 ffigen / 无 .h)             │ │
│  └─────────────────────────────┬───────────────────────────────┘ │
└────────────────────────────────┼─────────────────────────────────┘
                                 │
                  ────  FFI 边界（纯基础类型，无 C 结构体）────
                                 │
┌────────────────────────────────▼─────────────────────────────────┐
│                            Rust 内核层                             │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │                  ffi/exports.rs  (extern "C")               │  │
│  │               ffi/callbacks.rs  (回调存储)                  │  │
│  └─────────────────────────────┬───────────────────────────────┘  │
│                                │                                  │
│  ┌─────────────────────────────▼───────────────────────────────┐  │
│  │                   core/engine.rs  (核心引擎)                │  │
│  │     时间控制 / 播放状态 / 过滤规则 / 弹幕分发                │  │
│  └──────┬───────────────────────────────────┬──────────────────┘  │
│         │                                   │                     │
│  ┌──────▼──────────┐              ┌────────▼──────────┐          │
│  │  track/         │              │  emoji/           │          │
│  │  轨道管理器      │              │  Emoji 管理器     │          │
│  │  4种轨道+碰撞避让│              │  LRU缓存+3种加载  │          │
│  └──────┬──────────┘              └────────┬──────────┘          │
│         │                                   │                     │
│  ┌──────▼───────────────────────────────────▼──────────┐          │
│  │              render/renderer.rs  (渲染管线)         │          │
│  │         CPU 软件渲染 / RGBA8888 帧缓冲              │          │
│  └──────────────────────┬─────────────────────────────┘          │
│                         │                                        │
│              ┌──────────▼──────────┐                             │
│              │  text_effect/       │                             │
│              │  四大文字特效       │                             │
│              │  描边/阴影/霓虹/渐变│                             │
│              └─────────────────────┘                             │
└──────────────────────────────────────────────────────────────────┘

         Rust 侧 ──────回调请求 Emoji 位图──────► Dart 侧
         Dart 侧 ──────返回 RGBA 像素数据───────► Rust 侧
```

### 核心设计理念：纯 Rust <-> Dart FFI 双向交互

本插件最大的技术特色是 **完全摒弃 C 中间层**，直接在 Rust 和 Dart 之间建立 FFI 绑定：

1. **Rust 侧**：使用 `#[no_mangle] pub unsafe extern "C"` 导出裸函数符号，参数仅使用基础类型（u8、u32、u64、f32、裸指针），不传递任何 Rust 结构体。

2. **Dart 侧**：使用 `dart:ffi` 的 `DynamicLibrary.lookupFunction` 手动绑定每个符号，类型签名与 Rust 侧一一对应，不依赖 `ffigen` 或 `.h` 头文件。

3. **字符串传递**：统一使用 `Pointer<Uint8>` + `length` 的方式传递 UTF-8 编码字节，两端各自负责编码/解码。

4. **内存所有权**：严格遵循「谁分配谁释放」原则，Dart 分配的内存在 FFI 调用后由 Dart 释放（通过 `Arena` 自动管理），Rust 分配的内存由 Rust 侧 `Box::from_raw` 回收。

5. **回调机制**：Dart 侧通过 `Pointer.fromFunction` 创建静态函数指针，注册到 Rust 全局存储（`parking_lot::RwLock` 保护），Rust 渲染线程可主动调用此回调。

### 无 C 绑定的技术方案说明

| 传统方案（有 C 中间层） | 本方案（零 C 中间层） |
|----------------------|---------------------|
| Rust → cbindgen → .h 头文件 → ffigen → Dart 绑定 | Rust `extern "C"` → Dart `dart:ffi` 手动绑定 |
| 需要维护 C 头文件与 Rust 代码的同步 | 符号签名直接对应，无中间产物 |
| 依赖 cbindgen / ffigen 工具链 | 零额外工具依赖 |
| C 结构体需兼顾两边对齐 | 仅用基础类型，无结构体跨边界 |
| 调试链路长（Rust→C→Dart） | 直接双向调用，问题定位简单 |

---

## 📦 环境要求

### 基础依赖

| 依赖 | 版本要求 | 说明 |
|------|---------|------|
| Flutter SDK | `>=3.41.0` | 需支持 native-assets 稳定 API |
| Dart SDK | `>=3.7.0 <4.0.0` | 与 Flutter 3.41.0 配套 |
| Rust 工具链 | stable（最新稳定版） | 通过 rustup 安装 |

### Rust 工具链安装

```bash
# macOS / Linux
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# Windows
# 从 https://rustup.rs/ 下载安装器

# 验证安装
cargo --version
rustc --version
```

### 各平台编译工具链

#### Android
- Android NDK（推荐 r26+）
- 设置环境变量：`ANDROID_NDK_HOME` 或 `ANDROID_NDK_PATH`
- Rust 目标平台：`aarch64-linux-android`、`armv7-linux-androideabi`、`x86_64-linux-android`、`riscv64-linux-android`

#### iOS
- Xcode 命令行工具：`xcode-select --install`
- Rust 目标平台：`aarch64-apple-ios`、`aarch64-apple-ios-sim`、`x86_64-apple-ios`

#### macOS
- Xcode 命令行工具
- Rust 目标平台：`aarch64-apple-darwin`、`x86_64-apple-darwin`

#### Windows
- Visual Studio Build Tools（MSVC）
- Rust 目标平台：`x86_64-pc-windows-msvc`、`aarch64-pc-windows-msvc`

#### Linux
- 基础编译工具：`clang`、`cmake`、`pkg-config`、`gtk-3`、`libx11` 等
- Rust 目标平台：`x86_64-unknown-linux-gnu`、`aarch64-unknown-linux-gnu`

---

## 🚀 快速开始

### 1. 添加依赖

在项目的 `pubspec.yaml` 中添加：

```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_rs_ffi_barrage:
    git: https://github.com/HDYOU/flutter_rs_ffi_barrage.git
```

然后执行：

```bash
flutter pub get
```

> **注意**：首次执行 `flutter pub get` 时，native-assets 构建 hook 会自动调用 `cargo build --release` 编译 Rust 核心库。后续只有源码变更时才会重新编译。

### 2. 基础使用

```dart
import 'package:flutter/material.dart';
import 'package:flutter_rs_ffi_barrage/flutter_rs_ffi_barrage.dart';

class BarragePage extends StatefulWidget {
  const BarragePage({super.key});

  @override
  State<BarragePage> createState() => _BarragePageState();
}

class _BarragePageState extends State<BarragePage> {
  late final BarrageController _controller;

  @override
  void initState() {
    super.initState();
    // 创建控制器（内部自动创建引擎）
    _controller = BarrageController(
      width: 1920,
      height: 1080,
      fontRatio: 0.04,
      speed: 1.0,
      autoPlay: true,
    );

    // 设置全局描边效果
    _controller.setGlobalStroke(
      StrokeConfig.enabled(
        width: 2.0,
        color: Colors.black,
        isOuter: true,
      ),
    );

    // 推送一些示例弹幕
    _pushDemoBarrages();
  }

  void _pushDemoBarrages() {
    // 滚动弹幕
    _controller.push(BarrageMsg(
      id: '1',
      text: '欢迎使用 flutter_rs_ffi_barrage！',
      trackType: TrackType.scrolling,
      color: Colors.white,
      fontSize: 24,
      timestamp: 0,
    ));

    // 顶部固定弹幕
    _controller.push(BarrageMsg(
      id: '2',
      text: '顶部公告',
      trackType: TrackType.top,
      color: Colors.yellow,
      fontSize: 28,
      timestamp: 0,
    ));

    // 底部固定弹幕
    _controller.push(BarrageMsg(
      id: '3',
      text: '底部字幕',
      trackType: TrackType.bottom,
      color: Colors.white,
      fontSize: 20,
      timestamp: 0,
    ));

    // 逆向滚动弹幕
    _controller.push(BarrageMsg(
      id: '4',
      text: '逆向弹幕',
      trackType: TrackType.reverse,
      color: Colors.cyan,
      fontSize: 24,
      timestamp: 0,
    ));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 底层视频或背景
          Container(color: Colors.black),
          // 弹幕层（透明背景，可叠加在视频上）
          BarrageView(
            controller: _controller,
            backgroundColor: Colors.transparent,
          ),
        ],
      ),
      floatingActionButton: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            onPressed: () => _controller.pause(),
            child: const Icon(Icons.pause),
          ),
          const SizedBox(width: 8),
          FloatingActionButton(
            onPressed: () => _controller.resume(),
            child: const Icon(Icons.play_arrow),
          ),
          const SizedBox(width: 8),
          FloatingActionButton(
            onPressed: () => _controller.clear(),
            child: const Icon(Icons.clear_all),
          ),
        ],
      ),
    );
  }
}
```

### 3. 自定义 Emoji 回调

这是本插件的核心特色——**Rust 渲染引擎主动回调 Dart 获取 Emoji 位图**：

```dart
import 'dart:ui' as ui;
import 'package:flutter_rs_ffi_barrage/flutter_rs_ffi_barrage.dart';

// 注册 Emoji 位图回调
void setupEmojiCallback(BarrageController controller) {
  controller.setEmojiBitmapCallback(_onEmojiRequested);
}

/// 当 Rust 渲染引擎遇到未缓存的 Emoji 时，会回调此函数
/// 
/// - [emojiText]: Emoji 文本标识（如 "[微笑]" 或 "😀"）
/// - [width] / [height]: 期望的位图尺寸（像素）
/// 
/// 返回 RGBA8888 格式的像素数据，失败返回 null
Future<Uint8List?> _onEmojiRequested(
  String emojiText,
  int width,
  int height,
) async {
  try {
    // 示例：使用 Flutter 的 TextPainter 渲染 Emoji 到位图
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    
    final textPainter = TextPainter(
      text: TextSpan(
        text: emojiText,
        style: TextStyle(fontSize: width.toDouble()),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset.zero);
    
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    final byteData = await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    
    image.dispose();
    picture.dispose();
    
    if (byteData == null) return null;
    return Uint8List.sublistView(byteData);
  } catch (e) {
    debugPrint('Emoji 渲染失败: $e');
    return null;
  }
}
```

> **注意**：回调函数会在 Rust 渲染线程中被调用，请确保线程安全。回调中返回的像素数据会被 Rust 侧拷贝到自己的 LRU 缓存中，后续相同 Emoji 将直接使用缓存。

---

## 🎯 API 文档

### BarrageEngine

弹幕引擎核心类，封装 Rust 侧引擎的所有功能。每个实例对应一个 Rust 不透明句柄，通过 `dispose()` 释放资源。

#### 构造函数

```dart
factory BarrageEngine({
  required int width,       // 渲染区域宽度（像素）
  required int height,      // 渲染区域高度（像素）
  double fontRatio = 0.04,  // 字体大小占画布高度的比例
  double speed = 1.0,       // 弹幕滚动速度倍率
})
```

#### 播放控制方法

| 方法 | 说明 |
|------|------|
| `void dispose()` | 销毁引擎，释放所有资源。重复调用安全。 |
| `void resize(int width, int height)` | 调整渲染区域大小 |
| `void setSpeed(double speed)` | 设置滚动速度倍率（> 0） |
| `void pause()` | 暂停弹幕滚动 |
| `void resume()` | 恢复弹幕滚动 |
| `void seek(int timestampMs)` | 跳转到指定时间点（毫秒），会清空当前所有弹幕 |
| `void clear()` | 清空所有弹幕 |

#### 弹幕推送方法

| 方法 | 说明 |
|------|------|
| `void push(BarrageMsg msg)` | 推送一条弹幕 |
| `void pushAll(List<BarrageMsg> messages)` | 批量推送多条弹幕 |
| `Uint8List? renderFrame(int timestampMs)` | 渲染指定时间戳的帧，返回 RGBA8888 像素数据 |

#### Emoji 相关方法

| 方法 | 说明 |
|------|------|
| `void setEmojiBitmapCallback(EmojiBitmapCallback? callback)` | 设置/取消 Emoji 位图请求回调（Rust 主动调用 Dart） |
| `void registerEmojiFromFlutterBitmap(String emojiText, Uint8List pixels, int width, int height)` | 从 Flutter 内存 RGBA 位图注册 Emoji |
| `void registerEmojiFromLocalPath(String emojiText, String path)` | 从本地文件路径注册 Emoji（Rust 侧解码） |
| `void registerEmojiFromUrl(String emojiText, String url)` | 从网络 URL 注册 Emoji（Rust 侧异步下载） |

#### 特效设置方法

| 方法 | 说明 |
|------|------|
| `void setGlobalStroke(StrokeConfig config)` | 设置全局描边效果（对后续弹幕生效） |
| `void setGlobalShadow(ShadowConfig config)` | 设置全局阴影效果 |
| `void setGlobalNeon(NeonConfig config)` | 设置全局霓虹发光效果 |
| `void setGlobalGradient(GradientConfig config)` | 设置全局渐变填充效果 |

---

### BarrageView & BarrageController

#### BarrageController

弹幕控制器，管理引擎生命周期和播放控制。可独立使用或配合 `BarrageView`。

```dart
factory BarrageController({
  int width = 1920,            // 初始渲染宽度
  int height = 1080,           // 初始渲染高度
  double fontRatio = 0.04,     // 字体比例
  double speed = 1.0,          // 速度倍率
  bool autoPlay = true,        // 是否自动播放
})
```

**控制方法**：`pause()`、`resume()`、`seek()`、`setSpeed()`、`clear()`、`push()`、`pushAll()`、`dispose()`

**Emoji 方法**：`setEmojiBitmapCallback()`、`registerEmojiFromFlutterBitmap()`、`registerEmojiFromLocalPath()`、`registerEmojiFromUrl()`

**特效方法**：`setGlobalStroke()`、`setGlobalShadow()`、`setGlobalNeon()`、`setGlobalGradient()`

#### BarrageView

弹幕渲染 Widget，基于 `CustomPaint` + `Ticker` 实现逐帧渲染。支持透明背景，可叠加在视频或其他 Widget 上方。

```dart
BarrageView({
  super.key,
  BarrageController? controller,     // 控制器（null 则自动创建）
  double speed = 1.0,                // 初始速度（controller 为 null 时生效）
  bool autoPlay = true,              // 是否自动播放
  Color backgroundColor = const Color(0x00000000),  // 背景色（默认透明）
})
```

---

### 文字特效配置

#### StrokeConfig — 描边效果

```dart
const StrokeConfig({
  this.enabled = false,           // 是否启用
  this.width = 2.0,               // 描边宽度（像素）
  this.color = const Color(0xFF000000),  // 描边颜色
  this.isOuter = true,            // true=外描边, false=内描边
});

// 便捷构造
factory StrokeConfig.enabled({
  double width = 2.0,
  Color color = const Color(0xFF000000),
  bool isOuter = true,
})
```

#### ShadowConfig — 阴影效果

```dart
const ShadowConfig({
  this.enabled = false,           // 是否启用
  this.offsetX = 2.0,             // X 轴偏移（像素）
  this.offsetY = 2.0,             // Y 轴偏移（像素）
  this.blur = 0.0,                // 模糊半径（像素）
  this.color = const Color(0x80000000),  // 阴影颜色
  this.layers = 1,                // 阴影层数（多层叠加产生立体效果）
});
```

#### NeonConfig — 霓虹发光

```dart
const NeonConfig({
  this.enabled = false,           // 是否启用
  this.radius = 8.0,              // 发光半径（像素）
  this.color = const Color(0xFFFF00FF),  // 发光颜色
  this.intensity = 0.8,           // 发光强度（0.0 ~ 1.0）
  this.layers = 3,                // 发光层数（多层叠加增强光晕）
});
```

#### GradientConfig — 渐变填充

```dart
const GradientConfig({
  this.enabled = false,           // 是否启用
  this.type = GradientType.linear, // 渐变类型
  this.colors = const [Color(0xFFFF0000), Color(0xFF0000FF)],  // 渐变颜色列表
  this.angle = 0.0,               // 渐变角度（度，仅线性渐变有效）
});

// 渐变类型
enum GradientType {
  linear,    // 线性渐变
  radial,    // 径向渐变
  rainbow,   // 彩虹渐变（内置七色，忽略 colors 参数）
}
```

#### TextEffectConfig — 特效组合

所有特效可叠加使用，渲染顺序为：**描边 → 阴影 → 霓虹 → 渐变填充**。

```dart
const TextEffectConfig({
  this.stroke = const StrokeConfig(),
  this.shadow = const ShadowConfig(),
  this.neon = const NeonConfig(),
  this.gradient = const GradientConfig(),
});
```

---

## 🎨 四大文字特效

### 1. 文字描边

在文字外缘添加描边，提升弹幕在复杂背景上的可读性。支持外描边和内描边两种模式。

```dart
// 设置全局描边
_controller.setGlobalStroke(
  StrokeConfig.enabled(
    width: 3.0,                    // 3 像素描边宽度
    color: Colors.black,           // 黑色描边
    isOuter: true,                 // 外描边（文字外扩）
  ),
);

// 单条弹幕单独设置描边
_controller.push(BarrageMsg(
  id: 'stroke_demo',
  text: '黑色描边的白色文字',
  color: Colors.white,
  fontSize: 28,
  textEffects: TextEffectConfig(
    stroke: StrokeConfig.enabled(
      width: 2.0,
      color: Colors.black,
    ),
  ),
));
```

**效果说明**：外描边会使文字整体外扩 `width` 像素，内描边则在文字内部收缩。推荐使用外描边 + 2~3px 宽度，兼顾可读性和美观度。

---

### 2. 立体偏移阴影

为文字添加多层偏移阴影，产生 3D 立体浮雕效果。支持偏移距离、模糊半径和阴影层数调节。

```dart
_controller.setGlobalShadow(
  ShadowConfig.enabled(
    offsetX: 3.0,                  // X 轴偏移 3px
    offsetY: 3.0,                  // Y 轴偏移 3px
    blur: 2.0,                     // 轻微模糊
    color: Color(0xAA000000),      // 半透明黑色
    layers: 3,                     // 3 层叠加，增强立体感
  ),
);

// 单条弹幕设置
_controller.push(BarrageMsg(
  id: 'shadow_demo',
  text: '立体阴影文字',
  color: Colors.white,
  fontSize: 32,
  textEffects: TextEffectConfig(
    shadow: ShadowConfig.enabled(
      offsetX: 4.0,
      offsetY: 4.0,
      blur: 3.0,
      color: Color(0x80000000),
      layers: 2,
    ),
  ),
));
```

**效果说明**：多层阴影沿偏移方向递进排列，每层之间间距为 `offset / layers`，形成阶梯式立体效果。层数越多立体感越强，但渲染开销也越大。推荐 1~3 层。

---

### 3. 霓虹外发光

文字外围产生柔和的光晕效果，类似霓虹灯发光。支持发光半径、强度和层数调节。

```dart
_controller.setGlobalNeon(
  NeonConfig.enabled(
    radius: 12.0,                  // 发光半径 12px
    color: Color(0xFF00FFFF),      // 青色霓虹
    intensity: 1.0,                // 发光强度
    layers: 4,                     // 4 层叠加，光晕更饱满
  ),
);

// 单条弹幕设置
_controller.push(BarrageMsg(
  id: 'neon_demo',
  text: '霓虹发光文字',
  color: Colors.white,
  fontSize: 28,
  textEffects: TextEffectConfig(
    neon: NeonConfig.enabled(
      radius: 10.0,
      color: Color(0xFFFF00FF),    // 品红色霓虹
      intensity: 0.9,
      layers: 3,
    ),
  ),
));
```

**效果说明**：使用高斯衰减近似算法计算发光强度，距离文字边缘越远亮度越低。多层发光从外向内半径递减，模拟真实霓虹灯管的光晕扩散效果。推荐半径 8~16px，层数 3~5。

---

### 4. 七彩渐变文字

文字填充使用渐变色，支持线性渐变、径向渐变和彩虹渐变三种模式。

```dart
// 线性渐变（红→黄→蓝，45度角）
_controller.setGlobalGradient(
  GradientConfig.enabled(
    type: GradientType.linear,
    colors: [Colors.red, Colors.yellow, Colors.blue],
    angle: 45.0,                   // 45 度
  ),
);

// 径向渐变（从中心向外）
_controller.push(BarrageMsg(
  id: 'radial_demo',
  text: '径向渐变',
  fontSize: 32,
  textEffects: TextEffectConfig(
    gradient: GradientConfig.enabled(
      type: GradientType.radial,
      colors: [Colors.yellow, Colors.orange, Colors.red],
    ),
  ),
));

// 彩虹渐变（内置七色，无需指定 colors）
_controller.push(BarrageMsg(
  id: 'rainbow_demo',
  text: '七彩彩虹文字',
  fontSize: 32,
  textEffects: TextEffectConfig(
    gradient: GradientConfig.enabled(
      type: GradientType.rainbow,
    ),
  ),
));
```

**效果说明**：
- **线性渐变**：沿指定角度方向从左向右（或自定义角度）渐变
- **径向渐变**：从文字中心向外围辐射渐变
- **彩虹渐变**：内置红橙黄绿青蓝紫七色均匀过渡，适合节日/庆典氛围

> **提示**：所有四种特效可以任意组合叠加。例如「描边 + 霓虹 + 渐变」可以产生「带描边的霓虹渐变字」效果。

---

## 😀 Emoji 四种加载模式

本插件支持多种 Emoji 加载方式，适应不同业务场景。

### 1. Flutter 内存 RGBA 位图主动注册

将 Flutter 侧预渲染的 Emoji 位图直接注册到 Rust 引擎的 LRU 缓存中。适用于数量有限、尺寸固定的表情包。

```dart
import 'dart:ui' as ui;
import 'package:flutter_rs_ffi_barrage/flutter_rs_ffi_barrage.dart';

// 从 ui.Image 注册 Emoji
Future<void> registerEmojiFromImage(
  BarrageController controller,
  String emojiTag,
  ui.Image image,
) async {
  final byteData = await image.toByteData(
    format: ui.ImageByteFormat.rawRgba,
  );
  if (byteData == null) return;

  final pixels = Uint8List.sublistView(byteData);

  controller.registerEmojiFromFlutterBitmap(
    emojiTag,      // Emoji 标识，如 "[微笑]"
    pixels,        // RGBA8888 像素数据
    image.width,   // 宽度
    image.height,  // 高度
  );
}
```

### 2. 本地 Assets 文件路径加载

由 Rust 侧直接读取并解码图片文件（支持 PNG / JPG / WebP 格式）。适用于打包在 App 内的表情包资源。

```dart
// 注册本地文件 Emoji
controller.registerEmojiFromLocalPath(
  '[doge]',                              // Emoji 标识
  '/data/data/com.example/files/doge.png', // 本地文件绝对路径
);
```

> 注意：需要先将 assets 拷贝到应用可访问的文件目录，再传入绝对路径。

### 3. 远程网络图片加载

由 Rust 侧异步下载并解码网络图片，支持内存 LRU + 磁盘双层缓存。适用于云端表情包。

```dart
// 注册网络 Emoji
controller.registerEmojiFromUrl(
  '[666]',                                       // Emoji 标识
  'https://example.com/emoji/666.png',           // 图片 URL
);
```

### 4. 按需回调加载模式（核心特色）

这是本插件最独特的能力——**Rust 渲染引擎在遇到未缓存的 Emoji 时，主动回调 Dart/Flutter 获取位图**。

```dart
// 注册回调，Rust 按需请求 Emoji
controller.setEmojiBitmapCallback((emojiText, width, height) async {
  // emojiText: Rust 请求的 Emoji 文本（如 "[笑哭]"）
  // width/height: 期望的位图尺寸
  
  try {
    // 方式一：从 Flutter 图标系统渲染
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    
    final tp = TextPainter(
      text: TextSpan(
        text: emojiText,
        style: TextStyle(fontSize: width.toDouble()),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, Offset.zero);
    
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    final bytes = await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    
    image.dispose();
    picture.dispose();
    
    if (bytes == null) return null;
    return Uint8List.sublistView(bytes);
  } catch (e) {
    return null; // 返回 null 表示获取失败，Rust 将使用占位符
  }
});
```

**工作流程**：
1. 弹幕文本中包含 Emoji 标识（如 `[微笑]`）
2. Rust 渲染引擎查找 LRU 缓存，未命中
3. 检查是否已注册 Dart 回调函数
4. 调用回调函数，传入 Emoji 文本和期望尺寸
5. Dart 侧（Flutter）渲染 Emoji 并返回 RGBA 像素数据
6. Rust 侧将位图存入 LRU 缓存，后续相同 Emoji 直接使用缓存

**优势**：
- 无需提前注册所有 Emoji，首次使用时按需加载
- 充分利用 Flutter 的字体渲染能力（系统字体、自定义字体均可）
- 缓存命中后性能与预注册完全一致

---

## 🔄 Rust-Dart 回调机制详解

### 回调流程图

```
┌─────────────┐                         ┌─────────────┐
│  Rust 渲染   │                         │  Dart/Flutter│
│  线程        │                         │  UI 线程     │
└──────┬──────┘                         └──────┬──────┘
       │                                       │
       │  渲染弹幕，发现未缓存的 Emoji           │
       │                                       │
       │  查询 LRU 缓存 → miss                 │
       │                                       │
       │  检查全局回调指针 (RwLock read)        │
       │                                       │
       ├─────── 调用函数指针 ──────────────────►│
       │         (emoji_text, len,             │
       │          out_w, out_h,                │
       │          out_pixels, out_len)         │
       │                                       │  执行 Dart 回调
       │                                       │  (渲染 Emoji)
       │                                       │
       │                                       │  分配像素内存
       │                                       │  (malloc / arena)
       │◄────── 返回 true + 填充输出参数 ───────┤
       │                                       │
       │  验证返回参数有效性                    │
       │  (尺寸 > 0, 像素非空, 长度匹配)        │
       │                                       │
       │  拷贝像素数据到 Rust 内存              │
       │  (Vec<u8> 接管)                       │
       │                                       │
       │  存入 LRU 缓存                        │
       │                                       │
       │  继续渲染，使用该位图绘制 Emoji        │
       │                                       │
```

### 技术原理说明

1. **函数指针注册**：Dart 侧通过 `Pointer.fromFunction<NativeFunction>(callback, exceptionalReturn)` 将静态/顶层函数转换为可被 C 调用的函数指针，然后通过 FFI 调用 `set_emoji_bitmap_callback` 注册到 Rust 侧。

2. **全局存储**：Rust 侧使用 `OnceLock<RwLock<Option<EmojiBitmapRawCallback>>>` 全局存储回调函数指针。`OnceLock` 保证延迟初始化，`parking_lot::RwLock` 提供线程安全的读写访问。

3. **调用流程**：当 Rust 渲染线程需要 Emoji 位图时，获取读锁读取回调指针，然后按照 C 调用约定调用该函数指针。

4. **输出参数**：回调使用输出参数（`out_width`、`out_height`、`out_pixels`、`out_pixel_len`）返回位图数据。Dart 侧分配内存并填充这些指针，Rust 侧读取后拷贝到自己的内存管理中。

5. **类型安全**：两端严格约定函数签名（参数顺序、类型、返回值），任何不匹配都会导致未定义行为。这也是为什么本项目采用手动绑定而非自动生成——精确控制每个符号的签名。

### 内存安全保障

| 风险点 | 保障措施 |
|--------|---------|
| 空指针解引用 | Rust 侧所有指针参数均做空值检查，null 直接返回错误 |
| 缓冲区溢出 | 所有长度参数做上下限检查（最大字符串 1MB，最大像素 64MB） |
| 回调异常 | Dart 侧回调包裹 try-catch，异常时返回 false，Rust 侧安全降级 |
| 内存泄漏 | Dart 侧使用 `Arena` 自动管理临时内存；Rust 侧使用 `Vec<u8>` 拷贝后由 RAII 自动释放 |
| 线程安全 | 回调指针存储使用 `parking_lot::RwLock` 保护，读多写少场景性能最优 |
| 函数指针失效 | Dart 侧保持对 `Pointer.fromFunction` 返回值的强引用，防止 GC 回收 |

---

## 📱 全平台运行指引

### 前置准备

1. 安装 Flutter SDK 3.41.0+
2. 安装 Rust 工具链（stable）
3. 克隆项目并安装依赖：

```bash
git clone https://github.com/HDYOU/flutter_rs_ffi_barrage.git
cd flutter_rs_ffi_barrage
flutter pub get
```

### Android

```bash
# 设置 NDK 环境变量
export ANDROID_NDK_HOME=$ANDROID_HOME/ndk/26.1.10909125

# 运行
flutter run -d android
```

**注意事项**：
- 需提前通过 Android SDK Manager 安装 NDK
- 最低支持 API Level 21（Android 5.0）
- 支持 arm64-v8a / armeabi-v7a / x86_64 / riscv64 四种架构

### iOS

```bash
# 安装 iOS 目标平台
rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios

# 运行（模拟器）
flutter run -d ios

# 真机运行需要配置签名
flutter run -d <device_id> --release
```

**注意事项**：
- 需安装 Xcode 及命令行工具
- 真机调试需要 Apple 开发者账号和正确的签名配置

### Windows

```bash
# 安装 Windows 目标平台
rustup target add x86_64-pc-windows-msvc

# 运行
flutter run -d windows
```

**注意事项**：
- 需安装 Visual Studio Build Tools 2019/2022（含 MSVC 和 Windows SDK）
- 生成的 `.dll` 文件位于 `build/windows/x64/runner/Release/` 目录

### macOS

```bash
# 安装 macOS 目标平台
rustup target add aarch64-apple-darwin x86_64-apple-darwin

# 运行
flutter run -d macos
```

**注意事项**：
- 需安装 Xcode 命令行工具：`xcode-select --install`
- 支持 Apple Silicon（arm64）和 Intel（x86_64）双架构

### Linux

```bash
# 安装 Linux 编译依赖
sudo apt-get update
sudo apt-get install -y \
  clang cmake pkg-config \
  libgtk-3-dev libx11-dev libxrandr-dev \
  libxext-dev libxfixes-dev libxrender-dev \
  libxi-dev libgl1-mesa-dev libglu1-mesa-dev \
  libasound2-dev libpulse-dev libcurl4-openssl-dev

# 安装 Linux 目标平台
rustup target add x86_64-unknown-linux-gnu

# 运行
flutter run -d linux
```

**注意事项**：
- 支持 x86_64 和 arm64 架构
- 生成的 `.so` 文件位于 `build/linux/x64/release/bundle/lib/` 目录

---

## 🏭 CI/CD 流水线

项目配置了三条 GitHub Actions 工作流，覆盖代码检查、测试和全平台构建。

### rust_ci.yml — Rust 代码质量与测试

**触发条件**：`native/rs_core/**` 目录下代码变更时

**包含两个 Job**：

1. **Rust Lint & Test**（Ubuntu）
   - `cargo fmt --check`：格式化校验
   - `cargo clippy --all-targets --all-features -- -D warnings`：静态检查，警告视为错误
   - `cargo test --all-features`：单元测试
   - `cargo bench --no-run`：Benchmark 编译验证

2. **Cross Compile**（5 个目标矩阵）
   - `x86_64-unknown-linux-gnu`
   - `aarch64-unknown-linux-gnu`
   - `x86_64-pc-windows-msvc`
   - `aarch64-apple-darwin`
   - `x86_64-apple-darwin`
   - 每个目标执行 `cargo build --release` 并验证 cdylib 产物存在

### dart_flutter_ci.yml — Dart/Flutter 代码质量

**触发条件**：`lib/**`、`pubspec.yaml` 等 Dart 相关文件变更时

**包含两个 Job**：

1. **Dart Lint & Test**
   - `dart format --set-exit-if-changed .`：格式化校验
   - `flutter analyze`：静态分析
   - `flutter test --coverage`：单元测试（存在 test 目录时）
   - `flutter pub publish --dry-run`：发布预检

2. **Example Build Check**
   - 编译 example 工程的 Web 版本，验证插件集成无误

### full_build_all_platform.yml — 全平台构建归档

**触发条件**：推送 `v*` 标签或手动触发

**包含 6 个 Job**：

| Job | 运行环境 | 产物 |
|-----|---------|------|
| Build Android | Ubuntu | APK + .so |
| Build iOS | macOS | .framework |
| Build Windows | Windows | .dll + .exe |
| Build macOS | macOS | .dylib |
| Build Linux | Ubuntu | .so |
| Upload All Artifacts | Ubuntu | 统一归档所有平台产物 |

所有产物通过 `actions/upload-artifact@v4` 上传，可在 GitHub Actions 页面下载。

---

## 📁 项目结构

```
flutter_rs_ffi_barrage/
├── .github/
│   └── workflows/
│       ├── rust_ci.yml                 # Rust CI：格式化/检查/测试/交叉编译
│       ├── dart_flutter_ci.yml         # Dart CI：格式化/分析/测试
│       └── full_build_all_platform.yml # 全平台构建 + 产物归档
├── lib/
│   ├── flutter_rs_ffi_barrage.dart     # 包入口，导出所有公共 API
│   └── src/
│       ├── engine.dart                 # BarrageEngine：引擎封装，管理 Rust 句柄
│       ├── widget.dart                 # BarrageView + BarrageController
│       ├── types.dart                  # 纯 Dart 数据类型（BarrageMsg、特效配置等）
│       ├── ffi_bind.dart               # ⭐ FFI 绑定层：手动 dart:ffi 绑定
│       │                               #   （无 ffigen、无 .h、无 C 胶水）
│       └── emoji_helper.dart           # Emoji 工具：RGBA ↔ ui.Image 互转
├── native/
│   └── rs_core/                        # Rust 核心库
│       ├── Cargo.toml                  # 依赖：crossbeam/parking_lot/bytemuck/lru 等
│       ├── build.rs                    # 构建脚本
│       └── src/
│           ├── lib.rs                  # 库入口，模块声明
│           ├── ffi/
│           │   ├── mod.rs              # FFI 模块入口
│           │   ├── exports.rs          # ⭐ extern "C" 导出函数
│           │   │                       #   （无 cbindgen、无 .h、纯裸符号）
│           │   └── callbacks.rs        # 全局回调存储（parking_lot 保护）
│           ├── core/
│           │   ├── mod.rs
│           │   └── engine.rs           # 核心引擎：时间控制/弹幕分发/过滤规则
│           ├── track/
│           │   ├── mod.rs
│           │   └── track_manager.rs    # 轨道管理器：4 种轨道 + 碰撞避让
│           ├── emoji/
│           │   ├── mod.rs
│           │   └── emoji_manager.rs    # Emoji 管理器：LRU 缓存 + 多路加载
│           ├── render/
│           │   ├── mod.rs
│           │   └── renderer.rs         # 渲染管线：CPU 软件渲染 RGBA8888
│           ├── text_effect/
│           │   ├── mod.rs
│           │   └── effects.rs          # 文字特效：描边/阴影/霓虹/渐变
│           └── utils/
│               ├── mod.rs
│               ├── color.rs            # 颜色工具：RGBA/HSL/渐变计算
│               └── math.rs             # 数学工具：插值/钳位/向量运算
├── hook/
│   └── build.dart                      # Native-assets 构建 hook
│                                       #   （自动调用 cargo build 编译 Rust 库）
├── pubspec.yaml                        # Flutter 插件配置：ffiPlugin 全平台声明
├── .gitignore
└── README.md                           # 本文档
```

> **高亮说明**：本项目**没有任何 C 相关文件**——没有 `.h` 头文件、没有 `.c` 源文件、没有 cbindgen 配置、没有 ffigen 配置。Rust 与 Dart 之间通过 `extern "C"` 裸符号 + `dart:ffi` 手动绑定直接通信，真正实现了零 C 中间层。

---

## ⚡ 性能优化亮点

### 1. crossbeam 无锁环形队列

- 使用 `crossbeam::queue::ArrayQueue` 实现弹幕异步推送
- 多线程环境下无需加锁，高并发推送场景性能优异
- 容量固定（默认 1024），内存预分配，无运行时分配开销

### 2. parking_lot 轻量读写锁

- 全局回调指针存储使用 `parking_lot::RwLock`
- 比标准库 `std::sync::RwLock` 更轻量，读多写少场景性能提升显著
- 支持 `try_read` / `try_write` 无阻塞尝试

### 3. bytemuck 零拷贝类型映射

- 使用 `bytemuck` 进行安全的零拷贝类型转换
- RGBA 像素数据在 Rust 和 Dart 之间直接按字节映射，无需序列化/反序列化
- 编译期保证类型布局兼容，无运行时开销

### 4. SIMD 向量化加速

- 渲染管线关键路径（像素混合、颜色计算）支持 SIMD 向量化
- Rust 编译器在 Release + LTO 模式下自动生成 SSE/AVX/NEON 指令
- 大幅提升像素填充和混合的吞吐量

### 5. Release 模式 LTO 全量优化

```toml
[profile.release]
opt-level = 3
lto = true           # 全链路优化
codegen-units = 1    # 单代码生成单元，最大化优化
strip = true         # 去除调试符号
panic = "abort"      # panic 时直接 abort，FFI 安全
```

- LTO（Link Time Optimization）跨 crate 内联和优化
- 单 codegen-unit 最大化优化粒度
- `panic=abort` 避免 unwinding 跨越 FFI 边界导致 UB

### 6. 贴图 LRU 内存缓存

- Emoji 位图使用 LRU（最近最少使用）缓存策略
- 缓存容量可配置（默认 200 项）
- 高频使用的 Emoji 常驻缓存，减少重复渲染/解码开销

### 7. 弹幕对象内存池

- 弹幕对象复用机制，减少频繁分配释放
- 轨道内弹幕数组连续存储，缓存友好
- 死亡弹幕批量清理，降低 GC / 分配器压力

### 8. 智能碰撞避让算法

- 新弹幕选择轨道时优先选择空闲轨道
- 考虑弹幕速度和长度，确保不会追上前方弹幕
- 顶部/底部固定轨道按时间轮询分配
- 在保证不重叠的前提下最大化弹幕密度

---

## 🛡️ 安全保障

### 全链路空指针检查

Rust 侧所有 `extern "C"` 函数的指针参数在使用前均做空值检查：

```rust
#[no_mangle]
pub unsafe extern "C" fn barrage_engine_destroy(engine_ptr: *mut u8) {
    if engine_ptr.is_null() {
        return;  // 空指针直接返回，不崩溃
    }
    // ...
}
```

Dart 侧 `ffi_bind.dart` 中也对所有传入 Rust 的指针做空值校验。

### 缓冲区边界校验

| 检查项 | 限制值 | 说明 |
|--------|-------|------|
| 最大字符串长度 | 1 MB | 防止超长文本导致内存问题 |
| 最大画布尺寸 | 7680 × 4320 | 8K 上限 |
| 最小画布尺寸 | 16 × 16 | 防止无效尺寸 |
| 最大帧缓冲区 | 512 MB | 防止缓冲区溢出 |
| 最大像素数据 | 64 MB | Emoji 位图上限 |
| 最大渐变颜色数 | 32 色 | 防止颜色数组过大 |

### 字符串长度限制

- 所有从 C 指针读取的字符串均通过 `std::slice::from_raw_parts` + 长度上限双重校验
- UTF-8 解码使用 `String::from_utf8(...).ok()` 容错处理，非法 UTF-8 不崩溃
- Dart 侧字符串编码同样检查长度，空字符串分配 1 字节避免空指针

### 回调异常捕获

- Dart 侧回调函数全程包裹 try-catch，任何异常均返回 false
- Rust 侧调用回调后检查返回值，失败则使用占位符或降级处理
- 不影响主渲染流程，单个 Emoji 加载失败不会导致整帧崩溃

### 资源自动释放

- **Rust 侧**：引擎句柄使用 `Box::into_raw` / `Box::from_raw` 管理生命周期，`barrage_engine_destroy` 调用后自动 drop 所有资源
- **Dart 侧**：`BarrageEngine.dispose()` 销毁引擎句柄，`BarrageController.dispose()` 级联释放
- **临时内存**：Dart 侧 FFI 调用使用 `Arena` 自动管理临时分配，作用域结束自动释放
- **图像资源**：`ui.Image` 使用完毕后主动调用 `dispose()`，避免 GPU 内存泄漏

---

## 📝 版本约束

### Flutter >=3.41.0 适配说明

本插件要求 Flutter SDK 版本 `>=3.41.0`，主要依赖以下特性：

1. **Native Assets 稳定 API**
   - Flutter 3.41.0 中 native-assets 机制达到稳定状态
   - `hook/build.dart` 构建 hook 可自动编译原生代码
   - 无需手动配置 Gradle / Xcode 编译脚本

2. **dart:ffi 稳定能力**
   - 支持 `DynamicLibrary` 全平台加载
   - `Pointer.fromFunction` 支持回调
   - Opaque 类型用于不透明句柄

3. **dart:ui 新接口**
   - `ImageDescriptor.raw` + `ImmutableBuffer` 用于像素数据解码
   - `decodeImageFromPixels` 用于异步图像解码
   - `ImageByteFormat.rawRgba` 格式支持

### native-assets 稳定 API

本插件使用 Flutter 官方的 native-assets 机制，具有以下优势：

- **自动构建**：`flutter pub get` 时自动触发 Rust 编译
- **增量编译**：源码未变更时跳过编译，加快开发迭代
- **全平台统一**：Android/iOS/Windows/macOS/Linux 使用同一套构建逻辑
- **官方标准**：Flutter 官方推荐的原生代码集成方案，长期维护

---

## 🤝 贡献指南

欢迎贡献代码！请遵循以下步骤：

1. **Fork 本仓库**到你的 GitHub 账号
2. **克隆到本地**：`git clone https://github.com/<your-name>/flutter_rs_ffi_barrage.git`
3. **创建功能分支**：`git checkout -b feature/your-feature-name`
4. **确保代码通过检查**：
   ```bash
   # Dart 代码
   dart format lib/
   flutter analyze
   flutter test

   # Rust 代码
   cd native/rs_core
   cargo fmt
   cargo clippy --all-targets --all-features -- -D warnings
   cargo test
   ```
5. **提交更改**：`git commit -m 'feat: 添加某某功能'`
6. **推送到分支**：`git push origin feature/your-feature-name`
7. **提交 Pull Request**：描述清楚改动内容和目的

### 代码规范

- Dart 代码遵循 `flutter_lints` 规则
- Rust 代码遵循 `rustfmt` 格式和 `clippy` 全部警告
- 所有 FFI 函数必须有完整的安全文档注释
- 新增功能需附带单元测试

---

## 📄 开源协议

本项目采用 **MIT License** 开源协议。

```
MIT License

Copyright (c) 2024 flutter_rs_ffi_barrage Authors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---

## ⭐ 致谢

### 参考项目

- **[dart_quickjs](https://pub.dev/packages/dart_quickjs)** — 参考了其 Flutter FFI 插件的目录结构组织方式和 native-assets build hook 的设计风格。

- **[flame_barrage](https://pub.dev/packages/flame_barrage)** — 参考了其 Rust 弹幕引擎的轨道管理和碰撞避让算法设计思路。

### 依赖的开源库

**Rust 侧**：
- `crossbeam` — 无锁并发数据结构
- `parking_lot` — 轻量同步原语
- `bytemuck` — 零拷贝类型转换
- `lru` — LRU 缓存实现
- `image` — 图片解码（PNG/JPG/WebP）
- `ab_glyph` / `rusttype` — 字体渲染
- `serde` / `serde_json` — 序列化
- `rand` — 随机数
- `once_cell` — 延迟初始化
- `reqwest` / `tokio` — 网络请求（可选）

**Dart 侧**：
- `ffi` — Dart FFI 支持
- `native_assets_cli` — Native assets 构建工具

---

如果这个项目对你有帮助，欢迎点个 Star ⭐ 支持一下！
