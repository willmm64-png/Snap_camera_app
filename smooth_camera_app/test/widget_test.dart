import 'package:flutter_test/flutter_test.dart';
import 'package:smooth_camera_app/main.dart';

void main() {
  testWidgets('SmoothCameraApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const SmoothCameraApp());
    expect(find.byType(SmoothCameraApp), findsOneWidget);
  });
}
