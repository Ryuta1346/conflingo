# Conference 回帰基準・PR0検証記録

更新: 2026-11-08。PR0作業中。自動テストと実機操作を区別し、Gate Aは実機確認まで未検証とする。

## 環境と基準

- 変更前: `f78be454d423a0c513fc4073d5ea3f012fc8deb7`、作業ブランチ: `feature/meeting-copilot`
- macOS 26.5.2 (25F84)、Apple Silicon arm64、Xcode 26.6 (17F113)
- Deployment target: macOS 26.0、Swift 6、Debug、ローカル署名、App Sandbox有効
- 手元の実装計画は2026-11-08にユーザー承認済み。

## 受け入れ条件

1. アプリのビルド、全単体テスト、SwiftLintが完了し、結果を記録できる。
2. 録音を開始していない場合の停止・繰り返し停止は、音声入力デバイスへの接続を発生させない。
3. 停止時に保留字幕を一度だけ翻訳キューへ確定する既存の動作を維持する。
4. 回帰表の実機確認には実測結果を記入する。未実施を成功扱いにしない。
5. 音声素材・同意・権限・計測手順と設計判断を参照できる。

## 変更前の検証結果

| 検証 | 結果 | 証跡 |
|---|---|---|
| Debug build | 成功。AppIntentsメタデータ抽出スキップの警告 | `/private/tmp/conflingo-pr0-build-20261108.log` |
| 全単体テスト | 60件成功後に進行停止。中断、全体合格ではない | `/private/tmp/conflingo-pr0-test-20261108.log` |
| SessionControllerTests単独 | 停止処理で再現 | `/private/tmp/conflingo-pr0-controller-red.log` |
| スタック採取 | `stopWithEmptyBufferDoesNotEnqueue` → `SessionController.stop` → `SpeechTranscriptionService.stop` → `AudioCaptureService.stop` → `AVAudioEngine.inputNode` → CoreAudioデバイス待ち | `/private/tmp/conflingo-pr0-controller-sample.txt` |
| lint | コマンド・設定なし | PR0で導入予定 |

最初のsandbox内ビルドはSwiftマクロ起動時の制約で失敗し、制限外で再実行して成功した。テスト停止はそれとは別に制限外でも再現した。音声関連ログの警告だけで原因を断定せず、上記スタックを根拠とする。

## 修正方針と検証予定

`AudioCaptureService.stop()` はキャプチャの開始準備で作成したストリームが存在する場合だけtap・エンジンを停止する。未開始や起動失敗の後、すでに停止済みの場合は入力ノードを取得しない。権限やSandboxの設定を変える必要はない。既存の停止テストをRedの再現として用い、繰り返し停止の回帰テストを追加する。

追加した繰り返し停止テストを含むスイートは修正前に35秒で未完了となり、中断した（`/private/tmp/conflingo-pr0-controller-with-regression-red.log`、終了コード124）。メソッド名だけの`-only-testing`指定はSwift Testingで0件だったため証跡から除外し、スイート指定で確認した。

## 修正後の検証結果（2026-11-08）

| 検証 | 結果 | 証跡 |
|---|---|---|
| Debug build | **成功**、xcodebuild終了0 | `/private/tmp/conflingo-pr0-final-build.log` |
| 全単体テスト | **111件・11スイート成功**、Swift Testing実行0.055秒、xcodebuild終了0 | `/private/tmp/conflingo-pr0-green-20261108.log` / `/private/tmp/conflingo-pr0-green-20261108.xcresult` |
| 二重停止の回帰テスト | `repeatedStopFlushesBufferedSegmentOnlyOnce`成功、保留文1件・キュー1件・idleを確認 | 上記ログ |
| SwiftLint 0.65.1 | **31ファイル、違反0**（strict / no-cache） | `/private/tmp/conflingo-pr0-final-lint.log` |
| 差分空白チェック | `git diff --check`成功 | 作業ツリーで実施 |

テスト時にはAppIntentsメタデータ抽出スキップやOSサービス`com.apple.linkd.autoShortcut`への接続警告が出るが、全テストは完了した。破損JSONのログは辞書復旧テストの期待ケース。個別のOS警告の解消はPR0の修正範囲に含めない。

生成した音声素材の長さ・ハッシュは[音声試験手順](audio-benchmark.md)に記録。実音声入力・実翻訳・性能はまだ未検証。

## 再現コマンド

リポジトリルートから実行する。結果バンドルの出力先は既存ファイルと重ならないよう一回ごとに作成する。

```sh
validation_dir=$(mktemp -d /private/tmp/conflingo-validation.XXXXXX)
xcodebuild -project ConfLingo.xcodeproj -scheme ConfLingo -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath "$validation_dir/DerivedData" build > "$validation_dir/build.log" 2>&1
xcodebuild -project ConfLingo.xcodeproj -scheme ConfLingo -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath "$validation_dir/DerivedData" -resultBundlePath "$validation_dir/tests.xcresult" test > "$validation_dir/test.log" 2>&1
swiftlint lint --strict --no-cache > "$validation_dir/lint.log" 2>&1
```

