//! 文字特效实现
//!
//! 实现四大文字特效：
//! - StrokeEffect: 文字描边
//! - ShadowEffect: 立体偏移阴影
//! - NeonEffect: 霓虹发光
//! - GradientEffect: 线性/径向/彩虹渐变

use crate::utils::color::{
    gradient_sample_pos, linear_gradient, radial_gradient_sample, rainbow_gradient, Color,
};

/// 渐变类型
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u32)]
pub enum GradientType {
    /// 线性渐变
    Linear = 0,
    /// 径向渐变
    Radial = 1,
    /// 彩虹渐变
    Rainbow = 2,
}

impl GradientType {
    /// 从 u32 转换
    pub fn from_u32(value: u32) -> Self {
        match value {
            0 => GradientType::Linear,
            1 => GradientType::Radial,
            2 => GradientType::Rainbow,
            _ => GradientType::Linear,
        }
    }
}

/// 描边特效
#[derive(Debug, Clone)]
pub struct StrokeEffect {
    pub enabled: bool,
    /// 描边宽度（像素）
    pub width: f32,
    /// 描边颜色
    pub color: Color,
}

impl Default for StrokeEffect {
    fn default() -> Self {
        Self {
            enabled: false,
            width: 2.0,
            color: Color::rgba(0, 0, 0, 200),
        }
    }
}

impl StrokeEffect {
    pub fn new(width: f32, color: Color) -> Self {
        Self {
            enabled: true,
            width,
            color,
        }
    }

    /// 计算描边需要扩展的区域大小
    pub fn expand_size(&self) -> f32 {
        if self.enabled {
            self.width
        } else {
            0.0
        }
    }
}

/// 阴影特效
#[derive(Debug, Clone)]
pub struct ShadowEffect {
    pub enabled: bool,
    /// X 轴偏移
    pub offset_x: f32,
    /// Y 轴偏移
    pub offset_y: f32,
    /// 模糊半径
    pub blur: f32,
    /// 阴影颜色
    pub color: Color,
}

impl Default for ShadowEffect {
    fn default() -> Self {
        Self {
            enabled: false,
            offset_x: 2.0,
            offset_y: 2.0,
            blur: 3.0,
            color: Color::rgba(0, 0, 0, 128),
        }
    }
}

impl ShadowEffect {
    pub fn new(offset_x: f32, offset_y: f32, blur: f32, color: Color) -> Self {
        Self {
            enabled: true,
            offset_x,
            offset_y,
            blur,
            color,
        }
    }

    /// 计算阴影需要扩展的区域大小
    pub fn expand_size(&self) -> (f32, f32, f32, f32) {
        if !self.enabled {
            return (0.0, 0.0, 0.0, 0.0);
        }
        let blur_expand = self.blur * 2.0;
        (
            self.offset_x.max(0.0) + blur_expand,    // right
            self.offset_y.max(0.0) + blur_expand,    // bottom
            (-self.offset_x).max(0.0) + blur_expand, // left
            (-self.offset_y).max(0.0) + blur_expand, // top
        )
    }
}

/// 霓虹发光特效
#[derive(Debug, Clone)]
pub struct NeonEffect {
    pub enabled: bool,
    /// 发光半径
    pub radius: f32,
    /// 发光颜色
    pub color: Color,
    /// 发光强度（0.0 ~ 3.0）
    pub intensity: f32,
}

impl Default for NeonEffect {
    fn default() -> Self {
        Self {
            enabled: false,
            radius: 8.0,
            color: Color::rgba(0, 200, 255, 255),
            intensity: 1.0,
        }
    }
}

impl NeonEffect {
    pub fn new(radius: f32, color: Color, intensity: f32) -> Self {
        Self {
            enabled: true,
            radius,
            color,
            intensity: intensity.clamp(0.0, 3.0),
        }
    }

    /// 计算霓虹效果需要扩展的区域大小
    pub fn expand_size(&self) -> f32 {
        if self.enabled {
            self.radius * 2.0
        } else {
            0.0
        }
    }

    /// 根据距离计算发光强度
    pub fn glow_attenuation(&self, distance: f32) -> f32 {
        if !self.enabled || distance >= self.radius {
            return 0.0;
        }
        let t = 1.0 - distance / self.radius;
        // 高斯衰减近似
        (t * t * self.intensity).min(1.0)
    }
}

/// 渐变特效
#[derive(Debug, Clone)]
pub struct GradientEffect {
    pub enabled: bool,
    /// 渐变类型
    pub gradient_type: GradientType,
    /// 渐变颜色数组
    pub colors: Vec<Color>,
    /// 渐变停止位置（0.0 ~ 1.0）
    pub stops: Vec<f32>,
    /// 渐变角度（度，仅线性渐变有效）
    pub angle: f32,
}

impl Default for GradientEffect {
    fn default() -> Self {
        Self {
            enabled: false,
            gradient_type: GradientType::Linear,
            colors: vec![
                Color::rgb(255, 0, 0),
                Color::rgb(255, 255, 0),
                Color::rgb(0, 0, 255),
            ],
            stops: vec![0.0, 0.5, 1.0],
            angle: 0.0,
        }
    }
}

