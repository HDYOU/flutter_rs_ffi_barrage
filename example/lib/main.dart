import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_rs_ffi_barrage/flutter_rs_ffi_barrage.dart';

void main() {
  initializeRustLib();
  runApp(const BarrageDemoApp());
}

class BarrageDemoApp extends StatelessWidget {
  const BarrageDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FRB Barrage Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const BarrageDemoPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class BarrageDemoPage extends StatefulWidget {
  const BarrageDemoPage({super.key});

  @override
  State<BarrageDemoPage> createState() => _BarrageDemoPageState();
}

class _BarrageDemoPageState extends State<BarrageDemoPage> {
  late final BarrageController _controller;
  final TextEditingController _inputController = TextEditingController();
  TrackType _selectedTrackType = TrackType.scroll;
  int _barrageCount = 0;

  bool _strokeEnabled = false;
  bool _shadowEnabled = false;
  bool _neonEnabled = false;
  bool _gradientEnabled = false;

  double _currentSpeed = 1.0;

  @override
  void initState() {
    super.initState();
    _controller = BarrageController(width: 800, height: 600);
    _pushInitialDemoBarrages();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _pushInitialDemoBarrages() {
    const demos = [
      ('Welcome to FRB Barrage Demo!', 0xFFFFFFFF),
      ('High-performance Rust rendering', 0xFFFFFF00),
      ('Stroke / Shadow / Neon / Gradient', 0xFF00FFFF),
      ('Scrolling / Top / Bottom / Reverse', 0xFFFF4081),
      ('flutter_rust_bridge migration done', 0xFF69F0AE),
    ];

    for (int i = 0; i < demos.length; i++) {
      final msg = BarrageMsg(
        id: 'demo_$i',
        text: demos[i].$1,
        trackType: TrackType.scroll,
        color: demos[i].$2,
        fontSize: 24,
        timestamp: i * 800,
        textEffects: _buildCurrentEffectConfig(),
      );
      _controller.push(msg);
      _barrageCount++;
    }
  }

  void _sendBarrage() {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;

    _barrageCount++;
    const colors = [
      0xFFFFFFFF,
      0xFFFFFF00,
      0xFF00FFFF,
      0xFFFF4081,
      0xFF69F0AE,
      0xFFFF9800,
    ];

    final msg = BarrageMsg(
      id: 'user_$_barrageCount',
      text: text,
      trackType: _selectedTrackType,
      color: colors[_barrageCount % colors.length],
      fontSize: 24,
      timestamp: _controller.currentTime,
      textEffects: _buildCurrentEffectConfig(),
    );

    _controller.push(msg);
    _inputController.clear();
  }

  TextEffectConfig _buildCurrentEffectConfig() {
    return TextEffectConfig(
      stroke:
          _strokeEnabled
              ? const StrokeConfig(
                enabled: true,
                width: 2.5,
                color: 0xFF000000,
                isOuter: true,
              )
              : const StrokeConfig(
                enabled: false,
                width: 0,
                color: 0,
                isOuter: false,
              ),
      shadow:
          _shadowEnabled
              ? const ShadowConfig(
                enabled: true,
                offsetX: 3.0,
                offsetY: 3.0,
                blur: 0.0,
                color: 0x80000000,
                layers: 3,
              )
              : const ShadowConfig(
                enabled: false,
                offsetX: 0,
                offsetY: 0,
                blur: 0,
                color: 0,
                layers: 0,
              ),
      neon:
          _neonEnabled
              ? const NeonConfig(
                enabled: true,
                radius: 10.0,
                color: 0xFFFF00FF,
                intensity: 0.8,
                layers: 4,
              )
              : const NeonConfig(
                enabled: false,
                radius: 0,
                color: 0,
                intensity: 0,
                layers: 0,
              ),
      gradient:
          _gradientEnabled
              ? GradientConfig(
                enabled: true,
                gradType: GradientType.rainbow,
                colors: Uint32List(0),
                angle: 0.0,
              )
              : GradientConfig(
                enabled: false,
                gradType: GradientType.rainbow,
                colors: Uint32List(0),
                angle: 0,
              ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('FRB Barrage Demo'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          Expanded(flex: 3, child: _buildBarrageArea()),
          _buildEffectToggles(),
          _buildTrackSelector(),
          _buildInputPanel(),
          _buildControlPanel(),
        ],
      ),
    );
  }

  Widget _buildBarrageArea() {
    return Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1a1a2e),
            Color(0xFF16213e),
            Color(0xFF0f3460),
            Color(0xFF533483),
          ],
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BarrageView(
          controller: _controller,
          backgroundColor: const Color(0x00000000),
        ),
      ),
    );
  }

  Widget _buildEffectToggles() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: Colors.grey.shade100,
      child: Row(
        children: [
          Expanded(
            child: _buildSwitch('Stroke', _strokeEnabled, (v) {
              setState(() => _strokeEnabled = v);
            }),
          ),
          Expanded(
            child: _buildSwitch('Shadow', _shadowEnabled, (v) {
              setState(() => _shadowEnabled = v);
            }),
          ),
          Expanded(
            child: _buildSwitch('Neon', _neonEnabled, (v) {
              setState(() => _neonEnabled = v);
            }),
          ),
          Expanded(
            child: _buildSwitch('Gradient', _gradientEnabled, (v) {
              setState(() => _gradientEnabled = v);
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildSwitch(String label, bool value, ValueChanged<bool> onChanged) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Switch(
          value: value,
          onChanged: onChanged,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _buildTrackSelector() {
    const types = [
      (TrackType.scroll, 'Scroll'),
      (TrackType.top, 'Top'),
      (TrackType.bottom, 'Bottom'),
      (TrackType.reverse, 'Reverse'),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: Colors.grey.shade200,
      child: Row(
        children:
            types.map((t) {
              final isSelected = _selectedTrackType == t.$1;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: ElevatedButton(
                    onPressed: () => setState(() => _selectedTrackType = t.$1),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          isSelected ? Colors.deepPurple : Colors.white,
                      foregroundColor:
                          isSelected ? Colors.white : Colors.black87,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      minimumSize: Size.zero,
                      textStyle: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    child: Text(t.$2),
                  ),
                ),
              );
            }).toList(),
      ),
    );
  }

  Widget _buildInputPanel() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _inputController,
              decoration: const InputDecoration(
                hintText: 'Enter barrage text...',
                hintStyle: TextStyle(fontSize: 13, color: Colors.grey),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (_) => _sendBarrage(),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _sendBarrage,
            icon: const Icon(Icons.send, size: 18),
            label: const Text('Send'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlPanel() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          IconButton(
            icon: const Icon(Icons.pause),
            onPressed: () {
              _controller.pause();
              setState(() {});
            },
          ),
          IconButton(
            icon: const Icon(Icons.play_arrow),
            onPressed: () {
              _controller.resume();
              setState(() {});
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            onPressed: () {
              _controller.clear();
              setState(() {});
            },
          ),
          _buildSpeedControl(),
          IconButton(
            icon: const Icon(Icons.replay),
            onPressed: () {
              _controller.seek(0);
              _pushInitialDemoBarrages();
              setState(() {});
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSpeedControl() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.remove, size: 18),
          onPressed: () {
            setState(() {
              _currentSpeed = (_currentSpeed - 0.25).clamp(0.25, 5.0);
              _controller.setSpeed(_currentSpeed);
            });
          },
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        ),
        Text(
          '${_currentSpeed.toStringAsFixed(2)}x',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
        IconButton(
          icon: const Icon(Icons.add, size: 18),
          onPressed: () {
            setState(() {
              _currentSpeed = (_currentSpeed + 0.25).clamp(0.25, 5.0);
              _controller.setSpeed(_currentSpeed);
            });
          },
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        ),
      ],
    );
  }
}