各コマンドの終了コードとログ末尾を個別に確認する。`TEST SUCCEEDED`だけでなくSwift Testingのテスト件数・失敗数も確認する。途中で失敗した場合はそこで調査し、最後のコマンドの成功で全体を成功扱いにしない。

### SwiftLintの導入

本PR0では[公式SwiftLint 0.65.1](https://github.com/realm/SwiftLint/releases/tag/0.65.1)を使用する。通常の`swiftlint`がなければ、以下のようにバージョン固定の配布物を検証してローカル配置できる。

```sh
lint_dir=$(mktemp -d /private/tmp/conflingo-swiftlint.XXXXXX)
curl -fL https://github.com/realm/SwiftLint/releases/download/0.65.1/portable_swiftlint.zip -o "$lint_dir/portable_swiftlint.zip"
printf '%s  %s\n' 'c1e429b0599cf1b516f369a2d9ec04eaf0e436f3c12b637df8851fa52ff694d0' "$lint_dir/portable_swiftlint.zip" | shasum -a 256 -c -
# ハッシュ検証が成功した場合だけ展開・実行する。
unzip -q "$lint_dir/portable_swiftlint.zip" -d "$lint_dir"
chmod +x "$lint_dir/swiftlint"
"$lint_dir/swiftlint" version
"$lint_dir/swiftlint" lint --strict --no-cache
```

`.swiftlint.yml`はアプリとテストの両方を対象にする。強制cast/try、重複import、未使用optional binding、基本的な空白・括弧・改行の12ルールを明示的に有効化する。既存の命名・長さの一括整形や違反のベースライン除外は行わない。lint成功はこの12ルールの範囲に限る。

## Conference回帰表

「自動」はメモリ上のモデル・制御・出力の検証。「実機」は実デバイス・OSモデル・GUIの検証。

| 項目 | 期待する結果 | 自動検証 | 実機 |
|---|---|---|---|
| 起動・モデル準備 | モデル準備状態を表示し、利用可能時に操作できる | 直接対象なし | 実機でダウンロード中表示→英語認識/日本語翻訳画面とStart有効を確認 |
| マイク許可/拒否 | 許可後に開始、拒否時に理由を表示しidleへ戻る | 直接対象なし | 未実施 |
| 英→日翻訳 | 原文と訳文を別ペインに表示 | キュー・用語保護の単体テスト | 未実施 |
| 文字起こし専用 | 訳文ペインなし、出力も原文のみ | MarkdownExporterTests | 切替で訳文ペインが消え、高速確定設定が出現。元の翻訳モードへの復帰を確認。実音声は未実施 |
| 途中/確定字幕 | 途中は更新、確定は追記・連続重複抑止 | SessionStoreTests | 未実施 |
| Start/Stop/再開 | 終了時の保留文を確定、二重停止で重複なし、再開可能 | SessionControllerTests（停止のみ） | 未実施 |
| 辞書プロファイル | 作成/複製/選択/名前変更/削除、再起動後保持 | KeywordProfileStoreTests（専用UserDefaults） | 未実施 |
| 辞書の認識/訳語 | 入力した用語を使い指定訳語を保護 | KeywordParserTests / TermProtectorTests | 未実施 |
| 言語切替 | 同言語の翻訳先を避ける、動作中は切替不可 | LanguageCatalogTests（候補解決） | 未実施 |
| Markdown保存 | 原文・訳文・時刻・未翻訳状態を保持 | MarkdownExporterTests（文字列） | 保存ダイアログは未実施 |
| Clear | idle時に履歴・保留文を消去、動作中は不可 | SessionStoreTests（reset） | 未実施 |
| ショートカット | Cmd+Rで開始/停止、Cmd+−/Cmd+＋で文字サイズ変更 | 直接対象なし | 未実施 |
| 最前面・文字サイズ | 切替・拡大縮小が反映される | 直接対象なし | 最前面checkboxの0→1→0と状態復元を確認。実際の重なり・文字サイズは未検証 |
| 既存保存データ | 辞書と設定が読み込める。セッション履歴はメモリのみ、明示保存はMarkdown | 辞書旧形式の移行テスト | 個人データは未操作 |

GUI確認は2026-11-08にビルド済みDebugアプリを起動し、ネイティブアクセシビリティツリーで確認した。辞書・個人データの編集、マイクの開始、スピーカー再生は実施していない。切り替えた文字起こし専用・最前面の設定は元に戻した。実機音声試験は同日のユーザー指示で後日実施とした（[実施方針](audio-benchmark.md#実機音声試験の実施方針)）。Gate Aの合格やPR0の完了を意味しない。

## 関連資料

- [音声素材・同意・実機試験・計測](audio-benchmark.md)
- [設計判断 ADR-001](../adr/001-meeting-copilot-baseline.md)
- [全体の詳細計画](../meeting-copilot-plan.md)

PR0のDONEにはPRマージと受入検証の証跡が必要。自動検証だけではGate Aを通過しない。
