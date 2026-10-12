import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'camera_controller.dart';
import 'shader_camera_preview.dart';

/// Minimal camera: full-screen preview, shutter, flash toggle, photos thumbnail.
/// Double-tap the preview to switch front/back camera.
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with SingleTickerProviderStateMixin {
  late final SmoothCameraController _cameraController;
  late final AnimationController _shutterAnimController;
  late final Animation<double> _shutterScaleAnimation;

  bool _isCapturing = false;
  bool _showShutterFlash = false;
  String? _statusBannerText;

  @override
  void initState() {
    super.initState();
    _cameraController = SmoothCameraController();
    _cameraController.requestPermissionsOnStartup();

    _shutterAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      reverseDuration: const Duration(milliseconds: 160),
    );
    _shutterScaleAnimation = Tween<double>(begin: 1.0, end: 0.88).animate(
      CurvedAnimation(parent: _shutterAnimController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _cameraController.dispose();
    _shutterAnimController.dispose();
    super.dispose();
  }

  Future<void> _handleShutterPress() async {
    if (_isCapturing || !_cameraController.isInitialized) return;

    // Front camera has no hardware flash: hold a white screen to light the face.
    final useScreenFlash =
        _cameraController.flashOn && _cameraController.isFrontCamera;

    setState(() {
      _isCapturing = true;
      _showShutterFlash = true;
    });
    HapticFeedback.mediumImpact();

    await Future.delayed(Duration(milliseconds: useScreenFlash ? 300 : 90));
    if (!useScreenFlash && mounted) {
      setState(() => _showShutterFlash = false);
    }

    try {
      await _cameraController.captureProcessAndSaveToGallery();
      _showBanner('Saved to Photos');
    } catch (e) {
      _showBanner('Capture failed: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() {
          _isCapturing = false;
          _showShutterFlash = false;
        });
      }
    }
  }

  void _showBanner(String message) {
    if (!mounted) return;
    setState(() => _statusBannerText = message);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && _statusBannerText == message) {
        setState(() => _statusBannerText = null);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: ListenableBuilder(
          listenable: _cameraController,
          builder: (context, _) {
            if (_cameraController.errorMessage != null) {
              return _buildErrorState(_cameraController.errorMessage!);
            }
            return SafeArea(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Column(
                    children: [
                      Expanded(child: _buildViewfinder()),
                      _buildBottomBar(),
                    ],
                  ),
                  if (_showShutterFlash)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Container(color: Colors.white),
                      ),
                    ),
                  if (_statusBannerText != null)
                    Positioned(
                      top: 24,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _statusBannerText!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// Full-size preview. Double-tap switches front/back camera.
  Widget _buildViewfinder() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onDoubleTap: () {
        HapticFeedback.mediumImpact();
        _cameraController.toggleCameraLens();
      },
      child: ShaderCameraPreview(cameraController: _cameraController),
    );
  }

  /// [Photos thumbnail] [Shutter] [Flash toggle]
  Widget _buildBottomBar() {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildCameraRollThumbnail(),
          _buildShutterButton(),
          _buildFlashButton(),
        ],
      ),
    );
  }

  Widget _buildCameraRollThumbnail() {
    final thumbnail = _cameraController.lastThumbnailBytes;
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        Gal.open();
      },
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.35),
            width: 1.0,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: thumbnail != null
            ? Image.memory(thumbnail, fit: BoxFit.cover)
            : const Icon(
                Icons.photo_library_outlined,
                color: Colors.white70,
                size: 22,
              ),
      ),
    );
  }

  Widget _buildShutterButton() {
    return GestureDetector(
      onTapDown: (_) => _shutterAnimController.forward(),
      onTapUp: (_) {
        _shutterAnimController.reverse();
        _handleShutterPress();
      },
      onTapCancel: () => _shutterAnimController.reverse(),
      child: ScaleTransition(
        scale: _shutterScaleAnimation,
        child: Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3.5),
          ),
          alignment: Alignment.center,
          child: Container(
            width: 66,
            height: 66,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFlashButton() {
    final on = _cameraController.flashOn;
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        _cameraController.toggleFlash();
      },
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E),
          shape: BoxShape.circle,
          border: Border.all(
            color: on
                ? const Color(0xFFFFCC00)
                : Colors.white.withValues(alpha: 0.25),
            width: 1.0,
          ),
        ),
        alignment: Alignment.center,
        child: Icon(
          on ? Icons.flash_on_rounded : Icons.flash_off_rounded,
          color: on ? const Color(0xFFFFCC00) : Colors.white,
          size: 22,
        ),
      ),
    );
  }

  Widget _buildErrorState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_off_rounded,
                color: Colors.white54, size: 56),
            const SizedBox(height: 16),
            const Text(
              'Camera Unavailable',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60, fontSize: 14),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => _cameraController.requestPermissionsOnStartup(),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
