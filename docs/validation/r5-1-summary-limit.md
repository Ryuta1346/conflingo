# R5-1 — 長い会議の要約上限・検証結果

> 2026-11-14独立レビュー追記: 固定main `33c8ae6`で[残件レビュー](remaining-review-2026-11-14.md)を実施済み。指摘・未修正項目・確認範囲は同記録を参照。以下の「独立レビュー未実施」は当時の履歴で、実機受入の未完了は継続。

> 2026-11-14マージ確認: R5-1 `39e1d7b`・R5-2 `1510670`を含む[PR #36](https://github.com/Ryuta1346/conflingo/pull/36)はローカルmain `a607f6e`へマージ済み。独立レビュー完了・実機受入は未確認。以下の「未コミット・未PR・未マージ」はローカル検証完了時点の記録。R5-3も[ローカル実装・検証済み](r5-3-query-selection.md)。

2026-11-14 / 基点: main `7888730` / [承認済み計画](../design/r5-1-summary-limit-plan.md)

## 変更と到達点

- 要約の上限を20区間から100区間へ拡張した。各区間30発話・12,000文字の制限を維持し、短い発話なら最大3,000件を扱う。長文では件数が少なくても区間上限に達する。
- Review画面で上限と全文Markdown出力の案内を表示する。送信確認画面では実際の要求数を示し、20区間を超える場合は処理時間・料金増加と停止操作を案内する。
- 生成の直列実行・区間ごと60秒・自動再送なし・失敗時の後続停止・旧完成版保持を維持した。coordinator、保存モデル、v1固定JSONは変更していない。
- 製品変更は`MeetingSummary.swift`、`MeetingReviewControls.swift`、`SummaryConfirmationView.swift`の3ファイル。

## TDD・受入結果

先行テストでは、601／3,000発話、100件の長文、21区間以降の停止・資料付き要約が旧20区間制限で拒否された。Redは3 suites・17テストに8 issues、すべて想定した`tooManySections`。上限変更後、関連32テスト／7 suitesが成功した。

| 対象 | 結果・主な証跡 |
|---|---|
| 600／601／3,000発話 | 20／21／100区間。時系列・全発話IDを保持、省略0。`LongMeetingSummaryTests.shortUtterancesPreserveEveryIDBeyondOldLimit` |
| 3,001発話・101区間 | 送信前に拒否、既存要約と全文を保持。`exceedingLimitDoesNotSendOrDiscardExistingSummaryAndTranscript` |
| 文字数境界 | 12,000文字×100件を受理、次の1発話で101区間として拒否。単一12,001文字の拒否も既存テストで成功 |
| 100区間の生成・保存 | fakeで100要求を順に1回ずつ実行。根拠3,000件・資料引用・時刻を保存し、新しいSessionFilesで再読込して同値。v1、Markdown根拠リンク3,000件を保持。`hundredSectionsGenerateOnceAndRoundTripWithEvidenceAndKnowledge` |
| 21区間目の取消／失敗 | 22区間の再生成を21区間目で停止。後続送信0、途中結果20区間、遅延応答を棄却、前回の完成22区間を維持。`stoppingAtSectionTwentyOneKeepsOldCompletionAndSendsNoLaterSection` |
| 資料付き21区間 | 全区間で実ローカル検索し、抜粋上限を維持。会議中の資料許可はオフのまま。同意なし・資料削除後の古い計画は送信0。`longKnowledgePlanSearchesEverySectionAndRejectsChangedDocuments` |
| 既存契約 | 固定16会議・22区間の合成評価ケース、Meetingの終了後のみ生成する制約、R3のv1固定JSON、取消・期限・再生成を含む全回帰成功 |
| 合成UI | 440pt／620pt幅・高さ700ptで3,000発話の確認画面を表示。100要求・長時間案内・送信ボタンの存在をAXで確認、取消操作で計画が無効化。440ptのReviewでは21区間の進捗表示と停止ボタンの実行を確認。`LongSummaryLayoutTests` |

UI画像はNSHostingViewの未加工PNGを目視確認。案内の折返し、発話用スクロール領域、確認・取消・停止ボタンの配置を確認した。全3,000発話を末尾までスクロールする実操作、VoiceOverの読み上げ全経路、実アプリのシート開閉を含む全UI受入は未検証。

画像: `$TMPDIR/r5-summary-confirmation-{440,620}.png`、`$TMPDIR/r5-summary-review-440.png`。
UI試験の初回失敗はAXツリー有効化の不足と、画面の`3,000`に対するテスト期待値`3000`の不一致。試験設定を修正後、全回帰でも成功した。製品の失敗とは区別する。

## 最終検証

- 全617テスト／111 suites：610成功・実API評価7skip・失敗0、59.771秒。xcresultの`totalTestCount`／`passedTests`／`skippedTests`でも確認。
- SwiftLint 0.65.1：238ファイル・違反0（strict/no-cache）。
- Release：arm64／x86_64・署名なしでビルド成功。
- `git diff --check`：成功。
- ソース差分と保存・取消・境界の自己レビューを実施。独立レビューは未実施。

```sh
xcodebuild test -project ConfLingo.xcodeproj -scheme ConfLingo \
  -destination 'platform=macOS' -derivedDataPath /tmp/conflingo-r5-build \
  CODE_SIGNING_ALLOWED=NO
/tmp/conflingo-swiftlint-0.65.1/swiftlint lint --strict --no-cache
xcodebuild -project ConfLingo.xcodeproj -scheme ConfLingo \
  -configuration Release -derivedDataPath /tmp/conflingo-r5-release \
  CODE_SIGNING_ALLOWED=NO build
```

テストでは`CONFLINGO_LIVE_AI`、`CONFLINGO_FOCUSED_LIVE_AI`、`CONFLINGO_GROUNDING_LIVE_AI`、`CONFLINGO_RAG_LIVE`、`CONFLINGO_SUMMARY_LIVE`、`CONFLINGO_SUMMARY_REMAINING_LIVE`、`CONFLINGO_SUMMARY_DEADLINE_LIVE`、`CONFLINGO_R2_SIZE_LIVE`をすべて0に設定した。

ログ: `/tmp/conflingo-r5-{red,focused,ui,all,lint,release}.log`。
全テストxcresult: `/tmp/conflingo-r5-build/Logs/Test/Test-ConfLingo-2026.11.14_01-04-41-+0900.xcresult`。
集計: `/tmp/conflingo-r5-test-summary.json`。
サンドボックス内の初回ビルドはSwiftマクロ起動失敗のためテスト到達前に失敗。通常のXcode権限で再実行した。AppIntentsのメタデータ省略や合成UIのScrollGeometryログは残るが、最終テスト・ビルドの失敗はない。

## 残件

R5-1はローカル実装・自動検証・上記合成UI確認済み、REVIEW相当。未コミット・未PR・未マージ。インストール済みアプリは更新していない。実API送信・音声取得は0。最大100区間の実モデル品質・所要時間・実費・長時間耐久、独立レビューは未確認。

R5の残りはライブ表示の全履歴再計算と、資料検索語をアルファベット順の先頭32語で選ぶ処理。次は前者の調査・計画。R4のマージ済みをplan.mdへ反映したが、独立レビュー完了の確認とGate A実機受入は残す。

2026-11-14追記: 上記の次段階R5-2は[ローカル実装・検証済み](r5-2-live-presentation.md)。資料検索語選択も[R5-3でローカル実装・検証済み](r5-3-query-selection.md)。
