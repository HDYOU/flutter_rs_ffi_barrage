// Copyright (c) 2024 flutter_rs_ffi_barrage Authors.
//
// Native Assets build hook for flutter_rs_ffi_barrage.
// Compiles the Rust core library (native/rs_core) via cargo and bundles
// the resulting dynamic library as a native code asset.
//
// Uses the official Dart hooks + code_assets packages:
//   - package:hooks/hooks.dart      → build(), BuildInput, BuildOutputBuilder
//   - package:code_assets/code_assets.dart → CodeAsset, DynamicLoadingBundled
//
// IMPORTANT:
// No C headers are generated. No cbindgen is invoked. This project uses
// pure Rust extern "C" exports with manually-written Dart:ffi bindings.
//
// Architecture:
//   Dart Layer (ffi_bind.dart)  <-->  Rust Layer (extern "C" + #[no_mangle])
//         ^  direct symbol lookup, zero C glue / zero .h files  ^

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

/// Build hook entry point – called by the Dart / Flutter SDK.
///
/// Uses the official `build()` function from package:hooks to parse
/// the input and write the output, following the standard native-assets
/// build protocol used by Flutter 3.41+.
void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) {
      return;
    }

    final codeConfig = input.config.code;
    final packageName = input.packageName;
    final packageRoot = input.packageRoot;
    final targetOS = codeConfig.targetOS;
    final targetArch = codeConfig.targetArchitecture;
    final linkMode = codeConfig.linkModePreference;

    // Always build in release mode for optimal performance.
    const buildMode = 'release';

    _section('flutter_rs_ffi_barrage – native-assets build hook');
    _info('Package:  $packageName');
    _info('Target:   ${targetOS.name} / ${targetArch.name}');
    _info('Mode:     $buildMode / ${linkMode.name}');
    _info('No C headers generated - pure Rust extern C + Dart:ffi binding');

    // -------------------------------------------------------------------
    // 1. 🔍 环境检测
    // -------------------------------------------------------------------
    _step('🔍 环境检测');

    await _checkRustToolchain();

    final rustTarget = _mapRustTarget(targetOS, targetArch);
    _info('Rust target:  $rustTarget');

    final buildEnv = <String, String>{};

    if (targetOS == OS.android) {
      final ndkEnv = await _checkAndroidNdkAndGetEnv(rustTarget);
      buildEnv.addAll(ndkEnv);
    } else if (targetOS == OS.macOS || targetOS == OS.iOS) {
      // Set Apple SDK environment variables so cc-rs (used by ring, etc.)
      // can find TargetConditionals.h and other system headers.
      final sdkEnv = await _appleSdkEnv(targetOS, targetArch);
      buildEnv.addAll(sdkEnv);
    }

    // -------------------------------------------------------------------
    // 2. 🔨 编译准备 & 增量检查
    // -------------------------------------------------------------------
    _step('🔨 编译准备');

    final rsCoreDir = Directory.fromUri(packageRoot.resolve('native/rs_core/'));
    if (!await rsCoreDir.exists()) {
      throw Exception('Rust source directory not found: ${rsCoreDir.path}');
    }

    final libName = _libNameFor(targetOS);
    final targetDir = Directory.fromUri(
      rsCoreDir.uri.resolve('target/$rustTarget/$buildMode/'),
    );
    final libPath = File.fromUri(targetDir.uri.resolve(libName));

    final outDir = input.outputDirectoryShared;
    if (!await Directory.fromUri(outDir).exists()) {
      await Directory.fromUri(outDir).create(recursive: true);
    }

    // 增量编译检查：基于源码文件修改时间
    final sourceHash = await _computeSourceHash(rsCoreDir);
    final hashFile = File.fromUri(outDir.resolve('.build_hash_$rustTarget'));
    final lastHash =
        await hashFile.exists() ? await hashFile.readAsString() : '';

    if (lastHash == sourceHash && await libPath.exists()) {
      _info('📦 源码未变更，跳过编译，使用缓存产物');
    } else {
      // -----------------------------------------------------------------
      // 3. 🚀 编译 Rust 核心库
      // -----------------------------------------------------------------
      _step('🚀 编译 Rust 核心库');

      final cargoArgs = ['build', '--$buildMode', '--target', rustTarget];

      _info('cargo ${cargoArgs.join(' ')}');

      final result = await Process.run(
        'cargo',
        cargoArgs,
        workingDirectory: rsCoreDir.path,
        environment: {...Platform.environment, ...buildEnv},
      );

      if (result.exitCode != 0) {
        stderr.writeln('❌ Cargo build failed (exit code ${result.exitCode})');
        stderr.writeln('--- stdout ---');
        stderr.writeln(result.stdout);
        stderr.writeln('--- stderr ---');
        stderr.writeln(result.stderr);
        throw Exception('Cargo build failed with exit code ${result.exitCode}');
      }

      // 输出 cargo 的警告信息
      final stderrOutput = result.stderr.toString();
      if (stderrOutput.isNotEmpty) {
        final lines = stderrOutput
            .split('\n')
            .where((l) => l.contains('warning:'))
            .take(10);
        for (final line in lines) {
          _info('⚠️  $line');
        }
      }

      _info('✅ Cargo build completed');
      await hashFile.writeAsString(sourceHash);
    }

    // 验证产物
    if (!await libPath.exists()) {
      throw Exception('Compiled library not found: ${libPath.path}');
    }

    final libSize = await libPath.length();
    _info('📦 产物大小: ${(libSize / 1024 / 1024).toStringAsFixed(2)} MB');

    // -------------------------------------------------------------------
    // 4. 📝 拷贝产物到输出目录 & 注册资产
    // -------------------------------------------------------------------
    _step('📝 注册原生代码资产');

    // 拷贝产物到共享输出目录
    final assetDirUri = outDir.resolve('${targetOS.name}/${targetArch.name}/');
    final assetDir = Directory.fromUri(assetDirUri);
    if (!await assetDir.exists()) {
      await assetDir.create(recursive: true);
    }

    final assetFileUri = assetDirUri.resolve(libName);
    await libPath.copy(assetFileUri.toFilePath());
    _info('📋 产物已拷贝: ${assetFileUri.toFilePath()}');

    // 注册代码资产
    output.assets.code.add(
      CodeAsset(
        package: packageName,
        name: 'src/ffi_bind.dart',
        linkMode: DynamicLoadingBundled(),
        file: assetFileUri,
      ),
    );

    // 声明依赖（用于增量构建缓存失效）
    output.dependencies.add(packageRoot.resolve('native/rs_core/Cargo.toml'));
    output.dependencies.add(packageRoot.resolve('native/rs_core/build.rs'));

    _info('✅ 代码资产已注册: package:$packageName/src/ffi_bind.dart');

    // -------------------------------------------------------------------
    // 完成
    // -------------------------------------------------------------------
    _section('✅ 构建完成');
    _info('平台:        ${targetOS.name} / ${targetArch.name}');
    _info('Rust target: $rustTarget');
    _info('产物:        ${assetFileUri.toFilePath()}');
    _info('大小:        ${(libSize / 1024 / 1024).toStringAsFixed(2)} MB');
  });
}

