# R2 — 受信上限のローカル調査

2026-11-13 / 調査基点 main `3ffaaf8`。以下のローカル初回調査では追加実API0・音声取得0・製品コード変更0。その後の承認済み実測・修正結果は末尾参照。

## ローカル調査結果（修正前）

同じ8,000文字の正常な構造化回答が、単一の本文イベントなら完了し、1文字ごとのSSEイベントでは`InsightFailure.oversized`になることを、現在のデコーダーで確認した。

| 経路 | 英語・一括 bytes | 英語・1文字分割 bytes | 日本語・一括 bytes | 日本語・1文字分割 bytes |
|---|---:|---:|---:|---:|
| Gemini | 8,192 | 571,902 | 24,192 | 587,902 |
| OpenAI | 8,191 | 459,159 | 24,191 | 475,159 |
| Claude | 8,250 | 716,914 | 24,250 | 732,914 |
| Kimi / DeepSeek / custom / local | 8,222 | 628,303 | 24,222 | 644,303 |

一括は全ケース成功、1文字分割は全ケース上限超過。復号JSONは英語8,054 bytes・日本語24,054 bytesで、既存の65,536 bytes以下。表は生成した合成応答全体のサイズであり、失敗までに実際に受理した量ではない。1,024 bytesずつconsumeへ渡した。

Web調査は既存のGemini・OpenAI・Claudeの合成フィクスチャ（本文7文字）を使用。元のJSONはそれぞれ405 / 277 / 424 bytesで成功。同じJSONに有効な空白を末尾追加して262,145 bytesにすると、すべて上限超過した。これは生バイト制限の確認であり、現実の検索メタデータ量の再現ではない。

計34ケースの期待結果をpreconditionで検証し終了0。製品の機能テスト数や実API合格数には加算しない。

## 方法・再現

[プローブ](fixtures/r2-response-size/main.swift)と[修正前の測定値](fixtures/r2-response-size/measurements.json)を保存した。プローブの期待値は修正後の成功へ更新し、[修正後の測定値](fixtures/r2-response-size/measurements-after.json)と比較できるようにした。3種類のデコーダー、InsightPayload、WebReferenceは製品ソースをそのままコンパイル。周辺のモデル型のみ最小スタブで代用した。HTTP通信層、アプリ全体、実モデルの検証ではない。

リポジトリルートから実行:

```sh
mkdir -p /private/tmp/conflingo-r2-investigation
swiftc -module-cache-path /private/tmp/conflingo-r2-investigation/module-cache \
  ConfLingo/Meeting/Services/LLMResponseLimits.swift \
  ConfLingo/Meeting/Services/LLMStreamDecoder.swift \
  ConfLingo/Meeting/Services/GeminiStreamDecoder.swift \
  ConfLingo/Meeting/Services/InsightPayload.swift \
  ConfLingo/Research/LLMResearchResponse.swift \
  ConfLingo/Research/WebReference.swift \
  docs/validation/fixtures/r2-response-size/main.swift \
  -o /private/tmp/conflingo-r2-investigation/probe
/private/tmp/conflingo-r2-investigation/probe > /private/tmp/conflingo-r2-investigation/measurements.json
```

Swiftコンパイル・プローブ実行は成功。保存したプローブで再実行し、測定JSONの一致も確認した。既存アプリ/テストのSwiftLint 0.65.1 strict/no-cacheは228ファイル・違反0、`git diff --check`も成功。Lintログ: `/private/tmp/conflingo-r2-investigation/lint.log`。初回調査は文書と調査用プローブのみの変更のため、この時点ではアプリの全テスト・Releaseビルドは未実行だった。最終の製品修正検証は末尾を参照。

## 初回調査時の判断

旧上限による分割依存の拒否は合成入力で再現済み。実プロバイダーのイベント分割・メタデータ量、適切な総受信予算は未確認。新しい上限を推測だけで製品へ適用せず、[計画](../design/r2-response-limit-plan.md)と[実API評価の確認事項](../design/r2-response-limit-hearing.md)を作成した。その後、ユーザー「進めて」でGemini限定最大4要求の承認を得た。以下に準備結果を記録する。


