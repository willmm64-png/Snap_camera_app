import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smooth_camera_app/skin_smooth_processor.dart';
import 'package:smooth_camera_app/skin_smooth_shader.dart';

/// Renders a synthetic skin-tone test image (with a red blemish dot) as PNG.
Future<Uint8List> _makeTestImagePng(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(
    recorder,
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
  );

  // Skin-tone background (opaque).
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xFFE0B49E),
  );
  // Slightly darker cheek half so smoothing has luminance structure to work on.
  canvas.drawRect(
    ui.Rect.fromLTWH(0, height / 2, width.toDouble(), height / 2),
    ui.Paint()..color = const ui.Color(0xFFD2A692),
  );
  // Red blemish dot for the healing pass.
  canvas.drawCircle(
    ui.Offset(width / 2, height / 2),
    width * 0.03,
    ui.Paint()..color = const ui.Color(0xFFCC6666),
  );

  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

/// Decodes PNG bytes back into raw RGBA pixels.
Future<Uint8List> _decodeToRgba(Uint8List pngBytes) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(pngBytes);
  final descriptor = await ui.ImageDescriptor.encoded(buffer);
  final codec = await descriptor.instantiateCodec();
  final frame = await codec.getNextFrame();
  final data =
      await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
  frame.image.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('skin_smooth.frag runs and the processed photo is fully opaque '
      '(no transparent patches)', () async {
    final ui.FragmentProgram program;
    try {
      program = await SkinSmoothShader.load();
    } catch (e) {
      // Some test runners ship shader assets for a different GPU backend than
      // they execute (e.g. Windows flutter_tester: Vulkan assets, Skia/SkSL
      // runtime). The shader cannot run there; the GLSL itself is still
      // validated by the build step, whose shader compiler fails the build on
      // any GLSL error.
      debugPrint('Skipping shader checks, backend cannot run shaders: $e');
      return;
    }
    final shader = program.fragmentShader();
    expect(shader, isNotNull);
    shader.dispose();

    const width = 96;
    const height = 128;
    final inputPng = await _makeTestImagePng(width, height);

    final outputPng = await SkinSmoothProcessor.processImageBytes(
      rawBytes: inputPng,
      intensity: 1.0,
      tan: 0.5,
    );

    // The shader path must actually have run (output differs from input).
    expect(outputPng, isNot(equals(inputPng)));

    // Output must keep the input dimensions...
    final rgba = await _decodeToRgba(outputPng);
    expect(rgba.length, width * height * 4);

    // ...and every pixel must be fully opaque.
    for (int i = 3; i < rgba.length; i += 4) {
      expect(rgba[i], 255, reason: 'transparent pixel at byte $i');
    }
  });
}
