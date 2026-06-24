//! 颜色工具
//!
//! 提供颜色空间转换、颜色操作等工具函数。

/// RGBA 颜色结构体（预乘 Alpha）
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Color {
    pub r: u8,
    pub g: u8,
    pub b: u8,
    pub a: u8,
}

impl Color {
    /// 从 u32 创建颜色（RGBA8888，R 在高字节）
    #[inline]
    pub fn from_u32(color: u32) -> Self {
        Self {
            r: ((color >> 24) & 0xFF) as u8,
            g: ((color >> 16) & 0xFF) as u8,
            b: ((color >> 8) & 0xFF) as u8,
            a: (color & 0xFF) as u8,
        }
    }

    /// 转换为 u32
    #[inline]
    pub fn to_u32(self) -> u32 {
        (self.r as u32) << 24 | (self.g as u32) << 16 | (self.b as u32) << 8 | self.a as u32
    }

    /// 创建不透明颜色（Alpha=255）
    #[inline]
    pub fn rgb(r: u8, g: u8, b: u8) -> Self {
        Self { r, g, b, a: 255 }
    }

    /// 创建带 Alpha 的颜色
    #[inline]
    pub fn rgba(r: u8, g: u8, b: u8, a: u8) -> Self {
        Self { r, g, b, a }
    }

    /// 透明黑色
    #[inline]
    pub fn transparent() -> Self {
        Self {
            r: 0,
            g: 0,
            b: 0,
            a: 0,
        }
    }

    /// 预乘 Alpha
    #[inline]
    pub fn premultiply(self) -> Self {
        if self.a == 255 {
            return self;
        }
        let a = self.a as u32;
        Self {
            r: ((self.r as u32 * a + 127) / 255) as u8,
            g: ((self.g as u32 * a + 127) / 255) as u8,
            b: ((self.b as u32 * a + 127) / 255) as u8,
            a: self.a,
        }
    }

    /// 取消预乘 Alpha
    #[inline]
    pub fn unpremultiply(self) -> Self {
        if self.a == 255 || self.a == 0 {
            return self;
        }
        let a = self.a as u32;
        Self {
            r: ((self.r as u32 * 255 + a / 2) / a) as u8,
            g: ((self.g as u32 * 255 + a / 2) / a) as u8,
            b: ((self.b as u32 * 255 + a / 2) / a) as u8,
            a: self.a,
        }
    }

    /// 线性插值颜色
    pub fn lerp(self, other: Color, t: f32) -> Color {
        let t = t.clamp(0.0, 1.0);
        let inv_t = 1.0 - t;
        Color {
            r: ((self.r as f32 * inv_t + other.r as f32 * t).clamp(0.0, 255.0)) as u8,
            g: ((self.g as f32 * inv_t + other.g as f32 * t).clamp(0.0, 255.0)) as u8,
            b: ((self.b as f32 * inv_t + other.b as f32 * t).clamp(0.0, 255.0)) as u8,
            a: ((self.a as f32 * inv_t + other.a as f32 * t).clamp(0.0, 255.0)) as u8,
        }
    }

    /// 调整亮度（factor > 1.0 变亮，< 1.0 变暗）
    pub fn lighten(self, factor: f32) -> Color {
        Color {
            r: ((self.r as f32 * factor).clamp(0.0, 255.0)) as u8,
            g: ((self.g as f32 * factor).clamp(0.0, 255.0)) as u8,
            b: ((self.b as f32 * factor).clamp(0.0, 255.0)) as u8,
            a: self.a,
        }
    }
}

/// HSL 颜色结构体
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct HslColor {
    pub h: f32, // 0.0 ~ 360.0
    pub s: f32, // 0.0 ~ 1.0
    pub l: f32, // 0.0 ~ 1.0
    pub a: f32, // 0.0 ~ 1.0
}

impl HslColor {
    /// 转换为 RGBA
    pub fn to_rgba(self) -> Color {
        let h = self.h % 360.0;
        let s = self.s.clamp(0.0, 1.0);
        let l = self.l.clamp(0.0, 1.0);

        if s == 0.0 {
            let v = (l * 255.0).round() as u8;
            return Color::rgba(v, v, v, (self.a * 255.0).round() as u8);
        }

        let c = (1.0 - (2.0 * l - 1.0).abs()) * s;
        let x = c * (1.0 - ((h / 60.0) % 2.0 - 1.0).abs());
        let m = l - c / 2.0;

        let (r, g, b) = if h < 60.0 {
            (c, x, 0.0)
        } else if h < 120.0 {
            (x, c, 0.0)
        } else if h < 180.0 {
            (0.0, c, x)
        } else if h < 240.0 {
            (0.0, x, c)
        } else if h < 300.0 {
            (x, 0.0, c)
        } else {
            (c, 0.0, x)
        };

        Color::rgba(
            ((r + m) * 255.0).round().min(255.0) as u8,
            ((g + m) * 255.0).round().min(255.0) as u8,
            ((b + m) * 255.0).round().min(255.0) as u8,
            (self.a * 255.0).round().min(255.0) as u8,
        )
    }
}

