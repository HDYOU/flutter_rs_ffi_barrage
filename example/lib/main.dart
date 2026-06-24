import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_rs_ffi_barrage/flutter_rs_ffi_barrage.dart';

// ---------------------------------------------------------------------------
// 程序入口
// ---------------------------------------------------------------------------

void main() {
  runApp(const BarrageDemoApp());
}

/// 弹幕演示应用
class BarrageDemoApp extends StatelessWidget {
  const BarrageDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Rust FFI 弹幕演示',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const BarrageDemoPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// ---------------------------------------------------------------------------
// 主页面
// ---------------------------------------------------------------------------

/// 弹幕演示主页
///
/// 展示 flutter_rs_ffi_barrage 插件的全部核心功能：
/// - 自定义 EmojiBitmapCallback 实现（Rust 主动回调 Dart）
/// - 三种 Emoji 注册方式（Flutter 位图 / 本地文件 / 网络 URL）
/// - 四大文字特效（描边 / 立体阴影 / 霓虹发光 / 彩虹渐变）
/// - 四种轨道类型（滚动 / 顶部 / 底部 / 逆向）
/// - 弹幕控制（暂停 / 恢复 / 清空 / 速度 / 跳转）
/// - BarrageView 透明叠加效果
class BarrageDemoPage extends StatefulWidget {
  const BarrageDemoPage({super.key});

  @override
  State<BarrageDemoPage> createState() => _BarrageDemoPageState();
}

class _BarrageDemoPageState extends State<BarrageDemoPage> {
  // -----------------------------------------------------------------------
  // 弹幕控制器
  // -----------------------------------------------------------------------

  late final BarrageController _controller;
  final TextEditingController _inputController = TextEditingController();

  // -----------------------------------------------------------------------
  // 特效开关状态
  // -----------------------------------------------------------------------

  bool _strokeEnabled = false;
  bool _shadowEnabled = false;
  bool _neonEnabled = false;
  bool _gradientEnabled = false;

  // -----------------------------------------------------------------------
  // 轨道类型
  // -----------------------------------------------------------------------

  TrackType _selectedTrackType = TrackType.scrolling;

  // -----------------------------------------------------------------------
  // 速度控制
  // -----------------------------------------------------------------------

  double _currentSpeed = 1.0;

  // -----------------------------------------------------------------------
  // 弹幕计数（用于生成唯一 ID）
  // -----------------------------------------------------------------------

  int _barrageCount = 0;

  // -----------------------------------------------------------------------
  // 生命周期
  // -----------------------------------------------------------------------

  @override
  void initState() {
    super.initState();

    // 创建弹幕控制器
    _controller = BarrageController(speed: _currentSpeed, autoPlay: true);

    // ================================================================
    // 场景 A：注入自定义 EmojiBitmapCallback 到 BarrageEngine
    // ================================================================
    // 当 Rust 渲染引擎遇到未注册的 emoji 时，会通过 FFI 回调
    // 到 Dart 侧请求位图数据。这是 Rust 主动调用 Dart 的典型场景。
    _controller.setEmojiBitmapCallback(_customEmojiBitmapCallback);

    // ================================================================
    // 场景 D：主动预注册表情（演示三种注册方式）
    // ================================================================
    _preRegisterEmojis();

    // 推送一些初始弹幕用于演示
    _pushInitialDemoBarrages();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _controller.dispose();
    super.dispose();
  }

  // =====================================================================
  // 场景 A：自定义 EmojiBitmapCallback 实现
  // =====================================================================

  /// 自定义 emoji 位图回调函数
  ///
  /// 此函数由 Rust 侧通过 FFI 主动调用，用于按需获取 emoji 位图。
  /// - 识别 "[666]" 返回一个红色笑脸位图（内存生成 RGBA）
  /// - 识别 "[好]" 返回一个绿色点赞位图
  /// - 其他表情返回 null，让其降级为纯文字渲染
  ///
  /// [emojiText] 为 emoji 文本标识
  /// [width] / [height] 为期望的位图尺寸
  /// 返回 RGBA8888 格式的像素数据，失败返回 null
  Uint8List? _customEmojiBitmapCallback(
    String emojiText,
    int width,
    int height,
  ) {
    // 识别 "[666]" → 红色笑脸位图
    if (emojiText == '[666]') {
      return _generateSmileyBitmap(width, height, const Color(0xFFFF4444));
    }

    // 识别 "[好]" → 绿色点赞位图
    if (emojiText == '[好]') {
      return _generateThumbsUpBitmap(width, height, const Color(0xFF44CC44));
    }

    // 其他表情返回 null → 降级为纯文字
    return null;
  }

