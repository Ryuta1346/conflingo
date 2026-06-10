---
title: ConfLingo 使い方ガイド
created: 2026-06-10
updated: 2026-06-10
status: active
type: user-guide
related:
  - "[[mvp]]"
---

# ConfLingo 使い方ガイド

英語カンファレンスの登壇音声を、MacBook のマイクでリアルタイムに文字起こしし、日本語字幕として表示するアプリの使い方ガイド。

## 1. 起動

```sh
# ビルド（初回・コード変更後のみ）
xcodebuild -project ConfLingo.xcodeproj -scheme ConfLingo -configuration Debug build

# 起動
open ~/Library/Developer/Xcode/DerivedData/ConfLingo-*/Build/Products/Debug/ConfLingo.app
```

一度起動すれば、以降は Spotlight（⌘Space → "ConfLingo"）や Dock からも起動できる。

## 2. 初回セットアップ

初回起動時に自動で以下が行われる。**会場に行く前に自宅などネットワークが安定した場所で一度起動しておくこと。**

| ステップ | 内容 | 操作 |
|---|---|---|
| 英語認識モデル | 未インストールなら自動ダウンロード（数百MB） | 待つだけ（進捗バー表示） |
| 英→日翻訳モデル | 未インストールなら初回 Start 後に OS のダイアログが出る | 「ダウンロード」を押す |
| マイク許可 | 初回 Start 時にダイアログが出る | 「許可」を押す |

モデルのダウンロードが完了していれば、**以降は完全オフラインで動作する**（会場の Wi-Fi 不要）。

## 3. 画面の見方

```
┌──────────────────────────────────────┐
│ English transcript                    │  ← 上ペイン: 英語原文
│ The speaker is explaining how...      │     確定した文（濃い色）
│ and now we are going to ...           │     認識途中の文（薄い斜体・揺れる）
├──────────────────────────────────────┤
│ 日本語翻訳                            │  ← 下ペイン: 日本語訳
│ 登壇者は〜について説明している。       │     確定文のみ翻訳（2〜5秒遅れ）
│ …翻訳中                               │
├──────────────────────────────────────┤
│ 🔍 [専門用語（カンマ区切り）...]      │  ← 専門用語欄（§5）
│ [セッション名] [Start] [Save Markdown]│  ← コントロールバー
│ [Clear]        [最前面] [A−] [A＋]    │
└──────────────────────────────────────┘
```

- **薄い斜体の英文**は認識途中（partial）で、内容が変わることがある。確定すると濃い色で履歴に積まれ、そのタイミングで翻訳が始まる
- 日本語訳が意図的に数秒遅れるのは**訳揺れ防止**のため（途中の文を翻訳すると訳が二転三転して読みにくい）
- 両ペインとも新しい字幕が来ると自動で最下部にスクロールする

## 4. 基本操作

| 操作 | 方法 | 備考 |
|---|---|---|
| 文字起こし開始 | **Start** ボタン or ⌘R | 初回はマイク許可ダイアログ |
| 停止 | **Stop** ボタン or ⌘R | 停止後 Start で履歴に追記再開 |
| セッション名 | 左端のテキスト欄に入力 | 保存ファイル名と Markdown 見出しに使われる |
| Markdown 保存 | **Save Markdown** ボタン | 保存先を選ぶダイアログが開く |
| 履歴の破棄 | **Clear** ボタン | 停止中のみ押せる。元に戻せないので注意 |
| 文字サイズ | **A−** / **A＋** or ⌘− / ⌘+ | 10〜48pt |
| 最前面表示 | 「最前面」チェックボックス | メモアプリ等と並べて使うときに便利 |

## 5. 専門用語の追加・編集

### 何のための機能か

音声認識は一般的な英語に最適化されているため、`Claude Code` が "cloud code"、`MCP` が "M C P" や別の語に化けることがある。**専門用語欄に登録した語は認識エンジンに「この語が出やすい」とヒントとして渡され（contextual strings）、固有名詞・略語・人名の認識精度が大きく改善する。**

### 編集方法

1. コントロールバーの上にある 🔍 付きテキスト欄が専門用語欄
2. **カンマ（`,` または `、`）か改行区切り**で用語を入力する
   ```
   Claude Code, MCP, sub-agent, Cat Wu, primeNumber
   ```
3. 前後の空白は自動で除去され、大文字小文字だけ違う重複は自動でまとめられる
4. **反映タイミングは次回の Start 時**。リスニング中は欄がグレーアウトして編集できないので、変更したいときは一度 Stop → 編集 → Start する
5. 内容は自動保存され、アプリを再起動しても保持される

### デフォルトのプリセット

初期状態では **Code with Claude Tokyo Extended（2026-06-11）向けの約40語**が登録済み:

