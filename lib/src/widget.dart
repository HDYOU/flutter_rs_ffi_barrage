/// BarrageView 自定义 Widget - 弹幕渲染层
///
/// 提供基于 [CustomPaint] 的弹幕渲染 Widget，每帧从 Rust 引擎获取
/// RGBA 像素数据并通过 [dart:ui.Image] 绘制到屏幕。
///
/// 使用方式：
/// ```dart
/// final controller = BarrageController();
///
/// BarrageView(
///   controller: controller,
/// )
///
/// // 推送弹幕
/// controller.push(BarrageMsg(id: '1', text: 'Hello'));
///
/// // 控制播放
/// controller.pause();
/// controller.resume();
///
/// // 释放资源
/// controller.dispose();
/// ```
library;

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'engine.dart';
import 'types.dart';

// ---------------------------------------------------------------------------
// BarrageController - 弹幕控制器
// ---------------------------------------------------------------------------

/// 弹幕控制器
///
/// 管理弹幕引擎的生命周期，提供推送、暂停、恢复等控制方法。
/// 可独立使用或配合 [BarrageView] 使用。
///
/// 控制器采用时间驱动模式，内部维护一个播放时间轴。
/// 当与 [BarrageView] 配合使用时，时间轴由 Widget 的 ticker 驱动。
class BarrageController extends ChangeNotifier {
  /// 弹幕引擎实例
  final BarrageEngine _engine;

  /// 是否自动播放
  final bool autoPlay;

  /// 是否暂停
  bool _paused = false;

  /// 当前播放时间（毫秒）
  int _currentTime = 0;

  /// 是否已销毁
  bool _disposed = false;

  /// 当前渲染的帧图像
  ui.Image? _currentFrame;

  /// 创建弹幕控制器
  ///
  /// - [width] / [height]: 初始渲染尺寸（像素）
  /// - [fontRatio]: 字体大小占高度比例
  /// - [speed]: 滚动速度倍率
  /// - [autoPlay]: 是否自动开始播放
  factory BarrageController({
    int width = 1920,
    int height = 1080,
    double fontRatio = 0.04,
    double speed = 1.0,
    bool autoPlay = true,
  }) {
    final engine = BarrageEngine(
      width: width,
      height: height,
      fontRatio: fontRatio,
      speed: speed,
    );
    return BarrageController._(engine, autoPlay);
  }

  BarrageController._(this._engine, this.autoPlay) {
    _paused = !autoPlay;
  }

  /// 弹幕引擎
  BarrageEngine get engine => _engine;

  /// 渲染宽度
  int get width => _engine.width;

  /// 渲染高度
  int get height => _engine.height;

  /// 当前播放时间（毫秒）
  int get currentTime => _currentTime;

  /// 是否暂停
  bool get isPaused => _paused;

  /// 是否已销毁
  bool get isDisposed => _disposed;

  /// 当前帧图像（供渲染使用）
  ui.Image? get currentFrame => _currentFrame;

  // -----------------------------------------------------------------------
  // 尺寸调整
  // -----------------------------------------------------------------------

  /// 调整渲染尺寸
  ///
  /// 由 [BarrageView] 在布局变化时调用。
  void resize(int width, int height) {
    if (_disposed) return;
    if (width <= 0 || height <= 0) return;
    if (width == _engine.width && height == _engine.height) return;
    _engine.resize(width, height);
    notifyListeners();
  }

  // -----------------------------------------------------------------------
  // 播放控制
  // -----------------------------------------------------------------------

  /// 暂停弹幕滚动
  void pause() {
    if (_disposed || _paused) return;
    _paused = true;
    _engine.pause();
    notifyListeners();
  }

  /// 恢复弹幕滚动
  void resume() {
    if (_disposed || !_paused) return;
    _paused = false;
    _engine.resume();
    notifyListeners();
  }

  /// 跳转到指定时间点
  void seek(int timestampMs) {
    if (_disposed) return;
    _currentTime = timestampMs;
    _engine.seek(timestampMs);
    notifyListeners();
  }

  /// 设置滚动速度倍率
  void setSpeed(double speed) {
    if (_disposed) return;
    _engine.setSpeed(speed);
  }

  /// 清空所有弹幕
  void clear() {
    if (_disposed) return;
    _engine.clear();
    notifyListeners();
  }

  // -----------------------------------------------------------------------
  // 弹幕推送
  // -----------------------------------------------------------------------

