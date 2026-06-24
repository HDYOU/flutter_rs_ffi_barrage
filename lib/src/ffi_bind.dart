/// 核心 FFI 绑定层 - 手动硬编码，与 Rust 侧 extern "C" 导出一一对应
///
/// 本文件包含所有与 Rust 侧 `#[no_mangle] pub extern "C"` 函数相对应的
/// Dart 侧绑定。所有函数签名、类型、指针布局均为手动编写，不依赖任何
/// ffigen / cbindgen 生成的产物，也不依赖任何 .h 头文件。
///
/// 内存安全约定：
/// - 所有传入 Rust 的字符串使用 UTF-8 编码，以 Pointer<Uint8> + length 传递
/// - 所有由 Dart 分配并传入 Rust 的内存，由 Dart 负责在调用后释放
/// - 所有由 Rust 分配并返回给 Dart 的内存，由 Dart 侧提供对应的释放函数
/// - 指针操作前后均做空值检查与长度校验
///
/// 符号命名约定（与 Rust 侧完全一致）：
/// - 引擎相关：`barrage_engine_*`
/// - Emoji 相关：`register_emoji_*` / `set_emoji_bitmap_callback`
/// - 全局特效：`set_global_*`
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io' show Platform;
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:ffi/ffi.dart';

import 'types.dart';

// ---------------------------------------------------------------------------
// 不透明引擎句柄
// ---------------------------------------------------------------------------

/// 弹幕引擎不透明句柄
///
/// Rust 侧 `BarrageEngine` 的不透明指针，Dart 侧只持有句柄，
/// 不直接访问内部字段。
typedef _EngineHandle = Opaque;

// ---------------------------------------------------------------------------
// Emoji 位图回调 NativeFunction 签名
// ---------------------------------------------------------------------------

/// Emoji 位图请求回调的 Native 签名
///
/// 当 Rust 渲染引擎需要某个 emoji 的位图数据时，会通过此回调
/// 向 Dart/Flutter 侧请求。回调函数需要填充输出参数并返回是否成功。
///
/// 参数说明：
/// - [emojiText]: emoji 文本的 UTF-8 字节指针
/// - [textLen]: emoji 文本字节长度
/// - [outWidth]: 输出 - 位图宽度（像素）
/// - [outHeight]: 输出 - 位图高度（像素）
/// - [outPixels]: 输出 - RGBA8888 像素数据指针（由 Dart 分配，Rust 使用后释放）
/// - [outPixelLen]: 输出 - 像素数据字节长度
///
/// 返回值：true 表示成功获取位图，false 表示失败。
typedef _EmojiBitmapCallbackNative =
    Bool Function(
      Pointer<Uint8> emojiText,
      Uint64 textLen,
      Pointer<Uint32> outWidth,
      Pointer<Uint32> outHeight,
      Pointer<Pointer<Uint8>> outPixels,
      Pointer<Uint64> outPixelLen,
    );

// ---------------------------------------------------------------------------
// 引擎生命周期 FFI 签名
// ---------------------------------------------------------------------------

/// 创建弹幕引擎
///
/// ```c
/// void* barrage_engine_create(
///   uint32_t width,
///   uint32_t height,
///   float    font_ratio,
///   float    speed,
/// );
/// ```
typedef _BarrageEngineCreateNative =
    Pointer<_EngineHandle> Function(
      Uint32 width,
      Uint32 height,
      Float fontRatio,
      Float speed,
    );
typedef _BarrageEngineCreateDart =
    Pointer<_EngineHandle> Function(
      int width,
      int height,
      double fontRatio,
      double speed,
    );

/// 销毁弹幕引擎
///
/// ```c
/// void barrage_engine_destroy(void* engine);
/// ```
typedef _BarrageEngineDestroyNative =
    Void Function(Pointer<_EngineHandle> engine);
typedef _BarrageEngineDestroyDart =
    void Function(Pointer<_EngineHandle> engine);

// ---------------------------------------------------------------------------
// 引擎控制 FFI 签名
// ---------------------------------------------------------------------------

/// 调整渲染区域大小
///
/// ```c
/// void barrage_engine_resize(
///   void*    engine,
///   uint32_t width,
///   uint32_t height,
/// );
/// ```
typedef _BarrageEngineResizeNative =
    Void Function(Pointer<_EngineHandle> engine, Uint32 width, Uint32 height);
typedef _BarrageEngineResizeDart =
    void Function(Pointer<_EngineHandle> engine, int width, int height);

/// 设置弹幕滚动速度倍率
///
/// ```c
/// void barrage_engine_set_speed(
///   void* engine,
///   float speed,
/// );
/// ```
typedef _BarrageEngineSetSpeedNative =
    Void Function(Pointer<_EngineHandle> engine, Float speed);
