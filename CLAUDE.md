# CLAUDE.md - Project Guide for Claude Code

## Project Overview

VoiceGenius is a native iOS voice-to-voice app that converses with a local LLM. It uses a **Sidecar Pattern** to support both Simulator (Python server) and Device (MLX Swift) targets.

## Architecture

### Sidecar Pattern
- **Simulator builds**: Use `SidecarLLMService` → HTTP to `localhost:8080` Python server
- **Device builds**: Use `OnDeviceLLMService` → MLX Swift on-device inference
- Compile-time switching via `#if targetEnvironment(simulator)`

### Key Components
- **Services**: LLM, Audio Capture, Speech Recognition, TTS, Model Download, Transcript Storage
- **ViewModels**: `ConversationViewModel` orchestrates the conversation loop
- **Views**: SwiftUI with `GlowVisualizer` (breathing circle animation)

## Build & Run

### Simulator (recommended for development)
```bash
# 1. Install Python deps (one-time)
cd sidecar && pip install -r requirements.txt

# 2. Build/run in Xcode - sidecar auto-starts via build phase
open VoiceGenius.xcodeproj
# Press ⌘R
```

### Device
Requires adding MLXLLM SPM package manually in Xcode:
- File → Add Package Dependencies
- URL: `https://github.com/ml-explore/mlx-swift-examples`

## Project Structure

```
VoiceGenius/           # iOS app source
├── Models/            # Data models (Transcript, ConversationState)
├── Services/          # Business logic (LLM, Audio, Speech, Persistence)
├── ViewModels/        # State management
└── Views/             # SwiftUI views

sidecar/               # Python LLM server for Simulator
├── sidecar.py
└── requirements.txt

project.yml            # XcodeGen config (regenerate with: xcodegen generate)
```

## Threading Notes

Audio services (`AudioCaptureService`, `SpeechRecognizer`) are **NOT** `@MainActor` because audio callbacks fire on background threads. They dispatch UI updates to main thread via `DispatchQueue.main.async`.

## Common Tasks

### Regenerate Xcode project
```bash
xcodegen generate
```

### Check sidecar status
```bash
curl http://127.0.0.1:8080/health
```

### View sidecar logs
```bash
tail -f /tmp/voicegenius_sidecar.log
```

### Kill sidecar manually
```bash
lsof -ti :8080 | xargs kill
```
