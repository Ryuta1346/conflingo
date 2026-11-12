# LLMストリーミング表示のキー順依存修正

日付: 2026-11-12 / feature/llm-selection
状態: 実装・検証完了。レビューの修正案に対するユーザー「修正進めて」により承認済み。以下は承認時の修正方針と手順。
正本: `~/.coding-agents/docs/conflingo/feature-llm-selection/llm-preview-order-fix-plan.md`

## 問題と修正方針

部分応答の表示がJSONの先頭キー`text`に依存している。OpenAI等の有効な応答でも、`kind`や`evidenceIDs`が先に出力されると完了まで本文が表示されない。

共通の`InsightPayload.preview`で、文字列のエスケープとオブジェクト／配列の深さを追い、トップレベルの`text`値を順序に依存せず取得する。本文の文字列復号と完了時のJSON・根拠・完了イベント検証は維持する。スキーマやAPI要求は変更しない。

## 手順・受入条件

1. 回帰テストを先行追加し、未修正コードで失敗することを確認する。
   - `text`が先頭・途中・末尾の部分JSONを表示できる。
   - 入れ子の`text`や引用文字列内の`text`を表示しない。
   - エスケープや分割Unicodeの途中は待機し、復号できた時点で表示する。
   - OpenAI・Claude・互換APIで完了イベント前に更新が届き、未完了ストリームは引き続き失敗する。
2. 共通プレビュー解析だけを最小修正する。
3. 関連テスト・全回帰・SwiftLint・差分検査を実行し、検証記録を更新する。

実API要求・依存追加・コミットは行わない。Planモード切替ツールは提供されていないため、この計画文書で手順を管理する。

## 実施結果

- Red: 先行追加した5テスト（引数別ケースを含む）を実行し、既存の先頭キー制約により12件の期待値不一致を確認。
- Green: 共通プレビューにトップレベルのキー探索を追加。Unicodeスカラーで文字列境界を追跡し、文字列復号は既存のJSONDecoderを利用。
- OpenAI・Claude・互換APIでは完了イベントを送らない合成SSEを1バイトずつ渡し、未完了エラーに至る前の本文更新を確認。Geminiの共通解析経路も確認。
- 全回帰: **467 tests / 81 suites 合格**。SwiftLint: **179ファイル、違反0**。`git diff --check`合格。
- ログ: `/tmp/conflingo-preview-fix-red.log`、`/tmp/conflingo-preview-fix-green.log`、`/tmp/conflingo-preview-fix-lint.log`。
- 実API・GUI操作は未検証。製品コードの変更は`InsightPayload.swift`のみ。
