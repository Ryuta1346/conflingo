---
title: ConfLingo — Apple API版カンファレンス字幕翻訳MVP
created: 2026-06-10
updated: 2026-06-10
status: active
type: product-design
---

# ConfLingo — Apple API版カンファレンス字幕翻訳MVP

## 0. 仮サービス名

**ConfLingo**

Conference + Lingo。英語カンファレンス会場で、流れていく登壇音声を自分の理解可能な字幕に変えるMacアプリ、という意味の仮称。

候補の中では、短く、カンファレンス用途と多言語/翻訳用途の両方が伝わりやすいため、現時点の作業名として採用する。

## 1. 一言で

**ConfLingoは、英語カンファレンス会場で、MacBookのマイク音声をApple/macOS組み込みAPIでリアルタイム文字起こしし、日本語翻訳字幕として表示する自分用Macアプリ。**

Kanaryのようなlocal-first / Apple API寄せの方向性を参考にする。ただし、Kanary完全再現ではなく、最初の実用機能は以下に絞る。

- 英語リアルタイム文字起こし
- 日本語リアルタイム翻訳
- 英語原文 + 日本語訳の表示
- セッション履歴の保存

録音管理、要約、会議AI、課金、配布、notarize、メニューバー化、システム音声キャプチャは初期MVPから外す。

## 2. 背景

英語カンファレンス参加時に、登壇内容をその場で追いやすくするための即席アプリを作りたい。既存プロダクトとしてKanaryを参考にしたところ、KanaryはApple/macOS組み込みAPIをかなり使っている可能性が高い。

確認・推定されたKanary関連framework / 権限:

- `Speech.framework`
- `Translation.framework`
- `FoundationModels.framework`
- `AVAudio...`
- `NSSpeechRecognitionUsageDescription`
- `NSAudioCaptureUsageDescription`
- `NSMicrophoneUsageDescription`

Kanary公式の方向性としても、デバイス上での文字起こし・Mac上だけでの録音/文字起こし・local-first保存が示されており、今回のMVPもこの思想に寄せる。

## 3. 前提・決定事項

### 決定済み

- **MacBook上で動かすSwiftUI macOSアプリ**として作る。
- **会場音をMacBookのマイクで拾う**。
- macOSバージョンは問題ない前提。
- Kanary完全再現は不要。
- Claude Codeオンリーで実装する前提。
- 最短で使える実用品を重視する。

### 明示的に不要

- Zoom / YouTube / 配信音声などのMac内部音声取得
- `ScreenCaptureKit` によるsystem audio capture
- BlackHole等の仮想オーディオデバイス
- 録音管理
- AI要約
- 話者分離
- 配布、署名、notarize
- 課金
- メニューバー常駐
- 複数入力デバイス対応

## 4. MVP構成

```text
SwiftUI macOS app
  ↓
AVAudioEngineでMacBookマイク入力
  ↓
Speech.frameworkで英語音声認識
  ↓
英語リアルタイム文字起こし
  ↓
Translation.frameworkで英語→日本語翻訳
  ↓
SwiftUIで英語原文 + 日本語訳を2ペイン表示
  ↓
セッション終了時にMarkdown保存
```

## 5. MVP機能

### 必須

- Start / Stop
- MacBookマイク入力
- 英語リアルタイム文字起こし
- 日本語リアルタイム翻訳
- 英語原文ペイン
- 日本語訳ペイン
- 直近の字幕履歴
- セッション終了時のMarkdown / txt保存
- microphone / speech recognition permission説明をInfo.plistに設定
- 起動時に英語音声認識と英日翻訳が利用可能かチェック
- READMEに起動方法・権限許可・制限を記載
- `xcodebuild` でビルド確認

### あるとよい

- フォントサイズ調整
- always-on-top window
- セッション名
- partial transcriptを薄く表示
- final transcriptだけ翻訳して履歴化

## 6. UIイメージ

```text
┌──────────────────────────────────────┐
│ English transcript                    │
│ The speaker is explaining how...      │
├──────────────────────────────────────┤
│ 日本語翻訳                            │
│ 登壇者は〜について説明している...       │
└──────────────────────────────────────┘

[Start] [Stop] [Save Markdown] [Font -] [Font +]
```

会場利用では、UIは派手にせず、読む負荷が低い字幕ウィンドウでよい。

## 7. 実装方針

### 音声入力

- `AVAudioEngine`
- `AVAudioInputNode`
- MacBook内蔵マイクを前提にする。
- カンファレンス会場では、物理的なマイク位置・席・周囲ノイズの影響が大きい。

