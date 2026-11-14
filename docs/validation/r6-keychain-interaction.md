# R6-4 — Keychain操作の排他制御・設定復元

2026-11-14 / 基点: ローカルmain `18d0fcb`＋未コミット変更。
状態: **承認済み範囲をローカル実装・自動検証済み（REVIEW相当）。未コミット・未PR。独立レビュー・実機受入は未実施。**
[実装計画](../design/r6-keychain-interaction-plan.md)。

## 変更

- 全接続の`KeychainAPIKeyStore`が共有する`KeychainOperations`へSecurity操作を集約した。`Mutex`で読出し・保存・削除を直列化し、Update→必要時Addも一続きの処理として保護する。
- 読出し時の認証UI設定を、項目取得の成否にかかわらず元のtrue/falseへ戻す。設定の取得・非対話化・復元失敗を`InsightFailure.keyStorage`として扱う。
- 復元失敗時は元設定を保持する。次の操作の先頭で復元を1回試み、成功するまで項目の読出し・保存・削除を行わない。復元失敗を「キーなし」や読出し成功として返さない。
- Security APIの最小境界をfakeへ差し替えられるようにし、実OSの設定を競合させずに故障・競合を検証する。製品のSystem adapterは同じファイル内に限定した。
- 既存の保存先・service/account・ACL・署名条件を維持した。readはバックグラウンド、save/deleteは既存の同期APIを維持。UI変更・キー移行はない。

## TDD・確認結果

| 検証 | 結果 |
|---|---|
| Red | 既存動作をSecurity境界へ抽出した段階で3テスト定義・12 issues。readの非対話区間中に別接続のsave/deleteが進むこと、復元失敗でもキー/nilを返すことを確認 |
| Green | 共通排他・復元処理の追加後、Keychainと既存資格情報の10テスト定義が成功 |
| 関連回帰 | Keychain・資格情報・接続設定・クライアント・Meeting結合の33テスト定義／6 suites成功 |
| 並行テスト修正後 | Keychainと既存AssistanceReviewRegressionの15テスト定義／2 suites成功、2.067秒 |
| 追加の設定失敗・字幕UI | LLMSettingsとLiveTranscriptLayoutの8テスト定義／2 suites成功、4.415秒 |
| 最終全体 | 全667テスト定義中660成功・実API7skip・失敗0、121 suites、165.252秒。Xcodeの並列テスト無効で成功 |
| Lint | strict/no-cache、251ファイル・違反0 |
| Release | arm64/x86_64ビルド成功。インストール済みアプリは更新していない |

追加は11テスト定義（パラメータ展開38ケース）。既存のKeychain往復は一意のテスト用serviceに合成キーを保存・置換・削除する。利用者の既存キーは変更しない。

### 受入条件との対応

| 条件 | 証跡 |
|---|---|
| K01/K02 | 異なるserviceのread→read/save/delete。元設定true/falseの双方で、設定復元後に次のSecurity操作へ進む |
| K03 | Updateが項目なしの場合、別接続のread/save/deleteをAdd後まで待たせる。Update成功・その他エラーではAddしない |
| K04 | 成功、項目なし、OSエラー、不正な型・UTF-8、nil応答での復元・結果分類 |
| K05 | 設定取得・非対話化・復元の失敗、復元が繰り返し失敗する間の全項目操作抑止、復元成功後の回復。元設定falseも保持 |
| K06 | Update/Add/Delete失敗後も次の操作が進む。未登録項目の削除を成功扱いし、元設定falseを変更しない |
| K07 | 既存`APIKeyCredentialsTests.keychainRoundtripUsesUniqueTestItem`と、queryの保存契約の確認 |
| K08 | 既存refresh世代・Gemini取消・LLM設定変更時の送信停止。追加テストで復元失敗時に接続先変更/削除を保存せず、回復後に確定することを確認 |

## 途中の失敗と切り分け