## 承認後の準備・認証待ち（当時の記録）

- Gemini限定4要求を承認済み。他社・代替モデルへの送信は未承認のまま。
- `ResponseSizeLiveEvaluationTests`を追加。実製品の要求生成を無通信transportで捕捉し、4ケース全部のモデル・URL・合成入力・30発話/6,000文字・32,768 bytes・8,192出力tokens・60秒を確認してから認証情報を読む。
- 送信前に固定IDの台帳を排他的に作成し、ケースを予約。数値だけ保存し、使用量不明では停止。台帳が既存なら再実行を拒否する。実測時の受信上限は8 MiB、SSE行・イベントは1 MiB。
- 計測の単体テスト3件は成功。実API評価の最初の起動は`InsightFailure.keyStorage`で終了。キー取得前のため**外部要求0、使用枠0/4、応答本文保存0**。
- 既存の読取専用`KeychainRead.xctest`でOS認証を起動した。キー値の表示・変更なし。記録時点ではOS応答待ち。認証画面は操作ツールからアクセス不可で、ユーザーのOS操作が必要。
- 製品修正用のRedテストは5定義を実行し、長文SSE7経路とWeb調査3経路の計10ケースが旧受信上限で失敗することを確認。残る本文・行・フレーム上限と不完全終端の拒否は成功。未修正のテストは`ResponseLimitTests.swift`（現在はConfLingoTestsへ復帰済み）へ退避し、通常テスト対象には残していない。
- 最終全回帰: **587件中580成功・実API7skip・失敗0**。SwiftLint: **231ファイル・違反0**。製品コードの変更とRelease再ビルドは未実施。
- ログ・集計: `/private/tmp/conflingo-r2/{measurement-tests,live,keychain-authorize,red,all,lint-final}.log`、`test-summary.json`。xcresult: `/private/tmp/conflingo-r2/build/Logs/Test/Test-ConfLingo-2026.11.13_22-46-41-+0900.xcresult`。

### 再開手順（実施済み・4要求消費済みのため再送不可）

1. `/private/tmp/conflingo-r2/keychain-authorize.log`の`KEYCHAIN_READ_STATUS=0`を確認する。失敗・認証待ちなら送信しない。
2. 認証対象は`/private/tmp/conflingo-r1-2/build/Build/Products/Debug/ConfLingo.app`。再ビルドで認証状態を変えず、同じビルドに`TEST_RUNNER_CONFLINGO_R2_SIZE_LIVE=1`を渡し、`test-without-building`で`ResponseSizeLiveEvaluationTests`だけを実行する。保存先はアプリのApplication Support内`ConfLingo/Validation/r2-response-size-20261113/measurements.json`。既存台帳があれば中身を確認し、削除して再送しない。
3. 実測後に受信予算を決定し、待機中のRedテストを`ConfLingoTests/`へ戻してTDDで修正。全回帰・Lint・Releaseを実施する。


## 実API測定結果

ユーザー「許可した」を受け、読取専用認証の`KEYCHAIN_READ_STATUS=0`を確認。認証済みの同じビルドを再ビルドせず、`test-without-building`で4要求を逐次実行した。すべてusageを取得して終了。追加要求・再試行なし、回答本文・キーの保存なし。音声取得0。

| ケース | 総受信 bytes | 復号text bytes | イベント数 | 最大イベント bytes | 秒 | 復号 |
|---|---:|---:|---:|---:|---:|---|
| 要約・日本語 | 28,676 | 1,876 | 51 | 7,579 | 19.969 | 成功 |
| 要約・英語 | 29,476 | 1,845 | 53 | 7,647 | 20.010 | 成功 |
| Web調査・日本語 | 26,667 | 4,836 | 1（JSON全体） | 26,667 | 24.715 | 成功 |
| Web調査・英語 | 26,127 | 3,296 | 1（JSON全体） | 26,127 | 20.870 | 成功 |

