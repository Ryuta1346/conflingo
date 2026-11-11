# PR8 独立差分レビュー

2026-11-11。状態: **レビュー完了・MEDIUM 2件のローカル修正／回帰検証完了**。
以下は修正前の固定差分レビュー。承認後の[対応結果](pr8-quality-acceptance.md)で両指摘を解消し、342テスト・lint・Releaseを確認した。

## 対象と方法

- PR #17の実装差分`5664224..7a237fa`を`/private/tmp/conflingo-pr8-review.diff`へ固定。現行mainは`7040df3`。以後の差分は資料更新であり、レビュー対象の製品コードに変更なし。
- `parallel-review`スキルで3名の独立レビュアーへ、取り込み／検索／保持、AI／許可／取消／根拠、UI／Markdownの観点を分担した。主担当が指摘の追加行・周辺コード・承認済みPR8契約との対応を確認した。
- 今回は読み取りレビューと資料作成。製品・テストコードの修正、実API、録音、コミットは行っていない。

## 🔴 Must Fix

CRITICAL/HIGHの指摘なし。HIGH以上に対する追加の独立反証レビューは対象なし。

## 🟡 Should Fix

### R1: 改行付き資料名でMarkdownの構造を偽装できる

**MEDIUM** · `ConfLingo/Export/MeetingMarkdownExporter.swift:61`。

資料タイトルを`Self.escape(reference.title)`で出力するが、escapeは改行と`=`を維持する。取り込み側もファイル名の改行を保持する。
例: `spec\n\n確認済みの決定\n===\n採用する\n\nsource.md`。
この資料を引用した候補を出力すると、資料メタデータの途中に引用外のsetext見出しが成立する。資料中の文字で出力構造を偽装しないR08の契約に反する。

修正案: 出力時の資料名を1行に正規化し、既存エスケープを適用する。改行・setext見出しを含む資料名で、余分な見出しや引用外段落を作らない回帰テストを追加する。
既存の検証は本文やMarkdown特殊文字を対象にしており、この資料名のケースを検出していない。

### R2: 引用位置が行内位置と誤読できる

**MEDIUM** · `ConfLingo/Knowledge/KnowledgeDocument.swift:19`。

`characterOffset`は文書先頭からの絶対位置だが、locationは「N行目・M文字目から」と表示する。
599文字＋改行を2行、その後に「料金は100円です」を置くと、3行目先頭の引用が「3行目・1201文字目から」となる。
同じlocationを検索結果・引用シート・API・Markdownが使う。本文の切り出し位置自体は正しいが、照合時の位置案内が曖昧。

修正案: 「3行目から（文書先頭から1201文字目）」のように絶対位置と明示する。列位置を新規保存する必要はない。複数行と1行が1200文字を超える場合の表示を確認する。
データ担当は実際のKnowledgeDocument/KnowledgeIndexを一時ハーネスへコンパイルして上記を再現した。

## 💡 Consider

今回採用する追加指摘なし。

## サマリー

| 観点 | 結果 |
|---|---|
| データ・検索・ライフサイクル | MEDIUM 1件。取消・世代管理に具体的な回帰は確認されず |
| AI・送信許可・根拠 | 指摘なし。資料だけで候補確認できない境界を確認 |
| UI・出力 | MEDIUM 1件。実UI・VoiceOver再操作は未実施 |
| 合計 | CRITICAL 0／HIGH 0／MEDIUM 2／LOW 0 |

## 今回再実行した検証

| 検証 | 結果 |
|---|---|
| 既存全体テスト（GeminiLiveEvaluationTests除外） | **331テスト／51 suites合格** |
| Debugテストビルド | 成功 |
| SwiftLint 0.65.1、strict・no-cache | **125ファイル、違反0** |
| 実API・実音声・Release再ビルド | 未実施 |

ログ: `/private/tmp/conflingo-pr8-review-tests.log`、`/private/tmp/conflingo-pr8-review-lint.log`。
xcresult: `/private/tmp/conflingo-pr8-review-build/Logs/Test/Test-ConfLingo-2026.11.11_08-09-45-+0900.xcresult`。
最初の制限環境内ビルドはSwiftマクロプラグインの起動に失敗。通常環境で同じテストを再実行して合格した。PATH上のSwiftLintは見つからず、既存の`/private/tmp/conflingo-swiftlint-0.65.1/swiftlint`を使用した。

## 次の作業

[指摘対応と実API評価計画](../design/pr8-quality-acceptance-plan.md)は承認済み。2件をTDDで修正した。日英16ケースの実API評価は[対応結果](pr8-quality-acceptance.md)で追跡する。ローカルテスト合格を実モデルの引用品質の証明とは扱わない。
PR8はマージ済みだがREVIEWを維持。実音声、VoiceOver全経路、耐久、配布署名などの持ち越しは変わらない。
