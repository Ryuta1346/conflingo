# ConfLingo

**English** | [日本語](README.ja.md) | [简体中文](README.zh-CN.md) | [한국어](README.ko.md) | [Español](README.es.md)

A personal macOS app that transcribes MacBook microphone audio in real time at conference venues using Apple's built-in macOS APIs, and displays the result as translated subtitles. The recognition language and target language can be freely chosen from the languages supported by the OS (default: English → Japanese).

- Transcription: `Speech.framework` (`SpeechAnalyzer` / `SpeechTranscriber` on macOS 26, on-device)
- Translation: `Translation.framework` (`TranslationSession`, on-device)
- UI: SwiftUI two-pane layout (source transcript / translated text)

📖 **For detailed usage (registering technical terms, on-site tips, troubleshooting), see [docs/usage.md](docs/usage.md).**

## Saved sessions

After stopping Conference or ending a Meeting, choose **Save on this Mac** (「このMacに保存」). The saved sessions page supports name search, read-only viewing after restarting the app, Markdown export, and deletion. Home shows the five most recently saved sessions.

Saved records include final transcripts, available translations, completed AI cards, candidate review states, completed summaries, and cited document excerpts. Changes require an explicit re-save. Audio, complete source documents, API keys, and AI permissions are not included. There is no autosave or cloud sync. Deleting a saved session leaves exported Markdown and source files intact.

Meeting also supports microphone and system audio transcription, optional AI responses and summaries, and document references. See the [progress tracker](plan.md) for outstanding real-meeting acceptance checks and the [Sessions validation record](docs/validation/sessions.md) for verified behavior. The instructions below primarily describe Conference.

## Assistance in both modes

Conference and Meeting both support registered materials, transcript-plus-document questions, automatic suggestions and manual Web research. Choose microphone/external devices, system audio, or both in setup for in-person or online sessions.

Web research uses the selected Gemini, OpenAI or Claude model’s built-in search and existing LLM credentials; no separate search key is needed. Completed answers and transcript, document and Web citations can be saved and exported as Markdown. See [usage](docs/usage.md#web-research) and [validation and remaining checks](docs/validation/shared-session-assistance.md).

## Meeting translation

Meeting and Conference default to transcription for each new session. Select **リアルタイム翻訳** in setup to enable translation. Meeting initially offers English for the microphone and Japanese for system audio; target choices are remembered separately from the mode. Space is reserved below source text before translations arrive, reducing layout shifts. Translations that exceed the reserved space expand to remain readable. Original text and completed translations are retained, including in the floating panel, saved sessions and Markdown exports. Each input can disable translation. Translation runs on this Mac without an API key; a model download may be needed. Translation failures do not stop transcription. See [validation](docs/validation/meeting-translation.md) for the tested scope.

Meeting protects the original spelling of selected terms during translation. Changes apply when the next utterance starts translating; completed translations stay unchanged. Fixed target translations are not supported in Meeting. If term restoration fails, the original text is translated again, so exact term preservation is not guaranteed.

## Knowledge library

From the knowledge library, or before/during Meeting and Conference, import Markdown/Text or selected repository files, then choose **ライブラリに保存** to explicitly save the document bodies on this Mac. Ordinary documents are saved individually; a repository entry contains the files currently attached to the meeting.

Reuse saved material with **ライブラリから選択**. The library supports browsing, name search, replacement and deletion while preserving existing meeting copies and citations. AI consent is not saved. See the [usage guide](docs/usage.md#knowledge-library).

Conference includes document browsing/search, cited AI questions, reviewed terminology and AI corrections that preserve originals. Recognition and correction quality have not yet been evaluated with real inputs. See the [usage guide](docs/usage.md#add-materials-during-a-session).

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

Lint (SwiftLint 0.65.1):

```sh
swiftlint lint --strict --no-cache
```

See the [Conference baseline](docs/validation/conference-baseline.md) for setup, reproducible checks, and results, and the [audio test procedure](docs/validation/audio-benchmark.md) for fixtures and manual validation (Japanese).

## Permissions

1. **Microphone**: A microphone permission dialog appears the first time you press Start. Required when using the microphone; system-audio-only capture does not request it
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


## Requirements to tell recipients

- **macOS 26 or later + Apple Silicon** (does not launch on earlier macOS versions)
- **Network required on first launch**: each Mac downloads the recognition and translation models (several hundred MB). In case the venue Wi-Fi is weak, ask recipients to launch the app as soon as they receive it
- Microphone permission dialog on first Start → "Allow"

## Limitations

- Both modes support microphone/external devices, system audio, or both; Zoom/Meet/Teams-specific acceptance checks remain outstanding.
- In-progress (partial) sentences are not translated by design (to avoid unstable translations). Translation lags finalized sentences by roughly 2–5 seconds
- Languages can only be changed while stopped. Switching languages keeps the existing subtitle history (the Markdown header records the language pair at save time)
- Speaker identification and audio file recording are not supported. Optional AI summaries are available in Meeting.
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

Meeting supports Gemini, OpenAI, Claude, Kimi, DeepSeek, other OpenAI-compatible clouds, and local models such as Qwen through Ollama / LM Studio. API keys are stored per connection in Keychain. See [setup](docs/usage.md#meeting-ai-assistance-and-llm-selection) and [validation scope](docs/validation/llm-selection.md).