要約の復号textは構造化回答JSON全体で、表示本文だけのサイズではない。Web調査は引用挿入前の返却本文。すべてSTOP。今回の実応答は旧上限以下であり、上限超過を実APIで再現したとは扱わない。内容の意味・翻訳品質は今回の数値計測の対象外。

[本文を含まない全件記録](r2-response-size-live-2026-11-13.json)。入力8,510・出力5,095・思考5,646 tokens、承認済み生成4/4要求を消費。内蔵検索の内部要求数・実請求額は未照合。ほかのプロバイダーは未測定。

ログ: `/private/tmp/conflingo-r2/live-authorized.log`。liveテスト1件成功（全体約87秒）。xcresult: `/private/tmp/conflingo-r1-2/build/Logs/Test/Test-ConfLingo-2026.11.13_23-45-49-+0900.xcresult`。


## 修正・最終検証

`LLMResponseLimits`に総受信2 MiB、SSE行/イベント64 KiB、復号JSON64 KiBを定義し、通信層2か所・デコーダー3か所へ適用した。表示本文・補足の各8,000文字、引用、検索候補HTML、通信期限、停止/取消の既存処理を維持する。

- **Red:** `red.log`で長文SSE7経路・Web調査3経路の10ケースが旧上限で失敗。通信層と境界を追加した`red-boundaries.log`では21箇所の失敗を確認。
- **上限の調整:** 最初の候補8 MiBは、複数の大きなURLProtocol応答をDebugで受信する試験が60秒制限に到達。テスト側を2分に延長しても通信側の期限に達したため、必要な合成ケースを収容する2 MiBへ縮小した。製品の通信期限は変更していない。これらの模擬受信時間を実ネットワークの性能値として扱わない。
- **Green・全回帰:** 最終2 MiBで、本文8,000文字＋補足8,000文字の1文字イベント分割、UTF-8分断、復号JSON64 KiB境界/1 byte超過、総受信2 MiB境界/1 byte超過、行/イベント超過、不完全終端、実通信層からの復号、コールバック失敗での受信停止を確認。**599件中592成功・実API7skip・失敗0**。全体約55秒。
- **Lint:** SwiftLint 0.65.1 strict/no-cache、**233ファイル・違反0**。`git diff --check`成功。
- **Release:** arm64/x86_64のビルド成功（`CODE_SIGNING_ALLOWED=NO`）。既存の非推奨SDK・AppIntents等の警告は残る。
- **単独プローブ:** 最終2 MiBの製品ソースで再コンパイルし、34ケースすべて成功。[修正前](fixtures/r2-response-size/measurements.json)と[修正後](fixtures/r2-response-size/measurements-after.json)の入力サイズは一致する。
- **台帳照合:** `~/Library/Application Support/ConfLingo/Validation/r2-response-size-20261113/measurements.json`の4件が保存した実測JSONと一致。消費済み台帳を保持し、再送していない。

最終ログ: `/private/tmp/conflingo-r2/all-final.log`、`lint-final.log`、`release-final.log`、`test-summary-final.json`。xcresult: `/private/tmp/conflingo-r2/build/Logs/Test/Test-ConfLingo-2026.11.13_23-54-56-+0900.xcresult`。

実API計測は修正前ビルド。今回の4件は旧上限以下であり、修正後の大規模な実応答の受入とは区別する。OpenAI・Claude・Kimi・DeepSeek等の実測、独立レビュー、実会議の品質ゲート、PRマージは残る。R2はREVIEW、次の実装はR3。検証完了時点ではコミット・push・PR作成・インストール済みアプリ更新は未実施だった。


## PR提出（2026-11-14）

ユーザー「コミットand PR作成」に基づき、`fix/llm-response-limits`で`ab4f10e`（`fix(llm): separate wire and payload limits`）をコミット・pushし、main向け[Draft PR #33](https://github.com/Ryuta1346/conflingo/pull/33)を作成。担当はRyuta1346。REVIEWと未受入項目を維持する。インストール済みアプリは更新していない。
