# VoiceGenius Architecture

This document provides a comprehensive overview of the VoiceGenius iOS application architecture.

## Overview

VoiceGenius is a native iOS voice-to-voice conversational app that runs LLM inference locally. The app uses a **Sidecar Pattern** to support both Simulator and Device builds with different inference backends.

```
┌─────────────────────────────────────────────────────────────────────┐
│                         VoiceGenius App                              │
├─────────────────────────────────────────────────────────────────────┤
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────────────┐  │
│  │   SwiftUI    │    │  ViewModel   │    │      Services        │  │
│  │    Views     │◄──►│ Conversation │◄──►│  (Audio, LLM, TTS)   │  │
│  └──────────────┘    └──────────────┘    └──────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
                                │
                    ┌───────────┴───────────┐
                    ▼                       ▼
         ┌──────────────────┐    ┌──────────────────┐
         │   Simulator      │    │     Device       │
         │  SidecarLLM      │    │  OnDeviceLLM     │
         │  (HTTP→Python)   │    │  (MLX Swift)     │
         └────────┬─────────┘    └──────────────────┘
                  │
                  ▼
         ┌──────────────────┐
         │  Python Sidecar  │
         │  (Flask + MLX)   │
         └──────────────────┘
```

## Directory Structure

```
VoiceGenius/
├── VoiceGeniusApp.swift          # App entry point
├── Models/
│   ├── ConversationState.swift   # State enum (idle/listening/thinking/speaking)
│   ├── LLMBackend.swift          # Backend enum + ModelPreset struct
│   └── Transcript.swift          # Conversation transcript model
├── Services/
│   ├── AudioCaptureService.swift # Microphone + amplitude metering
│   ├── SpeechRecognizer.swift    # On-device STT with VAD
│   ├── SpeechSynthesizer.swift   # TTS via AVSpeechSynthesizer
│   ├── LLMService.swift          # Protocol + factory
│   ├── SidecarLLMService.swift   # HTTP client for Simulator
│   ├── OnDeviceLLMService.swift  # MLX Swift for Device
│   ├── FoundationLLMService.swift # Apple Intelligence (iOS 26+)
│   ├── ModelDownloader.swift     # HuggingFace model downloader
│   └── TranscriptStore.swift     # JSON persistence for transcripts
├── ViewModels/
│   ├── ConversationViewModel.swift # Main orchestrator
│   └── SettingsViewModel.swift     # User preferences (UserDefaults)
└── Views/
    ├── ContentView.swift         # Root view composition
    ├── GlowVisualizer.swift      # Breathing circle animation
    ├── DownloadProgressView.swift # Model download UI
    ├── EndSessionButton.swift    # Start/stop session control
    ├── SettingsView.swift        # Backend/model settings UI
    ├── TranscriptHistoryView.swift # Conversation history list
    └── TranscriptDetailView.swift  # Single transcript view

VoiceGeniusAssetDownloader/       # Background Assets extension
├── AssetDownloaderExtension.swift
└── Info.plist

sidecar/                          # Python LLM server (Simulator only)
├── sidecar.py
└── requirements.txt
```

## Core Components

### 1. Conversation Loop (ConversationViewModel)

The `ConversationViewModel` orchestrates the main conversation loop:

```
┌─────────┐     ┌───────────┐     ┌──────────┐     ┌──────────┐
│  IDLE   │────►│ LISTENING │────►│ THINKING │────►│ SPEAKING │
└─────────┘     └───────────┘     └──────────┘     └──────────┘
     ▲                                                   │
     └───────────────────────────────────────────────────┘
```

**State Transitions:**
1. **IDLE → LISTENING**: User starts session
2. **LISTENING → THINKING**: VAD detects 1.2s silence after speech
3. **THINKING → SPEAKING**: LLM response received
4. **SPEAKING → LISTENING**: TTS completes, loop continues

### 2. Audio Pipeline

