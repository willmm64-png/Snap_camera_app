import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:gal/gal.dart';
import 'skin_smooth_processor.dart';

/// Represents live camera texture metadata and coordinates piped to shaders and custom painters.
class CameraTextureCoordinates {
  final double previewWidth;
  final double previewHeight;
  final double aspectRatio;
  final int sensorOrientation;
  final CameraLensDirection lensDirection;
  final DateTime timestamp;

  const CameraTextureCoordinates({
    required this.previewWidth,
    required this.previewHeight,
    required this.aspectRatio,
    required this.sensorOrientation,
    required this.lensDirection,
    required this.timestamp,
  });

  @override
  String toString() =>
      'CameraTextureCoordinates(w: $previewWidth, h: $previewHeight, aspect: $aspectRatio, sensor: $sensorOrientation)';
}

/// Controller responsible for managing the front-facing iPhone camera,
/// piping live coordinates and frames to custom shaders, and handling captures.
class SmoothCameraController extends ChangeNotifier {
  CameraController? _controller;
  List<CameraDescription> _availableCameras = [];
  CameraDescription? _frontCamera;
  bool _isInitializing = false;
  bool _isSwitchingLens = false;
  String? _errorMessage;

  // Stream piping live camera coordinate updates into custom painter / FragmentShader
  final StreamController<CameraTextureCoordinates> _textureCoordinatesController =
      StreamController<CameraTextureCoordinates>.broadcast();

  // Smoothing filter intensity uniform: [0.0 (off) .. 1.0 (maximum)]
  double _smoothIntensity = 0.75;
  final double _tanAmount = 0.35;

  // Zoom control
  double _currentZoom = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 5.0;

  // Flash mode
  FlashMode _flashMode = FlashMode.off;

  // Format mode: e.g. HEIF 24, RAW 48, JPEG
  String _formatMode = 'HEIF\n24';

  // Grid line overlay
  bool _showGrid = true;

  // Selected camera mode
  String _selectedMode = 'PHOTO';

  // Aspect ratio mode: defaults to 19:9
  String _aspectRatioMode = '19:9';

  // Last captured photo thumbnail bytes
  Uint8List? _lastThumbnailBytes;

  CameraController? get controller => _controller;
  bool get isInitialized => _controller != null && _controller!.value.isInitialized;
  bool get isInitializing => _isInitializing;
  String? get errorMessage => _errorMessage;
  double get smoothIntensity => _smoothIntensity;
  double get tanAmount => _tanAmount;
  CameraDescription? get currentCamera => _frontCamera;
  double get currentZoom => _currentZoom;
  double get minZoom => _minZoom;
  double get maxZoom => _maxZoom;
  FlashMode get flashMode => _flashMode;
  String get formatMode => _formatMode;
  bool get showGrid => _showGrid;
  bool get flashOn => _flashMode != FlashMode.off;
  bool get isFrontCamera =>
      _frontCamera?.lensDirection == CameraLensDirection.front;
  String get selectedMode => _selectedMode;
  String get aspectRatioMode => _aspectRatioMode;
  Uint8List? get lastThumbnailBytes => _lastThumbnailBytes;

  /// Viewport aspect ratio (width / height) based on current mode
  double get currentAspectRatio {
    switch (_aspectRatioMode) {
      case '19:9':
        return 9.0 / 19.0;
      case '16:9':
        return 9.0 / 16.0;
      case '1:1':
        return 1.0;
      case '4:3':
      default:
        return 3.0 / 4.0;
    }
  }

  /// Toggle aspect ratio between 19:9, 4:3, 1:1, 16:9
  void toggleAspectRatio() {
    switch (_aspectRatioMode) {
      case '19:9':
        _aspectRatioMode = '4:3';
        break;
      case '4:3':
        _aspectRatioMode = '1:1';
        break;
      case '1:1':
        _aspectRatioMode = '16:9';
        break;
      default:
        _aspectRatioMode = '19:9';
        break;
    }
    notifyListeners();
  }