// ---------------------------------------------------------------------------
// 环境检测
// ---------------------------------------------------------------------------

Future<void> _checkRustToolchain() async {
  try {
    final result = await Process.run('cargo', ['--version']);
    if (result.exitCode == 0) {
      _info('✅ Rust / Cargo: ${(result.stdout as String).trim()}');
    } else {
      _error('Cargo not found');
      _installRustHint();
      throw Exception('Rust toolchain not found');
    }
  } catch (e) {
    _error('Rust toolchain not found: $e');
    _installRustHint();
    rethrow;
  }
}

void _installRustHint() {
  _info('');
  _info('💡 Install Rust toolchain:');
  _info(
    '   macOS / Linux:  curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh',
  );
  _info('   Windows:        Download from https://rustup.rs/');
  _info('');
  _info('💡 For Android cross-compilation:');
  _info('   - Set ANDROID_NDK_HOME environment variable');
  _info(
    '   - rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android',
  );
  _info('');
}

/// Auto-detect Android NDK from common locations and environment variables.
///
/// Search order:
///   1. ANDROID_NDK_HOME
///   2. ANDROID_NDK
///   3. NDK_HOME
///   4. ANDROID_HOME/ndk/* (pick latest version)
///   5. ANDROID_SDK_ROOT/ndk/*
Future<String?> _findAndroidNdk() async {
  // Direct NDK path environment variables
  final directVars = ['ANDROID_NDK_HOME', 'ANDROID_NDK', 'NDK_HOME'];
  for (final varName in directVars) {
    final val = Platform.environment[varName];
    if (val != null && val.isNotEmpty) {
      final dir = Directory(val);
      if (await dir.exists()) {
        return val;
      }
    }
  }

  // Auto-detect from Android SDK ndk/ directory
  final sdkVars = ['ANDROID_HOME', 'ANDROID_SDK_ROOT'];
  for (final varName in sdkVars) {
    final sdkPath = Platform.environment[varName];
    if (sdkPath == null || sdkPath.isEmpty) continue;
    final ndkDir = Directory('$sdkPath/ndk');
    if (!await ndkDir.exists()) continue;

    // Find the latest NDK version directory
    String? latest;
    await for (final entity in ndkDir.list()) {
      if (entity is Directory) {
        final name = entity.uri.pathSegments.lastWhere(
          (s) => s.isNotEmpty,
          orElse: () => '',
        );
        if (name.isEmpty) continue;
        // Prefer directories that look like version numbers
        if (latest == null || name.compareTo(latest) > 0) {
          latest = name;
        }
      }
    }
    if (latest != null) {
      final ndkPath = '$sdkPath/ndk/$latest';
      if (await Directory(ndkPath).exists()) {
        return ndkPath;
      }
    }
  }

  return null;
}

