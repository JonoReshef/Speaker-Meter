# SpeakMeter

A native macOS menubar utility that monitors your microphone to display real-time speaking volume (dB SPL) and words-per-minute (WPM) pace.

**100% offline and private — no audio data ever leaves your computer.** All processing happens locally on-device using Apple's native frameworks. No network calls, no cloud services, no data collection.

## Motivation

I speak too fast and too loud most of the time time. This helps me keep it in check. It might help you too!

## How to use

- Comes with sensible default thresholds for volume and pace, but you can customize them in the settings popover and these persist across launches
- Just open the app, it will float on top of other windows as long as they are not in full-screen mode
- I have not done any extensive testing but it has not perceptible impact on CPU or battery on my MacBook Pro, even with the volume and pace graphs updating in real-time.

## Requirements

- macOS 14+ (Sonoma)
- Apple Silicon (arm64)
- Swift 5.9+ (Command Line Tools)

## Build & Run

```bash
chmod +x Scripts/build.sh
./Scripts/build.sh
open build/SpeakMeter.app
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

## How It Works

### Summary

SpeakMeter captures audio from your microphone and processes it in real-time to estimate two key metrics:

- **Volume (dB SPL)**: A measure of how loud you're speaking. Simple measurement of the live streamed waveform
- **Words Per Minute (WPM)**: An estimate of your speaking pace based on acoustic features. Simple signal processing that measure the frequency of peak amplitudes from the natural oscillations in the 300–3000 Hz range.
- All data processed on device, nothing is stored, nothing is sent.

### Volume (dB SPL)

Audio is captured from your default input device via `AVAudioEngine`. For each buffer:

1. **RMS calculation** — the root-mean-square of all samples across channels gives the average signal power.
2. **dBFS conversion** — `20 × log10(RMS)` converts to decibels relative to full scale, clamped to the range −60 to 0 dBFS.
3. **Approximate dB SPL** — an offset of +90 dB maps the digital level to a rough sound-pressure-level estimate (digital 0 dBFS ≈ 90 dB SPL).
4. **Smoothing** — an exponential moving average (α = 0.3) smooths the displayed value to reduce jitter.

### Words Per Minute (WPM)

WPM is estimated entirely through acoustic signal processing — **no speech recognition or transcription** is used. The pipeline uses Apple's Accelerate framework for efficient DSP:

1. **Mono mixdown** — multi-channel audio is averaged to a single channel.
2. **Bandpass filter (300–3000 Hz)** — isolates the speech frequency range using Butterworth biquad filters, removing low rumble and high-frequency noise.
3. **Full-wave rectification** — takes the absolute value of the filtered signal.
4. **Envelope extraction** — a 10 Hz lowpass filter smooths the rectified signal into an amplitude envelope that traces syllable-level energy fluctuations.
5. **Downsample to 100 Hz** — reduces the envelope to a manageable rate for peak detection.
6. **Voice Activity Detection (VAD)** — monitors RMS energy with onset/offset thresholds and a hold timer to determine when you're actually speaking vs. silent.
7. **Peak detection** — counts peaks in the envelope over a 3-second sliding window. Peaks must exceed an adaptive threshold (mean + 0.3× std dev), be separated by at least 80 ms, and have sufficient valley depth between them. Each peak represents roughly one syllable.
8. **Syllables to WPM** — `(syllable count ÷ 1.5) ÷ window duration × 60` converts syllable rate to an estimated word rate (assuming ~1.5 syllables per word on average).
9. **Smoothing** — exponential moving average reduces noise in the final displayed value.

### Privacy

SpeakMeter processes audio buffers in real-time and discards them immediately — nothing is recorded, stored, or transmitted. The app requires microphone permission solely for live monitoring.