```
┌─────────────────┐     ┌────────────────────┐
│ AudioCapture    │────►│  SpeechRecognizer  │
│ (AVAudioEngine) │     │  (SFSpeechRecog.)  │
└─────────────────┘     └─────────┬──────────┘
        │                         │
        ▼                         ▼
   Amplitude               Transcript Text
   (for visualizer)        (for LLM prompt)
```

**Key Design Decisions:**
- Both services are `@unchecked Sendable` (not `@MainActor`) because audio callbacks fire on background threads
- UI updates dispatched to main thread via `DispatchQueue.main.async`
- VAD (Voice Activity Detection) uses 1.2s silence threshold to detect utterance end

### 3. LLM Service (Dynamic Backend Selection)

The app supports runtime switching between backends via `LLMFactory`:

```swift
switch settings.backend {
case .foundation:
    return FoundationLLMService()  // Apple Intelligence (iOS 26+)
case .mlx:
    #if targetEnvironment(simulator)
    return SidecarLLMService()     // HTTP to Python server
    #else
    return OnDeviceLLMService()    // MLX Swift on-device
    #endif
}
```

**Backend Options:**

| Backend | Service | Requirements |
|---------|---------|--------------|
| Apple Foundation | `FoundationLLMService` | iOS 26+, Apple Intelligence device |
| MLX (Simulator) | `SidecarLLMService` | Python sidecar running |
| MLX (Device) | `OnDeviceLLMService` | Model downloaded (~2GB) |

**Hot-Swap Support:** When switching backends, `ConversationViewModel.reinitializeLLMService()` unloads the current model (freeing ~2GB RAM) before loading the new service.

### 4. Model Asset Management

The `ModelDownloader` handles downloading the ~1.7GB Qwen model from HuggingFace:

```
┌─────────────────────────────────────────────────────────────┐
│                    ModelDownloader                          │
├─────────────────────────────────────────────────────────────┤
│  • Storage: Library/Application Support/Models/             │
│  • Backup Exclusion: isExcludedFromBackupKey = true        │
│  • Resume Support: URLSession download delegate             │
│  • Validation: SHA-256 checksum for LFS files              │
│  • Pre-checks: Disk space (2.5GB), network availability    │
└─────────────────────────────────────────────────────────────┘
```

**Download States:**
```
IDLE → CHECKING_REQUIREMENTS → DOWNLOADING → VALIDATING → COMPLETED
                                    │
                                    └──► FAILED (resumable)
```

### 5. Background Assets Extension

The `VoiceGeniusAssetDownloader` extension enables model downloads before first app launch:

```
┌──────────────────┐     ┌─────────────────────────────────┐
│  App Store /     │     │  VoiceGeniusAssetDownloader     │
│  TestFlight      │────►│  (BADownloaderExtension)        │
│  Install         │     └─────────────┬───────────────────┘
└──────────────────┘                   │
                                       ▼
                        ┌─────────────────────────────────┐
                        │  Downloads model files to       │
                        │  shared App Group container     │
                        └─────────────────────────────────┘
```

**Trigger Points:**
- App installation from App Store
- TestFlight update
- OS background asset refresh

## Data Flow

### Conversation Flow

```
User speaks
    │
    ▼
┌─────────────────────┐
│  AudioCaptureService │──► amplitude ──► GlowVisualizer
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  SpeechRecognizer   │
│  (on-device STT)    │
└──────────┬──────────┘
           │ 1.2s silence detected
           ▼
┌─────────────────────┐
│  ConversationVM     │
│  handleUtterance()  │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  LLMService         │
│  generate(prompt)   │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  SpeechSynthesizer  │
│  speak(response)    │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  TranscriptStore    │
│  save(transcript)   │
└─────────────────────┘
```

### Model Download Flow

