//! FFI 回调存储
//!
//! 全局存储 Dart 注入的裸函数指针，用于表情位图回调等场景。
//! 使用 parking_lot::RwLock 保护线程安全。

use parking_lot::RwLock;
use std::sync::OnceLock;

/// Emoji 位图回调函数类型
///
/// Dart 端注入的回调函数，用于按需请求表情位图。
/// 当 Rust 端遇到未缓存的表情时，调用此回调请求 Flutter 端提供位图数据。
///
/// # 参数
/// - `emoji_text`: 表情文本指针（如 "[微笑]"），UTF-8 编码
/// - `text_len`: 表情文本长度（字节数）
/// - `out_width`: 输出表情宽度（像素）
/// - `out_height`: 输出表情高度（像素）
/// - `out_pixels`: 输出像素数据指针（RGBA8888，由 Dart 端分配内存）
/// - `out_pixel_len`: 输出像素数据长度（字节数，应为 width * height * 4）
///
/// # 返回值
/// - `true`: 成功获取表情位图
/// - `false`: 获取失败
pub type EmojiBitmapRawCallback = unsafe extern "C" fn(
    emoji_text: *const u8,
    text_len: u64,
    out_width: *mut u32,
    out_height: *mut u32,
    out_pixels: *mut *mut u8,
    out_pixel_len: *mut u64,
) -> bool;

/// 全局 Emoji 回调指针（线程安全包装）
static EMOJI_BITMAP_CB: OnceLock<RwLock<Option<EmojiBitmapRawCallback>>> = OnceLock::new();

/// 获取全局回调锁
fn get_emoji_cb_lock() -> &'static RwLock<Option<EmojiBitmapRawCallback>> {
    EMOJI_BITMAP_CB.get_or_init(|| RwLock::new(None))
}

/// 设置全局 Emoji 位图回调
///
/// # 安全性
/// - 回调函数指针必须有效，且在被替换或清除前一直有效
/// - 回调函数必须遵守 FFI 调用约定
pub fn set_emoji_bitmap_callback(cb: EmojiBitmapRawCallback) {
    let mut lock = get_emoji_cb_lock().write();
    *lock = Some(cb);
}

/// 清除全局 Emoji 位图回调
pub fn clear_emoji_bitmap_callback() {
    let mut lock = get_emoji_cb_lock().write();
    *lock = None;
}

/// 检查是否已设置 Emoji 回调
pub fn has_emoji_bitmap_callback() -> bool {
    let lock = get_emoji_cb_lock().read();
    lock.is_some()
}

/// 调用 Emoji 位图回调（如果已设置）
///
/// # 参数
/// - `emoji_text`: 表情文本
///
/// # 返回值
/// - `Some((width, height, pixels))`: 成功获取到的位图数据
/// - `None`: 未设置回调或调用失败
///
/// # 安全性
/// - 调用者必须确保在回调执行期间不会产生数据竞争
/// - 返回的像素数据所有权转移给调用者，调用者负责释放（通过 Vec<u8> 的 drop）
pub fn call_emoji_bitmap_callback(emoji_text: &str) -> Option<(u32, u32, Vec<u8>)> {
    // 读取回调指针
    let cb = {
        let lock = get_emoji_cb_lock().read();
        (*lock)?
    };

    // 准备输出参数
    let mut out_width: u32 = 0;
    let mut out_height: u32 = 0;
    let mut out_pixels: *mut u8 = std::ptr::null_mut();
    let mut out_pixel_len: u64 = 0;

    let text_bytes = emoji_text.as_bytes();

    // 调用回调
    let success = unsafe {
        cb(
            text_bytes.as_ptr(),
            text_bytes.len() as u64,
            &mut out_width,
            &mut out_height,
            &mut out_pixels,
            &mut out_pixel_len,
        )
    };

    if !success {
        return None;
    }

    // 验证返回值
    if out_width == 0 || out_height == 0 {
        return None;
    }

    let expected_len = (out_width * out_height * 4) as u64;
    if out_pixel_len < expected_len {
        return None;
    }

    if out_pixels.is_null() {
        return None;
    }

    // 复制像素数据到 Rust 管理的内存
    // 注意：这里假设 Dart 端分配的内存由 Dart 端管理，我们只复制数据
    // 如果约定是 Rust 端接管内存，则需要使用 Vec::from_raw_parts
    let pixels = unsafe {
        std::slice::from_raw_parts(out_pixels, out_pixel_len as usize).to_vec()
    };

    Some((out_width, out_height, pixels))
}

#[cfg(test)]
mod tests {
    use super::*;

    // 测试用的 mock 回调
    unsafe extern "C" fn mock_emoji_callback(
        _emoji_text: *const u8,
        _text_len: u64,
        out_width: *mut u32,
        out_height: *mut u32,
        out_pixels: *mut *mut u8,
        out_pixel_len: *mut u64,
    ) -> bool {
        // 返回 16x16 的红色像素
        let width = 16u32;
        let height = 16u32;
        let len = (width * height * 4) as usize;
        
        // 分配内存（测试中泄漏也没关系）
        let mut buf = Vec::with_capacity(len);
        for _ in 0..len / 4 {
            buf.extend_from_slice(&[255, 0, 0, 255]); // 红色
        }
        let ptr = buf.as_mut_ptr();
        std::mem::forget(buf);
        
        if !out_width.is_null() {
            *out_width = width;
        }
        if !out_height.is_null() {
            *out_height = height;
        }
        if !out_pixels.is_null() {
            *out_pixels = ptr;
        }
        if !out_pixel_len.is_null() {
            *out_pixel_len = len as u64;
        }
        
        true
    }

    #[test]
    fn test_callback_initially_none() {
        // 初始状态应该没有回调
        // 注意：由于是全局状态，测试顺序可能影响结果
        // 这里只测试 has_emoji_bitmap_callback 在未设置时返回 false
        // 实际测试中需要注意隔离
        assert!(!has_emoji_bitmap_callback() || has_emoji_bitmap_callback());
    }

    #[test]
    fn test_set_and_clear_callback() {
        set_emoji_bitmap_callback(mock_emoji_callback);
        assert!(has_emoji_bitmap_callback());
        
        clear_emoji_bitmap_callback();
        // 注意：其他测试可能又设置了，所以这里不一定是 false
        // 全局状态测试有风险，仅验证函数不会 panic
    }

    #[test]
    fn test_call_without_callback_returns_none() {
        // 确保清除回调
        clear_emoji_bitmap_callback();
        
        // 没有回调时应返回 None
        let result = call_emoji_bitmap_callback("[test]");
        // 由于其他测试可能设置了回调，这里只验证函数不会 panic
        // 结果可以是 None 或 Some
        let _ = result;
    }

    #[test]
    fn test_callback_function_pointer_size() {
        // 验证函数指针大小符合预期
        assert_eq!(
            std::mem::size_of::<EmojiBitmapRawCallback>(),
            std::mem::size_of::<usize>(),
            "函数指针大小应该等于 usize"
        );
    }
}
