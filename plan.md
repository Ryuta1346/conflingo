# ConfLingo — 開発・進捗管理

> **本ファイルは常に簡潔明瞭に保つ。** 詳細な仕様・タスク説明・受入条件は [詳細計画](docs/meeting-copilot-plan.md) に集約し、ここに重複させない。

## 現在地

- 更新: **2026-11-11**／進捗: **2/12**。PR1・2はDONE。PR0は実機確認待ち、PR3〜8はマージ済み・残る受入待ち、PR9は未着手。
- **次の作業:** PR7の実API要約品質評価のケース・要求数・費用上限を具体化する。PR8の2指摘は修正・342テスト・lint・Release検証済み、実APIは16/16合格（計数込み32要求、推定US$0.04850325）。[結果](docs/validation/pr8-quality-acceptance.md)。修正ブランチは提出準備中。実音声再受入は読み上げ準備待ちを維持。
- **確認済み:** PR8品質対応後342テスト・Debug/Release・lint131ファイル違反0、合成実API16/16合格。PR8初版の非録音UI確認も完了。[検証記録](docs/validation/pr8-local-rag.md)。PR6は3.8 Flash/medium・8192で品質52/52合格、Keychain・回答言語保存/復元・実受信後の停止/取消・再開後回答を確認済み。
- **確認済みの範囲:** [キーボード主要経路・反復とVoiceOver基本操作](docs/validation/pr6-focus-stability.md)は確認済み。全画面・全状態の受入とは区別する。実音声2入力STTは一部確認済みだが、停止表示修正版の実音声再確認は未実施。
- **完了条件:** 残る実機受入・品質検証の証跡を記録し、対象PRのマージと受入完了を確認してDONEへ更新する。今回の追加検証は合成資料による実API評価。実音声受入と修正ブランチのマージは未完了。

## PR進捗