  /// Explicitly set aspect ratio
  void setAspectRatio(String ratio) {
    if (_aspectRatioMode != ratio) {
      _aspectRatioMode = ratio;
      notifyListeners();
    }
  }

  /// Stream of texture coordinates piped on camera value changes and preview updates
  Stream<CameraTextureCoordinates> get textureCoordinatesStream =>
      _textureCoordinatesController.stream;

  /// Update blur intensity and notify listeners
  void setSmoothIntensity(double value) {
    final clamped = value.clamp(0.0, 1.0);
    if (_smoothIntensity != clamped) {
      _smoothIntensity = clamped;
      notifyListeners();
    }
  }

  /// Toggle grid line overlay
  void toggleGrid() {
    _showGrid = !_showGrid;
    notifyListeners();
  }

  /// Set camera mode (e.g. VIDEO, PHOTO, PORTRAIT)
  void setMode(String mode) {
    if (_selectedMode != mode) {
      _selectedMode = mode;
      notifyListeners();
    }
  }

  /// Toggle format indicator between HEIF 24, RAW 48, etc.
  void toggleFormat() {
    if (_formatMode.startsWith('HEIF')) {
      _formatMode = 'RAW\n48';
    } else {
      _formatMode = 'HEIF\n24';
    }
    notifyListeners();
  }

  /// Flash is simply off or on (always).
  Future<void> toggleFlash() async {
    if (!isInitialized || _controller == null) return;
    _flashMode =
        _flashMode == FlashMode.off ? FlashMode.always : FlashMode.off;
    await _applyFlashMode();
    notifyListeners();
  }