typedef _BarrageEngineSetSpeedDart =
    void Function(Pointer<_EngineHandle> engine, double speed);

/// 暂停弹幕
///
/// ```c
/// void barrage_engine_pause(void* engine);
/// ```
typedef _BarrageEnginePauseNative =
    Void Function(Pointer<_EngineHandle> engine);
typedef _BarrageEnginePauseDart = void Function(Pointer<_EngineHandle> engine);

/// 恢复弹幕
///
/// ```c
/// void barrage_engine_resume(void* engine);
/// ```
typedef _BarrageEngineResumeNative =
    Void Function(Pointer<_EngineHandle> engine);
typedef _BarrageEngineResumeDart = void Function(Pointer<_EngineHandle> engine);

/// 跳转到指定时间点
///
/// ```c
/// void barrage_engine_seek(
///   void*    engine,
///   uint64_t timestamp_ms,
/// );
/// ```
typedef _BarrageEngineSeekNative =
    Void Function(Pointer<_EngineHandle> engine, Uint64 timestampMs);
typedef _BarrageEngineSeekDart =
    void Function(Pointer<_EngineHandle> engine, int timestampMs);

/// 清空所有弹幕
///
/// ```c
/// void barrage_engine_clear(void* engine);
/// ```
typedef _BarrageEngineClearNative =
    Void Function(Pointer<_EngineHandle> engine);
typedef _BarrageEngineClearDart = void Function(Pointer<_EngineHandle> engine);

// ---------------------------------------------------------------------------
// 弹幕推送 FFI 签名
// ---------------------------------------------------------------------------

/// 推送一条弹幕
///
/// 所有字符串参数均以 UTF-8 字节指针 + 长度方式传递。
/// 颜色使用 32 位 RGBA 格式（0xRRGGBBAA）。
///
/// ```c
/// void barrage_engine_push(
///   void*          engine,
///   const uint8_t* id,
///   uint64_t       id_len,
///   const uint8_t* text,
///   uint64_t       text_len,
///   uint32_t       track_type,     // 0=scrolling, 1=top, 2=bottom, 3=reverse
///   uint32_t       color,          // RGBA
///   float          font_size,
///   uint64_t       timestamp_ms,
///   // 文字特效 - 描边
///   uint8_t  stroke_enabled,
///   float    stroke_width,
///   uint32_t stroke_color,         // RGBA
///   uint8_t  stroke_outer,
///   // 文字特效 - 阴影
///   uint8_t  shadow_enabled,
///   float    shadow_offset_x,
///   float    shadow_offset_y,
///   float    shadow_blur,
///   uint32_t shadow_color,         // RGBA
///   uint32_t shadow_layers,
///   // 文字特效 - 霓虹
///   uint8_t  neon_enabled,
///   float    neon_radius,
///   uint32_t neon_color,           // RGBA
///   float    neon_intensity,
///   uint32_t neon_layers,
///   // 文字特效 - 渐变
///   uint8_t        gradient_enabled,
///   uint32_t       gradient_type,  // 0=linear, 1=radial, 2=rainbow
///   const uint32_t* gradient_colors, // RGBA 数组
///   uint32_t       gradient_color_count,
///   float          gradient_angle,
/// );
/// ```
typedef _BarrageEnginePushNative =
    Void Function(
      Pointer<_EngineHandle> engine,
      Pointer<Uint8> id,
      Uint64 idLen,
      Pointer<Uint8> text,
      Uint64 textLen,
      Uint32 trackType,
      Uint32 color,
      Float fontSize,
      Uint64 timestampMs,
      // stroke
      Uint8 strokeEnabled,
      Float strokeWidth,
      Uint32 strokeColor,
      Uint8 strokeOuter,
      // shadow
      Uint8 shadowEnabled,
      Float shadowOffsetX,
      Float shadowOffsetY,
      Float shadowBlur,
      Uint32 shadowColor,
      Uint32 shadowLayers,
      // neon
      Uint8 neonEnabled,
      Float neonRadius,
      Uint32 neonColor,
      Float neonIntensity,
      Uint32 neonLayers,
      // gradient
      Uint8 gradientEnabled,
      Uint32 gradientType,
      Pointer<Uint32> gradientColors,
      Uint32 gradientColorCount,
      Float gradientAngle,
    );
