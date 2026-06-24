// Copyright (c) 2024 flutter_rs_ffi_barrage Authors.
//
// Native Assets build hook for flutter_rs_ffi_barrage.
// Compiles the Rust core library (native/rs_core) via cargo and bundles
// the resulting dynamic library as a code asset.
//
// IMPORTANT:
// No C headers are generated. No cbindgen is invoked. This project uses
// pure Rust extern "C" exports with manually-written Dart:ffi bindings.
//
// Architecture:
//   Dart Layer (ffi_bind.dart)  <-->  Rust Layer (extern "C" + #[no_mangle])
//         ^  direct symbol lookup, zero C glue / zero .h files  ^

import 'dart:io';
import 'package:native_assets_cli/native_assets_cli.dart';

// ---------------------------------------------------------------------------
// 入口
// ---------------------------------------------------------------------------

/// Build hook entry point – called by the Dart / Flutter SDK.
void main(List<String> args) async {
  await build(args, _build);
}

// ---------------------------------------------------------------------------
// 构建主逻辑
// ---------------------------------------------------------------------------

/// Compiles the Rust core library and registers it as a code asset.
Future<void> _build(BuildInput input, BuildOutputBuilder output) async {
  final config = input.config;

  // 跳过非代码资产构建
  if (!config.buildCodeAssets) {
    _info('Skipping – no code assets requested.');
    return;
  }

  final codeConfig = config.code;
  final targetOS = codeConfig.targetOS;
  final targetArch = codeConfig.targetArchitecture;
  final packageName = input.packageName;
  final packageRoot = input.packageRoot;
  final outputDir = Directory.fromUri(input.outputDirectory);

  _section('flutter_rs_ffi_barrage – native-assets build hook');
  _info('Package:  $packageName');
  _info('Target:   ${targetOS.name} / ${targetArch.name}');

  // -----------------------------------------------------------------------
  // 1. 🔍 环境检测
  // -----------------------------------------------------------------------
  _step('🔍 环境检测');

  await _checkRustToolchain();

  final rustTarget = _mapRustTarget(targetOS, targetArch, codeConfig);
  _info('Rust target:  $rustTarget');

  final buildEnv = <String, String>{};

  if (targetOS == OS.android) {
    final ndkEnv = await _checkAndroidNdkAndGetEnv(rustTarget);
    buildEnv.addAll(ndkEnv);
  } else if (targetOS == OS.iOS || targetOS == OS.macOS) {
    await _checkAppleTools(targetOS);
  }

  // -----------------------------------------------------------------------
  // 2. 🔨 编译准备 & 增量检查
  // -----------------------------------------------------------------------
  _step('🔨 编译准备');

  final rsCoreDir = Directory.fromUri(packageRoot.resolve('native/rs_core/'));
  if (!await rsCoreDir.exists()) {
    _error('Rust source directory not found: ${rsCoreDir.path}');
    throw Exception('Rust core directory missing: ${rsCoreDir.path}');
  }

  final libFileName = _libraryFileName(targetOS, packageName);
  final outputLib = File.fromUri(outputDir.uri.resolve(libFileName));

  // 增量编译：若输出已存在且 Cargo.toml / src 均无变更，跳过 cargo 调用
  final skipBuild = await _canSkipBuild(
    rsCoreDir: rsCoreDir,
    outputLib: outputLib,
    rustTarget: rustTarget,
  );

  if (skipBuild) {
    _info('Cache hit – source unchanged, skipping cargo build.');
    _registerAsset(output, packageName, outputLib.uri);
    _addDependencies(output, rsCoreDir);
    _success('Build skipped (cached).');
    return;
  }

  // -----------------------------------------------------------------------
  // 3. 🔨 执行 cargo build
  // -----------------------------------------------------------------------
  _step('🔨 编译 Rust 核心库');
  _info('Command:  cargo build --release --target $rustTarget');
  _info('CWD:      ${rsCoreDir.path}');

  final buildArgs = const ['build', '--release', '--target'];

  final result = await Process.run(
    'cargo',
    [...buildArgs, rustTarget],
    workingDirectory: rsCoreDir.path,
    environment: buildEnv.isEmpty ? null : buildEnv,
  );

  if (result.exitCode != 0) {
    _error('Cargo build failed (exit code ${result.exitCode}).');
    stderr.writeln('--- cargo stdout ---');
    stderr.writeln(result.stdout.toString());
    stderr.writeln('--- cargo stderr ---');
    stderr.writeln(result.stderr.toString());
    throw Exception(
      'Rust compilation failed for target $rustTarget.\n'
      '${result.stderr}',
    );
  }

  // 输出编译日志尾部（便于 CI 排查）
  final stdout = result.stdout.toString();
  if (stdout.isNotEmpty) {
    final lines = stdout.trim().split('\n');
    final tail = lines.length > 8 ? lines.sublist(lines.length - 8) : lines;
    for (final line in tail) {
      _info('  $line');
    }
  }

  // -----------------------------------------------------------------------
  // 4. 📦 定位并拷贝产物
  // -----------------------------------------------------------------------
  _step('📦 处理编译产物');

  final builtLib = _findBuiltLibrary(
    rsCoreDir: rsCoreDir,
    rustTarget: rustTarget,
    targetOS: targetOS,
    packageName: packageName,
  );

  if (!await builtLib.exists()) {
    _error('Compiled library not found at: ${builtLib.path}');
    throw Exception('Expected library not found: ${builtLib.path}');
  }

  await outputDir.create(recursive: true);
  await builtLib.copy(outputLib.path);
  _info('Copied: ${builtLib.path}');
  _info('     → ${outputLib.path}');

  // -----------------------------------------------------------------------
  // 5. 📝 注册代码资产
  // -----------------------------------------------------------------------
  _step('📝 注册代码资产');

  _registerAsset(output, packageName, outputLib.uri);
  _addDependencies(output, rsCoreDir);

  _success('flutter_rs_ffi_barrage build complete!');
  _info('No C headers generated - pure Rust extern C + Dart:ffi binding');
}

