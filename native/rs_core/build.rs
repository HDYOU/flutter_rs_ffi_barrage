//! Build script for flutter_rs_ffi_barrage
//!
//! IMPORTANT: This build script does NOT use cbindgen.
//! No C header files are generated. All FFI symbols are manually
//! matched on the Dart side via dart:ffi.
//!
//! The build script only handles:
//! - Version metadata injection
//! - Platform-specific linker flags

use std::env;

fn main() {
    // Inject package version from Cargo.toml as a compile-time env var
    println!("cargo:rustc-env=CARGO_PKG_VERSION={}", env!("CARGO_PKG_VERSION"));

    // Detect target OS for conditional compilation
    // Note: We use custom cfg names (not target_os/target_arch) because those
    // are built-in Rust cfgs that cannot be set manually.
    let target_os = env::var("CARGO_CFG_TARGET_OS").unwrap_or_default();
    let target_arch = env::var("CARGO_CFG_TARGET_ARCH").unwrap_or_default();

    // Android-specific configuration
    if target_os == "android" {
        println!("cargo:rustc-cfg=platform_android");
    }

    // iOS-specific configuration
    if target_os == "ios" {
        println!("cargo:rustc-cfg=platform_ios");
    }

    // Windows-specific configuration
    if target_os == "windows" {
        println!("cargo:rustc-cfg=platform_windows");
        // On Windows, we need to ensure the cdylib exports all symbols
        println!("cargo:rustc-link-arg=/EXPORT:set_emoji_bitmap_callback");
    }

    // macOS-specific configuration
    if target_os == "macos" {
        println!("cargo:rustc-cfg=platform_macos");
    }

    // Linux-specific configuration
    if target_os == "linux" {
        println!("cargo:rustc-cfg=platform_linux");
    }

    // Print build info for debugging
    println!("cargo:warning=Building flutter_rs_ffi_barrage for {} / {}", target_os, target_arch);
    println!("cargo:warning=No C headers generated - using pure Rust extern \"C\" + Dart:ffi direct binding");
}
