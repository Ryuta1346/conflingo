# 構成ルート分離の検証

2026-11-14。基点: main `33c8ae6`＋第1段階の未コミット変更。
[計画](../design/app-composition-plan.md)。今回の7ソース/テストの[固定ハッシュ](app-composition-2026-11-14/hashes.json)。

## 実装

- `ConfLingoApp`が`AppComposition`を一つ保持し、サービス生成と起動引数・設定の選択を集約。
- `ContentView`はサービスを注入で受け取り、画面固有の表示状態と停止・遷移処理を保持。
- Meeting・小窓、Conference支援のLLM設定、入力所有権、ライブラリを同じ構成から渡す。保存形式と保存先は変更なし。
- Debug検証画面、通常プレビューのfake、実AIプレビューの明示2フラグ条件を維持。重複していたプレビューシナリオの引数読取りを削除。
- 既存の狭幅/支援表示テストとPreviewを新しい構成入口へ変更。README英日構成図・plan.mdを更新。

## 結果

| 確認 | 結果 |
|---|---|
| 先行テスト | 新規6テスト定義を先に追加。AppComposition型とContentView(composition:)の未実装によるビルド失敗を確認。既存動作の不具合を再現したRedとは区別 |
| 関連テスト | 27定義・7suite成功（17.347秒、パラメータ展開を別件数に数えない） |
| 通常並列の全体テスト | 688定義中681成功・7skip・失敗0。126suite、54.879秒。[xcresult集計](app-composition-2026-11-14/test-summary.json) |
| Lint | SwiftLint 0.65.1、strict/no-cache、259ファイル、違反0 |
| Release | 署名なしビルド成功。lipoでx86_64・arm64を確認 |
| 差分 | `git diff --check`成功 |
| 独立レビュー | サービス寿命/SwiftUI、契約/テストの2観点、指摘0。テストの独立再実行はなし |

新規テストは起動画面・合成字幕、注入設定、共有store/LLM設定/入力排他、合成Meeting使用中のConference拒否と停止後解放、View初期化し直しによる状態リセットの防止、キーワード/言語設定の保存、通常プレビューのキーstoreとInsightClient、明示実AIプレビューのシナリオ維持を確認する。実描画は既存の狭幅/支援表示テストを使用。Releaseのプレビュー引数無視と既定suiteの選択はコードとReleaseビルドで確認し、実機起動評価とは区別する。

[寿命レビュー](app-composition-2026-11-14/lifecycle-review.json)・[確認範囲](app-composition-2026-11-14/lifecycle-review-scope.md)、[契約レビュー](app-composition-2026-11-14/contracts-review.json)・[確認範囲](app-composition-2026-11-14/contracts-review-scope.md)。固定7ファイルと最終ソースのハッシュ一致を確認。

## 実行資料と範囲

- `/tmp/conflingo-composition-red.log`
- `/tmp/conflingo-composition-focused.log`
- `/tmp/conflingo-composition-full.log`
- `/tmp/conflingo-composition-lint.log`
- `/tmp/conflingo-composition-release.log`
- `/tmp/conflingo-remaining-build/Logs/Test/Test-ConfLingo-2026.11.14_22-29-52-+0900.xcresult`
- `/tmp/conflingo-remaining-release/Build/Products/Release/ConfLingo.app`

全実API評価フラグを0にし、実API7テストをskip。実音声・実キーの読取り・実API要求・実機VoiceOver・署名配布・リモートCIは実施していない。プレビューのWeb調査等の既存通信ポリシーは変更していない。

既存のKeychain非推奨API、テスト用AX非推奨API、AppIntentsメタデータ未使用の警告は残る。ContentViewのRelease到達不能分岐の警告は解消。

実装コミット済み・未マージ。次は共通支援/通知整理、SSE集約、CI。実機受入ゲートの合格や第2段階全体の完了とは扱わない。
