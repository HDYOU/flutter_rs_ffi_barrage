/// 表情工具类 - ui.Image 与 RGBA 字节数据互转
///
/// 提供 Flutter 图像数据与原始 RGBA 字节之间的转换功能，
/// 适配 Flutter >=3.41.0 的 dart:ui 新接口。
///
/// 使用 [ImageDescriptor] 和 [ImmutableBuffer] 等现代 API，
/// 避免使用已废弃的接口。
library;

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

// ---------------------------------------------------------------------------
// RGBA -> ui.Image
// ---------------------------------------------------------------------------

/// 将 RGBA8888 字节数据转换为 [ui.Image]
///
/// - [pixels]: RGBA8888 格式的像素数据，长度必须为 width * height * 4
/// - [width] / [height]: 图像尺寸
///
/// 返回解码后的 [ui.Image]，调用方负责在使用完毕后调用 [ui.Image.dispose]。
///
/// 使用 [ImageDescriptor.raw] + [ImmutableBuffer] 新 API，
/// 兼容 Flutter >=3.41.0。
Future<ui.Image> rgbaBytesToImage(Uint8List pixels, int width, int height) async {
  if (width <= 0 || height <= 0) {
    throw ArgumentError('Invalid image dimensions: ${width}x$height');
  }

  final expectedLen = width * height * 4;
  if (pixels.length != expectedLen) {
    throw ArgumentError(
      'Pixel data length (${pixels.length}) does not match '
      'width * height * 4 ($expectedLen)',
    );
  }

  // 使用 ImmutableBuffer 创建不可变缓冲区
  // 这是 Flutter 2.13+ 推荐的新 API，替代旧的内存拷贝方式
  final buffer = await ui.ImmutableBuffer.fromUint8List(pixels);

  try {
    // 使用 ImageDescriptor.raw 描述原始像素格式
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: width,
      height: height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );

    // 实例化解码器
    final codec = await descriptor.instantiateCodec(
      targetWidth: width,
      targetHeight: height,
    );

    try {
      // 获取第一帧（静态图像只有一帧）
      final frameInfo = await codec.getNextFrame();
      return frameInfo.image;
    } finally {
      codec.dispose();
    }
  } finally {
    // descriptor 不持有 buffer 的引用，buffer 需要手动释放
    // 但 ImageDescriptor.raw 会消费 buffer，所以这里不需要手动 dispose buffer
    // 如果 descriptor 创建失败，buffer 需要释放
    buffer.dispose();
  }
}

// ---------------------------------------------------------------------------
// ui.Image -> RGBA
// ---------------------------------------------------------------------------

/// 将 [ui.Image] 转换为 RGBA8888 字节数据
///
/// 返回的 [Uint8List] 长度为 image.width * image.height * 4。
/// 像素格式为 RGBA，每像素 4 字节。
///
/// 使用 [ui.Image.toByteData] 接口，兼容 Flutter >=3.41.0。
Future<Uint8List> imageToRgbaBytes(ui.Image image) async {
  final byteData = await image.toByteData(
    format: ui.ImageByteFormat.rawRgba,
  );

  if (byteData == null) {
    throw StateError('Failed to convert image to RGBA bytes');
  }

  // 将 ByteData 转换为 Uint8List
  // 注意：Uint8List.sublistView 创建的是视图而非拷贝，
  // 如果需要独立生命周期的列表，请使用 Uint8List.fromList
  return Uint8List.sublistView(byteData);
}

// ---------------------------------------------------------------------------
// 便捷方法：同步版本（基于已有字节数据）
// ---------------------------------------------------------------------------

/// 同步创建 RGBA 像素缓冲区
///
/// 创建指定尺寸的空白 RGBA 缓冲区，所有像素初始化为透明（0x00000000）。
Uint8List createRgbaBuffer(int width, int height) {
  if (width <= 0 || height <= 0) {
    throw ArgumentError('Invalid dimensions: ${width}x$height');
  }
  return Uint8List(width * height * 4);
}