### 文字起こし

候補:

- `Speech.framework`
- `SFSpeechRecognizer`
- 可能なら新しい `SpeechAnalyzer` / `SpeechTranscriber` 系APIも検証

基本挙動:

- partial transcript: 英語ペインに表示
- final transcript: セグメントとして確定し、翻訳へ渡す

### 翻訳

- `Translation.framework`
- `TranslationSession`
- 英語 → 日本語

途中結果を逐次翻訳すると訳が揺れるため、**確定英文だけ翻訳する**。

### 保存

セッション終了時に、以下のMarkdownを保存する。

```markdown
# Conference Live Translator Session

- Date:
- Source language: en-US
- Target language: ja-JP

## Transcript

### Segment 1

English:
...

Japanese:
...
```

## 8. 開発フェーズ

### Phase 1: マイク入力 + 文字起こし

- SwiftUI app作成
- microphone permission
- speech recognition permission
- 英語音声を逐次文字起こし
- 原文を画面表示

目安: **0.5〜1日**

### Phase 2: 翻訳

- transcription segmentを受け取る
- 確定した英文だけTranslation frameworkへ渡す
- 日本語訳を画面表示
- 重複翻訳を避ける

目安: **0.5〜1日**

### Phase 3: 実用化

- Start / Stop
- 履歴保存
- Markdown export
- フォントサイズ調整
- always-on-top window
- セッション名

目安: **0.5〜1日**

### Phase 4: システム音声取得（今回は後回し）

Zoom / YouTube / 配信音声を拾いたくなった場合のみ検討する。

- `ScreenCaptureKit`
- `SCStream`
- system audio capture permission
- マイク/システム音声切替

目安: **1〜3日**

## 9. 見積もり

会場音をMacBookマイクで拾う前提なら、かなり短い。

| 範囲 | 目安 |
|---|---:|
| 最小MVP | 0.5〜1日 |
| 実用調整込み | 1〜2日 |
| 見た目・保存・安定化込み | 2〜3日 |
| システム音声対応込み | 2〜4日 |

現時点の判断としては、**今日中にMVPを作って試せる可能性が高い**。

## 10. Claude Codeへの初期プロンプト

```text
macOS 26+ / Apple Silicon向けに、英語カンファレンス用のリアルタイム文字起こし・翻訳アプリを作ってください。

前提:
- 会場音をMacBook内蔵マイクで拾う
- システム音声キャプチャは不要
- KanaryのようにApple/macOS組み込みAPIを使う
- 自分用ローカルMVPでよい
- 配布、課金、notarize、メニューバー化は不要

要件:
- SwiftUI macOS app
- AVAudioEngineでマイク入力を取得
- Speech.frameworkで英語音声をリアルタイム文字起こし
- Translation.frameworkで英語→日本語に逐次翻訳
- 英語原文と日本語訳を2ペイン表示
- Start / Stopボタン
- 直近の字幕履歴を表示
- フォントサイズ調整
- セッション終了時にMarkdown保存
- Info.plistにmicrophone / speech recognition permission説明を入れる
- 起動時に英語音声認識と英日翻訳が利用可能かチェックする
- xcodebuildでビルド確認する
- READMEに起動方法、権限許可、制限を書く
```

## 11. 実装上の注意

### 翻訳は「確定文」単位にする

音声認識の途中結果を毎回翻訳すると、翻訳が揺れて読みにくい。

おすすめ:

- partial transcript: 英語ペインに薄く表示
- final transcript: 日本語翻訳して履歴に追加

### 遅延は2〜5秒でよい

カンファレンス用途では、完全な同時通訳より以下を優先する。

- 文が崩れない
- 意味が追える
- 重要語が落ちない
- 表示が落ち着いて読める

### マイク位置が重要

会場音を拾う場合、実装より物理環境の影響が大きい。

- MacBookをスピーカー方向に向ける
- 可能なら前方席
- 周囲の会話を避ける
- ノイズキャンセリング系設定が邪魔する可能性がある
- AirPodsマイクよりMacBook内蔵マイクの方が会場音には向くことが多い

## 12. Go判断

バージョン制約が問題なく、会場音をマイクで拾うなら、**Kanary寄せのApple API版で進めてよい**。

最初のゴール:

> SwiftUIで、MacBookマイクの英語音声をSpeech.frameworkで文字起こしし、Translation.frameworkで日本語にして、2ペイン字幕として表示する。

システム音声対応は不要。まず会場用の字幕翻訳MVPとして作り、実地で音質・遅延・翻訳品質を確認する。

