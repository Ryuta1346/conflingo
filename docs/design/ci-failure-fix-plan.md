# PR #43 CI失敗の修正計画

2026-11-15。対象: refactor/llm-sse-ci、基点 e0bc210。
ユーザー「修正して」により、CI失敗の修正を承認。先行依頼のマージ・main切替・作業ブランチ削除は、修正の検証後に続行する。

## 確認済みの失敗

GitHub Actions run 43607605159 / job 132485649869。HTTP転送の2 MiB境界テストが60秒の上限を超える。InsightRecoveryTestsとMicrophoneConfigurationSessionTestsは2秒待機後も非同期処理が未完了。MeetingAIIntegrationTestsは自動提案開始に到達せず60秒後に取消。

## 原因仮説と調査

- HTTPのURLSession.AsyncBytesをMainActorで1バイトずつ反復し、非隔離iteratorとのexecutor切替が2 MiB応答の処理を遅らせる。合成URLProtocolで同一処理のMainActor/非MainActor時間を比較する。
- 短い実時間ポーリングは他の並列UIテストのMainActor占有で期限を越える。既存の状態通知またはObservationの状態変化を待ち、suiteの上限で不成立を検出する。
- 会議AIテストは実時間の同意時刻と固定オフセット2秒の合成発話を混在させている。既存のMeetingTimeline時刻注入を使用する。

## 最小修正

1. 関連設計・検証資料に失敗と未確認事項を記録。
2. CIの既存失敗をRedの根拠として保持。合成応答で性能差を計測し、受信中取消・MainActor callback・上限維持の回帰を先に補強。
3. HTTPのバイト走査だけを明示的な@concurrent helperへ移し、SSE chunkの配信はMainActorで逐次await。応答を無制限に読み込まない。Web調査も2 MiBの上限を維持したバックグラウンド走査とする。
4. 失敗した非同期テストで固定時刻と状態変化待機を利用し、実行速度への依存を除く。製品のタイムアウト・同意境界を弱めない。
5. 関連テスト、通常並列の全ローカルテスト、Lint、署名なしRelease両CPU、差分レビュー。テスト除外追加・タイムアウトの一律延長・自動再試行で失敗を隠さない。
6. 修正をPRへ反映し、GitHub CIのLint・全テスト・Releaseの成功を確認。PR #43をマージし、最新mainへ移動後、マージ済みrefactor/llm-sse-ciのローカル・リモートブランチを削除する。他のブランチは対象外。

## 受入条件

- 2 MiBちょうどの応答成功、1 byte超過でoversized、取消とcallbackエラーが即時に伝播。
- SSEの受信順・行/イベント上限・UTF-8・終端・usageを維持。
- 構成変更による停止完了と所有権解放、購読overflow回復、会議の一時停止/再開を検証。
- 実API・実音声を使わずGitHub CI成功。作業ツリーがクリーンなmainで終了。
