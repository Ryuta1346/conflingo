# PR5-C — Meeting UI・フローティングUI 検証記録

> 2026-11-14独立レビュー追記: 固定main `33c8ae6`で[残件レビュー](remaining-review-2026-11-14.md)を実施済み。指摘・未修正項目・確認範囲は同記録を参照。以下の「独立レビュー未実施」は当時の履歴で、実機受入の未完了は継続。

2026-11-08 / `feature/meeting-ui` / **PR #11マージ済み、残る受入待ち（REVIEW）。** 初期実装: `fa5f515` / レビュー修正: `4c1902d` / マージ: `e167765` / [PR #11](https://github.com/Ryuta1346/conflingo/pull/11)

ユーザー「進めて」により[実装計画](../design/pr5-c-implementation-plan.md)を承認。基点main `c34ddd1`。PR4の実機受入を持ち越し、接続コードとfake結合検証を先行する方針を含む。実音声試験の延期は継続している。

## 実装と範囲

- Home/App ShellにMeetingを追加。Preparation/Live/Review、入力別言語、通知・同意、開始・準備取消・一時停止・再開・終了・破棄確認を実装。
- PR4の`DualTranscriptionController`/`MeetingSessionStore`を再利用。Meeting専用の所有者で共通入力排他に参加し、2つの検証ウィンドウやConferenceとの二重取得を防ぐ。
- 主画面と小窓で同じMeeting状態を共有。Pause/Resumeでは会議ID・発話・共通時刻を維持する。終了は停止と最後のfinal取り込みを待ち、停止失敗なら同じ終了意図で再試行する。
- 提案の種類・本文・要確認表示、根拠IDから時刻・引用への移動。根拠不明時は参照不能を表示。通常起動ではAI未接続・外部送信なしを示し、架空提案は出さない。
- 小窓は重要度が最も高い提案を最大1件表示。同順位は新しいものを選ぶ。主画面を隠すコンパクト表示、展開、非表示、ウィンドウメニューからの再表示、サイズ/位置保存と画面内への補正を実装。
- 小窓を閉じても収集は止めない。メイン窓は収集中に停止確認を行う。新しいCmd+Q終了ガードは追加していない。
- Conferenceの状態所有・翻訳タスク・既存設定キー・Markdown形式を維持。Meetingの保存/書き出し・候補確認/却下・AI通信・RAGは後続PRの範囲。
- レビュー中に、同じ根拠の再選択、現在画面を閉じる時の確認、停止再試行成功後の古いエラー解除、非表示のMeeting画面の操作抑止を確認・修正した。

## 自動検証

| 検証 | 結果 | ログ |
|---|---|---|
| ベースライン | 211テスト成功、lint 76ファイル・違反0 | `/private/tmp/conflingo-pr5c-baseline.log` / `conflingo-pr5c-baseline-lint.log` |
| 操作契約Red | 未実装のMeetingWorkspaceでコンパイル失敗 | `/private/tmp/conflingo-pr5c-red.log` |
| 操作契約Green | 7テスト成功 | `/private/tmp/conflingo-pr5c-green.log` |
| 表示契約Red | 根拠表示・位置復元・Meeting遷移が未実装のため失敗 | `/private/tmp/conflingo-pr5c-presentation-red.log` |
| 操作の追加Red | 根拠の再選択と同じ画面での閉鎖確認の未実装を確認 | `/private/tmp/conflingo-pr5c-interaction-red.log` |
| 停止再試行Red | 成功後に古い停止失敗エラーが残ることをassertionで確認 | `/private/tmp/conflingo-pr5c-retry-red.log` |
| レイアウト/小窓 | 実NSHostingView/NSPanelを使う8テスト成功 | `/private/tmp/conflingo-pr5c-layout.log` |
| 最終Debug build/test | **229テスト・31スイート成功**（既存211＋追加18） | `/private/tmp/conflingo-pr5c-tests.log` |
| Release build | 成功 | `/private/tmp/conflingo-pr5c-release.log` |
| SwiftLint strict | **86ファイル・違反0** | `/private/tmp/conflingo-pr5c-lint.log` |
| 差分/資料 | `git diff --check`、ローカルリンク検証、計画保存先との一致確認 | 最終確認 |

