// Copyright (c) 2024 flutter_rs_ffi_barrage Authors.
//
// Native Assets build hook for flutter_rs_ffi_barrage.
// Compiles the Rust core library (native/rs_core) via cargo and bundles
// the resulting dynamic library as a native code asset.
//
// This is a pure Dart hook implementation — no dependency on
// package:native_assets_cli. It directly implements the native-assets
// build protocol: reads the config YAML, runs cargo build, and writes
// the output YAML with the compiled asset.
//
// IMPORTANT:
// No C headers are generated. No cbindgen is invoked. This project uses
// pure Rust extern "C" exports with manually-written Dart:ffi bindings.
//
// Architecture:
//   Dart Layer (ffi_bind.dart)  <-->  Rust Layer (extern "C" + #[no_mangle])
//         ^  direct symbol lookup, zero C glue / zero .h files  ^

import 'dart:convert';
import 'dart:io';

// ---------------------------------------------------------------------------
// 入口
// ---------------------------------------------------------------------------

/// Build hook entry point – called by the Dart / Flutter SDK.
///
/// Protocol: the tool passes --config=<path> and --output=<path>.
/// We read the config YAML/JSON, run the build, and write the output.
void main(List<String> args) async {
  final configPath = _parseArg(args, 'config');
  final outputPath = _parseArg(args, 'output');

  if (configPath == null || outputPath == null) {
    stderr.writeln(
      'Usage: dart hook/build.dart --config=<path> --output=<path>',
    );
    exit(1);
  }

  final config = _readConfig(configPath);
  final outputDir = Directory(outputPath).parent;
  if (!await outputDir.exists()) {
    await outputDir.create(recursive: true);
  }

  await _build(config, outputPath, outputDir);
}

// ---------------------------------------------------------------------------
// 参数解析
// ---------------------------------------------------------------------------

