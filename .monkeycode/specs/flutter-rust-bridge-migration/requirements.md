# Requirements Document - flutter_rust_bridge Migration

## Introduction

将 `flutter_rs_ffi_barrage` 从手写 Dart:ffi 绑定迁移到 `flutter_rust_bridge` 框架，实现自动生成 Dart/Rust 绑定代码，消除手动 FFI 维护成本，提升类型安全和开发体验。

## Glossary

- **FRB**: flutter_rust_bridge，Rust-Dart 绑定代码生成框架
- **Engine**: 弹幕引擎核心（BarrageEngine），管理弹幕生命周期、时间轴、碰撞检测
- **Renderer**: 渲染器（BarrageRenderer），CPU 软件渲染 RGBA8888 帧
- **BarrageMsg**: 弹幕消息，包含文本、轨道类型、颜色、字体大小、时间戳、特效配置
- **TextEffect**: 文字特效（描边、阴影、霓虹、渐变）的组合配置
- **Emoji**: 表情符号，通过回调机制从 Dart 侧获取位图数据
- **Track**: 弹幕轨道，支持滚动/顶部/底部/逆向四种类型

## Requirements

### Requirement 1: Rust-Dart 自动绑定生成

**User Story:** AS 开发者，I want 使用 flutter_rust_bridge 自动生成 Rust-Dart FFI 绑定，so that 消除手写 FFI 代码的维护成本和人因错误。

#### Acceptance Criteria

1. Rust 侧所有公开 API SHALL 使用 `#[flutter_rust_bridge::frb]` 宏标记，由 FRB 代码生成器自动生成 Dart 绑定
2. Rust Cargo.toml SHALL 添加 `flutter_rust_bridge` 依赖，Cargo.toml 中 SHALL 移除 `crate-type = ["cdylib"]`
3. Dart 侧 SHALL 通过 FRB 生成的代码调用 Rust 函数，不再使用 `dart:ffi` 手写绑定
4. 生成的 Dart 绑定 SHALL 通过 `flutter analyze` 零错误
5. Rust 编译 (`cargo build`) SHALL 零错误通过

---

### Requirement 2: 弹幕引擎生命周期管理

**User Story:** AS 开发者，I want 通过 FRB 绑定的 API 管理弹幕引擎的完整生命周期，so that 应用可以创建、使用和销毁引擎实例。

#### Acceptance Criteria

1. Engine SHALL 支持创建实例（指定画布宽度/高度），返回引擎句柄
2. Engine SHALL 支持销毁实例，释放所有资源
3. Engine SHALL 支持调整画布尺寸（resize）
4. IF 引擎句柄无效时调用 API，system SHALL 返回明确错误
5. Engine SHALL 使用 Rust `StreamSink` 输出渲染帧（RGBA8888 像素数据）

---

### Requirement 3: 弹幕消息推送

**User Story:** AS 开发者，I want 通过类型安全的 API 推送弹幕消息，so that 无需手动构建扁平化的 24 参数 FFI 调用。

#### Acceptance Criteria

1. System SHALL 提供 `pushBarrage(BarrageMsg)` 方法，接受结构化消息对象
2. BarrageMsg SHALL 包含：id、text、track_type、color、font_size、timestamp、text_effects
3. TextEffect 配置 SHALL 通过嵌套结构体传递（StrokeConfig、ShadowConfig、NeonConfig、GradientConfig）
4. WHEN 推送的弹幕文本包含已注册 emoji 标识，system SHALL 自动触发 emoji 位图回调
5. IF text_effects 中某特效 disabled，对应的嵌套结构体 SHALL 可为 null/Option

---

### Requirement 4: 渲染帧输出

**User Story:** AS 开发者，I want 通过 Rust Stream 获取渲染帧数据，so that Flutter UI 层可以高效地展示弹幕画面。

#### Acceptance Criteria

1. Renderer SHALL 通过 `StreamSink<Vec<u8>>` 输出 RGBA8888 格式的帧缓冲区
2. Dart 侧 SHALL 通过 `Stream<Uint8List>` 接收帧数据
3. Frame 输出频率 SHALL 由引擎内部时钟控制（默认 60fps 目标）
4. WHEN 引擎暂停，frame stream SHALL 停止发送新帧
5. WHEN 引擎恢复，frame stream SHALL 继续发送帧

---

### Requirement 5: 弹幕控制

**User Story:** AS 开发者，I want 通过 FRB API 控制弹幕播放行为，so that 实现播放器级别的弹幕同步。

#### Acceptance Criteria

1. System SHALL 支持暂停/恢复弹幕滚动
2. System SHALL 支持设置播放速度倍率（0.25x ~ 5.0x）
3. System SHALL 支持跳转到指定时间戳
4. System SHALL 支持清空所有弹幕
5. WHEN 跳转到新时间点，已过期的弹幕 SHALL 被自动清理

---

### Requirement 6: Emoji 管理

**User Story:** AS 开发者，I want 通过 FRB 管理表情符号注册和查询，so that 弹幕中的 emoji 标识能正确渲染为位图。

#### Acceptance Criteria

1. System SHALL 支持从 Flutter 注册 emoji（传入 RGBA 像素数据）
2. System SHALL 支持从本地文件路径注册 emoji
3. System SHALL 支持从 URL 注册 emoji（Rust 侧异步下载）
4. System SHALL 提供 emoji 位图查询接口（根据 emoji 标识返回位图）
5. WHEN emoji 未注册时渲染到含该 emoji 的弹幕，system SHALL 降级为纯文字渲染

---

### Requirement 7: 全局文字特效

**User Story:** AS 开发者，I want 通过 FRB API 全局设置文字特效默认值，so that 后续弹幕自动应用特效。

#### Acceptance Criteria

1. System SHALL 支持设置全局描边特效（宽度、颜色、内外模式）
2. System SHALL 支持设置全局立体阴影特效（偏移、模糊、层数、颜色）
3. System SHALL 支持设置全局霓虹发光特效（半径、颜色、强度、层数）
4. System SHALL 支持设置全局渐变特效（类型、颜色数组、角度）
5. WHEN 全局特效未设置，弹幕 SHALL 不使用对应特效

---

### Requirement 8: 查询与工具

**User Story:** AS 开发者，I want 通过 FRB API 查询引擎状态信息。

#### Acceptance Criteria

1. System SHALL 提供引擎版本号查询
2. System SHALL 提供当前存活弹幕数量查询
3. System SHALL 提供引擎运行状态查询（运行中/暂停）

---

### Requirement 9: 清理与迁移

**User Story:** AS 开发者，I want 迁移完成后清理旧代码，so that 项目结构保持整洁。

#### Acceptance Criteria

1. `lib/src/ffi_bind.dart` (1193 行) SHALL 被删除
2. `native/rs_core/src/ffi/` 目录下旧 exports.rs SHALL 被 FRB 生成的 API 层替换
3. `pubspec.yaml` 中 `ffi: ^2.1.2` 依赖 SHALL 移除
4. `pubspec.yaml` 中 `hooks: ^2.0.2`, `code_assets: ^1.2.0`, `native_toolchain_rust: ^1.0.4` 依赖 SHALL 评估是否仍需保留
5. `native/rs_core/src/ffi/callbacks.rs` 回调机制 SHALL 改为 FRB 的 StreamSink/DartFn 模式