Future<Map<String, String>> _checkAndroidNdkAndGetEnv(String rustTarget) async {
  final ndkHome = await _findAndroidNdk();

  if (ndkHome == null) {
    _error('Android NDK not found');
    _info('💡 Set one of the following environment variables:');
    _info('   export ANDROID_NDK_HOME=/path/to/ndk');
    _info('   export ANDROID_NDK=/path/to/ndk');
    _info('   export ANDROID_HOME=/path/to/android-sdk  (auto-detects ndk/*)');
    _info('');
    _info('💡 Or install Android NDK via SDK Manager:');
    _info('   sdkmanager --install "ndk;26.2.11394342"');
    throw Exception(
      'Android NDK not found. Set ANDROID_NDK_HOME or ANDROID_HOME.',
    );
  }

  _info('✅ Android NDK: $ndkHome');

  // Map Rust target to NDK toolchain prefix
  final toolchainPrefix = _ndkToolchainPrefix(rustTarget);
  final toolchainDir = await _ndkToolchainDir(ndkHome);
  final toolchainBin = '$toolchainDir/bin';

  // Find actual clang binary (NDK r23+ may include API level in the name,
  // e.g. armv7a-linux-androideabi21-clang instead of just
  // armv7a-linux-androideabi-clang).
  final clangBinary = await _findClangBinary(toolchainBin, toolchainPrefix);
  final clangxxBinary = clangBinary.replaceFirst(
    RegExp(r'-clang$'),
    '-clang++',
  );

  final targetEnv = _targetTripleEnv(rustTarget);
  final ccPath = '$toolchainBin/$clangBinary';
  final cxxPath = '$toolchainBin/$clangxxBinary';
  final arPath = '$toolchainBin/llvm-ar';

  _info('🔧 CC:  $clangBinary');
  _info('🔧 CXX: $clangxxBinary');

  final env = <String, String>{
    // Standard cargo-cc / cc-rs variables (per-target)
    'CC_$targetEnv': ccPath,
    'CXX_$targetEnv': cxxPath,
    'AR_$targetEnv': arPath,
    'CARGO_TARGET_${targetEnv}_LINKER': ccPath,

    // Also set without target suffix (some build scripts use these)
    'TARGET_CC': ccPath,
    'TARGET_CXX': cxxPath,
    'TARGET_AR': arPath,
    'CC': ccPath,
    'CXX': cxxPath,
    'AR': arPath,

    // ANDROID_NDK_HOME for crates that read it directly
    'ANDROID_NDK_HOME': ndkHome,
    'NDK_HOME': ndkHome,
  };

  // Add toolchain bin to PATH so cc-rs can find tools by name
  final existingPath = Platform.environment['PATH'] ?? '';
  env['PATH'] = '$toolchainBin:$existingPath';

  // Create compatibility symlinks for cc-rs / ring build scripts.
  // Some crates look for tool names that differ from what the NDK provides.
  await _createNdkCompatSymlinks(
    toolchainBin,
    rustTarget,
    clangBinary,
    clangxxBinary,
  );

  return env;
}

