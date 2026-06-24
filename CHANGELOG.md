# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2024-06-24

### Added

- Initial release of flutter_rs_ffi_barrage
- Pure Rust extern "C" exports with Dart:ffi direct binding
- Zero C glue layer — no cbindgen, no .h headers, no C structs
- Four track types: scrolling, top-fixed, bottom-fixed, reverse scrolling
- Smart track collision avoidance algorithm
- Three emoji loading modes: Flutter bitmap, local assets, remote URL
- Rust-to-Dart callback for on-demand emoji bitmap fetching
- Four stackable text effects: stroke, 3D shadow, neon glow, gradient
  - Stroke: inner/outer, custom width, color, soft edge
  - Shadow: multi-layer 3D relief effect
  - Neon: multi-layer concentric glow
  - Gradient: linear, radial, rainbow
- CPU-based RGBA8888 software rendering pipeline
- crossbeam lock-free concurrent queue for non-blocking barrage submission
- parking_lot lightweight read-write locks
- LRU memory cache for emoji bitmaps
- Millisecond-accurate time control: 0.25x~4.0x speed, seek, pause/resume, clear
- Barrage filtering: keyword blacklist, type toggles, short duration filter
- Barrage object memory pool to reduce heap fragmentation
- Full platform support: Android, iOS, Windows, macOS, Linux
- Native-assets auto-compilation via pure Dart hook/build.dart
- Complete example app with all feature demos
- Three GitHub Actions CI workflows:
  - rust_ci.yml: fmt, clippy, test, bench, cross-platform compile
  - dart_flutter_ci.yml: format, analyze, test, publish dry-run
  - full_build_all_platform.yml: all 5 platforms parallel build + artifact upload