typedef _BarrageEnginePushDart =
    void Function(
      Pointer<_EngineHandle> engine,
      Pointer<Uint8> id,
      int idLen,
      Pointer<Uint8> text,
      int textLen,
      int trackType,
      int color,
      double fontSize,
      int timestampMs,
      // stroke
      int strokeEnabled,
      double strokeWidth,
      int strokeColor,
      int strokeOuter,
      // shadow
      int shadowEnabled,
      double shadowOffsetX,
      double shadowOffsetY,
      double shadowBlur,
      int shadowColor,
      int shadowLayers,
      // neon
      int neonEnabled,
      double neonRadius,
      int neonColor,
      double neonIntensity,
      int neonLayers,
      // gradient
      int gradientEnabled,
      int gradientType,
      Pointer<Uint32> gradientColors,
      int gradientColorCount,
      double gradientAngle,
    );

// ---------------------------------------------------------------------------
// 渲染帧 FFI 签名
// ---------------------------------------------------------------------------

/// 渲染指定时间戳的帧
///
/// 返回指向内部 RGBA8888 帧缓冲区的指针，缓冲区大小为
/// width * height * 4 字节。返回的指针在下次调用 render_frame
/// 或 destroy 之前有效。返回 nullptr 表示渲染失败。
///
/// ```c
/// const uint8_t* barrage_engine_render_frame(
///   void*    engine,
///   uint64_t timestamp_ms,
/// );
/// ```
typedef _BarrageEngineRenderFrameNative =
    Pointer<Uint8> Function(Pointer<_EngineHandle> engine, Uint64 timestampMs);
typedef _BarrageEngineRenderFrameDart =
    Pointer<Uint8> Function(Pointer<_EngineHandle> engine, int timestampMs);

// ---------------------------------------------------------------------------
// Emoji 注册与回调 FFI 签名
// ---------------------------------------------------------------------------

/// 设置 emoji 位图请求回调
///
/// 将 Dart 侧的回调函数注册到 Rust 引擎。当 Rust 侧需要某个 emoji
/// 的位图时，会调用此回调向 Flutter 请求。
///
/// ```c
/// void set_emoji_bitmap_callback(
///   void*     engine,
///   bool (*callback)(
///     const uint8_t* emoji_text,
///     uint64_t       text_len,
///     uint32_t*      out_width,
///     uint32_t*      out_height,
///     uint8_t**      out_pixels,
///     uint64_t*      out_pixel_len,
///   )
/// );
/// ```
typedef _SetEmojiBitmapCallbackNative =
    Void Function(
      Pointer<_EngineHandle> engine,
      Pointer<NativeFunction<_EmojiBitmapCallbackNative>> callback,
    );
typedef _SetEmojiBitmapCallbackDart =
    void Function(
      Pointer<_EngineHandle> engine,
      Pointer<NativeFunction<_EmojiBitmapCallbackNative>> callback,
    );

/// 从 Flutter 位图注册 emoji
///
/// 直接将 Flutter 侧预渲染的 emoji 位图注册到 Rust 引擎。
///
/// ```c
/// void register_emoji_from_flutter(
///   void*          engine,
///   const uint8_t* emoji_text,
///   uint64_t       text_len,
///   const uint8_t* pixels,
///   uint32_t       width,
///   uint32_t       height,
/// );
/// ```
typedef _RegisterEmojiFromFlutterNative =
    Void Function(
      Pointer<_EngineHandle> engine,
      Pointer<Uint8> emojiText,
      Uint64 textLen,
      Pointer<Uint8> pixels,
      Uint32 width,
      Uint32 height,
    );
typedef _RegisterEmojiFromFlutterDart =
    void Function(
      Pointer<_EngineHandle> engine,
      Pointer<Uint8> emojiText,
      int textLen,
      Pointer<Uint8> pixels,
      int width,
      int height,
    );

/// 从本地文件路径注册 emoji
///
/// ```c
/// void register_emoji_from_local_path(
///   void*          engine,
///   const uint8_t* emoji_text,
///   uint64_t       text_len,
///   const uint8_t* path,
///   uint64_t       path_len,
/// );
/// ```
typedef _RegisterEmojiFromLocalPathNative =
    Void Function(
      Pointer<_EngineHandle> engine,
      Pointer<Uint8> emojiText,
      Uint64 textLen,
      Pointer<Uint8> path,
      Uint64 pathLen,
    );
typedef _RegisterEmojiFromLocalPathDart =
    void Function(
      Pointer<_EngineHandle> engine,
      Pointer<Uint8> emojiText,
      int textLen,
      Pointer<Uint8> path,
      int pathLen,
    );

/// 从网络 URL 注册 emoji
///
/// ```c
/// void register_emoji_from_url(
///   void*          engine,
///   const uint8_t* emoji_text,
///   uint64_t       text_len,
///   const uint8_t* url,
///   uint64_t       url_len,
/// );
/// ```
typedef _RegisterEmojiFromUrlNative =
    Void Function(
      Pointer<_EngineHandle> engine,
      Pointer<Uint8> emojiText,
      Uint64 textLen,
      Pointer<Uint8> url,
      Uint64 urlLen,
    );