/// Find the actual clang binary for a given target prefix in the NDK.
///
/// NDK r23+ ships clang binaries with API level suffixes
/// (e.g. `armv7a-linux-androideabi21-clang`). This function scans
/// the toolchain bin directory to find the highest available API level
/// for the given prefix.
Future<String> _findClangBinary(
  String toolchainBin,
  String toolchainPrefix,
) async {
  final binDir = Directory(toolchainBin);
  if (!await binDir.exists()) {
    // Fallback: just return the prefix + -clang
    return '${toolchainPrefix}-clang';
  }

  String? bestMatch;
  int bestApiLevel = -1;

  await for (final entity in binDir.list()) {
    if (entity is! File) continue;
    final name = entity.uri.pathSegments.lastWhere(
      (s) => s.isNotEmpty,
      orElse: () => '',
    );
    if (name.isEmpty) continue;

    // Match patterns like:
    //   armv7a-linux-androideabi-clang
    //   armv7a-linux-androideabi21-clang
    //   armv7a-linux-androideabi33-clang
    final pattern = RegExp('^${RegExp.escape(toolchainPrefix)}(\\d*)-clang\$');
    final match = pattern.firstMatch(name);
    if (match != null) {
      final apiLevelStr = match.group(1) ?? '';
      final apiLevel = apiLevelStr.isEmpty ? 0 : int.tryParse(apiLevelStr) ?? 0;

      if (apiLevel > bestApiLevel) {
        bestApiLevel = apiLevel;
        bestMatch = name;
      }
    }
  }

  if (bestMatch != null) {
    return bestMatch;
  }

  // Fallback: try the exact prefix + -clang
  return '${toolchainPrefix}-clang';
}

/// Create compatibility symlinks in the NDK toolchain bin directory.
///
/// cc-rs and some crates (e.g. ring) look for toolchain binaries using
/// target triple names that differ from what the NDK provides.
/// For example, cc-rs looks for "arm-linux-androideabi-clang" for the
/// armv7-linux-androideabi target, but the NDK ships
/// "armv7a-linux-androideabiNN-clang" (with API level suffix).
Future<void> _createNdkCompatSymlinks(
  String toolchainBin,
  String rustTarget,
  String clangBinary,
  String clangxxBinary,
) async {
  final symlinks = <String, String>{};

  switch (rustTarget) {
    case 'armv7-linux-androideabi':
      // cc-rs looks for arm-linux-androideabi-* but NDK has armv7a-linux-androideabi*-*
      symlinks['arm-linux-androideabi-clang'] = clangBinary;
      symlinks['arm-linux-androideabi-clang++'] = clangxxBinary;
      symlinks['arm-linux-androideabi-ar'] = 'llvm-ar';
      symlinks['arm-linux-androideabi-ranlib'] = 'llvm-ranlib';
      // Also add versionless symlink (e.g. armv7a-linux-androideabi-clang -> armv7a-linux-androideabi33-clang)
      symlinks['armv7a-linux-androideabi-clang'] = clangBinary;
      symlinks['armv7a-linux-androideabi-clang++'] = clangxxBinary;
    case 'aarch64-linux-android':
      symlinks['aarch64-linux-android-ar'] = 'llvm-ar';
      symlinks['aarch64-linux-android-ranlib'] = 'llvm-ranlib';
      symlinks['aarch64-linux-android-clang'] = clangBinary;
      symlinks['aarch64-linux-android-clang++'] = clangxxBinary;
    case 'x86_64-linux-android':
      symlinks['x86_64-linux-android-ar'] = 'llvm-ar';
      symlinks['x86_64-linux-android-ranlib'] = 'llvm-ranlib';
      symlinks['x86_64-linux-android-clang'] = clangBinary;
      symlinks['x86_64-linux-android-clang++'] = clangxxBinary;
    case 'i686-linux-android':
      symlinks['i686-linux-android-ar'] = 'llvm-ar';
      symlinks['i686-linux-android-ranlib'] = 'llvm-ranlib';
      symlinks['i686-linux-android-clang'] = clangBinary;
      symlinks['i686-linux-android-clang++'] = clangxxBinary;
  }

  for (final entry in symlinks.entries) {
    final linkPath = '$toolchainBin/${entry.key}';
    final targetPath = entry.value;
    final linkFile = Link(linkPath);
    if (!await linkFile.exists()) {
      try {
        await linkFile.create(targetPath);
        _info('🔗 Created compat symlink: ${entry.key} -> ${entry.value}');
      } catch (e) {
        _info('⚠️  Could not create symlink $linkPath: $e');
      }
    }
  }
}