String? _parseArg(List<String> args, String name) {
  for (final arg in args) {
    if (arg.startsWith('--$name=')) {
      return arg.substring('--$name='.length);
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// 配置读取
// ---------------------------------------------------------------------------

Map<String, dynamic> _readConfig(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('Config file not found: $path');
    exit(1);
  }
  final content = file.readAsStringSync();
  // 尝试 JSON 解析（Flutter 原生资源协议使用 JSON 或 YAML）
  try {
    return jsonDecode(content) as Map<String, dynamic>;
  } catch (_) {
    // 如果不是 JSON，尝试简单的 YAML 解析（只处理键值对）
    return _parseSimpleYaml(content);
  }
}

Map<String, dynamic> _parseSimpleYaml(String content) {
  final result = <String, dynamic>{};
  for (final line in LineSplitter.split(content)) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    final colonIdx = trimmed.indexOf(':');
    if (colonIdx > 0) {
      final key = trimmed.substring(0, colonIdx).trim();
      final value = trimmed.substring(colonIdx + 1).trim();
      // 去掉引号
      if (value.startsWith('"') && value.endsWith('"')) {
        result[key] = value.substring(1, value.length - 1);
      } else if (value.startsWith("'") && value.endsWith("'")) {
        result[key] = value.substring(1, value.length - 1);
      } else {
        result[key] = value;
      }
    }
  }
  return result;
}

// ---------------------------------------------------------------------------
// 构建主逻辑
// ---------------------------------------------------------------------------

Future<void> _build(
  Map<String, dynamic> config,
  String outputPath,
  Directory outputDir,
) async {
  // 从配置中读取参数
  final packageName =
      config['package_name'] ??
      config['packageName'] ??
      'flutter_rs_ffi_barrage';
  final packageRoot =
      config['package_root'] ?? config['packageRoot'] ?? Directory.current.path;
  final targetOS = config['target_os'] ?? config['targetOS'] ?? _currentOS;
  final targetArch =
      config['target_architecture'] ??
      config['targetArchitecture'] ??
      _currentArch;
  final buildMode = config['build_mode'] ?? config['buildMode'] ?? 'release';
  final linkMode =
      config['link_mode_preference'] ??
      config['linkModePreference'] ??
      'dynamic';

  _section('flutter_rs_ffi_barrage – native-assets build hook');
  _info('Package:  $packageName');
  _info('Target:   $targetOS / $targetArch');
  _info('Mode:     $buildMode / $linkMode');
  _info('No C headers generated - pure Rust extern C + Dart:ffi binding');

  // -----------------------------------------------------------------------
  // 1. 🔍 环境检测
  // -----------------------------------------------------------------------
  _step('🔍 环境检测');

  await _checkRustToolchain();

  final rustTarget = _mapRustTarget(targetOS, targetArch);
  _info('Rust target:  $rustTarget');

  final buildEnv = <String, String>{};

  if (targetOS == 'android') {
    final ndkEnv = await _checkAndroidNdkAndGetEnv(rustTarget);
    buildEnv.addAll(ndkEnv);
  }

  // -----------------------------------------------------------------------
  // 2. 🔨 编译准备 & 增量检查
  // -----------------------------------------------------------------------
  _step('🔨 编译准备');

  final rsCoreDir = Directory('$packageRoot/native/rs_core');
  if (!await rsCoreDir.exists()) {
    _error('Rust source directory not found: ${rsCoreDir.path}');
    throw Exception('Rust core directory missing: ${rsCoreDir.path}');
  }

  final libName = _libNameFor(targetOS);
  final targetDir = Directory(
    '${rsCoreDir.path}/target/$rustTarget/$buildMode',
  );
  final libPath = '${targetDir.path}/$libName';

  // 增量编译检查
  final sourceHash = await _computeSourceHash(rsCoreDir);
  final hashFile = File('${outputDir.path}/.build_hash');
  final lastHash = await hashFile.exists() ? await hashFile.readAsString() : '';

  if (lastHash == sourceHash && await File(libPath).exists()) {
    _info('📦 源码未变更，跳过编译，使用缓存产物');
  } else {
    // -------------------------------------------------------------------
    // 3. 🚀 编译 Rust 核心库
    // -------------------------------------------------------------------
    _step('🚀 编译 Rust 核心库');

    final args = ['build', '--$buildMode', '--target', rustTarget];

    _info('cargo ${args.join(' ')}');

    final result = await Process.run(
      'cargo',
      args,
      workingDirectory: rsCoreDir.path,
      environment: {...Platform.environment, ...buildEnv},
    );

    if (result.exitCode != 0) {
      stderr.writeln('❌ Cargo build failed (exit code ${result.exitCode})');
      stderr.writeln('--- stdout ---');
      stderr.writeln(result.stdout);
      stderr.writeln('--- stderr ---');
      stderr.writeln(result.stderr);
      exit(result.exitCode);
    }

    // 输出 cargo 的警告信息
    final stderrOutput = result.stderr.toString();
    if (stderrOutput.isNotEmpty) {
      final lines = LineSplitter.split(
        stderrOutput,
      ).where((l) => l.contains('warning:')).take(10);
      for (final line in lines) {
        _info('⚠️  $line');
      }
    }

    _info('✅ Cargo build completed');
    await hashFile.writeAsString(sourceHash);
  }

  // 验证产物
  final libFile = File(libPath);
  if (!await libFile.exists()) {
    _error('Compiled library not found: $libPath');
    throw Exception('Build produced no output at $libPath');
  }

  final libSize = await libFile.length();
  _info('📦 产物大小: ${(libSize / 1024 / 1024).toStringAsFixed(2)} MB');

  // -----------------------------------------------------------------------
  // 4. 📝 注册原生资源
  // -----------------------------------------------------------------------
  _step('📝 注册原生代码资产');

  // 拷贝产物到输出目录
  final assetDir = Directory('${outputDir.path}/$targetOS/$targetArch');
  if (!await assetDir.exists()) {
    await assetDir.create(recursive: true);
  }

  final assetPath = '${assetDir.path}/$libName';
  await libFile.copy(assetPath);
  _info('📋 产物已拷贝: $assetPath');

  // 构建输出 YAML/JSON
  final output = {
    'format-version': [1, 0, 0],
    'assets': [
      {
        'id': 'package:$packageName/src/ffi_bind.dart',
        'link_mode': {'type': 'dynamic'},
        'target': '$targetOS-$targetArch',
        'path': assetPath,
        'type': {'subtype': 'code'},
      },
    ],
    'dependencies': [
      '${rsCoreDir.path}/Cargo.toml',
      '${rsCoreDir.path}/build.rs',
    ],
  };

  // 写入输出文件
  final outputFile = File(outputPath);
  final jsonEncoder = const JsonEncoder.withIndent('  ');
  await outputFile.writeAsString(jsonEncoder.convert(output));
  _info('✅ 输出清单已写入: $outputPath');

  // -----------------------------------------------------------------------
  // 完成
  // -----------------------------------------------------------------------
  _section('✅ 构建完成');
  _info('平台:        $targetOS / $targetArch');
  _info('Rust target: $rustTarget');
  _info('产物:        $assetPath');
  _info('大小:        ${(libSize / 1024 / 1024).toStringAsFixed(2)} MB');
}

// ---------------------------------------------------------------------------
// 环境检测
// ---------------------------------------------------------------------------

Future<void> _checkRustToolchain() async {
  try {
    final result = await Process.run('cargo', ['--version']);
    if (result.exitCode == 0) {
      _info('✅ Rust / Cargo: ${result.stdout.toString().trim()}');
    } else {
      _error('Cargo not found');
      _installRustHint();
      exit(1);
    }
  } catch (e) {
    _error('Rust toolchain not found: $e');
    _installRustHint();
    exit(1);
  }
}

void _installRustHint() {
  _info('');
  _info('💡 安装 Rust 工具链:');
  _info(
    '   macOS / Linux:  curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh',
  );
  _info('   Windows:        下载安装包 https://rustup.rs/');
  _info('');
  _info('💡 Android 交叉编译额外需要:');
  _info('   - 设置 ANDROID_NDK_HOME 环境变量');
  _info(
    '   - rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android',
  );
  _info('');
}

Future<Map<String, String>> _checkAndroidNdkAndGetEnv(String rustTarget) async {
  final ndkHome =
      Platform.environment['ANDROID_NDK_HOME'] ??
      Platform.environment['ANDROID_NDK'] ??
      Platform.environment['NDK_HOME'];

  if (ndkHome == null) {
    _error('ANDROID_NDK_HOME 环境变量未设置');
    _info('💡 请设置 Android NDK 路径:');
    _info('   export ANDROID_NDK_HOME=/path/to/ndk');
    exit(1);
  }

  _info('✅ Android NDK: $ndkHome');

  // 映射 Rust target 到 NDK 工具链
  final toolchainPrefix = _ndkToolchainPrefix(rustTarget);
  final toolchainDir = _ndkToolchainDir(ndkHome);

  final env = <String, String>{
    'CC_${_targetTripleEnv(rustTarget)}':
        '$toolchainDir/bin/$toolchainPrefix-clang',
    'CXX_${_targetTripleEnv(rustTarget)}':
        '$toolchainDir/bin/$toolchainPrefix-clang++',
    'AR_${_targetTripleEnv(rustTarget)}': '$toolchainDir/bin/llvm-ar',
    'CARGO_TARGET_${_targetTripleEnv(rustTarget)}_LINKER':
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
  // NDK 23+ 工具链路径
  return '$ndkHome/toolchains/llvm/prebuilt/linux-x86_64';
}

String _targetTripleEnv(String rustTarget) {
  // 转换为 CARGO_TARGET_*_LINKER 格式（大写 + 下划线）
  return rustTarget.toUpperCase().replaceAll('-', '_').replaceAll('.', '_');
}

// ---------------------------------------------------------------------------
// Target 映射
// ---------------------------------------------------------------------------

String _mapRustTarget(String targetOS, String targetArch) {
  // 规范化
  final os = targetOS.toString().toLowerCase();
  final arch = targetArch.toString().toLowerCase();

  switch (os) {
    case 'android':
      switch (arch) {
        case 'arm64':
        case 'aarch64':
          return 'aarch64-linux-android';
        case 'arm':
        case 'armv7':
        case 'armeabi-v7a':
          return 'armv7-linux-androideabi';
        case 'x64':
        case 'x86_64':
          return 'x86_64-linux-android';
        case 'x86':
        case 'ia32':
          return 'i686-linux-android';
        default:
          return 'aarch64-linux-android';
      }

    case 'ios':
      switch (arch) {
        case 'arm64':
        case 'aarch64':
          return 'aarch64-apple-ios';
        case 'x64':
        case 'x86_64':
          return 'x86_64-apple-ios';
        default:
          return 'aarch64-apple-ios';
      }

    case 'macos':
      switch (arch) {
        case 'arm64':
        case 'aarch64':
          return 'aarch64-apple-darwin';
        case 'x64':
        case 'x86_64':
          return 'x86_64-apple-darwin';
        default:
          return 'aarch64-apple-darwin';
      }

    case 'windows':
      switch (arch) {
        case 'x64':
        case 'x86_64':
          return 'x86_64-pc-windows-msvc';
        case 'arm64':
        case 'aarch64':
          return 'aarch64-pc-windows-msvc';
        default:
          return 'x86_64-pc-windows-msvc';
      }

    case 'linux':
      switch (arch) {
        case 'x64':
        case 'x86_64':
          return 'x86_64-unknown-linux-gnu';
        case 'arm64':
        case 'aarch64':
          return 'aarch64-unknown-linux-gnu';
        case 'arm':
        case 'armv7':
          return 'armv7-unknown-linux-gnueabihf';
        default:
          return 'x86_64-unknown-linux-gnu';
      }

    default:
      _error('Unsupported target OS: $targetOS');
      exit(1);
  }
}

String _libNameFor(String targetOS) {
  switch (targetOS) {
    case 'windows':
      return 'flutter_rs_ffi_barrage.dll';
    case 'macos':
    case 'ios':
      return 'libflutter_rs_ffi_barrage.dylib';
    default:
      // android, linux, etc.
      return 'libflutter_rs_ffi_barrage.so';
  }
}

String get _currentOS {
  if (Platform.isAndroid) return 'android';
  if (Platform.isIOS) return 'ios';
  if (Platform.isMacOS) return 'macos';
  if (Platform.isWindows) return 'windows';
  if (Platform.isLinux) return 'linux';
  return 'linux';
}

String get _currentArch {
  final arch = Platform.version;
  if (arch.contains('arm64') || arch.contains('aarch64')) return 'arm64';
  if (arch.contains('x64') || arch.contains('x86_64')) return 'x64';
  return 'x64'; // 默认
}

// ---------------------------------------------------------------------------
// 增量编译
// ---------------------------------------------------------------------------

Future<String> _computeSourceHash(Directory rsCoreDir) async {
  final sb = StringBuffer();

  // Cargo.toml
  final cargoToml = File('${rsCoreDir.path}/Cargo.toml');
  if (await cargoToml.exists()) {
    sb.write('Cargo.toml:${await cargoToml.lastModified()}');
  }

  // build.rs
  final buildRs = File('${rsCoreDir.path}/build.rs');
  if (await buildRs.exists()) {
    sb.write('build.rs:${await buildRs.lastModified()}');
  }

  // src/ 目录下所有 .rs 文件
  final srcDir = Directory('${rsCoreDir.path}/src');
  if (await srcDir.exists()) {
    await for (final entity in srcDir.list(recursive: true)) {
      if (entity is File && entity.path.endsWith('.rs')) {
        final stat = await entity.stat();
        sb.write('${entity.path}:${stat.modified}');
      }
    }
  }

  // 简单哈希（用长度+内容特征代替真实哈希，足够用于增量检测）
  return '${sb.length}:${sb.toString().hashCode}';
}

// ---------------------------------------------------------------------------
// 日志工具
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
