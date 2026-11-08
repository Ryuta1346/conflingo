# PR3 システム音声キャプチャ 検証記録

2026-11-08。計画承認済み、実装・自動検証完了、レビュー待ち。基点main / da6c7aa、feature/system-audio。実装コミット`d71211f`をpushし、[Draft PR #8](https://github.com/Ryuta1346/conflingo/pull/8)を作成済み。

## 自動受入条件

- 権限参照で要求しない。未許可開始拒否、明示要求、重複・キャンセルを確認。
- 内部音声有効、自プロセス除外、マイク無効。入力元systemAudio。
- 非同期開始、二重開始、開始中停止、開始／停止失敗、同時停止、再開と旧入力の分離。
- 同時停止に後から参加した呼び出し元が、先行呼び出し元の完了を待たずに再開／停止失敗の再試行を行える。
- 合成CMSampleBufferの内容・順序・所有権、レート／チャンネル変換、無効入力、キュー超過と異常停止の通知。
- 検証画面モデルの開始停止・閉じる時の解放・権限とエラー表示。
- 既存Conference回帰、Debugビルド、全テスト、SwiftLint strict/no-cache、diffチェック。

## 結果

レビュー修正（2026-11-08）: 同時停止の状態更新とタスク参照の後処理を共有Task内へ移動した。成功時は再開可能な状態まで待ち、失敗時は再試行用の状態を保持して停止Taskを解除する。単発テストでは再現しなかったため、正常停止後の再開／停止失敗後の再試行を各100回繰り返すテストを追加し、修正前の失敗と修正後の成功を確認した。

| レビュー修正の検証 | 結果 | 証跡 |
|---|---|---|
| 回帰テストRed | `.stopping`の早期復帰、`alreadyRunning`、停止再試行時の旧エラーで失敗、終了65 | `/private/tmp/conflingo-stop-fix-red-repeat.log` |
| 全テストGreen・Debugテストビルド | **176テスト・19スイート成功、終了0** | `/private/tmp/conflingo-stop-fix-green.log` / `/private/tmp/conflingo-stop-fix-green.xcresult` |
| SwiftLint strict/no-cache・diffチェック | **51ファイル・違反0、各終了0** | `/private/tmp/conflingo-stop-fix-lint.log` / 作業ツリー |

以下は初回実装時の検証記録。

| 検証 | 結果 | 証跡 |
|---|---|---|
| 入力ライフサイクルRed | SystemAudioSource等の未実装によるビルド失敗、終了65 | `/private/tmp/conflingo-pr3-source-red.log` |
| 入力・既存接続Green | 21テスト・3スイート成功、終了0 | `/private/tmp/conflingo-pr3-source-green.log` |
| PCM・OS境界Red→Green | 未実装による終了65→6テスト成功、終了0 | `/private/tmp/conflingo-pr3-pcm-{red,green}.log` |
| 検証画面モデルRed→Green | 未実装による終了65→5テスト成功、終了0 | `/private/tmp/conflingo-pr3-probe-{red,green}.log` |
| 開始失敗からの復帰Red→Green | OS停止済みエラーで再開不能→修正後13テスト成功 | `/private/tmp/conflingo-pr3-cleanup-{red,green}.log` |
| リサンプル末尾Red→Green | 1600サンプルの期待に対し1360→停止時の排出追加で成功 | `/private/tmp/conflingo-pr3-tail-{red,green}.log` |
| 入力形式変更Red→Green | 前形式の末尾が新形式の音声より後に届く失敗→全テストで成功 | `/private/tmp/conflingo-pr3-format-red.log` / 最終結果 |
| 最終全テスト | **175テスト・19スイート成功、終了0**（既存152件＋新規23件） | `/private/tmp/conflingo-pr3-final-tests.log` / `/private/tmp/conflingo-pr3-validation/final-tests.xcresult` |
| 最終Debugビルド | 成功、終了0 | `/private/tmp/conflingo-pr3-final-build.log` |
| SwiftLint 0.65.1 strict/no-cache | **51ファイル・違反0、終了0** | `/private/tmp/conflingo-pr3-final-lint.log` |
| git diff --check | 成功 | 作業ツリーで実施 |
| UI表示・開閉 | Windowメニューから検証画面を表示。未許可／停止中・0フレーム・入力レベル0・ボタン・取得範囲を確認し、閉じてConference画面へ復帰 | CUAによる実画面観測。入力開始・アクセス要求は操作していない |

UI確認時にWindowメニューの自動項目と追加項目の重複を発見し、追加Commandsを削除した。全テスト後のこの変更は最終Debugビルドで確認した。lintで検出した末尾空行1件も除去済み。

初回のメソッド単独指定ではSwift Testingの対象が0件だったため、スイート全体で再実行してRedを確認した。空CMSampleBufferの初回失敗はfixture生成方法の問題で、製品不具合とは区別する。新規23件すべてが個別に振る舞いのRedを経たという記録ではない。

Xcode実行は既知のsandbox内マクロ制約を避けて許可された制限外で行った。AppIntentsメタデータ抽出スキップとcom.apple.linkd.autoShortcutのログは既存同様。最終Swiftコンパイルの警告・エラーなし。App Sandbox・entitlementsは変更していない。

## 実装・検証範囲

- AudioSourceは非同期start/stopとAsyncThrowingStreamのPCM供給を公開。マイクの既存変換処理を維持し、認識側のawaitとエラー伝達を追従させた。
- SystemAudioSourceは権限と開始停止を管理する。開始待ち中の停止／キャンセル、遅延成功、同時停止、停止失敗の再試行、旧ストリームの分離をfakeで確認した。
- ScreenCaptureAudioCaptureは音声出力のみ登録する。内部音声有効・自己音声除外・マイク無効の構成と、開始失敗／対象なしからの再開をfake OS境界で確認した。SCStreamの実開始は未検証。
- SystemAudioFrameOutputは音声コールバックとdelegateをロックで直列化する。PCM内容・順序・所有権、48kHz stereo→16kHz mono、無音、空／不正サンプル、256フレームの待機上限（テストでは容量1）、停止・形式変更時の末尾排出を確認した。変換失敗のエラー分岐は実装したが、OSコンバーター故障の直接注入試験は行っていない。
- 検証画面は権限待ちで閉じても後から開始せず、メーター更新は最大10Hz。停止に失敗すると状態を保持し、閉じる操作での失敗時は画面を再表示する。後者のウィンドウ再表示はコード確認のみで、実OS停止失敗によるUI試験は未実施。
- Speech入力のエラー付き列挙と既存Conferenceの回帰テストは成功。実SpeechAnalyzerを使った内部音声認識はPR4以降の対象。

## 再現コマンド

各終了コードを個別に確認する。実音声・権限操作は含まない。

```sh
validation_dir=$(mktemp -d /private/tmp/conflingo-pr3-validation.XXXXXX)
xcodebuild -project ConfLingo.xcodeproj -scheme ConfLingo -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath "$validation_dir/DerivedData" build > "$validation_dir/build.log" 2>&1
xcodebuild -project ConfLingo.xcodeproj -scheme ConfLingo -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath "$validation_dir/DerivedData" -resultBundlePath "$validation_dir/tests.xcresult" test > "$validation_dir/tests.log" 2>&1
swiftlint lint --strict --no-cache
git diff --check
```

今回のSwiftLint実体: `/private/tmp/conflingo-swiftlint-0.65.1/swiftlint`。

## 実機試験（延期中・全項目未検証）

既存の[音声素材・試験方針](audio-benchmark.md)を引き継ぐ。ユーザーが実音声試験を再開するまでキャプチャ・再生を実行しない。

| ケース | 確認内容 |
|---|---|
| Zoom / Meet / Teams | 同じ許可済み素材の再生、フレーム数増加、無音からの入力、停止後の増加停止 |
| 取得範囲 | 自プロセス音声の除外、マイク未使用、他アプリ音声も対象であること |
| 権限 | 未許可・拒否・許可・取消、設定変更と必要時の再起動、明示操作以外で要求しない |
| ライフサイクル | 開始中キャンセル、連続開始停止、OS側停止、ウィンドウ閉鎖、アプリ終了 |
| 構成変更 | 出力先切替、ディスプレイ切断、ヘッドフォン利用 |
| 配布 | App Sandbox有効、署名／配布形態、OSとアプリリビジョンを記録 |

実機合格とPRマージの証跡が揃うまでPR3をDONEにしない。