1. 最初のサンドボックス内ビルドはSwiftマクロpluginの起動に失敗した。これはRedの証拠ではない。権限付き再実行でテスト本体の12 issuesを確認した。
2. 最初の全体実行は666テスト定義／121 suites、14 issuesで失敗。新しい並行テスト9ケースでGCDの共有プール上の開始待ちが5秒に達した。同期待機を伴うテストを専用`Thread`へ移し、当該suiteをserializedにした。製品のlockや待機仕様は変更していない。
3. 同じ実行で既存`AssistanceReviewRegressionTests.preparationShowsAnswerCitationAndSaveActions`のAXツリーが空となり5 issues。製品・既存テストを変更せず、当該suiteを含む再確認で成功した。
4. 続く全体実行は666テスト定義／121 suites、54.054秒で既存`LiveTranscriptLayoutTests.meetingEvidenceRemainsVisibleDuringUpdatesThenReturnsToLatest`が1 issue。固定200msのレイアウト待ち後に合成翻訳がまだ未完了（0件、期待1件）だった。当該suiteの単独再確認は成功した。既存テスト・翻訳製品コードは変更していない。
5. 最終全体は接続設定の追加テストを含め、Xcodeの`-parallel-testing-enabled NO`を明示して実施。途中のUI不安定性を最終結果で抹消しない。

並行テストは開始・解放の合図と終了順を検証し、0.2秒の観測区間では後続操作が完了しないことを確認する。開始/終了には5秒の上限を置き、失敗時にもgateを解放する。これはOS処理時間の測定や性能合格基準ではない。

## 再実行・成果物

```sh
env CONFLINGO_LIVE_AI=0 CONFLINGO_FOCUSED_LIVE_AI=0 \
  CONFLINGO_GROUNDING_LIVE_AI=0 CONFLINGO_RAG_LIVE=0 \
  CONFLINGO_SUMMARY_LIVE=0 CONFLINGO_SUMMARY_REMAINING_LIVE=0 \
  CONFLINGO_SUMMARY_DEADLINE_LIVE=0 CONFLINGO_R2_SIZE_LIVE=0 \
  xcodebuild test -project ConfLingo.xcodeproj -scheme ConfLingo \
  -destination 'platform=macOS' -derivedDataPath /tmp/conflingo-r5-build \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO
/tmp/conflingo-swiftlint-0.65.1/swiftlint lint --strict --no-cache
xcodebuild -project ConfLingo.xcodeproj -scheme ConfLingo \
  -configuration Release -derivedDataPath /tmp/conflingo-r5-release \
  CODE_SIGNING_ALLOWED=NO build
```

自己レビューでは、製品のSecurity呼出しが共有境界へ集約されていること、lock内にawait・MainActorへの同期呼出しがないこと、旧read専用lockを削除したことを確認した。独立レビューとは区別する。

ログ: `/tmp/conflingo-r6-4-{red,green,focused,full,recheck,full-recheck,layout-settings,final,lint,release}.log`。一時ファイルの証跡であり、永続的なCI成果物ではない。

最終xcresult: `/tmp/conflingo-r5-build/Logs/Test/Test-ConfLingo-2026.11.14_20-51-31-+0900.xcresult`。`xcresulttool get test-results summary`の集計は`/tmp/conflingo-r6-4-test-summary.json`（660成功・7skip・0失敗）。集計キャッシュ書込みには権限付き再実行が必要だった。

## 未検証・制約

独立レビュー、実アプリの認証要求・Keychainロック/解除・新署名での既存キー読出し、実音声・実API・60分耐久は未実施。同期save/deleteは実行中のreadを待ち得る。プロセス全体設定の保護はアプリのストア経路に限定する。実OSで復元失敗を強制した結果ではない。

Keychainの非推奨API、ContentViewの到達不能コード、AppIntentsメタデータ抽出省略の既存ビルド警告は残る。今回の全体実行で観測した既存UIのタイミング不安定性も残件とする。

実API送信・実音声取得・モデルダウンロード・インストール済みアプリ更新・コミット・PR作成は行っていない。R6やGate全体をDONEへ変更しない。