Xcodeの初回実行は実行環境のサンドボックスでSwiftマクロが失敗したため、許可された通常権限で再実行した。音声入力はfake。権限復旧テストは、OS側で許可状態が変更されたこともfakeへ反映して検証した。

実行コマンド:

```sh
xcodebuild test -project ConfLingo.xcodeproj -scheme ConfLingo -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath /private/tmp/conflingo-pr5c-build
xcodebuild build -project ConfLingo.xcodeproj -scheme ConfLingo -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath /private/tmp/conflingo-pr5c-build
/private/tmp/conflingo-swiftlint-0.65.1/swiftlint lint --strict --no-cache
git diff --check
```

主なテスト:

- `MeetingWorkspaceTests`: 通知確認、入力排他、権限拒否/復旧、設定移動、Pause/ResumeのID/時刻保持、終了時final取り込み、二重操作抑止、停止失敗/再試行、準備取消と遅延完了、入力切断、破棄取消/確定。
- `MeetingPresentationTests`: 根拠IDの一致/不明、同じ根拠の再選択、重要度と新しさ、画面外/巨大な保存フレームの補正、停止成功/失敗時のナビゲーション、同じ画面での閉鎖確認。
- `MeetingLayoutTests`: 80発話を表示し、根拠へ移動した読み返し位置を1280×800→720×560→1280×800で保持。小窓切替・新しい発話・Review移行でも同じスクロールビューを維持。小窓の表示/閉鎖/非表示/再表示で会議ID・収集を維持し、表示時にkeyWindowを奪わないことを確認。

ReleaseにはDEBUG専用プレビュー分岐の到達不能コード警告が残る。AppIntentsメタデータ抽出の非対象警告も出る。ビルドは成功しており、警告を無視する設定変更は行っていない。

## 非録音ネイティブ操作

DEBUGの`--meeting-preview`を使用。専用UserDefaults suiteは`com.gavrri.conflingo.meeting-preview`。実マイク/内部音声/モデル取得/AI通信を呼ばないfakeを注入し、通常起動とReleaseではfixtureを有効にしない。`--meeting-state=live|review|stop-failed|permission-denied|offline|sending`で状態を準備でき、指定なしはsetup。

| 操作 | 確認した結果 |
|---|---|
| Pause/Resume/End | 両入力の取得/停止表示、同じ発話を保持した再開、Reviewへの遷移 |
| 根拠への移動 | 引用時刻の発話へ移動し「履歴を表示中」「最新へ」を表示 |
| 破棄取消/確定 | 取消で発話保持、確定で空の準備へ。通知確認が外れ、開始は無効 |
| 小窓の停止再試行 | 停止未完了を表示、再試行後に古いエラーが消え、Reviewへの導線を表示 |
| 小窓/非表示/再表示/展開 | 同じ会議名・提案を保持。Windowメニューからの再表示操作、主画面への復帰 |
| 配色と文字 | 狭幅のDark/Light、16→48→16pt。本文はスクロールでき、操作部が画面内に残る |
| 設定往復 | 配色がMeeting主画面と小窓に反映、発話・会議名を保持 |
| メイン窓の閉鎖確認 | 取消で取得中を維持、確定後は両入力停止・再開可能。CUAは次の観察時に主画面を再表示するため、閉鎖瞬間の不可視状態はこの操作では独立に観察していない |

非アクティブ小窓を表示しても、CUAが主画面を選ぶ場合があった。コンパクト操作で主画面を隠した後は小窓を取得でき、停止再試行/展開を操作した。ウィンドウ可視状態と非表示で停止しないことはホスティングテストでも検証した。

## 画像・モックとの差分

CUAから取得した未加工JPEG。主画面は外枠込み1512×949pt相当、狭幅は757×949pt相当、小窓は420×462pt相当（画像は2倍画素）。1280×800/720×560の正確なサイズ変更はホスティングテストで確認し、同寸法のモック画像との差分比較は未実施。

