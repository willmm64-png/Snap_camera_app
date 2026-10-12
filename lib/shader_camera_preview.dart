import 'dart:async';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'camera_controller.dart';

/// CustomPainter that renders with the compiled skin_smooth.frag FragmentShader
/// using live camera texture coordinates and intensity configurations.
class SkinSmoothCustomPainter extends CustomPainter {
  final ui.FragmentShader? shader;
  final CameraTextureCoordinates? coordinates;
  final double intensity;
  final double tan;

  SkinSmoothCustomPainter({
    required this.shader,
    required this.coordinates,
    required this.intensity,
    required this.tan,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (shader == null || size.isEmpty) return;

    // Uniform 0 & 1: uResolution (viewport width and height in logical pixels)
    shader!.setFloat(0, size.width);
    shader!.setFloat(1, size.height);

    // Uniform 2: uIntensity (filter blur intensity [0.0 .. 1.0])
    shader!.setFloat(2, intensity);
    shader!.setFloat(3, tan);

    // Create a paint with the fragment shader or shader filter
    final paint = Paint()..shader = shader;

    // Draw viewport bounds
    final rect = Offset.zero & size;
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(covariant SkinSmoothCustomPainter oldDelegate) {
    return oldDelegate.shader != shader ||
        oldDelegate.intensity != intensity ||
        oldDelegate.tan != tan ||
        oldDelegate.coordinates?.timestamp != coordinates?.timestamp;
  }
}

/// Widget that compiles the skin_smooth.frag fragment shader,
/// subscribes to the camera texture coordinate stream, and applies
/// real-time skin smoothing to the front camera feed.
class ShaderCameraPreview extends StatefulWidget {
  final SmoothCameraController cameraController;

  const ShaderCameraPreview({super.key, required this.cameraController});

  @override
  State<ShaderCameraPreview> createState() => _ShaderCameraPreviewState();
}

class _ShaderCameraPreviewState extends State<ShaderCameraPreview> {
  ui.FragmentShader? _shader;
  bool _isLoadingShader = true;

  StreamSubscription<CameraTextureCoordinates>? _coordsSubscription;
  CameraTextureCoordinates? _latestCoordinates;

  @override
  void initState() {
    super.initState();
    _loadFragmentShader();
    _subscribeToTextureStream();
  }

  @override
  void didUpdateWidget(covariant ShaderCameraPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cameraController != widget.cameraController) {
      _coordsSubscription?.cancel();
      _subscribeToTextureStream();
    }
  }

  void _subscribeToTextureStream() {
    _coordsSubscription = widget.cameraController.textureCoordinatesStream
        .listen((coords) {
          if (mounted) {
            setState(() {
              _latestCoordinates = coords;
            });
          }
        });
  }

  Future<void> _loadFragmentShader() async {
    try {
      final program = await ui.FragmentProgram.fromAsset(
        'shaders/skin_smooth.frag',
      );
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
    _coordsSubscription?.cancel();
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

    // If shader is still loading or errored, render raw camera feed
    if (_isLoadingShader || _shader == null) {
      return rawPreview;
    }

    // Configure shader uniforms for real-time rendering
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final intensity = camera.smoothIntensity;

        // Set uniforms:
        // Index 0: uResolution.x
        // Index 1: uResolution.y
        // Index 2: uIntensity
        _shader!.setFloat(0, size.width);
        _shader!.setFloat(1, size.height);
        _shader!.setFloat(2, intensity);
        _shader!.setFloat(3, camera.tanAmount);

        // Check for Impeller ImageFilter shader support (default on iOS)
        final isFilterSupported = ui.ImageFilter.isShaderFilterSupported;

        if (isFilterSupported) {
          // Native GPU pipeline: apply FragmentShader as an ImageFilter to live CameraPreview
          return ImageFiltered(
            imageFilter: ui.ImageFilter.shader(_shader!),
            child: rawPreview,
          );
        } else {
          // Fallback on platforms without Impeller ImageFilter support:
          // Overlay custom painter with live piped coordinates
          return Stack(
            fit: StackFit.expand,
            children: [
              rawPreview,
              CustomPaint(
                painter: SkinSmoothCustomPainter(
                  shader: _shader,
                  coordinates: _latestCoordinates,
                  intensity: intensity,
                  tan: camera.tanAmount,
                ),
              ),
            ],
          );
        }
      },
    );
  }
}
