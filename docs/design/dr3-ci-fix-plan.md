# PR #48 CI失敗の修正計画

2026-11-15。対象 `feat/dr3-design-system`、基点 `375f0cd`。
ユーザー「修正して」により、CI修正後のマージ・main切替・対象ブランチ削除まで承認済み。

## 確認済みの失敗

[run 43698785395](https://github.com/Ryuta1346/conflingo/actions/runs/43698785395) の初回・再実行とも失敗。
再実行では `LiveTranscriptLayoutTests.conferenceManualHistoryScrollIsNotTakenOverByPartialUpdates` がAX要素取得に失敗し、`InsightHTTPTransportTests` の長文・2 MiB境界ケースが60秒を超えた。ローカル全748テストは成功していた。

## 調査と実装順序

1. 既存CI失敗をRedとして保持。ローカルで対象テストとUI併走時を比較し、画面状態・AX取得とMainActor待機を切り分ける。
2. 検証で判明した原因を資料へ反映し、必要な回帰テストを先行追加する。固定待機・ウィンドウ共有・転送の細粒度callbackを調査対象とし、未確認の原因は断定しない。
3. 根拠の得られた箇所だけ最小修正する。履歴位置維持、最新への復帰、SSEの逐次配信、2 MiB上限、取消・エラー伝播を維持する。
4. 関連テスト、通常の全非liveテスト、Lint、署名なし両CPU Releaseを実行。テスト除外・上限の一律延長・成功までの反復再実行は用いない。
5. 修正をコミット・pushし、GitHub CI成功を確認してPR #48をマージ。最新mainへ移動し、`feat/dr3-design-system` のみローカル・リモートから削除。

## 受入条件

- 履歴閲覧中の部分字幕更新で表示位置が奪われず、最新へ復帰できる。
- 長文・2 MiBちょうど/1 byte超過を実URLSessionと合成URLProtocolで検証。受信callbackの隔離、順序、取消、エラーの契約を維持。
- ローカルとGitHubのLint・非liveテスト・Release成功。実API・実音声は対象外。
- クリーンなmainで終了。調査・検証の事実と未検証事項を記録。

## 調査後の実装方針

- ローカル対象10定義・2suiteは4.327秒で成功。HTTP全体0.480秒、境界2ケース0.322秒。単独のHTTP処理遅延は再現しなかった。
- ウィンドウ/NSHostingViewを作る18suiteが並列実行され、個別の`.serialized`はsuiteをまたぐフォーカス・スクロール・AX状態を排他にしない。画面テストを共通の`AppKitIntegrationTests`親suiteへ配置し、その親を`.serialized`にする。ウィンドウを表示しない単体テストは従来どおり並列。
- 既存CIの失敗をRedとして、この実行構成だけを変更してローカル/リモートで比較する。テストの削除・タイムアウト変更・製品HTTPの変更は行わない。履歴AX失敗が残る場合はタイトルとviewportを診断に含め、別途原因を切り分ける。
