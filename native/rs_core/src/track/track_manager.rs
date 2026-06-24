//! 轨道管理器
//!
//! 实现四种轨道类型的智能管理：
//! - 滚动轨道（Scroll）：从右向左滚动
//! - 顶部固定轨道（Top）：固定在顶部，持续一段时间后消失
//! - 底部固定轨道（Bottom）：固定在底部，持续一段时间后消失
//! - 逆向轨道（Reverse）：从左向右滚动
//!
//! 智能碰撞避让算法：
//! - 新弹幕选择轨道时，优先选择空闲轨道
//! - 考虑弹幕速度和长度，确保不会追上前方弹幕
//! - 顶部/底部固定轨道按时间轮转

use crate::text_effect::effects::TextEffects;
use crate::utils::math::clamp_f32;

/// 弹幕轨道类型
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
#[repr(u32)]
pub enum TrackType {
    /// 滚动轨道（从右到左）
    Scroll = 0,
    /// 顶部固定轨道
    Top = 1,
    /// 底部固定轨道
    Bottom = 2,
    /// 逆向滚动轨道（从左到右）
    Reverse = 3,
}

impl TrackType {
    /// 从 u32 转换
    pub fn from_u32(value: u32) -> Self {
        match value {
            0 => TrackType::Scroll,
            1 => TrackType::Top,
            2 => TrackType::Bottom,
            3 => TrackType::Reverse,
            _ => TrackType::Scroll,
        }
    }

    /// 是否为滚动类型
    pub fn is_scrolling(&self) -> bool {
        matches!(self, TrackType::Scroll | TrackType::Reverse)
    }

    /// 是否为固定类型
    pub fn is_fixed(&self) -> bool {
        matches!(self, TrackType::Top | TrackType::Bottom)
    }
}

/// 单条弹幕数据
#[derive(Debug, Clone)]
pub struct BarrageItem {
    /// 弹幕唯一 ID
    pub id: u64,
    /// 弹幕文本
    pub text: String,
    /// 文字颜色（RGBA8888）
    pub color: u32,
    /// 字体大小（像素）
    pub font_size: u32,
    /// 时间戳（毫秒）
    pub timestamp_ms: u64,
    /// 轨道类型
    pub track_type: TrackType,
    /// 所在轨道索引
    pub track_index: usize,
    /// 当前 X 坐标
    pub x: f32,
    /// 当前 Y 坐标
    pub y: f32,
    /// 弹幕宽度（像素，计算后填充）
    pub width: f32,
    /// 弹幕高度（像素，计算后填充）
    pub height: f32,
    /// 滚动速度（像素/秒）
    pub speed: f32,
    /// 存活时长（毫秒，仅固定轨道使用）
    pub lifetime_ms: u64,
    /// 已存在时间（毫秒）
    pub elapsed_ms: u64,
    /// 是否存活
    pub alive: bool,
    /// 不透明度（0.0 ~ 1.0）
    pub opacity: f32,
    /// 文字特效（每条弹幕独立）
    pub effects: TextEffects,
}

impl BarrageItem {
    pub fn new(
        id: u64,
        text: String,
        color: u32,
        font_size: u32,
        timestamp_ms: u64,
        track_type: TrackType,
        effects: TextEffects,
    ) -> Self {
        Self {
            id,
            text,
            color,
            font_size,
            timestamp_ms,
            track_type,
            track_index: 0,
            x: 0.0,
            y: 0.0,
            width: 0.0,
            height: font_size as f32,
            speed: 0.0,
            lifetime_ms: 5000,
            elapsed_ms: 0,
            alive: true,
            opacity: 1.0,
            effects,
        }
    }

    /// 计算弹幕宽度（粗略估计，实际由渲染器精确计算）
    pub fn estimate_width(&self) -> f32 {
        // 假设每个字符宽度约为字体大小的 0.6 倍（汉字约 1.0，英文约 0.5）
        let char_count = self.text.chars().count() as f32;
        let avg_width_ratio = 0.7;
        char_count * self.font_size as f32 * avg_width_ratio
    }
}