  /// 生成红色笑脸 RGBA 位图（程序化生成）
  ///
  /// 在内存中绘制一个圆形笑脸：
  /// - 圆形脸（指定颜色）
  /// - 两个黑色眼睛
  /// - 微笑的嘴巴
  Uint8List _generateSmileyBitmap(int width, int height, Color faceColor) {
    final pixels = Uint8List(width * height * 4);
    final centerX = width / 2;
    final centerY = height / 2;
    final faceRadius = min(width, height) * 0.42;

    // 眼睛位置
    final eyeOffsetX = faceRadius * 0.35;
    final eyeOffsetY = -faceRadius * 0.2;
    final eyeRadius = faceRadius * 0.12;

    // 嘴巴（微笑弧线）参数
    final mouthCenterY = centerY + faceRadius * 0.2;
    final mouthWidth = faceRadius * 0.5;
    final mouthHeight = faceRadius * 0.25;

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final idx = (y * width + x) * 4;
        double alpha = 0.0;

        final dx = x - centerX;
        final dy = y - centerY;
        final dist = sqrt(dx * dx + dy * dy);

        // 绘制脸部圆形（带抗锯齿边缘）
        if (dist <= faceRadius) {
          if (dist >= faceRadius - 1.5) {
            alpha = (faceRadius - dist) / 1.5; // 边缘抗锯齿
          } else {
            alpha = 1.0;
          }

          // 绘制眼睛（黑色）
          final leftEyeDx = x - (centerX - eyeOffsetX);
          final leftEyeDy = y - (centerY + eyeOffsetY);
          final leftEyeDist = sqrt(
            leftEyeDx * leftEyeDx + leftEyeDy * leftEyeDy,
          );

          final rightEyeDx = x - (centerX + eyeOffsetX);
          final rightEyeDy = y - (centerY + eyeOffsetY);
          final rightEyeDist = sqrt(
            rightEyeDx * rightEyeDx + rightEyeDy * rightEyeDy,
          );

          if (leftEyeDist <= eyeRadius || rightEyeDist <= eyeRadius) {
            pixels[idx] = 0; // R
            pixels[idx + 1] = 0; // G
            pixels[idx + 2] = 0; // B
            pixels[idx + 3] = (255 * alpha).round(); // A
            continue;
          }

          // 绘制微笑嘴巴（椭圆弧线）
          final mouthDx = x - centerX;
          final mouthDy = y - mouthCenterY;
          final mouthDist =
              (mouthDx * mouthDx) / (mouthWidth * mouthWidth) +
              (mouthDy * mouthDy) / (mouthHeight * mouthHeight);

          if (mouthDist <= 1.0 && mouthDy > 0) {
            pixels[idx] = 0; // R
            pixels[idx + 1] = 0; // G
            pixels[idx + 2] = 0; // B
            pixels[idx + 3] = (255 * alpha).round(); // A
            continue;
          }

          // 脸部填充色
          pixels[idx] = (faceColor.r * 255).round().clamp(0, 255);
          pixels[idx + 1] = (faceColor.g * 255).round().clamp(0, 255);
          pixels[idx + 2] = (faceColor.b * 255).round().clamp(0, 255);
          pixels[idx + 3] = (255 * alpha).round();
        } else {
          // 透明背景
          pixels[idx] = 0;
          pixels[idx + 1] = 0;
          pixels[idx + 2] = 0;
          pixels[idx + 3] = 0;
        }
      }
    }

