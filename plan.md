# ConfLingo — 開発・進捗管理

> **本ファイルは常に簡潔明瞭に保つ。** 詳細な仕様・タスク説明・受入条件は [詳細計画](docs/meeting-copilot-plan.md) に集約し、ここに重複させない。

## 現在地

- 更新: **2026-11-10**／状態: **PR0実機確認持ち越し／PR1・PR2完了／PR3〜PR5マージ済み、残る実機受入待ち／PR6言語設定・3.8 Flash採用済み、品質52/52合格、残るUI等の受入待ち**／PR7実装・非録音検証済み、残る受入待ち／進捗: **2/12**
- **持ち越し:** PR0の実翻訳・保存操作、PR3の会議アプリ別内部音声・配布条件。短時間実入力試験は再開済み。
- **次の作業:** ユーザー指示でPR7の候補確認・手動AI要約・Markdown出力を実装し、310テスト・非録音UIを確認。[検証記録](docs/validation/pr7-meeting-state.md)。次は差分レビューと実API要約品質の受入準備。Sessionsは後続。修正版の短時間実音声受入は[発話できる時まで保留](docs/validation/real-audio-fixed-reacceptance.md)、両入力停止済み。通常Meeting・翻訳/保存の受入も残す。60分耐久はPR9、実請求額照合は別工程。API追加0、旧枠11/12・直近枠60/60のまま。
- 概算: PoC 2〜3週間、実用MVP 6〜10週間（着手日・期限は未設定）
- **確認済み:** 3.8 Flash/medium・8192へ変更し、290テスト/43 suites・Debug/Release・lint109ファイル違反0。新ビルド自身のKeychain、言語保存/再起動復元、主画面AI停止・一時停止・会議終了の実受信後取消、再開後回答を確認。
- **追加品質確認:** 製品と同じ設定で52/52ケース合格。指定言語一致・無効ID/通信失敗なし。平均完了5.80秒、p95 10.43秒、最大21.73秒。品質52＋UI8要求で推定予算管理額$0.3084。
- **未完了:** 長時間・実請求額と実機全状態の受入。キーボードの主要経路・反復、VoiceOverの基本動作は確認済み（範囲・証跡の制約は検証記録を参照）。短時間の実音声2入力STTは一部確認済み。停止後表示は修正・合成回帰済みで、修正版の実音声再確認は未実施。実翻訳・通常Meetingの開始後・会議アプリ別の受入は未検証。

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
| PR6 | AI会話理解・根拠付き回答 | PR1/PR4、実機受入持ち越し承認済み | **REVIEW** | [PR #12 (Merged)](https://github.com/Ryuta1346/conflingo/pull/12)・[品質改善 #13 (Merged)](https://github.com/Ryuta1346/conflingo/pull/13)・[修正・受入 #14 (Merged)](https://github.com/Ryuta1346/conflingo/pull/14)・[最新品質評価](docs/validation/pr6-answer-language-model.md) |
| PR7 | 決定・アクション候補管理 | PR6（実機受入持ち越し承認済み） | **REVIEW** | [計画](docs/design/pr7-implementation-plan.md)・[310テスト／非録音UI検証](docs/validation/pr7-meeting-state.md)・`feature/meeting-state` |
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

- **PR0:** 短時間2入力試験は再開済み。Conference実翻訳・保存は未実施。起動・専用モード切替は確認済み。Gate Aは未検証を維持。[検証記録](docs/validation/conference-baseline.md)
- **PR3:** PR #8マージ（`6b34a45`）・固定差分の独立コードレビュー完了、追加指摘なし。検証コピーの権限操作とローカル素材の内部音声取得は確認済み。Zoom/Meet/Teams別実音声・配布条件は未検証。
- **PR0/3:** ScreenCaptureKitとProcess Tap、権限・Sandbox・配布の検証
- **PR4:** [PR #9](https://github.com/Ryuta1346/conflingo/pull/9)マージ済み（`c714f9c`）、実装・自動検証・コードレビュー完了。2系統SpeechAnalyzerの性能・精度・時刻誤差・遅延は未検証。新検証画面の閉鎖確認はUI取得タイムアウトで持ち越し。
- **PR5-A:** 9画面・状態別モックと設計資料を作成、ブラウザ検証済み。主要4画面の画像提示後に方向性承認済み。PR #10でマージ済み。個別状態・全操作の受入記録は未完了のためREVIEWを維持。[検証記録](docs/design/validation.md)
- **PR5-C:** 独立コードレビュー・実音声受入・VoiceOver/画面共有等は未実施。AI通信はPR6で実装。候補確定・Meeting保存は後続PR。
- **PR6:** Gemini BYOKの個人PoC。回答言語設定と3.8 Flash/medium・8192を実装（未コミット）。[製品回帰52/52合格・停止3操作確認](docs/validation/pr6-model-adoption.md)。[小窓の実受信中停止をAXPressで確認](docs/validation/pr6-final-ui.md)。検証コピーで主要キー経路を確認、反復確認・VoiceOver基本動作の利用者確認まで完了。実機全状態・実音声等は残りREVIEW。
- **PR5-C/6/8:** 会議参加者への通知・同意、資料・発話の外部送信制御

## 更新ルール

1. **現在地・PR状態・次の作業・ブロッカー・品質ゲートのみを簡潔に管理。** 詳細手順やチェックリストは詳細計画・PRに記載する。
2. 状態: `TODO / READY / DOING / BLOCKED / REVIEW / DONE`。**DONEはPRマージと受入検証の証跡がある場合のみ**。未検証を完了扱いしない。
3. PR開始・レビュー・マージ・障害発生時に該当行だけ更新し、PRリンク・証跡を加える。進捗は`DONE数/12`で算出する。
4. 解決済みの課題と古い履歴は移動・削除する。**追記による肥大化を避ける。**

## 更新履歴（直近のみ）

- **2026-11-10:** 旧停止UIの残枠を1件使用し、新ビルド小窓の受信中停止・取消・部分回答保持をAXPressで確認。旧枠11/12、追加の予算管理額$0.03875。キーボード網羅・VoiceOverは操作取得が不安定で未確認。OS設定は復元、製品変更なし。

- **2026-11-10:** 言語設定を実装、290テスト・build/lint・非録音UI成功。承認済み72要求の比較でminimal 19/24、high 22/24、3.8/medium 24/24。製品採用と全体回帰が残るためREVIEW。
- **2026-11-10:** 継続修正後287テスト・build/lint成功、追加62要求完了。48合格・9不合格・5要確認。言語不一致4件と因果の補完等が残るため、プロンプト追記から要求言語・根拠契約の設計へ方針を更新。REVIEW継続。
- **2026-11-10:** 承認済みの回答範囲・期限改善をTDDで実装。286テスト・build/lint成功、68要求完了。候補60件は54合格・4不合格・2要確認、PR6/Gate C未合格を維持。
- **2026-11-10:** 追加12要求の承認を受け10要求を実行。一時停止・会議終了の実受信後クリック、取消・中断保持と再開後の回答完了に成功。無通信で主要キーボード経路と狭幅/48ptを確認。品質4件は意味2件合格・2件要確認、言語は一致。VoiceOver等は未完了、REVIEW継続。
- **2026-11-10:** ユーザーの認証完了・再開指示後、最新ビルド自身の対話読出し1件、続く非対話読出し・製品登録状態2件に成功。通常起動の設定シート・設定ページでも登録済みを確認。Keychain受入を完了へ更新、追加API0件、PR6 REVIEW継続。
- **2026-11-10:** 追加認証をスキップし、許可済みビルドで根拠36要求（35件合格・1件要確認）と停止UI8要求を実施。既存プレビュー終了は「OK」で承認。主画面・小窓は受信後クリックから取消・中断保持まで合格。一時停止/終了は回答完了後のクリックで未確認、日本語質問への英語回答1件を記録。計44/44要求、検証ホスト終了、REVIEW継続。
- **2026-11-10:** #14マージをローカルmain `f2baff9`で確認。通常起動の準備・設定遷移、Tab/Space/Esc、既存プレビューの根拠強調と小窓往復を追加確認。通常起動ビルドのキー読出しエラーとVoiceOver操作ツールのタイムアウトを記録。実API追加0件、REVIEW継続。
- **2026-11-10:** 品質2点修正、280テスト・Debug/Release・lint・合成52要求に合格。続く6要求で修正後UI/Keychain、実受信後の公開停止操作3経路・再開を確認。通常起動全体等の残項目がありREVIEW。
- **2026-11-10:** Keychain読出し・キー保存形式を解消。実アプリの合成28件が構造/分類/根拠IDに合格。UI最大8回の開始で回答・根拠・停止/再開・終了を確認。混在言語の品質と通信中停止が残るためREVIEW。
- **2026-11-09:** PR #13マージ（`d0b4379`）を確認。残る受入として合成24要求・実通信取消3要求と関連26テストを検証。Debug検証モード・読出し停止を修正、275テストとbuild/lint成功。新ビルドのKeychainアクセス許可が未完了のためREVIEWを維持。

- **2026-11-09:** PR6マージ（`85253db`）後の日程レビュー修正を実施。269テスト・Debug/Release・lint成功。追加92要求の最終版で合成28件合格。通常アプリ等の受入が残るためREVIEWを維持。
- **2026-11-08:** PR4（#9、`c714f9c`）、PR5-A/B（#10、`c34ddd1`）、PR5-C（#11、`e167765`）のマージをローカルmainで確認。PR5-C修正後236テスト・build/lint成功の既存記録あり。PR6は計画承認後に実装し、263テスト・Debug/Release・lint成功、モックUI操作を確認。実音声受入とGate A/B/Uは未完了を維持。
- **2026-11-07:** [詳細計画 v1.1](docs/meeting-copilot-plan.md)確定、UI刷新をPR5-A/B/Cに分割。
