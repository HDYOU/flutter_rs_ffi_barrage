//! FFI 导出函数
//!
//! 所有对外暴露的 extern "C" 函数定义。
//!
//! # 安全约束
//! - 所有函数使用 unsafe extern "C"
//! - 所有指针参数必须校验非空
//! - 所有长度参数必须做合理范围检查
//! - 字符串从 C 指针读取时用 std::slice::from_raw_parts，长度校验
//! - 引擎句柄用 Box<BarrageEngine> 包装，into_raw/from_raw 管理生命周期
//!
//! # 类型约束
//! 仅使用以下基础类型：
//! - u8, u32, u64
//! - *const u8, *mut u8
//! - *mut u32, *mut u64
//! - bool, f32

#![allow(clippy::missing_safety_doc)]

use crate::core::engine::BarrageEngine;
use crate::ffi::callbacks::{self, EmojiBitmapRawCallback};
use crate::render::renderer::BarrageRenderer;
use crate::text_effect::effects::TextEffects;
use crate::track::track_manager::TrackType;

/// 最大字符串长度限制（1MB）
const MAX_STRING_LEN: u64 = 1024 * 1024;
/// 最大缓冲区大小限制（512MB）
const MAX_BUFFER_LEN: u64 = 512 * 1024 * 1024;
/// 最大画布宽度
const MAX_CANVAS_WIDTH: u32 = 7680; // 8K
/// 最大画布高度
const MAX_CANVAS_HEIGHT: u32 = 4320; // 8K
/// 最小画布尺寸
const MIN_CANVAS_SIZE: u32 = 16;
/// 最大渐变颜色数
const MAX_GRADIENT_COLORS: u32 = 32;
/// 最大像素数据大小（64MB）
const MAX_PIXEL_LEN: u64 = 64 * 1024 * 1024;

/// 引擎内部包装（包含引擎和渲染器）
struct EngineWrapper {
    engine: BarrageEngine,
    renderer: BarrageRenderer,
}

/// 将引擎指针转换为可变引用（不安全，调用者需保证指针有效）
unsafe fn get_engine_wrapper<'a>(engine_ptr: *mut u8) -> Option<&'a mut EngineWrapper> {
    if engine_ptr.is_null() {
        return None;
    }
    let wrapper = engine_ptr as *mut EngineWrapper;
    Some(&mut *wrapper)
}

/// 从指针和长度读取 UTF-8 字符串切片
///
/// # 安全性
/// - 指针必须有效且指向至少 len 字节的连续内存
/// - 不保证字符串是有效的 UTF-8
unsafe fn read_utf8_slice<'a>(ptr: *const u8, len: u64) -> Option<&'a [u8]> {
    if ptr.is_null() {
        return None;
    }
    if len == 0 || len > MAX_STRING_LEN {
        return None;
    }
    Some(std::slice::from_raw_parts(ptr, len as usize))
}

/// 从指针和长度读取字符串
unsafe fn read_string(ptr: *const u8, len: u64) -> Option<String> {
    let bytes = read_utf8_slice(ptr, len)?;
    String::from_utf8(bytes.to_vec()).ok()
}

/// 验证画布尺寸
fn validate_canvas_size(width: u32, height: u32) -> bool {
    width >= MIN_CANVAS_SIZE
        && height >= MIN_CANVAS_SIZE
        && width <= MAX_CANVAS_WIDTH
        && height <= MAX_CANVAS_HEIGHT
}

// ============================================================================
// 引擎生命周期管理
// ============================================================================

/// 创建弹幕引擎
///
/// # 参数
/// - `width`: 画布宽度（像素）
/// - `height`: 画布高度（像素）
///
/// # 返回值
/// - 引擎句柄指针（不透明，使用 *mut u8 表示），失败返回 null
#[no_mangle]
pub unsafe extern "C" fn barrage_engine_create(width: u32, height: u32) -> *mut u8 {
    // 参数校验
    if !validate_canvas_size(width, height) {
        return std::ptr::null_mut();
    }

    // 创建引擎和渲染器
    let engine = BarrageEngine::new(width, height);
    let renderer = BarrageRenderer::new(width, height);

    let wrapper = Box::new(EngineWrapper { engine, renderer });
    Box::into_raw(wrapper) as *mut u8
}

