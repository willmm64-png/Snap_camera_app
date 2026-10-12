# Smooth Camera App – GitHub Actions Build & Sideloading Guide

This guide outlines the project architecture and provides step-by-step instructions for using **GitHub Actions** to automatically build an unsigned iOS application bundle (`Payload/smooth_camera.app`) and package it into an `.ipa` file for installation on Windows via **Sideloadly**.

---

## 1. Project Architecture Overview

```
ios_snap_smoth_camera/
├── .github/
│   └── workflows/
│       └── build-ipa.yml               # GitHub Actions CI workflow script
├── BUILD_INSTRUCTIONS.md               # This build & deployment guide
└── smooth_camera_app/                  # Flutter application root
    ├── .github/workflows/build-ipa.yml # Local copy for subfolder repository root
    ├── pubspec.yaml                    # camera, gal & shaders/skin_smooth.frag
    ├── shaders/
    │   └── skin_smooth.frag            # Bilateral filter GLSL fragment shader
    ├── ios/
    │   └── Runner/
    │       └── Info.plist              # NSCamera & NSPhotoLibrary permissions
    ├── lib/
    │   ├── main.dart                   # Entry point, system overlays & dark camera theme
    │   ├── camera_controller.dart      # Camera lifecycle, stream coordinates, zoom, capture
    │   ├── shader_camera_preview.dart  # Real-time GPU shader preview & CustomPainter
    │   ├── skin_smooth_processor.dart  # Offline GPU bilateral filtering on captured bytes
    │   └── camera_screen.dart          # 19:9 iOS Camera UI (grid, zoom bar, shutter, drawer)
    └── test/
        ├── processor_test.dart         # Unit tests for image shader processing
        └── widget_test.dart            # Smoke tests for app bootstrap
```

### Core Components
* **Real-time Fragment Shader (`shaders/skin_smooth.frag`)**: GLSL 460 bilateral filter compiled into SPIR-V by Flutter's asset-based shader pipeline. Uses photometric Gaussian weighting to smooth skin tones while preserving sharp facial features (eyes, eyebrows, eyelashes, hair).
* **Live Camera Viewport (`lib/shader_camera_preview.dart`)**: Piped through `ui.ImageFilter.shader` using Flutter's Impeller GPU backend on iOS for hardware-accelerated 60/120 FPS rendering.
* **High-Resolution Filter Processing (`lib/skin_smooth_processor.dart`)**: Applies `skin_smooth.frag` to raw still photos using an offline `ui.PictureRecorder` and `ui.Canvas` before saving.
* **iOS Camera Roll Storage (`lib/camera_controller.dart`)**: Uses the `gal` package to request photo permissions on startup and save captured images cleanly via `Gal.putImageBytes`.
* **iOS Interface Layout (`lib/camera_screen.dart`)**: Replicates the iOS Camera interface with a **19:9** viewfinder, rule-of-thirds grid, `.5`, `1`, `2x`, `5` zoom pills, mode strip, concentric shutter button, and an expandable camera controls drawer.

---

## 2. GitHub Actions Workflow Configuration (`.github/workflows/build-ipa.yml`)

GitHub provides free macOS runners (`macos-latest`) capable of compiling Flutter iOS applications. Because you will sign the app on Windows using Sideloadly with your personal Apple ID, the workflow builds an **unsigned release bundle** using `--no-codesign`, packages it into `Payload/smooth_camera.app`, and zips it into `smooth_camera_unsigned.ipa`.

Here is the workflow script configured in [`.github/workflows/build-ipa.yml`](.github/workflows/build-ipa.yml):

```yaml
name: Build Unsigned iOS IPA for Sideloadly

on:
  push:
    branches: [ main, master ]
  pull_request:
    branches: [ main, master ]
  workflow_dispatch: # Allows manual trigger button from GitHub Actions UI

jobs:
  build-ios:
    name: Build Unsigned iOS Release IPA
    runs-on: macos-latest
    timeout-minutes: 45

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Set up Flutter
        uses: subosito/flutter-action@v2
        with:
          channel: 'stable'
          cache: true

      - name: Verify Flutter & Xcode Environment
        run: |
          flutter --version
          xcodebuild -version

      - name: Install dependencies
        run: |
          if [ -d "smooth_camera_app" ]; then
            cd smooth_camera_app
          fi
          flutter pub get

      - name: Build unsigned iOS release bundle
        run: |
          if [ -d "smooth_camera_app" ]; then
            cd smooth_camera_app
          fi
          # Build release .app bundle without requiring an Apple Developer Certificate
          flutter build ios --release --no-codesign

      - name: Package Payload and create IPA for Sideloadly
        run: |
          if [ -d "smooth_camera_app" ]; then
            cd smooth_camera_app
          fi
          BUILD_DIR="build/ios/iphoneos"

          # Clean previous packaging
          rm -rf Payload smooth_camera_unsigned.ipa

          # Create Payload directory required by the iOS IPA standard
          mkdir -p Payload

          # Copy Runner.app into Payload as smooth_camera.app
          cp -R "$BUILD_DIR/Runner.app" Payload/smooth_camera.app

          # Compress Payload into unsigned .ipa archive
          zip -r -y smooth_camera_unsigned.ipa Payload

          echo "Payload and IPA package created successfully:"
          ls -la Payload
          ls -lh smooth_camera_unsigned.ipa

      - name: Upload IPA Artifact
        uses: actions/upload-artifact@v4
        with:
          name: smooth-camera-unsigned-ipa
          path: |
            smooth_camera_unsigned.ipa
            smooth_camera_app/smooth_camera_unsigned.ipa
          if-no-files-found: error
          retention-days: 30
```

