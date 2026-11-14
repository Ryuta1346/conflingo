# R6-1 — 同文の別発話保持・検証結果

> 2026-11-14マージ確認: [PR #38](https://github.com/Ryuta1346/conflingo/pull/38)はローカルmain `b526a1b`へマージ済み。独立レビュー完了・実音声受入は未確認。以下の未マージ等の記述は各記録時点の状態。

> 2026-11-14提出追記: ユーザー「コミットand PR作成」に基づき、実装 `0ec3d3f`を[Draft PR #38](https://github.com/Ryuta1346/conflingo/pull/38)へ提出済み。未マージ・独立レビュー待ち。以下の未コミット・未PR等の記述はローカル検証完了時点の記録。

2026-11-14 / 基点: ローカルmain `dab817e`＋今回の未コミット変更。
状態: **承認済み範囲をローカル実装・検証済み（REVIEW相当）。未コミット・未PR**。
[計画](../design/r6-1-repeated-final-plan.md)・[修正前の再現](r6-1-repeated-final-investigation.md)。

## 変更

`SessionStore.appendFinal`から直前本文との一致で拒否するguardを削除し、コメントを更新した。同じ入力元で同文が続いても、別発話として表示・翻訳・保存へ渡す。製品差分は1ファイルのみ。

空文字拒否・trim、adapterのイベントID/revisionによる再送除外、翻訳キューのunit IDによる重複除外、文末待ちの結合・flush、保存形式v1は維持する。normalizer・Meeting・adapter・翻訳キューには製品変更を加えていない。

詳細計画に同文反復の契約を追加し、日本語READMEからSessionStoreが再送除外を担うという古い責務説明を削除した。plan.mdとR5-3資料には、調査時に確認したPR #37のマージ済みを反映した。

## TDD・受入

先行テストは34定義／4 suites中、反復保持に関する4定義・14ケースで64 issuesを記録した。2件目がnil、2件を期待した履歴・翻訳・Markdownが1件、停止後再開を含む4件が1件になる失敗。同ID再送拒否とMeetingの既存動作は成功した。

最初の試行はSwift Testingの`#require`にmutatingメソッドを直接渡したためテストのコンパイルが失敗した。戻り値を一旦変数へ格納して修正し、製品未変更のまま再実行したものをRedの証拠とする。製品のguard削除後、同じ34定義／4 suitesが成功した。

| 対象 | 確認結果 |
|---|---|
| store | 英語・日本語×入力元なし／マイク／内部音声の6ケースで、2件・異なるID・連番・各開始時刻・onFinal通知2回を保持。前後空白除去・volatile消去も確認 |
| adapter・キュー | 英語・日本語×2入力元の4ケースで別IDの同文2件を投入。それぞれを再送しても翻訳キューは異なるunit IDで2件。segmentとの対応・言語・共通時刻を保持 |
| 表示・保存・Markdown | 原文表示モデル2行と各訳文の対応を確認。文字起こし／翻訳の両snapshotをディスク保存し、別SessionFilesで再読込して同値。Markdownにも2発話・各時刻・訳文を保持 |
| 文末待ち | `again`を別IDで2回投入し、finish時に`again again`と2つのsegment IDを持つ1単位へ結合。finishを繰り返しても追加投入なし |
| 入力・再開 | fake音声認識からマイクのみ／内部音声のみ／両入力で2発話→停止→再開→同文2発話を流し4件保持。Clearで履歴・単位を消去し、同文を新規取得。両入力の同文も保持 |
| 再送・不正イベント | 同ID再送、確定後のpartialと高revision final、古いrevision、別セッション、対象外入力、空文字の拒否を維持 |
| Meeting | 同一入力元の別ID同文を2件、別入力元同文を1件保持し、同ID再送は追加しない |
| 全体回帰 | 入力、翻訳準備・再試行、表示キャッシュ、補正、共通支援、保存、v1固定JSONなど既存テスト成功 |

追加は`RepeatedUtteranceTests`の3定義（8ケース）。既存のstore・adapter・Meetingテストを更新し、「別発話も捨てる」という旧期待値を整理した。表示の新規検証は表示モデルの内容であり、反復発話の実機UI・VoiceOver受入とは区別する。

## 最終検証

- 全640テスト／116 suites：633成功・実API評価7skip・失敗0、Swift Testing表示55.686秒。xcresultの集計でも照合済み。
- SwiftLint 0.65.1 strict/no-cache：245ファイル・違反0。
- Release：arm64／x86_64、署名なしビルド成功。
- `git diff --check`成功。変更範囲・呼出し元・重複除外の責務・保存形式を自己レビュー。独立レビューは未実施。

```sh
env CONFLINGO_LIVE_AI=0 CONFLINGO_FOCUSED_LIVE_AI=0 \
  CONFLINGO_GROUNDING_LIVE_AI=0 CONFLINGO_RAG_LIVE=0 \
  CONFLINGO_SUMMARY_LIVE=0 CONFLINGO_SUMMARY_REMAINING_LIVE=0 \
  CONFLINGO_SUMMARY_DEADLINE_LIVE=0 CONFLINGO_R2_SIZE_LIVE=0 \
  xcodebuild test -project ConfLingo.xcodeproj -scheme ConfLingo \
  -destination 'platform=macOS' -derivedDataPath /tmp/conflingo-r5-build \
  CODE_SIGNING_ALLOWED=NO
/tmp/conflingo-swiftlint-0.65.1/swiftlint lint --strict --no-cache
xcodebuild -project ConfLingo.xcodeproj -scheme ConfLingo \
  -configuration Release -derivedDataPath /tmp/conflingo-r5-release \
  CODE_SIGNING_ALLOWED=NO build
```

関連試験は上記testに`-only-testing:ConfLingoTests/`で`SessionStoreTests`、`LegacyTranslationAdapterTests`、`TranscriptEventTests`、`RepeatedUtteranceTests`を指定した。

ログ: `/tmp/conflingo-r6-1-{red,red-test,focused,full,lint,release}.log`。
全体結果: `/tmp/conflingo-r5-build/Logs/Test/Test-ConfLingo-2026.11.14_08-05-33-+0900.xcresult`。
集計: `/tmp/conflingo-r6-1-test-summary.json`。集計初回はxcresulttoolのTestReportキャッシュ権限不足で失敗し、権限付き再実行で取得した。

既存Keychain APIのdeprecated、ContentViewの到達不能コード、AppIntentsメタデータ省略の警告が残る。合成UI試験のScrollGeometry警告等も出たが、最終テスト・ビルドの失敗は0。

## 残件

実音声・実モデル・反復発話の実機UIは未受入。normalizerが別IDにした音声認識器の二重出力と正当な反復を、本文だけでは区別しない。同一イベントIDの再送除外を保証し、認識器の出力特性はGate Aで確認する。過去に欠落した発話は復元できない。

音声取得・実API送信・インストール済みアプリ更新・コミット・PR作成は0。R5の独立レビューと実機受入、R6の残項目、Gate A/B/C/U/Dは継続する。R6-1はローカル実装完了であり、マージ・受入完了のDONEには変更しない。
