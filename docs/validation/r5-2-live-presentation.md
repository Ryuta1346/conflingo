# R5-2 — ライブ表示の履歴再計算・検証結果

> 2026-11-14独立レビュー追記: 固定main `33c8ae6`で[残件レビュー](remaining-review-2026-11-14.md)を実施済み。指摘・未修正項目・確認範囲は同記録を参照。以下の「独立レビュー未実施」は当時の履歴で、実機受入の未完了は継続。

> 2026-11-14マージ確認: R5-1 `39e1d7b`・R5-2 `1510670`を含む[PR #36](https://github.com/Ryuta1346/conflingo/pull/36)はローカルmain `a607f6e`へマージ済み。独立レビュー完了・実機受入は未確認。以下の「未コミット・未PR・未マージ」はローカル検証完了時点の記録。R5-3も[ローカル実装・検証済み](r5-3-query-selection.md)。

2026-11-14 / 基点: main `7888730`＋R5-1の未コミット変更 / [承認済み計画](../design/r5-2-live-presentation-plan.md)

## 変更

- Conferenceは`SessionStore`内の非Observableなキャッシュへ確定表示を保持する。原文はセッション・確定件数・補正、訳文は翻訳更新revision・補正・準備状態で無効化する。途中字幕だけの変更では確定履歴を再生成しない。
- `TranscriptEntries`は確定履歴と末尾1行を連結配列なしで参照する。スクロールの変更検知は履歴識別子と末尾行だけを比較する。文末待ちの原文は既存ID辞書から取得する。
- Meetingの`MeetingTranscriptTimeline`は整列済みfinalsへ最大2件のpartialsを二分探索で挿入して参照する。同時刻は従来どおり確定発話が先。小窓の末尾3件取得に全履歴の列挙は不要になった。
- Meetingの追従判定は発話・翻訳の表示更新revisionへ変更した。翻訳の`completed`は保存用として維持する。サイズ変更時の下端追従は内容サイズと表示領域サイズの双方を監視する。
- 保存形式・発話ID・翻訳本文・R5-1の要約上限は変更していない。Clearでキャッシュ参照を破棄する。

## TDD・回帰確認

Conferenceは全件mapを残した段階で履歴の同一性テストが失敗した（2テスト、42 issues）。Meetingは旧結合・ソートを残した段階で30,000件を列挙し、40件以下の読み出し条件に失敗した（5テスト、1 issue）。実装後の関連37テスト／7 suitesは成功。

| 対象 | 検証 |
|---|---|
| Conference途中更新 | 原文・訳文の履歴参照を再利用、末尾本文・予約高を更新。以前取得した表示スナップショットを変更しない |
| 履歴の無効化 | 確定追加、翻訳待ち・開始・完了・失敗、モデル準備・失敗・復帰、複数segmentの補正採用・取消、バッファflush、reset |
| Meetingの順序・処理量 | 0／1／5／30,000件、途中0／1／2件、中間挿入・同時刻・逆順参照・非0始点slice。2回の二分探索＋末尾3件でfinals読み出し40件以下 |
| 更新通知 | 受理した発話、確定化、clearPartials、reset、翻訳失敗・再試行・完了。別セッション・空本文・古いrevision・確定済み再送は通知しない |
| 合成UI | キャッシュhit後の確定・訳文・Clear反映。Meeting根拠ジャンプ後、途中字幕と翻訳が来ても根拠行は可視範囲内。Conference手動スクロール後も閲覧行を保持。「最新へ」、Meetingリサイズ後の下端追従を確認 |

UIは`NSHostingView`、合成イベント、fake翻訳、AX要素の可視領域とボタン操作で検証した。初回の厳密な「座標差2pt未満」は不安定だった。旧Meeting表示処理・旧Conference配列比較へ一時的に戻しても同じ失敗を再現し、Conferenceでは14ptの差が出た。Meetingは別実行で0ptにもなった。遅延レイアウトの座標変動と今回の回帰を区別し、最終テストは閲覧行の可視性・履歴モード・明示操作での最新復帰を検証する。ピクセル単位の完全固定を保証するものではない。旧処理への一時変更は復元済み。

## データ準備の比較計測

[変更前と同じ入力・条件](r5-2-live-presentation-baseline.md)。合成300／3,000／30,000確定発話、200途中更新、3回の中央値、10回ウォームアップ、Swift `-O`。単位ms。描画・body頻度・実音声遅延は含まない。

| 確定発話数 | Conference補正なし 旧→新 | Conference補正20件 旧→新 | Meeting 旧→新 |
|---:|---:|---:|---:|
| 300 | 19.340 → 0.673 | 48.211 → 0.576 | 2.345 → 0.714 |
| 3,000 | 132.840 → 0.262 | 487.065 → 0.255 | 23.134 → 0.279 |
| 30,000 | 1,385.941 → 0.275 | 5,200.837 → 0.265 | 229.730 → 0.334 |

全ケースのchecksumは変更前と一致。計測外で全表示行を旧変換処理と比較し、ID・本文・状態・時刻・予約高が等しいこともassertした。旧変換は`7888730`から抽出した`LegacyPresentation.swift`で、製品・テストターゲットには含めない。キャッシュmissとなる確定追加・補正変更やSwiftUI自身の差分・レイアウトの全件処理は、この数値から高速化を主張しない。

メモリは別の合成30,000件プロセスでRSSを計測した。キャッシュ生成前36,945,920 bytes、生成後44,859,392 bytes（約7.9MB増）、1,000途中更新後も44,859,392 bytes。reset後はweak参照で両履歴の解放を確認したが、RSSは同値だった。アロケータの保持を含むRSSとオブジェクトの生存を区別する。長時間耐久・実アプリ全体のメモリ上限を証明する測定ではない。

生データ: [optimized.csv](r5-2-probe/optimized.csv)・[memory.csv](r5-2-probe/memory.csv)。ソース: [OptimizedProbe.swift](r5-2-probe/OptimizedProbe.swift)・[MemoryProbe.swift](r5-2-probe/MemoryProbe.swift)・[製品ソースSHA-256](r5-2-probe/optimized-source-hashes.json)。

```sh
xcrun swiftc -O -parse-as-library \
  -module-cache-path /tmp/conflingo-r5-2-probe/module-cache \
  ConfLingo/Models/{TranscriptEvent,TranscriptSegment,TranslationUnit,KeywordParser,SentenceBoundary,SessionStore,MeetingSessionStore}.swift \
  ConfLingo/Conference/{TranscriptPresentation,TranscriptEntries}.swift \
  ConfLingo/Meeting/MeetingTranscriptTimeline.swift \
  docs/validation/r5-2-probe/{Support,LegacyPresentation,OptimizedProbe}.swift \
  -o /tmp/conflingo-r5-2-probe/optimized
/tmp/conflingo-r5-2-probe/optimized
```

MemoryProbeは最後の入力を`{Support,MemoryProbe}.swift`へ置き換えて別バイナリとして実行する。

## 最終検証

- 全629テスト／114 suites：622成功・実API評価7skip・失敗0、59.808秒。xcresultの集計でも確認。
- SwiftLint 0.65.1 strict/no-cache：243ファイル・違反0。
- Release：arm64／x86_64、署名なしのビルド成功。
- `git diff --check`：成功。キャッシュの無効化・Observation依存・表示順・不要な全件変換を自己レビューした。

```sh
xcodebuild test -project ConfLingo.xcodeproj -scheme ConfLingo \
  -destination 'platform=macOS' -derivedDataPath /tmp/conflingo-r5-build \
  CODE_SIGNING_ALLOWED=NO
/tmp/conflingo-swiftlint-0.65.1/swiftlint lint --strict --no-cache
xcodebuild -project ConfLingo.xcodeproj -scheme ConfLingo \
  -configuration Release -derivedDataPath /tmp/conflingo-r5-release \
  CODE_SIGNING_ALLOWED=NO build
```

テスト時は`CONFLINGO_LIVE_AI`、`CONFLINGO_FOCUSED_LIVE_AI`、`CONFLINGO_GROUNDING_LIVE_AI`、`CONFLINGO_RAG_LIVE`、`CONFLINGO_SUMMARY_LIVE`、`CONFLINGO_SUMMARY_REMAINING_LIVE`、`CONFLINGO_SUMMARY_DEADLINE_LIVE`、`CONFLINGO_R2_SIZE_LIVE`をすべて0にした。

ログ: `/tmp/conflingo-r5-2-{red,timeline-red,focused,ui,ui-legacy,full,lint,release}.log`。
全テストxcresult: `/tmp/conflingo-r5-build/Logs/Test/Test-ConfLingo-2026.11.14_01-42-22-+0900.xcresult`。
集計: `/tmp/conflingo-r5-2-test-summary.json`。
AppIntentsメタデータ省略と合成UIのScrollGeometryログは残るが、最終テスト・ビルドの失敗はない。

実API評価の8種類のliveフラグはすべて0。音声取得・実API送信・インストール済みアプリ更新・コミット・PR作成は0。独立レビューと実音声・長時間UI耐久は未実施。

R5-2はローカル実装・検証済み、REVIEW相当。未コミット・未PR。次は資料検索語の選択（アルファベット順の先頭32語）の調査・計画。R5-1の未コミット変更は保持している。
