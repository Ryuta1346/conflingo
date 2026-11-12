# クラウド／ローカルLLM選択 検証記録

2026-11-12 / feature/llm-selection

## 結果

Gemini / OpenAI / Claude / Kimi / DeepSeek / その他OpenAI互換クラウド / ローカルLLMの接続追加・選択を実装した。ローカルはPCに導入したQwen等をOllama / LM Studio等のAPI経由で利用する。ChatGPTログインは対象外。

| 検証 | 結果 |
| --- | --- |
| 全回帰テスト | **462 tests / 79 suites 合格**（実APIのオプトイン評価は無効） |
| SwiftLint 0.65.1 | **178ファイル、違反0** |
| git diff --check | 合格 |
| Debug署名ビルド | 成功。App Sandbox・network.client有効、ATSはNSAllowsLocalNetworkingのみ追加 |
| Release署名ビルド | 成功 |
| 各社API契約 | 合成HTTP/SSEで送信先・認証・モデル・構造化応答・分割UTF-8・中断・完了判定を検証 |
| 接続設定 | 複数接続の復元、キー分離、既存Geminiキーの保存先維持、URL変更時のキー削除を検証 |
| 切替 | キー読出し中の変更でHTTP送信を防止。会議中の接続変更で生成・許可を解除。モデル変更で要約確認を失効 |
| ローカル実通信 | 署名済みアプリから127.0.0.1の模擬サーバーへGET一覧1回・POST合成生成1回成功。両方Authorizationなし |
| 実モデル | 新しいクラウド各社およびQwenの生成は未実施 |

## TDDと主な回帰

- 接続設定・APIアダプタ・一覧取得・会議結合のテストを先行し、対象型／引数が未実装のため失敗することを確認して実装した。
- 追加のプレビュー分離テストで、保存済みのカスタム接続が実Keychainストアを選ぶ不具合を実際に再現。プレビューのすべての接続を模擬ストアへ統一し、全テスト合格を確認した。
- Geminiのプロンプトと結果検証を共通化し、既存の送信内容・回答言語・資料引用・要約のテストを維持した。
- OpenAIの推論itemが本文より先行する応答と、思考トークンの二重計上防止を検証した。
- Kimi / DeepSeekのJSONモード、Claudeのoutput_config、OpenAIのResponses API、互換サーバーのChat Completionsをそれぞれモックで検証した。
- 接続先のhost・port・path境界、ローカルHTTPの許可範囲、認証ヘッダーの付与先、途中終了・出力打切り・不正JSONを検証した。

## 画面操作とローカルHTTP

`--meeting-preview --meeting-state=setup`で起動し、音声取得なしで確認した。

1. Meetingの「LLM設定」から接続追加を開き、Gemini / OpenAI / Claude / Kimi / DeepSeek / その他クラウド / ローカルLLMを確認。
2. ローカル接続の入力欄、Ollama / LM StudioのURLボタン、任意APIキー、応答形式を確認。
3. 一時ローカルサーバーからモデル一覧を取得し、`conflingo-fixture`が候補に表示された。モデルID手入力で保存し、選択中の接続・モデル・URL・キー任意表示を確認。
4. 「接続を確認」を実行し、「接続と応答形式を確認しました」を確認。サーバー側でも一覧取得・生成に認証ヘッダーがないことを確認した。
5. 検証サーバーを終了。通常の利用者設定ではなく、既存のプレビュー用UserDefaults領域を使用した。

モデル一覧からの選択操作自体は保存まで一貫して検証していない。VoiceOver全経路・狭幅表示も未検証。

## 再実行

```sh
xcodebuild test -project ConfLingo.xcodeproj -scheme ConfLingo -destination 'platform=macOS' -derivedDataPath /tmp/conflingo-llm-build CODE_SIGNING_ALLOWED=NO
swiftlint lint --strict --no-cache
xcodebuild build -project ConfLingo.xcodeproj -scheme ConfLingo -configuration Release -destination 'platform=macOS' -derivedDataPath /tmp/conflingo-llm-release CODE_SIGN_IDENTITY=-
```

初回の制限環境ではSwiftマクロの実行が拒否されたため、許可されたXcode実行環境で検証した。リントは既存のローカルSwiftLint 0.65.1を使用。

## 制約と未検証

- このPCのOllamaは稼働しているが、`ollama list`の導入済みモデルは0件だった。Qwenのダウンロードやインストールはしていない。
- 新規クラウドへの有料生成要求は0。各社の実際のアカウント権限・モデルの応答品質・速度・料金は未検証。既存Geminiの過去の品質合格を新しいモデルへ流用しない。
- モデル一覧は先頭ページ。未掲載モデルはID手入力できる。構造化応答への対応はモデル／サービスごとに接続確認が必要。
- 質問30秒・要約区間60秒の既存期限を維持。ローカルのモデル起動・CPU推論が遅い場合も適用する。
- ローカルは同じMacのloopback接続。サーバーが外部へ転送しないことはConfLingoから保証しない。
- /Applicationsへのインストールは実施していない。

## 公式仕様の確認先

- [OpenAI Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs)
- [Claude streaming](https://platform.claude.com/docs/en/build-with-claude/streaming)
- [Claude output_config型](https://github.com/anthropics/anthropic-sdk-python/blob/main/src/anthropic/types/json_output_format_param.py)
- [Kimi JSON Mode](https://platform.kimi.ai/docs/guide/use-json-mode-feature-of-kimi-api)
- [DeepSeek JSON Output](https://api-docs.deepseek.com/guides/json_mode/)
- [Ollama OpenAI互換API](https://docs.ollama.com/api/openai-compatibility)
- [LM Studio OpenAI互換API](https://lmstudio.ai/docs/developer/openai-compat)