// ---------------------------------------------------------------------------
// 代码资产注册
// ---------------------------------------------------------------------------

void _registerAsset(
  BuildOutputBuilder output,
  String packageName,
  Uri fileUri,
) {
  final asset = CodeAsset(
    package: packageName,
    name: 'src/ffi_bind.dart',
    linkMode: DynamicLoadingBundled(),
    file: fileUri,
  );
  output.assets.code.add(asset);
  _info('Asset: package:$packageName/src/ffi_bind.dart');
  _info('  linkMode: DynamicLoadingBundled');
}

/// 声明依赖文件，让 native-assets 框架在源码变更时自动重跑 hook
void _addDependencies(BuildOutputBuilder output, Directory rsCoreDir) {
  // Cargo.toml 作为主要依赖
  output.dependencies.add(rsCoreDir.uri.resolve('Cargo.toml'));
  output.dependencies.add(rsCoreDir.uri.resolve('build.rs'));
  // hook 自身也是依赖
  output.dependencies.add(rsCoreDir.uri.resolve('../../hook/build.dart'));
}

// ---------------------------------------------------------------------------
// Rust 目标三元组映射
// ---------------------------------------------------------------------------

/// Maps Dart [OS] + [Architecture] to the corresponding Rust target triple.
String _mapRustTarget(OS os, Architecture arch, CodeConfig codeConfig) {
  switch (os) {
    case OS.android:
      switch (arch) {
        case Architecture.arm64:
          return 'aarch64-linux-android';
        case Architecture.arm:
          return 'armv7-linux-androideabi';
        case Architecture.x64:
          return 'x86_64-linux-android';
        case Architecture.riscv64:
          return 'riscv64-linux-android';
        default:
          throw ArgumentError('Unsupported Android architecture: ${arch.name}');
      }

    case OS.iOS:
      final iOSConfig = codeConfig.iOS;
      final sdk = iOSConfig?.targetSdk;
      final isSimulator = sdk == IOSSdk.simulator;
      switch (arch) {
        case Architecture.arm64:
          return isSimulator ? 'aarch64-apple-ios-sim' : 'aarch64-apple-ios';
        case Architecture.x64:
          return 'x86_64-apple-ios';
        default:
          throw ArgumentError('Unsupported iOS architecture: ${arch.name}');
      }

    case OS.macOS:
      switch (arch) {
        case Architecture.arm64:
          return 'aarch64-apple-darwin';
        case Architecture.x64:
          return 'x86_64-apple-darwin';
        default:
          throw ArgumentError('Unsupported macOS architecture: ${arch.name}');
      }

    case OS.windows:
      switch (arch) {
        case Architecture.x64:
          return 'x86_64-pc-windows-msvc';
        case Architecture.arm64:
          return 'aarch64-pc-windows-msvc';
        default:
          throw ArgumentError('Unsupported Windows architecture: ${arch.name}');
      }

    case OS.linux:
      switch (arch) {
        case Architecture.x64:
          return 'x86_64-unknown-linux-gnu';
        case Architecture.arm64:
          return 'aarch64-unknown-linux-gnu';
        default:
          throw ArgumentError('Unsupported Linux architecture: ${arch.name}');
      }

    case OS.fuchsia:
    default:
      throw ArgumentError('Unsupported target OS: ${os.name}');
  }
}

