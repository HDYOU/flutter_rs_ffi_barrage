use flutter_rust_bridge::frb;
use std::sync::Mutex;

use crate::api::common::*;
use crate::core::engine::BarrageEngine;
use crate::render::renderer::BarrageRenderer;

#[frb(opaque)]
pub struct EngineHandle {
    pub(crate) engine: Mutex<BarrageEngine>,
    pub(crate) renderer: Mutex<BarrageRenderer>,
}

#[frb]
impl EngineHandle {
    #[frb(sync)]
    pub fn create(width: u32, height: u32) -> Self {
        let engine = BarrageEngine::new(width, height);
        let renderer = BarrageRenderer::new(width, height);
        Self {
            engine: Mutex::new(engine),
            renderer: Mutex::new(renderer),
        }
    }

    #[frb(sync)]
    pub fn resize(&self, width: u32, height: u32) {
        let mut engine = self.engine.lock().unwrap();
        engine.resize(width, height);
        self.renderer.lock().unwrap().resize(width, height);
    }

    #[frb(sync)]
    pub fn set_speed(&self, speed: f64) {
        let mut engine = self.engine.lock().unwrap();
        engine.set_speed(speed as f32);
    }

    #[frb(sync)]
    pub fn pause(&self) {
        let mut engine = self.engine.lock().unwrap();
        engine.pause();
    }

    #[frb(sync)]
    pub fn resume(&self) {
        let mut engine = self.engine.lock().unwrap();
        engine.resume();
    }

    #[frb(sync)]
    pub fn seek(&self, timestamp_ms: i64) {
        let mut engine = self.engine.lock().unwrap();
        engine.seek(timestamp_ms as u64);
    }

    #[frb(sync)]
    pub fn clear(&self) {
        let mut engine = self.engine.lock().unwrap();
        engine.clear();
    }

    #[frb(sync)]
    pub fn push_barrage(&self, msg: BarrageMsg) -> bool {
        let mut engine = self.engine.lock().unwrap();
        let effects = msg.text_effects.to_internal();
        engine.push(
            &msg.text,
            msg.color,
            msg.font_size as u32,
            msg.timestamp as u64,
            msg.track_type,
            effects,
        )
    }

    #[frb(sync)]
    pub fn render_frame(&self, timestamp_ms: i64) -> Vec<u8> {
        let mut engine = self.engine.lock().unwrap();
        let mut renderer = self.renderer.lock().unwrap();
        engine.update(timestamp_ms as u64);

        let width = engine.width as usize;
        let height = engine.height as usize;
        let buffer_len = (width * height) as u64;
        let mut buffer = vec![0u32; width * height];
        renderer.render_frame(&engine, timestamp_ms as u64, &mut buffer, buffer_len);

        let mut rgba = Vec::with_capacity(width * height * 4);
        for pixel in buffer {
            rgba.push(((pixel >> 24) & 0xFF) as u8);
            rgba.push(((pixel >> 16) & 0xFF) as u8);
            rgba.push(((pixel >> 8) & 0xFF) as u8);
            rgba.push((pixel & 0xFF) as u8);
        }
        rgba
    }

    #[frb(sync)]
    pub fn set_global_stroke(&self, config: StrokeConfig) {
        let mut engine = self.engine.lock().unwrap();
        engine.set_global_stroke(config.enabled, config.width, config.color);
    }

    #[frb(sync)]
    pub fn set_global_shadow(&self, config: ShadowConfig) {
        let mut engine = self.engine.lock().unwrap();
        engine.set_global_shadow(
            config.enabled,
            config.offset_x,
            config.offset_y,
            config.blur,
            config.color,
        );
    }

    #[frb(sync)]
    pub fn set_global_neon(&self, config: NeonConfig) {
        let mut engine = self.engine.lock().unwrap();
        engine.set_global_neon(config.enabled, config.radius, config.color, config.intensity);
    }

    #[frb(sync)]
    pub fn set_global_gradient(&self, config: GradientConfig) {
        let mut engine = self.engine.lock().unwrap();
        engine.set_global_gradient(
            config.enabled,
            config.grad_type as u32,
            &config.colors,
            &[],
            config.angle,
        );
    }

    pub fn version() -> String {
        crate::VERSION.to_string()
    }

    #[frb(sync)]
    pub fn alive_count(&self) -> u32 {
        self.engine.lock().unwrap().alive_count() as u32
    }

    #[frb(sync)]
    pub fn dimensions(&self) -> EngineDimensions {
        let engine = self.engine.lock().unwrap();
        EngineDimensions {
            width: engine.width,
            height: engine.height,
        }
    }

    #[frb(sync)]
    pub fn play_state(&self) -> PlayState {
        self.engine.lock().unwrap().play_state
    }

    #[frb(sync)]
    pub fn current_time(&self) -> i64 {
        self.engine.lock().unwrap().current_time_ms as i64
    }
}

#[frb]
#[derive(Debug, Clone, Copy)]
pub struct EngineDimensions {
    pub width: u32,
    pub height: u32,
}