/// 销毁弹幕引擎
///
/// # 参数
/// - `engine_ptr`: 引擎句柄指针
#[no_mangle]
pub unsafe extern "C" fn barrage_engine_destroy(engine_ptr: *mut u8) {
    if engine_ptr.is_null() {
        return;
    }

    // 从原始指针重建 Box，自动 drop
    let wrapper = Box::from_raw(engine_ptr as *mut EngineWrapper);
    drop(wrapper);
}

// ============================================================================
// 引擎控制
// ============================================================================

/// 调整画布大小
///
/// # 参数
/// - `engine_ptr`: 引擎句柄指针
/// - `width`: 新宽度
/// - `height`: 新高度
#[no_mangle]
pub unsafe extern "C" fn barrage_engine_resize(engine_ptr: *mut u8, width: u32, height: u32) {
    let wrapper = match get_engine_wrapper(engine_ptr) {
        Some(w) => w,
        None => return,
    };

    if !validate_canvas_size(width, height) {
        return;
    }

    wrapper.engine.resize(width, height);
    wrapper.renderer.resize(width, height);
}

/// 设置播放速度
///
/// # 参数
/// - `engine_ptr`: 引擎句柄指针
/// - `speed`: 速度倍率（0.1 ~ 10.0）
#[no_mangle]
pub unsafe extern "C" fn barrage_engine_set_speed(engine_ptr: *mut u8, speed: f32) {
    let wrapper = match get_engine_wrapper(engine_ptr) {
        Some(w) => w,
        None => return,
    };

    // 速度范围校验
    if speed.is_nan() || speed.is_infinite() || !(0.1..=10.0).contains(&speed) {
        return;
    }

    wrapper.engine.set_speed(speed);
}

/// 暂停播放
///
/// # 参数
/// - `engine_ptr`: 引擎句柄指针
#[no_mangle]
pub unsafe extern "C" fn barrage_engine_pause(engine_ptr: *mut u8) {
    let wrapper = match get_engine_wrapper(engine_ptr) {
        Some(w) => w,
        None => return,
    };

    wrapper.engine.pause();
}

/// 恢复播放
///
/// # 参数
/// - `engine_ptr`: 引擎句柄指针
#[no_mangle]
pub unsafe extern "C" fn barrage_engine_resume(engine_ptr: *mut u8) {
    let wrapper = match get_engine_wrapper(engine_ptr) {
        Some(w) => w,
        None => return,
    };

    wrapper.engine.resume();
}

/// 跳转到指定时间
///
/// # 参数
/// - `engine_ptr`: 引擎句柄指针
/// - `time_ms`: 目标时间（毫秒）
#[no_mangle]
pub unsafe extern "C" fn barrage_engine_seek(engine_ptr: *mut u8, time_ms: u64) {
    let wrapper = match get_engine_wrapper(engine_ptr) {
        Some(w) => w,
        None => return,
    };

    wrapper.engine.seek(time_ms);
}

/// 清空所有弹幕
///
/// # 参数
/// - `engine_ptr`: 引擎句柄指针
#[no_mangle]
pub unsafe extern "C" fn barrage_engine_clear(engine_ptr: *mut u8) {
    let wrapper = match get_engine_wrapper(engine_ptr) {
        Some(w) => w,
        None => return,
    };

    wrapper.engine.clear();
}

// ============================================================================
// 弹幕推送
// ============================================================================

