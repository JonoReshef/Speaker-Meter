# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

SpeakMeter is a macOS menubar-style utility that monitors microphone input to display real-time speaking volume (dB SPL) and words-per-minute (WPM) pace. It targets macOS 14+ (Sonoma), Apple Silicon only (arm64).

## Build & Run

```bash
# SPM build
swift build -c release --arch arm64

# Build .app bundle (builds + signs + assembles into build/SpeakMeter.app)
bash Scripts/build.sh

# Run the built app
open build/SpeakMeter.app
```

There are no tests or linting configured.

## Architecture

**App lifecycle**: Uses manual `NSApplication` setup in `main.swift` (NOT `@main` SwiftUI lifecycle). `AppDelegate` creates an `NSWindow` with `NSHostingView` wrapping the SwiftUI `ContentView`. Window height snaps to discrete segment counts (5–20) and persists via UserDefaults.

**Audio pipeline**: `AudioManager` captures mic input via `AVAudioEngine`, computes RMS → dB SPL, and forwards raw `AVAudioPCMBuffer` to `AcousticPaceAnalyzer` via a callback.

**WPM estimation** (`AcousticPaceAnalyzer`): Pure DSP approach using Accelerate framework — no speech recognition. Pipeline: bandpass filter (300–3000 Hz) → full-wave rectify → envelope extraction (10 Hz LPF) → downsample to 100 Hz → peak detection (syllable counting) → syllables/1.5 → WPM. Includes VAD (voice activity detection) with onset/offset thresholds and hold time.

**Views**: `VolumeMeterView` renders a segmented LED-style volume meter. `WPMGraphView` renders a scrolling line graph of WPM history. `ContentView` composes both with a settings popover for threshold tuning.

**User preferences**: All thresholds (volume dB, WPM ranges, color thresholds) stored via `@AppStorage` / `UserDefaults`.

## Key Conventions

- Bundle ID is `com.yourname.speakmeter` (placeholder — needs real Apple Developer prefix)
- Info.plist is embedded into the binary via linker flags in Package.swift (`__TEXT/__info_plist`)
- App requires microphone permission (`NSMicrophoneUsageDescription` in Info.plist, `com.apple.security.device.audio-input` in entitlements)
- Entitlements include App Sandbox (required for Mac App Store distribution)
- Xcode project can be regenerated from `project.yml` using xcodegen
