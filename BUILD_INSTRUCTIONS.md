# Smooth Camera App – CI/CD Build & Sideloading Guide

This document outlines the project architecture and provides step-by-step instructions for configuring a **Codemagic CI/CD workflow** to build an unsigned iOS application bundle (`Payload/smooth_camera.app`) and package it into an `.ipa` for installation on Windows via **Sideloadly**.

---

## 1. Project Architecture Overview

```
ios_snap_smoth_camera/
├── BUILD_INSTRUCTIONS.md               # This build & deployment guide
├── codemagic.yaml                      # Automated Codemagic build script
└── smooth_camera_app/                  # Flutter application root
    ├── codemagic.yaml                  # Local copy for direct root repository builds
    ├── pubspec.yaml                    # Dependencies (camera, gal) & shader mapping
    ├── shaders/
    │   └── skin_smooth.frag            # GLSL bilateral/surface blur fragment shader
    ├── ios/
    │   └── Runner/
    │       └── Info.plist              # NSCamera & NSPhotoLibrary permission keys
    ├── lib/
    │   ├── main.dart                   # Entry point, system overlays & dark camera theme
    │   ├── camera_controller.dart      # Camera lifecycle, stream coordinates, zoom, capture
    │   ├── shader_camera_preview.dart  # Real-time GPU shader preview & CustomPainter
    │   ├── skin_smooth_processor.dart  # Offline GPU bilateral filtering on captured bytes
    │   └── camera_screen.dart          # iOS Camera UI (19:9 ratio, grid, zoom, shutter, drawer)
    └── test/
        ├── processor_test.dart         # Unit tests for image shader processing
        └── widget_test.dart            # Smoke tests for app bootstrap
```

### Core Components
* **Real-time Fragment Shader (`shaders/skin_smooth.frag`)**: GLSL 460 bilateral filter compiled into SPIR-V by Flutter's asset-based shader pipeline. Features uniform resolution, dynamic blur intensity, and photometric Gaussian weighting to smooth skin tones while preserving eyes, eyebrows, and hair edges.
* **Live Camera Viewport (`lib/shader_camera_preview.dart`)**: Piped through `ui.ImageFilter.shader` using Flutter's Impeller GPU backend on iOS for hardware-accelerated 60/120 FPS rendering.
* **High-Resolution Filter Processing (`lib/skin_smooth_processor.dart`)**: Applies `skin_smooth.frag` to raw still photos using an offline `ui.PictureRecorder` and `ui.Canvas` before saving.
* **iOS Camera Roll Storage (`lib/camera_controller.dart`)**: Integrates the `gal` package to request photo permissions on startup and save captured images cleanly via `Gal.putImageBytes`.
* **iOS Interface Layout (`lib/camera_screen.dart`)**: Authentic iOS camera design featuring a **19:9** viewfinder, rule-of-thirds grid, `.5`, `1`, `2x`, `5` zoom pills, mode strip, concentric shutter button, and an expandable camera controls drawer.

---

## 2. GitHub Repository Setup

To allow Codemagic to build the app, push your codebase to GitHub:

```bash
# In the project root (c:\Users\metz-\Desktop\code\ios_snap_smoth_camera)
git init
git add .
git commit -m "Initial commit of smooth camera app with bilateral shader"

# Link to your GitHub repository
git branch -M main
git remote add origin https://github.com/<your-username>/<your-repo-name>.git
git push -u origin main
```

---

## 3. Codemagic Workflow Configuration (`codemagic.yaml`)

Codemagic provides free macOS build instances capable of compiling Flutter iOS applications. Because you will sign the app on Windows using Sideloadly with your personal Apple ID, the workflow builds an **unsigned release bundle** using `--no-codesign`, packages it into `Payload/smooth_camera.app`, and zips it into `smooth_camera_unsigned.ipa`.

Here is the exact `codemagic.yaml` specification:

```yaml
workflows:
  ios-unsigned-release:
    name: Build Unsigned iOS Release for Sideloadly
    max_build_duration: 30
    instance_type: mac_mini_m2
    environment:
      flutter: stable
      xcode: latest
      cocoapods: default
    scripts:
      - name: Set up Flutter environment & dependencies
        script: |
          # Navigate to project subfolder if repository contains root container
          if [ -d "smooth_camera_app" ]; then
            cd smooth_camera_app
          fi
          echo "Flutter SDK version:"
          flutter --version
          flutter pub get

      - name: Build unsigned iOS release bundle
        script: |
          if [ -d "smooth_camera_app" ]; then
            cd smooth_camera_app
          fi
          # Build release .app without requiring an Apple Developer Certificate
          flutter build ios --release --no-codesign

      - name: Package Payload and generate .ipa for Sideloadly
        script: |
          if [ -d "smooth_camera_app" ]; then
            cd smooth_camera_app
          fi
          # Locate built application bundle
          BUILD_DIR="build/ios/iphoneos"
          
          # Clean previous packaging
          rm -rf Payload smooth_camera_unsigned.ipa
          
          # Create Payload directory required by the iOS IPA standard
          mkdir -p Payload
          
          # Copy Runner.app into Payload as smooth_camera.app
          cp -R "$BUILD_DIR/Runner.app" Payload/smooth_camera.app
          
          # Compress Payload folder into unsigned .ipa archive
          zip -r -y smooth_camera_unsigned.ipa Payload
          
          echo "Payload and IPA package created successfully:"
          ls -la Payload
          ls -lh smooth_camera_unsigned.ipa

    artifacts:
      - smooth_camera_app/smooth_camera_unsigned.ipa
      - smooth_camera_unsigned.ipa
      - smooth_camera_app/Payload/**
      - Payload/**
```

---

## 4. Codemagic Web Setup (Step-by-Step)

1. **Sign up / Log in to Codemagic**:
   - Go to [codemagic.io](https://codemagic.io) and log in with your GitHub account.
2. **Add Your Repository**:
   - Navigate to **Applications** > **Add application**.
   - Select **GitHub** as the Git provider and select your `ios_snap_smoth_camera` repository.
   - Select **Flutter App** as the project type.
3. **Select `codemagic.yaml`**:
   - In the application settings, select **codemagic.yaml** as the workflow configuration method.
4. **Trigger Build**:
   - Click **Start new build**.
   - Select the `main` branch and select the `ios-unsigned-release` workflow.
   - Click **Start build**.
5. **Download the Artifact**:
   - Once the build succeeds (~5–8 minutes), scroll to the **Artifacts** section at the bottom of the build page.
   - Download **`smooth_camera_unsigned.ipa`** (or the zipped `Payload/` folder).

---

## 5. Sideloading via Sideloadly on Windows

[Sideloadly](https://sideloadly.io/) allows you to sign and install any `.ipa` file onto an iOS device directly from a Windows PC using a free personal Apple ID.

### Prerequisites on Windows:
* **iTunes**: Download the direct desktop version from [Apple](https://www.apple.com/itunes/) (do **not** install the Microsoft Store version, as it lacks mobile device drivers).
* **iCloud**: Download the direct desktop version from Apple or ensure Apple Mobile Device Support is running.
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

## 6. First-Time Setup on iOS (iOS 16, 17, and 18+)

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

## 7. Troubleshooting & Notes

| Issue | Cause | Resolution |
| :--- | :--- | :--- |
| **"Could not connect to Apple Mobile Device"** | Windows Store version of iTunes installed | Uninstall Windows Store iTunes; install the standalone iTunes installer from Apple. |
| **App crashes on startup on iOS** | Missing usage descriptions in `Info.plist` | Verified: `NSCameraUsageDescription` and `NSPhotoLibraryAddUsageDescription` are already configured in `ios/Runner/Info.plist`. |
| **"Developer Mode Required"** | iOS 16+ security policy | Enable Developer Mode under `Settings > Privacy & Security > Developer Mode`. |
| **7-Day Expiration** | Free Apple ID provisioning profile duration | Sideloaded apps signed with a free Apple ID remain valid for 7 days. Reconnect to Windows and click **Start** in Sideloadly to refresh the profile without losing app data. |
| **Shader Compilation on Device** | Impeller GPU compiler | `shaders/skin_smooth.frag` is compiled ahead-of-time by Flutter's asset toolchain and runs with full Impeller GPU hardware acceleration on iOS. |