/// 单个轨道
#[derive(Debug)]
struct Track {
    /// 轨道索引
    index: usize,
    /// 轨道 Y 坐标（顶部）
    y: f32,
    /// 轨道高度
    height: f32,
    /// 轨道中的弹幕列表
    items: Vec<BarrageItem>,
    /// 轨道类型
    track_type: TrackType,
    /// 最后一条弹幕的尾部位置（用于碰撞检测）
    last_tail_x: f32,
    /// 最后一条弹幕的进入时间
    last_entry_time_ms: u64,
}

impl Track {
    fn new(index: usize, y: f32, height: f32, track_type: TrackType) -> Self {
        Self {
            index,
            y,
            height,
            items: Vec::new(),
            track_type,
            last_tail_x: 0.0,
            last_entry_time_ms: 0,
        }
    }

    /// 检查轨道是否可以接受新弹幕（碰撞避让）
    fn can_accept(&self, item: &BarrageItem, canvas_width: f32, current_time_ms: u64) -> bool {
        match self.track_type {
            TrackType::Scroll => {
                // 滚动轨道：检查最后一条弹幕是否已经完全进入屏幕
                // 且新弹幕不会追上前方弹幕
                if self.items.is_empty() {
                    return true;
                }

                // 获取最后一条弹幕
                let last = &self.items[self.items.len() - 1];
                if !last.alive {
                    return true;
                }

                // 计算最后一条弹幕的尾部当前位置
                let time_delta = (current_time_ms - last.timestamp_ms) as f32 / 1000.0;
                let last_tail_x = canvas_width - last.speed * time_delta + last.width;

                // 如果最后一条弹幕的尾部还没进入屏幕（还在右边外面），则不能添加
                if last_tail_x > canvas_width {
                    return false;
                }

                // 速度检查：如果新弹幕比旧弹幕快，需要确保不会追上
                if item.speed > last.speed && last.speed > 0.0 {
                    // 计算追上需要的时间
                    let relative_speed = item.speed - last.speed;
                    let distance = last_tail_x - 0.0; // 新弹幕从右边进入
                    let catch_up_time = distance / relative_speed;
                    // 弹幕完全通过屏幕需要的时间
                    let screen_time = (canvas_width + item.width) / item.speed;
                    // 如果追上时间小于完全通过时间，则会碰撞
                    if catch_up_time < screen_time {
                        return false;
                    }
                }

                true
            }
            TrackType::Reverse => {
                // 逆向滚动轨道类似，但方向相反
                if self.items.is_empty() {
                    return true;
                }

                let last = &self.items[self.items.len() - 1];
                if !last.alive {
                    return true;
                }

                let time_delta = (current_time_ms - last.timestamp_ms) as f32 / 1000.0;
                let last_head_x = last.speed * time_delta - last.width;

                if last_head_x < 0.0 {
                    return false;
                }

                if item.speed > last.speed && last.speed > 0.0 {
                    let relative_speed = item.speed - last.speed;
                    let distance = 0.0 - last_head_x;
                    let catch_up_time = distance.abs() / relative_speed;
                    let screen_time = (canvas_width + item.width) / item.speed;
                    if catch_up_time < screen_time {
                        return false;
                    }
                }

                true
            }
            TrackType::Top | TrackType::Bottom => {
                // 固定轨道：检查最后一条弹幕是否已经消失
                if self.items.is_empty() {
                    return true;
                }

                let last = &self.items[self.items.len() - 1];
                if !last.alive {
                    return true;
                }

                // 固定弹幕需要等上一条消失后才能放新的
                let elapsed = current_time_ms.saturating_sub(last.timestamp_ms);
                elapsed >= last.lifetime_ms
            }
        }
    }

    /// 添加弹幕到轨道
    fn add_item(&mut self, mut item: BarrageItem, canvas_width: f32) {
        item.track_index = self.index;
        item.y = self.y + (self.height - item.height) / 2.0;

        match self.track_type {
            TrackType::Scroll => {
                item.x = canvas_width;
            }
            TrackType::Reverse => {
                item.x = -item.width;
            }
            TrackType::Top | TrackType::Bottom => {
                item.x = (canvas_width - item.width) / 2.0; // 居中
            }
        }

        self.last_entry_time_ms = item.timestamp_ms;
        self.items.push(item);
    }

