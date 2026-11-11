# PR7 計測付き残区間評価

2026-11-11 / `feature/pr8-quality-acceptance`。既存Draft PR #19と同じブランチ。
[追加計画](../design/pr7-summary-timeout-plan.md)をユーザー「すすめて」で承認後に実装した。**ローカル検証完了・追加評価は1/3会議／3/8区間合格、受信途中のtimeoutで停止**。

## 実装・ローカル検証

- `SummaryEvaluationRun`で初回22区間／US$2と今回8区間／US$1を固定する。ケース、上限、評価IDを任意の環境変数で増やせない。新旧台帳の取り違え、消費済み台帳の再開、PR6/PR8/初回PR7との同時live起動を拒否する。
- 評価wrapperに単調時計による計測を追加。client開始、transport到達、計数、生成、最初／最後のchunk、最初のプレビュー、ストリーム終了、使用量確定、loopback通知、client終了を記録する。本文を保存せず、chunk数・byte数・最大プレビュー文字数を保持する。
- 未到達のstageはnull。成功だけでなくtimeout・取消・usage欠落でも観測済みの時刻を保存する。保存失敗時は後続送信を停止する。coordinatorの終端状態と会議単位の経過時間も別記録する。
- 製品72ソースのSHA-256は前回評価と一致。fixtureの本文・発話生成・必須根拠は変更せず、評価選択部分のみ変更した。モデル、プロンプト、区間分割、製品の30秒期限は維持。
- 変更前は361テスト／60 suites（2.325秒）、最終は**367テスト／62 suites（2.440秒）成功**。
- TDD Redは計測型・固定追加枠の未実装を確認。途中の先行テスト構文誤りを直した後、意図したRedを取得した。Greenは関連19テスト／5 suites成功。
- 応答前／途中の短縮timeout、完了後の遅い観測通知、usage欠落、計測保存失敗、旧台帳の不変、8区間だけの許可と16要求上限を偽HTTPで検証。
- SwiftLint strict/no-cacheは**141ファイル・違反0**。Debugテストビルド、build-for-testing、Releaseビルド、差分チェック成功。

ログ: `/private/tmp/conflingo-pr7-remaining-{baseline,red,green,full,lint,release,build-for-testing}.log`。

## 評価の条件

