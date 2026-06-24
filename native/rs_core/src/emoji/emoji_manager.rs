//! 表情管理器
//!
//! 功能：
//! - LRU 内存缓存表情位图
//! - 三种加载模式：Flutter 位图、本地文件、远程 URL
//! - 按需回调拉取：当表情不存在时，通过全局回调请求 Flutter 端提供位图
//! - 文本解析：解析 [xxx] 格式的表情标签

use lru::LruCache;
use parking_lot::RwLock;
use std::num::NonZeroUsize;
use std::sync::Arc;

/// 表情位图数据
#[derive(Debug, Clone)]
pub struct EmojiBitmap {
    /// 表情文本标签（如 "[微笑]"）
    pub text: String,
    /// 位图宽度（像素）
    pub width: u32,
    /// 位图高度（像素）
    pub height: u32,
    /// RGBA8888 像素数据
    pub pixels: Vec<u8>,
    /// 表情来源类型
    pub source: EmojiSource,
}

/// 表情来源类型
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EmojiSource {
    /// 来自 Flutter 位图
    Flutter,
    /// 来自本地文件路径
    LocalPath,
    /// 来自远程 URL
    RemoteUrl,
}

/// 表情加载状态
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EmojiLoadState {
    /// 已加载
    Loaded,
    /// 加载中（已请求，等待回调）
    Loading,
    /// 加载失败
    Failed,
    /// 未加载
    NotLoaded,
}

/// 文本中的表情分段
#[derive(Debug, Clone)]
pub enum TextSegment {
    /// 纯文本
    Text(String),
    /// 表情
    Emoji {
        /// 表情文本
        text: String,
        /// 表情宽度
        width: u32,
        /// 表情高度
        height: u32,
    },
}

/// 表情解析结果
#[derive(Debug, Clone)]
pub struct ParsedEmojiText {
    /// 文本分段
    pub segments: Vec<TextSegment>,
    /// 总宽度（像素，基于字体大小估算）
    pub total_width: f32,
    /// 缺失的表情列表（需要加载的）
    pub missing_emojis: Vec<String>,
}

/// 表情管理器
pub struct EmojiManager {
    /// LRU 缓存（key: 表情文本标签）
    cache: RwLock<LruCache<String, Arc<EmojiBitmap>>>,
    /// 加载中的表情（防止重复请求）
    loading: RwLock<std::collections::HashSet<String>>,
    /// 表情大小（与字体高度的比例）
    emoji_scale: f32,
    /// 最大缓存数量
    max_cache_size: usize,
}

impl EmojiManager {
    /// 创建新的表情管理器
    pub fn new(max_cache_size: usize) -> Self {
        let cache_size =
            NonZeroUsize::new(max_cache_size.max(1)).unwrap_or(NonZeroUsize::new(100).unwrap());
        Self {
            cache: RwLock::new(LruCache::new(cache_size)),
            loading: RwLock::new(std::collections::HashSet::new()),
            emoji_scale: 1.2,
            max_cache_size,
        }
    }

    /// 获取表情大小比例
    pub fn emoji_scale(&self) -> f32 {
        self.emoji_scale
    }

    /// 设置表情大小比例
    pub fn set_emoji_scale(&mut self, scale: f32) {
        self.emoji_scale = scale.clamp(0.5, 3.0);
    }

    /// 检查表情是否已加载
    pub fn has_emoji(&self, text: &str) -> bool {
        self.cache.read().contains(text)
    }

    /// 获取表情位图
    pub fn get_emoji(&self, text: &str) -> Option<Arc<EmojiBitmap>> {
        let mut cache = self.cache.write();
        cache.get(text).cloned()
    }

    /// 注册表情（来自 Flutter 位图数据）
    pub fn register_from_flutter(
        &self,
        emoji_text: &str,
        width: u32,
        height: u32,
        pixels: &[u8],
    ) -> bool {
        if width == 0 || height == 0 {
            return false;
        }

        let expected_len = (width * height * 4) as usize;
        if pixels.len() < expected_len {
            return false;
        }

        let bitmap = EmojiBitmap {
            text: emoji_text.to_string(),
            width,
            height,
            pixels: pixels[..expected_len].to_vec(),
            source: EmojiSource::Flutter,
        };

        let mut cache = self.cache.write();
        cache.put(emoji_text.to_string(), Arc::new(bitmap));

        // 从加载中移除
        self.loading.write().remove(emoji_text);

        true
    }

