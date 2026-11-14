# macOSの自動検証

[workflow](../../.github/workflows/ci.yml)はPR、mainへのpush、workflow_dispatchを対象とする。
macOS 26 arm64とXcode 26.6（17F113）を検査し、SwiftLint 0.65.1を固定SHA-256で確認して使う。
環境の根拠は[GitHub公式イメージ](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md)。runnerのOS更新自体を固定するものではない。

## ローカル実行

Xcode 26.6を選択し、SwiftLint 0.65.1がPATHにある状態で次を実行する。

```sh
bash scripts/ci.sh
```

`lint`、`test`、`release`を引数に指定すると個別実行できる。`SWIFTLINT_BIN`でバイナリ、`CONFLINGO_CI_OUTPUT_DIR`で結果の保存先を指定できる。省略時は新しい一時ディレクトリを作る。`test`の再実行時は既存のxcresultを上書きせず、新しい保存先を指定する。

SwiftLintが未導入なら、一時ディレクトリへ導入できる。

```sh
bash scripts/install-swiftlint.sh /tmp/conflingo-tools
SWIFTLINT_BIN=/tmp/conflingo-tools/swiftlint bash scripts/ci.sh
```

## 検証範囲

- SwiftLint strict/no-cache。
- 既定の並列設定で全ローカルテスト。8つの実API評価フラグを0にし、実APIを使う4suite（7テスト定義）を明示除外する。合成HTTP応答やローカルfixtureを使用し、利用者のキー・実音声は使用しない。
- 署名なしReleaseをarm64/x86_64でビルドし、lipoで両アーキテクチャを検査する。
- `set -euo pipefail`でLint/テスト/ビルド失敗を伝播。エラー後の自動再実行で成功化しない。
- workflowはcontents:readのみ、checkoutの認証情報を残さず、同一refの古いrunを取り消す。30分上限。ログとxcresultを成功/失敗時に7日間保持し、アプリ本体はアップロードしない。

ここでの「無通信」は実LLM/実音声の評価をしない意味。checkout、公式ツール取得、GitHub成果物保存は通信する。配布署名、実機VoiceOver、実モデル品質、会議アプリ別入力、60分耐久の合格を保証しない。リモートworkflowの実行結果はローカルの結果とは別に記録する。
