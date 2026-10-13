import 'dart:ui' as ui;

/// Loads the skin smoothing shader once and shares it everywhere.
class SkinSmoothShader {
  SkinSmoothShader._();

  static final Future<ui.FragmentProgram> _program =
      ui.FragmentProgram.fromAsset('shaders/skin_smooth.frag');

  static Future<ui.FragmentProgram> load() => _program;

  /// Call at app start so the shader is ready before the camera opens.
  static void preload() {
    _program.ignore();
  }
}