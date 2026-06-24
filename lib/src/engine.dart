/// 弹幕引擎封装 - 管理 Rust 不透明句柄的生命周期
///
/// 本文件提供高层的 Dart API，封装底层 FFI 调用。
/// 所有裸指针操作都被隐藏在内部，对外暴露类型安全的 Dart 接口。
///
/// 使用方式：
/// ```dart
/// final engine = BarrageEngine(width: 1920, height: 1080);
/// engine.push(BarrageMsg(id: '1', text: 'hello'));
/// final pixels = engine.renderFrame(0);
/// engine.dispose();
/// ```
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'ffi_bind.dart';
import 'types.dart';

/// Dart 侧 emoji 位图回调函数类型
///
/// 接收 emoji 文本，返回 RGBA8888 像素数据，失败时返回 null。
typedef EmojiBitmapCallback =
    Uint8List? Function(String emojiText, int width, int height);

/// 弹幕引擎
///
/// 封装 Rust 侧弹幕引擎的所有功能。每个 [BarrageEngine] 实例对应一个
/// Rust 侧的不透明句柄，通过 [dispose] 方法释放资源。
///
/// 引擎采用时间驱动模式，通过 [renderFrame] 传入时间戳获取对应帧的
/// 渲染结果。支持暂停、恢复、跳转等播放控制。
class BarrageEngine {
  /// FFI 绑定实例
  final BarrageFfiBind _bind = BarrageFfiBind.instance;

  /// Rust 引擎不透明句柄
  Pointer<_EngineOpaque> _handle = nullptr;

  /// 渲染区域宽度（像素）
  int _width;

  /// 渲染区域高度（像素）
  int _height;

  /// 引擎是否已被销毁
  bool _disposed = false;

  /// 已注册的 emoji 回调（Dart 层）
  ///
  /// 保存引用以防止被 GC 回收。
  EmojiBitmapCallback? _emojiCallback;

  /// FFI 层的 native 回调指针
  ///
  /// 由 [Pointer.fromFunction] 创建，需要保持引用防止 GC 回收回调函数。
  // ignore: unused_field
  Pointer<NativeFunction<_EmojiCallbackNative>>? _nativeCallbackPtr;

  /// 渲染输出缓冲区（Dart 侧管理的 native 内存）
  Pointer<Uint32> _renderBuffer = nullptr;
  int _renderBufferSize = 0;

  /// 创建弹幕引擎
  ///
  /// - [width] / [height]: 渲染区域尺寸（像素）
  /// - [speed]: 弹幕滚动速度倍率（默认 1.0）
  ///
  /// 抛出 [StateError] 如果 native 库加载失败或引擎创建失败。
  factory BarrageEngine({
    required int width,
    required int height,
    double speed = 1.0,
  }) {
    final bind = BarrageFfiBind.instance;
    final handle = bind.createEngine(width, height);
    if (handle == nullptr) {
      throw StateError('Failed to create barrage engine');
    }
    final engine = BarrageEngine._(handle.cast<_EngineOpaque>(), width, height);
    if (speed != 1.0) {
      engine.setSpeed(speed);
    }
    return engine;
  }

  BarrageEngine._(this._handle, this._width, this._height);

  /// 渲染区域宽度
  int get width => _width;

  /// 渲染区域高度
  int get height => _height;

  /// 引擎是否已被销毁
  bool get isDisposed => _disposed;

  // -----------------------------------------------------------------------
  // 生命周期
  // -----------------------------------------------------------------------

  /// 销毁引擎，释放所有资源
  ///
  /// 调用后所有方法将抛出 [StateError]。
  /// 重复调用 dispose 是安全的（第二次及之后为 no-op）。
  void dispose() {
    if (_disposed) return;
    _disposed = true;

    if (_handle != nullptr) {
      _bind.destroyEngine(_handle.cast());
      _handle = nullptr;
    }

    // 释放渲染缓冲区
    if (_renderBuffer != nullptr) {
      malloc.free(_renderBuffer);
      _renderBuffer = nullptr;
      _renderBufferSize = 0;
    }

    _emojiCallback = null;
    _nativeCallbackPtr = null;
  }

  /// 检查引擎是否可用，不可用时抛出异常
  void _checkAlive() {
    if (_disposed || _handle == nullptr) {
      throw StateError(
        'BarrageEngine has been disposed. '
        'Cannot call methods on a disposed engine.',
      );
    }
  }