- S08-ja（3区間）→S08-en（3区間）→S07-en（2区間）の順で、各区間1回だけ実行する。生成8＋計数8の最大16要求、推定US$1以内。
- 新台帳はApplication Support配下の`ConfLingo/Validation/pr7-summary-remaining-20261111/ledger.json`。初回台帳の30要求・不明分予約US$0.042264は保持する。
- 2026-11-11に[公式Standard料金](https://aistudio.google.com/docs/pricing#gemini-3.8-flash)と[計数の課金条件](https://discuss.ai.google.dev/t/direct-gemini-developer-api-counttokens-free-tier-billing-and-quota-clarification/190706)を再確認。入力US$0.75、思考込み出力US$3.75／各100万token、計数無料。8区間の上限想定は20%余裕込みUS$0.338112。
- 初回起動は製品Keychainの`.keyStorage`で停止（新台帳0件、外部要求0件）。キーを表示・変更しない既存の読取専用確認と利用者のOS操作で`KEYCHAIN_READ_STATUS=0`を確認（61.042秒）。同じビルドで再開した。
- 本文は認証付きloopbackサーバーのメモリのみで意味判定し、メタデータと判定を保存した後に破棄する。成功しても初回のtimeout履歴を書き換えない。

## 実API結果

[本文を含まない全件記録](pr7-summary-remaining-2026-11-11.json)に、判定・根拠ID・計測値・台帳・ソースハッシュを保存した。完成3回答の意味・言語は主担当がメモリ上で確認し、構造・Markdownは評価コードで確認した。

| ケース | 結果 | 確認内容 |
|---|---|---|
| S08-ja-1 | 合格 | 120万円の予算案と追加決定なし、先頭発話の根拠を保持 |
| S08-ja-2 | 合格 | 120万円→90万円の訂正と未承認、中間区間の根拠を保持 |
| S08-ja-3 | 合格 | 予算承認待ち・担当／期限未定、末尾発話の根拠を保持 |
| S08-en-1 | timeout | データとプレビューを受信したが、30秒で取消。完成・usage未取得 |
| S08-en-2/3 | 未実施 | 先行区間の失敗で停止 |
| S07-en-1/2 | 未実施 | S08-en-1の失敗で停止 |

追加評価は**1会議合格・1失敗・1未実施／3会議、3区間合格・1timeout・4未実施／8区間**。全件合格条件は未達。初回と合わせた固定コーパスの確認済み範囲は**14/16会議・17/22区間**で、未合格5区間が残る。2回のtimeoutを初回成功へ書き換えない。

S08-ja-2は`decisionCandidate`分類で「訂正が提案されている」と表現した。予算案の変更方向・数値・未承認を保持しており今回の条件は合格。要約は未確認のsectionとして保存され、候補確認の操作を代行しない。分類と表現は観測事項として残す。

## タイミングの所見

以下は各client開始からの秒数。計数欄だけはcount開始→完了の差分。初回chunkは製品transportのバッファ後の観測値。

| 区間 | 計数 | 初回chunk | 初回preview | 最終chunk | client終了 | 状態 |
|---|---:|---:|---:|---:|---:|---|
| S08-ja-1 | 0.210 | 21.450 | 21.452 | 28.619 | 28.623 | complete |
| S08-ja-2 | 0.188 | 24.708 | 24.708 | 25.552 | 25.557 | complete |
| S08-ja-3 | 0.209 | 4.358 | 4.358 | 5.026 | 5.029 | complete |
| S08-en-1 | 0.190 | 23.286 | 23.383 | 29.746 | 30.036 | cancelled |

- 失敗区間は92 chunk・19,096 byteを受信し、最大195文字のプレビューがあった。`streamEnd`、`usageSettled`、`observerStart`はnull。coordinator終端は`failed(timeout)`で、完成要約は0件。ストリーム受信中に全体期限が切れたことを確認した。
- 失敗区間は計数約0.19秒。loopback通知には未到達。計数や完成後の通知待ちが30秒を占有した事例ではない。
- 日本語の30発話区間も25.56〜28.62秒と期限に近い。S08-ja-1の出力／思考は1162／2733 token、S08-ja-2は107／3221 token。多数の引用による出力量だけで遅延を説明できず、初回応答前の待ちも大きい。
- 最初のデータ到着までの時間にはネットワークとAPI内部処理が含まれる。その内訳と、初回S07-en-1の具体的な停止段階は未特定。今回の観測を初回の欠けた記録へ遡及適用しない。
- live XCTestは89.306秒で失敗。S08-ja全体は59.210秒、S08-enは30.039秒で停止。成功3区間だけの統計で性能Gateを判定しない。

## 費用・保全

- 新規送信は計数4＋生成4＝**8/16要求**。新台帳は7件complete・1件reserved。生成3件の入力8,907、出力1,355、思考6,242 token。
- 新枠の既知推定額US$0.035169＋不明分予約US$0.042264＝**推定管理額US$0.077433**。旧枠込みでは38要求、既知US$0.0989775＋不明予約US$0.084528＝**US$0.1835055**。実請求額ではない。
- 旧台帳・旧結果JSONは不変。新旧ともusage不明の予約を保持し、残枠を自動消化しない。
- 実行前後で141ソースのSHA-256一致を確認。結果保存後、受信サーバーを停止し、本文をメモリから破棄した。
- ログは`/private/tmp/conflingo-pr7-remaining-live-authorized.log`、初回認証失敗は`/private/tmp/conflingo-pr7-remaining-live.log`、OS認証は`/private/tmp/conflingo-pr7-remaining-keychain-authorize.log`。台帳・区間別timing・case-statesは新評価IDのApplication Supportフォルダに保持する。

## 次の対応

今回の観測に基づき、会議終了後の要約だけ期限を60秒とし、会議中の質問・自動提案は30秒のままにする[修正計画](../design/pr7-summary-deadline-plan.md)を作成した。coordinator、HTTP要求、URLSessionの期限を一緒に整合させる。これは今回の計測計画に含まれない製品変更なので、実装と追加実API枠は後続のユーザー「susumete」で承認された。

## 判定上の制限

最初のchunkは製品transportの改行／1024byteバッファ後の時刻であり、生の初回byteやHTTPヘッダー時刻ではない。DNS/TCP/TLSやサーバー内部処理時間は計測しない。今回再発しなくても、初回timeoutの原因解消や長期の安定性を証明しない。実音声・60分耐久・PR7全体・Gate Cは別の受入として維持する。

後続の[期限修正・再評価](pr7-summary-deadline.md)は承認後に実装し、8/8区間合格。3回の評価を通じ16/16会議・22/22区間を確認。本資料の失敗履歴と旧台帳は保持する。
