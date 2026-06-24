//! CPU RGBA8888 渲染管线
//!
//! 渲染流程（从底层到顶层）：
//! 1. 霓虹发光（最底层，模糊扩散）
//! 2. 阴影（立体偏移）
//! 3. 描边（文字轮廓）
//! 4. 渐变文字填充
//! 5. Emoji 表情（最顶层）
//!
//! 注意：本渲染器使用软件渲染，文字渲染采用简化的位图字体方式。
//! 实际项目中可集成 ab_glyph/rusttype 进行高质量字体渲染。

use crate::core::engine::BarrageEngine;
use crate::emoji::emoji_manager::{EmojiManager, TextSegment};
use crate::text_effect::effects::TextEffects;
use crate::track::track_manager::BarrageItem;
use crate::utils::color::Color;

/// 帧缓冲包装
pub struct FrameBuffer {
    /// RGBA8888 像素数据
    pub pixels: Vec<u32>,
    /// 宽度
    pub width: u32,
    /// 高度
    pub height: u32,
}

impl FrameBuffer {
    /// 创建新的帧缓冲
    pub fn new(width: u32, height: u32) -> Self {
        Self {
            pixels: vec![0; (width * height) as usize],
            width,
            height,
        }
    }

    /// 从外部缓冲区创建（零拷贝视图不可用，这里复制数据）
    pub fn from_external(pixels: &mut [u32], width: u32, height: u32) -> Self {
        let len = (width * height) as usize;
        let actual_len = pixels.len().min(len);
        let mut buf = vec![0; len];
        buf[..actual_len].copy_from_slice(&pixels[..actual_len]);
        Self {
            pixels: buf,
            width,
            height,
        }
    }

    /// 清空帧缓冲
    pub fn clear(&mut self) {
        for p in self.pixels.iter_mut() {
            *p = 0;
        }
    }

    /// 获取像素引用
    #[inline]
    pub fn get_pixel(&self, x: i32, y: i32) -> u32 {
        if x < 0 || y < 0 || x >= self.width as i32 || y >= self.height as i32 {
            return 0;
        }
        let idx = y as usize * self.width as usize + x as usize;
        self.pixels[idx]
    }

    /// 设置像素（带 Alpha 混合）
    #[inline]
    pub fn set_pixel(&mut self, x: i32, y: i32, color: Color) {
        if x < 0 || y < 0 || x >= self.width as i32 || y >= self.height as i32 {
            return;
        }
        if color.a == 0 {
            return;
        }
        let idx = y as usize * self.width as usize + x as usize;
        let dst = self.pixels[idx];
        let dst_color = Color::from_u32(dst);

        // Alpha 混合（预乘 Alpha 方式）
        let src_premul = color.premultiply();
        let dst_premul = dst_color.premultiply();

        let inv_a = 1.0 - src_premul.a as f32 / 255.0;
        let r = (src_premul.r as f32 + dst_premul.r as f32 * inv_a) as u32;
        let g = (src_premul.g as f32 + dst_premul.g as f32 * inv_a) as u32;
        let b = (src_premul.b as f32 + dst_premul.b as f32 * inv_a) as u32;
        let a = (src_premul.a as f32 + dst_premul.a as f32 * inv_a) as u32;

        self.pixels[idx] = Color::rgba(
            r.min(255) as u8,
            g.min(255) as u8,
            b.min(255) as u8,
            a.min(255) as u8,
        )
        .to_u32();
    }

    /// 直接设置像素（不混合，直接覆盖）
    #[inline]
    pub fn set_pixel_raw(&mut self, x: i32, y: i32, color: u32) {
        if x < 0 || y < 0 || x >= self.width as i32 || y >= self.height as i32 {
            return;
        }
        let idx = y as usize * self.width as usize + x as usize;
        self.pixels[idx] = color;
    }

    /// 绘制填充矩形
    pub fn fill_rect(&mut self, x: i32, y: i32, w: i32, h: i32, color: Color) {
        if color.a == 0 {
            return;
        }
        let x0 = x.max(0);
        let y0 = y.max(0);
        let x1 = (x + w).min(self.width as i32);
        let y1 = (y + h).min(self.height as i32);

        if x0 >= x1 || y0 >= y1 {
            return;
        }

        for py in y0..y1 {
            for px in x0..x1 {
                self.set_pixel(px, py, color);
            }
        }
    }

