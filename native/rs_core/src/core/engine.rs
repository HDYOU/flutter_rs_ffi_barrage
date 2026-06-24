//! 弹幕核心引擎
//!
//! BarrageEngine 是整个弹幕系统的核心，负责：
//! - 管理画布尺寸和播放状态
//! - 接收和分发弹幕到轨道
//! - 时间控制和同步
//! - 管理表情系统和文字特效
//! - 弹幕过滤和调度

use crate::emoji::emoji_manager::EmojiManager;
use crate::text_effect::effects::TextEffects;
use crate::track::track_manager::{BarrageItem, TrackManager, TrackType};
use crossbeam::queue::ArrayQueue;
use std::sync::Arc;

/// 引擎播放状态
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PlayState {
    /// 播放中
    Playing,
    /// 暂停
    Paused,
    /// 停止
    Stopped,
}

/// 弹幕过滤规则
#[derive(Debug, Clone)]
pub struct FilterRule {
    /// 是否启用
    pub enabled: bool,
    /// 屏蔽关键词列表
    pub keywords: Vec<String>,
    /// 屏蔽用户列表
    pub blocked_users: Vec<String>,
    /// 最大同屏弹幕数（0 表示不限制）
    pub max_on_screen: u32,
    /// 屏蔽滚动弹幕
    pub block_scroll: bool,
    /// 屏蔽顶部弹幕
    pub block_top: bool,
    /// 屏蔽底部弹幕
    pub block_bottom: bool,
    /// 屏蔽逆向弹幕
    pub block_reverse: bool,
    /// 弹幕显示不透明度（0.0 ~ 1.0）
    pub opacity: f32,
    /// 弹幕显示区域比例（0.0 ~ 1.0，1.0 表示全屏）
    pub display_area: f32,
}

impl Default for FilterRule {
    fn default() -> Self {
        Self {
            enabled: true,
            keywords: Vec::new(),
            blocked_users: Vec::new(),
            max_on_screen: 0,
            block_scroll: false,
            block_top: false,
            block_bottom: false,
            block_reverse: false,
            opacity: 1.0,
            display_area: 1.0,
        }
    }
}

impl FilterRule {
    /// 检查弹幕是否通过过滤
    pub fn passes(&self, text: &str, track_type: TrackType) -> bool {
        if !self.enabled {
            return true;
        }

        // 检查轨道类型屏蔽
        match track_type {
            TrackType::Scroll if self.block_scroll => return false,
            TrackType::Top if self.block_top => return false,
            TrackType::Bottom if self.block_bottom => return false,
            TrackType::Reverse if self.block_reverse => return false,
            _ => {}
        }

        // 检查关键词过滤
        for keyword in &self.keywords {
            if text.contains(keyword.as_str()) {
                return false;
            }
        }

        true
    }
}

/// 弹幕引擎核心结构体
pub struct BarrageEngine {
    /// 画布宽度
    pub width: u32,
    /// 画布高度
    pub height: u32,
    /// 轨道管理器
    pub track_manager: TrackManager,
    /// 表情管理器
    pub emoji_manager: EmojiManager,
    /// 全局文字特效
    pub text_effects: TextEffects,
    /// 播放状态
    pub play_state: PlayState,
    /// 当前播放时间（毫秒）
    pub current_time_ms: u64,
    /// 上一次更新时间（毫秒）
    pub last_update_time_ms: u64,
    /// 播放速度倍率
    pub speed_multiplier: f32,
    /// 弹幕过滤规则
    pub filter: FilterRule,
    /// 弹幕接收队列（无锁队列，跨线程安全）
    pub incoming_queue: Arc<ArrayQueue<PendingBarrage>>,
    /// 下一个弹幕 ID
    next_id: u64,
}

/// 待处理的弹幕（队列中）
#[derive(Debug, Clone)]
pub struct PendingBarrage {
    pub text: String,
    pub color: u32,
    pub font_size: u32,
    pub timestamp_ms: u64,
    pub track_type: TrackType,
    pub effects: TextEffects,
}

impl BarrageEngine {
    /// 创建新的弹幕引擎
    pub fn new(width: u32, height: u32) -> Self {
        let track_manager = TrackManager::new(width as f32, height as f32);
        let emoji_manager = EmojiManager::new(200);

        Self {
            width,
            height,
            track_manager,
            emoji_manager,
            text_effects: TextEffects::default(),
            play_state: PlayState::Playing,
            current_time_ms: 0,
            last_update_time_ms: 0,
            speed_multiplier: 1.0,
            filter: FilterRule::default(),
            incoming_queue: Arc::new(ArrayQueue::new(1024)),
            next_id: 1,
        }
    }

    /// 调整画布大小
    pub fn resize(&mut self, width: u32, height: u32) {
        self.width = width;
        self.height = height;
        self.track_manager.resize(width as f32, height as f32);
    }

    /// 设置播放速度
    pub fn set_speed(&mut self, speed: f32) {
        self.speed_multiplier = speed.clamp(0.1, 10.0);
        self.track_manager.set_speed(150.0 * self.speed_multiplier);
    }