typedef _RegisterEmojiFromUrlDart =
    void Function(
      Pointer<_EngineHandle> engine,
      Pointer<Uint8> emojiText,
      int textLen,
      Pointer<Uint8> url,
      int urlLen,
    );

// ---------------------------------------------------------------------------
// 全局特效 FFI 签名
// ---------------------------------------------------------------------------

/// 设置全局描边效果
///
/// 对所有后续推送的弹幕生效，除非弹幕自身指定了描边。
///
/// ```c
/// void set_global_stroke(
///   void*    engine,
///   uint8_t  enabled,
///   float    width,
///   uint32_t color,   // RGBA
///   uint8_t  is_outer,
/// );
/// ```
typedef _SetGlobalStrokeNative =
    Void Function(
      Pointer<_EngineHandle> engine,
      Uint8 enabled,
      Float width,
      Uint32 color,
      Uint8 isOuter,
    );
typedef _SetGlobalStrokeDart =
    void Function(
      Pointer<_EngineHandle> engine,
      int enabled,
      double width,
      int color,
      int isOuter,
    );

/// 设置全局阴影效果
///
/// ```c
/// void set_global_shadow(
///   void*    engine,
///   uint8_t  enabled,
///   float    offset_x,
///   float    offset_y,
///   float    blur,
///   uint32_t color,     // RGBA
///   uint32_t layers,
/// );
/// ```
typedef _SetGlobalShadowNative =
    Void Function(
      Pointer<_EngineHandle> engine,
      Uint8 enabled,
      Float offsetX,
      Float offsetY,
      Float blur,
      Uint32 color,
      Uint32 layers,
    );
typedef _SetGlobalShadowDart =
    void Function(
      Pointer<_EngineHandle> engine,
      int enabled,
      double offsetX,
      double offsetY,
      double blur,
      int color,
      int layers,
    );

/// 设置全局霓虹效果
///
/// ```c
/// void set_global_neon(
///   void*    engine,
///   uint8_t  enabled,
///   float    radius,
///   uint32_t color,       // RGBA
///   float    intensity,
///   uint32_t layers,
/// );
/// ```
typedef _SetGlobalNeonNative =
    Void Function(
      Pointer<_EngineHandle> engine,
      Uint8 enabled,
      Float radius,
      Uint32 color,
      Float intensity,
      Uint32 layers,
    );
typedef _SetGlobalNeonDart =
    void Function(
      Pointer<_EngineHandle> engine,
      int enabled,
      double radius,
      int color,
      double intensity,
      int layers,
    );

/// 设置全局渐变效果
///
/// ```c
/// void set_global_gradient(
///   void*            engine,
///   uint8_t          enabled,
///   uint32_t         type,   // 0=linear, 1=radial, 2=rainbow
///   const uint32_t*  colors, // RGBA 数组
///   uint32_t         color_count,
///   float            angle,
/// );
/// ```
typedef _SetGlobalGradientNative =
    Void Function(
      Pointer<_EngineHandle> engine,
      Uint8 enabled,
      Uint32 type,
      Pointer<Uint32> colors,
      Uint32 colorCount,
      Float angle,
    );
typedef _SetGlobalGradientDart =
    void Function(
      Pointer<_EngineHandle> engine,
      int enabled,
      int type,
      Pointer<Uint32> colors,
      int colorCount,
      double angle,
    );

// ---------------------------------------------------------------------------
// BarrageFfiBind - FFI 绑定封装类
// ---------------------------------------------------------------------------

/// 弹幕引擎 FFI 绑定封装
///
/// 负责加载动态库、查找符号、封装所有 FFI 调用。
/// 所有 unsafe 的指针操作都在此类内部完成，对外暴露安全的方法。
///
/// 此类为单例模式，全局共享一个动态库实例。
class BarrageFfiBind {
  /// 动态库名称（各平台不同）
  static const String _libName = 'flutter_rs_ffi_barrage';

  /// 单例实例
  static BarrageFfiBind? _instance;

  /// 获取单例
  static BarrageFfiBind get instance {
    _instance ??= BarrageFfiBind._();
    return _instance!;
  }

  // 引擎生命周期
  final _BarrageEngineCreateDart _create;
  final _BarrageEngineDestroyDart _destroy;

  // 引擎控制
  final _BarrageEngineResizeDart _resize;
  final _BarrageEngineSetSpeedDart _setSpeed;
  final _BarrageEnginePauseDart _pause;
  final _BarrageEngineResumeDart _resume;
  final _BarrageEngineSeekDart _seek;
  final _BarrageEngineClearDart _clear;

