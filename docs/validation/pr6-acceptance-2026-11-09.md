# PR6 残る受入の検証

2026-11-09 / main `d0b4379`。ユーザー「受入検証進めて」に基づく検証。製品コードは変更せず、実音声試験の延期を維持した。PR6はREVIEW、Gate C全体は未合格のまま。

## 検証範囲

- 通常アプリのKeychain登録状態を確認し、登録済みなら既存Xcode実API評価を実行する。既存キーを置換・削除しない。
- 本番通信6ソースのバイト一致コピーを一時ランナーで使い、未使用の合成会話8件を各3回評価する。反復は成功率観測が目的で、自動再試行はしない。日英の未知値、明示変更、未承認提案、雑談を含む。言語・分類・根拠ID・意味を評価する。
- 同じ本番通信コードで応答受信開始後の取消を3回検証する。取消を観測し、完了結果を返さないことを確認する。既送信内容の撤回や課金取消は検証対象ではない。
- 既存の通信・調整・Meeting結合テストを実行し、モックによる停止・遅延応答拒否と実通信の取消を区別する。
- 計測成果物には本文・キーを保存しない。評価対象は合成会話のみ。未知セットとは、今回のプロンプト調整に使用していないセットを指し、実会話一般の品質を保証しない。

## 開始時点で判明した制約

- 通常アプリのAPIキー設定画面は「APIキー未登録」。利用者へ画面上での登録を依頼した。
- `--meeting-preview` は音声だけでなくAIとキー保存もfake固定。通常アプリはMeeting開始に実音声入力が必要。このため、現状の非録音UI経路では実APIとの結合受入ができない。実通信ランナーの成功を通常アプリの受入成功として扱わない。
- PR #13はローカルmain `d0b4379`でマージ済み。PR6は受入が残るためREVIEWを維持する。

## 結果

| 対象 | 結果 | 証跡・限界 |
|---|---|---|
| 未使用の合成会話8件×3回 | 言語・分類・構造・根拠ID・意味24/24合格 | 質問言語、不明と未決定の区別、変更済みと提案の区別、雑談から候補を作らないことを確認。単一発話の限られた8ケースであり、複数発話・実会話一般の成功率ではない |
| 応答受信開始後の実通信取消 | 3/3合格 | 本番URLSession transportの最初のデータchunkを受信後、Swift Taskをcancel。全3回、1 chunkで停止し`interrupted`。完了結果なし。UI操作・Meeting停止との実通信結合は未検証 |
| 既存関連テスト | 26 tests / 5 suites成功 | MeetingAIIntegration / InsightCoordinator / InsightRecovery / InsightHTTPTransport / GeminiInsightClient。モックによるPause・入力障害・キー変更・遅延応答拒否等を確認 |
| 通常アプリのKeychain登録 | 確認済み | ユーザーが保存後、設定を開き直して「APIキー登録済み」「APIキーをKeychainへ保存しました」を確認 |
| Keychain経由のXcode実API評価 | 停止・未完了 | 別ビルドのテストホストが事前のKeychain読み出しで停止。評価ループへ到達せず、今回の追加API送信は0件 |

平均1.271秒、p95 1.493秒（nearest-rank、完了した24要求のみ）。入力25,419・出力1,994・思考0トークン。今回の実API要求は計27件、再試行0。取消3要求の使用量と実請求額は不明。

言語・意味は24回答を目視評価。全件、要求内の1発話への有効な参照を返した。英語の変更提案は2回`decisionCandidate`・1回`answerSuggestion`と変動したが、いずれも未承認を保持し、事前に許容した種別に含まれる。分類の完全な同一性は主張しない。

[測定JSON](pr6-acceptance-2026-11-09.json)に本番6ソースのSHA-256、各要求の測定・判定理由を保存。本文・キーは保存していない。一時ランナーは`/private/tmp/conflingo-pr6-acceptance/`。既存dotenvキーをメモリ経由で渡した。通常アプリのKeychain、製品コード、プロンプトは変更していない。

関連テストのログは`/private/tmp/conflingo-pr6-acceptance-tests.log`、xcresultは`/private/tmp/conflingo-pr6-acceptance-build/Logs/Test/Test-ConfLingo-2026.11.09_22-37-57-+0900.xcresult`。初回はサンドボックス内でSwiftマクロの応答異常によりビルド失敗し、承認された通常環境での再実行が成功した。全テストやReleaseビルドの再実行ではない。

## 次の受入

キー登録は完了。別ビルドでのKeychain読み出し停止の解消、および非録音で実Geminiへ接続するDebug限定のUI検証経路が必要。[確認シート](../design/pr6-app-acceptance-hearing.md)。実音声・通常起動全体・VoiceOver/画面共有・長時間性能・実請求額は未検証を維持する。

## Keychain登録後の追試

ユーザー「保存した」を受け、通常アプリの設定を開き直して登録済み表示を確認した。既存の`GeminiLiveEvaluationTests`を`TEST_RUNNER_CONFLINGO_LIVE_AI=1`で開始したが、約3分進まなかったため終了した（xcodebuild終了コード75）。APIキーの再登録・置換・削除・アクセス権変更はしていない。

呼び出しスタックの採取で、`InsightEvaluationTests.swift:114`の事前確認から`GeminiCredentials.swift:28`の`SecItemCopyMatching`、Security frameworkの復号処理応答待ちでメインスレッドが停止していることを確認した。これはGeminiの応答待ちではない。評価ループ開始前であり、28ケースの評価は未実施、追加API要求は0件。

`codesign -d -r-`では、保存元の`/private/tmp/conflingo-pr6-build/`内アプリと、今回の`/private/tmp/conflingo-pr6-acceptance-build/`内アプリのdesignated requirementが異なるcdhashだった。プロジェクトはad-hoc署名設定であり、別ビルドのKeychainアクセス判定が影響している可能性がある。ただし、OS側の停止理由や権限要求の有無は確定していない。Keychain失敗を返す経路・UIをブロックしないことも今後の確認対象とする。

ログ: `/private/tmp/conflingo-pr6-keychain-live-tests.log`。スタック証跡: `/private/tmp/conflingo-pr6-keychain-sample.txt`。通常アプリの登録成功、別テストホストの読み出し停止、Gemini実通信成功を混同しない。
