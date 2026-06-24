//! FFI 模块
//!
//! 提供与 Flutter/Dart 交互的 FFI 接口。
//! 所有导出函数均使用 unsafe extern "C"，仅使用基础类型。
//! 无 C 头文件、无 C 结构体、无 C 胶水代码。

pub mod callbacks;
pub mod exports;