impl GradientEffect {
    pub fn new_linear(colors: Vec<Color>, stops: Vec<f32>, angle: f32) -> Self {
        Self {
            enabled: true,
            gradient_type: GradientType::Linear,
            colors,
            stops,
            angle,
        }
    }

    pub fn new_radial(colors: Vec<Color>, stops: Vec<f32>) -> Self {
        Self {
            enabled: true,
            gradient_type: GradientType::Radial,
            colors,
            stops,
            angle: 0.0,
        }
    }

    pub fn new_rainbow() -> Self {
        Self {
            enabled: true,
            gradient_type: GradientType::Rainbow,
            colors: Vec::new(),
            stops: Vec::new(),
            angle: 0.0,
        }
    }

    /// 获取指定位置的渐变颜色
    pub fn sample_color(
        &self,
        x: f32,
        y: f32,
        width: f32,
        height: f32,
        base_color: Color,
    ) -> Color {
        if !self.enabled {
            return base_color;
        }

        match self.gradient_type {
            GradientType::Linear => {
                if self.colors.len() < 2 || self.stops.len() < 2 {
                    return base_color;
                }
                let t = gradient_sample_pos(x, y, width, height, self.angle);
                let grad_color = linear_gradient(&self.colors, &self.stops, t);
                // 保留原始 alpha
                Color::rgba(grad_color.r, grad_color.g, grad_color.b, base_color.a)
            }
            GradientType::Radial => {
                if self.colors.len() < 2 || self.stops.len() < 2 {
                    return base_color;
                }
                let cx = width / 2.0;
                let cy = height / 2.0;
                let radius = width.min(height) / 2.0;
                let t = radial_gradient_sample(x, y, cx, cy, radius);
                let grad_color = linear_gradient(&self.colors, &self.stops, t);
                Color::rgba(grad_color.r, grad_color.g, grad_color.b, base_color.a)
            }
            GradientType::Rainbow => {
                let t = if width > 0.0 { x / width } else { 0.0 };
                let grad_color = rainbow_gradient(t);
                Color::rgba(grad_color.r, grad_color.g, grad_color.b, base_color.a)
            }
        }
    }

    /// 设置渐变色（从 u32 颜色数组和 stops 数组）
    pub fn set_colors_from_u32(&mut self, colors: &[u32], stops: &[f32]) {
        self.colors = colors.iter().map(|&c| Color::from_u32(c)).collect();
        self.stops = stops.to_vec();
    }
}

/// 全局文字特效配置集合
#[derive(Debug, Clone, Default)]
pub struct TextEffects {
    pub stroke: StrokeEffect,
    pub shadow: ShadowEffect,
    pub neon: NeonEffect,
    pub gradient: GradientEffect,
}

impl TextEffects {
    /// 计算所有特效需要扩展的总区域
    pub fn total_expand(&self) -> (f32, f32, f32, f32) {
        let mut left = 0.0;
        let mut right = 0.0;
        let mut top = 0.0;
        let mut bottom = 0.0;

        // 描边扩展
        let stroke_expand = self.stroke.expand_size();
        left += stroke_expand;
        right += stroke_expand;
        top += stroke_expand;
        bottom += stroke_expand;

        // 阴影扩展
        let (s_right, s_bottom, s_left, s_top) = self.shadow.expand_size();
        left += s_left;
        right += s_right;
        top += s_top;
        bottom += s_bottom;

        // 霓虹扩展
        let neon_expand = self.neon.expand_size();
        left += neon_expand;
        right += neon_expand;
        top += neon_expand;
        bottom += neon_expand;

        (left, right, top, bottom)
    }

    /// 检查是否有任何特效启用
    pub fn any_enabled(&self) -> bool {
        self.stroke.enabled || self.shadow.enabled || self.neon.enabled || self.gradient.enabled
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_gradient_type_from_u32() {
        assert_eq!(GradientType::from_u32(0), GradientType::Linear);
        assert_eq!(GradientType::from_u32(1), GradientType::Radial);
        assert_eq!(GradientType::from_u32(2), GradientType::Rainbow);
        assert_eq!(GradientType::from_u32(99), GradientType::Linear);
    }

    #[test]
    fn test_stroke_effect_default() {
        let stroke = StrokeEffect::default();
        assert_eq!(stroke.enabled, false);
        assert_eq!(stroke.width, 2.0);
    }

    #[test]
    fn test_neon_attenuation() {
        let neon = NeonEffect::new(10.0, Color::rgb(0, 255, 255), 1.0);
        assert_eq!(neon.glow_attenuation(0.0), 1.0);
        assert!(neon.glow_attenuation(5.0) > 0.0);
        assert_eq!(neon.glow_attenuation(10.0), 0.0);
        assert_eq!(neon.glow_attenuation(15.0), 0.0);
    }

    #[test]
    fn test_text_effects_total_expand() {
        let effects = TextEffects::default();
        let (l, r, t, b) = effects.total_expand();
        assert_eq!(l, 0.0);
        assert_eq!(r, 0.0);
        assert_eq!(t, 0.0);
        assert_eq!(b, 0.0);
    }
}