  // 弹幕推送
  final _BarrageEnginePushDart _push;

  // 渲染
  final _BarrageEngineRenderFrameDart _renderFrame;

  // Emoji
  final _SetEmojiBitmapCallbackDart _setEmojiBitmapCallback;
  final _RegisterEmojiFromFlutterDart _registerEmojiFromFlutter;
  final _RegisterEmojiFromLocalPathDart _registerEmojiFromLocalPath;
  final _RegisterEmojiFromUrlDart _registerEmojiFromUrl;

  // 全局特效
  final _SetGlobalStrokeDart _setGlobalStroke;
  final _SetGlobalShadowDart _setGlobalShadow;
  final _SetGlobalNeonDart _setGlobalNeon;
  final _SetGlobalGradientDart _setGlobalGradient;

  /// 私有构造函数 - 加载动态库并查找所有符号
  factory BarrageFfiBind._() {
    final lib = _loadLibrary();

    return BarrageFfiBind._withLibrary(
      create: lib
          .lookupFunction<_BarrageEngineCreateNative, _BarrageEngineCreateDart>(
            'barrage_engine_create',
          ),
      destroy: lib.lookupFunction<
        _BarrageEngineDestroyNative,
        _BarrageEngineDestroyDart
      >('barrage_engine_destroy'),
      resize: lib
          .lookupFunction<_BarrageEngineResizeNative, _BarrageEngineResizeDart>(
            'barrage_engine_resize',
          ),
      setSpeed: lib.lookupFunction<
        _BarrageEngineSetSpeedNative,
        _BarrageEngineSetSpeedDart
      >('barrage_engine_set_speed'),
      pause: lib
          .lookupFunction<_BarrageEnginePauseNative, _BarrageEnginePauseDart>(
            'barrage_engine_pause',
          ),
      resume: lib
          .lookupFunction<_BarrageEngineResumeNative, _BarrageEngineResumeDart>(
            'barrage_engine_resume',
          ),
      seek: lib
          .lookupFunction<_BarrageEngineSeekNative, _BarrageEngineSeekDart>(
            'barrage_engine_seek',
          ),
      clear: lib
          .lookupFunction<_BarrageEngineClearNative, _BarrageEngineClearDart>(
            'barrage_engine_clear',
          ),
      push: lib
          .lookupFunction<_BarrageEnginePushNative, _BarrageEnginePushDart>(
            'barrage_engine_push',
          ),
      renderFrame: lib.lookupFunction<
        _BarrageEngineRenderFrameNative,
        _BarrageEngineRenderFrameDart
      >('barrage_engine_render_frame'),
      setEmojiBitmapCallback: lib.lookupFunction<
        _SetEmojiBitmapCallbackNative,
        _SetEmojiBitmapCallbackDart
      >('set_emoji_bitmap_callback'),
      registerEmojiFromFlutter: lib.lookupFunction<
        _RegisterEmojiFromFlutterNative,
        _RegisterEmojiFromFlutterDart
      >('register_emoji_from_flutter'),
      registerEmojiFromLocalPath: lib.lookupFunction<
        _RegisterEmojiFromLocalPathNative,
        _RegisterEmojiFromLocalPathDart
      >('register_emoji_from_local_path'),
      registerEmojiFromUrl: lib.lookupFunction<
        _RegisterEmojiFromUrlNative,
        _RegisterEmojiFromUrlDart
      >('register_emoji_from_url'),
      setGlobalStroke: lib
          .lookupFunction<_SetGlobalStrokeNative, _SetGlobalStrokeDart>(
            'set_global_stroke',
          ),
      setGlobalShadow: lib
          .lookupFunction<_SetGlobalShadowNative, _SetGlobalShadowDart>(
            'set_global_shadow',
          ),
      setGlobalNeon: lib
          .lookupFunction<_SetGlobalNeonNative, _SetGlobalNeonDart>(
            'set_global_neon',
          ),
      setGlobalGradient: lib
          .lookupFunction<_SetGlobalGradientNative, _SetGlobalGradientDart>(
            'set_global_gradient',
          ),
    );
  }