| ID | 作業 | 依存 | 状態 | PR |
|---|---|---|---|---|
| PR0 | Baseline・検証環境 | — | **DOING** | [#5 (Merged・実機確認待ち)](https://github.com/Ryuta1346/conflingo/pull/5) |
| PR1 | 会話イベント・Event Hub | PR0（実機確認持ち越し承認済み） | **DONE** | [#6 (Merged)](https://github.com/Ryuta1346/conflingo/pull/6) |
| PR2 | 音声入力の共通化 | PR1 | **DONE** | [#7 (Merged)](https://github.com/Ryuta1346/conflingo/pull/7) |
| PR3 | システム音声キャプチャ | PR2 | **REVIEW** | [#8 (Merged・実機受入待ち)](https://github.com/Ryuta1346/conflingo/pull/8) |
| PR4 | マイク＋内部音声の同時STT | PR3（実機確認持ち越し承認済み） | **REVIEW** | [#9 (Merged・実機受入待ち)](https://github.com/Ryuta1346/conflingo/pull/9) |
| PR5-A | UI/UX全体設計・高品質モック | PR0 | **REVIEW** | [設計・モック](docs/design/README.md)・[#10 (Merged)](https://github.com/Ryuta1346/conflingo/pull/10)（方向性承認済み） |
| PR5-B | デザインシステム・Conference刷新 | PR5-A | **REVIEW** | [PR #10 (Merged・受入待ち)](https://github.com/Ryuta1346/conflingo/pull/10)・[211テスト／レビュー修正検証](docs/validation/pr5-b-conference.md) |
| PR5-C | Meeting UI・フローティングUI | PR5-A/PR1、PR4実機受入持ち越し承認済み／AIはPR6 | **REVIEW** | [実装計画](docs/design/pr5-c-implementation-plan.md)・[検証記録](docs/validation/pr5-c-meeting.md)・[#11 (Merged・受入待ち)](https://github.com/Ryuta1346/conflingo/pull/11) |
| PR6 | AI会話理解・根拠付き回答 | PR1/PR4、実機受入持ち越し承認済み | **REVIEW** | [PR #12 (Merged)](https://github.com/Ryuta1346/conflingo/pull/12)・[品質改善 #13 (Merged)](https://github.com/Ryuta1346/conflingo/pull/13)・[修正・受入 #14 (Merged)](https://github.com/Ryuta1346/conflingo/pull/14)・[製品品質52/52合格](docs/validation/pr6-model-adoption.md) |
| PR7 | 決定・アクション候補管理 | PR6（実機受入持ち越し承認済み） | **REVIEW** | [計画](docs/design/pr7-implementation-plan.md)・[316テスト／非録音UI・修正検証](docs/validation/pr7-meeting-state.md)・[#16 (Merged・受入待ち)](https://github.com/Ryuta1346/conflingo/pull/16) |
| PR8 | ローカル資料検索・RAG | PR6 | **REVIEW** | [計画](docs/design/pr8-implementation-plan.md)・[331テスト／非録音UI検証](docs/validation/pr8-local-rag.md)・[#17 (Merged・受入待ち)](https://github.com/Ryuta1346/conflingo/pull/17) |
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

## 残る実機受入・品質検証

上からの実施順を目安とする。実音声待ちの間はレビュー・評価ケース準備を進める。詳細な手順・判定基準はリンク先と[品質ゲート](docs/meeting-copilot-plan.md#4-フェーズごとの受入基準)を参照。

| 完了 | 対象 | 残タスク・確認する結果 | 証跡・手順 |
|---|---|---|---|
| [ ] | PR8／レビュー | 独立レビュー・MEDIUM 2件の修正検証・実API評価は完了。修正ブランチのマージが残る | [レビュー](docs/validation/pr8-independent-review.md)・[結果](docs/validation/pr8-quality-acceptance.md) |
| [ ] | PR4／Gate B | 停止表示修正版で短時間2入力を再試験。入力元・主旨・数値・partial/final、停止後の認識中行解消、再開後の旧入力混入なしを確認 | [実音声再受入](docs/validation/real-audio-fixed-reacceptance.md) |
| [ ] | PR0・5-B／Gate A | Conferenceの実翻訳・文字起こし専用・字幕・停止/再開・辞書・言語切替・Clear・Markdown保存・権限拒否/復旧など、回帰表の未実施項目を実機確認 | [Conference回帰表](docs/validation/conference-baseline.md#conference回帰表) |
| [ ] | PR3・4／Gate B | Zoom/Meet/Teamsそれぞれで内部音声とマイクを識別。入力切替・機器/権限変更・切断/復旧・検証画面閉鎖時の停止、2系統STTの精度・時刻誤差・遅延・CPU/メモリを確認 | [2入力検証](docs/validation/dual-transcription.md)・[詳細計画](docs/meeting-copilot-plan.md) |
| [ ] | PR5-C・6・7・8／Gate C | 通常Meetingの開始→一時停止/再開→終了→候補確認/却下→要約→Markdown保存を実音声で確認。根拠表示・誤確定防止・提案連発防止、通信断時の音声継続とAIのみの縮退、資料検索との結合を確認 | [PR5-C](docs/validation/pr5-c-meeting.md)・[PR6](docs/validation/pr6-model-adoption.md)・[PR7](docs/validation/pr7-meeting-state.md)・[PR8](docs/validation/pr8-local-rag.md) |
| [ ] | PR7／Gate C | 実APIの区間別要約について意味品質、長い会議の訂正・矛盾・根拠の扱いを評価。要求数・費用上限は実行前に承認 | [PR7残る受入](docs/validation/pr7-meeting-state.md#残る受入) |
| [x] | PR8／合成引用品質 | 日英16/16ケースの意味・言語・引用が合格。命令・矛盾・不足資料を含む。Gate C全体とは区別 | [PR8品質評価](docs/validation/pr8-quality-acceptance.md) |
| [ ] | PR5-A/B/C・6〜8／Gate U | 承認モックと実装画像の比較、未確認の画面/空・失敗状態、全操作の受入記録を完成。VoiceOver全経路、画面共有・複数画面・高コントラスト等を確認。PR5-Cの独立コード/画像レビューを実施 | [設計検証](docs/design/validation.md)・[PR5-B](docs/validation/pr5-b-conference.md)・[PR5-C](docs/validation/pr5-c-meeting.md)・[確認済み範囲](docs/validation/pr6-focus-stability.md) |
| [ ] | PR0・3・9／Gate B・D | ScreenCaptureKit/Process Tapの権限・Sandbox・配布条件と配布署名での動作を検証 | [詳細計画](docs/meeting-copilot-plan.md) |
| [ ] | PR9／Gate D | 60分実会議の耐久、クラッシュ・メモリ増加・処理滞留、入力切断/再接続、APIタイムアウト・連続開始/停止を確認。発話終了→AI完成のp95目標8秒とSTT遅延を実測し、質問検知率・誤提案率・根拠正確性を記録 | [Gate D・テスト計画](docs/meeting-copilot-plan.md#4-フェーズごとの受入基準) |
| [ ] | PR5-C・6・8・9／Gate D | 参加者への通知・同意、発話/資料の外部送信許可と解除、停止後の取得/送信停止、保持/破棄、ログへの本文/秘密情報非出力を確認 | [詳細計画](docs/meeting-copilot-plan.md)・[PR8検証](docs/validation/pr8-local-rag.md) |
| [ ] | 費用確認／別工程 | 実API評価・取消分を含む使用量と実請求額を照合。推定予算管理額を実請求額と区別する | [PR6モデル採用](docs/validation/pr6-model-adoption.md)・[小窓停止](docs/validation/pr6-final-ui.md) |

**開始条件・持ち越し:** 実音声再受入は利用者の読み上げ準備待ち。PR7の実API評価はケース・要求数・費用枠を具体化して承認後に実行する。PR8の承認枠32要求は使用済み。追加評価は別枠とする。PR6の52/52やPR8の16/16の合成試験を、実会議・60分耐久の合格に置き換えない。

**追加実装として別計画:** Sessionsの永続保存・一覧・再読込・削除。PR8のPDF/OCR、永続資料ライブラリ、資料を使う自動提案/要約は今回の受入対象外で、後続範囲として管理する。

## 更新ルール

1. **現在地・PR状態・次の作業・ブロッカー・品質ゲートのみを簡潔に管理。** 詳細手順やチェックリストは詳細計画・PRに記載する。
2. 状態: `TODO / READY / DOING / BLOCKED / REVIEW / DONE`。**DONEはPRマージと受入検証の証跡がある場合のみ**。未検証を完了扱いしない。
3. PR開始・レビュー・マージ・障害発生時に該当行だけ更新し、PRリンク・証跡を加える。進捗は`DONE数/12`で算出する。
4. 解決済みの課題と古い履歴は移動・削除する。**追記による肥大化を避ける。**

## 更新履歴（直近のみ）

- **2026-11-11:** PR8独立レビューの2指摘を承認後TDDで修正。342テスト・lint・Release、独立再レビュー合格。新ビルドのKeychain認証後、実API16/16ケース合格、計数込み32要求・推定US$0.04850325。提出準備中、実音声0、PR状態・Gateは維持。
- **2026-11-11:** 残タスクを実機受入・品質検証の一覧へ整理。確認済みのAI品質・停止操作・キーボード/VoiceOver基本操作を保持し、全状態・実会議・60分耐久との差を明記。古い「実装予定」「PR作成手続き中」を整理。PR8 #17のマージをmain `b7558ac`で確認し反映。PRの受入状態・品質ゲート・進捗2/12は変更なし。