/// 推送一条弹幕
///
/// # 参数
/// - `engine_ptr`: 引擎句柄指针
/// - `text_ptr`: 弹幕文本指针（UTF-8）
/// - `text_len`: 文本长度（字节数）
/// - `track_type`: 轨道类型（0=滚动, 1=顶部, 2=底部, 3=逆向）
/// - `color`: 文字颜色（RGBA8888）
/// - `font_size`: 字体大小（像素）
/// - `timestamp_ms`: 时间戳（毫秒）
/// - `stroke_enabled`: 是否启用描边
/// - `stroke_width`: 描边宽度（像素）
/// - `stroke_color`: 描边颜色（RGBA8888）
/// - `shadow_enabled`: 是否启用阴影
/// - `shadow_offset_x`: 阴影 X 偏移（像素）
/// - `shadow_offset_y`: 阴影 Y 偏移（像素）
/// - `shadow_blur`: 阴影模糊半径（像素）
/// - `shadow_color`: 阴影颜色（RGBA8888）
/// - `neon_enabled`: 是否启用霓虹发光
/// - `neon_radius`: 霓虹发光半径（像素）
/// - `neon_color`: 霓虹发光颜色（RGBA8888）
/// - `neon_intensity`: 霓虹发光强度（0.0 ~ 3.0）
/// - `gradient_enabled`: 是否启用渐变
/// - `gradient_type`: 渐变类型（0=线性, 1=径向, 2=彩虹）
/// - `gradient_colors_ptr`: 渐变颜色数组指针（RGBA8888）
/// - `gradient_colors_len`: 渐变颜色数量
/// - `gradient_angle`: 渐变角度（度）
///
/// # 返回值
/// - `true`: 推送成功
/// - `false`: 推送失败（参数无效或被过滤）
#[no_mangle]
pub unsafe extern "C" fn barrage_engine_push(
    engine_ptr: *mut u8,
    text_ptr: *const u8,
    text_len: u64,
    track_type: u32,
    color: u32,
    font_size: u32,
    timestamp_ms: u64,
    stroke_enabled: bool,
    stroke_width: f32,
    stroke_color: u32,
    shadow_enabled: bool,
    shadow_offset_x: f32,
    shadow_offset_y: f32,
    shadow_blur: f32,
    shadow_color: u32,
    neon_enabled: bool,
    neon_radius: f32,
    neon_color: u32,
    neon_intensity: f32,
    gradient_enabled: bool,
    gradient_type: u32,
    gradient_colors_ptr: *const u32,
    gradient_colors_len: u32,
    gradient_angle: f32,
) -> bool {
    let wrapper = match get_engine_wrapper(engine_ptr) {
        Some(w) => w,
        None => return false,
    };

    // 指针和长度校验
    let text = match read_string(text_ptr, text_len) {
        Some(t) => t,
        None => return false,
    };

    if text.is_empty() {
        return false;
    }

    // 字体大小校验
    if !(8..=200).contains(&font_size) {
        return false;
    }

    // 轨道类型转换
    let tt = TrackType::from_u32(track_type);

    // 构建文字特效
    let mut effects = TextEffects::default();

    // 描边效果
    if stroke_enabled {
        if stroke_width.is_nan() || stroke_width.is_infinite() || !(0.0..=50.0).contains(&stroke_width) {
            return false;
        }
        effects.stroke.enabled = true;
        effects.stroke.width = stroke_width;
        effects.stroke.color = crate::utils::color::Color::from_u32(stroke_color);
    }

    // 阴影效果
    if shadow_enabled {
        if shadow_offset_x.is_nan() || shadow_offset_x.is_infinite() || shadow_offset_x.abs() > 100.0 {
            return false;
        }
        if shadow_offset_y.is_nan() || shadow_offset_y.is_infinite() || shadow_offset_y.abs() > 100.0 {
            return false;
        }
        if shadow_blur.is_nan() || shadow_blur.is_infinite() || !(0.0..=100.0).contains(&shadow_blur) {
            return false;
        }
        effects.shadow.enabled = true;
        effects.shadow.offset_x = shadow_offset_x;
        effects.shadow.offset_y = shadow_offset_y;
        effects.shadow.blur = shadow_blur;
        effects.shadow.color = crate::utils::color::Color::from_u32(shadow_color);
    }

    // 霓虹效果
    if neon_enabled {
        if neon_radius.is_nan() || neon_radius.is_infinite() || !(0.0..=200.0).contains(&neon_radius) {
            return false;
        }
        if neon_intensity.is_nan() || neon_intensity.is_infinite() || !(0.0..=3.0).contains(&neon_intensity) {
            return false;
        }
        effects.neon.enabled = true;
        effects.neon.radius = neon_radius;
        effects.neon.color = crate::utils::color::Color::from_u32(neon_color);
        effects.neon.intensity = neon_intensity;
    }

    // 渐变效果
    if gradient_enabled {
        if gradient_type > 2 {
            return false;
        }
        if gradient_angle.is_nan() || gradient_angle.is_infinite() {
            return false;
        }

        use crate::text_effect::effects::GradientType;
        effects.gradient.enabled = true;
        effects.gradient.gradient_type = GradientType::from_u32(gradient_type);
        effects.gradient.angle = gradient_angle;

        if gradient_type != 2 {
            // 非彩虹渐变需要颜色数组
            if gradient_colors_ptr.is_null() {
                return false;
            }
            if gradient_colors_len == 0 || gradient_colors_len > MAX_GRADIENT_COLORS {
                return false;
            }

            let colors_slice = std::slice::from_raw_parts(gradient_colors_ptr, gradient_colors_len as usize);
            let colors: Vec<u32> = colors_slice.to_vec();

            // 生成均匀分布的 stops
            let stops: Vec<f32> = if gradient_colors_len > 1 {
                (0..gradient_colors_len)
                    .map(|i| i as f32 / (gradient_colors_len - 1) as f32)
                    .collect()
            } else {
                vec![0.0]
            };

            effects.gradient.set_colors_from_u32(&colors, &stops);
        }
    }

    wrapper
        .engine
        .push(&text, color, font_size, timestamp_ms, tt, effects)
}

