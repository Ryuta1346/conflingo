# LLM分岐・SSE集約と無通信CI

2026-11-14。基点: main `50f59d4`（PR #42までマージ済み）。
正本: `~/.coding-agents/docs/conflingo/main/llm-sse-ci-plan.md`。
ユーザー「LLM分岐／SSE集約 → CIの対応すすめて」により、残タスク計画第2段階3・4の実施承認を引き継ぐ。Planモード切替機能がないため、この文書を実装前に記録する。

## 予定する変更

1. Geminiとその他LLMで重複するSSEフレーミングを小さな`SSEFramer`へ移す。UTF-8行復元、CRLF、複数data行の改行結合、EOFの最後のイベント処理、総受信2 MiB・行/イベント64 KiBの上限を一か所に置く。イベントを逐次渡し、大量のイベント配列を保持しない。JSON解釈、[DONE]、各社固有の終端・usage・拒否判定はフレーマーに入れない。
2. 通常回答・Web調査の各社固有の要求body/pathを専用の要求生成型へ分離し、HTTP共通設定・認証・要求128 KiB上限を一か所に置く。Gemini/Responses/Claude/Chat Completionsの契約を維持する。通常回答の送受信ループを一本にし、既存Gemini専用入口も同じ要求生成・デコードを使用する。保存するprovider/接続形式、モデル一覧、Web調査の引用解析は変更しない。
3. `.github/workflows/ci.yml`とローカルからも使える検証スクリプトを追加する。macOS 26 arm64、Xcode 26.6（17F113）、SwiftLint 0.65.1を明示する。PR・main push・手動実行を対象に、Lint、通常並列の全テスト、署名なしReleaseのarm64/x86_64ビルドを行う。テスト成果物・ログを期限付きで保存し、失敗を握りつぶさない。workflowはread-only権限、同一refの旧run取消、timeoutを持つ。
4. 実API評価フラグは全て0、実APIテストをCIから明示除外し、キー・実音声を使わない。CIセットアップのツールダウンロードやGitHub成果物転送まで通信禁止という意味ではない。実会議・配布署名・リモートCIの成功をローカル成功から推定しない。

## 維持する契約

- Geminiのschema・thinking設定、OpenAIのstore=false・strict schema、Claudeのschema/version、互換APIのschema/json/prompt選択、モデル・タイムアウト・認証先を維持。
- [DONE]だけ/正常終端なし/終端後不正イベント、拒否、長さ超過、usageのthinking/cache計上、引用ID・本文/補足・改行を既存テストで確認。
- 取消・設定revision変更による古い応答棄却、部分プレビュー、失敗診断の1回記録を維持。新たな再試行や送信先を追加しない。
- 実装時はコミット・pushを対象外とし、後続のユーザー「コミットしてPR作成」により承認を受領。実機ゲートは継続する。

## 実装・検証順

資料更新 → 先行テスト（フレーマー未実装のRedと公開クライアントの契約テスト）→ SSE集約 → 要求生成/実行経路整理 → 関連テスト → CI追加 → 全テスト・SwiftLint strict/no-cache・Release両CPU → 差分確認・結果記録。

- フレーマー: 1byte分割・絵文字・CRLF・無視フィールド・空data・複数イベント・EOF・不正UTF-8、行/イベント/総受信の上限と次イベントへのリセット。
- 各社: 既存の正常/異常終端、usage、引用、上限回帰を維持。Geminiの選択経路・モデル・要求、取消後の遅延chunkを合成transportで検証。
- CI: YAML/シェル構文検証、同じスクリプトのローカル実行。リモートrunは未実施として残す。

## 環境根拠

GitHub公式[macOS 26 arm64イメージ](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md)でXcode 26.6 / 17F113を確認。ローカルも同じXcode。runnerイメージ自体は更新されるためOS/toolchainを実行時に表示・検査する。

## 完了記録

ローカル実装・自動検証完了。全700定義成功（実API7定義除外）、Lint272ファイル違反0、Release arm64/x86_64成功、actionlint/ShellCheck/bash構文検証成功。先行テストで再現したGemini取消後プレビューも修正。[Draft PR #43](https://github.com/Ryuta1346/conflingo/pull/43)提出済み・未マージ。独立レビュー・初回リモートCI・実機/実モデル受入は継続。[検証記録](../validation/llm-sse-ci-2026-11-14.md)。

提出時: `bed5023`（LLM/SSE整理）、`6ec128b`（CI・検証記録）をコミット・push。Draft PR #43をmain向けに作成。独立レビュー・実機受入は継続。