    /// 更新轨道中所有弹幕的位置
    fn update(&mut self, delta_ms: u64, canvas_width: f32, _canvas_height: f32) {
        for item in &mut self.items {
            if !item.alive {
                continue;
            }

            item.elapsed_ms += delta_ms;

            match self.track_type {
                TrackType::Scroll => {
                    item.x -= item.speed * delta_ms as f32 / 1000.0;
                    // 弹幕完全离开左侧屏幕则死亡
                    if item.x + item.width < 0.0 {
                        item.alive = false;
                    }
                }
                TrackType::Reverse => {
                    item.x += item.speed * delta_ms as f32 / 1000.0;
                    // 弹幕完全离开右侧屏幕则死亡
                    if item.x > canvas_width {
                        item.alive = false;
                    }
                }
                TrackType::Top | TrackType::Bottom => {
                    // 固定弹幕根据生命周期计算透明度
                    let progress = item.elapsed_ms as f32 / item.lifetime_ms as f32;
                    if progress >= 1.0 {
                        item.alive = false;
                        item.opacity = 0.0;
                    } else if progress < 0.1 {
                        // 淡入
                        item.opacity = progress / 0.1;
                    } else if progress > 0.9 {
                        // 淡出
                        item.opacity = (1.0 - progress) / 0.1;
                    } else {
                        item.opacity = 1.0;
                    }
                }
            }
        }

        // 清理已死亡的弹幕
        self.items.retain(|item| item.alive);
    }

    /// 获取轨道中存活的弹幕数量
    fn alive_count(&self) -> usize {
        self.items.iter().filter(|i| i.alive).count()
    }

    /// 清空轨道
    fn clear(&mut self) {
        self.items.clear();
        self.last_tail_x = 0.0;
        self.last_entry_time_ms = 0;
    }
}

/// 轨道管理器
pub struct TrackManager {
    /// 画布宽度
    canvas_width: f32,
    /// 画布高度
    canvas_height: f32,
    /// 滚动轨道
    scroll_tracks: Vec<Track>,
    /// 顶部固定轨道
    top_tracks: Vec<Track>,
    /// 底部固定轨道
    bottom_tracks: Vec<Track>,
    /// 逆向滚动轨道
    reverse_tracks: Vec<Track>,
    /// 轨道高度（行高）
    track_height: f32,
    /// 轨道间距
    track_gap: f32,
    /// 基础滚动速度（像素/秒）
    base_speed: f32,
    /// 固定弹幕存活时间（毫秒）
    fixed_lifetime_ms: u64,
    /// 下一个弹幕 ID
    next_id: u64,
    /// 顶部轨道使用的下一个索引（轮询）
    top_track_cursor: usize,
    /// 底部轨道使用的下一个索引（轮询）
    bottom_track_cursor: usize,
}

impl TrackManager {
    /// 创建新的轨道管理器
    pub fn new(canvas_width: f32, canvas_height: f32) -> Self {
        let track_height = 36.0; // 默认行高
        let track_gap = 4.0;
        let total_per_track = track_height + track_gap;

        // 计算各种轨道的数量
        let scroll_track_count = ((canvas_height * 0.7) / total_per_track).max(1.0) as usize;
        let top_track_count = ((canvas_height * 0.15) / total_per_track).max(1.0) as usize;
        let bottom_track_count = ((canvas_height * 0.15) / total_per_track).max(1.0) as usize;

        let mut manager = Self {
            canvas_width,
            canvas_height,
            scroll_tracks: Vec::new(),
            top_tracks: Vec::new(),
            bottom_tracks: Vec::new(),
            reverse_tracks: Vec::new(),
            track_height,
            track_gap,
            base_speed: 150.0,
            fixed_lifetime_ms: 5000,
            next_id: 1,
            top_track_cursor: 0,
            bottom_track_cursor: 0,
        };

        manager.rebuild_tracks(scroll_track_count, top_track_count, bottom_track_count);
        manager
    }

