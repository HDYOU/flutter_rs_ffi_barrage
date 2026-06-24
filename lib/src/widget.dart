import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'engine.dart';
import 'package:flutter_rs_ffi_barrage/src/rust/api/common.dart' as common;

class BarrageController extends ChangeNotifier {
  final BarrageEngine _engine;
  final bool autoPlay;
  bool _paused = false;
  int _currentTime = 0;
  bool _disposed = false;

  BarrageController({
    int width = 800,
    int height = 600,
    double speed = 1.0,
    this.autoPlay = true,
  }) : _engine = BarrageEngine(width: width, height: height) {
    _engine.setSpeed(speed);
    if (!autoPlay) _engine.pause();
  }

  BarrageEngine get engine => _engine;
  bool get isPaused => _paused;
  bool get isDisposed => _disposed;
  int get currentTime => _currentTime;
  int get aliveCount => _engine.aliveCount;

  void setSpeed(double speed) {
    _ensureNotDisposed();
    _engine.setSpeed(speed);
  }

  void pause() {
    _ensureNotDisposed();
    _engine.pause();
    _paused = true;
    notifyListeners();
  }

  void resume() {
    _ensureNotDisposed();
    _engine.resume();
    _paused = false;
    notifyListeners();
  }

  void seek(int timestampMs) {
    _ensureNotDisposed();
    _engine.seek(timestampMs);
    _currentTime = timestampMs;
    notifyListeners();
  }

  void clear() {
    _ensureNotDisposed();
    _engine.clear();
  }

  void push(common.BarrageMsg msg) {
    _ensureNotDisposed();
    _engine.pushBarrage(msg);
  }

  Uint8List renderFrame(int timestampMs) {
    _ensureNotDisposed();
    _currentTime = timestampMs;
    return _engine.renderFrame(timestampMs);
  }

  void setGlobalStroke(common.StrokeConfig config) {
    _ensureNotDisposed();
    _engine.setGlobalStroke(config);
  }

  void setGlobalShadow(common.ShadowConfig config) {
    _ensureNotDisposed();
    _engine.setGlobalShadow(config);
  }

  void setGlobalNeon(common.NeonConfig config) {
    _ensureNotDisposed();
    _engine.setGlobalNeon(config);
  }

  void setGlobalGradient(common.GradientConfig config) {
    _ensureNotDisposed();
    _engine.setGlobalGradient(config);
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('BarrageController already disposed');
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _engine.dispose();
    super.dispose();
  }
}

class BarrageView extends StatefulWidget {
  final BarrageController controller;
  final Color backgroundColor;

  const BarrageView({
    super.key,
    required this.controller,
    this.backgroundColor = const Color(0x00000000),
  });

  @override
  State<BarrageView> createState() => _BarrageViewState();
}

class _BarrageViewState extends State<BarrageView>
    with SingleTickerProviderStateMixin {
  late Ticker _ticker;
  ui.Image? _frameImage;
  int _lastFrameMs = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _ticker.start();
  }

  void _onTick(Duration elapsed) {
    if (widget.controller.isDisposed) {
      _ticker.stop();
      return;
    }
    if (widget.controller.isPaused) return;

    final timestampMs = elapsed.inMilliseconds;
    if (timestampMs - _lastFrameMs < 16) return;
    _lastFrameMs = timestampMs;

    final pixels = widget.controller.renderFrame(timestampMs);
    if (pixels.isEmpty) return;

    _decodeAndSetImage(pixels);
  }

  Future<void> _decodeAndSetImage(Uint8List pixels) async {
    final engine = widget.controller.engine;
    final width = engine.width;
    final height = engine.height;

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
    setState(() {
      _frameImage = frame.image;
    });
    codec.dispose();
    descriptor.dispose();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _BarragePainter(
        image: _frameImage,
        backgroundColor: widget.backgroundColor,
      ),
      size: Size.infinite,
    );
  }
}

class _BarragePainter extends CustomPainter {
  final ui.Image? image;
  final Color backgroundColor;

  _BarragePainter({this.image, required this.backgroundColor});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(backgroundColor, BlendMode.srcOver);
    if (image != null) {
      canvas.drawImageRect(
        image!,
        Rect.fromLTWH(0, 0, image!.width.toDouble(), image!.height.toDouble()),
        Rect.fromLTWH(0, 0, size.width, size.height),
        Paint(),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BarragePainter oldDelegate) {
    return image != oldDelegate.image;
  }
}