---

## 3. GitHub Repository Setup & Triggering the Build

1. **Initialize Git and Push to GitHub**:
   ```bash
   # From the project root (c:\Users\metz-\Desktop\code\ios_snap_smoth_camera)
   git init
   git add .
   git commit -m "Add iOS camera app with GitHub Actions IPA build workflow"

   # Link your GitHub repository
   git branch -M main
   git remote add origin https://github.com/<your-username>/<your-repo-name>.git
   git push -u origin main
   ```

2. **Trigger the Workflow on GitHub**:
   - Pushing to `main` automatically triggers the build.
   - Alternatively, trigger it manually:
     1. Open your repository on **github.com**.
     2. Click on the **Actions** tab.
     3. In the left sidebar, click **Build Unsigned iOS IPA for Sideloadly**.
     4. Click **Run workflow** > select branch `main` > click **Run workflow**.

3. **Download the Compiled `.ipa`**:
   - Once the workflow completes (~6–10 minutes, marked with a green checkmark):
   - Click on the completed workflow run.
   - Scroll down to the **Artifacts** section at the bottom.
   - Click **`smooth-camera-unsigned-ipa`** to download the zip containing `smooth_camera_unsigned.ipa`.
   - Extract the downloaded zip file on your Windows machine to obtain `smooth_camera_unsigned.ipa`.

---

## 4. Sideloading via Sideloadly on Windows

[Sideloadly](https://sideloadly.io/) allows you to sign and install any `.ipa` file onto an iOS device directly from a Windows PC using a free personal Apple ID.

### Prerequisites on Windows:
* **iTunes**: Download the standalone desktop version from [Apple](https://www.apple.com/itunes/) (do **not** install the Microsoft Store version, as it lacks mobile device drivers).
* **iCloud**: Download the standalone desktop version from Apple or ensure Apple Mobile Device Support is running.
* **Sideloadly**: Download and install from [sideloadly.io](https://sideloadly.io/).

### Installation Steps:
1. **Connect iPhone**:
   - Connect your iPhone to your Windows PC via USB cable.
   - Unlock your iPhone and tap **Trust This Computer** when prompted.
2. **Open Sideloadly**:
   - Sideloadly will detect your connected iPhone in the **iDevice** dropdown.
3. **Load the IPA**:
   - Drag and drop `smooth_camera_unsigned.ipa` into the large **IPA icon** area on the left of Sideloadly.
4. **Enter Apple ID**:
   - In the **Apple ID** field, enter your personal Apple ID email address.
   - Under **Signing Mode**, leave it on **Normal Install**.
5. **Start Signing & Install**:
   - Click **Start**.
   - Enter your Apple ID password when prompted (handled securely via Apple's authentication servers with 2FA).
   - Sideloadly will unpack `Payload/smooth_camera.app`, apply a free 7-day development certificate, package it, and install **Smooth Camera** directly onto your home screen.

---

## 5. First-Time Setup on iOS (iOS 16, 17, and 18+)

Before the app can run on your iPhone:

1. **Enable Developer Mode** (iOS 16+):
   - Open **Settings** > **Privacy & Security** > scroll to the bottom and tap **Developer Mode**.
   - Toggle **Developer Mode** to **On** and restart your iPhone when prompted.
   - After restart, unlock your phone and tap **Turn On**.
2. **Trust Developer Certificate**:
   - Open **Settings** > **General** > **VPN & Device Management**.
   - Under **Developer App**, tap your Apple ID email.
   - Tap **Trust "[Your Apple ID]"** and confirm.
3. **Launch Smooth Camera**:
   - Open **Smooth Camera** from your home screen.
   - The app will prompt for:
     - **Camera Access** (`NSCameraUsageDescription`): Required for the live 19:9 feed.
     - **Photos Access** (`NSPhotoLibraryAddUsageDescription`): Required to save processed photos.
   - Tap **Allow** on both prompts.

---

## 6. Troubleshooting & Notes

| Issue | Cause | Resolution |
| :--- | :--- | :--- |
| **"Could not connect to Apple Mobile Device"** | Windows Store version of iTunes installed | Uninstall Windows Store iTunes; install the standalone iTunes installer from Apple. |
| **App crashes on startup on iOS** | Missing usage descriptions in `Info.plist` | Verified: `NSCameraUsageDescription` and `NSPhotoLibraryAddUsageDescription` are already configured in `ios/Runner/Info.plist`. |
| **"Developer Mode Required"** | iOS 16+ security policy | Enable Developer Mode under `Settings > Privacy & Security > Developer Mode`. |
| **7-Day Expiration** | Free Apple ID provisioning profile duration | Sideloaded apps signed with a free Apple ID remain valid for 7 days. Reconnect to Windows and click **Start** in Sideloadly to refresh the profile without losing app data. |
| **GitHub Actions runner timeout** | First run cache warming | Runner timeout is set to 45 minutes with Flutter cache enabled. Subsequent builds finish in ~5–7 minutes. |