  /// 确保渲染缓冲区大小足够
  void _ensureRenderBuffer(int width, int height) {
    final needed = width * height;
    if (_renderBufferSize >= needed && _renderBuffer != nullptr) return;

    // 释放旧缓冲区
    if (_renderBuffer != nullptr) {
      malloc.free(_renderBuffer);
    }

    // 分配新缓冲区（u32 数组，每个像素一个 u32 = RGBA8888）
    _renderBuffer = malloc.allocate<Uint32>(needed);
    _renderBufferSize = needed;
  }

  // -----------------------------------------------------------------------
  // 尺寸调整
  // -----------------------------------------------------------------------

  /// 调整渲染区域大小
  ///
  /// 当 Widget 尺寸变化时调用此方法更新内部渲染缓冲区。
  void resize(int width, int height) {
    _checkAlive();
    if (width <= 0 || height <= 0) {
      throw ArgumentError('Invalid dimensions: ${width}x$height');
    }
    _bind.resize(_handle.cast(), width, height);
    _width = width;
    _height = height;
    // 重新分配渲染缓冲区
    _ensureRenderBuffer(width, height);
  }

  // -----------------------------------------------------------------------
  // 播放控制
  // -----------------------------------------------------------------------

  /// 设置弹幕滚动速度倍率
  ///
  /// [speed] 必须大于 0，默认 1.0。
  void setSpeed(double speed) {
    _checkAlive();
    _bind.setSpeed(_handle.cast(), speed);
  }

  /// 暂停弹幕滚动
  void pause() {
    _checkAlive();
    _bind.pause(_handle.cast());
  }

  /// 恢复弹幕滚动
  void resume() {
    _checkAlive();
    _bind.resume(_handle.cast());
  }

  /// 跳转到指定时间点
  ///
  /// [timestampMs] 为毫秒级时间戳。
  void seek(int timestampMs) {
    _checkAlive();
    _bind.seek(_handle.cast(), timestampMs);
  }

  /// 清空所有弹幕
  void clear() {
    _checkAlive();
    _bind.clear(_handle.cast());
  }

  // -----------------------------------------------------------------------
  // 弹幕推送
  // -----------------------------------------------------------------------

  /// 推送一条弹幕
  ///
  /// 弹幕会根据 [BarrageMsg.timestamp] 被放入对应的时间位置。
  /// 对于实时弹幕，通常将 timestamp 设置为当前播放时间。
  ///
  /// 返回 true 表示推送成功，false 表示失败（参数无效或被过滤）。
  bool push(BarrageMsg msg) {
    _checkAlive();
    return _bind.pushBarrage(_handle.cast(), msg);
  }

  /// 批量推送多条弹幕
  ///
  /// 比循环调用 [push] 更高效。
  /// 返回成功推送的数量。
  int pushAll(List<BarrageMsg> messages) {
    _checkAlive();
    int count = 0;
    for (final msg in messages) {
      if (_bind.pushBarrage(_handle.cast(), msg)) {
        count++;
      }
    }
    return count;
  }

  /// 获取当前存活弹幕数
  int get aliveCount {
    _checkAlive();
    return _bind.aliveCount(_handle.cast());
  }

  // -----------------------------------------------------------------------
  // 渲染
  // -----------------------------------------------------------------------

  /// 渲染指定时间戳的帧，返回 RGBA8888 像素数据
  ///
  /// 返回的 [Uint8List] 长度为 width * height * 4。
  /// 如果渲染失败（如引擎已销毁），返回 null。
  ///
  /// 像素数据格式：每个像素 4 字节，顺序为 R, G, B, A。
  Uint8List? renderFrame(int timestampMs) {
    _checkAlive();

    // 确保缓冲区存在
    _ensureRenderBuffer(_width, _height);

    final count = _bind.renderFrame(
      _handle.cast(),
      timestampMs,
      _renderBuffer,
      _renderBufferSize,
    );

    if (count < 0) return null;

    // 从 native 内存拷贝到 Dart 托管内存
    // _renderBuffer 是 Uint32 数组，每个元素代表一个像素（RGBA8888）
    // 转换为 Uint8List 需要乘以 4
    final byteCount = _renderBufferSize * 4;
    try {
      return Uint8List.fromList(
        _renderBuffer.cast<Uint8>().asTypedList(byteCount),
      );
    } catch (_) {
      return null;
    }
  }

  // -----------------------------------------------------------------------
  // Emoji 回调注册
  // -----------------------------------------------------------------------

