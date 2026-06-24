# iOS 平台配置

## 说明

本目录包含 iOS 平台的基础配置骨架。

## 生成完整工程

如需生成完整的 iOS 工程文件，请在 `example/` 目录下执行：

```bash
flutter create --platforms=ios .
```

该命令会自动生成：
- `Runner.xcodeproj/` Xcode 项目
- `Runner.xcworkspace/` 工作空间
- `Runner/` 主工程代码（AppDelegate.swift 等）
- `Runner/Assets.xcassets/` 资源目录
- `Runner/Base.lproj/` 界面文件

## FFI 插件

本插件使用 Flutter FFI 插件模式，无需额外的平台通道代码。
Rust 编译的 iOS Framework 会通过 native assets 机制自动链接。

## 最低版本

- iOS: 12.0
- Xcode: 15.0+
