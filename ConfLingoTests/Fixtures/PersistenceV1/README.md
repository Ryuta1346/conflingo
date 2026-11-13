# v1保存形式の固定fixture

基点: main `0314aed`。実ユーザーのデータではなく、固定UUID・日時と日英の合成本文で構成したJSON。現在のencoderからテスト実行時に生成しない。

- `r3-meeting-basic.json`: Sessions初版 `e95f8ae` の `MeetingExportSnapshot` に存在しなかった translations / assistance を省略。
- `r3-conference-basic.json`: 同初版の ConferenceSnapshot に存在しなかった support と、TranscriptSegment の origin / sessionOffset / languageCode を省略。
- `r3-meeting-extended.json` / `r3-conference-extended.json`: 基点の任意項目を含む保存形式。Web出典、資料参照、翻訳、補正、用語を含む。
- `r3-knowledge-document.json` / `r3-knowledge-repository.json`: SavedKnowledgeの通常文書と複数ファイルのリポジトリ。初版 `e236c16` からのversion 1を基点の定義で固定。

初版ファイルの実採取ではない。基本fixtureの省略項目は上記コミットの型定義と照合した。JSON日付はFoundation既定の2001-01-01基準の秒数。enumのcase名、関連値の `_0` / `_1`、raw value、キー名、配列順、本文、参照、日付の意味を契約として固定する。Swiftの型名自体がJSONに含まれるとは限らない。

JSONはテストバンドルのリソースから読み、一時ディレクトリで製品のlist/load/saveを実行する。キー順・空白・Unicodeやスラッシュのエスケープ表記は比較対象外。実ファイルは変更しない。

## 更新規則

fixtureの自動上書きは禁止。互換性テストの失敗を解消するために既存fixtureを再生成しない。意味のある契約変更は理由と形式バージョン方針をレビューし、新たなfixtureを追加する。既存のv1読込保証は残す。