    return pixels;
  }

  /// 生成绿色点赞 RGBA 位图（程序化生成）
  ///
  /// 在内存中绘制一个竖起大拇指的图标：
  /// - 圆形背景（指定颜色）
  /// - 白色竖起的大拇指
  Uint8List _generateThumbsUpBitmap(int width, int height, Color bgColor) {
    final pixels = Uint8List(width * height * 4);
    final centerX = width / 2;
    final centerY = height / 2;
    final bgRadius = min(width, height) * 0.45;

    // 手掌区域
    final palmLeft = centerX - bgRadius * 0.35;
    final palmRight = centerX + bgRadius * 0.2;
    final palmTop = centerY - bgRadius * 0.1;
    final palmBottom = centerY + bgRadius * 0.35;

    // 大拇指
    final thumbLeft = centerX + bgRadius * 0.05;
    final thumbRight = centerX + bgRadius * 0.3;
    final thumbTop = centerY - bgRadius * 0.4;
    final thumbBottom = centerY - bgRadius * 0.05;

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final idx = (y * width + x) * 4;

        final dx = x - centerX;
        final dy = y - centerY;
        final dist = sqrt(dx * dx + dy * dy);

        if (dist <= bgRadius) {
          double alpha = 1.0;
          if (dist >= bgRadius - 1.5) {
            alpha = (bgRadius - dist) / 1.5;
          }

          // 判断是否在手掌区域
          bool inPalm =
              x >= palmLeft &&
              x <= palmRight &&
              y >= palmTop &&
              y <= palmBottom;

          // 判断是否在大拇指区域
          bool inThumb =
              x >= thumbLeft &&
              x <= thumbRight &&
              y >= thumbTop &&
              y <= thumbBottom;

          // 大拇指和手掌连接处的圆角
          if (inThumb || inPalm) {
            // 白色图标
            pixels[idx] = 255;
            pixels[idx + 1] = 255;
            pixels[idx + 2] = 255;
            pixels[idx + 3] = (255 * alpha).round();
          } else {
            // 背景色
            pixels[idx] = (bgColor.r * 255).round().clamp(0, 255);
            pixels[idx + 1] = (bgColor.g * 255).round().clamp(0, 255);
            pixels[idx + 2] = (bgColor.b * 255).round().clamp(0, 255);
            pixels[idx + 3] = (255 * alpha).round();
          }
        } else {
          // 透明背景
          pixels[idx] = 0;
          pixels[idx + 1] = 0;
          pixels[idx + 2] = 0;
          pixels[idx + 3] = 0;
        }
      }
    }

    return pixels;
  }

  // =====================================================================
  // 场景 D：预注册 Emoji（三种注册方式）
  // =====================================================================

  /// 预注册演示用的表情
  ///
  /// 演示三种 Emoji 注册方式：
  /// 1. 从 Flutter 位图注册（registerEmojiFromFlutterBitmap）
  /// 2. 从本地文件路径注册（registerEmojiFromLocalPath）
  /// 3. 从网络 URL 注册（registerEmojiFromUrl）
  void _preRegisterEmojis() {
    // 方式 1：从 Flutter 位图注册（内存生成的蓝色星星表情）
    const starSize = 64;
    final starPixels = _generateStarBitmap(
      starSize,
      starSize,
      const Color(0xFFFFD700),
    );
    _controller.registerEmojiFromFlutterBitmap(
      '[星星]',
      starPixels,
      starSize,
      starSize,
    );

    // 方式 2：从本地文件路径注册（示例路径，实际使用时替换为真实路径）
    // _controller.registerEmojiFromLocalPath(
    //   '[爱心]',
    //   '/path/to/assets/heart.png',
    // );

    // 方式 3：从网络 URL 注册（示例 URL，实际使用时替换为真实 URL）
    // _controller.registerEmojiFromUrl(
    //   '[火焰]',
    //   'https://example.com/emoji/fire.png',
    // );
  }

  /// 生成金色星星 RGBA 位图（用于演示 Flutter 位图注册方式）
  Uint8List _generateStarBitmap(int width, int height, Color color) {
    final pixels = Uint8List(width * height * 4);
    final cx = width / 2;
    final cy = height / 2;
    final outerR = min(width, height) * 0.42;
    final innerR = outerR * 0.4;

    // 五角星的 5 个外点和 5 个内点
    final points = <Offset>[];
    for (int i = 0; i < 10; i++) {
      final angle = -pi / 2 + i * pi / 5;
      final r = i.isEven ? outerR : innerR;
      points.add(Offset(cx + r * cos(angle), cy + r * sin(angle)));
    }

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final idx = (y * width + x) * 4;

        if (_isPointInPolygon(x.toDouble(), y.toDouble(), points)) {
          // 简单的径向渐变效果（中心亮边缘稍暗）
          final dx = x - cx;
          final dy = y - cy;
          final dist = sqrt(dx * dx + dy * dy);
          final ratio = 1.0 - (dist / outerR) * 0.3;

          pixels[idx] = (color.r * 255 * ratio).round().clamp(0, 255);
          pixels[idx + 1] = (color.g * 255 * ratio).round().clamp(0, 255);
          pixels[idx + 2] = (color.b * 255 * ratio).round().clamp(0, 255);
          pixels[idx + 3] = 255;
        } else {
          pixels[idx] = 0;
          pixels[idx + 1] = 0;
          pixels[idx + 2] = 0;
          pixels[idx + 3] = 0;
        }
      }
    }

    return pixels;
  }

  /// 判断点是否在多边形内（射线法）
  bool _isPointInPolygon(double x, double y, List<Offset> polygon) {
    bool inside = false;
    for (int i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final xi = polygon[i].dx, yi = polygon[i].dy;
      final xj = polygon[j].dx, yj = polygon[j].dy;

      if (((yi > y) != (yj > y)) &&
          (x < (xj - xi) * (y - yi) / (yj - yi) + xi)) {
        inside = !inside;
      }
    }
    return inside;
  }

  // =====================================================================
  // 场景 C & G：初始演示弹幕
  // =====================================================================

  /// 推送初始演示弹幕
  void _pushInitialDemoBarrages() {
    const demoTexts = [
      '欢迎来到 Flutter Rust FFI 弹幕演示！',
      '高性能弹幕引擎，纯 Rust 渲染',
      '[666] 666 走一波！[666]',
      '[好] 这个插件真不错 [好]',
      '[星星] 支持三种 Emoji 注册方式 [星星]',
      '描边 / 阴影 / 霓虹 / 渐变 四大特效',
      '滚动 / 顶部 / 底部 / 逆向 四种轨道',
      'Rust 主动回调 Dart 获取 Emoji 位图',
      'CPU 软件渲染，全平台一致体验',
      '透明叠加，完美融入视频背景',
    ];

    final colors = [
      Colors.white,
      Colors.yellow,
      Colors.cyan,
      Colors.pinkAccent,
      Colors.lightGreen,
      Colors.orange,
      Colors.lightBlue,
      Colors.amber,
    ];

    final random = Random(42);

    for (int i = 0; i < demoTexts.length; i++) {
      final msg = BarrageMsg(
        id: 'demo_$i',
        text: demoTexts[i],
        trackType: TrackType.scrolling,
        color: colors[i % colors.length],
        fontSize: 24 + random.nextDouble() * 12,
        timestamp: i * 800, // 每条间隔 800ms
        textEffects: _buildCurrentEffectConfig(),
      );
      _controller.push(msg);
      _barrageCount++;
    }
  }

  // =====================================================================
  // 场景 E：手动调用 getEmojiBitmapFromFlutter 查询贴图
  // =====================================================================

  /// 手动查询 emoji 位图并显示对话框
  Future<void> _queryEmojiBitmap(String emojiText) async {
    final result = _controller.engine.getEmojiBitmapFromFlutter(emojiText, 64);

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Emoji 位图查询结果'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('表情标识: $emojiText'),
              const SizedBox(height: 12),
              if (result != null) ...[
                Text('尺寸: ${result.width} x ${result.height}'),
                const SizedBox(height: 8),
                Text('像素数: ${result.pixels.length ~/ 4}'),
                const SizedBox(height: 12),
                FutureBuilder<ui.Image>(
                  future: _decodeRgbaToImage(
                    result.pixels,
                    result.width,
                    result.height,
                  ),
                  builder: (context, snapshot) {
                    if (snapshot.hasData) {
                      return RawImage(
                        image: snapshot.data,
                        width: 128,
                        height: 128,
                        scale: 1.0,
                      );
                    }
                    return const CircularProgressIndicator();
                  },
                ),
              ] else
                const Text(
                  '未找到对应位图（返回 null）\n该表情将降级为纯文字渲染',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.red),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  /// RGBA 字节解码为 ui.Image
  Future<ui.Image> _decodeRgbaToImage(
    Uint8List pixels,
    int width,
    int height,
  ) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(pixels);
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: width,
      height: height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final codec = await descriptor.instantiateCodec(
      targetWidth: width,
      targetHeight: height,
    );
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }

  // =====================================================================
  // 弹幕发送
  // =====================================================================

  /// 发送一条弹幕
  void _sendBarrage() {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;

    _barrageCount++;
    final msg = BarrageMsg(
      id: 'user_${_barrageCount}_${DateTime.now().millisecondsSinceEpoch}',
      text: text,
      trackType: _selectedTrackType,
      color: _randomColor(),
      fontSize: 24 + Random().nextDouble() * 8,
      timestamp: _controller.currentTime,
      textEffects: _buildCurrentEffectConfig(),
    );

    _controller.push(msg);
    _inputController.clear();
  }

  /// 构建当前特效配置
  TextEffectConfig _buildCurrentEffectConfig() {
    return TextEffectConfig(
      stroke:
          _strokeEnabled
              ? const StrokeConfig(
                enabled: true,
                width: 2.5,
                color: Color(0xFF000000),
                isOuter: true,
              )
              : const StrokeConfig(),
      shadow:
          _shadowEnabled
              ? const ShadowConfig(
                enabled: true,
                offsetX: 3.0,
                offsetY: 3.0,
                blur: 0.0,
                color: Color(0x80000000),
                layers: 3,
              )
              : const ShadowConfig(),
      neon:
          _neonEnabled
              ? const NeonConfig(
                enabled: true,
                radius: 10.0,
                color: Color(0xFFFF00FF),
                intensity: 0.8,
                layers: 4,
              )
              : const NeonConfig(),
      gradient:
          _gradientEnabled
              ? const GradientConfig(
                enabled: true,
                type: GradientType.rainbow,
                colors: [],
                angle: 0.0,
              )
              : const GradientConfig(),
    );
  }

  /// 生成随机明亮颜色
  Color _randomColor() {
    final random = Random();
    final colors = [
      Colors.white,
      Colors.yellow,
      Colors.cyan,
      Colors.pinkAccent,
      Colors.lightGreen,
      Colors.orange,
      Colors.lightBlue,
      Colors.amber,
      Colors.tealAccent,
      Colors.deepOrange,
    ];
    return colors[random.nextInt(colors.length)];
  }

  // =====================================================================
  // 场景 F：特效演示按钮
  // =====================================================================

  /// 发送描边特效弹幕
  void _sendStrokeDemo() {
    _barrageCount++;
    _controller.push(
      BarrageMsg(
        id: 'stroke_demo_$_barrageCount',
        text: '描边特效弹幕 Stroke Effect',
        trackType: TrackType.scrolling,
        color: const Color(0xFFFFFFFF),
        fontSize: 32,
        timestamp: _controller.currentTime,
        textEffects: const TextEffectConfig(
          stroke: StrokeConfig(
            enabled: true,
            width: 3.0,
            color: Color(0xFFFF0000),
            isOuter: true,
          ),
        ),
      ),
    );
  }

  /// 发送阴影特效弹幕
  void _sendShadowDemo() {
    _barrageCount++;
    _controller.push(
      BarrageMsg(
        id: 'shadow_demo_$_barrageCount',
        text: '立体阴影弹幕 3D Shadow',
        trackType: TrackType.scrolling,
        color: const Color(0xFFFFD700),
        fontSize: 32,
        timestamp: _controller.currentTime,
        textEffects: const TextEffectConfig(
          shadow: ShadowConfig(
            enabled: true,
            offsetX: 4.0,
            offsetY: 4.0,
            blur: 0.0,
            color: Color(0x80000000),
            layers: 4,
          ),
        ),
      ),
    );
  }

  /// 发送霓虹特效弹幕
  void _sendNeonDemo() {
    _barrageCount++;
    _controller.push(
      BarrageMsg(
        id: 'neon_demo_$_barrageCount',
        text: '霓虹发光弹幕 Neon Glow',
        trackType: TrackType.scrolling,
        color: const Color(0xFFFFFFFF),
        fontSize: 32,
        timestamp: _controller.currentTime,
        textEffects: const TextEffectConfig(
          neon: NeonConfig(
            enabled: true,
            radius: 12.0,
            color: Color(0xFF00FFFF),
            intensity: 0.9,
            layers: 5,
          ),
        ),
      ),
    );
  }

  /// 发送渐变特效弹幕
  void _sendGradientDemo() {
    _barrageCount++;
    _controller.push(
      BarrageMsg(
        id: 'gradient_demo_$_barrageCount',
        text: '彩虹渐变弹幕 Rainbow Gradient',
        trackType: TrackType.scrolling,
        color: const Color(0xFFFFFFFF),
        fontSize: 32,
        timestamp: _controller.currentTime,
        textEffects: const TextEffectConfig(
          gradient: GradientConfig(
            enabled: true,
            type: GradientType.rainbow,
            colors: [],
            angle: 0.0,
          ),
        ),
      ),
    );
  }

  /// 发送多特效叠加弹幕
  void _sendMixedEffectDemo() {
    _barrageCount++;
    _controller.push(
      BarrageMsg(
        id: 'mixed_demo_$_barrageCount',
        text: '多特效叠加 Mixed Effects! [666]',
        trackType: TrackType.scrolling,
        color: const Color(0xFFFFFFFF),
        fontSize: 36,
        timestamp: _controller.currentTime,
        textEffects: const TextEffectConfig(
          stroke: StrokeConfig(
            enabled: true,
            width: 2.0,
            color: Color(0xFF000000),
            isOuter: true,
          ),
          shadow: ShadowConfig(
            enabled: true,
            offsetX: 2.0,
            offsetY: 2.0,
            blur: 0.0,
            color: Color(0x60000000),
            layers: 2,
          ),
          neon: NeonConfig(
            enabled: true,
            radius: 8.0,
            color: Color(0xFFFF00FF),
            intensity: 0.7,
            layers: 3,
          ),
          gradient: GradientConfig(
            enabled: true,
            type: GradientType.rainbow,
            colors: [],
            angle: 0.0,
          ),
        ),
      ),
    );
  }

  // =====================================================================
  // 场景 G：轨道类型演示
  // =====================================================================

  /// 发送指定轨道类型的弹幕
  void _sendTrackTypeDemo(TrackType type) {
    _barrageCount++;
    final typeNames = {
      TrackType.scrolling: '滚动弹幕',
      TrackType.top: '顶部弹幕',
      TrackType.bottom: '底部弹幕',
      TrackType.reverse: '逆向弹幕',
    };

    _controller.push(
      BarrageMsg(
        id: 'track_${type.name}_$_barrageCount',
        text: '${typeNames[type]} [好]',
        trackType: type,
        color: _randomColor(),
        fontSize: 28,
        timestamp: _controller.currentTime,
        textEffects: const TextEffectConfig(
          stroke: StrokeConfig(
            enabled: true,
            width: 2.0,
            color: Color(0xFF000000),
          ),
        ),
      ),
    );
  }

  // =====================================================================
  // 速度控制
  // =====================================================================

  void _increaseSpeed() {
    setState(() {
      _currentSpeed = (_currentSpeed + 0.25).clamp(0.25, 5.0);
      _controller.setSpeed(_currentSpeed);
    });
  }

  void _decreaseSpeed() {
    setState(() {
      _currentSpeed = (_currentSpeed - 0.25).clamp(0.25, 5.0);
      _controller.setSpeed(_currentSpeed);
    });
  }

  // =====================================================================
  // 特效开关切换（应用到全局）
  // =====================================================================

  void _toggleStroke(bool value) {
    setState(() {
      _strokeEnabled = value;
      _controller.setGlobalStroke(
        value
            ? const StrokeConfig(
              enabled: true,
              width: 2.5,
              color: Color(0xFF000000),
            )
            : const StrokeConfig(),
      );
    });
  }

  void _toggleShadow(bool value) {
    setState(() {
      _shadowEnabled = value;
      _controller.setGlobalShadow(
        value
            ? const ShadowConfig(
              enabled: true,
              offsetX: 3.0,
              offsetY: 3.0,
              layers: 3,
            )
            : const ShadowConfig(),
      );
    });
  }

  void _toggleNeon(bool value) {
    setState(() {
      _neonEnabled = value;
      _controller.setGlobalNeon(
        value
            ? const NeonConfig(
              enabled: true,
              radius: 10.0,
              color: Color(0xFFFF00FF),
              layers: 4,
            )
            : const NeonConfig(),
      );
    });
  }

  void _toggleGradient(bool value) {
    setState(() {
      _gradientEnabled = value;
      _controller.setGlobalGradient(
        value
            ? const GradientConfig(enabled: true, type: GradientType.rainbow)
            : const GradientConfig(),
      );
    });
  }

  // =====================================================================
  // 构建 UI
  // =====================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Flutter Rust FFI 弹幕演示'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: '查询 Emoji 位图',
            onPressed: () => _queryEmojiBitmap('[666]'),
          ),
        ],
      ),
      body: Column(
        children: [
          // -----------------------------------------------------------
          // 弹幕渲染区域（Stack 叠加展示透明效果）
          // -----------------------------------------------------------
          Expanded(flex: 3, child: _buildBarrageArea()),

          // -----------------------------------------------------------
          // 特效选择区
          // -----------------------------------------------------------
          _buildEffectTogglePanel(),

          // -----------------------------------------------------------
          // 轨道类型选择
          // -----------------------------------------------------------
          _buildTrackTypePanel(),

          // -----------------------------------------------------------
          // 输入框和发送按钮
          // -----------------------------------------------------------
          _buildInputPanel(),

          // -----------------------------------------------------------
          // 控制面板
          // -----------------------------------------------------------
          _buildControlPanel(),
        ],
      ),
    );
  }

  /// 构建弹幕渲染区域（场景 I：透明叠加效果）
  Widget _buildBarrageArea() {
    return Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1a1a2e),
            Color(0xFF16213e),
            Color(0xFF0f3460),
            Color(0xFF533483),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 底层：装饰性背景元素
            Positioned.fill(child: CustomPaint(painter: _BackgroundPainter())),
            // 中间层：一些文字标识（证明 BarrageView 是透明的）
            const Positioned(
              left: 20,
              bottom: 20,
              child: Text(
                '背景层 - BarrageView 透明叠加',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            // 顶层：弹幕渲染视图（透明背景，叠加在背景之上）
            BarrageView(
              controller: _controller,
              backgroundColor: const Color(0x00000000), // 完全透明
            ),
          ],
        ),
      ),
    );
  }

  /// 构建特效开关面板（场景 F）
  Widget _buildEffectTogglePanel() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: Colors.grey.shade100,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '全局文字特效（应用于后续弹幕）',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: _buildEffectSwitch(
                  '描边',
                  _strokeEnabled,
                  _toggleStroke,
                  Colors.red,
                ),
              ),
              Expanded(
                child: _buildEffectSwitch(
                  '阴影',
                  _shadowEnabled,
                  _toggleShadow,
                  Colors.grey,
                ),
              ),
              Expanded(
                child: _buildEffectSwitch(
                  '霓虹',
                  _neonEnabled,
                  _toggleNeon,
                  Colors.purple,
                ),
              ),
              Expanded(
                child: _buildEffectSwitch(
                  '渐变',
                  _gradientEnabled,
                  _toggleGradient,
                  Colors.teal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // 单特效演示按钮
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildDemoButton('描边演示', _sendStrokeDemo),
                const SizedBox(width: 6),
                _buildDemoButton('阴影演示', _sendShadowDemo),
                const SizedBox(width: 6),
                _buildDemoButton('霓虹演示', _sendNeonDemo),
                const SizedBox(width: 6),
                _buildDemoButton('渐变演示', _sendGradientDemo),
                const SizedBox(width: 6),
                _buildDemoButton('混合特效', _sendMixedEffectDemo, accent: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 构建单个特效开关
  Widget _buildEffectSwitch(
    String label,
    bool value,
    ValueChanged<bool> onChanged,
    Color activeColor,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: activeColor,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: value ? activeColor : Colors.grey.shade700,
            fontWeight: value ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  /// 构建演示按钮
  Widget _buildDemoButton(
    String text,
    VoidCallback onPressed, {
    bool accent = false,
  }) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: accent ? Colors.deepPurple : Colors.blueGrey.shade200,
        foregroundColor: accent ? Colors.white : Colors.black87,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const TextStyle(fontSize: 12),
      ),
      child: Text(text),
    );
  }

  /// 构建轨道类型选择面板（场景 G）
  Widget _buildTrackTypePanel() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: Colors.grey.shade200,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '轨道类型（发送弹幕时使用）',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(child: _buildTrackButton('滚动', TrackType.scrolling)),
              const SizedBox(width: 6),
              Expanded(child: _buildTrackButton('顶部', TrackType.top)),
              const SizedBox(width: 6),
              Expanded(child: _buildTrackButton('底部', TrackType.bottom)),
              const SizedBox(width: 6),
              Expanded(child: _buildTrackButton('逆向', TrackType.reverse)),
            ],
          ),
          const SizedBox(height: 4),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildDemoButton(
                  '发滚动弹幕',
                  () => _sendTrackTypeDemo(TrackType.scrolling),
                ),
                const SizedBox(width: 6),
                _buildDemoButton(
                  '发顶部弹幕',
                  () => _sendTrackTypeDemo(TrackType.top),
                ),
                const SizedBox(width: 6),
                _buildDemoButton(
                  '发底部弹幕',
                  () => _sendTrackTypeDemo(TrackType.bottom),
                ),
                const SizedBox(width: 6),
                _buildDemoButton(
                  '发逆向弹幕',
                  () => _sendTrackTypeDemo(TrackType.reverse),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 构建轨道选择按钮
  Widget _buildTrackButton(String label, TrackType type) {
    final isSelected = _selectedTrackType == type;
    return ElevatedButton(
      onPressed: () {
        setState(() {
          _selectedTrackType = type;
        });
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected ? Colors.deepPurple : Colors.white,
        foregroundColor: isSelected ? Colors.white : Colors.black87,
        padding: const EdgeInsets.symmetric(vertical: 8),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        side: BorderSide(
          color: isSelected ? Colors.deepPurple : Colors.grey.shade400,
          width: 1,
        ),
      ),
      child: Text(label),
    );
  }

  /// 构建输入面板
  Widget _buildInputPanel() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _inputController,
              decoration: InputDecoration(
                hintText: '输入弹幕内容，支持 [666] [好] [星星] 等表情',
                hintStyle: const TextStyle(fontSize: 13, color: Colors.grey),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                isDense: true,
              ),
              onSubmitted: (_) => _sendBarrage(),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _sendBarrage,
            icon: const Icon(Icons.send, size: 18),
            label: const Text('发送'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              textStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建控制面板（场景 H）
  Widget _buildControlPanel() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.inversePrimary.withValues(alpha: 0.3),
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildControlButton(
            icon: Icons.pause,
            label: '暂停',
            onPressed: () {
              _controller.pause();
              setState(() {});
            },
          ),
          _buildControlButton(
            icon: Icons.play_arrow,
            label: '恢复',
            onPressed: () {
              _controller.resume();
              setState(() {});
            },
          ),
          _buildControlButton(
            icon: Icons.delete_sweep,
            label: '清空',
            onPressed: () {
              _controller.clear();
              setState(() {});
            },
          ),
          _buildSpeedControl(),
          _buildControlButton(
            icon: Icons.replay,
            label: '跳转0s',
            onPressed: () {
              _controller.seek(0);
              _pushInitialDemoBarrages();
              setState(() {});
            },
          ),
        ],
      ),
    );
  }

  /// 构建控制按钮
  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(icon, size: 22),
          onPressed: onPressed,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 40, minHeight: 36),
        ),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }

  /// 构建速度控制
  Widget _buildSpeedControl() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.remove, size: 18),
              onPressed: _decreaseSpeed,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
            Text(
              '${_currentSpeed.toStringAsFixed(2)}x',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            IconButton(
              icon: const Icon(Icons.add, size: 18),
              onPressed: _increaseSpeed,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
          ],
        ),
        const Text('速度', style: TextStyle(fontSize: 11)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 背景装饰绘制器
// ---------------------------------------------------------------------------

/// 背景装饰绘制器 - 用于演示 BarrageView 的透明叠加效果
///
/// 绘制一些装饰性的圆形和线条，证明弹幕层是透明的，
/// 可以清晰地看到底层内容。
class _BackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // 绘制几个装饰性圆形
    final paint =
        Paint()
          ..color = Colors.white.withValues(alpha: 0.05)
          ..style = PaintingStyle.fill;

    // 大圆形
    canvas.drawCircle(
      Offset(size.width * 0.2, size.height * 0.3),
      size.width * 0.15,
      paint,
    );

    canvas.drawCircle(
      Offset(size.width * 0.8, size.height * 0.7),
      size.width * 0.2,
      paint,
    );

    // 网格线
    final gridPaint =
        Paint()
          ..color = Colors.white.withValues(alpha: 0.03)
          ..strokeWidth = 1;

    const gridSize = 40.0;
    for (double x = 0; x < size.width; x += gridSize) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += gridSize) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // 中心水印文字
    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'Flutter × Rust',
        style: TextStyle(
          color: Color(0x10FFFFFF),
          fontSize: 72,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(
      canvas,
      Offset(
        (size.width - textPainter.width) / 2,
        (size.height - textPainter.height) / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _BackgroundPainter oldDelegate) => false;
}