    /// 注册表情（来自本地文件路径）
    pub fn register_from_local_path(&self, emoji_text: &str, path: &str) -> bool {
        // 尝试读取并解码图片
        match std::fs::read(path) {
            Ok(data) => match self.decode_image(&data) {
                Some((width, height, pixels)) => {
                    let bitmap = EmojiBitmap {
                        text: emoji_text.to_string(),
                        width,
                        height,
                        pixels,
                        source: EmojiSource::LocalPath,
                    };
                    let mut cache = self.cache.write();
                    cache.put(emoji_text.to_string(), Arc::new(bitmap));
                    self.loading.write().remove(emoji_text);
                    true
                }
                None => {
                    self.loading.write().remove(emoji_text);
                    false
                }
            },
            Err(_) => {
                self.loading.write().remove(emoji_text);
                false
            }
        }
    }

    /// 注册表情（来自远程 URL）
    /// 注意：此函数当前返回 false，建议 Flutter 端先下载图片，
    /// 再通过 register_from_flutter 注册表情位图。
    pub fn register_from_url(&self, emoji_text: &str, url: &str) -> bool {
        let _ = url;
        let _ = emoji_text;
        false
    }

    /// 解码图片数据
    fn decode_image(&self, data: &[u8]) -> Option<(u32, u32, Vec<u8>)> {
        // 使用 image crate 解码
        match image::load_from_memory(data) {
            Ok(img) => {
                let rgba = img.to_rgba8();
                let width = rgba.width();
                let height = rgba.height();
                let pixels = rgba.into_raw();
                Some((width, height, pixels))
            }
            Err(_) => None,
        }
    }

    /// 请求加载表情（如果不存在，标记为加载中）
    /// 返回 true 表示已在缓存中，false 表示需要加载
    pub fn request_emoji(&self, text: &str) -> EmojiLoadState {
        if self.cache.read().contains(text) {
            return EmojiLoadState::Loaded;
        }

        if self.loading.read().contains(text) {
            return EmojiLoadState::Loading;
        }

        EmojiLoadState::NotLoaded
    }

    /// 标记表情为加载中
    pub fn mark_loading(&self, text: &str) {
        self.loading.write().insert(text.to_string());
    }

    /// 标记表情加载失败
    pub fn mark_failed(&self, text: &str) {
        self.loading.write().remove(text);
    }

    /// 解析文本中的表情标签 [xxx]
    /// 返回分段后的文本和缺失的表情列表
    pub fn parse_text(&self, text: &str, font_size: u32) -> ParsedEmojiText {
        let mut segments = Vec::new();
        let mut missing_emojis = Vec::new();
        let mut total_width = 0.0f32;
        let mut current_text = String::new();

        let emoji_height = font_size as f32 * self.emoji_scale;

        let mut chars = text.chars().peekable();

        while let Some(c) = chars.next() {
            if c == '[' {
                // 尝试读取表情标签
                let mut emoji_text = String::new();
                let mut found_closing = false;

                while let Some(&ec) = chars.peek() {
                    if ec == ']' {
                        chars.next(); // 消耗 ']'
                        found_closing = true;
                        break;
                    }
                    // 限制表情标签长度，防止误解析
                    if emoji_text.len() >= 32 {
                        break;
                    }
                    emoji_text.push(ec);
                    chars.next();
                }

                if found_closing && !emoji_text.is_empty() {
                    let emoji_tag = format!("[{}]", emoji_text);

                    // 先输出之前累积的文本
                    if !current_text.is_empty() {
                        let text_width =
                            current_text.chars().count() as f32 * font_size as f32 * 0.6;
                        total_width += text_width;
                        segments.push(TextSegment::Text(std::mem::take(&mut current_text)));
                    }

                    // 检查表情是否存在
                    let emoji_state = self.request_emoji(&emoji_tag);

                    match emoji_state {
                        EmojiLoadState::Loaded => {
                            if let Some(bitmap) = self.get_emoji(&emoji_tag) {
                                // 按字体大小缩放表情
                                let scale = emoji_height / bitmap.height as f32;
                                let scaled_width = bitmap.width as f32 * scale;
                                total_width += scaled_width;
                                segments.push(TextSegment::Emoji {
                                    text: emoji_tag,
                                    width: bitmap.width,
                                    height: bitmap.height,
                                });
                            } else {
                                // 理论上不会到这里
                                missing_emojis.push(emoji_tag.clone());
                                let emoji_width = emoji_height; // 近似正方形
                                total_width += emoji_width;
                                segments.push(TextSegment::Emoji {
                                    text: emoji_tag,
                                    width: emoji_height as u32,
                                    height: emoji_height as u32,
                                });
                            }
                        }
                        EmojiLoadState::Loading
                        | EmojiLoadState::NotLoaded
                        | EmojiLoadState::Failed => {
                            missing_emojis.push(emoji_tag.clone());
                            let emoji_width = emoji_height; // 近似正方形
                            total_width += emoji_width;
                            segments.push(TextSegment::Emoji {
                                text: emoji_tag,
                                width: emoji_height as u32,
                                height: emoji_height as u32,
                            });
                        }
                    }
                } else {
                    // 没有找到闭合括号，把已读取的字符放回去
                    current_text.push('[');
                    current_text.push_str(&emoji_text);
                    if !found_closing {
                        // 说明读到了末尾或长度限制，没有 ']'
                    }
                }
            } else {
                current_text.push(c);
            }
        }

        // 输出剩余文本
        if !current_text.is_empty() {
            let text_width = current_text.chars().count() as f32 * font_size as f32 * 0.6;
            total_width += text_width;
            segments.push(TextSegment::Text(current_text));
        }

        ParsedEmojiText {
            segments,
            total_width,
            missing_emojis,
        }
    }