// ---------------------------------------------------------------------------
// 库文件名
// ---------------------------------------------------------------------------

/// Returns the platform-specific dynamic library file name.
String _libraryFileName(OS os, String packageName) {
  switch (os) {
    case OS.windows:
      return '$packageName.dll';
    case OS.macOS:
    case OS.iOS:
      return 'lib$packageName.dylib';
    case OS.android:
    case OS.linux:
    case OS.fuchsia:
      return 'lib$packageName.so';
    default:
      return 'lib$packageName.so';
  }
}

// ---------------------------------------------------------------------------
// 查找编译产物
// ---------------------------------------------------------------------------

/// Locates the compiled library inside the cargo target directory.
File _findBuiltLibrary({
  required Directory rsCoreDir,
  required String rustTarget,
  required OS targetOS,
  required String packageName,
}) {
  final libName = _libraryFileName(targetOS, packageName);
  return File.fromUri(
    rsCoreDir.uri.resolve('target/$rustTarget/release/$libName'),
  );
}

// ---------------------------------------------------------------------------
// 增量编译检测
// ---------------------------------------------------------------------------

/// 检查是否可以跳过编译（输出已存在且源码无变更）。
///
/// 通过比较 Cargo.toml / build.rs / src/ 目录的最新修改时间
/// 与输出文件的修改时间来判断。
Future<bool> _canSkipBuild({
  required Directory rsCoreDir,
  required File outputLib,
  required String rustTarget,
}) async {
  // 输出文件不存在则必须编译
  if (!await outputLib.exists()) return false;

  try {
    final outputStat = await outputLib.stat();
    final outputModified = outputStat.modified;

    // 检查 Cargo.toml
    final cargoToml = File.fromUri(rsCoreDir.uri.resolve('Cargo.toml'));
    if (await cargoToml.exists()) {
      final stat = await cargoToml.stat();
      if (stat.modified.isAfter(outputModified)) return false;
    }

    // 检查 build.rs
    final buildRs = File.fromUri(rsCoreDir.uri.resolve('build.rs'));
    if (await buildRs.exists()) {
      final stat = await buildRs.stat();
      if (stat.modified.isAfter(outputModified)) return false;
    }

    // 检查 src/ 目录（递归查找最新修改时间）
    final srcDir = Directory.fromUri(rsCoreDir.uri.resolve('src/'));
    if (await srcDir.exists()) {
      final latestSrcModified = await _findLatestModified(srcDir);
      if (latestSrcModified != null &&
          latestSrcModified.isAfter(outputModified)) {
        return false;
      }
    }

    return true;
  } catch (_) {
    // 任何检查失败都走完整编译流程
    return false;
  }
}

/// 递归查找目录中最新修改的文件时间。
Future<DateTime?> _findLatestModified(Directory dir) async {
  DateTime? latest;
  try {
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        try {
          final stat = await entity.stat();
          if (latest == null || stat.modified.isAfter(latest)) {
            latest = stat.modified;
          }
        } catch (_) {}
      }
    }
  } catch (_) {}
  return latest;
}

// ---------------------------------------------------------------------------
// 环境检测
// ---------------------------------------------------------------------------

/// Verifies that Rust / cargo is installed and available on PATH.
Future<void> _checkRustToolchain() async {
  try {
    final result = await Process.run('cargo', ['--version']);
    if (result.exitCode == 0) {
      _info('Rust toolchain: ${result.stdout.toString().trim()}');
    } else {
      throw Exception('cargo returned exit code ${result.exitCode}');
    }
  } catch (e) {
    _error('Rust / cargo not found on PATH.');
    _error('');
    _error('📦 安装指引:');
    _error('  macOS / Linux:');
    _error(
      '    curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh',
    );
    _error('  Windows:');
    _error('    Download from https://rustup.rs/');
    _error('');
    _error('After installation, restart your terminal or run:');
    _error('  source \$HOME/.cargo/env');
    rethrow;
  }
}

