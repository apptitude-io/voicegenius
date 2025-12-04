# VoiceGenius

A native iOS voice-to-voice app that converses with a local LLM. Speak to your phone, get AI responses spoken back — all running locally.

## Features

- **Voice Input**: Real-time speech recognition using on-device `SFSpeechRecognizer`
- **Local LLM**: Llama 3.2 1B running via MLX (device) or Python sidecar (Simulator)
- **Voice Output**: Text-to-speech responses via `AVSpeechSynthesizer`
- **Visual Feedback**: Breathing circle visualizer that reacts to audio
  - 🔴 Red = Listening (user speaking)
  - ⚪ White = Thinking (processing)
  - 🔵 Blue = Speaking (AI response)
- **Conversation History**: Save and browse past conversations

## Requirements

- macOS with Apple Silicon (for MLX)
- Xcode 15+ with iOS 17+ SDK
- Python 3.10+ (for Simulator sidecar)

## Quick Start (Simulator)

```bash
# 1. Clone the repo
git clone <repo-url>
cd voicegenius

# 2. Install Python dependencies
cd sidecar
pip install -r requirements.txt
cd ..

# 3. Open in Xcode and run
open VoiceGenius.xcodeproj
# Press ⌘R - sidecar starts automatically!
```

> **Note**: First run downloads ~700MB model from HuggingFace. The build phase will wait up to 60s for the model to load.

## Architecture

### Sidecar Pattern

The app uses a compile-time switching pattern to handle the Simulator's lack of Metal/NPU support:

| Target | LLM Service | How it works |
|--------|-------------|--------------|
| Simulator | `SidecarLLMService` | HTTP POST to Python Flask server on localhost:8080 |
| Device | `OnDeviceLLMService` | Direct MLX Swift inference on Apple Silicon |

### Tech Stack

- **UI**: SwiftUI with Observation framework
- **Audio**: AVAudioEngine, SFSpeechRecognizer, AVSpeechSynthesizer
- **LLM**: MLX Swift / mlx-lm (Python)
- **Model**: `mlx-community/Llama-3.2-1B-Instruct-4bit`

## Project Structure

```
voicegenius/
├── VoiceGenius/                 # iOS app
│   ├── Models/
│   ├── Services/
│   ├── ViewModels/
│   └── Views/
├── sidecar/                     # Python LLM server
│   ├── sidecar.py
│   └── requirements.txt
├── project.yml                  # XcodeGen config
└── VoiceGenius.xcodeproj        # Generated Xcode project
```

## Running on Device

To run on a physical iOS device, you need to add the MLX Swift package:

1. Open `VoiceGenius.xcodeproj` in Xcode
2. File → Add Package Dependencies
3. Enter: `https://github.com/ml-explore/mlx-swift-examples`
4. Add the `MLXLLM` product to the VoiceGenius target
5. Build and run on device

The app will download the model on first launch (~700MB).

## Development

### Regenerate Xcode Project

If you modify `project.yml`:

```bash
xcodegen generate
```

### Manual Sidecar Control

```bash
# Start
cd sidecar && python sidecar.py

# Check health
curl http://127.0.0.1:8080/health

# Test chat
curl -X POST http://127.0.0.1:8080/chat \
  -H "Content-Type: application/json" \
  -d '{"prompt": "Hello!"}'
```

## License

MIT