  /// 推送一条弹幕
  void push(BarrageMsg msg) {
    if (_disposed) return;
    _engine.push(msg);
  }

  /// 批量推送弹幕
  void pushAll(List<BarrageMsg> messages) {
    if (_disposed) return;
    _engine.pushAll(messages);
  }

  // -----------------------------------------------------------------------
  // 全局特效
  // -----------------------------------------------------------------------

  /// 设置全局描边效果
  void setGlobalStroke(StrokeConfig config) {
    if (_disposed) return;
    _engine.setGlobalStroke(config);
  }

  /// 设置全局阴影效果
  void setGlobalShadow(ShadowConfig config) {
    if (_disposed) return;
    _engine.setGlobalShadow(config);
  }

  /// 设置全局霓虹效果
  void setGlobalNeon(NeonConfig config) {
    if (_disposed) return;
    _engine.setGlobalNeon(config);
  }

  /// 设置全局渐变效果
  void setGlobalGradient(GradientConfig config) {
    if (_disposed) return;
    _engine.setGlobalGradient(config);
  }

  // -----------------------------------------------------------------------
  // Emoji 相关
  // -----------------------------------------------------------------------

  /// 设置 emoji 位图回调
  void setEmojiBitmapCallback(EmojiBitmapCallback? callback) {
    if (_disposed) return;
    _engine.setEmojiBitmapCallback(callback);
  }

  /// 从 Flutter 位图注册 emoji
  void registerEmojiFromFlutterBitmap(
    String emojiText,
    Uint8List pixels,
    int width,
    int height,
  ) {
    if (_disposed) return;
    _engine.registerEmojiFromFlutterBitmap(emojiText, pixels, width, height);
  }

  /// 从本地文件注册 emoji
  void registerEmojiFromLocalPath(String emojiText, String path) {
    if (_disposed) return;
    _engine.registerEmojiFromLocalPath(emojiText, path);
  }

  /// 从网络 URL 注册 emoji
  void registerEmojiFromUrl(String emojiText, String url) {
    if (_disposed) return;
    _engine.registerEmojiFromUrl(emojiText, url);
  }

  // -----------------------------------------------------------------------
  // 帧更新（内部使用）
  // -----------------------------------------------------------------------

  /// 更新当前帧（由 Widget 的 ticker 驱动）
  ///
  /// [deltaMs] 为距离上一帧的毫秒增量。
  /// 返回值表示是否需要重新绘制。
  @internal
  bool updateFrame(int deltaMs) {
    if (_disposed || _paused) return false;

    _currentTime += deltaMs;
    final pixels = _engine.renderFrame(_currentTime);
    if (pixels == null) return false;

    // 异步解码像素数据为 ui.Image
    _decodeFrame(pixels, _engine.width, _engine.height);

    return true;
  }

  /// 解码像素数据为 ui.Image
  void _decodeFrame(Uint8List pixels, int width, int height) {
    if (_disposed) return;

    // 使用 dart:ui 的异步图像解码
    ui.decodeImageFromPixels(pixels, width, height, ui.PixelFormat.rgba8888, (
      ui.Image image,
    ) {
      if (_disposed) {
        image.dispose();
        return;
      }
      // 释放旧图像
      _currentFrame?.dispose();
      _currentFrame = image;
      notifyListeners();
    });
  }

  // -----------------------------------------------------------------------
  // 生命周期
  // -----------------------------------------------------------------------

  /// 销毁控制器和引擎
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;

    _currentFrame?.dispose();
    _currentFrame = null;

    _engine.dispose();
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// BarrageView - 弹幕渲染 Widget
// ---------------------------------------------------------------------------

/// 弹幕渲染视图
///
/// 使用 [CustomPaint] + [CustomPainter] 将弹幕引擎的渲染结果绘制到屏幕。
/// 每帧通过 ticker 驱动，调用引擎的 renderFrame 获取 RGBA 像素数据，
/// 解码为 [ui.Image] 后绘制。
///
/// 支持透明背景，可以叠加在视频或其他 Widget 上方。
///
/// 示例：
/// ```dart
/// BarrageView(
///   controller: _controller,
/// )
/// ```
class BarrageView extends StatefulWidget {
  /// 弹幕控制器
  ///
  /// 如果为 null，将自动创建一个默认控制器。
  final BarrageController? controller;

  /// 初始速度倍率
  final double speed;

  /// 是否自动开始播放
  final bool autoPlay;

  /// 背景色（默认透明）
  final Color backgroundColor;

