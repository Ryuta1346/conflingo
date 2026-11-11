---
title: ConfLingo Usage Guide
created: 2026-06-10
updated: 2026-11-09
status: active
type: user-guide
---

# ConfLingo Usage Guide

**English** | [日本語](usage.ja.md)

Conference transcribes microphone input and displays source text with translations. Choose recognition and target languages supported on your Mac; the default is English → Japanese. Requires macOS 26 or later and Apple Silicon. UI labels below match the current Japanese interface.

## Meeting transcription

1. Open **会議を開く** (Open meeting) on Home or select **Meeting**.
2. Enter a name, choose Japanese or English independently for the microphone and system audio, and confirm that participants have been notified and have consented. The checkbox does not send notifications.
3. Select **会議を開始** (Start meeting). The app prepares recognition models and checks input permissions. System audio may include other playback on your Mac; headphones are recommended.
4. **一時停止** (Pause) stops both inputs; **再開** (Resume) preserves the same meeting and transcript. Preparation can be cancelled. If stopping fails, select **停止を再試行** (Retry stop).
5. **会議を終了** (End meeting) waits for inputs to stop and final results to arrive before opening Review.

The timeline identifies input sources, not individual participants. Reading older speech suspends automatic scrolling; **最新へ** returns to the latest speech. Text size and appearance are shared with Conference.

**小さく表示** hides the main window and opens the floating panel. **展開** restores the main window. Hiding or closing the panel does not stop capture. Restore it through **Window → Meetingの小窓を表示**. Use Pause or End to stop capture. The panel is not guaranteed to be excluded from screen sharing.

Transcripts remain in memory until the app exits. Audio files and transcripts are not saved automatically. AI requests require explicit permission for each meeting. Candidate confirmation/rejection and Meeting save/export are not available yet. Text can be selected and copied. Starting a new meeting asks before discarding existing speech. Conference Markdown export is a separate feature.

### Meeting AI assistance (Gemini)

1. Register your own Gemini API key in Settings or **APIキー設定**. It is stored in this Mac's Keychain. Replacing or deleting the key revokes AI sharing permission.
2. Review the data-sharing explanation and Google's data terms, then enable **確定発話と質問文のGeminiへの送信を許可** for this meeting. Check your own Google project's free/paid data terms.
3. During capture, enter a question and choose **Ask AI**. The request includes your question and up to 30 recent final utterances (12,000 characters total), including earlier utterances from before permission was granted. Audio and documents are not sent. Evidence links open the original utterance. Suggestions remain unconfirmed candidates.
4. Automatic suggestions start off for each meeting. Enable them only when needed: at most twice per minute, at least 12 seconds apart, using post-permission speech. This creates additional API usage.
5. **AI送信を停止** stops AI in either window without stopping capture. Pause, End, and input failures also cancel AI work. Cancellation cannot retract data already sent or charges already incurred.

The model is Gemini 3.8 Flash, billed to your API project. Errors are not retried automatically and turn automatic suggestions off; retry manually after checking the connection or key. Local transcripts continue on AI failures. Other providers, managed AI, and subscription-based authentication are future work.

Real-audio acceptance remains postponed. See the [validation record](validation/pr6-insights.md) for the opt-in synthetic-text Gemini evaluation after registering a key.

If the AI status asks you to pause and resume the meeting, automatic suggestions cannot be enabled until recovery. Pause and resume the meeting, then enable automatic suggestions again. Local transcripts and manual Ask AI remain available while automatic suggestions are unavailable.


Acceptance tests with real Zoom/Meet/Teams audio remain deferred. See the [PR5-C validation record](validation/pr5-c-meeting.md) for automated and non-recording checks.

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

## Repository context in Meeting

In Meeting preparation, open **資料 → リポジトリを追加** and select a local working folder. Review the source, tests, and documents, exclude files or directories, then import. Hidden files, dependencies, generated output, and known credential files are excluded. Full `.gitignore` semantics and detection of secrets embedded in source are not provided.

One repository per meeting supports up to 1,000 files, five million characters, and 20 MiB; each file is limited to 1 MiB and 100,000 characters. Ordinary Markdown/Text documents retain their separate limits. Import and local search send nothing externally.

Manual questions require both meeting AI and document permission; at most five matching excerpts / 6,000 characters plus their names and locations are sent to Gemini. Automatic suggestions can use the same material when **自動提案にも資料を使う** is enabled in AI settings. This defaults off and is independent of manual and summary permissions. The triggering final utterance searches for up to five excerpts / 6,000 characters. No matches means transcript-only generation; a search failure sends nothing and disables automatic suggestions. The existing two-per-minute and 12-second minimum interval remain, with one 30-second deadline covering search and generation. A manual question preempts automatic work. Input token usage may increase. After the meeting, select **この要約では資料も参照する** in summary confirmation to review excerpts and request counts before sending. This choice is independent of the live meeting permission and defaults to transcript only.

Summary output separates spoken content from document/implementation supplements. Citations open the imported snapshot with relative paths, line numbers, and content hashes, and are included in Markdown export. A working-tree snapshot is not a verified Git commit or deployed state. Original files are unchanged; imported material is discarded with the meeting or app exit. Existing answer citations remain until meeting disposal even after a source is removed.

Search uses words, paths, and split identifiers. It does not guarantee cross-language semantic retrieval or complete understanding of dependencies across files.
