---
title: ConfLingo Usage Guide
created: 2026-06-10
updated: 2026-06-10
status: active
type: user-guide
related:
  - "[[mvp]]"
---

# ConfLingo Usage Guide

**English** | [日本語](usage.ja.md)

A usage guide for the app that transcribes conference talk audio in real time via the MacBook microphone and displays it as translated subtitles. The recognition language and target language can be freely chosen (default: English → Japanese).

## 1. Launch

```sh
# Build (first time and after code changes only)
xcodebuild -project ConfLingo.xcodeproj -scheme ConfLingo -configuration Debug build

# Launch
open ~/Library/Developer/Xcode/DerivedData/ConfLingo-*/Build/Products/Debug/ConfLingo.app
```

Once launched, you can also start it from Spotlight (⌘Space → "ConfLingo") or the Dock.

## 2. First-time setup

The following happens automatically at first launch. **Launch the app once at home or anywhere with a stable network before going to the venue.**

| Step | What happens | Action |
|---|---|---|
| Recognition model | Downloads automatically if not installed (several hundred MB) | Just wait (progress bar shown) |
| Translation model | If not installed, an OS dialog appears after the first Start | Press "Download" |
| Microphone permission | A dialog appears on the first Start | Press "Allow" |

Once the model downloads are complete, **the app works fully offline** (no venue Wi-Fi needed).

## 3. Understanding the screen

```
┌──────────────────────────────────────┐
│ English (United States) (recognition)│  ← Top pane: source text (selected recognition language)
│ The speaker is explaining how...      │     Finalized sentences (solid color)
│ and now we are going to ...           │     In-progress sentences (dimmed italic, may change)
├──────────────────────────────────────┤
│ Japanese (translation)                │  ← Bottom pane: translation (selected target language)
│ 登壇者は〜について説明している。       │     Only finalized sentences are translated (2–5 s delay)
│ …translating                          │
├──────────────────────────────────────┤
│ [Recognition ▾] → [Target ▾]         │  ← Language selection (§4.5)
│ 🔍 [Technical terms (comma-sep)...]  │  ← Technical terms field (§5)
│ [Session name] [Start] [Save Markdown]│  ← Control bar
│ [Clear]        [On top] [A−] [A＋]   │
└──────────────────────────────────────┘
```

- **Dimmed italic text** is an in-progress (partial) recognition and may change. Once finalized, it turns solid and is appended to the history, at which point translation begins
- The translation intentionally lags by a few seconds to **avoid unstable translations** (translating in-progress sentences would make the output flip back and forth and hard to read)
- Both panes auto-scroll to the bottom when new subtitles arrive

## 4. Basic operations

| Operation | How | Notes |
|---|---|---|
| Start transcription | **Start** button or ⌘R | Microphone permission dialog on first use |
| Stop | **Stop** button or ⌘R | Pressing Start again appends to the history |
| Session name | Type into the left text field | Used for the saved file name and the Markdown heading |
| Save Markdown | **Save Markdown** button | Opens a save dialog |
| Discard history | **Clear** button | Only while stopped. Cannot be undone |
| Font size | **A−** / **A＋** or ⌘− / ⌘+ | 10–48 pt |
| Always on top | "On top" checkbox | Handy when used side by side with a notes app |

## 4.5 Switching languages

The two pickers at the top of the control bar let you **freely choose the recognition language (= translation source) and the target language**.

- **Recognition language**: choose from all languages supported by macOS speech recognition (English, Japanese, Chinese, Korean, Spanish, French, German, etc.)
- **Target language**: choose from all languages supported by Apple Translation (the same language as the recognition language is automatically excluded from the options)
- Any combination works (e.g., Chinese → Japanese, Japanese → English, English → Korean)

Behavioral notes:

- **Languages can only be changed while stopped (idle)**. The pickers are grayed out while listening
- Changing a language automatically triggers an availability check; if the recognition model for that language is not installed, the download starts (**network required the first time**). For the translation model, the OS download confirmation appears at the next Start
- If changing the recognition language makes it collide with the target language, the target is switched automatically (Japanese ⇔ English)
- Switching languages **keeps the existing subtitle history**. The Markdown header records the language pair at save time, so if you want to organize per language, Save → Clear before switching is recommended
- If you choose a pair this Mac cannot translate, "translation to ... is not available on this Mac" is shown and you cannot Start
- The default technical-term preset targets English-language events. **If you set the recognition language to something other than English, rewrite the technical terms field yourself** (§5)

## 5. Adding and editing technical terms

### What this feature is for

Speech recognition is optimized for general English, so `Claude Code` may come out as "cloud code" and `MCP` as "M C P" or another word. **Terms registered in the technical terms field are passed to the recognition engine as hints that these words are likely to appear (contextual strings), greatly improving recognition of proper nouns, abbreviations, and personal names.**

### How to edit

