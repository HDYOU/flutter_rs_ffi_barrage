/// 弹幕插件纯 Dart 数据类型定义
///
/// 本文件只包含纯 Dart 数据结构，不涉及任何 FFI 绑定或 C 兼容类型。
/// 所有类型均为值类型，可安全地在 Dart 层传递和序列化。
library;

import 'dart:typed_data';
import 'dart:ui';

// ---------------------------------------------------------------------------
// 轨道类型
// ---------------------------------------------------------------------------

/// 弹幕轨道类型
///
/// 决定弹幕在屏幕上的运动方式和显示位置。
enum TrackType {
  /// 从右向左滚动的普通弹幕
  scrolling,

  /// 顶部固定弹幕，从上到下依次排列
  top,

  /// 底部固定弹幕，从下到上依次排列
  bottom,

  /// 从左向右滚动的反向弹幕
  reverse,
}

// ---------------------------------------------------------------------------
// 渐变类型
// ---------------------------------------------------------------------------

/// 渐变填充类型
enum GradientType {
  /// 线性渐变
  linear,

  /// 径向渐变
  radial,

  /// 彩虹渐变（多色线性过渡）
  rainbow,
}

// ---------------------------------------------------------------------------
// 文字特效配置
// ---------------------------------------------------------------------------

/// 描边效果配置
class StrokeConfig {
  /// 是否启用描边
  final bool enabled;

  /// 描边宽度（像素）
  final double width;

  /// 描边颜色
  final Color color;

  /// 是否为外描边
  ///
  /// true 为外描边（文字外扩），false 为内描边（文字内缩）。
  final bool isOuter;

  /// 创建描边配置
  const StrokeConfig({
    this.enabled = false,
    this.width = 2.0,
    this.color = const Color(0xFF000000),
    this.isOuter = true,
  });

  /// 创建启用状态的描边配置（便捷构造）
  factory StrokeConfig.enabled({
    double width = 2.0,
    Color color = const Color(0xFF000000),
    bool isOuter = true,
  }) =>
      StrokeConfig(enabled: true, width: width, color: color, isOuter: isOuter);
}

/// 阴影效果配置
class ShadowConfig {
  /// 是否启用阴影
  final bool enabled;

  /// 阴影 X 轴偏移（像素）
  final double offsetX;

  /// 阴影 Y 轴偏移（像素）
  final double offsetY;

  /// 阴影模糊半径（像素）
  final double blur;

  /// 阴影颜色
  final Color color;

  /// 阴影层数（多层叠加产生立体效果）
  ///
  /// 每层阴影会沿偏移方向递进，层数越多立体效果越强。
  final int layers;

  /// 创建阴影配置
  const ShadowConfig({
    this.enabled = false,
    this.offsetX = 2.0,
    this.offsetY = 2.0,
    this.blur = 0.0,
    this.color = const Color(0x80000000),
    this.layers = 1,
  });

  /// 创建启用状态的阴影配置（便捷构造）
  factory ShadowConfig.enabled({
    double offsetX = 2.0,
    double offsetY = 2.0,
    double blur = 0.0,
    Color color = const Color(0x80000000),
    int layers = 1,
  }) => ShadowConfig(
    enabled: true,
    offsetX: offsetX,
    offsetY: offsetY,
    blur: blur,
    color: color,
    layers: layers,
  );
}

/// 霓虹发光效果配置
class NeonConfig {
  /// 是否启用霓虹效果
  final bool enabled;

  /// 发光半径（像素）
  final double radius;

  /// 发光颜色
  final Color color;

  /// 发光强度（0.0 - 1.0）
  final double intensity;

  /// 发光层数（多层叠加产生更强的光晕）
  final int layers;

  /// 创建霓虹配置
  const NeonConfig({
    this.enabled = false,
    this.radius = 8.0,
    this.color = const Color(0xFFFF00FF),
    this.intensity = 0.8,
    this.layers = 3,
  });

  /// 创建启用状态的霓虹配置（便捷构造）
  factory NeonConfig.enabled({
    double radius = 8.0,
    Color color = const Color(0xFFFF00FF),
    double intensity = 0.8,
    int layers = 3,
  }) => NeonConfig(
    enabled: true,
    radius: radius,
    color: color,
    intensity: intensity,
    layers: layers,
  );
}