// ============================================================================
// 渲染
// ============================================================================

/// 渲染一帧弹幕
///
/// # 参数
/// - `engine_ptr`: 引擎句柄指针
/// - `time_ms`: 当前时间（毫秒）
/// - `out_buffer`: 输出缓冲区指针（RGBA8888，u32 数组）
/// - `buffer_len`: 缓冲区长度（元素个数，不是字节数）
///
/// # 返回值
/// - 渲染的弹幕数量，失败返回 0
#[no_mangle]
pub unsafe extern "C" fn barrage_engine_render_frame(
    engine_ptr: *mut u8,
    time_ms: u64,
    out_buffer: *mut u32,
    buffer_len: u64,
) -> u32 {
    let wrapper = match get_engine_wrapper(engine_ptr) {
        Some(w) => w,
        None => return 0,
    };

    // 缓冲区指针校验
    if out_buffer.is_null() {
        return 0;
    }

    // 缓冲区大小校验
    if buffer_len == 0 || buffer_len > MAX_BUFFER_LEN {
        return 0;
    }

    let expected_len = (wrapper.engine.width * wrapper.engine.height) as u64;
    if buffer_len < expected_len {
        return 0;
    }

    // 更新引擎
    wrapper.engine.update(time_ms);

    // 将指针转为切片
    let buffer_slice = std::slice::from_raw_parts_mut(out_buffer, buffer_len as usize);

    // 渲染
    wrapper
        .renderer
        .render_frame(&wrapper.engine, time_ms, buffer_slice, buffer_len)
}

// ============================================================================
// Emoji 回调
// ============================================================================

/// 设置全局 Emoji 位图回调函数
///
/// 当引擎需要渲染某个表情但缓存中没有时，会调用此回调请求 Flutter 端提供位图。
///
/// # 参数
/// - `cb`: 回调函数指针
#[no_mangle]
pub unsafe extern "C" fn set_emoji_bitmap_callback(cb: EmojiBitmapRawCallback) {
    // 函数指针不需要空指针检查（函数指针本身可以是 null 的话需要检查）
    // 这里我们直接设置，回调调用时会检查是否为 None
    callbacks::set_emoji_bitmap_callback(cb);
}

// ============================================================================
// Emoji 注册
// ============================================================================

/// 从 Flutter 注册表情（直接提供位图数据）
///
/// # 参数
/// - `engine_ptr`: 引擎句柄指针
/// - `emoji_text_ptr`: 表情文本指针（如 "[微笑]"）
/// - `emoji_text_len`: 表情文本长度
/// - `width`: 表情宽度（像素）
/// - `height`: 表情高度（像素）
/// - `pixels_ptr`: 像素数据指针（RGBA8888）
/// - `pixels_len`: 像素数据长度（字节数）
///
/// # 返回值
/// - `true`: 注册成功
/// - `false`: 注册失败
#[no_mangle]
pub unsafe extern "C" fn register_emoji_from_flutter(
    engine_ptr: *mut u8,
    emoji_text_ptr: *const u8,
    emoji_text_len: u64,
    width: u32,
    height: u32,
    pixels_ptr: *const u8,
    pixels_len: u64,
) -> bool {
    let wrapper = match get_engine_wrapper(engine_ptr) {
        Some(w) => w,
        None => return false,
    };

    // 表情文本校验
    let emoji_text = match read_string(emoji_text_ptr, emoji_text_len) {
        Some(t) => t,
        None => return false,
    };

    if emoji_text.is_empty() {
        return false;
    }

    // 尺寸校验
    if width == 0 || height == 0 || width > 4096 || height > 4096 {
        return false;
    }

    // 像素数据校验
    if pixels_ptr.is_null() {
        return false;
    }

    let expected_pixel_len = (width * height * 4) as u64;
    if pixels_len < expected_pixel_len || pixels_len > MAX_PIXEL_LEN {
        return false;
    }

    let pixels = std::slice::from_raw_parts(pixels_ptr, pixels_len as usize);

    wrapper
        .engine
        .emoji_manager
        .register_from_flutter(&emoji_text, width, height, pixels)
}

