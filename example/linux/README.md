# Linux 平台配置

## 说明

本目录包含 Linux 平台的基础配置骨架。

## 生成完整工程

如需生成完整的 Linux 工程文件，请在 `example/` 目录下执行：

```bash
flutter create --platforms=linux .
```

该命令会自动生成：
- `CMakeLists.txt`（完整版本）
- `runner/` 主程序代码（flutter_window.cc, main.cc 等）
- `flutter/` Flutter 工具链配置
- `resources/` 资源文件（图标、desktop 文件等）

## FFI 插件

本插件使用 Flutter FFI 插件模式，无需额外的平台通道代码。
Rust 编译的动态库（`.so`）会通过 native assets 机制自动打包到应用目录。

## 最低版本

- Linux kernel: 5.x+
- GTK: 3.24+
- CMake: 3.15+
- Clang/GCC: 支持 C++17
