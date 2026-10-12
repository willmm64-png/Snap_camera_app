import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'camera_controller.dart';
import 'shader_camera_preview.dart';

/// Pixel-perfect replica of the Apple iOS Camera app user interface.
/// Features top status bar, 4:3 viewfinder with grid & zoom selectors,
/// horizontal mode selector strip, bottom controls with camera roll preview,
/// solid white circular shutter button, and sliding controls drawer.
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with TickerProviderStateMixin {
  late final SmoothCameraController _cameraController;

  // Shutter button spring animation
  late final AnimationController _shutterAnimController;
  late final Animation<double> _shutterScaleAnimation;

  // Controls drawer slide animation
  late final AnimationController _drawerAnimController;
  late final Animation<double> _drawerSlideAnimation;

  bool _isCapturing = false;
  bool _showShutterFlash = false;
  bool _isDrawerOpen = false;
  bool _showSmoothSlider = false;
  String? _statusBannerText;

  // List of iOS camera modes
  final List<String> _cameraModes = const [
    'TIME-LAPSE',
    'SLO-MO',
    'CINEMATIC',
    'VIDEO',
    'PHOTO',
    'PORTRAIT',
    'PANO',
  ];

  late final ScrollController _modeScrollController;

  @override
  void initState() {
    super.initState();
    _cameraController = SmoothCameraController();
    _cameraController.requestPermissionsOnStartup();

    _modeScrollController = ScrollController();

    // Shutter animation
    _shutterAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      reverseDuration: const Duration(milliseconds: 160),
    );

    _shutterScaleAnimation = Tween<double>(begin: 1.0, end: 0.88).animate(
      CurvedAnimation(
        parent: _shutterAnimController,
        curve: Curves.easeInOut,
      ),
    );

    // Controls drawer animation
    _drawerAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );

    _drawerSlideAnimation = CurvedAnimation(
      parent: _drawerAnimController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    // Initial scroll position to center 'PHOTO'
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToMode('PHOTO', animate: false);
    });
  }

  @override
  void dispose() {
    _cameraController.dispose();
    _shutterAnimController.dispose();
    _drawerAnimController.dispose();
    _modeScrollController.dispose();
    super.dispose();
  }

  void _scrollToMode(String mode, {bool animate = true}) {
    final index = _cameraModes.indexOf(mode);
    if (index == -1 || !_modeScrollController.hasClients) return;

    // Center the item horizontally (each item approximately 76px width)
    const itemWidth = 76.0;
    final screenWidth = MediaQuery.of(context).size.width;
    final targetOffset =
        (index * itemWidth) - (screenWidth / 2) + (itemWidth / 2) + 24;

    final clampedOffset = targetOffset.clamp(
      0.0,
      _modeScrollController.position.maxScrollExtent,
    );

    if (animate) {
      _modeScrollController.animateTo(
        clampedOffset,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    } else {
      _modeScrollController.jumpTo(clampedOffset);
    }
  }

  void _toggleDrawer() {
    HapticFeedback.lightImpact();
    setState(() {
      _isDrawerOpen = !_isDrawerOpen;
      if (_isDrawerOpen) {
        _drawerAnimController.forward();
      } else {
        _drawerAnimController.reverse();
      }
    });
  }

  Future<void> _handleShutterPress() async {
    if (_isCapturing || !_cameraController.isInitialized) return;

    setState(() {
      _isCapturing = true;
      _showShutterFlash = true;
    });

    HapticFeedback.mediumImpact();

    await Future.delayed(const Duration(milliseconds: 90));
    if (mounted) {
      setState(() {
        _showShutterFlash = false;
      });
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
        });
      }
    }
  }

  void _showBanner(String message) {
    if (!mounted) return;
    setState(() {
      _statusBannerText = message;
    });
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && _statusBannerText == message) {
        setState(() {
          _statusBannerText = null;
        });
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
              top: false,
              bottom: true,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Main vertical layout
                  Column(
                    children: [
                      // 1. Top Bar Container (Solid Pitch-Black)
                      _buildTopBar(),

                      // 2. Viewfinder Container (4:3 Aspect Ratio)
                      Expanded(
                        child: Center(
                          child: _buildViewfinderSection(),
                        ),
                      ),

                      // 3. Bottom Controls Container (Solid Pitch-Black)
                      _buildBottomContainer(),
                    ],
                  ),

                  // Shutter Flash Overlay
                  if (_showShutterFlash)
                    Positioned.fill(
                      child: Container(
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),

                  // Status Toast Banner (e.g. "Saved to Photos")
                  if (_statusBannerText != null)
                    Positioned(
                      top: 110,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.15),
                              width: 0.5,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.check_circle_rounded,
                                color: Color(0xFF34C759),
                                size: 15,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _statusBannerText!,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
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

  // =========================================================================
  // 1. TOP BAR: Status indicators (HEIF/RAW, Flash, Exposure/Live, Night Mode)
  // =========================================================================
  Widget _buildTopBar() {
    return Container(
      color: Colors.black,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8,
        bottom: 8,
        left: 20,
        right: 20,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // HEIF / RAW format indicator
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              _cameraController.toggleFormat();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.2),
                  width: 0.5,
                ),
              ),
              child: Text(
                _cameraController.formatMode,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  height: 1.1,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),

          // Central top indicators & chevron drawer toggle
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Flash indicator
              GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  _cameraController.toggleFlash();
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Icon(
                    _cameraController.flashMode == FlashMode.off
                        ? Icons.flash_off_rounded
                        : Icons.flash_on_rounded,
                    color: _cameraController.flashMode != FlashMode.off
                        ? const Color(0xFFFFCC00)
                        : Colors.white,
                    size: 20,
                  ),
                ),
              ),

              // Exposure / Live indicator (concentric circles)
              GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  _toggleDrawer();
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Icon(
                    Icons.motion_photos_on_rounded,
                    color: Colors.white.withValues(alpha: 0.9),
                    size: 20,
                  ),
                ),
              ),

              // Night Mode indicator (crescent moon with stars)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Icon(
                  Icons.nightlight_round,
                  color: Colors.white.withValues(alpha: 0.9),
                  size: 19,
                ),
              ),

              // Chevron drawer toggle
              GestureDetector(
                onTap: _toggleDrawer,
                child: Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: AnimatedRotation(
                    turns: _isDrawerOpen ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(
                      Icons.keyboard_arrow_up_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ],
          ),

          // Empty spacer to balance HEIF button on left
          const SizedBox(width: 44),
        ],
      ),
    );
  }

  // =========================================================================
  // 2. VIEWFINDER: 19:9 live viewport, grid overlay, zoom selectors & drawer
  // =========================================================================
  Widget _buildViewfinderSection() {
    return AspectRatio(
      aspectRatio: _cameraController.currentAspectRatio,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Live Camera Preview with FragmentShader Skin Smooth pipeline
          ShaderCameraPreview(
            cameraController: _cameraController,
          ),

          // Rule-of-thirds Grid Overlay
          if (_cameraController.showGrid) _buildGridOverlay(),

          // Minimal Circular Zoom Selectors sitting on bottom of viewport
          Positioned(
            left: 0,
            right: 0,
            bottom: 14,
            child: _buildZoomControls(),
          ),

          // Sliding Camera Controls Drawer (matching right image)
          if (_isDrawerOpen)
            SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 1),
                end: Offset.zero,
              ).animate(_drawerSlideAnimation),
              child: _buildControlsDrawer(),
            ),

          // Skin smooth intensity slider (if toggled via depth/f button)
          if (_showSmoothSlider)
            Positioned(
              left: 20,
              right: 20,
              bottom: 64,
              child: _buildSmoothSliderOverlay(),
            ),
        ],
      ),
    );
  }

  /// 3x3 Rule-of-thirds grid lines
  Widget _buildGridOverlay() {
    return IgnorePointer(
      child: CustomPaint(
        painter: _CameraGridPainter(),
      ),
    );
  }

  /// 4. ZOOM CONTROLS: Minimal circular zoom selectors (.5, 1, 2x, 5)
  Widget _buildZoomControls() {
    final currentZoom = _cameraController.currentZoom;

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildZoomButton(label: '.5', targetZoom: 0.5, currentZoom: currentZoom),
            const SizedBox(width: 8),
            _buildZoomButton(label: '1', targetZoom: 1.0, currentZoom: currentZoom),
            const SizedBox(width: 8),
            _buildZoomButton(label: '2x', targetZoom: 2.0, currentZoom: currentZoom),
            const SizedBox(width: 8),
            _buildZoomButton(label: '5', targetZoom: 5.0, currentZoom: currentZoom),
          ],
        ),
      ),
    );
  }

  Widget _buildZoomButton({
    required String label,
    required double targetZoom,
    required double currentZoom,
  }) {
    // Check if this zoom level is currently selected
    final isSelected = (currentZoom - targetZoom).abs() < 0.35;

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        _cameraController.setZoom(targetZoom);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.black.withValues(alpha: 0.6)
              : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? const Color(0xFFFFCC00) : Colors.white,
            fontSize: isSelected ? 12 : 11,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  // =========================================================================
  // 3. BOTTOM CONTAINER: Mode selector, Camera roll, Shutter & Flip
  // =========================================================================
  Widget _buildBottomContainer() {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.only(top: 10, bottom: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Mode Selector Strip right above shutter button
          _buildModeSelector(),

          const SizedBox(height: 18),

          // Bottom Controls Row: [Thumbnail (left) | Shutter (center) | Flip (right)]
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Left: Camera Roll Preview Thumbnail & Filter toggle
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildCameraRollThumbnail(),
                    const SizedBox(width: 14),
                    _buildDepthFilterButton(),
                  ],
                ),

                // Center: Solid White Circular Shutter Button
                _buildShutterButton(),

                // Right: Styles toggle & Camera Flip Button
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildStylesGridButton(),
                    const SizedBox(width: 14),
                    _buildCameraFlipButton(),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 3. MODE SELECTOR: Horizontal text scrolling mode strip (VIDEO, PHOTO, etc.)
  Widget _buildModeSelector() {
    final currentMode = _cameraController.selectedMode;

    return SizedBox(
      height: 32,
      child: ListView.builder(
        controller: _modeScrollController,
        scrollDirection: Axis.horizontal,
        itemCount: _cameraModes.length,
        itemBuilder: (context, index) {
          final mode = _cameraModes[index];
          final isSelected = mode == currentMode;

          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              _cameraController.setMode(mode);
              _scrollToMode(mode);
            },
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.black.withValues(alpha: 0.5)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  mode,
                  style: TextStyle(
                    color: isSelected
                        ? const Color(0xFFFFCC00)
                        : Colors.white.withValues(alpha: 0.45),
                    fontSize: 12.5,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Left: Camera roll preview thumbnail
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
            ? Image.memory(
                thumbnail,
                fit: BoxFit.cover,
              )
            : const Icon(
                Icons.photo_library_outlined,
                color: Colors.white70,
                size: 22,
              ),
      ),
    );
  }

  /// 'f' (aperture/depth/skin smooth filter toggle button)
  Widget _buildDepthFilterButton() {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() {
          _showSmoothSlider = !_showSmoothSlider;
        });
      },
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _showSmoothSlider
              ? const Color(0xFFFFCC00).withValues(alpha: 0.25)
              : const Color(0xFF1C1C1E),
          border: Border.all(
            color: _showSmoothSlider
                ? const Color(0xFFFFCC00)
                : Colors.white.withValues(alpha: 0.2),
            width: 1.0,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          'f',
          style: TextStyle(
            color: _showSmoothSlider ? const Color(0xFFFFCC00) : Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w700,
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
    );
  }

  /// Center: Solid white circular shutter button with outer ring
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
            border: Border.all(
              color: Colors.white,
              width: 3.5,
            ),
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

  /// ':::' styles drawer button
  Widget _buildStylesGridButton() {
    return GestureDetector(
      onTap: _toggleDrawer,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF1C1C1E),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.2),
            width: 1.0,
          ),
        ),
        alignment: Alignment.center,
        child: const Icon(
          Icons.apps_rounded,
          color: Colors.white,
          size: 18,
        ),
      ),
    );
  }

  /// Right: Camera flip button
  Widget _buildCameraFlipButton() {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        _cameraController.toggleCameraLens();
      },
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E),
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.25),
            width: 1.0,
          ),
        ),
        alignment: Alignment.center,
        child: const Icon(
          Icons.flip_camera_ios_rounded,
          color: Colors.white,
          size: 22,
        ),
      ),
    );
  }

  // =========================================================================
  // SLIDING CAMERA CONTROLS DRAWER (Replicating Right Image)
  // =========================================================================
  Widget _buildControlsDrawer() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.65),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top drag pill handle
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 14),

                // 3x4 Controls Grid
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildDrawerItem(
                      icon: Icons.flash_auto_rounded,
                      label: 'FLASH',
                      onTap: () => _cameraController.toggleFlash(),
                    ),
                    _buildDrawerItem(
                      icon: Icons.auto_fix_high_rounded,
                      label: 'SMOOTH',
                      isActive: true,
                      onTap: () {
                        setState(() {
                          _showSmoothSlider = !_showSmoothSlider;
                        });
                      },
                    ),
                    _buildDrawerItem(
                      icon: Icons.motion_photos_on_rounded,
                      label: 'LIVE',
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildDrawerItem(
                      icon: Icons.timer_outlined,
                      label: 'TIMER',
                    ),
                    _buildDrawerItem(
                      icon: Icons.exposure_rounded,
                      label: 'EXPOSURE',
                    ),
                    _buildDrawerItem(
                      icon: Icons.grid_view_rounded,
                      label: 'STYLES',
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildDrawerItem(
                      icon: Icons.aspect_ratio_rounded,
                      label: _cameraController.aspectRatioMode,
                      isActive: true,
                      onTap: () => _cameraController.toggleAspectRatio(),
                    ),
                    _buildDrawerItem(
                      icon: Icons.nightlight_round,
                      label: 'NIGHT MODE',
                    ),
                    _buildDrawerItem(
                      icon: Icons.grid_on_rounded,
                      label: 'GRID',
                      isActive: _cameraController.showGrid,
                      onTap: () => _cameraController.toggleGrid(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDrawerItem({
    required IconData icon,
    required String label,
    bool isActive = false,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive
                  ? const Color(0xFFFFCC00).withValues(alpha: 0.25)
                  : const Color(0xFF2C2C2E).withValues(alpha: 0.8),
              border: Border.all(
                color: isActive
                    ? const Color(0xFFFFCC00)
                    : Colors.white.withValues(alpha: 0.15),
                width: 1.0,
              ),
            ),
            child: Icon(
              icon,
              color: isActive ? const Color(0xFFFFCC00) : Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              color: isActive
                  ? const Color(0xFFFFCC00)
                  : Colors.white.withValues(alpha: 0.85),
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }

  /// Skin smooth intensity slider popup
  Widget _buildSmoothSliderOverlay() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.2),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.auto_fix_high_rounded,
            color: Color(0xFFFFCC00),
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2.5,
                activeTrackColor: const Color(0xFFFFCC00),
                inactiveTrackColor: Colors.white24,
                thumbColor: Colors.white,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: SliderComponentShape.noOverlay,
              ),
              child: Slider(
                value: _cameraController.smoothIntensity,
                min: 0.0,
                max: 1.0,
                onChanged: (val) {
                  _cameraController.setSmoothIntensity(val);
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 36,
            child: Text(
              '${(_cameraController.smoothIntensity * 100).round()}%',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
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
            const Icon(
              Icons.videocam_off_rounded,
              color: Colors.white54,
              size: 56,
            ),
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
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 14,
              ),
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

/// Custom painter that draws subtle rule-of-thirds grid lines (2 vertical, 2 horizontal)
class _CameraGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.22)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    final oneThirdW = size.width / 3.0;
    final twoThirdsW = (size.width * 2.0) / 3.0;

    final oneThirdH = size.height / 3.0;
    final twoThirdsH = (size.height * 2.0) / 3.0;

    // Vertical lines
    canvas.drawLine(Offset(oneThirdW, 0), Offset(oneThirdW, size.height), paint);
    canvas.drawLine(Offset(twoThirdsW, 0), Offset(twoThirdsW, size.height), paint);

    // Horizontal lines
    canvas.drawLine(Offset(0, oneThirdH), Offset(size.width, oneThirdH), paint);
    canvas.drawLine(Offset(0, twoThirdsH), Offset(size.width, twoThirdsH), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
