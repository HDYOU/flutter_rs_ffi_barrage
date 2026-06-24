/// flutter_rs_ffi_barrage - High-performance Flutter Barrage Plugin
///
/// Powered by Rust FFI with pure extern "C" exports and direct Dart:ffi binding.
/// No C glue layer, no cbindgen, no .h header files.
///
/// Key Features:
/// - Pure Rust <-> Dart FFI interaction (zero C intermediary)
/// - Four track types: scrolling, top-fixed, bottom-fixed, reverse
/// - Three emoji loading modes: Flutter bitmap, local assets, remote URL
/// - Rust-to-Dart callback for on-demand emoji bitmap fetching
/// - Four stackable text effects: stroke, 3D shadow, neon glow, gradient
/// - CPU-based RGBA8888 software rendering
/// - Cross-platform: Android, iOS, Windows, macOS, Linux
///
/// Architecture:
/// ```
/// Dart Layer                          Rust Layer
/// ┌─────────────────────┐             ┌─────────────────────┐
/// │  BarrageView        │             │  Render Pipeline    │
/// │  (Widget)           │             │  (CPU RGBA)         │
/// ├─────────────────────┤             ├─────────────────────┤
/// │  BarrageEngine      │   FFI       │  Core Engine        │
/// │  (Dart API)         │◄───────────►│  (Track/Filter/Time)│
/// ├─────────────────────┤  bare       ├─────────────────────┤
/// │  ffi_bind.dart      │  symbols    │  ffi/exports.rs     │
/// │  (manual binding)   │────────────►│  (extern "C" +      │
/// │                     │◄────────────│   #[no_mangle])     │
/// └─────────────────────┘             └─────────────────────┘
///         ▲                                    ▲
///         │ getEmojiBitmapFromFlutter          │
///         └──────────── callback ──────────────┘
/// ```

library flutter_rs_ffi_barrage;

export 'src/engine.dart';
export 'src/types.dart';
export 'src/widget.dart';
export 'src/emoji_helper.dart';