  /// 设置 emoji 位图请求回调（全局）
  ///
  /// 当 Rust 渲染引擎遇到未注册的 emoji 时，会通过此回调向 Flutter
  /// 请求位图。回调函数需要返回 RGBA8888 格式的像素数据。
  ///
  /// 注意：这是全局回调，不针对特定引擎实例。
  /// 回调会在渲染线程中被调用，注意线程安全。
  ///
  /// 传入 null 可取消回调。
  void setEmojiBitmapCallback(EmojiBitmapCallback? callback) {
    _checkAlive();

    // 保存 Dart 回调引用
    _emojiCallback = callback;
    // 同步到静态变量，供静态桥接函数使用
    BarrageEngine._globalEmojiCallback = callback;

    if (callback == null) {
      // 取消回调
      _bind.setEmojiBitmapCallback(nullptr);
      _nativeCallbackPtr = null;
      return;
    }

    // 创建 native 回调桥接函数
    // 注意：fromFunction 要求静态/顶层函数，所以我们使用静态方法
    final nativePtr = Pointer.fromFunction<_EmojiCallbackNative>(
      _emojiCallbackBridge,
      false, // 异常时返回 false
    );

    _nativeCallbackPtr = nativePtr;
    _bind.setEmojiBitmapCallback(nativePtr);
  }

  /// 同步查询 emoji 位图（从 Flutter 侧回调获取）
  ///
  /// 直接调用已注册的 Dart 回调获取 emoji 位图，不经过 Rust 侧。
  /// 用于测试或手动获取 emoji 渲染结果。
  ///
  /// 如果未注册回调或回调返回 null，则返回 null。
  EmojiBitmapResult? getEmojiBitmapFromFlutter(String emojiText, int size) {
    if (_emojiCallback == null) return null;

    try {
      final pixels = _emojiCallback!(emojiText, size, size);
      if (pixels == null) return null;

      final expectedLen = size * size * 4;
      if (pixels.length != expectedLen) {
        // 长度不匹配，忽略
        return null;
      }

      return EmojiBitmapResult(width: size, height: size, pixels: pixels);
    } catch (_) {
      return null;
    }
  }

  // -----------------------------------------------------------------------
  // Emoji 注册
  // -----------------------------------------------------------------------

  /// 从 Flutter 位图注册 emoji
  ///
  /// 将 Flutter 侧预渲染的 emoji 位图注册到 Rust 引擎缓存中。
  /// 后续渲染时遇到相同 emoji 将直接使用缓存的位图。
  ///
  /// - [emojiText]: emoji 文本（如 "😀"）
  /// - [pixels]: RGBA8888 像素数据
  /// - [width] / [height]: 位图尺寸
  ///
  /// 返回 true 表示注册成功。
  bool registerEmojiFromFlutterBitmap(
    String emojiText,
    Uint8List pixels,
    int width,
    int height,
  ) {
    _checkAlive();
    if (emojiText.isEmpty) {
      throw ArgumentError('emojiText cannot be empty');
    }
    if (pixels.length != width * height * 4) {
      throw ArgumentError(
        'Pixel data length (${pixels.length}) does not match '
        'width * height * 4 (${width * height * 4})',
      );
    }

    // 将像素数据拷贝到 native 内存
    // Rust 侧会再次拷贝到自己的缓存，所以这里用完即可释放
    return using((Arena arena) {
      final pixelPtr = arena.allocate<Uint8>(pixels.length);
      pixelPtr.asTypedList(pixels.length).setAll(0, pixels);

      return _bind.registerEmojiFromFlutter(
        _handle.cast(),
        emojiText,
        width,
        height,
        pixelPtr,
        pixels.length,
      );
    });
  }

  /// 从本地文件路径注册 emoji
  ///
  /// 由 Rust 侧读取并解码图片文件。支持常见格式（PNG, JPG 等）。
  /// 返回 true 表示注册成功。
  bool registerEmojiFromLocalPath(String emojiText, String path) {
    _checkAlive();
    if (emojiText.isEmpty) {
      throw ArgumentError('emojiText cannot be empty');
    }
    if (path.isEmpty) {
      throw ArgumentError('path cannot be empty');
    }
    return _bind.registerEmojiFromLocalPath(_handle.cast(), emojiText, path);
  }

