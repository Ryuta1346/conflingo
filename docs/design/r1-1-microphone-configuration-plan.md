# R1-1 マイクの機器・構成変更

2026-11-13 / main `0e25f5a`。ユーザー「OK、R1-1進めて」を、plan.mdのR1-1に限定した修正・検証への承認として記録する。
正本の保存先: `~/.coding-agents/docs/conflingo/main/r1-1-microphone-configuration-plan.md`。

## 問題と方針

`AudioCaptureService`は構成変更通知を監視していない。AVAudioEngineは機器のチャンネル数・サンプルレート変更で停止するため、入力ストリームが終了しないまま画面に取得中と表示される可能性がある。物理機器での再現は未確認。

R1-1で認められた「エラーを表示して停止」を採用する。構成変更を検知したらtapとエンジンを停止し、入力ストリームを説明付きエラーで終了する。利用者には入力機器を確認して再開始するよう案内する。通知の内部キューではエンジンを操作せずMainActorへ渡す。

音声入力のエラーをSpeechTranscriptionServiceの失敗通知へ確実に伝え、既存のConference／Meetingの停止・エラー表示経路につなぐ。OSの認識結果側が同じエラーを返すことには依存しない。

## 受入条件

- 実行中の自身のエンジンの構成変更だけを検知し、エラー終了・入力解放・再開始の案内を行う。
- 通常停止・未開始・開始失敗・重複通知で二重停止しない。停止／開始失敗では監視を解除する。
- 通知受信後、MainActorで処理する前に停止・再開始しても、古い実行の通知で新しい入力を停止しない。
- 再開始時は新しいハードウェア形式を取得する。別エンジンの通知は無視する。
- 入力エラーが認識の失敗通知まで伝わり、Conferenceはidleへ、Meetingの2入力は両方停止し、エラーを保持する。正常な音声フレーム順序・通常停止は維持する。
- 実機の抜き差し、Bluetooth、会議アプリ別受入は合成通知テストとは区別する。

## 実施手順

1. AVAudioEngineを小さなOS境界として差し替え可能にし、構成変更通知と公開start/stopの回帰テストを先行追加。変更未対応によるRedを確認する。
2. 実行ID付き通知監視・停止・説明付きエラー終了を最小実装。入力エラー通知のテストを先行追加し、音声認識への伝播を確認する。
3. Conference／Meetingの既存停止経路との結合、再開始・競合・正常動作を確認する。
4. 関連テスト、全テスト（実API評価フラグ無効）、SwiftLint、Releaseビルド、差分確認。結果と実機未検証範囲をこの文書とplan.mdに反映する。

## 根拠

- [Apple: AVAudioEngineConfigurationChangeNotification](https://developer.apple.com/documentation/avfaudio/avaudioengineconfigurationchangenotification) とローカルXcode 26.6 SDKヘッダで、構成変更時の停止・以前の形式の保持・通知内での同期破棄の注意を確認。
- 調査時点のAudioCaptureServiceには通知登録なし。SpeechTranscriptionServiceは入力をmapして渡し、失敗通知は認識結果のconsume側だけにある。

## 検証結果

### 実装

- `AudioCaptureService`で対象エンジンだけの通知を監視。MainActorへ渡し、実行IDが一致する場合だけtap・エンジンを停止し、`configurationChanged`でストリームを終了する。
- 通常停止・開始失敗・破棄時に監視を解除する。再開始では入力形式を読み直し、旧実行の遅延通知を無視する。
- AVAudioEngineの機器操作を`MicrophoneCaptureEngine`へ分離。テストではこのOS境界だけを差し替える。
- `SpeechAudioInputSequence`で入力エラーを失敗通知へ伝播。認識結果のエラー待ちに依存せず、追加のキュー・供給タスクは作らない。通常終了・キャンセルではエラー表示を起こさない。
- 製品のConference／Meetingコントローラーを使った結合テストで、エラー保持・入力停止・占有解放・再開始を確認。SpeechAnalyzerの消費部分はテスト用に代替しており、実OS認識の検証とは区別する。

### TDDと実行記録

- `red-retry.log`: 構成変更後の停止とエラー終了が実装されていないことを、5テスト中2テスト・4箇所の失敗で確認。
- `propagation-red.log`: 通知による停止の5テストは成功。入力エラーの失敗通知が届かないことを1テスト・2箇所の失敗で確認。
- `green2.log`: 関連49テスト／7 suites成功。その後、通常停止・キャンセルの追加テストを全回帰に含めた。
- 最初のsandbox内ビルドはSwiftマクロ起動制約で失敗。通常実行環境で再実行した。入力sequenceはSwift 6のactor分離を保つ`next(isolation:)`を使用する。
- 全体テストの初回・再試行は既存のSharedAssistanceLayoutTestsの画像保存3ケースが失敗。固定`/tmp`への保存をSandboxに拒否され、過去画像の退避でも再現した。テスト出力先だけを`FileManager.default.temporaryDirectory`へ修正。過去画像は元に戻し、製品のSandbox設定は維持した。
- `all-final.log`: 全568テスト／100 suites、562成功・実API評価6skip・失敗0。xcresultの集計でも同じ件数を確認（`test-summary.json`）。追加10テストで通知・開始失敗・再開始・異種エンジン・別スレッド・破棄・キャンセル・両コントローラーとの結合を確認。
- `lint-final.log`: SwiftLint 0.65.1 strict/no-cache、224ファイル違反0、終了0。
- `release.log`: arm64 Release、`CODE_SIGNING_ALLOWED=NO`、ビルド成功、終了0。`git diff --check`成功。既存のSDK非推奨・AppIntents等の警告は残る。
- 最終xcresult: `/private/tmp/conflingo-r1-1/build/Logs/Test/Test-ConfLingo-2026.11.13_11-36-17-+0900.xcresult`。
- ログ: `/private/tmp/conflingo-r1-1/`。実API評価フラグを除去して実行した。

### 残る実機受入

実機のヘッドフォン抜き差し・Bluetooth切替・機器切断、OSのSpeechAnalyzerを含む認識、会議アプリ別のGate Bは未実施。実音声・実API送信は行っていない。これらの合格を合成通知テストから推定しない。実装・検証時点ではコミット・push・インストール済みアプリの更新は未実施。続くユーザー「コミットしてPR作成」により、R1-1の変更をコミット・pushし、main向けDraft PRを作成する承認を得た。
