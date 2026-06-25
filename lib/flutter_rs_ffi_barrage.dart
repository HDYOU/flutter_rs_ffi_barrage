library flutter_rs_ffi_barrage;

export 'src/engine.dart' show BarrageEngine;
export 'src/widget.dart' show BarrageController, BarrageView;
export 'package:flutter_rs_ffi_barrage/src/rust/frb_generated.dart' show RustLib;
export 'package:flutter_rs_ffi_barrage/src/rust/api/common.dart'
    show
        BarrageMsg,
        StrokeConfig,
        ShadowConfig,
        NeonConfig,
        GradientConfig,
        TextEffectConfig;
export 'package:flutter_rs_ffi_barrage/src/rust/track/track_manager.dart'
    show TrackType;
export 'package:flutter_rs_ffi_barrage/src/rust/text_effect/effects.dart'
    show GradientType;
export 'package:flutter_rs_ffi_barrage/src/rust/core/engine.dart'
    show PlayState;