    /// 重建所有轨道
    fn rebuild_tracks(&mut self, scroll_count: usize, top_count: usize, bottom_count: usize) {
        self.scroll_tracks.clear();
        self.top_tracks.clear();
        self.bottom_tracks.clear();
        self.reverse_tracks.clear();

        let total_per_track = self.track_height + self.track_gap;

        // 顶部固定轨道（从顶部开始）
        let mut current_y = self.track_gap;
        for i in 0..top_count {
            self.top_tracks
                .push(Track::new(i, current_y, self.track_height, TrackType::Top));
            current_y += total_per_track;
        }

        // 滚动轨道（在顶部轨道下方）
        let scroll_start_y = current_y;
        for i in 0..scroll_count {
            self.scroll_tracks.push(Track::new(
                i,
                scroll_start_y + i as f32 * total_per_track,
                self.track_height,
                TrackType::Scroll,
            ));
            self.reverse_tracks.push(Track::new(
                i,
                scroll_start_y + i as f32 * total_per_track,
                self.track_height,
                TrackType::Reverse,
            ));
        }

        // 底部固定轨道（从底部向上）
        let bottom_start_y =
            self.canvas_height - self.track_gap - bottom_count as f32 * total_per_track;
        for i in 0..bottom_count {
            self.bottom_tracks.push(Track::new(
                i,
                bottom_start_y + i as f32 * total_per_track,
                self.track_height,
                TrackType::Bottom,
            ));
        }
    }

    /// 调整画布大小
    pub fn resize(&mut self, width: f32, height: f32) {
        self.canvas_width = width;
        self.canvas_height = height;

        let total_per_track = self.track_height + self.track_gap;
        let scroll_track_count = ((height * 0.7) / total_per_track).max(1.0) as usize;
        let top_track_count = ((height * 0.15) / total_per_track).max(1.0) as usize;
        let bottom_track_count = ((height * 0.15) / total_per_track).max(1.0) as usize;

        // 保存现有弹幕
        let mut all_items = Vec::new();
        for track in &self.scroll_tracks {
            all_items.extend(track.items.clone());
        }
        for track in &self.top_tracks {
            all_items.extend(track.items.clone());
        }
        for track in &self.bottom_tracks {
            all_items.extend(track.items.clone());
        }
        for track in &self.reverse_tracks {
            all_items.extend(track.items.clone());
        }

        self.rebuild_tracks(scroll_track_count, top_track_count, bottom_track_count);

        // 重新分配弹幕到轨道（简化处理：只保留还在屏幕内的）
        for item in all_items {
            if item.alive {
                let _ = self.push_item(item);
            }
        }
    }

    /// 设置基础速度
    pub fn set_speed(&mut self, speed: f32) {
        self.base_speed = clamp_f32(speed, 10.0, 1000.0);
    }

    /// 设置轨道高度
    pub fn set_track_height(&mut self, height: f32) {
        self.track_height = height.max(10.0);
    }

    /// 推送一条弹幕，返回是否成功
    pub fn push(
        &mut self,
        text: String,
        color: u32,
        font_size: u32,
        timestamp_ms: u64,
        track_type: TrackType,
        effects: TextEffects,
    ) -> bool {
        let id = self.next_id;
        self.next_id += 1;

        let mut item = BarrageItem::new(
            id,
            text,
            color,
            font_size,
            timestamp_ms,
            track_type,
            effects,
        );
        item.width = item.estimate_width();
        item.height = font_size as f32 * 1.2;
        item.speed = self.base_speed;
        item.lifetime_ms = self.fixed_lifetime_ms;

        self.push_item(item)
    }

    /// 推送一个已有的弹幕对象
    fn push_item(&mut self, mut item: BarrageItem) -> bool {
        let current_time = item.timestamp_ms;

        match item.track_type {
            TrackType::Scroll => {
                // 寻找最合适的滚动轨道
                if let Some(track_idx) = self.find_best_scroll_track(&item, current_time) {
                    item.speed = self.base_speed;
                    self.scroll_tracks[track_idx].add_item(item, self.canvas_width);
                    return true;
                }
                false
            }
            TrackType::Reverse => {
                if let Some(track_idx) = self.find_best_reverse_track(&item, current_time) {
                    item.speed = self.base_speed;
                    self.reverse_tracks[track_idx].add_item(item, self.canvas_width);
                    return true;
                }
                false
            }
            TrackType::Top => {
                // 顶部固定轨道轮询
                let start_idx = self.top_track_cursor;
                for i in 0..self.top_tracks.len() {
                    let idx = (start_idx + i) % self.top_tracks.len();
                    if self.top_tracks[idx].can_accept(&item, self.canvas_width, current_time) {
                        self.top_track_cursor = (idx + 1) % self.top_tracks.len();
                        self.top_tracks[idx].add_item(item, self.canvas_width);
                        return true;
                    }
                }
                // 如果都满了，找最早会空出来的
                if !self.top_tracks.is_empty() {
                    self.top_tracks[start_idx].add_item(item, self.canvas_width);
                    self.top_track_cursor = (start_idx + 1) % self.top_tracks.len();
                    return true;
                }
                false
            }
            TrackType::Bottom => {
                let start_idx = self.bottom_track_cursor;
                for i in 0..self.bottom_tracks.len() {
                    let idx = (start_idx + i) % self.bottom_tracks.len();
                    if self.bottom_tracks[idx].can_accept(&item, self.canvas_width, current_time) {
                        self.bottom_track_cursor = (idx + 1) % self.bottom_tracks.len();
                        self.bottom_tracks[idx].add_item(item, self.canvas_width);
                        return true;
                    }
                }
                if !self.bottom_tracks.is_empty() {
                    self.bottom_tracks[start_idx].add_item(item, self.canvas_width);
                    self.bottom_track_cursor = (start_idx + 1) % self.bottom_tracks.len();
                    return true;
                }
                false
            }
        }
    }