  BarrageFfiBind._withLibrary({
    required _BarrageEngineCreateDart create,
    required _BarrageEngineDestroyDart destroy,
    required _BarrageEngineResizeDart resize,
    required _BarrageEngineSetSpeedDart setSpeed,
    required _BarrageEnginePauseDart pause,
    required _BarrageEngineResumeDart resume,
    required _BarrageEngineSeekDart seek,
    required _BarrageEngineClearDart clear,
    required _BarrageEnginePushDart push,
    required _BarrageEngineRenderFrameDart renderFrame,
    required _SetEmojiBitmapCallbackDart setEmojiBitmapCallback,
    required _RegisterEmojiFromFlutterDart registerEmojiFromFlutter,
    required _RegisterEmojiFromLocalPathDart registerEmojiFromLocalPath,
    required _RegisterEmojiFromUrlDart registerEmojiFromUrl,
    required _SetGlobalStrokeDart setGlobalStroke,
    required _SetGlobalShadowDart setGlobalShadow,
    required _SetGlobalNeonDart setGlobalNeon,
    required _SetGlobalGradientDart setGlobalGradient,
  }) : _create = create,
       _destroy = destroy,
       _resize = resize,
       _setSpeed = setSpeed,
       _pause = pause,
       _resume = resume,
       _seek = seek,
       _clear = clear,
       _push = push,
       _renderFrame = renderFrame,
       _setEmojiBitmapCallback = setEmojiBitmapCallback,
       _registerEmojiFromFlutter = registerEmojiFromFlutter,
       _registerEmojiFromLocalPath = registerEmojiFromLocalPath,
       _registerEmojiFromUrl = registerEmojiFromUrl,
       _setGlobalStroke = setGlobalStroke,
       _setGlobalShadow = setGlobalShadow,
       _setGlobalNeon = setGlobalNeon,
       _setGlobalGradient = setGlobalGradient;

  // -----------------------------------------------------------------------
  // 动态库加载
  // -----------------------------------------------------------------------

  /// 根据当前平台加载动态库
  static DynamicLibrary _loadLibrary() {
    try {
      if (Platform.isAndroid || Platform.isLinux) {
        return DynamicLibrary.open('lib$_libName.so');
      } else if (Platform.isIOS || Platform.isMacOS) {
        return DynamicLibrary.open('$_libName.framework/$_libName');
      } else if (Platform.isWindows) {
        return DynamicLibrary.open('$_libName.dll');
      } else {
        throw UnsupportedError(
          'Unsupported platform: ${Platform.operatingSystem}',
        );
      }
    } catch (e) {
      throw StateError(
        'Failed to load barrage native library "$_libName": $e\n'
        'Make sure the Rust core library is built and bundled correctly.',
      );
    }
  }

  // -----------------------------------------------------------------------
  // 引擎生命周期
  // -----------------------------------------------------------------------

  /// 创建弹幕引擎
  ///
  /// 返回不透明引擎句柄。失败时返回 nullptr。
  Pointer<_EngineHandle> createEngine(
    int width,
    int height,
    double fontRatio,
    double speed,
  ) {
    if (width <= 0 || height <= 0) {
      throw ArgumentError('Invalid engine dimensions: ${width}x$height');
    }
    return _create(width, height, fontRatio, speed);
  }

  /// 销毁弹幕引擎
  ///
  /// 调用后引擎句柄失效，不可再使用。
  void destroyEngine(Pointer<_EngineHandle> engine) {
    if (engine == nullptr) {
      throw StateError('Cannot destroy null engine handle');
    }
    _destroy(engine);
  }

  // -----------------------------------------------------------------------
  // 引擎控制
  // -----------------------------------------------------------------------

  /// 调整渲染区域大小
  void resize(Pointer<_EngineHandle> engine, int width, int height) {
    _checkEngine(engine);
    if (width <= 0 || height <= 0) {
      throw ArgumentError('Invalid resize dimensions: ${width}x$height');
    }
    _resize(engine, width, height);
  }

  /// 设置播放速度
  void setSpeed(Pointer<_EngineHandle> engine, double speed) {
    _checkEngine(engine);
    if (speed <= 0) {
      throw ArgumentError('Speed must be positive: $speed');
    }
    _setSpeed(engine, speed);
  }

  /// 暂停
  void pause(Pointer<_EngineHandle> engine) {
    _checkEngine(engine);
    _pause(engine);
  }

  /// 恢复
  void resume(Pointer<_EngineHandle> engine) {
    _checkEngine(engine);
    _resume(engine);
  }

  /// 跳转
  void seek(Pointer<_EngineHandle> engine, int timestampMs) {
    _checkEngine(engine);
    if (timestampMs < 0) {
      throw ArgumentError('Timestamp cannot be negative: $timestampMs');
    }
    _seek(engine, timestampMs);
  }

  /// 清空
  void clear(Pointer<_EngineHandle> engine) {
    _checkEngine(engine);
    _clear(engine);
  }

  // -----------------------------------------------------------------------
  // 弹幕推送
  // -----------------------------------------------------------------------

