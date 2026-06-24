//! Flutter 弹幕插件 Rust 内核
//!
//! 高性能弹幕引擎，纯 Rust 实现，通过 extern "C" 裸符号导出与 Flutter/Dart 交互。
//!
//! # 架构
//!
//! ```text
//!                    ┌─────────────────────┐
//!                    │   Flutter / Dart    │
//!                    │  (dart:ffi 绑定)    │
//!                    └─────────┬───────────┘
//!                              │
//!              ┌───────────────▼───────────────┐
//!              │       FFI 接口层              │
//!              │  ffi/exports.rs (extern "C")  │
//!              │  ffi/callbacks.rs (回调存储)  │
//!              └───────────────┬───────────────┘
//!                              │
//!              ┌───────────────▼───────────────┐
//!              │      核心引擎层               │
//!              │     core/engine.rs            │
//!              └──────┬───────────┬────────────┘
//!                     │           │
//!           ┌─────────▼──┐    ┌──▼─────────┐
//!           │  轨道管理  │    │  表情管理  │
//!           │ track/     │    │ emoji/     │
//!           └────────────┘    └────────────┘
//!                     │           │
//!              ┌──────▼───────────▼──────┐
//!              │    渲染管线             │
//!              │   render/renderer.rs    │
//!              └──────┬──────────────────┘
//!                     │
//!              ┌──────▼──────────────┐
//!              │  文字特效           │
//!              │  text_effect/       │
//!              └─────────────────────┘
//! ```
//!
//! # 核心特性
//!
//! - 完全无 C 绑定：纯 Rust extern "C" + #[no_mangle] 裸符号导出
//! - 无 cbindgen、无 .h 头文件、无 C 结构体、无 C 胶水代码
//! - 四种轨道类型：滚动、顶部固定、底部固定、逆向滚动
//! - 智能碰撞避让算法
//! - LRU 表情缓存，支持 Flutter 位图、本地文件、远程 URL 三种加载方式
//! - 四大文字特效：描边、阴影、霓虹发光、渐变
//! - CPU RGBA8888 软件渲染管线
//! - 线程安全：crossbeam 无锁队列 + parking_lot 轻量锁
//!
//! # 安全约束
//!
//! - 所有 FFI 函数使用 unsafe extern "C"
//! - 所有指针参数必须校验非空
//! - 所有长度参数必须做合理范围检查
//! - 引擎句柄用 Box<T> 包装，into_raw/from_raw 管理生命周期

// FFI 库中 unsafe 操作不可避免，使用 allow 而非 deny
// 所有 unsafe 操作都有详细的安全文档说明
#![allow(unsafe_op_in_unsafe_fn)]

/// 工具模块
pub mod utils;

/// 文字特效模块
pub mod text_effect;

/// 轨道模块
pub mod track;

/// Emoji 模块
pub mod emoji;

/// 核心引擎模块
pub mod core;

/// 渲染模块
pub mod render;

/// FFI 接口模块
pub mod ffi;

// 重新导出常用类型
pub use core::engine::BarrageEngine;
pub use emoji::emoji_manager::EmojiManager;
pub use render::renderer::{BarrageRenderer, FrameBuffer};
pub use text_effect::effects::TextEffects;
pub use track::track_manager::{BarrageItem, TrackManager, TrackType};

/// 库版本号
pub const VERSION: &str = env!("CARGO_PKG_VERSION");

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_version() {
        assert!(!VERSION.is_empty());
    }

    #[test]
    fn test_integration_create_engine() {
        let engine = BarrageEngine::new(800, 600);
        assert_eq!(engine.width, 800);
        assert_eq!(engine.height, 600);
    }

    #[test]
    fn test_integration_full_pipeline() {
        // 完整管线测试：创建引擎 → 推送弹幕 → 更新 → 渲染
        let mut engine = BarrageEngine::new(400, 300);
        let mut renderer = BarrageRenderer::new(400, 300);

        // 推送多条弹幕
        for i in 0..10 {
            engine.push(
                &format!("弹幕测试 {}", i),
                0xFFFFFFFF,
                20,
                i * 100,
                TrackType::Scroll,
                TextEffects::default(),
            );
        }

        // 更新
        let count = engine.update(500);
        assert!(count > 0);

        // 渲染
        let mut buffer = vec![0u32; 400 * 300];
        let rendered = renderer.render_frame(&engine, 500, &mut buffer, (400 * 300) as u64);
        assert!(rendered > 0);

        // 检查缓冲区有内容
        let has_content = buffer.iter().any(|&p| p != 0);
        assert!(has_content);
    }
}
