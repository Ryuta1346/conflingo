# ADR-002: ScreenCaptureKitで内部音声の単独入力を検証する

- 日付: 2026-11-08
- 状態: 実装方針承認済み。実機・配布条件の検証待ち。

## 決定

PR3はScreenCaptureKitを採用し、AudioSourceの非同期開始・停止とエラー付きPCM供給に接続する。Mac全体の出力音声を対象とし、自プロセス音声を除外する。音声出力だけを登録し、マイク・画面サンプル・録音ファイルは扱わない。App Sandboxは維持する。

## 比較

| 観点 | ScreenCaptureKit | Core Audio Process Tap |
|---|---|---|
| 取得対象 | コンテンツフィルタと音声設定で指定 | プロセス／プロセス群の出力をtapで指定 |
| 自己音声除外 | excludesCurrentProcessAudioで指定 | tap対象プロセスの選別が必要 |
| 権限 | 画面・システム音声の収録へのアクセス | 公式サンプルではNSAudioCaptureUsageDescriptionが必要 |
| 実装 | SCStreamの出力・delegate・開始停止 | tapとaggregate device等のライフサイクル管理 |
| Sandbox・署名・配布 | 現行構成で実機検証予定、未確認 | 未検証。本線採用の根拠なし |
| PR3の判断 | 既存計画に沿った第一候補 | 比較のみ。実装・性能上の優劣は未確定 |

## 帰結

- 全体音声には会議以外のアプリの音も含まれる。検証画面に取得範囲を明記する。
- 権限参照は要求を発生させず、未許可のBool値から初回／拒否済みを推測しない。
- 権限要求、再起動の要否、OS側停止、出力先切替、Zoom/Meet/Teamsでの受信は実機試験まで未検証。
- 検証画面の合成入力成功は、実機取得・2入力STT・配布成功の証明ではない。

## 根拠

- [Apple: Capturing screen content in macOS](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos)
- [Apple: Capturing system audio with Core Audio taps](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps)
- インストール済みmacOS SDK: SCStream.h / CGWindow.h。