/// 从本地文件路径注册表情
///
/// # 参数
/// - `engine_ptr`: 引擎句柄指针
/// - `emoji_text_ptr`: 表情文本指针
/// - `emoji_text_len`: 表情文本长度
/// - `path_ptr`: 文件路径指针（UTF-8）
/// - `path_len`: 路径长度
///
/// # 返回值
/// - `true`: 注册成功
/// - `false`: 注册失败
#[no_mangle]
pub unsafe extern "C" fn register_emoji_from_local_path(
    engine_ptr: *mut u8,
    emoji_text_ptr: *const u8,
    emoji_text_len: u64,
    path_ptr: *const u8,
    path_len: u64,
) -> bool {
    let wrapper = match get_engine_wrapper(engine_ptr) {
        Some(w) => w,
        None => return false,
    };

    // 表情文本校验
    let emoji_text = match read_string(emoji_text_ptr, emoji_text_len) {
        Some(t) => t,
        None => return false,
    };

    if emoji_text.is_empty() {
        return false;
    }

    // 文件路径校验
    let path = match read_string(path_ptr, path_len) {
        Some(p) => p,
        None => return false,
    };

    if path.is_empty() || path.len() > 4096 {
        return false;
    }

    wrapper
        .engine
        .emoji_manager
        .register_from_local_path(&emoji_text, &path)
}

/// 从远程 URL 注册表情
///
/// 注意：此函数为同步阻塞调用，建议在 Flutter 端使用异步方式
/// 先下载图片，再通过 register_emoji_from_flutter 注册。
///
/// # 参数
/// - `engine_ptr`: 引擎句柄指针
/// - `emoji_text_ptr`: 表情文本指针
/// - `emoji_text_len`: 表情文本长度
/// - `url_ptr`: URL 指针（UTF-8）
/// - `url_len`: URL 长度
///
/// # 返回值
/// - `true`: 注册成功
/// - `false`: 注册失败
#[no_mangle]
pub unsafe extern "C" fn register_emoji_from_url(
    engine_ptr: *mut u8,
    emoji_text_ptr: *const u8,
    emoji_text_len: u64,
    url_ptr: *const u8,
    url_len: u64,
) -> bool {
    let wrapper = match get_engine_wrapper(engine_ptr) {
        Some(w) => w,
        None => return false,
    };

    // 表情文本校验
    let emoji_text = match read_string(emoji_text_ptr, emoji_text_len) {
        Some(t) => t,
        None => return false,
    };

    if emoji_text.is_empty() {
        return false;
    }

    // URL 校验
    let url = match read_string(url_ptr, url_len) {
        Some(u) => u,
        None => return false,
    };

    if url.is_empty() || url.len() > 4096 {
        return false;
    }

    // 简化实现：直接返回 false，建议 Flutter 端下载后通过 register_emoji_from_flutter 注册
    // 实际项目中可集成 reqwest 进行异步下载
    wrapper
        .engine
        .emoji_manager
        .register_from_url(&emoji_text, &url)
}

// ============================================================================
// 文字特效
// ============================================================================

/// 设置全局描边效果
///
/// # 参数
/// - `engine_ptr`: 引擎句柄指针
/// - `enabled`: 是否启用
/// - `width`: 描边宽度（像素）
/// - `color`: 描边颜色（RGBA8888）
#[no_mangle]
pub unsafe extern "C" fn set_global_stroke(
    engine_ptr: *mut u8,
    enabled: bool,
    width: f32,
    color: u32,
) {
    let wrapper = match get_engine_wrapper(engine_ptr) {
        Some(w) => w,
        None => return,
    };

    // 参数校验
    if width.is_nan() || width.is_infinite() || !(0.0..=50.0).contains(&width) {
        return;
    }

    wrapper.engine.set_global_stroke(enabled, width, color);
}