```
App Launch
    │
    ▼
┌───────────────────────────┐
│ isModelDownloaded()?      │──Yes──► Load Model ──► Ready
└───────────┬───────────────┘
            │ No
            ▼
┌───────────────────────────┐
│ Check disk space (2.5GB)  │──Fail──► Show Error
└───────────┬───────────────┘
            │ OK
            ▼
┌───────────────────────────┐
│ Check network             │──Fail──► Show Offline UI
└───────────┬───────────────┘
            │ OK
            ▼
┌───────────────────────────┐
│ Fetch file list from HF   │
│ (sizes + checksums)       │
└───────────┬───────────────┘
            │
            ▼
┌───────────────────────────┐
│ Download files with       │◄─── Resume data if interrupted
│ progress updates          │
└───────────┬───────────────┘
            │
            ▼
┌───────────────────────────┐
│ Validate SHA-256          │──Fail──► Retry download
└───────────┬───────────────┘
            │ OK
            ▼
┌───────────────────────────┐
│ Set backup exclusion      │
│ Load model                │
└───────────────────────────┘
```

## Threading Model

| Component | Actor Isolation | Reason |
|-----------|-----------------|--------|
| `ConversationViewModel` | `@MainActor` | UI state management |
| `SettingsViewModel` | `@MainActor` | UI-bound settings |
| `ModelDownloader` | `@MainActor` | Published properties for UI |
| `TranscriptStore` | `@MainActor` | Published transcript list |
| `SpeechSynthesizer` | `@MainActor` | AVSpeechSynthesizer delegate |
| `AudioCaptureService` | `@unchecked Sendable` | Audio callbacks on background threads |
| `SpeechRecognizer` | `@unchecked Sendable` | Recognition callbacks on background |
| `SidecarLLMService` | `@unchecked Sendable` | Network operations |
| `OnDeviceLLMService` | `@unchecked Sendable` | MLX inference |
| `FoundationLLMService` | `@unchecked Sendable` | Foundation Models inference |

## Configuration

Settings are managed by `SettingsViewModel` and persisted in UserDefaults:

| Setting | Default | Description |
|---------|---------|-------------|
| `backend` | `.mlx` | LLM backend (MLX or Apple Foundation) |
| `selectedPreset` | Balanced | Model preset (Qwen 3B or Llama 1B) |
| `systemPrompt` | (voice assistant) | AI persona instructions |
| `maxTokens` | 256 | Max response length |

Accessed via `SettingsViewModel.shared` singleton. Settings UI available via gear icon.

## Storage Locations

| Data | Location | Backup |
|------|----------|--------|
| Model files | `Library/Application Support/Models/` | Excluded |
| Transcripts | `Documents/transcripts/` | Included |
| Resume data | `Library/Application Support/Models/.resume_data` | Excluded |

## Dependencies

### iOS App
- **SwiftUI**: UI framework
- **AVFoundation**: Audio capture and TTS
- **Speech**: On-device speech recognition
- **BackgroundAssets**: Install-time downloads
- **CryptoKit**: SHA-256 validation
- **Network**: Connectivity monitoring
- **MLXLLM** (device only): On-device LLM inference

### Python Sidecar
- **Flask**: HTTP server
- **mlx-lm**: MLX language model inference

## Build Configurations

### Simulator
- Uses `SidecarLLMService` (HTTP to Python)
- Pre-build script auto-starts sidecar
- No model download required (sidecar handles it)

### Device
- Uses `OnDeviceLLMService` (MLX Swift)
- Requires MLXLLM SPM package
- Downloads model on first launch or via Background Assets

## Extension Points

### Adding New LLM Providers
1. Implement `LLMService` protocol
2. Add to `LLMFactory.create()`
3. Handle model loading if needed

### Custom Voices
Modify `SpeechSynthesizer.speak()` to use different `AVSpeechSynthesisVoice` configurations.

### Alternative Model Sources
Update `ModelDownloader.fetchFileList()` and download URLs to support other model repositories.