1. The text field with the 🔍 icon above the control bar is the technical terms field
2. Enter terms separated by **commas (`,` or `、`) or newlines**
   ```
   Claude Code, MCP, sub-agent, Cat Wu, primeNumber
   ```
3. Leading/trailing whitespace is removed automatically, and duplicates differing only in case are merged
4. **Changes take effect at the next Start**. The field is grayed out while listening, so Stop → edit → Start to change it
5. The content is saved automatically and persists across app restarts

### Default preset

By default, **about 40 terms for Code with Claude Tokyo Extended (2026-06-11)** are registered:

> Claude, Claude Code, Anthropic, Opus, Sonnet, Haiku, Fable, MCP, Model Context Protocol, sub-agent, subagents, orchestrator, Managed Agents, Agent SDK, Routines, agentic, multi-agent, evals, evaluation, Constitutional AI, system prompt, prompt engineering, context window, tool use, function calling, hooks, slash command, plugin, skill, RAG, fine-tuning, token, LLM, API key, rate limit, workflow, Bedrock, Vertex AI, primeNumber

### Tips for effective registration

- **Add speaker and company names**: adding speaker names (e.g., `Cat Wu`, `Ami Vora`) before a session stabilizes name recognition
- **Add session-specific terms**: check the agenda and add product/tool names in advance
- **Keep it to roughly 40–60 terms**: too many dilutes the effect. Feel free to remove terms from finished sessions
- **Register compound terms as-is**: whole phrases like `Model Context Protocol` can be registered
- Terms in the target language are unnecessary (only the recognized speech is matched)

### Reset to the preset / clear everything

- Leaving the field empty means "no terms registered" (not an error)
- To restore the initial preset, quit the app and run in Terminal:
  ```sh
  defaults delete com.gavrri.conflingo contextKeywords
  ```
  The preset is re-populated at the next launch

## 6. Markdown export format

After Stop (or even mid-session), **Save Markdown** saves in the following format. Untranslated segments are marked `(untranslated)`.

```markdown
# ConfLingo Session: <session name>

- Date: 2026-06-11 10:30
- Source language: en-US
- Target language: ja
- Segments: 42

## Transcript

### Segment 1

English:
Hello everyone, welcome to the conference.

Japanese:
皆さんこんにちは、カンファレンスへようこそ。
```

The default file name is `<session name>-<datetime>.md`.

## 7. Practical tips for conference day

1. **Launch the app at least once the day before** to finish the model downloads and microphone permission
2. **Point the MacBook toward the speakers (the presenter)**. Sit near the front if possible
3. Even with AirPods on, **the built-in MacBook microphone is used by design** (it is better suited for venue audio)
4. Before the session starts, **enter the session name and speaker names (technical terms field)** → Start
5. Securing a power outlet is recommended (continuous recognition drains the battery)
6. After each session, **Stop → Save Markdown**, then **Clear** to keep things organized

## 8. Troubleshooting

| Symptom | Fix |
|---|---|
| An error banner appears when pressing Start | Follow the banner's instructions. If the microphone was denied, enable ConfLingo under System Settings > Privacy & Security > Microphone |
| The microphone permission dialog does not appear | Reset the permission with `tccutil reset Microphone com.gavrri.conflingo` and relaunch |
| The "unavailable" screen appears | Check that the Mac runs macOS 26 or later and supports the selected recognition/translation languages |
| Only the translation is missing | The translation model may not be downloaded. Relaunch the app with a network connection and press "Download" in the dialog |
| Poor recognition accuracy | Reconsider the microphone position (§7). Register misrecognized proper nouns in the technical terms field (§5) |
| Inspect runtime logs | `log show --last 5m --predicate 'subsystem == "com.gavrri.conflingo"'` |

## 9. Installing from a zip received from a friend

If you received `ConfLingo-1.0.zip` via AirDrop etc.:

1. Double-click the zip to extract, then move `ConfLingo.app` to the Applications folder or similar
2. Double-clicking shows **"cannot be opened because the developer cannot be verified"** (expected behavior for a personal build)
3. Open **System Settings > Privacy & Security** and click **"Open Anyway"** near the bottom
4. After that it launches normally

Requirements and first-time setup:

- **macOS 26 or later + Apple Silicon** is required
- The first launch downloads the recognition and translation models (several hundred MB), so **a network connection is required**. If the venue Wi-Fi is unreliable, launch the app as soon as you receive it
- Press "Allow" in the microphone permission dialog at the first Start

For how to create the distribution zip (the builder's steps), see the ["Distribution" section of the README](../README.md#distribution).

## 10. Known limitations

- Language and technical-term changes are only possible while stopped (not applied while listening; effective from the next Start)
- Internal Mac audio such as Zoom / YouTube cannot be captured (microphone input only)
- Speaker diarization, summarization, and audio recording are not supported
- Translatable language pairs depend on what Apple Translation supports (unsupported pairs show an error)