/// Checks Android NDK and returns the NDK environment variables for cargo.
Future<Map<String, String>> _checkAndroidNdkAndGetEnv(String rustTarget) async {
  final ndkHome =
      Platform.environment['ANDROID_NDK_HOME'] ??
      Platform.environment['ANDROID_NDK_PATH'] ??
      Platform.environment['NDK_HOME'];

  if (ndkHome == null || ndkHome.isEmpty) {
    _error('Android NDK not found.');
    _error('');
    _error('📦 安装指引:');
    _error('  1. Install Android NDK via Android SDK Manager');
    _error('  2. Set ANDROID_NDK_HOME environment variable, e.g.:');
    _error(
      '     export ANDROID_NDK_HOME=\$HOME/Library/Android/sdk/ndk/<version>',
    );
    _error('');
    _error('Or set ANDROID_NDK_PATH to the NDK root directory.');
    throw Exception(
      'Android NDK not configured. '
      'Set ANDROID_NDK_HOME or ANDROID_NDK_PATH.',
    );
  }

  _info('Android NDK:  $ndkHome');

  // 确保 Rust 目标已安装
  await _ensureRustTarget(rustTarget);

  // 构建 NDK 环境变量
  final env = <String, String>{};
  final toolchain = '$ndkHome/toolchains/llvm/prebuilt/${_hostTag()}/bin';
  final clangPrefix = _androidClangPrefix(rustTarget);

  if (clangPrefix != null) {
    final targetUpper = rustTarget.toUpperCase().replaceAll('-', '_');
    env['CC_$rustTarget'] = '$toolchain/${clangPrefix}clang';
    env['CXX_$rustTarget'] = '$toolchain/${clangPrefix}clang++';
    env['AR_$rustTarget'] = '$toolchain/llvm-ar';
    env['CARGO_TARGET_${targetUpper}_LINKER'] =
        '$toolchain/${clangPrefix}clang';
    _info('NDK toolchain: $toolchain');
  }

  return env;
}

/// Ensures required build tools are available for Apple platforms.
Future<void> _checkAppleTools(OS os) async {
  try {
    final result = await Process.run('xcode-select', ['-p']);
    if (result.exitCode == 0) {
      _info('Xcode CLI:    ${result.stdout.toString().trim()}');
    } else {
      throw Exception('xcode-select failed');
    }
  } catch (e) {
    _error('Xcode command line tools not found.');
    _error('');
    _error('📦 安装指引:');
    _error('  xcode-select --install');
    _error('');
    throw Exception('Xcode command line tools not installed.');
  }

  // 确保 Rust 目标已安装
  if (os == OS.iOS) {
    await _ensureRustTarget('aarch64-apple-ios');
    await _ensureRustTarget('aarch64-apple-ios-sim');
    await _ensureRustTarget('x86_64-apple-ios');
  } else if (os == OS.macOS) {
    await _ensureRustTarget('aarch64-apple-darwin');
    await _ensureRustTarget('x86_64-apple-darwin');
  }
}

/// Ensures a Rust target is installed via rustup.
Future<void> _ensureRustTarget(String target) async {
  try {
    final result = await Process.run('rustup', ['target', 'add', target]);
    if (result.exitCode == 0) {
      final out = result.stdout.toString().trim();
      if (out.isNotEmpty && !out.contains('already')) {
        _info('Rust target:  $target (added)');
      } else {
        _info('Rust target:  $target (ready)');
      }
    } else {
      _info('Rust target:  $target (rustup warning, continuing)');
    }
  } catch (e) {
    _info('Rust target:  $target (rustup not found, assuming installed)');
  }
}

// ---------------------------------------------------------------------------
// 辅助函数
// ---------------------------------------------------------------------------

/// Returns the NDK host toolchain tag for the current host OS.
String _hostTag() {
  if (Platform.isMacOS) {
    // NDK provides both darwin-x86_64 and darwin-aarch64 since r23
    // We detect the host architecture to pick the right one
    // For simplicity, fall back to x86_64 (works via Rosetta on Apple Silicon)
    return 'darwin-x86_64';
  } else if (Platform.isLinux) {
    return 'linux-x86_64';
  } else if (Platform.isWindows) {
    return 'windows-x86_64';
  }
  return 'linux-x86_64';
}

/// Maps a Rust Android target to the corresponding NDK clang prefix.
String? _androidClangPrefix(String rustTarget) {
  switch (rustTarget) {
    case 'aarch64-linux-android':
      return 'aarch64-linux-android21-';
    case 'armv7-linux-androideabi':
      return 'armv7a-linux-androideabi21-';
    case 'x86_64-linux-android':
      return 'x86_64-linux-android21-';
    case 'riscv64-linux-android':
      return 'riscv64-linux-android35-';
    default:
      return null;
  }
}

// ---------------------------------------------------------------------------
// 日志工具
// ---------------------------------------------------------------------------

void _section(String title) {
  final line = '=' * 60;
  stderr.writeln();
  stderr.writeln(line);
  stderr.writeln('  $title');
  stderr.writeln(line);
}

void _step(String msg) {
  stderr.writeln();
  stderr.writeln(msg);
  stderr.writeln('  ${'-' * 50}');
}

void _info(String msg) {
  stderr.writeln('  ℹ️  $msg');
}

void _success(String msg) {
  stderr.writeln();
  stderr.writeln('✅  $msg');
}

void _error(String msg) {
  stderr.writeln('❌  $msg');
}
