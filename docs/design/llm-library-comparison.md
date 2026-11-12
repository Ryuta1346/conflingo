# ConfLingo LLMライブラリ比較

調査日: 2026-11-12
状態: 2026-11-12、ユーザーが現行の自前実装の維持を決定。SDK移行は見送り。

## 決定

2026-11-12、ユーザーの「OK、では一旦今の自前を維持」により、現行の自前LLM接続実装を維持する。

- 今回はSDKの導入・置換、LiteLLM等の補助プロセス追加を行わない。
- 既存のプロバイダー選択・モデル指定・APIキー管理・OpenAI互換接続を継続する。
- 独自APIへの対応増加やAPI追従の保守負担が顕在化した時点で、部分的なSDK導入を再検討する。
- 以下は判断時の比較記録であり、ライブラリ移行の承認済み計画ではない。

## 比較時点の提案（最終決定は上記）

Swift単体で完結する候補内では **teunlao/swift-ai-sdk v0.20.0** を機能面から推奨していた。ただし、下記の追加調査により、普及規模を優先する全体比較の第一候補とは位置づけない。
複数社を共通APIで扱い、任意の接続先・モデル・利用者APIキーを設定できることがConfLingoの中心要件。当時はAPI通信と応答解析をSDKへ移す案を検討したが、最終的に移行は見送った。

これは公式README・公開ソース・Package.swift・リリース情報からの判断。ConfLingoへの組込みビルド、各SDKのテスト実行、実クラウド/Qwenの生成は今回実施していない。採用の最終技術判定には小規模な結合検証が必要。

## 追加比較: 一般性・普及規模を優先する場合（2026-11-12）

前の比較はSwiftの統合SDKに限定しており、広く使われるLLMライブラリ全体の比較としては不十分だった。Swift版AI SDKはVercel公式SDKそのものではなく、別のコミュニティ実装である。

GitHub公式APIで確認したスター数（利用者数・導入社数ではなく、関心/コミュニティ規模の参考値）:

| 候補 | スター数 | 言語・構成 | ConfLingoへの適用 |
|---|---:|---|---|
| Vercel AI SDK | 27,872 | TypeScript | 統合生成API・構造化出力・ストリーミング。SwiftからはNode等の補助プロセス/サービスを介して利用する設計になる |
| LiteLLM | 63,131 | Python SDK / Gateway | 各社APIを共通形式へ変換。既存のOpenAI互換クライアントからProxyへ接続できる。ローカル常駐プロセスの配布/起動管理が増える |
| LangChain | 149,379 | Python（JS版は別リポジトリ） | 幅広いモデル連携・エージェント機能。今回の接続統一だけなら、より目的の狭い上記2候補を先に評価する判断 |
| MacPaw/OpenAI | 2,963 | Swift | OpenAIとOpenAI互換の接続に使える。Claude/GeminiのネイティブAPIをこれ一つで統一できるSDKではない |
| teunlao/swift-ai-sdk | 157 | Swift | 機能適合性は高いが、一般的な定番と評価する根拠は弱い |
| AIProxySwift | 448 | Swift | 直接BYOKクライアントの候補。統合APIはアプリ側で補う |

### 選択の意味

- **広く使われる統合層を優先**: LiteLLMとVercel公式AI SDKを本命として評価する。本件のAPI接続統一に絞ればLiteLLMが目的に近い。生成処理・構造化出力をTypeScriptで組み立てるならVercel AI SDKが合う。
- **Swiftアプリ単体での配布を優先**: MacPaw/OpenAIをOpenAI互換部分に使い、専用APIが必要な部分を別クライアントで補う案がある。複数SDK/変換コードは残る。
- Vercel AI SDKはVercelへのデプロイやAI Gateway利用を必須にせず、providerを明示して直接API接続できる。
- 同じPCのQwenを使う場合、中継層も同じPCに置くか、ローカル接続だけアプリから直接行う。クラウドサーバーから利用者PCのlocalhostへ接続する設計にはしない。
- 補助プロセスの配布・署名・Sandbox・起動停止・キーの受渡しは新しい実装範囲になる。現時点で実現性を検証済みとは扱わない。

### 一次情報