> Claude, Claude Code, Anthropic, Opus, Sonnet, Haiku, Fable, MCP, Model Context Protocol, sub-agent, subagents, orchestrator, Managed Agents, Agent SDK, Routines, agentic, multi-agent, evals, evaluation, Constitutional AI, system prompt, prompt engineering, context window, tool use, function calling, hooks, slash command, plugin, skill, RAG, fine-tuning, token, LLM, API key, rate limit, workflow, Bedrock, Vertex AI, primeNumber

### 効果的な登録のコツ

- **登壇者名・社名を足す**: セッション開始前にスピーカー名（例: `Cat Wu`, `Ami Vora`）を追記すると人名の認識が安定する
- **そのセッション固有の語を足す**: アジェンダを見て製品名・ツール名を事前に入れておく
- **数は40〜60語程度まで**: 多すぎると効果が薄まる。終わったセッションの用語は消してよい
- **複合語はそのまま入れる**: `Model Context Protocol` のようにフレーズごと登録できる
- 日本語の用語は不要（認識対象は英語音声のみ）

### プリセットに戻したい / 全部消したい

- 欄を空にすれば「登録なし」で動作する（エラーにはならない）
- 初期プリセットに戻すには、アプリ終了後にターミナルで:
  ```sh
  defaults delete com.gavrri.conflingo contextKeywords
  ```
  次回起動時にプリセットが再投入される

## 6. Markdown 保存の内容

Stop 後（または途中でも）**Save Markdown** で以下の形式で保存される。未翻訳のセグメントは `(untranslated)` と明記される。

```markdown
# ConfLingo Session: <セッション名>

- Date: 2026-06-11 10:30
- Source language: en-US
- Target language: ja-JP
- Segments: 42

## Transcript

### Segment 1

English:
Hello everyone, welcome to the conference.

Japanese:
皆さんこんにちは、カンファレンスへようこそ。
```

デフォルトのファイル名は `<セッション名>-<日時>.md`。

## 7. カンファレンス当日の実践 Tips

1. **前日までに一度起動**してモデルのダウンロードとマイク許可を済ませる
2. **MacBook をスピーカー（登壇者）方向に向ける**。可能なら前方席へ
3. AirPods を着けている場合も**マイクは MacBook 内蔵が使われる設計**（会場音には内蔵マイクの方が向く）
4. セッション開始前に**セッション名と登壇者名（専門用語欄）を入力** → Start
5. 電源確保を推奨（連続認識はバッテリーを消費する）
6. セッション終了ごとに **Stop → Save Markdown** で保存してから **Clear** すると整理しやすい

## 8. トラブルシューティング

| 症状 | 対処 |
|---|---|
| Start を押してもエラーバナーが出る | バナーの指示を確認。マイク拒否済みなら「システム設定 > プライバシーとセキュリティ > マイク」で ConfLingo を ON |
| マイク許可ダイアログが出ない | `tccutil reset Microphone com.gavrri.conflingo` で許可状態をリセットして再起動 |
| 「利用できません」画面になる | macOS 26 以降か、英語認識・英日翻訳対応の Mac かを確認 |
| 日本語訳だけ出ない | 翻訳モデル未ダウンロードの可能性。ネットワーク接続のある状態でアプリを再起動し、ダイアログで「ダウンロード」を押す |
| 認識精度が低い | マイク位置を見直す（§7）。固有名詞の誤認識は専門用語欄に登録（§5） |
| 動作ログを確認したい | `log show --last 5m --predicate 'subsystem == "com.gavrri.conflingo"'` |

## 9. 知り合いから zip で受け取った場合のインストール

AirDrop 等で `ConfLingo-1.0.zip` を受け取った場合:

1. zip をダブルクリックして展開し、`ConfLingo.app` を「アプリケーション」フォルダ等に移動
2. ダブルクリックすると**「開発元を確認できないため開けません」**と出る（個人ビルドのため正常な挙動）
3. **システム設定 > プライバシーとセキュリティ** を開き、下の方に表示される **「このまま開く」** をクリック
4. 以降は普通に起動できる

動作要件と初回セットアップ:

- **macOS 26 以降 + Apple Silicon** が必須
- 初回起動時に認識・翻訳モデル（数百MB）のダウンロードが走るため**ネットワーク接続が必要**。会場 Wi-Fi が不安定なら受け取ってすぐ起動しておく
- 初回 Start 時のマイク許可ダイアログで「許可」を押す

配布用 zip の作り方（ビルドする側の手順）は [README の「配布」セクション](../README.md#配布知り合いに共有する) を参照。

## 10. 既知の制限

- 英語 → 日本語のみ（言語切替 UI なし）
- Zoom / YouTube などの Mac 内部音声は拾えない（マイク経由のみ）
- 話者分離・要約・録音保存は非対応
- 専門用語の変更はリスニング中に反映されない（次回 Start から）
