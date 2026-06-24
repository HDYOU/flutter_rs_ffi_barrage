# flutter_rust_bridge Migration - Technical Design

Feature Name: flutter-rust-bridge-migration
Updated: 2026-06-24

## Description

将 flutter_rs_ffi_barrage 从手写 `dart:ffi` 绑定迁移到 `flutter_rust_bridge` v2 框架。FRB 自动生成 Dart/Rust 绑定代码，消除 2403 行手写 FFI 代码。Rust FFI 导出层 (`exports.rs`) 用 FRB 注解重写，核心引擎/渲染/轨道模块保持不变。Flutter 侧 API 全新设计，利用 FRB 的 Stream/异步特性。

## Architecture

### 迁移前 vs 迁移后

```mermaid
graph LR
    subgraph "Before"
        A1["main.dart"] --> B1["BarrageController"]
        B1 --> C1["engine.dart (544L)"]
        C1 --> D1["ffi_bind.dart (1193L)\n手写 dart:ffi"]
        D1 --> E1["exports.rs (1210L)\nextern \"C\" + #[no_mangle]"]
        E1 --> F1["engine.rs / renderer.rs"]
    end

    subgraph "After"
        A2["main.dart"] --> B2["BarrageEngine (FRB)"]
        B2 --> C2["flutter_rust_bridge 生成的绑定"]
        C2 --> D2["api.rs (FRB 注解)\n#[frb] pub fn ..."]
        D2 --> F2["engine.rs / renderer.rs"]
    end
```

### 模块结构

```
native/rs_core/
├── src/
│   ├── lib.rs              # 不变：模块声明
│   ├── api/                # 新：FRB 注解 API 层
│   │   ├── mod.rs
│   │   ├── engine_api.rs   # 引擎生命周期 API
│   │   ├── barrage_api.rs  # 弹幕推送 API
│   │   ├── render_api.rs   # 渲染帧输出 API
│   │   ├── emoji_api.rs    # Emoji 管理 API
│   │   └── effect_api.rs   # 特效设置 API
│   ├── core/               # 不变：核心逻辑
│   │   └── engine.rs
│   ├── render/             # 不变：渲染管线
│   │   └── renderer.rs
│   ├── track/              # 不变：轨道管理
│   │   └── track_manager.rs
│   ├── text_effect/        # 不变：文字特效
│   └── emoji/              # 不变：表情管理
│       └── emoji_manager.rs
├── Cargo.toml              # 更新：添加 flutter_rust_bridge
└── build.rs                # 保留

lib/
├── flutter_rs_ffi_barrage.dart  # 重写：全新 API 导出
├── src/
│   ├── rust/                    # 新：FRB 生成的绑定代码
│   │   └── frb_generated.dart
│   ├── barrage_engine.dart      # 新：引擎封装（替代 engine.dart）
│   ├── barrage_view.dart        # 新：Widget 封装（替代 widget.dart）
│   ├── types.dart               # 重写：FRB 兼容类型
│   └── ffi_bind.dart            # 删除
```

## Components and Interfaces

### 1. Rust API 层 (`api/`)

替换 `ffi/exports.rs`，使用 FRB 注解：

```rust
// api/engine_api.rs
#[flutter_rust_bridge::frb]
pub struct BarrageEngine {
    inner: Arc<Mutex<EngineWrapper>>,
}

#[flutter_rust_bridge::frb]
impl BarrageEngine {
    pub fn create(width: u32, height: u32) -> Self { ... }
    pub fn destroy(self) { ... }
    pub fn resize(&self, width: u32, height: u32) { ... }
}

// api/barrage_api.rs
#[flutter_rust_bridge::frb]
pub struct BarrageMsg {
    pub id: String,
    pub text: String,
    pub track_type: TrackType,
    pub color: u32,           // RGBA packed
    pub font_size: f64,
    pub timestamp: i64,       // ms
    pub text_effects: Option<TextEffectConfig>,
}

#[flutter_rust_bridge::frb]
impl BarrageEngine {
    pub fn push_barrage(&self, msg: BarrageMsg) -> Result<(), String> { ... }
}
```

### 2. 类型映射

| Rust 类型 | FRB 映射到 Dart | 说明 |
|-----------|----------------|------|
| `u32`, `i32` | `int` | |
| `f64` | `double` | |
| `String` | `String` | |
| `Vec<u8>` | `Uint8List` | 二进制数据 |
| `Option<T>` | `T?` | nullable |
| `enum TrackType` | `enum TrackType` | FRB 自动生成 |
| `struct Config` | `class Config` | FRB 自动生成 |
| `Arc<Mutex<T>>` | 自动管理 | FRB 封装 |
| `StreamSink<Vec<u8>>` | `Stream<Uint8List>` | 渲染帧流 |

### 3. 渲染帧输出机制

```rust
// render_api.rs
#[flutter_rust_bridge::frb]
impl BarrageEngine {
    /// 创建一个帧输出流，Dart 侧通过 Stream<Uint8List> 接收
    pub fn render_stream(&self, sink: StreamSink<Vec<u8>>) {
        let engine = self.inner.clone();
        std::thread::spawn(move || {
            loop {
                let frame = engine.lock().render_frame();
                sink.add(frame).unwrap();
                std::thread::sleep(Duration::from_millis(16)); // ~60fps
            }
        });
    }
}
```