| 状態 | 画像 |
|---|---|
| 会議中・Light | [Meeting Live](pr5-c-screenshots/meeting-live.jpg) |
| 準備・Light | [Preparation](pr5-c-screenshots/meeting-preparation.jpg) |
| 振り返り・Light | [Review](pr5-c-screenshots/meeting-review.jpg) |
| 停止失敗 | [Main](pr5-c-screenshots/meeting-stop-failed.jpg) / [Floating・Dark](pr5-c-screenshots/floating-stop-failed-dark.jpg) |
| 小窓・振り返り | [Dark](pr5-c-screenshots/floating-review-dark.jpg) / [Light](pr5-c-screenshots/floating-review-light.jpg) |
| 狭幅 | [Dark](pr5-c-screenshots/meeting-narrow-dark.jpg) / [Light](pr5-c-screenshots/meeting-narrow-light.jpg) |
| 48pt | [狭幅・Dark](pr5-c-screenshots/meeting-large-text-dark.jpg) |

小窓Reviewの画像は、最終確認で下部に「マイク 停止・内部音声 停止」の補助ラベルを追加する前の版。会議中/停止失敗の入力状態表示は画像どおり。閉鎖確認とSettingsの案内も、Meetingに未提供の書き出しを案内しない文言へ最終調整した。

モックの提案優先/発話補助の配置、トークン、常設停止、候補と根拠の区別を維持。今回の提供範囲に合わせ、通常起動のAsk AI/AI許可、候補確定、Sessions/保存/書き出しを省いた。Reviewは発話の読み返しと破棄を提供する。小窓は同じSwiftUIカードをAppKitの非アクティブパネルで表示し、狭幅の主画面は上下配置へ切り替える。

## 未検証と次の受入

実音声・実モデル取得・実翻訳、Zoom/Meet/Teams、2入力の精度/遅延/性能、60分利用、実AI、画面共有、複数モニターの実配置、VoiceOver読み上げ・全キーボード経路は未検証。画面外位置は計算テストでのみ確認。通常製品でのAI通信・Meeting保存はそもそも今回の実装対象外。

主担当が差分とテストを確認した。独立コードレビューは未実施。2026-11-08、ローカルmainでPR #11のマージ（`e167765`）を確認。マージは残る受入の合格を意味しない。PR5-CのDONE判定、Gate A/B/U全体の合格、実会議での利用可否の判定は保留する。差分・画像の独立レビュー、VoiceOver/画面共有等の受入、延期中の実機受入は残課題として維持する。次の開発計画は[PR6](../design/pr6-implementation-plan.md)。

参考: Context7経由でApple公式の[NSPanel](https://developer.apple.com/documentation/appkit/nspanel)と[nonactivatingPanel](https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/nonactivatingpanel)を確認。新規パネルの表示時にアプリをアクティブ化しない構成へ適用した。

## レビュー指摘の修正（2026-11-08）

`f450d9c`までの差分レビューで、小窓からMeetingを展開すると停止確認が入る問題と、認識中発話が時刻順に並ばない問題を確認。ユーザー「修正進めて。その後コミットandプッシュ」により修正を承認。

- 展開時はConferenceのphaseを参照し、Meetingの収集・準備・停止を継続する。Conferenceの停止確認や処理中の移動保留は維持し、移動できなければ小窓を表示したままにする。
- Meetingの表示イベントをfinal/partial結合後に開始時刻で安定整列する。発話ID、revision、確定データは保持する。
- 7テスト追加。実controller＋fake入力で設定からの復帰、収集維持、準備維持、停止失敗後の復帰を検証。NSPanelの表示継続/非表示、Conferenceの停止確認/取消/処理中拒否、partial更新・確定前後の表示順、同時刻の安定順を確認した。

| 検証 | 結果 | ログ |
|---|---|---|
| 回帰テストRed | 展開専用操作・表示イベントが未実装のためコンパイル失敗 | `/private/tmp/conflingo-review-fix-red.log` |
| Debug build/test | **236テスト・31スイート成功** | `/private/tmp/conflingo-review-fix-tests.log` |
| Release build | 成功 | `/private/tmp/conflingo-review-fix-release.log` |
| SwiftLint strict | **86ファイル・違反0** | `/private/tmp/conflingo-review-fix-lint.log` |
| 差分 | `git diff --check`成功 | 最終確認 |

Releaseの既知のDEBUG専用分岐の到達不能警告とAppIntents非対象警告は継続。実音声・実AI・手動UIの追加受入は未実施。新規スクリーンショットは取得していない。今回のレビュー・修正は単独実行で、独立した別エージェントによるレビューは未実施。
