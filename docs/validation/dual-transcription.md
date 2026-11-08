# PR4 2入力文字起こし 検証記録

2026-11-08。計画承認済み、実装・自動検証・コードレビュー完了。基点main / `6b34a45`、作業ブランチ`feature/dual-transcription`。実装コミット`1a0e75a`をpushし、[Draft PR #9](https://github.com/Ryuta1346/conflingo/pull/9)を作成済み。実機受入待ち。

## 自動受入仕様

- マイク・内部音声の言語、origin、共通会議ID・時刻、partial/finalを分離する。
- 遅着したfinalを時刻順に整列し、同時刻の順序を安定させる。同一IDの古い更新を拒否し、別入力の同文を保持する。
- モデル・権限準備失敗、準備中キャンセル、片系開始失敗で無断入力・取り残しを生じさせない。
- 一方のfinalize待ちで他方の入力停止を遅らせない。両入力の最終finalを取り込んでからHubを終了する。
- 認識・入力・必須購読失敗で両系統を止める。同時停止、停止失敗後の再試行、再開・Clear、旧イベントの排除を確認する。
- Conference・単独音声検証との競合起動を拒否し、解放成功まで使用状態を保持する。
- 既存Conference回帰、全テスト、Debugビルド、SwiftLint、diffチェックを実行する。

## 結果

| 検証 | 結果 | 証跡 |
|---|---|---|
| 時系列整列Red | 遅着finalが末尾に追加され、期待順序と不一致。終了65 | `/private/tmp/conflingo-pr4-order-red.log` |
| 2入力Red | DualTranscriptionController・AudioInputUse未実装によるコンパイル失敗。終了65 | `/private/tmp/conflingo-pr4-dual-red.log` |
| 2入力・時系列Green | 9テスト・2スイート成功。終了0 | `/private/tmp/conflingo-pr4-dual-green.log` |
| 画面間競合Red→Green | 既存コントローラへの使用状態注入が未実装で終了65→全189テスト成功 | `/private/tmp/conflingo-pr4-use-red.log` / `conflingo-pr4-integration-green.log` |
| ライフサイクル追加確認 | 14テスト・2スイート成功。同時停止直後の再開／失敗再試行は各30回 | `/private/tmp/conflingo-pr4-lifecycle.log` |
| 停止失敗の表示Red→Green | 入力別の状態参照未実装で終了65→最終全テスト成功 | `/private/tmp/conflingo-pr4-state-red.log` / 最終結果 |
| 最終全テスト | **195テスト・23スイート成功、終了0**（既存176件＋新規19件） | `/private/tmp/conflingo-pr4-final-tests.log` / `/private/tmp/conflingo-pr4-final-tests.xcresult` |
| 最終Debugビルド | **成功、終了0** | `/private/tmp/conflingo-pr4-final-build.log` |
| SwiftLint strict/no-cache | **58ファイル・違反0、終了0** | `/private/tmp/conflingo-pr4-final-lint.log` |
| git diff --check | 成功 | 作業ツリー |
| 非録音UI表示 | Windowメニューから2入力検証画面を表示。英語の初期値、言語Picker、権限・停止状態、復旧案内、開始／Clear、空字幕を実画面で確認 | CUAによる実画面観測 |

初回Greenのビルドで、内部Input構造体のcomputed propertyにMainActor指定が不足していたため修正した。既存と同じAppIntentsメタデータ抽出スキップ・linkdログを除き、最終Swiftコンパイルの警告・エラーなし。

### 実装・検証の境界

- DualTranscriptionControllerは入力ごとのモデル・権限準備を完了してから2系統を起動する。認識言語・入力元・normalizerを分離し、Timeline・Hub・MeetingSessionStoreを共有する。
- SpeechTranscriptionServiceの入力停止と認識終了を分離。両入力停止を先に開始し、その後にfinalize・最終finalの取り込み・Hub終了を行う。片系停止失敗ではその入力だけを再試行対象に残し、使用権を保持する。
- fakeの開始・モデル準備を保留してキャンセルし、遅延成功後も入力が取り残されないことを検証。Task.yieldに依存した同期は明示的なキャンセル通知に置き換えた。
- MeetingSessionStoreは遅着finalを時刻順に安定挿入する。別入力の同文は保持し、既存ID/revision規約・再開・Clear・旧結果拒否は維持する。
- アプリ全体でAudioInputUseを共有し、Conference・単独内部音声検証・2入力検証の競合開始を権限要求前に拒否する。開始失敗・正常停止で解放し、停止失敗時は保持する。Conferenceにも停止再試行の導線を追加した。
- 音声認識とモデル取得はfake境界で検証。実SpeechAnalyzerの2系統同時稼働、SpeechDetectorの実音声性能、モデルの実ダウンロードは未検証。実音声・外部AI送信・音声保存は実行していない。
- 必須購読のoverflowは既存Hub単体テストと、同エラーを認識境界から通知する2入力の結合テストで確認。実際の負荷によるキュー超過は未測定。

### コードレビュー

`/private/tmp/conflingo-pr4-review/review.diff`の固定差分に対し、2名が独立レビュー。担当は2入力の非同期ライフサイクル／認識終了、画面間の競合・モデル準備・既存回帰。製品不具合の追加指摘なし。最終の入力別停止状態表示・権限案内とテスト同期の調整は主担当が確認し、全テスト・build・lintを再実行した。

### UI確認の制限

検証画面の表示後に閉じる操作を行ったが、対象ビルドのAX取得がタイムアウトしたため、閉鎖・Conferenceへの復帰は実画面で確認できていない。同名の旧ビルドも起動しており、アプリ名での再選択では旧版が選ばれた。対象ビルドのプロセスは存続し、1秒のスタックサンプルではメインスレッドは通常のイベント待機中だった（`/private/tmp/conflingo-pr4-ui-sample.txt`）。クラッシュ記録は見つからなかったが、これを閉鎖成功の証拠とは扱わない。

開始ボタン・アクセス要求は操作していない。閉じる際の両系統停止はコントローラの自動テストで検証し、実OS停止失敗時のウィンドウ再表示は未検証。

## 再現コマンド

```sh
validation_dir=$(mktemp -d /private/tmp/conflingo-pr4-validation.XXXXXX)
xcodebuild -project ConfLingo.xcodeproj -scheme ConfLingo -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath "$validation_dir/DerivedData" build > "$validation_dir/build.log" 2>&1
xcodebuild -project ConfLingo.xcodeproj -scheme ConfLingo -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath "$validation_dir/DerivedData" -resultBundlePath "$validation_dir/tests.xcresult" test > "$validation_dir/tests.log" 2>&1
/private/tmp/conflingo-swiftlint-0.65.1/swiftlint lint --strict --no-cache
git diff --check
```

各終了コードを個別に確認する。Xcodeのマクロ・テスト実行は承認された制限外環境で行った。

## 実機試験（延期継続・未検証）

実音声試験を再開する指示があるまで、音声のキャプチャ・再生・実認識は行わない。Zoom/Meet/Teamsでの2入力字幕、権限・機器切替、時刻誤差、認識精度・遅延、CPU・メモリ、配布構成を後日確認する。入力開始通知を時計の基準とし、ハードウェアのサンプル時刻同期は保証しない。

コードと自動検証の完了はGate B合格とは区別する。マージ・実機受入の証跡が揃うまでPR4をDONEにしない。