  /// Front camera has no hardware flash on iPhone, so skip it there
  /// (the UI uses a white screen flash instead).
  Future<void> _applyFlashMode() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (isFrontCamera) return;
    try {
      await _controller!.setFlashMode(_flashMode);
    } catch (e) {
      debugPrint('Failed to set flash mode: $e');
    }
  }

  /// Set camera zoom level
  Future<void> setZoom(double zoom) async {
    if (!isInitialized || _controller == null) return;
    try {
      final target = zoom.clamp(_minZoom, _maxZoom);
      await _controller!.setZoomLevel(target);
      _currentZoom = target;
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to set zoom level: $e');
    }
  }

  /// Request both camera and iOS Photos library permissions on startup
  Future<void> requestPermissionsOnStartup() async {
    // 2. Initialize camera (prompts for camera permission on iOS)
    await initializeCamera();

    try {
      // 1. Request Photos library access on startup
      final hasPhotosAccess = await Gal.hasAccess();
      if (!hasPhotosAccess) {
        await Gal.requestAccess();
      }
    } catch (e) {
      debugPrint('Photos permission startup request: $e');
    }
  }

  /// Initialize the front-facing camera (with automatic fallback if front camera is not present)
  Future<void> initializeCamera() async {
    if (_isInitializing) return;

    _isInitializing = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _availableCameras = await availableCameras();
      if (_availableCameras.isEmpty) {
        throw CameraException(
          'noCameras',
          'No cameras available on this device.',
        );
      }

      // Prioritize front-facing camera for iPhone selfie / skin smooth preview
      _frontCamera = _availableCameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => _availableCameras.first,
      );

      final controller = CameraController(
        _frontCamera!,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.bgra8888,
      );

      _controller = controller;

      await controller.initialize();

      _minZoom = 1.0;
      _maxZoom = 5.0;
      _currentZoom = 1.0;

      // Listen for camera orientation, preview size, and stream changes
      controller.addListener(_onCameraControllerUpdate);

      // Emit initial coordinate state
      _emitCurrentTextureCoordinates();

      await _applyFlashMode();

      _isInitializing = false;
      notifyListeners();
    } catch (e) {
      _isInitializing = false;
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  /// Listener invoked whenever the camera controller updates its state
  void _onCameraControllerUpdate() {
    if (!isInitialized) return;
    _emitCurrentTextureCoordinates();
    notifyListeners();
  }

  /// Pipe current camera texture dimensions and metadata down the stream
  void _emitCurrentTextureCoordinates() {
    if (!isInitialized || _controller == null) return;

    final previewSize = _controller!.value.previewSize;
    final width = previewSize?.width ?? 1080.0;
    final height = previewSize?.height ?? 1920.0;
    final aspect = _controller!.value.aspectRatio;

    final coords = CameraTextureCoordinates(
      previewWidth: width,
      previewHeight: height,
      aspectRatio: aspect,
      sensorOrientation: _frontCamera?.sensorOrientation ?? 0,
      lensDirection: _frontCamera?.lensDirection ?? CameraLensDirection.front,
      timestamp: DateTime.now(),
    );

    if (!_textureCoordinatesController.isClosed) {
      _textureCoordinatesController.add(coords);
    }
  }

  /// Switch between front and back camera lenses
  Future<void> toggleCameraLens() async {
    if (_isSwitchingLens || _isInitializing) return;
    if (_availableCameras.length < 2 || _controller == null) return;
    _isSwitchingLens = true;
    try {
      final newDirection =
          _frontCamera?.lensDirection == CameraLensDirection.front
              ? CameraLensDirection.back
              : CameraLensDirection.front;
      final nextCamera = _availableCameras.firstWhere(
        (cam) => cam.lensDirection == newDirection,
        orElse: () => _availableCameras.first,
      );

      // Detach the old controller from the UI BEFORE disposing it.
      final oldController = _controller;
      _controller = null;
      notifyListeners();
      oldController?.removeListener(_onCameraControllerUpdate);
      await oldController?.dispose();

      _frontCamera = nextCamera;
      final newController = CameraController(
        nextCamera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.bgra8888,
      );
      _controller = newController;
      await newController.initialize();
      newController.addListener(_onCameraControllerUpdate);

      _minZoom = 1.0;
      _maxZoom = 5.0;
      _currentZoom = 1.0;

      await _applyFlashMode();
      _emitCurrentTextureCoordinates();
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isSwitchingLens = false;
      notifyListeners();
    }
  }

  /// Capture a high-resolution photo from the camera, apply the skin_smooth.frag
  /// bilateral filter to the final captured byte array, and save to the iOS Photos library.
  Future<Uint8List> captureProcessAndSaveToGallery() async {
    if (!isInitialized || _controller == null) {
      throw StateError('Camera is not initialized.');
    }

    if (_controller!.value.isTakingPicture) {
      throw StateError('A picture capture is already in progress.');
    }

    // 1. Capture high-resolution photo from the camera
    final XFile photoFile = await _controller!.takePicture();
    final Uint8List rawBytes = await photoFile.readAsBytes();

    // 2. Apply skin_smooth.frag shader filter to the captured photo byte array
    final Uint8List processedBytes = await SkinSmoothProcessor.processImageBytes(
      rawBytes: rawBytes,
      intensity: _smoothIntensity,
      tan: _tanAmount,
    );

    // 3. Ensure iOS Photos library access permissions
    final hasAccess = await Gal.hasAccess();
    if (!hasAccess) {
      final granted = await Gal.requestAccess();
      if (!granted) {
        throw Exception('Access to iOS Photos library was denied.');
      }
    }

    // 4. Save processed image cleanly to iOS Camera Roll / Photos App using gal
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    await Gal.putImageBytes(
      processedBytes,
      name: 'smooth_snap_$timestamp',
    );

    // 5. Store last thumbnail for the camera roll preview button
    _lastThumbnailBytes = processedBytes;
    notifyListeners();

    return processedBytes;
  }

  @override
  void dispose() {
    _controller?.removeListener(_onCameraControllerUpdate);
    _controller?.dispose();
    _textureCoordinatesController.close();
    super.dispose();
  }
}