### 4. Emoji 回调机制

```rust
// emoji_api.rs
#[flutter_rust_bridge::frb]
impl BarrageEngine {
    /// 设置 emoji 回调（Rust 调用 Dart 获取位图）
    pub fn set_emoji_callback(
        &self,
        callback: impl Fn(String, u32, u32) -> Option<Vec<u8>> + Send + 'static,
    ) { ... }
}
```

### 5. Dart 侧 API 设计

```dart
// barrage_engine.dart
class BarrageEngine {
  final platform.BarrageEngine _inner;

  BarrageEngine.create({required int width, required int height})
      : _inner = platform.BarrageEngine.create(width: width, height: height);

  void pushBarrage(BarrageMsg msg) => _inner.pushBarrage(msg: msg);
  Stream<Uint8List> get renderStream => _inner.renderStream();
  void setEmojiCallback(EmojiCallback callback) => _inner.setEmojiCallback(callback);
  void pause() => _inner.pause();
  void resume() => _inner.resume();
  // ...
}
```

## Data Models

FRB 从 Rust 结构体自动生成 Dart 类：

```rust
// Rust 定义 (api/common.rs)

#[flutter_rust_bridge::frb]
pub enum TrackType { Scrolling, Top, Bottom, Reverse }

#[flutter_rust_bridge::frb]
pub enum GradientType { Linear, Radial, Rainbow }

#[flutter_rust_bridge::frb]
pub struct StrokeConfig {
    pub enabled: bool,
    pub width: f64,
    pub color: u32,
    pub is_outer: bool,
}

#[flutter_rust_bridge::frb]
pub struct ShadowConfig {
    pub enabled: bool,
    pub offset_x: f64,
    pub offset_y: f64,
    pub blur: f64,
    pub color: u32,
    pub layers: u32,
}

#[flutter_rust_bridge::frb]
pub struct NeonConfig {
    pub enabled: bool,
    pub radius: f64,
    pub color: u32,
    pub intensity: f64,
    pub layers: u32,
}

#[flutter_rust_bridge::frb]
pub struct GradientConfig {
    pub enabled: bool,
    pub grad_type: GradientType,
    pub colors: Vec<u32>,
    pub angle: f64,
}

#[flutter_rust_bridge::frb]
pub struct TextEffectConfig {
    pub stroke: Option<StrokeConfig>,
    pub shadow: Option<ShadowConfig>,
    pub neon: Option<NeonConfig>,
    pub gradient: Option<GradientConfig>,
}
```

## Correctness Properties

1. **引擎单例安全**：`BarrageEngine` 内部 `Arc<Mutex<EngineWrapper>>` 确保多线程安全访问
2. **Stream 生命周期**：FRB 管理 `StreamSink` 生命周期，Dart 取消订阅时自动清理
3. **内存安全**：FRB 自动管理 Rust 对象所有权，无需 Dart 侧手动 `malloc/free`
4. **类型安全**：编译时保证 Dart/Rust 类型一致性，消除 `Pointer.fromFunction` 类型错误
5. **线程安全**：Rust 核心模块保持 `Send + Sync` trait，FRB 自动处理线程边界

## Error Handling

| 场景 | Rust 返回 | Dart 接收 |
|------|----------|----------|
| 无效引擎句柄 | `Err("engine already destroyed")` | FRB 自动转为 Dart Exception |
| 无效参数 | `Err("width must be > 0")` | FRB 自动转为 Dart Exception |
| Stream 写入失败 | `sink.add().unwrap_err()` | Dart Stream 错误事件 |
| 文件找不到 | `Err("file not found")` | FRB 自动转为 Dart Exception |

## Test Strategy

1. **单元测试 (Rust)**：保留现有 Rust 测试，增加 API 层测试
2. **集成测试 (Dart)**：创建 FRB 绑定测试，验证所有 API 接口
3. **Example App**：更新 example/ 以使用新 API，构建并运行验证
4. **Flutter Analyze**：每次修改后运行 `flutter analyze` 零错误
5. **平台构建**：验证 Linux/macOS/Windows/Android/iOS 全平台编译

## Migration Steps

1. 添加 `flutter_rust_bridge` 到 Cargo.toml 和 pubspec.yaml
2. 创建 `api/` 模块，逐个迁移 FFI 函数为 FRB 注解方法
3. 运行 FRB 代码生成器，验证 Dart 绑定编译通过
4. 更新 Dart 侧 `engine.dart`、`widget.dart`、`types.dart` 适配新 API
5. 更新 `example/` 代码
6. 删除旧 `ffi_bind.dart`、`ffi/exports.rs`
7. 运行 `flutter analyze` 和 `cargo test` 验证
8. 全平台构建验证

## References

[^1]: (flutter_rust_bridge) - [Official Documentation](https://cjycode.com/flutter_rust_bridge/)
[^2]: (lib/src/ffi_bind.dart#L758-L777) - 当前动态库加载代码
[^3]: (native/rs_core/src/ffi/exports.rs) - 当前 Rust FFI 导出层
[^4]: (native/rs_core/src/ffi/callbacks.rs) - 当前回调机制实现
