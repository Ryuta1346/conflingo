# 共通支援の切り出し・通知統一

2026-11-14。ユーザー「共通支援の切り出し・通知統一すすめて」により、残タスク計画第2段階の項目2へ着手。
正本: `~/.coding-agents/docs/conflingo/main/shared-assistance-notifications-plan.md`。
Planモード切替機能がないため、この文書に実装前の計画を記録する。今回の明示依頼を本項目の実施承認として引き継ぐ。

## 現状

Conference/MeetingがそれぞれKnowledgeStore・InsightCoordinator・WebResearchCoordinator・資料用語を構成している。KnowledgeStore、SessionStore、MeetingSessionStore、LLMSettings、DualTranscriptionControllerの同期通知には、単一コールバック・解除不能配列・UUID購読が混在する。複数の利用者の登録による上書き、終了した所有者の購読が残る問題を防ぐ必要がある。

## 変更予定

1. MainActor内の同期通知に小さな型付きEventSignal/EventSubscriptionを導入する。登録順に同期配信し、購読を持つ利用者が所有する。cancelは冪等、購読を破棄すると配信しない。配信中の解除を即時反映し、配信中の追加は次回から対象とする。弱参照で購読を保持し、次回登録/配信時に失効した登録を除去する。
2. KnowledgeStoreの変更/無効化/内容変更、LLMSettings変更、両字幕storeの確定/リセット/phase、DualTranscriptionControllerのphase/取得状態をこの方式へ移す。利用側は購読を保持する。APIKeyCredentialsの単一所有コールバックと、入力準備/終了をawaitする委譲フックは通知と区別し、今回変更しない。
3. SessionAssistanceへAI・Web調査・資料・用語の生成と共通の許可/停止/リセットを移す。両Workspaceはこれを所有し、既存のUI参照をcomputed propertyで提供する。Conferenceの発話変換・補正・資料単独質問、Meetingの音声/翻訳・要約・保存は各Workspaceに残す。
4. Conferenceの通知接続はWorkspaceの寿命に従う。SessionControllerのphase購読は開始時に前回を解除して付け直す。Meetingの音声イベントhub購読の世代判定・停止待ちは既存実装を維持する。

## 維持する契約

- 許可は初期オフ。設定変更でAI/Web許可を取り消す。資料内容変更成功時に資料送信許可・自動資料許可と用語をリセットし、失敗時は既存資料/許可を維持する。無効化時の要約取消・Conferenceの補正取消を維持する。
- 音声停止前にAI/Web送信を停止し、古い応答は採用しない。再開は同じ会議の記録を保持し、破棄は新sessionへ切り替える。
- 保存形式・保存先・引用根拠・Markdown・UIの表示契約を変更しない。購読の追加で同じ発話を二重にAIへ渡さない。
- SSE/LLM分岐整理、CI、実API/実音声評価は今回の範囲外。コミット・push・PR作成は後続のユーザー「コミットand PR作成」で承認。

## 検証予定

資料更新 → 先行テストのRed → 最小実装 → 関連テスト → 全テスト → SwiftLint strict/no-cache → Release両CPUビルド → 差分確認 → 結果記録。

- 通知の複数購読、明示解除、token解放、配信中の解除/追加、登録順と一回配信。
- 追加の購読者がConference発話接続・Meeting翻訳・資料許可取消・設定変更通知を上書きしない。
- 同じ設定に複数Workspaceを接続した場合、全ての許可を解除する。破棄したWorkspaceを保持せず、残ったWorkspaceの通知を維持する。
- Conferenceの繰り返し同期/リセット、Meetingの停止/再開、旧実行の応答棄却をfakeで検証。既存の資料変更失敗/成功、要約取消、保存golden、UI回帰も実行する。
- 全実API評価フラグ0。実音声・利用者のキー・保存データを使用しない。

## 完了記録

実装コミット`3e4e27b`。ローカル実装・自動検証完了、[Draft PR #42](https://github.com/Ryuta1346/conflingo/pull/42)提出済み・未マージ。先行2テストの通知上書き不具合を修正し、全698定義中691成功・実API7skip、Lint263ファイル違反0、Release arm64/x86_64成功。[結果](../validation/shared-assistance-notifications-2026-11-14.md)。主担当の差分確認済み、独立レビュー・実機受入は未実施。