    /// 绘制位图（RGBA8888）
    pub fn draw_bitmap(&mut self, x: i32, y: i32, w: i32, h: i32, pixels: &[u8]) {
        if pixels.len() < (w * h * 4) as usize {
            return;
        }

        let x0 = x.max(0);
        let y0 = y.max(0);
        let x1 = (x + w).min(self.width as i32);
        let y1 = (y + h).min(self.height as i32);

        if x0 >= x1 || y0 >= y1 {
            return;
        }

        for py in y0..y1 {
            for px in x0..x1 {
                let src_x = px - x;
                let src_y = py - y;
                let src_idx = (src_y as usize * w as usize + src_x as usize) * 4;

                let r = pixels[src_idx];
                let g = pixels[src_idx + 1];
                let b = pixels[src_idx + 2];
                let a = pixels[src_idx + 3];

                if a > 0 {
                    self.set_pixel(px, py, Color::rgba(r, g, b, a));
                }
            }
        }
    }

    /// 绘制缩放后的位图（最近邻采样）
    pub fn draw_bitmap_scaled(
        &mut self,
        dst_x: i32,
        dst_y: i32,
        dst_w: i32,
        dst_h: i32,
        src_w: i32,
        src_h: i32,
        pixels: &[u8],
    ) {
        if pixels.len() < (src_w * src_h * 4) as usize {
            return;
        }
        if dst_w <= 0 || dst_h <= 0 || src_w <= 0 || src_h <= 0 {
            return;
        }

        let x0 = dst_x.max(0);
        let y0 = dst_y.max(0);
        let x1 = (dst_x + dst_w).min(self.width as i32);
        let y1 = (dst_y + dst_h).min(self.height as i32);

        if x0 >= x1 || y0 >= y1 {
            return;
        }

        for py in y0..y1 {
            for px in x0..x1 {
                let local_x = px - dst_x;
                let local_y = py - dst_y;

                let src_x = (local_x * src_w / dst_w).max(0).min(src_w - 1);
                let src_y = (local_y * src_h / dst_h).max(0).min(src_h - 1);

                let src_idx = (src_y as usize * src_w as usize + src_x as usize) * 4;

                let r = pixels[src_idx];
                let g = pixels[src_idx + 1];
                let b = pixels[src_idx + 2];
                let a = pixels[src_idx + 3];

                if a > 0 {
                    self.set_pixel(px, py, Color::rgba(r, g, b, a));
                }
            }
        }
    }

    /// 将内容复制到外部缓冲区
    pub fn copy_to(&self, out_buffer: &mut [u32]) {
        let len = out_buffer.len().min(self.pixels.len());
        out_buffer[..len].copy_from_slice(&self.pixels[..len]);
    }
}

/// 渲染器
pub struct BarrageRenderer {
    /// 内部帧缓冲
    frame_buffer: FrameBuffer,
    /// 宽度
    width: u32,
    /// 高度
    height: u32,
}

impl BarrageRenderer {
    /// 创建新的渲染器
    pub fn new(width: u32, height: u32) -> Self {
        Self {
            frame_buffer: FrameBuffer::new(width, height),
            width,
            height,
        }
    }

    /// 调整大小
    pub fn resize(&mut self, width: u32, height: u32) {
        self.width = width;
        self.height = height;
        self.frame_buffer = FrameBuffer::new(width, height);
    }

    /// 渲染一帧弹幕
    /// 返回渲染的弹幕数量
    pub fn render_frame(
        &mut self,
        engine: &BarrageEngine,
        _time_ms: u64,
        out_buffer: &mut [u32],
        buffer_len: u64,
    ) -> u32 {
        // 清空帧缓冲
        self.frame_buffer.clear();

        // 检查缓冲区大小
        let expected_len = (self.width * self.height) as u64;
        if buffer_len < expected_len {
            return 0;
        }

        // 获取所有需要渲染的弹幕
        let items = engine.get_render_items();
        let count = items.len() as u32;

        // 按层级渲染：先画滚动弹幕，再画固定弹幕
        // 实际按顺序即可，因为已经在正确的位置

        // 从后往前渲染（先出现的在底层）
        for item in items.iter().rev() {
            self.render_barrage(item, &engine.emoji_manager, &engine.text_effects);
        }

        // 复制到输出缓冲区
        self.frame_buffer.copy_to(out_buffer);

        count
    }