/// 渐变填充配置
class GradientConfig {
  /// 是否启用渐变
  final bool enabled;

  /// 渐变类型
  final GradientType type;

  /// 渐变颜色列表
  ///
  /// 至少需要 2 种颜色。对于 [GradientType.rainbow]，颜色列表会被忽略，
  /// 使用内置的彩虹色阶。
  final List<Color> colors;

  /// 渐变角度（度）
  ///
  /// 0° 表示从左到右，90° 表示从上到下，依次类推。
  /// 仅对线性渐变有效。
  final double angle;

  /// 创建渐变配置
  const GradientConfig({
    this.enabled = false,
    this.type = GradientType.linear,
    this.colors = const [Color(0xFFFF0000), Color(0xFF0000FF)],
    this.angle = 0.0,
  });

  /// 创建启用状态的渐变配置（便捷构造）
  factory GradientConfig.enabled({
    GradientType type = GradientType.linear,
    List<Color> colors = const [Color(0xFFFF0000), Color(0xFF0000FF)],
    double angle = 0.0,
  }) => GradientConfig(enabled: true, type: type, colors: colors, angle: angle);
}

/// 文字特效组合配置
///
/// 所有特效可叠加使用，渲染顺序为：描边 → 阴影 → 霓虹 → 渐变填充。
class TextEffectConfig {
  /// 描边效果
  final StrokeConfig stroke;

  /// 阴影效果
  final ShadowConfig shadow;

  /// 霓虹发光效果
  final NeonConfig neon;

  /// 渐变填充效果
  final GradientConfig gradient;

  /// 创建文字特效配置
  const TextEffectConfig({
    this.stroke = const StrokeConfig(),
    this.shadow = const ShadowConfig(),
    this.neon = const NeonConfig(),
    this.gradient = const GradientConfig(),
  });

  /// 无特效的默认配置
  static const TextEffectConfig none = TextEffectConfig();

  /// 是否启用了任意特效
  bool get hasAnyEffect =>
      stroke.enabled || shadow.enabled || neon.enabled || gradient.enabled;
}

// ---------------------------------------------------------------------------
// 弹幕消息
// ---------------------------------------------------------------------------

/// 单条弹幕消息
///
/// 包含弹幕的所有显示属性。通过 [BarrageEngine] 推送到渲染队列。
class BarrageMsg {
  /// 弹幕唯一标识符
  ///
  /// 用于去重、查找和控制特定弹幕。建议使用全局唯一 ID。
  final String id;

  /// 弹幕文本内容
  final String text;

  /// 轨道类型
  final TrackType trackType;

  /// 文字颜色
  final Color color;

  /// 字体大小（像素）
  final double fontSize;

  /// 时间戳（毫秒）
  ///
  /// 弹幕在视频/直播时间轴上的出现时间点。
  /// 对于实时弹幕，通常设置为当前播放时间。
  final int timestamp;

  /// 文字特效配置
  final TextEffectConfig textEffects;

  /// 创建弹幕消息
  BarrageMsg({
    required this.id,
    required this.text,
    this.trackType = TrackType.scrolling,
    this.color = const Color(0xFFFFFFFF),
    this.fontSize = 24.0,
    this.timestamp = 0,
    this.textEffects = TextEffectConfig.none,
  });
}

// ---------------------------------------------------------------------------
// Emoji 位图结果
// ---------------------------------------------------------------------------

/// Emoji 位图查询结果
///
/// 当 Dart 侧通过回调向 Flutter 请求 emoji 位图时，返回此结构。
class EmojiBitmapResult {
  /// 位图宽度（像素）
  final int width;

  /// 位图高度（像素）
  final int height;

  /// RGBA8888 格式的像素数据
  ///
  /// 长度必须等于 width * height * 4。
  final Uint8List pixels;

  /// 创建 emoji 位图结果
  EmojiBitmapResult({
    required this.width,
    required this.height,
    required this.pixels,
  }) : assert(
         pixels.length == width * height * 4,
         'pixels length (${pixels.length}) must equal width * height * 4 '
         '(${width * height * 4})',
       );
}
