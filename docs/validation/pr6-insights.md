# PR6 — AI会話理解・根拠付き回答 検証記録

2026-11-08 / `feature/insight-engine` / 基点 `e167765`

状態は **REVIEW**。ユーザーが[実装計画](../design/pr6-implementation-plan.md)を承認した後、TDDで実装した。Gemini直接接続のコードとモックでの操作・障害処理を検証済み。実際のGeminiへの通信、品質・遅延・費用、実音声受入は未検証。実装コミットは`a512255`。[Draft PR #12](https://github.com/Ryuta1346/conflingo/pull/12)を作成済み。マージは未実施。

## 実装した範囲

- Gemini BYOK、Keychainでのキー登録・置換・削除、会議ごとの送信許可、手動Ask AI、ストリーミング、根拠発話への移動。
- 自動提案は初期オフ。オン時もローカル検出、最大2件/分・最短12秒間隔、重複抑制、文脈・出力上限で呼び出しを制限。失敗後は自動提案をオフにし、通信を自動再試行しない。
- Pause/End/破棄/入力障害/許可取消/キー変更で通信を取り消し、遅延応答を破棄。AI購読の障害は必須の字幕購読から分離。
- `InsightClient`をGeminiとfakeで共用。運営Proxy、他社モデル、サブスク連携、候補確定、保存、資料検索は後続。

## 自動検証

| 検証 | 結果・証跡 |
|---|---|
| 着手前ベースライン | 236テスト、31 suites成功。`/private/tmp/conflingo-pr6-baseline.log` |
| 最終Debugテスト・ビルド | 263 tests / 39 suites成功。実API評価1件は明示スキップ。`/private/tmp/conflingo-pr6-tests.log` |
| Releaseビルド | 成功。`/private/tmp/conflingo-pr6-release.log` |
| SwiftLint | 100ファイル・違反0。`/private/tmp/conflingo-pr6-lint.log` |
| 差分の空白等 | `git diff --check`成功 |

最終テストのxcresultは`/private/tmp/conflingo-pr6-build/Logs/Test/Test-ConfLingo-2026.11.08_23-33-04-+0900.xcresult`。これらはローカル一時ファイルであり、永続的なCI証跡ではない。SwiftLintはキャッシュ保存権限エラー後、`--no-cache`で成功。Releaseでは既存のContentViewの到達不能コードとAppIntentsメタデータ抽出省略の警告が残る。今回追加したKeychainの非推奨API警告は解消した。

### 契約別の証跡

| 計画の受入条件 | 確認した内容 |
|---|---|
| I01–04 | `InsightRequestTests` / `InsightCoordinatorTests`：許可・final・会議ID・文脈上限、手動優先、自動頻度、許可前発話の自動送信除外 |
| I05–06 | 根拠ID照合、不正IDの要確認扱い、取消・期限・旧会議からの遅延応答拒否。根拠移動は下記UI操作で確認 |
| I07 | `MeetingAIIntegrationTests`：実controller＋fake音声入力。停止がAIを待たない、再開、入力障害、キー変更、任意購読のキュー超過時も字幕を維持 |
| I08–09 | `GeminiInsightClientTests` / `InsightHTTPTransportTests`：UTF-8分割、構造化JSON、正常終端、異常終端、不正・過大応答、HTTPエラー、キー未設定、再試行なし |
| I10 | 主画面と小窓の操作をfakeで確認。既存レイアウトテスト成功。文字拡大・全キーボード操作は未検証 |
| I11 | 全カードを候補表示。発話を指示と分離するプロンプトとツール未提供をコード確認。注入例を含む合成コーパスを用意したが、実モデルの耐性は未検証 |
| I12 | 既存テストを含む全テスト成功。実音声・実翻訳・保存操作の実機受入は従来どおり未検証 |
| I13 | 実LLM評価の手順と未実施を下記に記録。品質・遅延・使用量の実測は未取得 |
| I14–15 | `GeminiCredentialsTests`：専用の一時Keychain項目で保存・置換・削除、fakeで保存失敗。HTTPテストで認証ヘッダーとリダイレクト拒否、共通境界の差し替えを確認 |

Red→Greenは要求組み立て、調整、Gemini/Keychain、Meeting結合ごとに実施。最終セルフレビューでは「通信失敗後も自動提案がオン」「許可取消直前に予約されたTaskが後から通信を開始する」の2点を追加の失敗テストで再現し、修正後に全テストを再実行した。別エージェントによる独立レビューは行っていない。

## 非録音のネイティブUI確認

Debugアプリの`--meeting-preview --meeting-state=live`を使用。合成発話・fake AI・fakeキー設定であり、実音声取得やGoogleへの通信は行っていない。

- 初期状態で送信許可・自動提案がオフ、許可後も自動提案はオフ。
- 日本語質問の入力、Ask AI、生成中から完了への更新を確認。新しい回答を先頭に表示し、根拠を選ぶと対象発話の00:00へ移動。
- 送信内容の説明は許可前に展開し、許可後は折りたたみ可能。キー設定シートの表示を確認したが、実キーは入力していない。
- 小窓でAI停止後、展開しても音声入力の状態を保持し、AI許可を取り消した状態を共有。
- Pause後は入力とAIが停止し、Ask AIは無効、再開操作を表示。

操作結果は画面とアクセシビリティツリーで確認した。スクリーンショットファイルは保存していない。プレビューは最後に一時停止した。

## 合成会話による実API評価（未実施）

`InsightEvaluationTests.swift`に日本語10件・英語10件を用意。質問、曖昧さ、料金不明、リスク、決定/アクション候補、雑談、反復、指示注入、矛盾を含む。ローカル検出のテストは実行済み。

実API評価は通常のテストでは無効。利用者が通常アプリの設定でGemini APIキーを登録し、利用するGoogleプロジェクトの課金・データ条件を確認した後、次を実行する。キーをコマンドやチャットへ貼らない。

```sh
TEST_RUNNER_CONFLINGO_LIVE_AI=1 xcodebuild test \
  -project ConfLingo.xcodeproj -scheme ConfLingo \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/conflingo-pr6-build \
  -only-testing:ConfLingoTests/GeminiLiveEvaluationTests
```

このコマンド自体は未実行。実行時は最大20要求を順次送り、再試行しない。キーはアプリ専用Keychainから読み、既存キーの変更・削除を行わない。モデルは`gemini-3.1-flash-lite`、出力上限1024、思考レベルminimal。アクセス不可時に他モデルへ自動切替しない。

成功時の記録はテストプロセスの一時ディレクトリに`conflingo-pr6-live-evaluation.json`として出力する。ケースID、秒数、種別、根拠数・不正ID有無、取得できたトークン数のみを含み、キー・質問・発話・回答本文は保存しない。自動評価は構造と参照IDの検査までであり、回答内容の正確さ・根拠の意味的妥当性・誤提案は別途目視評価が必要。実測前に品質や費用の合格を主張しない。

## 残る受入

実Gemini接続・品質・取消・使用量、実音声/2入力STT、VoiceOver、文字拡大と全キーボード操作、画面共有、長時間性能、独立コードレビューは未実施。Gate A/B/C/U/D全体は未検証を維持する。API通信取消は、Googleへ既に送った内容の撤回・課金取消を保証しない。
