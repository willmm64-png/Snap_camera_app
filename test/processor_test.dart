import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:smooth_camera_app/skin_smooth_processor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('SkinSmoothProcessor bypasses processing when intensity is zero', () async {
    final dummyBytes = Uint8List.fromList([1, 2, 3, 4, 5]);
    final result = await SkinSmoothProcessor.processImageBytes(
      rawBytes: dummyBytes,
      intensity: 0.0,
    );
    expect(result, equals(dummyBytes));
  });

  test('SkinSmoothProcessor gracefully falls back on invalid raw image bytes', () async {
    final dummyBytes = Uint8List.fromList([1, 2, 3, 4, 5]);
    final result = await SkinSmoothProcessor.processImageBytes(
      rawBytes: dummyBytes,
      intensity: 0.8,
    );
    expect(result, equals(dummyBytes));
  });
}