/// 获取 RGBA 缓冲区中指定位置的像素颜色
///
/// - [buffer]: RGBA8888 缓冲区
/// - [width]: 图像宽度
/// - [x] / [y]: 像素坐标
///
/// 返回 RGBA 颜色值（0xRRGGBBAA）。
int getRgbaPixel(Uint8List buffer, int width, int x, int y) {
  final index = (y * width + x) * 4;
  if (index < 0 || index + 3 >= buffer.length) {
    throw RangeError('Pixel coordinates out of bounds: ($x, $y)');
  }
  return (buffer[index] << 24) |
      (buffer[index + 1] << 16) |
      (buffer[index + 2] << 8) |
      buffer[index + 3];
}

/// 设置 RGBA 缓冲区中指定位置的像素颜色
///
/// - [buffer]: RGBA8888 缓冲区
/// - [width]: 图像宽度
/// - [x] / [y]: 像素坐标
/// - [color]: RGBA 颜色值（0xRRGGBBAA）
void setRgbaPixel(Uint8List buffer, int width, int x, int y, int color) {
  final index = (y * width + x) * 4;
  if (index < 0 || index + 3 >= buffer.length) {
    throw RangeError('Pixel coordinates out of bounds: ($x, $y)');
  }
  buffer[index] = (color >> 24) & 0xFF; // R
  buffer[index + 1] = (color >> 16) & 0xFF; // G
  buffer[index + 2] = (color >> 8) & 0xFF; // B
  buffer[index + 3] = color & 0xFF; // A
}

// ---------------------------------------------------------------------------
// 图像缩放（基于字节缓冲的简易缩放）
// ---------------------------------------------------------------------------

/// 缩放 RGBA 图像（最近邻插值）
///
/// 简单的 CPU 缩放实现，用于 emoji 位图的尺寸调整。
/// 对于高质量缩放，建议使用 Flutter 的 [ui.Image] 缩放能力。
///
/// - [srcPixels]: 源 RGBA 数据
/// - [srcWidth] / [srcHeight]: 源尺寸
/// - [dstWidth] / [dstHeight]: 目标尺寸
///
/// 返回缩放后的 RGBA 数据。
Uint8List scaleRgbaNearest(
  Uint8List srcPixels,
  int srcWidth,
  int srcHeight,
  int dstWidth,
  int dstHeight,
) {
  if (srcWidth <= 0 || srcHeight <= 0) {
    throw ArgumentError('Invalid source dimensions: ${srcWidth}x$srcHeight');
  }
  if (dstWidth <= 0 || dstHeight <= 0) {
    throw ArgumentError('Invalid target dimensions: ${dstWidth}x$dstHeight');
  }

  final srcExpected = srcWidth * srcHeight * 4;
  if (srcPixels.length != srcExpected) {
    throw ArgumentError(
      'Source pixel data length (${srcPixels.length}) does not match '
      'srcWidth * srcHeight * 4 ($srcExpected)',
    );
  }

  final dstPixels = Uint8List(dstWidth * dstHeight * 4);

  final xRatio = srcWidth / dstWidth;
  final yRatio = srcHeight / dstHeight;

  for (var y = 0; y < dstHeight; y++) {
    final srcY = (y * yRatio).floor().clamp(0, srcHeight - 1);
    for (var x = 0; x < dstWidth; x++) {
      final srcX = (x * xRatio).floor().clamp(0, srcWidth - 1);

      final srcIdx = (srcY * srcWidth + srcX) * 4;
      final dstIdx = (y * dstWidth + x) * 4;

      dstPixels[dstIdx] = srcPixels[srcIdx]; // R
      dstPixels[dstIdx + 1] = srcPixels[srcIdx + 1]; // G
      dstPixels[dstIdx + 2] = srcPixels[srcIdx + 2]; // B
      dstPixels[dstIdx + 3] = srcPixels[srcIdx + 3]; // A
    }
  }

  return dstPixels;
}

// ---------------------------------------------------------------------------
// 图像校验
// ---------------------------------------------------------------------------

/// 校验 RGBA 缓冲区是否有效
///
/// 检查缓冲区长度是否与尺寸匹配。
bool validateRgbaBuffer(Uint8List buffer, int width, int height) {
  if (width <= 0 || height <= 0) return false;
  if (buffer.isEmpty) return false;
  return buffer.length == width * height * 4;
}

/// 计算 RGBA 缓冲区的预期长度
int rgbaBufferLength(int width, int height) {
  return width * height * 4;
}