    /// 渲染单条弹幕
    fn render_barrage(
        &mut self,
        item: &BarrageItem,
        emoji_manager: &EmojiManager,
        effects: &TextEffects,
    ) {
        if !item.alive || item.opacity <= 0.0 {
            return;
        }

        let x = item.x as i32;
        let y = item.y as i32;
        let base_color = Color::from_u32(item.color);

        // 应用弹幕整体不透明度
        let base_color = if item.opacity < 1.0 {
            Color::rgba(
                base_color.r,
                base_color.g,
                base_color.b,
                ((base_color.a as f32) * item.opacity) as u8,
            )
        } else {
            base_color
        };

        // 解析文本（分离文字和表情）
        let parsed = emoji_manager.parse_text(&item.text, item.font_size);

        // 计算特效扩展区域
        let (expand_left, expand_right, expand_top, expand_bottom) = effects.total_expand();
        let total_width = item.width + expand_left + expand_right;
        let total_height = item.height + expand_top + expand_bottom;

        // 快速视锥剔除
        let screen_x = x - expand_left as i32;
        let screen_y = y - expand_top as i32;
        let tw = total_width as i32;
        let th = total_height as i32;
        if screen_x + tw < 0 || screen_x > self.width as i32 {
            return;
        }
        if screen_y + th < 0 || screen_y > self.height as i32 {
            return;
        }

        // 渲染顺序：霓虹 → 阴影 → 描边 → 文字 → Emoji
        // 由于软件渲染性能考虑，我们采用简化的特效实现

        // 1. 霓虹发光（如果启用）
        if effects.neon.enabled {
            self.render_neon_glow(x, y, item.width, item.height, &effects.neon, item.opacity);
        }

        // 2. 阴影（如果启用）
        if effects.shadow.enabled {
            self.render_shadow(x, y, item.width, item.height, &effects.shadow, item.opacity);
        }

        // 3. 描边 + 文字主体
        // 计算文本布局
        let mut cursor_x = 0.0f32;
        let font_size = item.font_size as f32;
        let line_height = font_size * 1.2;

        // 先计算总宽度用于居中
        let total_text_width = parsed.total_width;

        // 居中偏移（固定弹幕已经在轨道管理器居中了，这里处理相对偏移）
        let start_x = 0.0f32;

        for segment in &parsed.segments {
            match segment {
                TextSegment::Text(text) => {
                    let text_width = text.chars().count() as f32 * font_size * 0.6;

                    // 描边（如果启用）
                    if effects.stroke.enabled {
                        self.render_text_stroke(
                            x + (start_x + cursor_x) as i32,
                            y,
                            text,
                            font_size,
                            &effects.stroke,
                            item.opacity,
                        );
                    }

                    // 文字主体
                    let text_color = if effects.gradient.enabled {
                        // 渐变文字
                        effects.gradient.sample_color(
                            start_x + cursor_x,
                            0.0,
                            total_text_width,
                            line_height,
                            base_color,
                        )
                    } else {
                        base_color
                    };

                    self.render_text_body(
                        x + (start_x + cursor_x) as i32,
                        y,
                        text,
                        font_size,
                        text_color,
                    );

                    cursor_x += text_width;
                }
                TextSegment::Emoji {
                    text,
                    width,
                    height,
                } => {
                    // 渲染 Emoji
                    let emoji_height = font_size * emoji_manager.emoji_scale();
                    let scale = emoji_height / *height as f32;
                    let emoji_width = *width as f32 * scale;

                    if let Some(bitmap) = emoji_manager.get_emoji(text) {
                        let emoji_y = y + (line_height - emoji_height) as i32 / 2;
                        self.frame_buffer.draw_bitmap_scaled(
                            x + (start_x + cursor_x) as i32,
                            emoji_y,
                            emoji_width as i32,
                            emoji_height as i32,
                            bitmap.width as i32,
                            bitmap.height as i32,
                            &bitmap.pixels,
                        );
                    } else {
                        // 表情未加载，画一个占位矩形
                        let emoji_y = y + (line_height - emoji_height) as i32 / 2;
                        self.frame_buffer.fill_rect(
                            x + (start_x + cursor_x) as i32,
                            emoji_y,
                            emoji_width as i32,
                            emoji_height as i32,
                            Color::rgba(128, 128, 128, 100),
                        );
                    }

                    cursor_x += emoji_width;
                }
            }
        }
    }

