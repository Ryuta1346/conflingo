# PR2 音声入力の共通化 検証記録

2026-11-08。PR2完了（ユーザー確認済み）。基点main / 8812ae0、ブランチfeature/audio-abstraction。実装コミット`d5928f3`。[PR #7](https://github.com/Ryuta1346/conflingo/pull/7)はマージ済み（`da6c7aa`）。実音声試験の延期は継続し、以下の自動検証結果と区別する。

## 受入条件

- 入力元・権限状態を公開し、参照だけでは権限要求を出さない。
- 未許可入力を拒否。重複権限要求・権限待ち中キャンセルを安全に扱う。
- 指定フォーマットのPCM内容・順序を認識入力へ渡す。元バッファの再利用からフレームを独立させる。
- 二重startは既存入力を維持して拒否。stopは冪等でストリームを終了。
- 開始失敗で後始末し再開可能。新しい入力へ旧ストリームが混入しない。
- PR1の最終final取り込み、字幕・翻訳・辞書・Markdownの回帰がない。
- Debugビルド、全テスト、SwiftLint strict/no-cache、git diff --checkが成功。

## 結果

| 検証 | 結果 | 証跡 |
|---|---|---|
| 入力契約のRed | AudioPermissionStatus / AudioSource / MicrophoneAudioSource等の未実装によるビルド失敗、終了65 | `/private/tmp/conflingo-pr2-source-red.log` |
| 入力契約のGreen | 10テスト成功、終了0 | `/private/tmp/conflingo-pr2-source-green.log` |
| 接続・キャンセルの追加Red | 26テスト中1件失敗。権限待ちキャンセルが誤って権限拒否エラーを残す期待違反、終了65 | `/private/tmp/conflingo-pr2-integration-red.log` |
| 上記修正後のGreen | 26テスト・3スイート成功、終了0 | `/private/tmp/conflingo-pr2-integration-green.log` |
| 最終Debugビルド | 成功、終了0 | `/private/tmp/conflingo-pr2-final-build.log` |
| 最終全テスト | **152テスト・16スイート成功、終了0**（既存137件＋新規15件） | `/private/tmp/conflingo-pr2-final-tests.log` / `/private/tmp/conflingo-pr2-validation/final-tests.xcresult` |
| SwiftLint 0.65.1 strict / no-cache | **43ファイル・違反0、終了0** | `/private/tmp/conflingo-pr2-final-lint.log` |
| git diff --check | 成功 | 作業ツリーで実施 |

Xcodeは既知のsandbox内マクロ制約を避けるため、許可された制限外実行を使用した。実マイク・スピーカー再生・モデルダウンロードは実行していない。AppIntentsメタデータ抽出スキップとcom.apple.linkd.autoShortcut接続ログはPR0/1と同様。破損JSONの復旧ログは既存テストの期待ケース。Swiftコンパイルの警告・エラーは発生していない。

## 実装・自動検証の範囲

- AudioSourceはMainActor上で入力元・権限・状態・開始停止を公開する。MicrophoneAudioSourceがキャプチャと権限要求のOS境界を包む。
- 権限状態の読み取りは要求を発生させない。未決定時の重複要求は1つにまとめ、キャンセルされた呼び出しには入力開始を許可しない。SessionControllerは権限待ちのキャンセルでidleに戻り、権限拒否エラーを残さない。
- 未許可・二重開始を拒否し、正常停止と開始失敗は後始末してidleへ戻る。停止・再開でストリームを分離し、旧producerからの追加入力を拒否することを合成PCMとfakeキャプチャで確認した。
- AudioCaptureServiceからSpeech依存を除去し、AudioFrameを供給する。AudioFrameはAVAudioPCMBufferをコピーし、元バッファの再利用から独立させる。発行後は供給側・消費側とも変更しない契約のもと、非SendableなPCM型を限定的に@unchecked Sendableで包む。
- SpeechTranscriptionServiceの入力開始処理は同じフォーマットとPCM内容をAnalyzerInputへ順序どおり写す。mapを利用し、中継用Taskや二重キューは追加していない。既存フォーマット変換のアルゴリズムは維持している。
- SessionControllerの既定構成で、権限要求と認識サービスに同じAudioSourceを注入する。認識停止は入力停止→Analyzerのfinalize・最終結果取り込み→Hub終了の順序を維持する。
- 認識サービス接続のテストは入力開始・PCM変換・停止経路を対象とする。実SpeechAnalyzerを起動した結合試験ではない。既存PR1の最終final・イベント配信・翻訳の合成入力回帰テストも全件成功した。
- 入力契約10件を先行実装した後、接続・キャンセルの5件を追加した。追加時に失敗したのはキャンセル後のエラー表示1件であり、全15件が個別の振る舞い失敗を経たという記録ではない。

## 再現コマンド

各コマンドの終了コードを個別に確認する。実機の音声操作は含まない。

```sh
validation_dir=$(mktemp -d /private/tmp/conflingo-pr2-validation.XXXXXX)
xcodebuild -project ConfLingo.xcodeproj -scheme ConfLingo -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath "$validation_dir/DerivedData" build > "$validation_dir/build.log" 2>&1
xcodebuild -project ConfLingo.xcodeproj -scheme ConfLingo -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath "$validation_dir/DerivedData" -resultBundlePath "$validation_dir/tests.xcresult" test > "$validation_dir/tests.log" 2>&1
swiftlint lint --strict --no-cache > "$validation_dir/lint.log" 2>&1
git diff --check
```

今回のSwiftLint実体は`/private/tmp/conflingo-swiftlint-0.65.1/swiftlint`。

## 持ち越し

実音声試験はユーザー指示で延期中。実AVAudioEngineの解放、実認識結果の同等性、実翻訳、OS権限ダイアログ操作は未検証。合成PCM・fake OS境界の成功を実機合格として扱わない。PR0のGate Aは未検証を維持する。
