---
title: ConfLingo Usage Guide
created: 2026-06-10
updated: 2026-11-08
status: active
type: user-guide
---

# ConfLingo Usage Guide

**English** | [日本語](usage.ja.md)

Conference transcribes microphone input and displays source text with translations. Choose recognition and target languages supported on your Mac; the default is English → Japanese. Requires macOS 26 or later and Apple Silicon. UI labels below match the current Japanese interface.

## Launch and prepare

```sh
xcodebuild -project ConfLingo.xcodeproj -scheme ConfLingo -configuration Debug build
open ~/Library/Developer/Xcode/DerivedData/ConfLingo-*/Build/Products/Debug/ConfLingo.app
```

1. Select **字幕を準備する** (Prepare subtitles) on Home, or open Conference.
2. Enter a session name and select recognition language, target language, and dictionary.
3. Once the recognition model is ready, select **字幕を開始** (Start subtitles). Allow microphone access on first use.

The app checks language availability at launch and when settings change, downloading recognition models when needed. macOS may also request a translation model download. Prepare with a network connection before attending an event. Unsupported languages or preparation failures are shown in the preparation screen; change settings or select **もう一度確認** (Check again).

Recognition-model readiness does not guarantee that translation-model downloads are complete. Once the required models are installed, recognition and translation run on your Mac.

## Read subtitles

Source and translation appear side by side in wide windows and vertically in narrow windows. Transcription-only mode shows one source pane.

- **認識中** marks partial recognition that may change.
- Translation groups finalized speech into sentences; source and translation rows may not align one to one.
- **翻訳待ち** means waiting for translation; **翻訳失敗** marks a failed translation. Source text remains available.
- Scrolling back pauses automatic following in that pane. **最新へ** (Latest) resumes following.
- Select text to copy it. Captions with timing information show their start time.

## Controls

| Action | Control |
|---|---|
| Start / stop | Bottom **字幕を開始／再開** / **停止する**, or ⌘R |
| Retry failed stop | **停止を再試行**; navigation and clearing remain blocked until stopping succeeds |
| Change session settings | **字幕の設定**; during listening, confirm stopping before navigation |
| Font size | Top A− / A＋, ⌘− / ⌘＋, or Settings; 10–48 pt |
| Keep window on top | **最前面**, or Settings |
| Appearance | Settings → **配色**: System, Light, Dark |
| Export Markdown | Top **書き出す**; choose a file name and destination |
| Clear subtitles | **字幕を消去** while stopped, then confirm; cancel preserves content |

Stopping and navigation preserve current subtitles. Restarting appends to them. Closing the window while listening asks to stop first; closing is blocked during start/stop operations. Export anything needed before quitting the app.

## Languages and transcription-only mode

Change languages, dictionaries, and modes while stopped. If source and target become the same language, the target switches automatically. Supported pairs depend on runtime availability checks.

**文字起こしのみ** disables translation. This mode also offers **高速確定**, which prioritizes subtitle speed over recognition accuracy.

Changing languages preserves existing text. Markdown records the language settings at export time, so export and clear before changing languages if you want separate files.

## Technical-term dictionaries

Open **辞書を管理** from preparation or Settings. Create, select, duplicate, rename, or delete dictionaries. The final dictionary cannot be deleted.

Separate terms with commas, Japanese commas, or newlines. Use `evals=評価` to specify a translation. Terms without a translation are protected to preserve their spelling. Terms also provide recognition hints; correct recognition and translation are not guaranteed.

```text
ConfLingo
Model Context Protocol
evals=評価
```

Edits save automatically and apply at the next start. Empty content means no glossary terms. Dictionaries persist across app restarts.

## Export and data

Subtitles are not saved automatically. **書き出す** exports finalized source text and translations as Markdown. The default file name is `<session name>-<datetime>.md`. Untranslated content is marked `(untranslated)`; available timestamps are included. Partial recognition is not finalized transcript content.

Cancelling the save dialog or encountering a write failure preserves subtitles. Clearing subtitles does not delete exported files. The app does not save audio files.

## Troubleshooting

| Symptom | Check |
|---|---|
| Cannot start | Read preparation status and the error banner. For denied microphone access, check System Settings → Privacy & Security → Microphone |
| Missing translation | Check transcription-only mode, translation-model download, and translation failure labels |
| Poor recognition | Check the input microphone, background noise, distance, and technical-term dictionary |
| Stop remains unconfirmed | Select **停止を再試行**; the app preserves captions and input state while retrying |

Conference uses microphone input. System audio and dual-input transcription currently live in separate validation windows under the Window menu. Meeting, session history, and AI summaries are not yet available in the Conference interface.

See [README](../README.md#distribution) for distribution builds and [PR5-B validation](validation/pr5-b-conference.md) for the verification scope.
