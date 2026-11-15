# PR #42・#43 独立レビュー

2026-11-15。対象main: `8a02bc89d2faec70701541c3785d740bbfde923f`（PR #44までマージ済み）。
`plan.md` の「実音声待ちの間はレビュー・評価ケース準備を進める」に基づくレビュー・検証。製品実装の変更は対象外。

## 対象と実施順

1. PR #42の`ed0a08b..50f59d4`、PR #43の`50f59d4..e21c355`を固定し、仕様と差分を3担当が独立に確認する。
2. 現行mainで既存の全テスト・Lint・Release両CPU、およびCIスクリプトの静的検証を実行する。
3. 指摘を統合・反証し、進捗資料と次の作業を更新する。実装が必要な指摘は修正計画として分離する。

| 担当 | 範囲 |
|---|---|
| 共通支援・通知 | 購読寿命、配信中の変更、Conference/Meetingの停止・再開・許可取消 |
| LLM要求・SSE | provider別要求、終端・usage・受信上限、取消、HTTP転送 |
| CI・テスト | 非同期fixture、待機、workflow権限、ツール固定、失敗伝播、実API除外 |

使用スキル: `parallel-review`・`review-common`。TDDは既存テストの評価に使用。LLM担当は`staff-backend`、CI担当は`staff-sre`の観点を併用する。

差分SHA-256:

- PR #42: `1ed0bacf41e6a547718c6f07fd71734944c95818e6a4f7d39df347b19519c547`
- PR #43: `3689976cd6b7b0de890094521d42349afb76036460162f7754d4de743b692170`

## レビュー結果

独立3担当とも修正指摘0件。差分の実行順序・既存契約と周辺コードを確認し、新たな不具合を確認しなかった。CRITICAL/HIGHの候補がないため、追加の反証担当は起動していない。製品コード・テストコードの変更はない。

[担当別結果と対象](pr42-pr43-independent-review-2026-11-15/reviews.json)・[LLM担当の詳細範囲](pr42-pr43-independent-review-2026-11-15/llm-scope.md)。Web調査HTTP転送の受信途中取消を決定的に発生させる既存テストはなく、この点は検証上の限界として残す。今回の差分による不具合とは判定していない。

## 自動検証結果

| 検証 | 結果 |
|---|---|
| 標準検証 | `scripts/ci.sh all`終了0 |
| 全テスト | **705定義・127suite成功**、32.930秒。実API7定義は明示除外、失敗0。パラメータ展開後は1,118ケース |
| SwiftLint | 0.65.1 strict/no-cache、275ファイル違反0 |
| Release | 署名なしビルド成功、lipoでarm64/x86_64確認 |
| CI静的検証 | `bash -n`・ShellCheck・actionlint 1.7.12成功 |

[識別子を除いたxcresult集計](pr42-pr43-independent-review-2026-11-15/test-summary.json)。検証コードはレビュー対象より後のPR #44を含む現行mainであり、PR #42・#43当時の件数とは区別する。

- 最初のSandbox内実行: Lint275ファイル違反0。Swiftマクロの起動制約によりビルド失敗、テスト未実行。製品の回帰失敗とは判定しない。
- 権限付きで再実行して上記の成功を確認。xcresult集計もTestReportキャッシュへの権限が必要だった。actionlintのmise shimはバージョン未設定のため、既存の1.7.12バイナリを直接指定した。
- ログ・差分の保存先: `/private/tmp/conflingo-review-42-43-20261115/`。

```sh
SWIFTLINT_BIN=/tmp/conflingo-swiftlint-0.65.1/swiftlint \
CONFLINGO_CI_OUTPUT_DIR=/private/tmp/conflingo-review-42-43-20261115/validated \
bash scripts/ci.sh all
```

同ディレクトリの`test.log`・`lint.log`・`release.log`・`architectures.log`・`tests.xcresult`を参照。最初の失敗は別の`validation/`と`validation.log`に保持した。

## 受入の境界

PR #44はGitHubのマージ情報とローカルmainで確認済み。修正HEAD `d63e176`の[CI run 43667087489](https://github.com/Ryuta1346/conflingo/actions/runs/43667087489)はGitHub APIで`completed / success`を確認した。

PR #43もmain `e21c355`へのマージを確認。修正HEAD `f9d19e5`の[CI run 43610628462](https://github.com/Ryuta1346/conflingo/actions/runs/43610628462)はGitHub APIで`completed / success`を確認した。今回新しいリモートCIは起動していない。

今回のレビュー対象はPR #42・#43。PR #44の独立レビュー、実音声、各社実モデル、VoiceOver、最大容量・耐久・配布署名は今回の合格対象に含めない。実API評価フラグは全て0、該当4suite・7定義を標準スクリプトで除外した。Gate A/B/C/U/Dと受入完了数2/12は維持する。追加実API・実音声取得・コミット・pushは0。

次は従来の優先順どおりConference回帰（Gate A）と会議アプリ別2入力受入（Gate B）。実音声の条件確認待ちではPR #44の独立レビューと、VoiceOverを除く残るUI受入を進められる。

## コミット時の統合

プッシュ時にリモートmainのPR #45・#46（`d3b266c`）への更新を確認。資料コミットを載せ直し、`plan.md`の競合はDR1〜5のタスク・PR #46の実装記録を保持して解消した。この報告のレビュー・705テストは`8a02bc8`に対する結果で、PR #46を含む最新版の受入へ流用しない。統合時の製品・テスト・CIコード変更はない。
