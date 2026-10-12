import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';

/// Processor that applies the skin_smooth.frag fragment shader logic
/// to high-resolution photo byte arrays.
class SkinSmoothProcessor {
  const SkinSmoothProcessor._();

  /// Applies the skin_smooth.frag bilateral filter to the provided image bytes.
  /// If intensity <= 0.001, returns the original bytes untouched.
  /// If GPU shader rendering fails (e.g. headless test environment), falls back to rawBytes.
  static Future<Uint8List> processImageBytes({
    required Uint8List rawBytes,
    required double intensity,
    double tan = 0.35,
  }) async {
    final clampedIntensity = intensity.clamp(0.0, 1.0);
    final clampedTan = tan.clamp(0.0, 1.0);

    // Bypass processing if intensity is essentially zero
    if (clampedIntensity <= 0.001 && clampedTan <= 0.001) {
      return rawBytes;
    }

    try {
      // 1. Decode high-resolution image bytes into a GPU-backed ui.Image
      final ui.ImmutableBuffer buffer =
          await ui.ImmutableBuffer.fromUint8List(rawBytes);
      final ui.ImageDescriptor descriptor =
          await ui.ImageDescriptor.encoded(buffer);
      final ui.Codec codec = await descriptor.instantiateCodec();
      final ui.FrameInfo frameInfo = await codec.getNextFrame();
      final ui.Image sourceImage = frameInfo.image;

      final width = sourceImage.width.toDouble();
      final height = sourceImage.height.toDouble();

      // 2. Load and compile the skin_smooth.frag FragmentProgram
      final ui.FragmentProgram program = await ui.FragmentProgram.fromAsset(
        'shaders/skin_smooth.frag',
      );
      final ui.FragmentShader shader = program.fragmentShader();

      // 3. Set shader uniforms:
      // Index 0 & 1: uResolution (image width & height)
      // Index 2: uIntensity (filter blur intensity)
      // Sampler 0: uTexture (input high-res source image)
      shader.setFloat(0, width);
      shader.setFloat(1, height);
      shader.setFloat(2, clampedIntensity);
      shader.setFloat(3, clampedTan);
      shader.setImageSampler(0, sourceImage);

      // 4. Render to an offline canvas using PictureRecorder
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final ui.Canvas canvas = ui.Canvas(
        recorder,
        ui.Rect.fromLTWH(0, 0, width, height),
      );

      final ui.Paint paint = ui.Paint()..shader = shader;
      canvas.drawRect(ui.Rect.fromLTWH(0, 0, width, height), paint);

      final ui.Picture picture = recorder.endRecording();

      // 5. Rasterize picture to a processed ui.Image
      final ui.Image processedImage = await picture.toImage(
        sourceImage.width,
        sourceImage.height,
      );

      // 6. Encode filtered image to PNG byte array
      final ByteData? byteData = await processedImage.toByteData(
        format: ui.ImageByteFormat.png,
      );

      // Clean up GPU image resources
      sourceImage.dispose();
      processedImage.dispose();
      shader.dispose();

      if (byteData == null) {
        return rawBytes;
      }

      return byteData.buffer.asUint8List();
    } catch (e) {
      debugPrint('SkinSmoothProcessor shader filter fallback: $e');
      return rawBytes;
    }
  }
}
