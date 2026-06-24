# 说明：
# 本文件为 Windows 平台基础配置骨架。
# 如需完整的 Windows 工程，请在 example/ 目录下执行：
#   flutter create --platforms=windows .
#
# 该命令会自动生成完整的 CMake 工程、runner 代码、
# 资源文件及构建配置等。

cmake_minimum_required(VERSION 3.15)
project(flutter_rs_ffi_barrage_example LANGUAGES CXX)

set(BINARY_NAME "flutter_rs_ffi_barrage_example")

# Apply standard settings for Flutter Windows apps
cmake_policy(SET CMP0063 NEW)

set(CMAKE_INSTALL_RPATH "$ORIGIN/lib")

# Flutter 提供的工具函数
include(flutter)

# 配置 Flutter 应用
flutter_additional_windows_build_settings()

# 添加 runner 源文件
# 注：完整工程由 `flutter create` 生成，此处仅为占位
add_executable(${BINARY_NAME} WIN32
  "runner/main.cpp"
)

# 链接 Flutter 库
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)

# FFI 插件：Rust 编译的动态库会通过 native assets 机制自动打包