    /// 寻找最佳滚动轨道（碰撞避让）
    fn find_best_scroll_track(&self, item: &BarrageItem, current_time_ms: u64) -> Option<usize> {
        let mut best_idx = None;
        let mut best_score = f32::NEG_INFINITY;

        for (i, track) in self.scroll_tracks.iter().enumerate() {
            if track.can_accept(item, self.canvas_width, current_time_ms) {
                // 评分：轨道中弹幕越少越好
                let score = -(track.alive_count() as f32);
                if score > best_score {
                    best_score = score;
                    best_idx = Some(i);
                }
            }
        }

        // 如果所有轨道都满了，找最空的那个
        if best_idx.is_none() && !self.scroll_tracks.is_empty() {
            let mut min_count = usize::MAX;
            for (i, track) in self.scroll_tracks.iter().enumerate() {
                let count = track.alive_count();
                if count < min_count {
                    min_count = count;
                    best_idx = Some(i);
                }
            }
        }

        best_idx
    }

    /// 寻找最佳逆向滚动轨道
    fn find_best_reverse_track(&self, item: &BarrageItem, current_time_ms: u64) -> Option<usize> {
        let mut best_idx = None;
        let mut best_score = f32::NEG_INFINITY;

        for (i, track) in self.reverse_tracks.iter().enumerate() {
            if track.can_accept(item, self.canvas_width, current_time_ms) {
                let score = -(track.alive_count() as f32);
                if score > best_score {
                    best_score = score;
                    best_idx = Some(i);
                }
            }
        }

        if best_idx.is_none() && !self.reverse_tracks.is_empty() {
            let mut min_count = usize::MAX;
            for (i, track) in self.reverse_tracks.iter().enumerate() {
                let count = track.alive_count();
                if count < min_count {
                    min_count = count;
                    best_idx = Some(i);
                }
            }
        }

        best_idx
    }

    /// 更新所有轨道
    pub fn update(&mut self, delta_ms: u64) {
        for track in &mut self.scroll_tracks {
            track.update(delta_ms, self.canvas_width, self.canvas_height);
        }
        for track in &mut self.top_tracks {
            track.update(delta_ms, self.canvas_width, self.canvas_height);
        }
        for track in &mut self.bottom_tracks {
            track.update(delta_ms, self.canvas_width, self.canvas_height);
        }
        for track in &mut self.reverse_tracks {
            track.update(delta_ms, self.canvas_width, self.canvas_height);
        }
    }

    /// 获取所有存活的弹幕（用于渲染）
    pub fn get_all_alive(&self) -> Vec<&BarrageItem> {
        let mut result = Vec::new();

        for track in &self.scroll_tracks {
            result.extend(track.items.iter().filter(|i| i.alive));
        }
        for track in &self.top_tracks {
            result.extend(track.items.iter().filter(|i| i.alive));
        }
        for track in &self.bottom_tracks {
            result.extend(track.items.iter().filter(|i| i.alive));
        }
        for track in &self.reverse_tracks {
            result.extend(track.items.iter().filter(|i| i.alive));
        }

        result
    }