    /// 渲染霓虹发光效果（简化版：多层半透明矩形模拟发光）
    fn render_neon_glow(
        &mut self,
        x: i32,
        y: i32,
        width: f32,
        height: f32,
        neon: &crate::text_effect::effects::NeonEffect,
        global_opacity: f32,
    ) {
        let radius = neon.radius;
        let base_color = neon.color;

        // 多层发光，从外到内透明度递增
        let layers = 4;
        for i in 0..layers {
            let t = i as f32 / layers as f32;
            let expand = radius * (1.0 - t * 0.5);
            let alpha = (neon.intensity * (1.0 - t) * 0.3 * global_opacity).min(1.0);

            if alpha <= 0.0 {
                continue;
            }

            let glow_color = Color::rgba(
                base_color.r,
                base_color.g,
                base_color.b,
                ((base_color.a as f32) * alpha) as u8,
            );

            let glow_x = x - expand as i32;
            let glow_y = y - expand as i32;
            let glow_w = width as i32 + expand as i32 * 2;
            let glow_h = height as i32 + expand as i32 * 2;

            self.frame_buffer
                .fill_rect(glow_x, glow_y, glow_w, glow_h, glow_color);
        }
    }

    /// 渲染阴影效果
    fn render_shadow(
        &mut self,
        x: i32,
        y: i32,
        width: f32,
        height: f32,
        shadow: &crate::text_effect::effects::ShadowEffect,
        global_opacity: f32,
    ) {
        let shadow_x = x + shadow.offset_x as i32;
        let shadow_y = y + shadow.offset_y as i32;

        let alpha = shadow.color.a as f32 / 255.0 * global_opacity;
        if alpha <= 0.0 {
            return;
        }

        let _shadow_color = Color::rgba(
            shadow.color.r,
            shadow.color.g,
            shadow.color.b,
            (alpha * 255.0) as u8,
        );

        // 简化阴影：用多层矩形模拟模糊
        let blur_layers = if shadow.blur > 0.0 { 3 } else { 1 };
        for i in 0..blur_layers {
            let expand = shadow.blur * (i as f32 / blur_layers as f32);
            let layer_alpha = alpha * (1.0 - i as f32 / blur_layers as f32) / blur_layers as f32;

            if layer_alpha <= 0.0 {
                continue;
            }

            let layer_color = Color::rgba(
                shadow.color.r,
                shadow.color.g,
                shadow.color.b,
                (layer_alpha * 255.0) as u8,
            );

            self.frame_buffer.fill_rect(
                shadow_x - expand as i32,
                shadow_y - expand as i32,
                width as i32 + expand as i32 * 2,
                height as i32 + expand as i32 * 2,
                layer_color,
            );
        }
    }

    /// 渲染文字描边
    fn render_text_stroke(
        &mut self,
        x: i32,
        y: i32,
        text: &str,
        font_size: f32,
        stroke: &crate::text_effect::effects::StrokeEffect,
        global_opacity: f32,
    ) {
        let stroke_width = stroke.width;
        if stroke_width <= 0.0 {
            return;
        }

        let alpha = stroke.color.a as f32 / 255.0 * global_opacity;
        if alpha <= 0.0 {
            return;
        }

        let stroke_color = Color::rgba(
            stroke.color.r,
            stroke.color.g,
            stroke.color.b,
            (alpha * 255.0) as u8,
        );

        // 简化描边：在 8 个方向偏移绘制文字
        let directions = [
            (-1, -1),
            (0, -1),
            (1, -1),
            (-1, 0),
            (1, 0),
            (-1, 1),
            (0, 1),
            (1, 1),
        ];

        let offset = stroke_width.max(1.0) as i32;

        for &(dx, dy) in &directions {
            self.render_text_body(
                x + dx * offset,
                y + dy * offset,
                text,
                font_size,
                stroke_color,
            );
        }
    }