String _ndkToolchainPrefix(String rustTarget) {
  switch (rustTarget) {
    case 'aarch64-linux-android':
      return 'aarch64-linux-android';
    case 'armv7-linux-androideabi':
      return 'armv7a-linux-androideabi';
    case 'x86_64-linux-android':
      return 'x86_64-linux-android';
    case 'i686-linux-android':
      return 'i686-linux-android';
    default:
      return rustTarget;
  }
}

// ---------------------------------------------------------------------------
// Apple SDK environment (macOS / iOS)
// ---------------------------------------------------------------------------

/// Set up Apple SDK environment variables for cc-rs compatibility.
///
/// Crates like `ring` use cc-rs to compile C code, which needs to find
/// Apple SDK headers (e.g. TargetConditionals.h). When running on macOS
/// CI, cc-rs may use the system `cc` instead of Xcode's clang, and
/// may not know where the SDK is.
Future<Map<String, String>> _appleSdkEnv(
  OS targetOS,
  Architecture targetArch,
) async {
  final env = <String, String>{};

  // Only apply on macOS hosts (where xcrun is available)
  if (Platform.operatingSystem != 'macos') return env;

  final sdkName = targetOS == OS.iOS ? 'iphoneos' : 'macosx';

  // Get SDK path via xcrun
  try {
    final result = await Process.run('xcrun', [
      '--sdk',
      sdkName,
      '--show-sdk-path',
    ]);
    if (result.exitCode == 0) {
      final sdkPath = (result.stdout as String).trim();
      if (sdkPath.isNotEmpty) {
        env['SDKROOT'] = sdkPath;
        env['CMAKE_OSX_SYSROOT'] = sdkPath;
        _info('🏔️  Apple SDK: $sdkName -> $sdkPath');
      }
    }
  } catch (_) {
    // xcrun not available, skip
  }

  // Also try to get the platform path and developer dir
  try {
    final result = await Process.run('xcrun', ['--show-sdk-platform-path']);
    if (result.exitCode == 0) {
      final platformPath = (result.stdout as String).trim();
      if (platformPath.isNotEmpty) {
        env['PLATFORM_DIR'] = platformPath;
      }
    }
  } catch (_) {
    // ignore
  }

  // Use Xcode's clang if available
  try {
    final result = await Process.run('xcrun', ['--find', 'clang']);
    if (result.exitCode == 0) {
      final clangPath = (result.stdout as String).trim();
      if (clangPath.isNotEmpty) {
        env['CC'] = clangPath;
        env['CXX'] = '${clangPath}++';
        _info('🔧 Apple CC: $clangPath');
      }
    }
  } catch (_) {
    // ignore
  }

  return env;
}

Future<String> _ndkToolchainDir(String ndkHome) async {
  // NDK 23+ toolchain path – auto-detect host prebuilt directory
  final prebuiltDir = Directory('$ndkHome/toolchains/llvm/prebuilt');
  if (!await prebuiltDir.exists()) {
    // Fallback to common patterns
    final host = Platform.operatingSystem;
    String hostTag;
    switch (host) {
      case 'macos':
        hostTag = 'darwin-x86_64';
      case 'windows':
        hostTag = 'windows-x86_64';
      case 'linux':
      default:
        hostTag = 'linux-x86_64';
    }
    return '$ndkHome/toolchains/llvm/prebuilt/$hostTag';
  }

  // Find the first (and typically only) prebuilt host directory
  await for (final entity in prebuiltDir.list()) {
    if (entity is Directory) {
      return entity.path;
    }
  }

  return '$ndkHome/toolchains/llvm/prebuilt/linux-x86_64';
}

String _targetTripleEnv(String rustTarget) {
  // Convert to CARGO_TARGET_*_LINKER format (uppercase + underscores)
  return rustTarget.toUpperCase().replaceAll('-', '_').replaceAll('.', '_');
}

// ---------------------------------------------------------------------------
// Target mapping
// ---------------------------------------------------------------------------