/// 设置全局阴影效果
///
/// # 参数
/// - `engine_ptr`: 引擎句柄指针
/// - `enabled`: 是否启用
/// - `offset_x`: X 轴偏移（像素）
/// - `offset_y`: Y 轴偏移（像素）
/// - `blur`: 模糊半径（像素）
/// - `color`: 阴影颜色（RGBA8888）
#[no_mangle]
pub unsafe extern "C" fn set_global_shadow(
    engine_ptr: *mut u8,
    enabled: bool,
    offset_x: f32,
    offset_y: f32,
    blur: f32,
    color: u32,
) {
    let wrapper = match get_engine_wrapper(engine_ptr) {
        Some(w) => w,
        None => return,
    };

    // 参数校验
    if offset_x.is_nan() || offset_x.is_infinite() || offset_x.abs() > 100.0 {
        return;
    }
    if offset_y.is_nan() || offset_y.is_infinite() || offset_y.abs() > 100.0 {
        return;
    }
    if blur.is_nan() || blur.is_infinite() || !(0.0..=100.0).contains(&blur) {
        return;
    }

    wrapper
        .engine
        .set_global_shadow(enabled, offset_x, offset_y, blur, color);
}

/// 设置全局霓虹发光效果
///
/// # 参数
/// - `engine_ptr`: 引擎句柄指针
/// - `enabled`: 是否启用
/// - `radius`: 发光半径（像素）
/// - `color`: 发光颜色（RGBA8888）
/// - `intensity`: 发光强度（0.0 ~ 3.0）
#[no_mangle]
pub unsafe extern "C" fn set_global_neon(
    engine_ptr: *mut u8,
    enabled: bool,
    radius: f32,
    color: u32,
    intensity: f32,
) {
    let wrapper = match get_engine_wrapper(engine_ptr) {
        Some(w) => w,
        None => return,
    };

    // 参数校验
    if radius.is_nan() || radius.is_infinite() || !(0.0..=200.0).contains(&radius) {
        return;
    }
    if intensity.is_nan() || intensity.is_infinite() || !(0.0..=3.0).contains(&intensity) {
        return;
    }

    wrapper
        .engine
        .set_global_neon(enabled, radius, color, intensity);
}

/// 设置全局渐变效果
///
/// # 参数
/// - `engine_ptr`: 引擎句柄指针
/// - `enabled`: 是否启用
/// - `gradient_type`: 渐变类型（0=线性, 1=径向, 2=彩虹）
/// - `colors_ptr`: 颜色数组指针（u32 数组，RGBA8888）
/// - `colors_len`: 颜色数量
/// - `angle`: 渐变角度（度，仅线性渐变有效）
#[no_mangle]
pub unsafe extern "C" fn set_global_gradient(
    engine_ptr: *mut u8,
    enabled: bool,
    gradient_type: u32,
    colors_ptr: *const u32,
    colors_len: u32,
    angle: f32,
) {
    let wrapper = match get_engine_wrapper(engine_ptr) {
        Some(w) => w,
        None => return,
    };

    // 参数校验
    if gradient_type > 2 {
        return;
    }

    if angle.is_nan() || angle.is_infinite() {
        return;
    }

    // 颜色数组校验
    if enabled {
        if colors_ptr.is_null() {
            return;
        }
        if colors_len == 0 || colors_len > MAX_GRADIENT_COLORS {
            return;
        }

        let colors_slice = std::slice::from_raw_parts(colors_ptr, colors_len as usize);
        let colors: Vec<u32> = colors_slice.to_vec();

        // 生成均匀分布的 stops
        let stops: Vec<f32> = if colors_len > 1 {
            (0..colors_len)
                .map(|i| i as f32 / (colors_len - 1) as f32)
                .collect()
        } else {
            vec![0.0]
        };

        wrapper
            .engine
            .set_global_gradient(enabled, gradient_type, &colors, &stops, angle);
    } else {
        // 禁用渐变
        wrapper
            .engine
            .set_global_gradient(false, gradient_type, &[], &[], angle);
    }
}

// ============================================================================
// 工具函数（调试用）
// ============================================================================

