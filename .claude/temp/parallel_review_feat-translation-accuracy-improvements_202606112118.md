# 並列レビュー結果

**レビュー日時**: 2026-06-11 21:18 JST
**対象ブランチ**: feat/translation-accuracy-improvements
**比較対象**: main
**変更ファイル数**: 16件
**レビューモード**: 並列レビュー (4エージェント、React なし / specialist 0件ヒット)

## 📊 指摘サマリー

| 領域 | 🔴 Must Fix | 🟡 Should Fix | 💡 Consider |
|------|-------------|---------------|-------------|
| コード品質 | 0 | 2 | 3 |
| セキュリティ | 0 | 1 | 2 |
| パフォーマンス | 0 | 2 | 2 |
| テストカバレッジ | 4 | 1 | 1 |
| **合計** | **4** | **6** | **8** |

## 🔴 Must Fix

### [テストカバレッジ] (reviewer-test-coverage)
1. **SpeechTranscriptionService.swift scheduleTranslation()** — 新規メソッド（バッファリング・タイムアウト flush の核）のテストがない
2. **SpeechTranscriptionService.swift bufferFlushTimeout** — タイムアウト機構（4秒）のテストがない
3. **SpeechTranscriptionService.swift SpeechDetector 統合** — VAD モジュール初期化のテストがない
4. **SessionController.swift stop()** — stop 時のバッファ flush ロジックのテストがない（テストファイル自体なし）

## 🟡 Should Fix

### [コード品質] (reviewer-code-quality)
1. **TermProtector.swift claimed タプル** — ラベル付きタプルを named struct 化する提案
2. **SessionStore.swift 定数コメント** — maxBufferedCharacters=400 / maxBufferedSegments=4 の設計根拠をコメント化する提案

### [セキュリティ] (reviewer-security)
3. **TermProtector.swift brokenTokenPattern** — 正規表現 DoS の理論的可能性（入力ソースは翻訳エンジン出力で信頼性高、低リスク）

### [パフォーマンス] (reviewer-performance)
4. **SessionStore.swift bufferedSegments** — `segments.first(where:)` の N+1 線形探索。長セッションで累積遅延。UUID→Segment 辞書化を提案
5. **ContentView.swift / TermProtector.mask** — glossary の filter+sort が翻訳単位ごとに毎回実行される

### [テストカバレッジ] (reviewer-test-coverage)
6. **ContentView.swift targetEntries** — bufferedSegmentIDs による「…翻訳中」表示ロジックのテストがない

## 💡 Consider

- [品質] SpeechTranscriptionService.scheduleTranslation の flushTask 再スケジュールを名前付きヘルパー化
- [品質] ContentView.targetEntries の配列構築スタイル
- [品質] MarkdownExporter.entry() の行配列構築の構造化
- [セキュリティ] recoverBrokenTokens で同一 index 複数出現時は最初の1つのみ復元（仕様確認）
- [セキュリティ] KeywordParser の term 文字種ホワイトリスト検証
- [パフォ] TermProtector.mask の claimed 重複チェックが O(m²)（用語50+で Interval Tree 検討）
- [パフォ] flushTask の isCancelled 再チェック（既に堅牢）
- [テスト] MarkdownExporter の entry/heading を internal 化して単体テスト

## ✅ 問題なし

- セキュリティ: インジェクション・データ保護・認証認可・ロギングに問題なし（Must Fix ゼロ）
- モデル層（SentenceBoundary, TranslationUnit, SessionStore, KeywordParser, TermProtector）のテストは包括的

## 📋 次のアクション

1. 🔴 SessionController.stop() のテスト追加（実現可能）
2. 🔴 SpeechTranscriptionService 系3件 — private メソッド・実機フレームワーク・実時間依存のため実現可能性を精査
3. 🟡 SessionStore の N+1 辞書化
4. 🟡 その他は費用対効果を精査して対応/スキップ判断
