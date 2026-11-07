# ADR-001: Conferenceの回帰基準を固定してMeetingを追加する

- 日付: 2026-11-08
- 状態: 採用（PR0計画承認に基づく方針。Meeting機能は未実装）
- 対象: [詳細計画](../meeting-copilot-plan.md) PR0〜PR4

## 背景

Conferenceはマイク、Speech.framework、Translation.frameworkを使い、用語辞書をUserDefaultsに保持する。セッションの字幕・訳文はメモリ上に置き、明示操作でMarkdown保存する。Meetingの2入力・会話理解を追加する際も、この操作と保存形式を回帰基準にする。

## 決定

1. PR0で現行build/test/lintと実機操作の証跡を分けて記録する。自動テスト合格を実音声の認識・翻訳成功と同一視しない。
2. 既存SessionStore / TranscriptSegmentを全面置換せず、Meeting用ドメインとイベント配信をPR1以降で追加する。既存翻訳にはアダプタで接続する。
3. PR0の修正は未開始の音声入力を停止時に初期化しないことに限定する。単体テストのためにApp Sandboxを無効化したり、音声関連の例外entitlementを追加したりしない。
4. システム音声はPR3でScreenCaptureKitを先に検証する。Process Tapとの優劣は未確定とし、検証後に別ADRで採否を記録する。
5. 音声・文字起こし・翻訳は現行のオンデバイス処理を基準にする。将来のクラウドAIはPR6以降、ユーザーによる明示的な送信許可のある会議だけを対象とする。

## 比較した案

| 案 | 判断 |
|---|---|
| 既存モデルをMeeting用に全置換 | 保存形式と翻訳処理まで同時に変わり、回帰の切り分けが難しいため採用しない |
| テストをskipして先に進む | 停止時flushの回帰検出を失うため採用しない |
| Sandboxの解除・例外追加 | 未開始入力へのアクセスが不要という問題を解決しないため採用しない |
| 既存モデル維持＋段階的な追加 | 各PRの検証範囲を限定できるため採用 |

## 帰結と後続の判断

- 一時的にConferenceとMeetingのモデルが共存する。統合の判断は実際のイベント・保存要件が揃ってから行う。
- 内部音声方式、2系統STTの性能、画面共有時の表示、通知・同意UIは未検証。
- PR3ではZoom / Meet / Teamsの入力範囲、自己音声除外、権限拒否・取消、デバイス切替、Sandboxと配布条件を同じ試験条件で比較する。
- PR4では共通時計・重複・同時発話・遅延・CPU/メモリを計測する。数値未取得の段階では方式の有効性を断定しない。

## 根拠

- [Conference回帰基準・再現スタック](../validation/conference-baseline.md)
- `ConfLingo/ConfLingo.entitlements`
- `ConfLingo/Models/KeywordProfileStore.swift`
- `ConfLingo/Services/AudioCaptureService.swift`
- `ConfLingo/Export/MarkdownExporter.swift`