    /// 暂停播放
    pub fn pause(&mut self) {
        self.play_state = PlayState::Paused;
    }

    /// 恢复播放
    pub fn resume(&mut self) {
        self.play_state = PlayState::Playing;
    }

    /// 跳转到指定时间
    pub fn seek(&mut self, time_ms: u64) {
        self.current_time_ms = time_ms;
        self.last_update_time_ms = time_ms;
        // 跳转时清空所有弹幕
        self.track_manager.clear();
    }

    /// 清空所有弹幕
    pub fn clear(&mut self) {
        self.track_manager.clear();
        // 清空队列
        while self.incoming_queue.pop().is_some() {}
    }

    /// 推送一条弹幕
    pub fn push(
        &mut self,
        text: &str,
        color: u32,
        font_size: u32,
        timestamp_ms: u64,
        track_type: TrackType,
        effects: TextEffects,
    ) -> bool {
        // 过滤检查
        if !self.filter.passes(text, track_type) {
            return false;
        }

        // 检查同屏数量限制
        if self.filter.max_on_screen > 0 {
            let alive = self.track_manager.alive_count() as u32;
            if alive >= self.filter.max_on_screen {
                return false;
            }
        }

        // 推送到轨道管理器
        let result = self.track_manager.push(
            text.to_string(),
            color,
            font_size,
            timestamp_ms,
            track_type,
            effects,
        );

        if result {
            self.next_id += 1;
        }

        result
    }

    /// 异步推送弹幕（通过无锁队列）
    pub fn push_async(
        &self,
        text: String,
        color: u32,
        font_size: u32,
        timestamp_ms: u64,
        track_type: TrackType,
        effects: TextEffects,
    ) -> bool {
        let pending = PendingBarrage {
            text,
            color,
            font_size,
            timestamp_ms,
            track_type,
            effects,
        };
        self.incoming_queue.push(pending).is_ok()
    }

    /// 处理队列中的弹幕
    fn process_incoming(&mut self) {
        while let Some(pending) = self.incoming_queue.pop() {
            // 过滤检查
            if !self.filter.passes(&pending.text, pending.track_type) {
                continue;
            }

            // 检查同屏数量限制
            if self.filter.max_on_screen > 0 {
                let alive = self.track_manager.alive_count() as u32;
                if alive >= self.filter.max_on_screen {
                    continue;
                }
            }

            let _ = self.track_manager.push(
                pending.text,
                pending.color,
                pending.font_size,
                pending.timestamp_ms,
                pending.track_type,
                pending.effects,
            );
        }
    }

    /// 更新引擎状态（每帧调用）
    /// 返回当前渲染的弹幕数量
    pub fn update(&mut self, time_ms: u64) -> u32 {
        if self.play_state != PlayState::Playing {
            self.last_update_time_ms = time_ms;
            return self.track_manager.alive_count() as u32;
        }

        // 计算时间差
        let delta_ms = if self.last_update_time_ms == 0 {
            16 // 默认 60fps
        } else {
            time_ms.saturating_sub(self.last_update_time_ms)
        };

        self.current_time_ms = time_ms;
        self.last_update_time_ms = time_ms;

        // 处理队列中的弹幕
        self.process_incoming();

        // 更新轨道
        let scaled_delta = (delta_ms as f32 * self.speed_multiplier) as u64;
        self.track_manager.update(scaled_delta);

        // 应用全局不透明度
        let global_opacity = self.filter.opacity;
        if global_opacity < 1.0 {
            for item in self.track_manager.get_all_alive_mut() {
                item.opacity *= global_opacity;
            }
        }

        self.track_manager.alive_count() as u32
    }

    /// 获取所有存活的弹幕（用于渲染）
    pub fn get_render_items(&self) -> Vec<&BarrageItem> {
        self.track_manager.get_all_alive()
    }

    /// 设置全局描边效果
    pub fn set_global_stroke(&mut self, enabled: bool, width: f32, color: u32) {
        self.text_effects.stroke.enabled = enabled;
        self.text_effects.stroke.width = width.max(0.0);
        self.text_effects.stroke.color = crate::utils::color::Color::from_u32(color);
    }

    /// 设置全局阴影效果
    pub fn set_global_shadow(
        &mut self,
        enabled: bool,
        offset_x: f32,
        offset_y: f32,
        blur: f32,
        color: u32,
    ) {
        self.text_effects.shadow.enabled = enabled;
        self.text_effects.shadow.offset_x = offset_x;
        self.text_effects.shadow.offset_y = offset_y;
        self.text_effects.shadow.blur = blur.max(0.0);
        self.text_effects.shadow.color = crate::utils::color::Color::from_u32(color);
    }

    /// 设置全局霓虹效果
    pub fn set_global_neon(&mut self, enabled: bool, radius: f32, color: u32, intensity: f32) {
        self.text_effects.neon.enabled = enabled;
        self.text_effects.neon.radius = radius.max(0.0);
        self.text_effects.neon.color = crate::utils::color::Color::from_u32(color);
        self.text_effects.neon.intensity = intensity.clamp(0.0, 3.0);
    }

