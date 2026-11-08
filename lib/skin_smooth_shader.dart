import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

/// Loads the skin smoothing shader once and shares it everywhere.
class SkinSmoothShader {
  SkinSmoothShader._();

  static final Future<ui.FragmentProgram> _program =
      ui.FragmentProgram.fromAsset('shaders/skin_smooth.frag');

  static Future<ui.FragmentProgram> load() => _program;

  /// Call at app start so the shader is ready before the camera opens.
  /// Besides loading the program this also compiles its GPU pipeline with a
  /// throwaway draw: without that, the pipeline compiles on the first preview
  /// frame and hitches exactly when the camera feed appears.
  static void preload() {
    _warmUpPipeline().ignore();
  }

  /// Renders one tiny frame with the shader while the camera is still
  /// initializing. Failures are ignored: the worst case is the old behaviour
  /// (first frame pays the compile cost).
  static Future<void> _warmUpPipeline() async {
    try {
      final program = await _program;
      final shader = program.fragmentShader();

      // 1x1 white image as the texture sampler.
      final samplerRecorder = ui.PictureRecorder();
      ui.Canvas(
        samplerRecorder,
        const ui.Rect.fromLTWH(0, 0, 1, 1),
      ).drawPaint(ui.Paint()..color = const ui.Color(0xFFFFFFFF));
      final samplerImage = await samplerRecorder.endRecording().toImage(1, 1);

      shader.setFloat(0, 8.0); // uResolution.x
      shader.setFloat(1, 8.0); // uResolution.y
      shader.setFloat(2, 0.75); // uIntensity
      shader.setFloat(3, 0.5); // uTan
      shader.setImageSampler(0, samplerImage);

      final warmRecorder = ui.PictureRecorder();
      ui.Canvas(warmRecorder, const ui.Rect.fromLTWH(0, 0, 8, 8)).drawRect(
        const ui.Rect.fromLTWH(0, 0, 8, 8),
        ui.Paint()..shader = shader,
      );
      final warmImage = await warmRecorder.endRecording().toImage(8, 8);

      samplerImage.dispose();
      warmImage.dispose();
      shader.dispose();
    } catch (e) {
      debugPrint('SkinSmoothShader pipeline warm-up skipped: $e');
    }
  }
}
