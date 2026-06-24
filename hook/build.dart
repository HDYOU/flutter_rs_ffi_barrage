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
    }

    // -------------------------------------------------------------------
    // 2. 🔨 编译准备 & 增量检查
    // -------------------------------------------------------------------
    _step('🔨 编译准备');

    final rsCoreDir =
        Directory.fromUri(packageRoot.resolve('native/rs_core/'));
    if (!await rsCoreDir.exists()) {
      throw Exception(
        'Rust source directory not found: ${rsCoreDir.path}',
      );
    }

    final libName = _libNameFor(targetOS);
    final targetDir =
        Directory.fromUri(rsCoreDir.uri.resolve('target/$rustTarget/$buildMode/'));
    final libPath =
        File.fromUri(targetDir.uri.resolve(libName));

    final outDir = input.outputDirectoryShared;
    if (!await Directory.fromUri(outDir).exists()) {
      await Directory.fromUri(outDir).create(recursive: true);
    }

    // 增量编译检查：基于源码文件修改时间
    final sourceHash = await _computeSourceHash(rsCoreDir);
    final hashFile = File.fromUri(
      outDir.resolve('.build_hash_$rustTarget'),
    );
    final lastHash =
        await hashFile.exists() ? await hashFile.readAsString() : '';

    if (lastHash == sourceHash && await libPath.exists()) {
      _info('📦 源码未变更，跳过编译，使用缓存产物');
    } else {
      // -----------------------------------------------------------------
      // 3. 🚀 编译 Rust 核心库
      // -----------------------------------------------------------------
      _step('🚀 编译 Rust 核心库');

      final cargoArgs = [
        'build',
        '--$buildMode',
        '--target',
        rustTarget,
      ];

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
    final assetDirUri =
        outDir.resolve('${targetOS.name}/${targetArch.name}/');
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
    output.dependencies.add(
      packageRoot.resolve('native/rs_core/Cargo.toml'),
    );
    output.dependencies.add(
      packageRoot.resolve('native/rs_core/build.rs'),
    );

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
  _info('   macOS / Linux:  curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh');
  _info('   Windows:        Download from https://rustup.rs/');
  _info('');
  _info('💡 For Android cross-compilation:');
  _info('   - Set ANDROID_NDK_HOME environment variable');
  _info('   - rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android');
  _info('');
}

Future<Map<String, String>> _checkAndroidNdkAndGetEnv(String rustTarget) async {
  final ndkHome = Platform.environment['ANDROID_NDK_HOME'] ??
      Platform.environment['ANDROID_NDK'] ??
      Platform.environment['NDK_HOME'];

  if (ndkHome == null) {
    _error('ANDROID_NDK_HOME environment variable not set');
    _info('💡 Please set the Android NDK path:');
    _info('   export ANDROID_NDK_HOME=/path/to/ndk');
    throw Exception('ANDROID_NDK_HOME not set');
  }

  _info('✅ Android NDK: $ndkHome');

  // Map Rust target to NDK toolchain prefix
  final toolchainPrefix = _ndkToolchainPrefix(rustTarget);
  final toolchainDir = _ndkToolchainDir(ndkHome);

  final targetEnv = _targetTripleEnv(rustTarget);
  final env = <String, String>{
    'CC_$targetEnv': '$toolchainDir/bin/$toolchainPrefix-clang',
    'CXX_$targetEnv': '$toolchainDir/bin/$toolchainPrefix-clang++',
    'AR_$targetEnv': '$toolchainDir/bin/llvm-ar',
    'CARGO_TARGET_${targetEnv}_LINKER':
        '$toolchainDir/bin/$toolchainPrefix-clang',
  };

  return env;
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

String _ndkToolchainDir(String ndkHome) {
  // NDK 23+ toolchain path
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
  stderr.writeln('╔══════════════════════════════════════════════════════════╗');
  stderr.writeln('║  $title');
  stderr.writeln('╚══════════════════════════════════════════════════════════╝');
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