    /// 设置全局渐变效果
    pub fn set_global_gradient(
        &mut self,
        enabled: bool,
        gradient_type: u32,
        colors: &[u32],
        stops: &[f32],
        angle: f32,
    ) {
        use crate::text_effect::effects::GradientType;
        self.text_effects.gradient.enabled = enabled;
        self.text_effects.gradient.gradient_type = GradientType::from_u32(gradient_type);
        self.text_effects.gradient.angle = angle;
        self.text_effects
            .gradient
            .set_colors_from_u32(colors, stops);
    }

    /// 获取当前存活弹幕数
    pub fn alive_count(&self) -> usize {
        self.track_manager.alive_count()
    }

    /// 设置过滤规则
    pub fn set_filter(&mut self, filter: FilterRule) {
        self.filter = filter;
    }

    /// 添加过滤关键词
    pub fn add_filter_keyword(&mut self, keyword: &str) {
        if !self.filter.keywords.iter().any(|k| k == keyword) {
            self.filter.keywords.push(keyword.to_string());
        }
    }

    /// 移除过滤关键词
    pub fn remove_filter_keyword(&mut self, keyword: &str) {
        self.filter.keywords.retain(|k| k != keyword);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_engine_creation() {
        let engine = BarrageEngine::new(800, 600);
        assert_eq!(engine.width, 800);
        assert_eq!(engine.height, 600);
        assert_eq!(engine.play_state, PlayState::Playing);
        assert_eq!(engine.alive_count(), 0);
    }

    #[test]
    fn test_push_barrage() {
        let mut engine = BarrageEngine::new(800, 600);
        let result = engine.push("测试弹幕", 0xFFFFFFFF, 24, 0, TrackType::Scroll, TextEffects::default());
        assert!(result);
        assert_eq!(engine.alive_count(), 1);
    }

    #[test]
    fn test_pause_resume() {
        let mut engine = BarrageEngine::new(800, 600);
        assert_eq!(engine.play_state, PlayState::Playing);

        engine.pause();
        assert_eq!(engine.play_state, PlayState::Paused);

        engine.resume();
        assert_eq!(engine.play_state, PlayState::Playing);
    }

    #[test]
    fn test_seek() {
        let mut engine = BarrageEngine::new(800, 600);
        engine.push("测试", 0xFFFFFFFF, 24, 0, TrackType::Scroll, TextEffects::default());
        assert_eq!(engine.alive_count(), 1);

        engine.seek(10000);
        assert_eq!(engine.current_time_ms, 10000);
        assert_eq!(engine.alive_count(), 0); // seek 会清空
    }

    #[test]
    fn test_clear() {
        let mut engine = BarrageEngine::new(800, 600);
        engine.push("测试1", 0xFFFFFFFF, 24, 0, TrackType::Scroll, TextEffects::default());
        engine.push("测试2", 0xFFFFFFFF, 24, 0, TrackType::Top, TextEffects::default());

        assert_eq!(engine.alive_count(), 2);

        engine.clear();
        assert_eq!(engine.alive_count(), 0);
    }

    #[test]
    fn test_resize() {
        let mut engine = BarrageEngine::new(800, 600);
        engine.resize(1920, 1080);
        assert_eq!(engine.width, 1920);
        assert_eq!(engine.height, 1080);
    }

    #[test]
    fn test_filter_keyword() {
        let mut engine = BarrageEngine::new(800, 600);
        engine.add_filter_keyword("屏蔽词");

        // 包含屏蔽词的弹幕应该被过滤
        let result = engine.push("这是屏蔽词测试", 0xFFFFFFFF, 24, 0, TrackType::Scroll, TextEffects::default());
        assert!(!result);

        // 不包含屏蔽词的应该通过
        let result = engine.push("正常弹幕", 0xFFFFFFFF, 24, 0, TrackType::Scroll, TextEffects::default());
        assert!(result);
    }

    #[test]
    fn test_filter_track_type() {
        let mut engine = BarrageEngine::new(800, 600);
        engine.filter.block_top = true;

        let result = engine.push("顶部弹幕", 0xFFFFFFFF, 24, 0, TrackType::Top, TextEffects::default());
        assert!(!result);

        let result = engine.push("滚动弹幕", 0xFFFFFFFF, 24, 0, TrackType::Scroll, TextEffects::default());
        assert!(result);
    }

    #[test]
    fn test_async_push() {
        let engine = BarrageEngine::new(800, 600);
        let result =
            engine.push_async("异步弹幕".to_string(), 0xFFFFFFFF, 24, 0, TrackType::Scroll, TextEffects::default());
        assert!(result);
    }

    #[test]
    fn test_set_speed() {
        let mut engine = BarrageEngine::new(800, 600);
        engine.set_speed(2.0);
        assert_eq!(engine.speed_multiplier, 2.0);
    }

    #[test]
    fn test_update() {
        let mut engine = BarrageEngine::new(800, 600);
        engine.push("测试", 0xFFFFFFFF, 24, 0, TrackType::Scroll, TextEffects::default());

        let count = engine.update(1000);
        assert!(count > 0);
    }
}