  /// 推送一条弹幕
  void pushBarrage(Pointer<_EngineHandle> engine, BarrageMsg msg) {
    _checkEngine(engine);

    // 使用 Arena 自动管理所有临时内存分配
    using((Arena arena) {
      final idPtr = _allocUtf8(arena, msg.id);
      final idLen = _utf8Length(msg.id);

      final textPtr = _allocUtf8(arena, msg.text);
      final textLen = _utf8Length(msg.text);

      // 渐变颜色数组
      Pointer<Uint32> gradientColorsPtr = nullptr;
      int gradientColorCount = 0;
      if (msg.textEffects.gradient.enabled &&
          msg.textEffects.gradient.type != GradientType.rainbow) {
        final colors = msg.textEffects.gradient.colors;
        gradientColorCount = colors.length;
        gradientColorsPtr = arena.allocate<Uint32>(gradientColorCount);
        for (var i = 0; i < colors.length; i++) {
          gradientColorsPtr[i] = _colorToRgba(colors[i]);
        }
      }

      _push(
        engine,
        idPtr,
        idLen,
        textPtr,
        textLen,
        msg.trackType.index,
        _colorToRgba(msg.color),
        msg.fontSize,
        msg.timestamp,
        // stroke
        msg.textEffects.stroke.enabled ? 1 : 0,
        msg.textEffects.stroke.width,
        _colorToRgba(msg.textEffects.stroke.color),
        msg.textEffects.stroke.isOuter ? 1 : 0,
        // shadow
        msg.textEffects.shadow.enabled ? 1 : 0,
        msg.textEffects.shadow.offsetX,
        msg.textEffects.shadow.offsetY,
        msg.textEffects.shadow.blur,
        _colorToRgba(msg.textEffects.shadow.color),
        msg.textEffects.shadow.layers,
        // neon
        msg.textEffects.neon.enabled ? 1 : 0,
        msg.textEffects.neon.radius,
        _colorToRgba(msg.textEffects.neon.color),
        msg.textEffects.neon.intensity,
        msg.textEffects.neon.layers,
        // gradient
        msg.textEffects.gradient.enabled ? 1 : 0,
        msg.textEffects.gradient.type.index,
        gradientColorsPtr,
        gradientColorCount,
        msg.textEffects.gradient.angle,
      );
    });
  }

  // -----------------------------------------------------------------------
  // 渲染
  // -----------------------------------------------------------------------

  /// 渲染一帧
  ///
  /// 返回指向内部 RGBA8888 缓冲区的指针。缓冲区在下次调用前有效。
  /// 返回 nullptr 表示渲染失败。
  Pointer<Uint8> renderFrame(Pointer<_EngineHandle> engine, int timestampMs) {
    _checkEngine(engine);
    if (timestampMs < 0) {
      throw ArgumentError('Timestamp cannot be negative: $timestampMs');
    }
    return _renderFrame(engine, timestampMs);
  }

  // -----------------------------------------------------------------------
  // Emoji 回调与注册
  // -----------------------------------------------------------------------

  /// 设置 emoji 位图请求回调
  void setEmojiBitmapCallback(
    Pointer<_EngineHandle> engine,
    Pointer<NativeFunction<_EmojiBitmapCallbackNative>> callback,
  ) {
    _checkEngine(engine);
    _setEmojiBitmapCallback(engine, callback);
  }

  /// 从 Flutter 位图注册 emoji
  void registerEmojiFromFlutter(
    Pointer<_EngineHandle> engine,
    String emojiText,
    Pointer<Uint8> pixels,
    int width,
    int height,
  ) {
    _checkEngine(engine);
    if (pixels == nullptr) {
      throw ArgumentError('Pixels pointer is null');
    }
    if (width <= 0 || height <= 0) {
      throw ArgumentError('Invalid emoji dimensions: ${width}x$height');
    }

    using((Arena arena) {
      final emojiPtr = _allocUtf8(arena, emojiText);
      final emojiLen = _utf8Length(emojiText);

      _registerEmojiFromFlutter(
        engine,
        emojiPtr,
        emojiLen,
        pixels,
        width,
        height,
      );
    });
  }

  /// 从本地文件路径注册 emoji
  void registerEmojiFromLocalPath(
    Pointer<_EngineHandle> engine,
    String emojiText,
    String path,
  ) {
    _checkEngine(engine);

    using((Arena arena) {
      final emojiPtr = _allocUtf8(arena, emojiText);
      final emojiLen = _utf8Length(emojiText);

      final pathPtr = _allocUtf8(arena, path);
      final pathLen = _utf8Length(path);

      _registerEmojiFromLocalPath(engine, emojiPtr, emojiLen, pathPtr, pathLen);
    });
  }

