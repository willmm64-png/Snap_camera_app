import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'camera_controller.dart';
import 'skin_smooth_shader.dart';

/// Widget that compiles the skin_smooth.frag fragment shader and applies
/// real-time skin smoothing to the camera feed through an ImageFilter
/// (hardware accelerated via Impeller on iOS).
class ShaderCameraPreview extends StatefulWidget {
  final SmoothCameraController cameraController;

  const ShaderCameraPreview({super.key, required this.cameraController});

  @override
  State<ShaderCameraPreview> createState() => _ShaderCameraPreviewState();
}

class _ShaderCameraPreviewState extends State<ShaderCameraPreview> {
  ui.FragmentShader? _shader;
  bool _isLoadingShader = true;

  @override
  void initState() {
    super.initState();
    _loadFragmentShader();
  }

  Future<void> _loadFragmentShader() async {
    try {
      final program = await SkinSmoothShader.load();
      if (mounted) {
        setState(() {
          _shader = program.fragmentShader();
          _isLoadingShader = false;
        });
      }
    } catch (e) {
      debugPrint('Failed to load fragment shader: $e');
      if (mounted) {
        setState(() {
          _isLoadingShader = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = widget.cameraController;

    if (!camera.isInitialized || camera.controller == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
      );
    }

    final controller = camera.controller!;
    final cameraAspect = controller.value.aspectRatio > 0
        ? controller.value.aspectRatio
        : (3.0 / 4.0);
    final rawPreview = ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: 1000.0,
          height: 1000.0 * cameraAspect,
          child: CameraPreview(controller),
        ),
      ),
    );

    // If the shader is still loading or errored, render the raw camera feed.
    if (_isLoadingShader || _shader == null) {
      return rawPreview;
    }

    if (!ui.ImageFilter.isShaderFilterSupported) {
      // No shader ImageFilter on this backend. A CustomPaint overlay is no
      // alternative: it has no access to the camera texture to sample from,
      // so smoothing is simply unavailable and the feed stays unfiltered.
      return rawPreview;
    }

    // Configure shader uniforms for real-time rendering. The parent rebuilds
    // on every camera controller change, so these stay in sync.
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);

        // Set uniforms:
        // Index 0 & 1: uResolution (viewport width and height)
        // Index 2: uIntensity, Index 3: uTan
        _shader!.setFloat(0, size.width);
        _shader!.setFloat(1, size.height);
        _shader!.setFloat(2, camera.smoothIntensity);
        _shader!.setFloat(3, camera.tanAmount);

        // Native GPU pipeline: apply FragmentShader as an ImageFilter to the
        // live CameraPreview.
        return ImageFiltered(
          imageFilter: ui.ImageFilter.shader(_shader!),
          child: rawPreview,
        );
      },
    );
  }
}
