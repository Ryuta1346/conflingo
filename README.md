# ConfLingo

英語カンファレンス会場で、MacBook のマイク音声を Apple/macOS 組み込み API でリアルタイム文字起こしし、日本語翻訳字幕として表示する自分用 macOS アプリ。

- 文字起こし: `Speech.framework`（macOS 26 の `SpeechAnalyzer` / `SpeechTranscriber`、オンデバイス）
- 翻訳: `Translation.framework`（`TranslationSession`、オンデバイス）
- UI: SwiftUI 2ペイン（英語原文 / 日本語訳）

📖 **詳しい使い方（専門用語の登録方法・当日の Tips・トラブルシューティング）は [docs/usage.md](docs/usage.md) を参照。**

## 動作要件

- macOS 26.0 以降 / Apple Silicon
- Xcode 26 以降（ビルドに使用）
- 初回のみ: 英語音声認識モデルと英→日翻訳モデルのダウンロードにネットワーク接続が必要

## ビルドと起動

```sh
# ビルド
xcodebuild -project ConfLingo.xcodeproj -scheme ConfLingo -configuration Debug build

# 起動（DerivedData 配下に生成された .app を開く）
open ~/Library/Developer/Xcode/DerivedData/ConfLingo-*/Build/Products/Debug/ConfLingo.app
```

テスト実行:

```sh
xcodebuild test -project ConfLingo.xcodeproj -scheme ConfLingo -destination 'platform=macOS'
```

## 権限許可

1. **マイク**: 初回の Start 押下時にマイク使用許可ダイアログが表示される。許可しないと文字起こしできない
2. **音声認識モデル**: 初回起動時に英語認識モデルが未インストールの場合、自動でダウンロードが始まる（進捗表示あり）
3. **翻訳モデル**: 英→日翻訳モデルが未インストールの場合、OS 標準のダウンロード確認ダイアログが表示される

マイク許可をやり直したい場合:

```sh
tccutil reset Microphone com.gavrri.conflingo
```

許可を拒否してしまった場合は「システム設定 > プライバシーとセキュリティ > マイク」で ConfLingo を有効にする。

## 使い方

1. アプリを起動（初回はモデルの確認・ダウンロードが走る）
2. 必要ならセッション名を入力
3. **専門用語欄**にイベント固有の用語（登壇者名・製品名・技術用語）をカンマ区切りで入力。Start 時に音声認識の contextual strings として登録され、固有名詞の認識精度が上がる（デフォルトで Code with Claude Tokyo 向け用語をプリセット済み。変更は次回 Start から反映）
4. **Start**（⌘R）で文字起こし開始
   - 英語ペイン: 認識途中の文（partial）は薄く斜体で表示され、確定すると履歴に積まれる
   - 日本語ペイン: 確定した英文のみ翻訳され、確定文単位で履歴に積まれる
5. **Stop**（⌘R）で停止。Start で再開すると履歴に追記される
6. **Save Markdown** でセッション全体を Markdown 保存
7. **A− / A＋**（⌘− / ⌘+）でフォントサイズ調整、「最前面」チェックでウィンドウを常に手前に表示
8. **Clear** で履歴を破棄（停止中のみ）

## 制限事項

- 会場音は MacBook 内蔵マイクで拾う前提。Zoom / YouTube などの Mac 内部音声（システム音声）はキャプチャできない
- 認識途中の文（partial）は翻訳しない設計（訳揺れ防止）。翻訳は確定文単位で 2〜5 秒程度遅延する
- 話者分離・要約・録音保存は非対応
- 配布用の署名・notarize はしていない（ローカルビルドでの自分用利用前提）
- 認識精度はマイク位置・周囲ノイズの影響が大きい。MacBook をスピーカー方向へ向け、可能なら前方席を推奨

## アーキテクチャ

```
AVAudioEngine マイク入力（ハードウェアフォーマット）
  └ AVAudioConverter で SpeechAnalyzer 推奨フォーマットへ変換
    └ AsyncStream<AnalyzerInput> → SpeechAnalyzer / SpeechTranscriber（en-US, volatileResults）
        ├ partial → SessionStore.volatileText（英語ペインに薄く表示）
        └ final  → SessionStore.segments に確定 → TranslationCoordinator のキューへ
            └ .translationTask クロージャ内の TranslationSession が逐次翻訳
                └ SessionStore.applyTranslation → 日本語ペインに表示
```

| ファイル | 責務 |
|---|---|
| `Models/SessionStore.swift` | UI の単一情報源。セグメント履歴・partial・重複排除 |
| `Models/KeywordParser.swift` | 専門用語欄のパース + イベント用プリセット |
| `Services/AudioCaptureService.swift` | マイク入力・フォーマット変換・権限要求 |
| `Services/SpeechTranscriptionService.swift` | SpeechAnalyzer / SpeechTranscriber 配線 |
| `Services/TranslationCoordinator.swift` | 翻訳キュー（ID dedup + AsyncStream） |
| `Services/ModelAvailabilityService.swift` | 起動時の利用可能性チェック・モデル DL |
| `Export/MarkdownExporter.swift` | Markdown 生成（純関数） |
