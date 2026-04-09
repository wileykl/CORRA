# Corra

Clinical Operations Recruitment and Retention Assistant (CORRA)** is a SwiftUI application for iOS that runs a local large language model with **Cache Augmented Generation (CAG)**, memory-aware loading, and safety boundaries tuned for clinical-trial and research contexts. The app entry point is `CorraCAGApp.swift` (version **2.0.0** as logged at startup).

#Features

- **On-device inference** via embedded **llama.cpp** (C/C++/Metal) bridged to Swift (`LlamaCppBridge`, `ModelManager`).
- **CAG knowledge layer** (`CAGManager`): loads `knowledge_cache.json` from the app bundle, lazy chunk loading, keyword indexing, and retrieval to augment prompts.
- **Safety** (`SafetyBoundaries`): clinical-trial–oriented keyword handling, adversarial-pattern checks, and filters to reduce inappropriate personal medical advice (including multilingual patterns).
- **Memory management** (`MemoryManager`): startup checks available memory, chooses full or reduced model configuration, and responds to iOS memory warnings.
- **UI**: chat (`ChatView`), launch screen, document reader, TTS settings, and optional text-to-speech integration (`TTSManager`, `AVSpeechSynthesizer`).

#Repository layout

| Path | Purpose |
|------|---------|
| `CorraCAGApp.swift` | `@main` app: wires environment objects and initializes CAG, model, and safety. |
| `Sources/App/` | Alternate `CorraApp` (reference only; not the active `@main`). |
| `Sources/Core/` | Model bridge, `CAGManager`, `ModelManager`, `DocumentManager`, ggml/llama sources, Metal backend. |
| `Sources/UI/` | SwiftUI views (`ContentView`, `ChatView`, `DocumentReaderView`, etc.). |
| `Sources/Memory/` | `MemoryManager` and related behavior. |
| `Sources/Safety/` | `SafetyBoundaries`. |
| `Sources/Models/`, `Sources/Utilities/` | Supporting types and helpers. |
| `Resources/` | Large assets (e.g. quantized **GGUF** model, reference PDFs). Expected bundle name for the model matches code: `Llama-3.2-3B-Instruct-HF_q4_k_m_20251105_145103.gguf`. |
| `Assets.xcassets/` | Images including app icon set. |
| `check_bundle_resources.sh` | Checks an Xcode `project.pbxproj` for GGUF and `knowledge_cache.json` in **Copy Bundle Resources**. |
| `verify_resources.sh` | Verifies on-disk presence of model, cache, and icon files (paths inside the script may need editing for your machine). |

#Requirements

- **Xcode** and an **iOS** deployment target suitable for SwiftUI and Metal.
- **Device storage and RAM**: the bundled GGUF is large (multi-gigabyte). The app prefers roughly **4 GB+** available memory for the full configuration; below that it uses a reduced configuration.
- A valid **`knowledge_cache.json`** in the app target’s bundle (same expectation as `CAGManager`); without it, CAG reports a load error at runtime.

#Building and running

1. Open the **CorraCAG** Xcode project (`.xcodeproj`) that references this source tree on your machine.
2. Add to the app target **Copy Bundle Resources** (if not already present):
   - The GGUF file under `Resources/` (name must match what `ModelManager` resolves in the bundle).
   - `knowledge_cache.json` when you have generated or copied it into the project.
3. **Clean** (Shift+Command+K) and **build** for a physical device or simulator, accounting for model size and simulator limitations.

You can adapt and run `check_bundle_resources.sh` after pointing `PROJECT_FILE` at your actual `project.pbxproj`. Similarly, update `PROJECT_DIR` / `RESOURCES_DIR` in `verify_resources.sh` so paths match your checkout (for example under iCloud or Box).

#Disclaimer

This software is intended as an educational assistant** with safety-oriented filtering. It is not a substitute for professional medical advice, diagnosis, or treatment. Validate behavior, data handling, and compliance with your organization’s policies before any production or research use.

