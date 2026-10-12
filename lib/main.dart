import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'camera_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock status bar overlay to light content for dark camera viewfinder
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ),
  );

  runApp(const SmoothCameraApp());
}

class SmoothCameraApp extends StatelessWidget {
  const SmoothCameraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smooth Camera',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFFCC00),
          surface: Colors.black,
        ),
        useMaterial3: true,
      ),
      home: const CameraScreen(),
    );
  }
}