    /// 获取缓存大小
    pub fn cache_size(&self) -> usize {
        self.cache.read().len()
    }

    /// 清空缓存
    pub fn clear_cache(&self) {
        self.cache.write().clear();
        self.loading.write().clear();
    }

    /// 获取缓存统计信息
    pub fn cache_stats(&self) -> (usize, usize) {
        let cache = self.cache.read();
        (cache.len(), self.max_cache_size)
    }
}

impl Default for EmojiManager {
    fn default() -> Self {
        Self::new(200)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_emoji_manager_creation() {
        let manager = EmojiManager::new(100);
        assert_eq!(manager.cache_size(), 0);
    }

    #[test]
    fn test_register_from_flutter() {
        let manager = EmojiManager::new(100);
        let pixels = vec![255u8; 16 * 16 * 4]; // 16x16 RGBA

        assert!(manager.register_from_flutter("[微笑]", 16, 16, &pixels));
        assert!(manager.has_emoji("[微笑]"));
        assert_eq!(manager.cache_size(), 1);
    }

    #[test]
    fn test_register_invalid() {
        let manager = EmojiManager::new(100);
        let pixels = vec![255u8; 10];

        // 尺寸为0
        assert!(!manager.register_from_flutter("[test]", 0, 16, &pixels));
        // 像素数据不足
        assert!(!manager.register_from_flutter("[test]", 16, 16, &pixels));
    }

    #[test]
    fn test_parse_text_no_emoji() {
        let manager = EmojiManager::new(100);
        let result = manager.parse_text("hello world", 24);

        assert_eq!(result.segments.len(), 1);
        assert!(result.missing_emojis.is_empty());
        match &result.segments[0] {
            TextSegment::Text(t) => assert_eq!(t, "hello world"),
            _ => panic!("Expected Text segment"),
        }
    }

    #[test]
    fn test_parse_text_with_emoji() {
        let manager = EmojiManager::new(100);
        // 先注册一个表情
        let pixels = vec![255u8; 16 * 16 * 4];
        manager.register_from_flutter("[微笑]", 16, 16, &pixels);

        let result = manager.parse_text("你好[微笑]世界", 24);

        assert_eq!(result.segments.len(), 3);
        assert!(result.missing_emojis.is_empty());
    }

    #[test]
    fn test_parse_text_missing_emoji() {
        let manager = EmojiManager::new(100);
        let result = manager.parse_text("你好[不存在的表情]世界", 24);

        assert_eq!(result.missing_emojis.len(), 1);
        assert_eq!(result.missing_emojis[0], "[不存在的表情]");
    }

    #[test]
    fn test_lru_eviction() {
        let manager = EmojiManager::new(3);

        for i in 0..5 {
            let pixels = vec![255u8; 16 * 16 * 4];
            manager.register_from_flutter(&format!("[emoji{}]", i), 16, 16, &pixels);
        }

        // 缓存容量为3，所以应该只有最后3个
        assert_eq!(manager.cache_size(), 3);
        assert!(!manager.has_emoji("[emoji0]"));
        assert!(!manager.has_emoji("[emoji1]"));
        assert!(manager.has_emoji("[emoji2]"));
        assert!(manager.has_emoji("[emoji3]"));
        assert!(manager.has_emoji("[emoji4]"));
    }

    #[test]
    fn test_clear_cache() {
        let manager = EmojiManager::new(100);
        let pixels = vec![255u8; 16 * 16 * 4];
        manager.register_from_flutter("[test]", 16, 16, &pixels);

        assert_eq!(manager.cache_size(), 1);
        manager.clear_cache();
        assert_eq!(manager.cache_size(), 0);
    }
}
