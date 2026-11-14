# PR #43 CI失敗の修正

2026-11-15。基点 `e0bc210`。[計画](../design/ci-failure-fix-plan.md)。ユーザー「修正して」による対応。

## 確認した原因と修正

- [失敗run 43607605159](https://github.com/Ryuta1346/conflingo/actions/runs/43607605159): HTTPの2 MiB境界テストが60秒超過。URLSession.AsyncBytesの1 byte反復をMainActorで行っていた。HTTP接続設定・応答検証は維持し、走査だけを`@concurrent`へ移した。SSEのMainActor callbackはchunkごとに逐次awaitし、2 MiB上限・行単位/1,024 byte単位配信・例外伝播・セッション終了を維持。
- 同runのMicrophoneConfigurationSessionTestsとInsightRecoveryTestsは、並列実行時にMainActorの処理待ちが2秒のポーリング期限を越えた。停止完了/overflowの実状態をObservationで待つ。suiteの60秒上限と失敗時の取消は維持。
- MeetingAIIntegrationTestsは実時計の同意時刻に対し、固定オフセット2秒の合成発話を送っていた。処理待ちが長いと同意前の発話として除外されるため、既存MeetingTimelineの時刻注入でテスト時計を固定。製品の同意判定は変更しない。
- 受信callbackがEOFで取消したとき、旧実装は成功終了していた。先行テストで再現し、最終配信後にも取消を確認する。callbackのMainActor実行と、取消後に後続chunkを配信しないことも検証。

## 再現・検証

- Red: `callbackCancellationStopsDeliveryIncludingAtEOF(byteCount:)`の3 byteケースが「expected error but none was thrown」で失敗。`/tmp/conflingo-ci-fix-red.log`。最初の実行は引数付きテスト識別子が不完全で0件だったため、正しい識別子で再実行し1定義を確認した。
- 性能: [同一2 MiB応答のプローブ](ci-failure-fix-2026-11-15/Probe.swift)。Debug、Swift 6、NonisolatedNonsendingByDefault有効でMainActor 11.286秒、`@concurrent` 0.115秒。URLProtocolが全応答を合成し、外部通信しない。これはローカル比較で、GitHubでの所要時間を保証する測定ではない。
- 関連テスト: 34定義・7suite成功、1.666秒。HTTP上限ちょうど/1 byte超過は2ケース合計0.939秒、Web調査の上限ちょうどは0.185秒。`/tmp/conflingo-ci-fix-focused.log`。
- 初回の修正ビルドで`Observations(stopped)`によるSwift 6.3.3のIR生成クラッシュを確認。明示的なクロージャ`Observations({ stopped() })`に直してビルド・関連テストが成功。
- 全体: 通常並列で701定義・126suite成功、32.898秒。実API7定義を従来どおり除外。[xcresult集計](ci-failure-fix-2026-11-15/test-summary.json)。
- Lint: SwiftLint 0.65.1 strict/no-cache、272ファイル・違反0。署名なしRelease成功、lipoでarm64/x86_64を確認。`bash -n`・ShellCheck・actionlint・`git diff --check`成功。
- 再現: `CONFLINGO_CI_OUTPUT_DIR=/tmp/conflingo-ci-fix-validation SWIFTLINT_BIN=/tmp/conflingo-swiftlint-0.65.1/swiftlint bash scripts/ci.sh all`。各logとxcresultは同出力ディレクトリ。
- 主担当が差分をレビューし、逐次配信、取消伝播、受信上限、セッション終了、状態変化待機を確認。独立エージェントによるレビューは未実施。
- この記録時点では修正をpushする前で、リモートCI成功は未確認。push後、全工程の成功を確認してからマージする。テスト除外追加、製品タイムアウト変更、自動再試行による成功化は行っていない。
