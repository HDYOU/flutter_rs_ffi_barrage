import 'dart:typed_data';

import 'package:flutter_rs_ffi_barrage/src/rust/api/engine.dart' as api;
import 'package:flutter_rs_ffi_barrage/src/rust/api/common.dart' as common;
import 'package:flutter_rs_ffi_barrage/src/rust/core/engine.dart' as core;
import 'package:flutter_rs_ffi_barrage/src/rust/frb_generated.dart';

typedef EmojiBitmapCallback = Uint8List? Function(
  String emojiText,
  int width,
  int height,
);

class BarrageEngine {
  late final api.EngineHandle _handle;
  final int _width;
  final int _height;
  bool _disposed = false;

  BarrageEngine({required int width, required int height})
      : _width = width,
        _height = height {
    RustLib.instance;
    _handle = api.EngineHandle.create(width: width, height: height);
  }

  int get width => _width;
  int get height => _height;
  bool get isDisposed => _disposed;

  void resize(int width, int height) {
    _ensureNotDisposed();
    _handle.resize(width: width, height: height);
  }

  void setSpeed(double speed) {
    _ensureNotDisposed();
    _handle.setSpeed(speed: speed);
  }

  void pause() {
    _ensureNotDisposed();
    _handle.pause();
  }

  void resume() {
    _ensureNotDisposed();
    _handle.resume();
  }

  void seek(int timestampMs) {
    _ensureNotDisposed();
    _handle.seek(timestampMs: timestampMs);
  }

  void clear() {
    _ensureNotDisposed();
    _handle.clear();
  }

  bool pushBarrage(common.BarrageMsg msg) {
    _ensureNotDisposed();
    return _handle.pushBarrage(msg: msg);
  }

  Uint8List renderFrame(int timestampMs) {
    _ensureNotDisposed();
    return _handle.renderFrame(timestampMs: timestampMs);
  }

  void setGlobalStroke(common.StrokeConfig config) {
    _ensureNotDisposed();
    _handle.setGlobalStroke(config: config);
  }

  void setGlobalShadow(common.ShadowConfig config) {
    _ensureNotDisposed();
    _handle.setGlobalShadow(config: config);
  }

  void setGlobalNeon(common.NeonConfig config) {
    _ensureNotDisposed();
    _handle.setGlobalNeon(config: config);
  }

  void setGlobalGradient(common.GradientConfig config) {
    _ensureNotDisposed();
    _handle.setGlobalGradient(config: config);
  }

  int get aliveCount {
    _ensureNotDisposed();
    return _handle.aliveCount();
  }

  core.PlayState get playState {
    _ensureNotDisposed();
    return _handle.playState();
  }

  int get currentTime {
    _ensureNotDisposed();
    return _handle.currentTime();
  }

  static String get version => '1.0.0';

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('BarrageEngine already disposed');
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
  }
}

void initializeRustLib() {
  RustLib.instance;
}
