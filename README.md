# VolumeMeter

A native macOS app that monitors microphone input volume in real-time with a visual meter.

## Requirements

- macOS 14+ (Sonoma)
- Apple Silicon (arm64)
- Swift 5.9+ (Command Line Tools)

## Build & Run

```bash
chmod +x Scripts/build.sh
./Scripts/build.sh
open build/VolumeMeter.app
```

## Install

To install to your Applications folder:

```bash
bash Scripts/build.sh && cp -R build/SpeakMeter.app /Applications/
```

## Usage

1. Grant microphone permission when prompted
2. The volume meter responds in real-time to audio input
3. Use the Start/Stop button to toggle monitoring
