# PR6 ネイティブ停止操作の追加受入

2026-11-10 / main f2baff9。主画面・小窓のAI停止は実受信後のクリックとクライアント取消を確認。一時停止・会議終了の受信中取消は未確認。PR6はREVIEWを維持する。

後続の[追加12要求枠の確認](pr6-followup-acceptance.md)で、一時停止・会議終了も実受信後クリックと取消に合格。本資料は前回8要求の履歴として保持する。最新ビルドのKeychain受入も[認証後に完了](pr6-keychain-auth-resume.md)している。

## 条件と結果

ユーザーの「OK」で既存の未保存合成プレビューの終了を承認後、許可済み品質修正ビルド（CDHash: 9a20486f03cbcae8e2601d656b8bcbe4c2ffaf44）をホストに一時XCTestを実行した。製品のMeetingWorkspaceView・MeetingFloatingPanel・Geminiクライアント・URLSession transportを使い、音声入力だけを合成fixtureに置換。実録音・追加認証・キー変更はない。最新ビルドのKeychain受入とは区別する。

停止はCUAのネイティブ操作で実施。transportの初回受信・終了をsystemUptime、マウス解放をNSEvent.timestampで記録した。人工的な応答遅延は加えていない。時刻とカード状態を[判定JSON](pr6-native-stop-acceptance-2026-11-10.json)に保存し、キー・生成本文は保存していない。

| 要求 | 操作 | 観測・判定 |
|---|---|---|
| 1 | 主画面AI停止（AX） | 操作前に正常完了。受信中停止は未確認。日本語質問に英語で回答する不一致を観測 |
| 2 | 主画面AI停止（AX） | 初回受信前に取消。マウス時刻なし。受信後クリック条件は未確認 |
| 3 | 主画面AI停止 | 初回受信前に取消。受信後条件は未確認 |
| 4 | 小窓AI停止 | **合格**。初回受信から364.000ms後にクリック、17.705ms後に取消。14チャンク受信、部分本文と中断表示を保持 |
| 5 | 主画面AI停止 | 初回受信前に取消。受信後条件は未確認 |
| 6 | 一時停止 | 通信正常完了の41.281ms後にクリック。両入力停止・再開ボタン・既存回答保持を確認。受信中取消は未確認 |
| 7 | 再開後、主画面AI停止 | **合格**。再開後の新規要求で6チャンク受信。初回受信から201.335ms後にクリック、19.952ms後に取消。中断表示を保持 |
| 8 | 会議終了 | 通信正常完了の364.214ms後にクリック。振り返り・両入力停止・8カード保持を確認。受信中取消は未確認 |

要求4・7は firstChunk < mouseUp < end、cancelled=true、正常完了なし。取消後に完成カードへ戻らないことを最終状態でも確認した。クライアント取消はサーバー側の推論停止や非課金を保証しない。再開後の新規受信は確認したが、再開後の回答完了までは今回の判定に含めない。

## 品質の残件と実行上限

固定36ケースは[根拠評価](pr6-semantic-acceptance.md)のとおり35件合格・1件要確認。今回のUI要求1では、日本語の長い質問に英語で回答した。固定36ケースとは別の言語不一致として記録し、全体合格とはしない。製品修正・原因の切り分けは未実施。

承認済み44要求は根拠評価36＋停止UI8で全て使用した。追加送信なし。最新ビルドの認証はユーザー指示でスキップ。一時停止・会議終了の受信中クリック、VoiceOver、全キーボード経路、狭幅・文字拡大の再検証、長時間・実請求額は残る。

## 終了・証跡

「受入検証を終了」でAI許可をオフにし、テスト用会議・小窓を終了。最終メタデータは allowed=false / phase=idle / page=review、カード状態は complete, interrupted, interrupted, interrupted, interrupted, complete, interrupted, complete。テストホストの終了をCUAで観測した。

/private/tmp/conflingo-pr6-followup-approved/ 配下の NativeStopAcceptance.swift、build-native.py、native.xctestrun、NativeStopRetry.xcresult、native-stop-retry.log が証跡。一時XCTestは1件成功（630.094秒、要求数8）。このテスト成功は実行・終了の成功であり、全操作の受入合格を意味しない。最初の0要求の中断試行 NativeStop.xcresult と区別する。

ログにはAppKitの負のview geometry警告が残る。今回、表示サイズの問題との対応は切り分けていない。製品コードは変更しておらず、製品全体のlint・テストは再実行していない。資料の差分・リンク・JSON整合を確認する。
