# 第2段階・構成ルート分離

2026-11-14。残タスク計画第2段階の先頭項目。ユーザー「次進めて」により着手。
正本: `~/.coding-agents/docs/conflingo/main/app-composition-plan.md`。
Planモード切替機能がないため、この文書で実装前の計画を記録する。

## 現状と変更

`ConfLingoApp`がMeeting・小窓・入力排他を所有し、`ContentView.init`が残るサービスと別のMeeting生成経路を持つ。Viewの再生成時に不要なサービスを作り、設定・プレビュー・共有インスタンスの接続が二か所に分散している。

`@MainActor final class AppComposition`を追加し、Appが`@State`で一つ保持する。以下を一度生成し、`ContentView(composition:)`とメニュー・検証画面へ同じ参照を渡す。

- 設定、プレビュー種別・シナリオ、AudioInputUse
- SessionsLibrary、KnowledgeLibrary、MeetingWorkspace、ConferenceKnowledgeWorkspace、MeetingFloatingPanel
- SessionStore、SessionController、TranslationCoordinator、ModelAvailabilityService、KeywordProfileStore、ConferenceNavigation
- DebugだけのSystemAudioProbeController、DualTranscriptionController

`ContentView`には生成処理を置かず、注入された参照と既存の表示状態を持たせる。Bindingが必要なstore/navigationは`@Bindable`で受け取る。AppStorageは構成オブジェクトで選択済みのUserDefaultsを使う。初回プレビュー準備は従来通りAppのtaskで一回だけ行う。

通常起動は.standard、`--ui-preview`はConference用suite、`--meeting-preview`はMeeting用suite。テストでは固有suiteを明示注入できるようにする。Releaseではプレビュー引数を無視する。実AIプレビューは既存の2フラグ同時指定条件を維持し、今回は実行しない。

## 維持する契約

- Conference/Meeting/検証画面の入力排他は同じAudioInputUseを使う。Meetingのownerは.meeting。
- 主画面と小窓は同じMeeting、Conference支援とMeetingは同じLLMSettingsを参照する。字幕storeとConference支援の接続も維持する。
- 保存先・保存形式・明示保存・停止完了待ち・失敗時保持を変更しない。永続ファイルを移行・削除しない。
- 通常プレビューは既存の合成音声・翻訳・InsightClient・キーstoreを使う。起動だけで収集・モデル準備・AI送信を開始しない。既存の明示操作によるWeb調査等の通信ポリシーはこの抽出で変更しない。
- 初期画面は通常home、Conferenceプレビューlive、Meetingプレビューmeeting。
- シート、確認ダイアログ、翻訳task、画面遷移の停止処理はViewに残す。

## 変更対象と検証

新規`AppComposition.swift`、`ConfLingoApp.swift`、`Views/ContentView.swift`、その呼び出し元2テスト・Preview。README英日構成図とplan.mdを結果に合わせて更新する。

先に構成の契約テストを追加し、未提供の構成APIを理由とするビルド失敗を確認する（既存の振る舞いの不具合とは区別）。実装後、次を検証する。

1. 起動引数、設定suite、初期画面、合成字幕、共有設定・store・入力排他の接続。
2. 合成Meeting開始中にConferenceが開始を拒否し、停止後に所有権を解放する。
3. 同じ構成でViewを再生成しても会議・字幕・選択画面を保持する。設定変更が同じsuiteに保存される。
4. 通常プレビューのキーstore・InsightClientがfakeで、明示2フラグ条件は既存テストで維持される。
5. 関連テスト、通常並列の全テスト、SwiftLint strict/no-cache、Release arm64/x86_64ビルド。実APIフラグは全て0。

共通支援/通知統一、SSE集約、CIは後続項目として残す。コミット・push・実音声・実API評価は含めない。

## 完了記録

2026-11-14、ローカル実装・検証・独立レビュー完了、実装コミット済み。全688件中681成功・実API7skip、Lint259ファイル違反0、Release両CPU成功、独立レビュー2観点指摘0。[検証記録](../validation/app-composition-2026-11-14.md)。
