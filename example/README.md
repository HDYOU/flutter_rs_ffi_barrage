# flutter_rs_ffi_barrage Example

Flutter Rust FFI 弹幕插件 - 全平台演示工程

## 功能演示

本示例演示了 `flutter_rs_ffi_barrage` 插件的全部核心功能：

### 1. 自定义 EmojiBitmapCallback（Rust 主动回调 Dart）
- 识别 `[666]` 返回红色笑脸位图（内存生成 RGBA）
- 识别 `[好]` 返回绿色点赞位图
- 其他表情返回 null，降级为纯文字渲染

### 2. 三种 Emoji 注册方式
- **Flutter 位图注册**: `registerEmojiFromFlutterBitmap()` - 代码生成位图直接注册
- **本地文件注册**: `registerEmojiFromLocalPath()` - 从本地图片文件注册
- **网络 URL 注册**: `registerEmojiFromUrl()` - 从网络 URL 异步下载注册

### 3. 四大文字特效
- **描边弹幕** (Stroke) - 外描边效果
- **立体阴影弹幕** (Shadow) - 多层阴影立体效果
- **霓虹发光弹幕** (Neon) - 多层发光光晕
- **彩虹渐变弹幕** (Gradient) - 彩虹渐变填充
- **多特效叠加** - 四种特效混合叠加

### 4. 四种轨道类型
- 滚动弹幕 (Scrolling) - 从右向左
- 顶部弹幕 (Top) - 顶部固定
- 底部弹幕 (Bottom) - 底部固定
- 逆向弹幕 (Reverse) - 从左向右

### 5. 弹幕控制
- 暂停 / 恢复
- 清空弹幕
- 速度调节 (0.25x ~ 5.0x)
- 时间跳转

### 6. 透明叠加效果
- `BarrageView` 叠加在彩色渐变背景之上
- 展示弹幕渲染层的透明特性

## 运行

### 1. 生成平台工程

```bash
cd example
flutter create .
```

### 2. 构建 Rust 核心库

确保 Rust 工具链已安装，然后构建 native 库：

```bash
# 构建对应平台的动态库
cd ../native/rs_core
cargo build --release
```

### 3. 运行 Demo

```bash
cd example
flutter run
```

## 目录结构

```
example/
├── lib/
│   └── main.dart              # 完整 Demo 代码
├── assets/
│   └── README.md              # 资源说明
├── android/                   # Android 平台配置
├── ios/                       # iOS 平台配置
├── macos/                     # macOS 平台配置
├── windows/                   # Windows 平台配置
├── linux/                     # Linux 平台配置
├── pubspec.yaml               # 项目配置
└── analysis_options.yaml      # 代码规范配置
```

## 版本要求

- Flutter: ^3.41.0
- Dart SDK: '>=3.7.0 <4.0.0'
- Rust: 1.75+