  /// 创建弹幕视图
  const BarrageView({
    super.key,
    this.controller,
    this.speed = 1.0,
    this.autoPlay = true,
    this.backgroundColor = const Color(0x00000000),
  });

  @override
  State<BarrageView> createState() => _BarrageViewState();
}

class _BarrageViewState extends State<BarrageView>
    with SingleTickerProviderStateMixin {
  late BarrageController _controller;
  late Ticker _ticker;
  Duration _lastTick = Duration.zero;
  bool _isInternalController = false;

  @override
  void initState() {
    super.initState();

    if (widget.controller != null) {
      _controller = widget.controller!;
    } else {
      _controller = BarrageController(
        speed: widget.speed,
        autoPlay: widget.autoPlay,
      );
      _isInternalController = true;
    }

    _controller.addListener(_onControllerChanged);

    _ticker = createTicker(_onTick);
    _ticker.start();
  }

  @override
  void didUpdateWidget(covariant BarrageView oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.controller != oldWidget.controller) {
      _controller.removeListener(_onControllerChanged);

      // 释放内部创建的控制器
      if (_isInternalController) {
        _controller.dispose();
        _isInternalController = false;
      }

      if (widget.controller != null) {
        _controller = widget.controller!;
      } else {
        _controller = BarrageController(
          speed: widget.speed,
          autoPlay: widget.autoPlay,
        );
        _isInternalController = true;
      }

      _controller.addListener(_onControllerChanged);
    }
  }

  /// 控制器状态变化回调
  void _onControllerChanged() {
    if (mounted) {
      setState(() {
        // 触发重建以更新 CustomPainter
      });
    }
  }

  /// Ticker 回调 - 每帧调用
  void _onTick(Duration elapsed) {
    if (_controller.isDisposed) return;

    final delta =
        _lastTick == Duration.zero ? 0 : (elapsed - _lastTick).inMilliseconds;
    _lastTick = elapsed;

    // 更新帧
    _controller.updateFrame(delta);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 根据布局尺寸调整引擎大小
        final width = constraints.maxWidth.toInt();
        final height = constraints.maxHeight.toInt();

        if (width > 0 && height > 0) {
          // 使用 addPostFrameCallback 避免在 build 过程中调用 resize
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || _controller.isDisposed) return;
            if (_controller.width != width || _controller.height != height) {
              _controller.resize(width, height);
            }
          });
        }

        return CustomPaint(
          painter: _BarragePainter(
            frame: _controller.currentFrame,
            backgroundColor: widget.backgroundColor,
          ),
          size: Size.infinite,
          willChange: true,
          isComplex: true,
        );
      },
    );
  }

  @override
  void dispose() {
    _ticker.dispose();
    _controller.removeListener(_onControllerChanged);

    if (_isInternalController) {
      _controller.dispose();
    }

    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// _BarragePainter - 弹幕绘制器
// ---------------------------------------------------------------------------

/// 弹幕 CustomPainter
///
/// 将引擎渲染的 RGBA 图像绘制到画布上。
/// 支持透明背景，可与底层内容混合。
class _BarragePainter extends CustomPainter {
  /// 当前帧图像
  final ui.Image? frame;

  /// 背景颜色
  final Color backgroundColor;

  _BarragePainter({required this.frame, required this.backgroundColor});

  @override
  void paint(Canvas canvas, Size size) {
    // 绘制背景
    if (backgroundColor.opacity > 0) {
      final bgPaint = Paint()..color = backgroundColor;
      canvas.drawRect(Offset.zero & size, bgPaint);
    }

    // 绘制弹幕帧
    if (frame != null) {
      final image = frame!;
      final imageSize = Size(image.width.toDouble(), image.height.toDouble());

      // 计算缩放以适配容器
      final scaleX = size.width / imageSize.width;
      final scaleY = size.height / imageSize.height;
      final scale = scaleX < scaleY ? scaleX : scaleY;

      final scaledWidth = imageSize.width * scale;
      final scaledHeight = imageSize.height * scale;

      // 居中绘制
      final left = (size.width - scaledWidth) / 2;
      final top = (size.height - scaledHeight) / 2;

      final paint = Paint()..isAntiAlias = false;

      // 绘制图像
      canvas.drawImageRect(
        image,
        Offset.zero & imageSize,
        Offset(left, top) & Size(scaledWidth, scaledHeight),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BarragePainter oldDelegate) {
    return frame != oldDelegate.frame ||
        backgroundColor != oldDelegate.backgroundColor;
  }
}
