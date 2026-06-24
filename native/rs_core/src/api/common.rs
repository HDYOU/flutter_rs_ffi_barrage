use flutter_rust_bridge::frb;
pub use crate::core::engine::PlayState;
pub use crate::text_effect::effects::GradientType;
pub use crate::track::track_manager::TrackType;

#[frb]
#[derive(Debug, Clone)]
pub struct StrokeConfig {
    pub enabled: bool,
    pub width: f32,
    pub color: u32,
    pub is_outer: bool,
}

impl Default for StrokeConfig {
    fn default() -> Self {
        Self {
            enabled: false,
            width: 2.0,
            color: 0xFF000000,
            is_outer: true,
        }
    }
}

#[frb]
#[derive(Debug, Clone)]
pub struct ShadowConfig {
    pub enabled: bool,
    pub offset_x: f32,
    pub offset_y: f32,
    pub blur: f32,
    pub color: u32,
    pub layers: u32,
}

impl Default for ShadowConfig {
    fn default() -> Self {
        Self {
            enabled: false,
            offset_x: 2.0,
            offset_y: 2.0,
            blur: 0.0,
            color: 0x80000000,
            layers: 1,
        }
    }
}

#[frb]
#[derive(Debug, Clone)]
pub struct NeonConfig {
    pub enabled: bool,
    pub radius: f32,
    pub color: u32,
    pub intensity: f32,
    pub layers: u32,
}

impl Default for NeonConfig {
    fn default() -> Self {
        Self {
            enabled: false,
            radius: 10.0,
            color: 0xFFFF00FF,
            intensity: 0.8,
            layers: 4,
        }
    }
}

#[frb]
#[derive(Debug, Clone)]
pub struct GradientConfig {
    pub enabled: bool,
    pub grad_type: GradientType,
    pub colors: Vec<u32>,
    pub angle: f32,
}

impl Default for GradientConfig {
    fn default() -> Self {
        Self {
            enabled: false,
            grad_type: GradientType::Rainbow,
            colors: vec![],
            angle: 0.0,
        }
    }
}

#[frb]
#[derive(Debug, Clone)]
pub struct TextEffectConfig {
    pub stroke: StrokeConfig,
    pub shadow: ShadowConfig,
    pub neon: NeonConfig,
    pub gradient: GradientConfig,
}

impl Default for TextEffectConfig {
    fn default() -> Self {
        Self {
            stroke: StrokeConfig::default(),
            shadow: ShadowConfig::default(),
            neon: NeonConfig::default(),
            gradient: GradientConfig::default(),
        }
    }
}

impl TextEffectConfig {
    pub fn to_internal(&self) -> crate::text_effect::effects::TextEffects {
        let mut effects = crate::text_effect::effects::TextEffects::default();

        if self.stroke.enabled {
            effects.stroke.enabled = true;
            effects.stroke.width = self.stroke.width;
            effects.stroke.color =
                crate::utils::color::Color::from_u32(self.stroke.color);
        }

        if self.shadow.enabled {
            effects.shadow.enabled = true;
            effects.shadow.offset_x = self.shadow.offset_x;
            effects.shadow.offset_y = self.shadow.offset_y;
            effects.shadow.blur = self.shadow.blur;
            effects.shadow.color =
                crate::utils::color::Color::from_u32(self.shadow.color);
        }

        if self.neon.enabled {
            effects.neon.enabled = true;
            effects.neon.radius = self.neon.radius;
            effects.neon.color =
                crate::utils::color::Color::from_u32(self.neon.color);
            effects.neon.intensity = self.neon.intensity;
        }

        if self.gradient.enabled {
            effects.gradient.enabled = true;
            effects.gradient.gradient_type = self.gradient.grad_type;
            effects.gradient.angle = self.gradient.angle;
            if !self.gradient.colors.is_empty() {
                let colors: Vec<u32> = self.gradient.colors.clone();
                let stops: Vec<f32> = (0..colors.len())
                    .map(|i| i as f32 / (colors.len() - 1) as f32)
                    .collect();
                effects.gradient.set_colors_from_u32(&colors, &stops);
            }
        }

        effects
    }
}

#[frb]
#[derive(Debug, Clone)]
pub struct BarrageMsg {
    pub id: String,
    pub text: String,
    pub track_type: TrackType,
    pub color: u32,
    pub font_size: f64,
    pub timestamp: i64,
    pub text_effects: TextEffectConfig,
}
