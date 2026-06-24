//! 数学工具函数
//!
//! 提供常用的数学计算辅助函数，包括区间运算、插值、边界检测等。

/// 线性插值
#[inline]
pub fn lerp(a: f32, b: f32, t: f32) -> f32 {
    a + (b - a) * t
}

/// 将值限制在 [min, max] 范围内
#[inline]
pub fn clamp<T: PartialOrd>(value: T, min: T, max: T) -> T {
    if value < min {
        min
    } else if value > max {
        max
    } else {
        value
    }
}

/// f32 版本的 clamp
#[inline]
pub fn clamp_f32(value: f32, min: f32, max: f32) -> f32 {
    value.max(min).min(max)
}

/// 将 u32 版本的 clamp
#[inline]
pub fn clamp_u32(value: u32, min: u32, max: u32) -> u32 {
    value.max(min).min(max)
}

/// 检查矩形是否相交（AABB 碰撞检测）
#[inline]
pub fn rect_intersects(
    x1: f32,
    y1: f32,
    w1: f32,
    h1: f32,
    x2: f32,
    y2: f32,
    w2: f32,
    h2: f32,
) -> bool {
    x1 < x2 + w2 && x1 + w1 > x2 && y1 < y2 + h2 && y1 + h1 > y2
}

/// 检查点是否在矩形内
#[inline]
pub fn point_in_rect(px: f32, py: f32, rx: f32, ry: f32, rw: f32, rh: f32) -> bool {
    px >= rx && px <= rx + rw && py >= ry && py <= ry + rh
}

/// 快速平方根倒数（牛顿迭代法近似，适用于对精度要求不高的场景）
#[inline]
pub fn fast_inv_sqrt(x: f32) -> f32 {
    if x <= 0.0 {
        return 0.0;
    }
    1.0 / x.sqrt()
}

/// 角度转弧度
#[inline]
pub fn deg_to_rad(deg: f32) -> f32 {
    deg * std::f32::consts::PI / 180.0
}

/// 弧度转角度
#[inline]
pub fn rad_to_deg(rad: f32) -> f32 {
    rad * 180.0 / std::f32::consts::PI
}

/// 平滑步进函数（0~1 之间的平滑过渡）
#[inline]
pub fn smoothstep(edge0: f32, edge1: f32, x: f32) -> f32 {
    let t = clamp_f32((x - edge0) / (edge1 - edge0), 0.0, 1.0);
    t * t * (3.0 - 2.0 * t)
}

/// 计算两点之间的距离
#[inline]
pub fn distance(x1: f32, y1: f32, x2: f32, y2: f32) -> f32 {
    let dx = x2 - x1;
    let dy = y2 - y1;
    (dx * dx + dy * dy).sqrt()
}

/// 计算两点之间的距离平方（不做开方，用于比较）
#[inline]
pub fn distance_sq(x1: f32, y1: f32, x2: f32, y2: f32) -> f32 {
    let dx = x2 - x1;
    let dy = y2 - y1;
    dx * dx + dy * dy
}

/// 将 u32 颜色值解包为 RGBA 分量
#[inline]
pub fn unpack_color_u32_to_rgba(color: u32) -> (u8, u8, u8, u8) {
    (
        ((color >> 24) & 0xFF) as u8,
        ((color >> 16) & 0xFF) as u8,
        ((color >> 8) & 0xFF) as u8,
        (color & 0xFF) as u8,
    )
}

/// 将 RGBA 分量打包为 u32 颜色值（RGBA8888 格式，R 在高字节）
#[inline]
pub fn pack_rgba_to_u32(r: u8, g: u8, b: u8, a: u8) -> u32 {
    ((r as u32) << 24) | ((g as u32) << 16) | ((b as u32) << 8) | (a as u32)
}

/// 预乘 Alpha 的颜色混合（源 over 目标）
#[inline]
pub fn blend_premultiplied(
    src_r: u8,
    src_g: u8,
    src_b: u8,
    src_a: u8,
    dst_r: u8,
    dst_g: u8,
    dst_b: u8,
    dst_a: u8,
) -> (u8, u8, u8, u8) {
    let inv_a = 255 - src_a as u32;
    let out_r = src_r as u32 + (dst_r as u32 * inv_a + 127) / 255;
    let out_g = src_g as u32 + (dst_g as u32 * inv_a + 127) / 255;
    let out_b = src_b as u32 + (dst_b as u32 * inv_a + 127) / 255;
    let out_a = src_a as u32 + (dst_a as u32 * inv_a + 127) / 255;
    (
        out_r.min(255) as u8,
        out_g.min(255) as u8,
        out_b.min(255) as u8,
        out_a.min(255) as u8,
    )
}

/// 非预乘 Alpha 的颜色混合
#[inline]
pub fn blend_unmultiplied(
    src_r: u8,
    src_g: u8,
    src_b: u8,
    src_a: u8,
    dst_r: u8,
    dst_g: u8,
    dst_b: u8,
    dst_a: u8,
) -> (u8, u8, u8, u8) {
    let src_a_f = src_a as f32 / 255.0;
    let inv_a = 1.0 - src_a_f;

    let out_r = (src_r as f32 * src_a_f + dst_r as f32 * inv_a) as u32;
    let out_g = (src_g as f32 * src_a_f + dst_g as f32 * inv_a) as u32;
    let out_b = (src_b as f32 * src_a_f + dst_b as f32 * inv_a) as u32;
    let out_a = (src_a_f + dst_a as f32 / 255.0 * inv_a) * 255.0;

    (
        out_r.min(255) as u8,
        out_g.min(255) as u8,
        out_b.min(255) as u8,
        out_a.min(255.0) as u8,
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_lerp() {
        assert_eq!(lerp(0.0, 10.0, 0.5), 5.0);
        assert_eq!(lerp(5.0, 15.0, 0.0), 5.0);
        assert_eq!(lerp(5.0, 15.0, 1.0), 15.0);
    }

    #[test]
    fn test_clamp() {
        assert_eq!(clamp_f32(5.0, 0.0, 10.0), 5.0);
        assert_eq!(clamp_f32(-1.0, 0.0, 10.0), 0.0);
        assert_eq!(clamp_f32(11.0, 0.0, 10.0), 10.0);
    }

    #[test]
    fn test_rect_intersects() {
        assert!(rect_intersects(0.0, 0.0, 10.0, 10.0, 5.0, 5.0, 10.0, 10.0));
        assert!(!rect_intersects(
            0.0, 0.0, 10.0, 10.0, 15.0, 15.0, 10.0, 10.0
        ));
    }

    #[test]
    fn test_color_pack_unpack() {
        let (r, g, b, a) = unpack_color_u32_to_rgba(0xFF804020);
        assert_eq!(r, 0xFF);
        assert_eq!(g, 0x80);
        assert_eq!(b, 0x40);
        assert_eq!(a, 0x20);
        assert_eq!(pack_rgba_to_u32(r, g, b, a), 0xFF804020);
    }
}
