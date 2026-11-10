# 停止後の確定表示の回帰検証

2026-11-10。[承認済み計画](../design/dual-transcription-final-status-plan.md)。表示修正と合成回帰検証を完了。

## Red: 実音声なしでの再現

実際の `DualTranscriptionController`、normalizer、hub、store、`DualTranscriptionProbeView` をそのまま使い、音声認識と入力ソースだけを合成に差し替えた[検証アプリ](fixtures/dual-transcription-status-app.swift)を一時プロジェクトでビルドした。製品エントリポイントには追加していない。マイク、ScreenCaptureKit、SpeechAnalyzer、Keychain、APIを利用しない。

9つの内部音声発話をpartial→finalへ更新し、途中でマイクpartialを交互に挿入、停止時にマイクfinalを発行した。修正前は **ストアfinals=10/partials=0、全体・両入力停止済みでも、画面の全10行が「認識中」**。AXとスクリーンショットで一致。同じデータ遷移を確認する追加のコントローラ回帰を含め、15テスト/2スイートは修正前から成功した。

したがって少なくとも今回の合成再現では認識最終化ではなく、確定・未確定を同一LazyVStack内の別々のForEachで描画し、同じ発話IDがリスト間を移る際の表示更新に問題がある。修正は単一のForEachで同じ発話IDを更新するものとし、finalを捏造する処理や音声認識変更を加えない。

証跡: `/private/tmp/conflingo-status-repro-red.log`（ビルド成功）、`/private/tmp/conflingo-final-status-baseline2.log` / `.xcresult`（15件成功）。最初のbaselineは追加テストのSwiftマクロの構文エラーでビルド失敗し、製品不具合のRedには数えていない。

## Green

製品変更は `DualTranscriptionProbeView` のForEach統合だけ。同じ合成シーケンスでストアfinals=10/partials=0に対し、**全10行が確定、認識中0行**をAXと画面の両方で確認した。再度同じシーケンスを開始・停止すると、同一セッションの先行10件を保持し、後続10件を追加して **確定20行・認識中0行、ストアfinals=20/partials=0** となった。CUAの取得済みAX文字列から件数を機械判定し、再開結果が20/0と異なる場合に失敗するチェックも成功。

| 検証 | 結果 | 証跡 |
| --- | --- | --- |
| 修正前の合成UI | 不合格: データ10件確定、表示10件認識中 | `conflingo-status-repro-red` のビルドとCUA画面/AX |
| 修正後の合成UI | 合格: 全10件確定、再開後も全20件確定 | `conflingo-status-repro-green` のビルドとCUA画面/AX |
| 全体回帰・Debugビルド | 295テスト・44スイート成功、2.024秒 | `/private/tmp/conflingo-final-status-full.log` / `.xcresult` |
| Releaseビルド | 成功 | `/private/tmp/conflingo-final-status-release.log` |
| SwiftLint | 109ファイル、違反0 | `/private/tmp/conflingo-final-status-lint.log` |
| 差分確認 | `git diff --check`成功 | 作業ツリー |

回帰テストは音声認識境界だけを偽物にし、連続する9文の最終化、入力間の交互到着、停止時のマイクfinal排出、重複なし・partialなし・idleを確認する。既存の再開・旧コールバック拒否・停止失敗・キャンセルのテストも全体スイートで成功。表示問題のRed/Greenそのものは合成UIで確認しており、追加コントローラテストが表示不具合を自動検出するとは主張しない。

製品の通常Meeting字幕画面は既に単一ForEachのため今回の変更対象外。音声認識モデル、最終化、ストア、AI設定は変更していない。

## 再現方法

一時ディレクトリへ `ConfLingo/` と `ConfLingo.xcodeproj/` だけをコピーし、検証アプリのSwiftファイルでそのコピーの `ConfLingo/ConfLingoApp.swift` を置き換える。製品リポジトリ側のエントリポイントは変更しない。コピーのbundle IDは一意の検証用IDへ変更し、別のderivedDataPathでDebugビルドする。

- Redで使用したID: `com.gavrri.conflingo.statusred`、成果物 `/private/tmp/conflingo-status-repro-red/Build/Products/Debug/ConfLingo.app`。
- Greenで使用したID: `com.gavrri.conflingo.statusgreen`、成果物 `/private/tmp/conflingo-status-repro-green/Build/Products/Debug/ConfLingo.app`。
- CUAで「Run synthetic sequence」を押し、約8秒後のストア件数と各行の確定表示を照合する。同じボタンの2回目で停止→再開を確認する。
- 検証アプリは本物のマイクを開く経路を注入せず、キーにもアクセスしない。画面上の権限表示は合成入力用のスタブであり、OS許可の証拠として扱わない。

## 実音声との区別

実音声で見つかった問題と同じ表示不一致を、確定データが存在すると確認できる合成試験で再現・解消した。局所的な表示変更のため、今回の修正後に実音声は再取得していない。以前の実音声試験そのものを合格へ書き換えず、実機の9英語文・4日本語文での再試験、通常Meeting、翻訳・保存、会議アプリ別・長時間の受入は別途残す。

認証済み元ビルドのdylib SHA-256は `68359040fb80160ab4524836c2739496ab58cdd9024b76a4f0adc02ff9a0d56a` のまま。製品の修正版は `/private/tmp/conflingo-final-status-product/Build/Products/Debug/ConfLingo.app` に別出力。API要求0、追加権限要求0、実音声保存0、コミットなし。