/// 生成彩虹渐变色
pub fn rainbow_gradient(t: f32) -> Color {
    let hue = (t * 360.0) % 360.0;
    HslColor {
        h: hue,
        s: 1.0,
        l: 0.5,
        a: 1.0,
    }
    .to_rgba()
}

/// 根据位置计算线性渐变颜色
pub fn linear_gradient(colors: &[Color], stops: &[f32], t: f32) -> Color {
    if colors.is_empty() {
        return Color::transparent();
    }
    if colors.len() == 1 {
        return colors[0];
    }

    let t = t.clamp(0.0, 1.0);

    // 找到 t 所在的区间
    let idx = stops.iter().position(|&s| s >= t).unwrap_or(stops.len()) - 1;
    let idx = idx.max(0).min(colors.len() - 2);

    let t0 = stops[idx];
    let t1 = stops[idx + 1];
    let range = t1 - t0;

    if range <= 0.0 {
        return colors[idx];
    }

    let local_t = (t - t0) / range;
    colors[idx].lerp(colors[idx + 1], local_t)
}

/// 根据角度计算线性渐变的采样位置
pub fn gradient_sample_pos(x: f32, y: f32, width: f32, height: f32, angle_deg: f32) -> f32 {
    use std::f32::consts::PI;
    let angle_rad = angle_deg * PI / 180.0;

    // 计算渐变方向向量
    let dx = angle_rad.sin();
    let dy = -angle_rad.cos();

    // 计算中心
    let cx = width / 2.0;
    let cy = height / 2.0;

    // 计算点相对于中心的偏移
    let ox = x - cx;
    let oy = y - cy;

    // 投影到渐变方向
    let proj = ox * dx + oy * dy;

    // 计算对角线长度的一半（用于归一化）
    let diag = (width * width + height * height).sqrt() / 2.0;

    // 归一化到 0~1
    (proj / diag + 0.5).clamp(0.0, 1.0)
}

/// 径向渐变采样
pub fn radial_gradient_sample(x: f32, y: f32, cx: f32, cy: f32, radius: f32) -> f32 {
    let dx = x - cx;
    let dy = y - cy;
    let dist = (dx * dx + dy * dy).sqrt();
    (dist / radius).clamp(0.0, 1.0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_color_from_u32() {
        let c = Color::from_u32(0xFF00FF80);
        assert_eq!(c.r, 0xFF);
        assert_eq!(c.g, 0x00);
        assert_eq!(c.b, 0xFF);
        assert_eq!(c.a, 0x80);
    }

    #[test]
    fn test_color_to_u32() {
        let c = Color::rgba(0x12, 0x34, 0x56, 0x78);
        assert_eq!(c.to_u32(), 0x12345678);
    }

    #[test]
    fn test_hsl_to_rgba() {
        // 红色
        let red = HslColor {
            h: 0.0,
            s: 1.0,
            l: 0.5,
            a: 1.0,
        }
        .to_rgba();
        assert_eq!(red.r, 255);
        assert_eq!(red.g, 0);
        assert_eq!(red.b, 0);

        // 绿色
        let green = HslColor {
            h: 120.0,
            s: 1.0,
            l: 0.5,
            a: 1.0,
        }
        .to_rgba();
        assert_eq!(green.r, 0);
        assert_eq!(green.g, 255);
        assert_eq!(green.b, 0);

        // 蓝色
        let blue = HslColor {
            h: 240.0,
            s: 1.0,
            l: 0.5,
            a: 1.0,
        }
        .to_rgba();
        assert_eq!(blue.r, 0);
        assert_eq!(blue.g, 0);
        assert_eq!(blue.b, 255);
    }

    #[test]
    fn test_rainbow_gradient() {
        let c = rainbow_gradient(0.0);
        assert_eq!(c.r, 255);
        assert!(c.g < 10);
        assert_eq!(c.b, 0);
    }
}