  /// 从网络 URL 注册 emoji
  void registerEmojiFromUrl(
    Pointer<_EngineHandle> engine,
    String emojiText,
    String url,
  ) {
    _checkEngine(engine);

    using((Arena arena) {
      final emojiPtr = _allocUtf8(arena, emojiText);
      final emojiLen = _utf8Length(emojiText);

      final urlPtr = _allocUtf8(arena, url);
      final urlLen = _utf8Length(url);

      _registerEmojiFromUrl(engine, emojiPtr, emojiLen, urlPtr, urlLen);
    });
  }

  // -----------------------------------------------------------------------
  // 全局特效
  // -----------------------------------------------------------------------

  /// 设置全局描边
  void setGlobalStroke(Pointer<_EngineHandle> engine, StrokeConfig config) {
    _checkEngine(engine);
    _setGlobalStroke(
      engine,
      config.enabled ? 1 : 0,
      config.width,
      _colorToRgba(config.color),
      config.isOuter ? 1 : 0,
    );
  }

  /// 设置全局阴影
  void setGlobalShadow(Pointer<_EngineHandle> engine, ShadowConfig config) {
    _checkEngine(engine);
    _setGlobalShadow(
      engine,
      config.enabled ? 1 : 0,
      config.offsetX,
      config.offsetY,
      config.blur,
      _colorToRgba(config.color),
      config.layers,
    );
  }

  /// 设置全局霓虹
  void setGlobalNeon(Pointer<_EngineHandle> engine, NeonConfig config) {
    _checkEngine(engine);
    _setGlobalNeon(
      engine,
      config.enabled ? 1 : 0,
      config.radius,
      _colorToRgba(config.color),
      config.intensity,
      config.layers,
    );
  }

  /// 设置全局渐变
  void setGlobalGradient(Pointer<_EngineHandle> engine, GradientConfig config) {
    _checkEngine(engine);

    using((Arena arena) {
      Pointer<Uint32> colorsPtr = nullptr;
      int colorCount = 0;

      if (config.enabled && config.type != GradientType.rainbow) {
        final colors = config.colors;
        colorCount = colors.length;
        colorsPtr = arena.allocate<Uint32>(colorCount);
        for (var i = 0; i < colors.length; i++) {
          colorsPtr[i] = _colorToRgba(colors[i]);
        }
      }

      _setGlobalGradient(
        engine,
        config.enabled ? 1 : 0,
        config.type.index,
        colorsPtr,
        colorCount,
        config.angle,
      );
    });
  }

  // -----------------------------------------------------------------------
  // 工具方法
  // -----------------------------------------------------------------------

  /// 检查引擎句柄是否有效
  void _checkEngine(Pointer<_EngineHandle> engine) {
    if (engine == nullptr) {
      throw StateError(
        'Barrage engine handle is null. '
        'The engine may have been disposed or not yet created.',
      );
    }
  }

  /// 将字符串编码为 UTF-8 并分配到 arena 内存中
  ///
  /// 返回指向 UTF-8 字节的指针。内存由 arena 管理，作用域结束时自动释放。
  static Pointer<Uint8> _allocUtf8(Arena arena, String str) {
    final bytes = utf8.encode(str);
    if (bytes.isEmpty) {
      // 确保至少分配 1 字节，避免空指针
      final ptr = arena.allocate<Uint8>(1);
      ptr.value = 0;
      return ptr;
    }
    final ptr = arena.allocate<Uint8>(bytes.length);
    ptr.asTypedList(bytes.length).setAll(0, bytes);
    return ptr;
  }

  /// 获取字符串的 UTF-8 编码长度
  static int _utf8Length(String str) {
    return utf8.encode(str).length;
  }

  /// 将 Color 转为 32 位 RGBA 整数（0xRRGGBBAA）
  static int _colorToRgba(Color color) {
    return (((color.r * 255).round().clamp(0, 255) & 0xFF) << 24) |
        (((color.g * 255).round().clamp(0, 255) & 0xFF) << 16) |
        (((color.b * 255).round().clamp(0, 255) & 0xFF) << 8) |
        ((color.a * 255).round().clamp(0, 255));
  }
}

// ---------------------------------------------------------------------------
// 顶层工具函数
// ---------------------------------------------------------------------------

/// 从 UTF-8 字节指针和长度解码 Dart 字符串
///
/// 异常时返回空字符串。
String utf8DecodeFromPointer(Pointer<Uint8> ptr, int length) {
  if (ptr == nullptr || length <= 0) return '';
  try {
    final bytes = ptr.asTypedList(length);
    return utf8.decode(bytes, allowMalformed: true);
  } catch (_) {
    return '';
  }
}

/// 将 Dart 字符串编码为 UTF-8 字节列表
///
/// 异常时返回空列表。
Uint8List utf8EncodeString(String str) {
  try {
    return Uint8List.fromList(utf8.encode(str));
  } catch (_) {
    return Uint8List(0);
  }
}
