# 残タスク第1段階 — 修正・検証結果

2026-11-14 / 基点main `33c8ae6`＋未コミット変更。
状態: **計画承認済み、ローカル実装・自動検証・独立レビュー完了。実装コミット済み・未マージ。**
[承認済み計画](../design/remaining-work-plan.md)・[修正前レビューと基準失敗](remaining-review-2026-11-14.md)。

## 実装した範囲

| 対象 | 変更と確認した契約 |
|---|---|
| SSEイベント上限 | Gemini/共通デコーダーともdata行の結合改行を含めて64 KiBを判定。追加前の上限判定・イベント毎のリセットを統一。Geminiの毎行reduceを累積カウンタへ置換 |
| 用語更新競合 | 前のcontext更新を取消し、その完了後に次を実行。旧更新が新しい値を後から上書きしない。停止時は音声を先に止め、旧書込みをdrainしてからidle/再開始へ進む |
| 資料送信許可 | Meetingの資料内容変更成功時に手動・自動の資料許可を解除。追加・取り外し・リポジトリ取り外しで統一。開始前に取消済みの取り外し要求は変更を始めない。重複した追加後の許可解除処理を削除 |
| UIテスト | 4 suiteが共有するAX設定を参照数で管理し、最後の利用終了まで有効状態を保持。元の設定を最後に復元。翻訳fakeの開始・保留・解放と期限付き完了待ちを入れ、AX本文も期待状態を期限付きで待つ |
| LLM失敗診断 | 通常回答/要約/資料質問/補正、Web調査、モデル一覧の3入口で失敗を1回記録。成功は0回、元エラー・要求・停止契約を維持。固定分類と数値以外は記録しない |
| 検証画面 | システム音声・2入力確認のcontroller所有/生成とWindow宣言をDEBUG条件へ移した。Releaseの通常Conference/Meeting・小窓は維持 |

資料変更時も既存の回答引用と残った資料、音声取得を維持する。失敗/変更なしでは許可を維持し、開始前取消では本文を削除しない。SQL障害そのものの実注入は今回行っておらず、成功時だけ通知する既存catch経路を静的に確認した。

## 診断ログの契約

- subsystem: `com.gavrri.conflingo`、category: `LLM`。
- 項目: `provider`、`operation`、`reason`、任意の数値`code`。provider/operation/reasonは固定enum。HTTPステータスまたはURLエラーコードだけを数値として出す。
- 本文、APIキー、URL、モデル名、接続名、資料パス、エラーの任意文字列はイベント型へ渡さない。未知エラーは`unknown`で数値コードも省く。
- 取消は`cancelled`としてinfo、通常失敗はerror。独自ファイル・外部送信・自動再送・設定UIは追加していない。OS側のログ保持期間は変更していない。
- 注入sinkで分類・回数・秘密文字列非出力を検証。全体テストの既存合成失敗でも、OSLogから`[LLM] provider=openai operation=models reason=missingKey code=none`などの出力を確認した。

## TDDと検証

| 段階 | 結果 |
|---|---|
| SSE/用語/許可のRed | 14定義・3 suitesで13 issues。うち12は目的の不具合（SSE8、用語2、取り外し2）。残る1はテスト側の自動資料許可の前提不足で、開始/許可設定を修正 |
| 同範囲のGreen | 診断Redとの併走で3 suitesが成功。SSE65,536 bytes成功/65,537拒否、4プロバイダ×1/1,023 bytes分割、用語順序/停止/片入力失敗、取り外し2種を確認 |
| 診断Red | 既存処理をpass-through captureへ接続した時点で、イベント未記録により6定義・34 issues |
| 診断Green | 分類・記録後に6定義成功。全プロバイダ401/429、秘密文字列を持つ未知エラー、timeout/offline/取消、用途別、Web/一覧、成功時0記録を確認 |
| AX共有設定Red | 従来の個別保存/復元を最小境界へ抽出。非LIFOで片方を解放すると無効化され、最後に元falseへ戻らない2 issuesを確認 |
| AX/UI Green | 共有lease化後に設定テスト成功。LiveTranscript/AssistanceReview/LongSummary/MeetingTermの4 UI suitesが並列で成功 |
| 取消済み取り外しRed→Green | 通常文書/リポジトリの取消済み要求が削除を進める4 issuesを再現。開始前取消のguard後に成功 |
| 最終全体 | **682定義中675成功・実API7skip・失敗0**、125 suites、52.987秒。Xcode並列テストを無効にせず実行 |
| Lint | SwiftLint 0.65.1 strict/no-cache、257ファイル・違反0 |
| Release | arm64/x86_64のuniversal binary生成成功、`CODE_SIGNING_ALLOWED=NO` |
| 差分 | `git diff --check`成功。独立レビュー後の製品/テスト21ファイルのハッシュ一致 |