  /// 从网络 URL 注册 emoji
  ///
  /// 由 Rust 侧同步下载并解码图片。建议先在 Flutter 侧异步下载后
  /// 通过 registerEmojiFromFlutterBitmap 注册。
  /// 返回 true 表示注册成功。
  bool registerEmojiFromUrl(String emojiText, String url) {
    _checkAlive();
    if (emojiText.isEmpty) {
      throw ArgumentError('emojiText cannot be empty');
    }
    if (url.isEmpty) {
      throw ArgumentError('url cannot be empty');
    }
    return _bind.registerEmojiFromUrl(_handle.cast(), emojiText, url);
  }

  // -----------------------------------------------------------------------
  // 全局特效设置
  // -----------------------------------------------------------------------

  /// 设置全局描边效果
  ///
  /// 对所有后续推送的弹幕生效。已在队列中的弹幕不受影响。
  void setGlobalStroke(StrokeConfig config) {
    _checkAlive();
    _bind.setGlobalStroke(_handle.cast(), config);
  }

  /// 设置全局阴影效果
  void setGlobalShadow(ShadowConfig config) {
    _checkAlive();
    _bind.setGlobalShadow(_handle.cast(), config);
  }

  /// 设置全局霓虹效果
  void setGlobalNeon(NeonConfig config) {
    _checkAlive();
    _bind.setGlobalNeon(_handle.cast(), config);
  }

  /// 设置全局渐变效果
  void setGlobalGradient(GradientConfig config) {
    _checkAlive();
    _bind.setGlobalGradient(_handle.cast(), config);
  }

  // -----------------------------------------------------------------------
  // 静态桥接 - Emoji 回调
  // -----------------------------------------------------------------------

  /// 当前注册的全局 emoji 回调（静态，供桥接函数使用）
  static EmojiBitmapCallback? _globalEmojiCallback;

  /// Emoji 位图回调的静态桥接函数
  ///
  /// 这是一个静态函数，被 Rust 侧通过 FFI 调用。
  /// 它负责将原生参数转换为 Dart 类型，然后调用对应的 Dart 回调。
  ///
  /// 注意：此函数必须是静态/顶层函数，才能被 [Pointer.fromFunction] 使用。
  static bool _emojiCallbackBridge(
    Pointer<Uint8> emojiText,
    int textLen,
    Pointer<Uint32> outWidth,
    Pointer<Uint32> outHeight,
    Pointer<Pointer<Uint8>> outPixels,
    Pointer<Uint64> outPixelLen,
  ) {
    try {
      // 解码 emoji 文本
      final emojiStr = utf8DecodeFromPointer(emojiText, textLen);
      if (emojiStr.isEmpty) return false;

      final callback = _globalEmojiCallback;
      if (callback == null) return false;

      // 调用 Dart 回调获取位图
      const defaultSize = 64;
      final pixels = callback(emojiStr, defaultSize, defaultSize);
      if (pixels == null || pixels.isEmpty) return false;

      final pixelLen = pixels.length;
      if (pixelLen % 4 != 0) return false;
      final totalPixels = pixelLen ~/ 4;

      // 估算宽高（假设为正方形）
      int w = defaultSize;
      int h = defaultSize;
      if (totalPixels > 0) {
        w = totalPixels ~/ h;
        if (w * h != totalPixels) {
          w = defaultSize;
          h = totalPixels ~/ w;
          if (h <= 0 || w * h > totalPixels) {
            return false;
          }
        }
      }

      // 分配输出像素内存（Rust 侧使用后负责释放）
      final pixelPtr = malloc.allocate<Uint8>(pixelLen);
      pixelPtr.asTypedList(pixelLen).setAll(0, pixels);

      // 填充输出参数
      outWidth.value = w;
      outHeight.value = h;
      outPixels.value = pixelPtr;
      outPixelLen.value = pixelLen;

      return true;
    } catch (_) {
      // 回调中发生任何异常都返回 false
      return false;
    }
  }
}

// ---------------------------------------------------------------------------
// 类型别名
// ---------------------------------------------------------------------------

/// 引擎不透明句柄类型
typedef _EngineOpaque = Opaque;

/// Emoji 位图回调的 Native 签名（与 ffi_bind.dart 中一致）
typedef _EmojiCallbackNative =
    Bool Function(
      Pointer<Uint8> emojiText,
      Uint64 textLen,
      Pointer<Uint32> outWidth,
      Pointer<Uint32> outHeight,
      Pointer<Pointer<Uint8>> outPixels,
      Pointer<Uint64> outPixelLen,
    );