/// 获取引擎版本号
///
/// # 返回值
/// - 版本号字符串指针（静态内存，不需要释放）
#[no_mangle]
pub unsafe extern "C" fn barrage_engine_version() -> *const u8 {
    static VERSION: &[u8] = concat!(env!("CARGO_PKG_VERSION"), "\0").as_bytes();
    VERSION.as_ptr()
}

/// 获取当前存活弹幕数
///
/// # 参数
/// - `engine_ptr`: 引擎句柄指针
///
/// # 返回值
/// - 存活弹幕数量，失败返回 0
#[no_mangle]
pub unsafe extern "C" fn barrage_engine_alive_count(engine_ptr: *mut u8) -> u32 {
    let wrapper = match get_engine_wrapper(engine_ptr) {
        Some(w) => w,
        None => return 0,
    };

    wrapper.engine.alive_count() as u32
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_engine_create_and_destroy() {
        let engine = unsafe { barrage_engine_create(800, 600) };
        assert!(!engine.is_null());

        unsafe { barrage_engine_destroy(engine) };
    }

    #[test]
    fn test_engine_create_invalid_size() {
        // 太小
        let engine = unsafe { barrage_engine_create(0, 600) };
        assert!(engine.is_null());

        // 太大
        let engine = unsafe { barrage_engine_create(10000, 600) };
        assert!(engine.is_null());
    }

    #[test]
    fn test_engine_null_ptr() {
        // 所有函数应该优雅处理空指针
        unsafe {
            barrage_engine_destroy(std::ptr::null_mut());
            barrage_engine_resize(std::ptr::null_mut(), 800, 600);
            barrage_engine_set_speed(std::ptr::null_mut(), 1.0);
            barrage_engine_pause(std::ptr::null_mut());
            barrage_engine_resume(std::ptr::null_mut());
            barrage_engine_seek(std::ptr::null_mut(), 1000);
            barrage_engine_clear(std::ptr::null_mut());

            let result = barrage_engine_push(
                std::ptr::null_mut(),
                b"test".as_ptr(),
                4,
                0,
                0xFFFFFFFF,
                24,
                0,
                false, 0.0, 0,          // stroke
                false, 0.0, 0.0, 0.0, 0, // shadow
                false, 0.0, 0, 0.0,     // neon
                false, 0, std::ptr::null(), 0, 0.0, // gradient
            );
            assert!(!result);

            let count =
                barrage_engine_render_frame(std::ptr::null_mut(), 0, std::ptr::null_mut(), 0);
            assert_eq!(count, 0);
        }
    }

    #[test]
    fn test_push_barrage() {
        let engine = unsafe { barrage_engine_create(800, 600) };
        assert!(!engine.is_null());

        let text = "测试弹幕";
        let result = unsafe {
            barrage_engine_push(
                engine,
                text.as_ptr(),
                text.len() as u64,
                0, // 滚动
                0xFFFFFFFF,
                24,
                0,
                false, 0.0, 0,          // stroke
                false, 0.0, 0.0, 0.0, 0, // shadow
                false, 0.0, 0, 0.0,     // neon
                false, 0, std::ptr::null(), 0, 0.0, // gradient
            )
        };
        assert!(result);

        // 空文本
        let result = unsafe { barrage_engine_push(engine, b"".as_ptr(), 0, 0, 0xFFFFFFFF, 24, 0,
            false, 0.0, 0,
            false, 0.0, 0.0, 0.0, 0,
            false, 0.0, 0, 0.0,
            false, 0, std::ptr::null(), 0, 0.0,
        ) };
        assert!(!result);

        unsafe { barrage_engine_destroy(engine) };
    }

    #[test]
    fn test_render_frame() {
        let engine = unsafe { barrage_engine_create(200, 200) };
        assert!(!engine.is_null());

        // 添加弹幕
        let text = "Test";
        unsafe {
            barrage_engine_push(
                engine,
                text.as_ptr(),
                text.len() as u64,
                0,
                0xFFFFFFFF,
                24,
                0,
                false, 0.0, 0,
                false, 0.0, 0.0, 0.0, 0,
                false, 0.0, 0, 0.0,
                false, 0, std::ptr::null(), 0, 0.0,
            );
        }

        // 渲染
        let mut buffer = vec![0u32; 200 * 200];
        let count = unsafe {
            barrage_engine_render_frame(engine, 100, buffer.as_mut_ptr(), buffer.len() as u64)
        };
        assert!(count > 0);

        unsafe { barrage_engine_destroy(engine) };
    }

    #[test]
    fn test_render_frame_buffer_too_small() {
        let engine = unsafe { barrage_engine_create(200, 200) };
        assert!(!engine.is_null());

        let mut buffer = vec![0u32; 100]; // 太小
        let count = unsafe {
            barrage_engine_render_frame(engine, 0, buffer.as_mut_ptr(), buffer.len() as u64)
        };
        assert_eq!(count, 0);

        unsafe { barrage_engine_destroy(engine) };
    }

    #[test]
    fn test_pause_resume() {
        let engine = unsafe { barrage_engine_create(800, 600) };
        assert!(!engine.is_null());

        unsafe {
            barrage_engine_pause(engine);
            barrage_engine_resume(engine);
        }

        unsafe { barrage_engine_destroy(engine) };
    }

    #[test]
    fn test_set_effects() {
        let engine = unsafe { barrage_engine_create(800, 600) };
        assert!(!engine.is_null());

        unsafe {
            set_global_stroke(engine, true, 2.0, 0xFF0000FF);
            set_global_shadow(engine, true, 2.0, 2.0, 3.0, 0x00000080);
            set_global_neon(engine, true, 10.0, 0x00FFFFFF, 1.0);

            let colors = [0xFF0000FF, 0x00FF00FF, 0x0000FFFF];
            set_global_gradient(
                engine,
                true,
                0, // 线性
                colors.as_ptr(),
                colors.len() as u32,
                45.0,
            );
        }

        unsafe { barrage_engine_destroy(engine) };
    }

    #[test]
    fn test_version() {
        let version_ptr = unsafe { barrage_engine_version() };
        assert!(!version_ptr.is_null());
    }

    #[test]
    fn test_alive_count() {
        let engine = unsafe { barrage_engine_create(800, 600) };
        assert!(!engine.is_null());

        let count = unsafe { barrage_engine_alive_count(engine) };
        assert_eq!(count, 0);

        // 添加一条弹幕
        let text = "Test";
        unsafe {
            barrage_engine_push(
                engine,
                text.as_ptr(),
                text.len() as u64,
                0,
                0xFFFFFFFF,
                24,
                0,
                false, 0.0, 0,
                false, 0.0, 0.0, 0.0, 0,
                false, 0.0, 0, 0.0,
                false, 0, std::ptr::null(), 0, 0.0,
            );
        }

        let count = unsafe { barrage_engine_alive_count(engine) };
        assert_eq!(count, 1);

        unsafe { barrage_engine_destroy(engine) };
    }

    #[test]
    fn test_register_emoji_from_flutter() {
        let engine = unsafe { barrage_engine_create(800, 600) };
        assert!(!engine.is_null());

        let emoji_text = "[微笑]";
        let pixels = vec![255u8; 16 * 16 * 4]; // 16x16 RGBA

        let result = unsafe {
            register_emoji_from_flutter(
                engine,
                emoji_text.as_ptr(),
                emoji_text.len() as u64,
                16,
                16,
                pixels.as_ptr(),
                pixels.len() as u64,
            )
        };
        assert!(result);

        // 无效尺寸
        let result = unsafe {
            register_emoji_from_flutter(
                engine,
                emoji_text.as_ptr(),
                emoji_text.len() as u64,
                0,
                16,
                pixels.as_ptr(),
                pixels.len() as u64,
            )
        };
        assert!(!result);

        unsafe { barrage_engine_destroy(engine) };
    }

    #[test]
    fn test_set_speed_validation() {
        let engine = unsafe { barrage_engine_create(800, 600) };
        assert!(!engine.is_null());

        unsafe {
            // 合法值
            barrage_engine_set_speed(engine, 1.0);
            barrage_engine_set_speed(engine, 0.5);
            barrage_engine_set_speed(engine, 2.0);

            // 非法值（不应该 panic）
            barrage_engine_set_speed(engine, f32::NAN);
            barrage_engine_set_speed(engine, f32::INFINITY);
            barrage_engine_set_speed(engine, 0.0); // 太小
            barrage_engine_set_speed(engine, 100.0); // 太大
        }

        unsafe { barrage_engine_destroy(engine) };
    }
}