String _mapRustTarget(OS targetOS, Architecture targetArch) {
  switch (targetOS) {
    case OS.android:
      switch (targetArch) {
        case Architecture.arm64:
          return 'aarch64-linux-android';
        case Architecture.arm:
          return 'armv7-linux-androideabi';
        case Architecture.x64:
          return 'x86_64-linux-android';
        case Architecture.ia32:
          return 'i686-linux-android';
      }
    case OS.iOS:
      switch (targetArch) {
        case Architecture.arm64:
          return 'aarch64-apple-ios';
        case Architecture.x64:
          return 'x86_64-apple-ios';
        case Architecture.arm:
        case Architecture.ia32:
          return 'aarch64-apple-ios';
      }
    case OS.macOS:
      switch (targetArch) {
        case Architecture.arm64:
          return 'aarch64-apple-darwin';
        case Architecture.x64:
          return 'x86_64-apple-darwin';
        case Architecture.arm:
        case Architecture.ia32:
          return 'aarch64-apple-darwin';
      }
    case OS.windows:
      switch (targetArch) {
        case Architecture.x64:
          return 'x86_64-pc-windows-msvc';
        case Architecture.arm64:
          return 'aarch64-pc-windows-msvc';
        case Architecture.arm:
        case Architecture.ia32:
          return 'x86_64-pc-windows-msvc';
      }
    case OS.linux:
      switch (targetArch) {
        case Architecture.x64:
          return 'x86_64-unknown-linux-gnu';
        case Architecture.arm64:
          return 'aarch64-unknown-linux-gnu';
        case Architecture.arm:
          return 'armv7-unknown-linux-gnueabihf';
        case Architecture.ia32:
          return 'i686-unknown-linux-gnu';
      }
    case OS.fuchsia:
      throw UnsupportedError('Fuchsia is not supported');
  }
  // Should never reach here, added for exhaustiveness analysis.
  throw UnsupportedError(
    'Unsupported target: ${targetOS.name} / ${targetArch.name}',
  );
}

String _libNameFor(OS targetOS) {
  switch (targetOS) {
    case OS.windows:
      return 'flutter_rs_ffi_barrage.dll';
    case OS.macOS:
    case OS.iOS:
      return 'libflutter_rs_ffi_barrage.dylib';
    case OS.android:
    case OS.linux:
    case OS.fuchsia:
      return 'libflutter_rs_ffi_barrage.so';
  }
  // Should never reach here.
  throw UnsupportedError('Unsupported OS: ${targetOS.name}');
}

// ---------------------------------------------------------------------------
// Incremental build
// ---------------------------------------------------------------------------

Future<String> _computeSourceHash(Directory rsCoreDir) async {
  final sb = StringBuffer();

  // Cargo.toml
  final cargoToml = File.fromUri(rsCoreDir.uri.resolve('Cargo.toml'));
  if (await cargoToml.exists()) {
    sb.write('Cargo.toml:${await cargoToml.lastModified()}');
  }

  // build.rs
  final buildRs = File.fromUri(rsCoreDir.uri.resolve('build.rs'));
  if (await buildRs.exists()) {
    sb.write('build.rs:${await buildRs.lastModified()}');
  }

  // All .rs files under src/
  final srcDir = Directory.fromUri(rsCoreDir.uri.resolve('src/'));
  if (await srcDir.exists()) {
    await for (final entity in srcDir.list(recursive: true)) {
      if (entity is File && entity.path.endsWith('.rs')) {
        final stat = await entity.stat();
        sb.write('${entity.path}:${stat.modified}');
      }
    }
  }

  // Simple hash based on length and hashCode, sufficient for
  // incremental build cache invalidation.
  return '${sb.length}:${sb.toString().hashCode}';
}

// ---------------------------------------------------------------------------
// Logging utilities
// ---------------------------------------------------------------------------

void _section(String title) {
  stderr.writeln('');
  stderr.writeln(
    '╔══════════════════════════════════════════════════════════╗',
  );
  stderr.writeln('║  $title');
  stderr.writeln(
    '╚══════════════════════════════════════════════════════════╝',
  );
}

void _step(String title) {
  stderr.writeln('');
  stderr.writeln('── $title ──');
}

void _info(String message) {
  stderr.writeln('   $message');
}

void _error(String message) {
  stderr.writeln('❌ $message');
}