    /// 获取所有存活弹幕的可变引用
    pub fn get_all_alive_mut(&mut self) -> Vec<&mut BarrageItem> {
        let mut result = Vec::new();

        for track in &mut self.scroll_tracks {
            result.extend(track.items.iter_mut().filter(|i| i.alive));
        }
        for track in &mut self.top_tracks {
            result.extend(track.items.iter_mut().filter(|i| i.alive));
        }
        for track in &mut self.bottom_tracks {
            result.extend(track.items.iter_mut().filter(|i| i.alive));
        }
        for track in &mut self.reverse_tracks {
            result.extend(track.items.iter_mut().filter(|i| i.alive));
        }

        result
    }

    /// 清空所有弹幕
    pub fn clear(&mut self) {
        for track in &mut self.scroll_tracks {
            track.clear();
        }
        for track in &mut self.top_tracks {
            track.clear();
        }
        for track in &mut self.bottom_tracks {
            track.clear();
        }
        for track in &mut self.reverse_tracks {
            track.clear();
        }
    }

    /// 获取当前存活弹幕总数
    pub fn alive_count(&self) -> usize {
        let mut count = 0;
        for track in &self.scroll_tracks {
            count += track.alive_count();
        }
        for track in &self.top_tracks {
            count += track.alive_count();
        }
        for track in &self.bottom_tracks {
            count += track.alive_count();
        }
        for track in &self.reverse_tracks {
            count += track.alive_count();
        }
        count
    }

    /// 获取滚动轨道数量
    pub fn scroll_track_count(&self) -> usize {
        self.scroll_tracks.len()
    }

    /// 获取顶部轨道数量
    pub fn top_track_count(&self) -> usize {
        self.top_tracks.len()
    }

    /// 获取底部轨道数量
    pub fn bottom_track_count(&self) -> usize {
        self.bottom_tracks.len()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_track_type_from_u32() {
        assert_eq!(TrackType::from_u32(0), TrackType::Scroll);
        assert_eq!(TrackType::from_u32(1), TrackType::Top);
        assert_eq!(TrackType::from_u32(2), TrackType::Bottom);
        assert_eq!(TrackType::from_u32(3), TrackType::Reverse);
        assert_eq!(TrackType::from_u32(99), TrackType::Scroll);
    }

    #[test]
    fn test_track_manager_creation() {
        let manager = TrackManager::new(800.0, 600.0);
        assert!(manager.scroll_track_count() > 0);
        assert!(manager.top_track_count() > 0);
        assert!(manager.bottom_track_count() > 0);
    }

    #[test]
    fn test_push_barrage() {
        let mut manager = TrackManager::new(800.0, 600.0);
        let result = manager.push(
            "测试弹幕".to_string(),
            0xFFFFFFFF,
            24,
            0,
            TrackType::Scroll,
            TextEffects::default(),
        );
        assert!(result);
        assert_eq!(manager.alive_count(), 1);
    }

    #[test]
    fn test_update_barrage() {
        let mut manager = TrackManager::new(800.0, 600.0);
        manager.push(
            "测试".to_string(),
            0xFFFFFFFF,
            24,
            0,
            TrackType::Scroll,
            TextEffects::default(),
        );

        let items = manager.get_all_alive();
        let initial_x = items[0].x;

        manager.update(1000); // 1秒后

        let items = manager.get_all_alive();
        assert!(items[0].x < initial_x); // 向左移动了
    }

    #[test]
    fn test_clear() {
        let mut manager = TrackManager::new(800.0, 600.0);
        manager.push(
            "测试1".to_string(),
            0xFFFFFFFF,
            24,
            0,
            TrackType::Scroll,
            TextEffects::default(),
        );
        manager.push(
            "测试2".to_string(),
            0xFFFFFFFF,
            24,
            0,
            TrackType::Top,
            TextEffects::default(),
        );

        assert_eq!(manager.alive_count(), 2);

        manager.clear();
        assert_eq!(manager.alive_count(), 0);
    }

    #[test]
    fn test_resize() {
        let mut manager = TrackManager::new(800.0, 600.0);
        manager.push(
            "测试".to_string(),
            0xFFFFFFFF,
            24,
            0,
            TrackType::Scroll,
            TextEffects::default(),
        );

        let count_before = manager.scroll_track_count();
        manager.resize(1920.0, 1080.0);
        let count_after = manager.scroll_track_count();

        assert!(count_after >= count_before);
    }
}
