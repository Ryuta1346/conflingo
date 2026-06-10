# ConfLingo

**English** | [日本語](README.ja.md) | [简体中文](README.zh-CN.md) | [한국어](README.ko.md) | [Español](README.es.md)

A personal macOS app that transcribes MacBook microphone audio in real time at conference venues using Apple's built-in macOS APIs, and displays the result as translated subtitles. The recognition language and target language can be freely chosen from the languages supported by the OS (default: English → Japanese).

- Transcription: `Speech.framework` (`SpeechAnalyzer` / `SpeechTranscriber` on macOS 26, on-device)
- Translation: `Translation.framework` (`TranslationSession`, on-device)
- UI: SwiftUI two-pane layout (source transcript / translated text)

📖 **For detailed usage (registering technical terms, on-site tips, troubleshooting), see [docs/usage.md](docs/usage.md).**

## Requirements

- macOS 26.0 or later / Apple Silicon
- Xcode 26 or later (for building)
- First launch only: a network connection is required to download the speech recognition model and the translation model

## Build and Run

```sh
# Build
xcodebuild -project ConfLingo.xcodeproj -scheme ConfLingo -configuration Debug build

# Launch (open the .app generated under DerivedData)
open ~/Library/Developer/Xcode/DerivedData/ConfLingo-*/Build/Products/Debug/ConfLingo.app
```

Run tests:

```sh
xcodebuild test -project ConfLingo.xcodeproj -scheme ConfLingo -destination 'platform=macOS'
```

## Permissions

1. **Microphone**: A microphone permission dialog appears the first time you press Start. Transcription does not work without it
2. **Speech recognition model**: If the recognition model is not installed at first launch, the download starts automatically (with progress display)
3. **Translation model**: If the translation model is not installed, the standard OS download confirmation dialog appears

To reset the microphone permission:

```sh
tccutil reset Microphone com.gavrri.conflingo
```

If you accidentally denied the permission, enable ConfLingo under System Settings > Privacy & Security > Microphone.

## Usage

1. Launch the app (on first launch, model checks and downloads run)
2. Choose the recognition language and target language with the **language pickers** (changeable only while stopped; changing them automatically triggers an availability check and model download)
3. Enter a session name if needed
4. In the **technical terms field**, enter event-specific terms (speaker names, product names, technical jargon) separated by commas. They are registered as contextual strings for speech recognition at Start, improving recognition accuracy for proper nouns (preset with terms for Code with Claude Tokyo by default; changes take effect from the next Start)
5. Press **Start** (⌘R) to begin transcription
   - Recognition pane: in-progress (partial) sentences are shown dimmed and italic, then appended to the history once finalized
   - Translation pane: only finalized source sentences are translated, appended per finalized sentence
6. Press **Stop** (⌘R) to stop. Pressing Start again appends to the existing history
7. **Save Markdown** saves the entire session as Markdown
8. **A− / A＋** (⌘− / ⌘+) adjusts the font size; the "always on top" checkbox keeps the window in front
9. **Clear** discards the history (only while stopped)

## Distribution

### Option A: Share the source (recommended for developers with Xcode)

Share the repository URL and have the recipient run the following. No Gatekeeper warning appears.

```sh
git clone <repository URL> && cd conflingo
xcodebuild -project ConfLingo.xcodeproj -scheme ConfLingo build
open ~/Library/Developer/Xcode/DerivedData/ConfLingo-*/Build/Products/Debug/ConfLingo.app
```

### Option B: AirDrop a zip of the Release build

```sh
# 1. Release build (fix the output path to build/)
xcodebuild -project ConfLingo.xcodeproj -scheme ConfLingo \
  -configuration Release -derivedDataPath build build

# 2. Zip with ditto (zip -r can break signatures and extended attributes)
ditto -c -k --sequesterRsrc --keepParent \
  build/Build/Products/Release/ConfLingo.app dist/ConfLingo-1.0.zip
```

Send the resulting `dist/ConfLingo-1.0.zip` via AirDrop. **Because the app is ad-hoc signed (not notarized), the recipient must bypass Gatekeeper on first launch**:

1. Unzip and double-click → "cannot be opened because the developer cannot be verified"
2. System Settings > Privacy & Security > "Open Anyway"
3. After that, it launches normally (developers can also run `xattr -dr com.apple.quarantine ConfLingo.app`)

### Requirements to tell recipients

- **macOS 26 or later + Apple Silicon** (does not launch on earlier macOS versions)
- **Network required on first launch**: each Mac downloads the recognition and translation models (several hundred MB). In case the venue Wi-Fi is weak, ask recipients to launch the app as soon as they receive it
- Microphone permission dialog on first Start → "Allow"

## Limitations

- Venue audio is assumed to be captured by the MacBook's built-in microphone. Internal Mac audio (system audio) such as Zoom / YouTube cannot be captured
- In-progress (partial) sentences are not translated by design (to avoid unstable translations). Translation lags finalized sentences by roughly 2–5 seconds
- Languages can only be changed while stopped. Switching languages keeps the existing subtitle history (the Markdown header records the language pair at save time)
- Speaker diarization, summarization, and audio recording are not supported
- No code signing / notarization for distribution (intended for personal use with local builds)
- Recognition accuracy is heavily affected by microphone position and ambient noise. Point the MacBook toward the speakers and sit near the front if possible

## Architecture

```
AVAudioEngine microphone input (hardware format)
  └ AVAudioConverter converts to SpeechAnalyzer's preferred format
    └ AsyncStream<AnalyzerInput> → SpeechAnalyzer / SpeechTranscriber (volatileResults)
        ├ partial → SessionStore.volatileText (shown dimmed in the recognition pane)
        └ final  → finalized into SessionStore.segments → TranslationCoordinator queue
            └ TranslationSession inside the .translationTask closure translates sequentially
                └ SessionStore.applyTranslation → shown in the translation pane
```

| File | Responsibility |
|---|---|
| `Models/SessionStore.swift` | Single source of truth for the UI. Segment history, partials, dedup |
| `Models/KeywordParser.swift` | Parses the technical terms field + event presets |
| `Models/LanguageCatalog.swift` | Language display names and target candidate filtering |
| `Services/AudioCaptureService.swift` | Microphone input, format conversion, permission requests |
| `Services/SpeechTranscriptionService.swift` | SpeechAnalyzer / SpeechTranscriber wiring |
| `Services/TranslationCoordinator.swift` | Translation queue (ID dedup + AsyncStream) |
| `Services/ModelAvailabilityService.swift` | Availability checks and model downloads at launch |
| `Export/MarkdownExporter.swift` | Markdown generation (pure function) |