    /// 渲染文字主体（简化版：用矩形代表每个字符）
    /// 实际项目中应替换为 ab_glyph 或 rusttype 的字体光栅化
    fn render_text_body(&mut self, x: i32, y: i32, text: &str, font_size: f32, color: Color) {
        if color.a == 0 {
            return;
        }

        let char_height = font_size as i32;
        let mut cursor = 0;

        for ch in text.chars() {
            // 估算字符宽度
            let is_ascii = ch.is_ascii() && !ch.is_ascii_control();
            let char_width = if is_ascii {
                (font_size * 0.5) as i32
            } else {
                font_size as i32
            };

            if char_width > 0 && char_height > 0 {
                // 绘制字符矩形（简化版）
                // 实际项目中应使用字体光栅化结果
                self.frame_buffer
                    .fill_rect(x + cursor, y, char_width, char_height, color);
            }

            cursor += char_width + 1; // 1px 字间距
        }
    }

    /// 获取帧缓冲引用
    pub fn frame_buffer(&self) -> &FrameBuffer {
        &self.frame_buffer
    }

    /// 获取帧缓冲可变引用
    pub fn frame_buffer_mut(&mut self) -> &mut FrameBuffer {
        &mut self.frame_buffer
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::track::track_manager::TrackType;

    #[test]
    fn test_frame_buffer_creation() {
        let fb = FrameBuffer::new(100, 100);
        assert_eq!(fb.width, 100);
        assert_eq!(fb.height, 100);
        assert_eq!(fb.pixels.len(), 10000);
    }

    #[test]
    fn test_frame_buffer_clear() {
        let mut fb = FrameBuffer::new(10, 10);
        fb.pixels.fill(0xFFFFFFFF);
        fb.clear();
        assert_eq!(fb.pixels[0], 0);
        assert_eq!(fb.pixels[99], 0);
    }

    #[test]
    fn test_set_pixel() {
        let mut fb = FrameBuffer::new(10, 10);
        fb.set_pixel(5, 5, Color::rgba(255, 0, 0, 255));
        let pixel = fb.get_pixel(5, 5);
        let color = Color::from_u32(pixel);
        assert_eq!(color.r, 255);
        assert_eq!(color.g, 0);
        assert_eq!(color.b, 0);
    }

    #[test]
    fn test_set_pixel_out_of_bounds() {
        let mut fb = FrameBuffer::new(10, 10);
        // 越界操作不应 panic
        fb.set_pixel(-1, 5, Color::rgba(255, 0, 0, 255));
        fb.set_pixel(10, 5, Color::rgba(255, 0, 0, 255));
        fb.set_pixel(5, -1, Color::rgba(255, 0, 0, 255));
        fb.set_pixel(5, 10, Color::rgba(255, 0, 0, 255));
    }

    #[test]
    fn test_fill_rect() {
        let mut fb = FrameBuffer::new(100, 100);
        fb.fill_rect(10, 10, 20, 20, Color::rgba(0, 255, 0, 255));

        // 矩形内应该是绿色
        let pixel = fb.get_pixel(20, 20);
        let color = Color::from_u32(pixel);
        assert_eq!(color.g, 255);

        // 矩形外应该是透明
        let pixel = fb.get_pixel(5, 5);
        assert_eq!(pixel, 0);
    }

    #[test]
    fn test_renderer_creation() {
        let renderer = BarrageRenderer::new(800, 600);
        assert_eq!(renderer.width, 800);
        assert_eq!(renderer.height, 600);
    }

    #[test]
    fn test_renderer_resize() {
        let mut renderer = BarrageRenderer::new(800, 600);
        renderer.resize(1920, 1080);
        assert_eq!(renderer.width, 1920);
        assert_eq!(renderer.height, 1080);
    }

    #[test]
    fn test_render_frame_empty() {
        let mut renderer = BarrageRenderer::new(100, 100);
        let engine = BarrageEngine::new(100, 100);
        let mut buffer = vec![0u32; 10000];

        let count = renderer.render_frame(&engine, 0, &mut buffer, 10000);
        assert_eq!(count, 0);
    }

    #[test]
    fn test_render_frame_with_barrage() {
        let mut renderer = BarrageRenderer::new(200, 200);
        let mut engine = BarrageEngine::new(200, 200);

        engine.push("测试", 0xFFFFFFFF, 24, 0, TrackType::Scroll);
        engine.update(0);

        let mut buffer = vec![0u32; 200 * 200];
        let count = renderer.render_frame(&engine, 0, &mut buffer, (200 * 200) as u64);

        assert!(count > 0);
        // 缓冲区中应该有一些非零像素
        let has_pixels = buffer.iter().any(|&p| p != 0);
        assert!(has_pixels);
    }
}