診断のOSLog sinkを接続した途中でMainActor関数から非isolated closure型への変換エラーが出た。sinkの型を明示して解消。これは仕様のRedには含めない。

修正前の通常並列実行は667定義中659成功・7skip・字幕AX空状態1失敗だった。今回成功はその問題の回帰確認だが、あらゆる実行環境でUIテストが不安定にならない保証ではない。テストの期待条件を削除したり、失敗した全体実行を再試行だけで成功扱いにしたりはしていない。

[最終xcresult集計](remaining-implementation-2026-11-14/test-summary.json)。パラメータ展開後件数とテスト定義数を混ぜない。

## 独立レビュー

3担当が固定diffとSHA-256へ照合。**全担当の指摘0件**。

- [入力順序・資料許可](remaining-implementation-2026-11-14/concurrency-consent.json)・[範囲](remaining-implementation-2026-11-14/concurrency-consent-scope.md)
- [診断・SSE](remaining-implementation-2026-11-14/diagnostics-sse.json)・[範囲](remaining-implementation-2026-11-14/diagnostics-sse-scope.md)。旧SSE再現プローブが修正後`oversized`で拒否されることも確認。
- [UIテスト・Debug画面](remaining-implementation-2026-11-14/ui-probes.json)・[範囲](remaining-implementation-2026-11-14/ui-probes-scope.md)
- [対象ファイルハッシュ](remaining-implementation-2026-11-14/hashes.json)

## 再実行と成果物

```sh
env CONFLINGO_LIVE_AI=0 CONFLINGO_FOCUSED_LIVE_AI=0 \
  CONFLINGO_GROUNDING_LIVE_AI=0 CONFLINGO_RAG_LIVE=0 \
  CONFLINGO_SUMMARY_LIVE=0 CONFLINGO_SUMMARY_REMAINING_LIVE=0 \
  CONFLINGO_SUMMARY_DEADLINE_LIVE=0 CONFLINGO_R2_SIZE_LIVE=0 \
  xcodebuild test -project ConfLingo.xcodeproj -scheme ConfLingo \
  -destination 'platform=macOS' -derivedDataPath /tmp/conflingo-remaining-build \
  CODE_SIGNING_ALLOWED=NO
/tmp/conflingo-swiftlint-0.65.1/swiftlint lint --strict --no-cache
xcodebuild -project ConfLingo.xcodeproj -scheme ConfLingo -configuration Release \
  -derivedDataPath /tmp/conflingo-remaining-release CODE_SIGNING_ALLOWED=NO build
```

ログ: `/tmp/conflingo-remaining-{core-red,diagnostics-red,ax-red,ax-red-recheck,removal-red-ui-green,full,final-lint,release}.log`。
xcresult: `/tmp/conflingo-remaining-build/Logs/Test/Test-ConfLingo-2026.11.14_22-15-04-+0900.xcresult`。

## 継続する範囲

第2段階の構造整理・CI、実音声/実モデル、VoiceOver全経路、60分耐久、署名付き配布・請求照合は未実施。実OSのsetContextが返らない場合の停止期限は保証していない。Keychain非推奨API、ContentViewのRelease到達不能分岐、AppIntents省略の既存警告は残る。

実API送信・実音声取得・モデルダウンロード・利用者データの削除・インストール済みアプリ更新・コミット・push・PR作成は行っていない。未マージなので各区分をDONEにせず、Gate A/B/C/U/Dと受入完了2/12を維持する。
