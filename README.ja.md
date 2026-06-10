# ConfLingo

[English](README.md) | **日本語** | [简体中文](README.zh-CN.md) | [한국어](README.ko.md) | [Español](README.es.md)

カンファレンス会場で、MacBook のマイク音声を Apple/macOS 組み込み API でリアルタイム文字起こしし、翻訳字幕として表示する自分用 macOS アプリ。認識言語・翻訳先言語は OS が対応する言語から自由に選択できる（デフォルト: 英語 → 日本語）。

- 文字起こし: `Speech.framework`（macOS 26 の `SpeechAnalyzer` / `SpeechTranscriber`、オンデバイス）
- 翻訳: `Translation.framework`（`TranslationSession`、オンデバイス）
- UI: SwiftUI 2ペイン（英語原文 / 日本語訳）

📖 **詳しい使い方（専門用語の登録方法・当日の Tips・トラブルシューティング）は [docs/usage.ja.md](docs/usage.ja.md) を参照。**

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
2. **言語 Picker** で認識言語と翻訳先言語を選択（停止中のみ変更可。変更すると利用可能性チェックとモデルダウンロードが自動で走る）
3. 必要ならセッション名を入力
4. **専門用語欄**にイベント固有の用語（登壇者名・製品名・技術用語）をカンマ区切りで入力。Start 時に音声認識の contextual strings として登録され、固有名詞の認識精度が上がる（デフォルトで Code with Claude Tokyo 向け用語をプリセット済み。変更は次回 Start から反映）
5. **Start**（⌘R）で文字起こし開始
   - 認識ペイン: 認識途中の文（partial）は薄く斜体で表示され、確定すると履歴に積まれる
   - 翻訳ペイン: 確定した原文のみ翻訳され、確定文単位で履歴に積まれる
6. **Stop**（⌘R）で停止。Start で再開すると履歴に追記される
7. **Save Markdown** でセッション全体を Markdown 保存
8. **A− / A＋**（⌘− / ⌘+）でフォントサイズ調整、「最前面」チェックでウィンドウを常に手前に表示
9. **Clear** で履歴を破棄（停止中のみ）

## 配布

### 方法A: ソース共有（Xcode を持つ開発者向け・推奨）

リポジトリの URL を渡し、相手に以下を実行してもらう。Gatekeeper の警告は出ない。

```sh
git clone <リポジトリURL> && cd conflingo
xcodebuild -project ConfLingo.xcodeproj -scheme ConfLingo build
open ~/Library/Developer/Xcode/DerivedData/ConfLingo-*/Build/Products/Debug/ConfLingo.app
```

### 方法B: Release ビルドの zip を AirDrop

```sh
# 1. Release ビルド（出力先を build/ に固定）
xcodebuild -project ConfLingo.xcodeproj -scheme ConfLingo \
  -configuration Release -derivedDataPath build build

# 2. ditto で zip 化（zip -r は署名・拡張属性を壊すことがあるので使わない）
ditto -c -k --sequesterRsrc --keepParent \
  build/Build/Products/Release/ConfLingo.app dist/ConfLingo-1.0.zip
```

できた `dist/ConfLingo-1.0.zip` を AirDrop で送る。**アドホック署名（notarize なし）のため、受け取った側は初回起動時に Gatekeeper の解除が必要**:

1. 展開してダブルクリック →「開発元を確認できないため開けません」
2. システム設定 > プライバシーとセキュリティ > 「このまま開く」
3. 以降は普通に起動できる（開発者なら `xattr -dr com.apple.quarantine ConfLingo.app` でも可）

### 共有相手に伝える動作要件

- **macOS 26 以降 + Apple Silicon**（未満の macOS では起動しない）
- **初回はネットワーク必須**: 認識・翻訳モデル（数百MB）を各自の Mac がダウンロードする。会場 Wi-Fi が貧弱な場合に備え、受け取ったらすぐ起動してもらう
- 初回 Start 時にマイク許可ダイアログ →「許可」

## 制限事項

- 会場音は MacBook 内蔵マイクで拾う前提。Zoom / YouTube などの Mac 内部音声（システム音声）はキャプチャできない
- 認識途中の文（partial）は翻訳しない設計（訳揺れ防止）。翻訳は確定文単位で 2〜5 秒程度遅延する
- 言語の変更は停止中のみ。言語を切り替えても既存の字幕履歴は保持される（Markdown ヘッダには保存時点の言語ペアが記録される）
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
| `Models/LanguageCatalog.swift` | 言語の表示名・翻訳先候補の整形 |
| `Services/AudioCaptureService.swift` | マイク入力・フォーマット変換・権限要求 |
| `Services/SpeechTranscriptionService.swift` | SpeechAnalyzer / SpeechTranscriber 配線 |
| `Services/TranslationCoordinator.swift` | 翻訳キュー（ID dedup + AsyncStream） |
| `Services/ModelAvailabilityService.swift` | 起動時の利用可能性チェック・モデル DL |
| `Export/MarkdownExporter.swift` | Markdown 生成（純関数） |
