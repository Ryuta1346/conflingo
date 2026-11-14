# 残タスクのレビュー・基準検証

> 2026-11-14修正追記: 下記MEDIUM 4件は承認後にローカル修正・自動検証・独立レビュー完了、未コミット・未PR。[修正結果](remaining-implementation-2026-11-14.md)。以下は修正前の固定版と基準検証の履歴。

2026-11-14 / 固定製品版: main `33c8ae6`。製品コード・テストコードの変更なし。
依頼「残っていること片付けて」に対する先行作業。実装案は[計画](../design/remaining-work-plan.md)、未決事項は[ヒアリング](../design/remaining-work-hearing.md)。

## 完了したこと

- PR #40がローカルmainへマージ済みであることを確認し、plan.mdとR6-4の資料を訂正した。
- `parallel-review`に従い、3つの別コンテキストで固定差分を独立レビューした。後続修正は現行版で確認し、解消済みの指摘を除いた。親担当が最終指摘の現行コード・仕様との整合を確認した。
- 日英READMEの構成図を共通文字起こし・Meeting・AI・資料・Sessionsの現行構成へ更新した。中国語・韓国語・スペイン語READMEへ現在の機能と未受入範囲を反映し、「システム音声・要約非対応」の古い記述を訂正した。各言語の構成図は英語版に集約した。
- 英語利用ガイドへ100区間要約の上限を追記した。根拠のない現行翻訳遅延の断定をREADMEから除き、実測未受入と明記した。

## 独立レビュー結果

| 対象 | 固定差分 | 結果 |
|---|---|---|
| R2 | `ab4f10e` | MEDIUM 1件: SSEの結合改行が64 KiBイベント予算に含まれない |
| R4/R5 | `2310f7a`, `39e1d7b`, `1510670`, `bd01b29` | MEDIUM 1件: 翻訳完了を固定200msで代用するUIテスト |
| R6-1〜4 | `0ec3d3f`, `dee4d81`, `5fad038` | 指摘0件。実モデル・Keychain実認証・実音声は未受入 |
| PR #20 | `294bd0c^1..294bd0c` | 指摘0件。実品質と1,000ファイル原本走査性能は未検証 |
| PR #22/#24 | `adf9516^1..adf9516`, `595eb5c^1..595eb5c` | MEDIUM 2件: 用語更新競合、資料取り外し時の許可解除漏れ |
| PR5-C | `e167765^1..e167765` | 必須修正0件。小窓の発話参照はLOWの任意UX提案。履歴画像16点を確認 |

CRITICAL/HIGHは0件。MEDIUM 4件は未修正。小窓の引用単独で主画面を展開しない点は、2段操作が成立し単独展開の必須契約もないため、当初のMEDIUM判定を撤回した。任意提案を今回の必須実装に追加しない。

[指摘JSON](remaining-review-2026-11-14/findings.json)・[固定diffハッシュ](remaining-review-2026-11-14/diff-hashes.json)。差分はGitコミットから再取得可能。確認したファイル・画像と制約は同ディレクトリの各`*-scope.md`参照。

### 未修正の具体条件

1. **SSE上限:** `LLMStreamDecoder`と`GeminiStreamDecoder`はdata値だけを合算し、結合時の改行を数えない。実デコーダーを使う[ローカルプローブ](remaining-review-2026-11-14/main.swift)で、空data行70,000行を含む420,204 bytesを受理した。結合後のイベントは約70,119 bytesで上限65,536 bytesを超える。[結果](remaining-review-2026-11-14/r2-probe-result.txt)。プローブの周辺モデル・payload型はstubで、製品全体の品質評価ではない。
2. **UI待機:** `LiveTranscriptLayoutTests.meetingEvidenceRemainsVisibleDuringUpdatesThenReturnsToLatest`は非同期fake翻訳の完了を待たず件数を検査する。既存検証記録とコードで確認。下記の今回実行では別の同suiteテストでAX空状態が再現した。
3. **用語競合:** `DualTranscriptionController.updateContext`の旧要求Aがマイク更新待ち中、新要求Bが両入力へ完了すると、再開したAがシステム音声に旧用語を書き込める。同run内の更新を保護する世代/直列化がない。静的に確認した競合経路であり、実Speechモデルの再現試験は未実施。
4. **資料許可:** Meetingの資料取り外しは`KnowledgeStore.remove/removeRepository`へ直行し、成功時の`onContentChange`は用語をresetするだけ。追加時と違って手動・自動の資料送信許可が維持される。資料変更で許可を無効化する承認計画と不整合。新しい資料の漏洩を示すものではない。

## 今回の基準検証

| 検証 | 結果 |
|---|---|
| 全体テスト・通常並列設定 | **667定義中659成功・7skip・1失敗**、121 suites、テスト実行49.925秒、xcodebuild終了65 |
| 失敗 | `LiveTranscriptLayoutTests.conferenceCacheHitsStillObserveFinalsTranslationsAndClear` 23行。`text(host)`が空で`Partial two`の期待に失敗 |
| SwiftLint 0.65.1 strict/no-cache | 251ファイル、違反0 |
| Release | 今回は未再実行。製品コード未変更、直前R6-4の成功記録を維持 |

[機器識別子を除いたxcresult集計](remaining-review-2026-11-14/test-summary.json)。パラメータ展開後件数とテスト定義数を混ぜない。直前の並列無効での660成功を、今回の通常並列検証成功とは扱わない。修正前の失敗を消すための再実行はしていない。

```sh
env CONFLINGO_LIVE_AI=0 CONFLINGO_FOCUSED_LIVE_AI=0 \
  CONFLINGO_GROUNDING_LIVE_AI=0 CONFLINGO_RAG_LIVE=0 \
  CONFLINGO_SUMMARY_LIVE=0 CONFLINGO_SUMMARY_REMAINING_LIVE=0 \
  CONFLINGO_SUMMARY_DEADLINE_LIVE=0 CONFLINGO_R2_SIZE_LIVE=0 \
  xcodebuild test -project ConfLingo.xcodeproj -scheme ConfLingo \
  -destination 'platform=macOS' -derivedDataPath /tmp/conflingo-remaining-build \
  CODE_SIGNING_ALLOWED=NO
/tmp/conflingo-swiftlint-0.65.1/swiftlint lint --strict --no-cache
```

ログ: `/tmp/conflingo-remaining-baseline.log`、`/tmp/conflingo-remaining-lint.log`。
xcresult: `/tmp/conflingo-remaining-build/Logs/Test/Test-ConfLingo-2026.11.14_21-29-52-+0900.xcresult`。
xcresulttool集計ではTestReportキャッシュへの権限不足が起き、権限付き再実行で集計を取得した。

## 残件

上記4件の修正とR6後続実装、現在ビルドのUI/VoiceOver、実音声・各社実モデル・Gate A/B/C/U/D、費用照合・配布署名は未完了。PR5-Cの画像は2026-11-08時点で、現在の画面受入に流用しない。今回、実API送信・音声取得・利用者データの削除・コミット・pushは行っていない。
