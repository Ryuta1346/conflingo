# ConfLingo — 開発・進捗管理

> **本ファイルは常に簡潔明瞭に保つ。** 詳細な仕様・タスク説明・受入条件は [詳細計画](docs/meeting-copilot-plan.md) に集約し、ここに重複させない。

## 現在地

- 更新: **2026-11-08**／状態: **PR0実機確認持ち越し／PR1・PR2完了／PR3マージ済み、実機受入待ち／PR4実装・自動検証・コードレビュー済み／PR5-A方向性承認済み／PR5-B実装・自動検証済み**／進捗: **2/12**
- **持ち越し:** PR0の実音声・翻訳・保存操作、PR3の内部音声・権限・配布条件の確認（音声試験はユーザー指示で延期）
- **次の作業:** [PR5-Bネイティブ画面と検証記録](docs/validation/pr5-b-conference.md)のレビュー。実音声受入は引き続き延期
- 概算: PoC 2〜3週間、実用MVP 6〜10週間（着手日・期限は未設定）
- **確認済み:** Debugビルド、195テスト、lint（58ファイル・違反0）、2入力検証画面の表示。[PR4検証記録](docs/validation/dual-transcription.md)
- **未検証:** 実音声・実翻訳、内部音声取得、2入力STT

## PR進捗

| ID | 作業 | 依存 | 状態 | PR |
|---|---|---|---|---|
| PR0 | Baseline・検証環境 | — | **DOING** | [#5 (Merged・実機確認待ち)](https://github.com/Ryuta1346/conflingo/pull/5) |
| PR1 | 会話イベント・Event Hub | PR0（実機確認持ち越し承認済み） | **DONE** | [#6 (Merged)](https://github.com/Ryuta1346/conflingo/pull/6) |
| PR2 | 音声入力の共通化 | PR1 | **DONE** | [#7 (Merged)](https://github.com/Ryuta1346/conflingo/pull/7) |
| PR3 | システム音声キャプチャ | PR2 | **REVIEW** | [#8 (Merged・実機受入待ち)](https://github.com/Ryuta1346/conflingo/pull/8) |
| PR4 | マイク＋内部音声の同時STT | PR3（実機確認持ち越し承認済み） | **REVIEW** | [#9 (Draft)](https://github.com/Ryuta1346/conflingo/pull/9) |
| PR5-A | UI/UX全体設計・高品質モック | PR0 | **REVIEW** | [設計・モック](docs/design/README.md)・[#10 (Draft)](https://github.com/Ryuta1346/conflingo/pull/10)（方向性承認済み） |
| PR5-B | デザインシステム・Conference刷新 | PR5-A | **REVIEW** | [Draft PR #10](https://github.com/Ryuta1346/conflingo/pull/10)・[206テスト／画面検証](docs/validation/pr5-b-conference.md) |
| PR5-C | Meeting UI・フローティングUI | PR5-A/PR1、実結合はPR4/6 | TODO | — |
| PR6 | AI会話理解・根拠付き回答 | PR1/PR4 | TODO | — |
| PR7 | 決定・アクション候補管理 | PR6 | TODO | — |
| PR8 | ローカル資料検索・RAG | PR6 | TODO | — |
| PR9 | 結合・性能・安全性検証 | 全PR | TODO | — |

**順序:** PR0→1→2→3→4→6。PR5-AはPR0後、PR1〜4と並行可。**PR5-B/CはPR5-Aのモック承認後**、PR7/8はPR6後に着手。

## 品質ゲート

| Gate | 合格の概要 | 状態 |
|---|---|---|
| A | 既存Conference機能の無回帰 | 未検証 |
| B | Zoom/Meet/Teamsで2入力を識別・認識 | 未検証 |
| C | AI提案の根拠・誤確定防止・障害時縮退 | 未検証 |
| U | 全体UI刷新・承認モック整合・操作性 | 未検証 |
| D | 60分耐久・性能・プライバシー・実用判定 | 未検証 |

## 主な未解決事項

- **PR0:** 実音声試験はユーザー指示で後日実施。起動・専用モード切替は確認済み。Gate Aは未検証を維持。[検証記録](docs/validation/conference-baseline.md)
- **PR3:** PR #8マージ（`6b34a45`）・固定差分の独立コードレビュー完了、追加指摘なし。Zoom/Meet/Teamsの実音声・権限操作・配布条件は未検証。実音声試験の延期は継続。
- **PR0/3:** ScreenCaptureKitとProcess Tap、権限・Sandbox・配布の検証
- **PR4:** 実装・自動検証・コードレビュー完了、[Draft PR #9](https://github.com/Ryuta1346/conflingo/pull/9)作成済み。2系統SpeechAnalyzerの性能・精度・時刻誤差・遅延は未検証。新検証画面の閉鎖確認はUI取得タイムアウトで持ち越し。
- **PR5-A:** 9画面・状態別モックと設計資料を作成、ブラウザ検証済み。主要4画面の画像提示後に方向性承認済み。PR未作成・未マージのためREVIEWを維持。[検証記録](docs/design/validation.md)
- **PR5-C/6/8:** 会議参加者への通知・同意、資料・発話の外部送信制御

## 更新ルール

1. **現在地・PR状態・次の作業・ブロッカー・品質ゲートのみを簡潔に管理。** 詳細手順やチェックリストは詳細計画・PRに記載する。
2. 状態: `TODO / READY / DOING / BLOCKED / REVIEW / DONE`。**DONEはPRマージと受入検証の証跡がある場合のみ**。未検証を完了扱いしない。
3. PR開始・レビュー・マージ・障害発生時に該当行だけ更新し、PRリンク・証跡を加える。進捗は`DONE数/12`で算出する。
4. 解決済みの課題と古い履歴は移動・削除する。**追記による肥大化を避ける。**

## 更新履歴（直近のみ）

- **2026-11-08:** PR5-Aモック方向性を承認、PR5-B実装計画承認後、Conference刷新を実装。206テスト・Debug/Release build・lint成功、非録音ネイティブ操作確認済み。PR5-A/Bは[Draft PR #10](https://github.com/Ryuta1346/conflingo/pull/10)でレビュー、Gate Uは未完了。PR3マージ（`6b34a45`）を反映。PR4を計画承認後に実装し、195テスト・build・lint成功、コードレビュー完了。実音声受入は持ち越し。
- **2026-11-07:** [詳細計画 v1.1](docs/meeting-copilot-plan.md)確定、UI刷新をPR5-A/B/Cに分割。