- [Vercel AI SDK](https://github.com/vercel/ai)
- [カスタムOpenAI互換provider](https://github.com/vercel/ai/tree/main/packages/openai-compatible)
- [LiteLLM](https://github.com/BerriAI/litellm)
- [LiteLLM Proxy](https://github.com/BerriAI/litellm/tree/main/litellm/proxy)
- [LangChain](https://github.com/langchain-ai/langchain)
- [MacPaw/OpenAI](https://github.com/MacPaw/OpenAI#using-the-sdk-for-other-providers-except-openai)

## 前提

- 現行アプリはmacOS 26、Swift 6。中継サーバーを運用せず、Macから各社/同一PCのLLMサーバーへ接続する。
- Gemini / OpenAI / Claude / Kimi / DeepSeek、任意のOpenAI互換サービス、Ollama / LM Studioを対象にする。
- サービスとモデルIDは利用者が選択し、キーは接続ごとにKeychainで保持する。
- 会議回答はJSON構造、引用検証、途中表示、キャンセル、トークン使用量が必要。
- 既存の送信先境界・リダイレクト拒否・応答サイズ上限・タイムアウト・接続変更時の失効を維持する。

## 比較

| 候補 | 適合点 | 課題 | 判断 |
|---|---|---|---|
| teunlao/swift-ai-sdk | 共通生成API、専用のOpenAI/Anthropic/Google/Moonshot/DeepSeekモジュール、OpenAI互換、構造化出力、fetch差替え | 多機能で内部規模が大きい。0.x系。既定リトライ/期限/構造化出力の動作を調整する必要 | 第一候補 |
| AIProxyTeam/AIProxySwift | 各社の型付きAPIクライアント、直接BYOK接続、OpenAI Base URL変更、ストリーミング | 各社のリクエスト/イベントをアプリで共通化する作業が残る。直接通信のfactoryに任意transport注入引数がない | 第二候補 |
| zaidmukaddam/swift-ai-sdk | 共通API、Ollama/LM Studio/互換接続、構造化出力、URLSession注入、外部パッケージ依存なし | teunlao版とは別製品。調査時最新リリース0.3.0。今回確認した公開テスト/変更履歴の蓄積はteunlao版より少ない | 軽量な構成を優先する場合の候補 |
| aktagon/llmkit-swift | 共通API、ローカル接続、URLSession注入、外部パッケージ依存なし | READMEがセキュリティ修正のみのMaintenance modeを明記。新プロバイダー/モデル/機能を追加しない | 今回は不採用を推奨 |
| 現行自前 | アプリの制約に最適化済み、依存なし | 各社JSON/SSE/使用量/モデル固有差異を継続保守する | 全面的な継続は推奨しない |

SDK対応は任意の独自APIとの自動互換を意味しない。互換APIの細かな差異やモデルのJSON出力能力は、いずれでも接続確認が必要。

## 調査した版と保守の根拠

| 候補 | 調査HEAD | HEADコミット日（各コミットの時差表記による日付） | 公開リリース等 | ライセンス |
|---|---|---|---|---|
| teunlao | 4e0230a06092583c4dd541071b1ce8e181821bf9 | 2026-10-17 | HEADはv0.20.0、同日リリース | Apache-2.0 |
| AIProxySwift | 57ad0946f022fa2467b3fda6ff4d8c30e19abf10 | 2026-11-07 | GitHub latest releaseは0.157.0 / 2026-08-28。HEADとは異なる | MIT |
| zaidmukaddam | d8d108ccf606a154647ef7eae948775a1e7aa969 | 2026-08-06 | 0.3.0 / 2026-08-06 | MIT |
| aktagon | 47e6bbd78520c6f8e7c5059f81b19e968a2a55d2 | 2026-11-02 | v2.0.0タグあり。GitHub latest releaseは取得不可 | MIT |

公開Tests配下のSwiftファイルはteunlao 490、AIProxySwift 67、zaidmukaddam 56、aktagon 0。これはテスト件数や品質評価ではない。aktagonはREADMEで別のテスト実行済みコードを参照しており、公開Swiftリポジトリにテストが見当たらないことだけを確認した。

teunlao版ではキャンセル、timeout、ストリーム継続/解放、OpenAI互換応答のテストソースを確認した。実行していないため合格は未確認。

## teunlao版を推奨する理由

1. 設定のprovider/modelを共通のLanguageModelへ変換でき、会議機能に各社の分岐が広がるのを避けられる。
2. OpenAICompatibleProviderSettingsにbaseURL、apiKey、任意headers、queryParams、fetch、supportsStructuredOutputsがある。モデルIDはStringで渡せる。
3. fetch差替えが公開されている。既存の送信先境界、リダイレクト拒否、サイズ上限、期限をアプリ側で維持する実装経路がある。
4. 構造化出力とSSE解析を委譲できる。会議の引用が実際に存在するか等の業務検証は引き続きConfLingoで行う。
5. プロバイダーは別のSwiftPM productになっており必要なものを選べる。Package.swiftの外部依存swift-argument-parserはplayground executable用で、選択するアプリ用productの実行時依存ではない。ただしパッケージ解決時の取得は別問題。

## 採用時に明示すべき設定

- バージョンをv0.20.0で固定して検証し、main追従にしない。
- 高水準APIのmaxRetries既定2を0にする。既存の再送方針・送信許可を変えない。
- fetchユーティリティの既定HTTP timeoutは24時間。既存の質問30秒/要約区間60秒に設定し、キャンセルも結合テストする。
- OpenAI互換のsupportsStructuredOutputsは既定false。利用者が選んだJSON Schema/JSONモード/プロンプト指定を正確に変換する。
- Claude構造化出力のautoモードにはモデルによる方式分岐がある。現行のJSON契約とツール呼出し禁止方針を維持できる設定を検証する。
- モデル一覧取得をSDKが一律に提供するとは確認できていない。現行のLLMModelCatalogは当面維持する設計が妥当。
- キーを環境変数へコピーせず、選択接続のKeychainから明示的に渡す。

## 採用判定用の小規模検証

実装計画の承認後、アプリ機能を大きく変える前に、模擬HTTP/SSEで次を確認する。

1. 3つの専用API形式（Gemini / Responses / Messages）とOpenAI互換で同じ会議JSONを受け取れる。
2. Kimi / DeepSeekのJSONモード、カスタムURL、任意モデルID、キーなしlocalhostが送信内容に正しく反映される。
3. 中断、30/60秒の期限、途中終了、上限超過、エラー、使用量を現行の契約に変換できる。
4. リダイレクト拒否、送信先変更時の失効、Keychainプレビュー分離を維持できる。
5. Releaseビルドと必要productのみの組込みを確認する。実測前にバイナリサイズや高速化を断定しない。

この検証が通れば自前のリクエスト/SSE解析を置換する。UI・Keychain・モデル一覧・プロンプト・結果の引用検証は必要な部分を維持する。実API品質確認は別に範囲を定める。

## 一次情報

- [teunlao Swift AI SDK](https://github.com/teunlao/swift-ai-sdk/tree/v0.20.0)
- [teunlaoリリース](https://github.com/teunlao/swift-ai-sdk/releases/tag/v0.20.0)
- [OpenAI互換設定](https://github.com/teunlao/swift-ai-sdk/blob/v0.20.0/Sources/OpenAICompatibleProvider/OpenAICompatibleProvider.swift)
- [fetchと既定timeout](https://github.com/teunlao/swift-ai-sdk/blob/v0.20.0/Sources/AISDKProviderUtils/FetchFunction.swift)
- [リトライ既定値](https://github.com/teunlao/swift-ai-sdk/blob/v0.20.0/Sources/SwiftAISDK/Util/PrepareRetries.swift)
- [AIProxySwift](https://github.com/AIProxyTeam/AIProxySwift)
- [AIProxySwift直接接続factory](https://github.com/AIProxyTeam/AIProxySwift/blob/57ad0946f022fa2467b3fda6ff4d8c30e19abf10/Sources/AIProxy/AIProxy.swift)
- [zaidmukaddam版](https://github.com/zaidmukaddam/swift-ai-sdk/tree/0.3.0)
- [aktagon保守モード宣言](https://github.com/aktagon/llmkit-swift/blob/47e6bbd78520c6f8e7c5059f81b19e968a2a55d2/README.md)
