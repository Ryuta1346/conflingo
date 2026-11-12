> 2026-11-12 共通支援: Conference／Meetingの資料＋発話への質問、自動提案、手動Web調査、入力3構成をローカル実装。Web調査はユーザー指定によりLLM内蔵検索へ変更し、別の検索API/キーを削除。542件／96 suites中536件成功・実API評価6件skip、Lint217ファイル違反0、Debugテスト・Releaseビルド成功。実音声・実API品質と操作性の網羅受入は未実施。[計画](docs/design/shared-session-assistance-plan.md)・[検証記録](docs/validation/shared-session-assistance.md)。

# ConfLingo — 開発・進捗管理

- **追加実装（PR提出対象）:** Meetingの入力別オンデバイス翻訳、原文＋訳文、小窓・保存・Markdown対応。503テスト／89 suites成功、Lint198ファイル違反0、Debug/Release成功、日英・英日の実モデル応答、主要合成UI、ローカル反映を確認。実会議の品質・結合受入は継続。[検証記録](docs/validation/meeting-translation.md)。

> **本ファイルは常に簡潔明瞭に保つ。** 詳細な仕様・タスク説明・受入条件は [詳細計画](docs/meeting-copilot-plan.md) に集約し、ここに重複させない。

## 現在地

- **資料追加導線（PR #24マージ済み）:** ライブラリ直接登録、Meeting／Conference実行中の資料追加・選択、Conferenceの資料質問・用語適用・補正を実装。自動検証・主要fake UIを確認し、実音声・実モデル品質とUI網羅受入を残す。[結果](docs/validation/knowledge-entry-points.md)。
- 更新: **2026-11-12／`feature/shared-session-assistance`**。共通支援を実装・ローカル検証。以下のPRマージ・全体受入の記録は既存の履歴で、今回の変更はPR #27をベースとする独立ブランチへ分離。
- **実装:** PR0〜8、リポジトリ参照（PR #20）、Sessions（PR #21）、資料ライブラリ（PR #22）、LLM選択（PR #23）はマージ済み。PR9（結合・性能・安全性検証）は未着手。
- **受入:** **2/12区分がDONE**（PR1・2）。これは実装率ではなく、マージと受入証跡が揃った区分数。PR0はDOING、PR3〜8はREVIEWを維持する。Gate A/B/C/U/Dはいずれも全体合格前。
- **直近の検証記録:** 共通支援の542件／96 suites中536件成功・実API評価6件skip、Lint217ファイル違反0。[最新結果](docs/validation/shared-session-assistance.md)。以前の[Meeting翻訳検証](docs/validation/meeting-translation.md)と実機結果は保持。新規機能の実音声・実API品質とVoiceOver全経路は未確認。
- **品質確認済み:** PR6の合成回答52/52、PR7の固定16会議・22区間（複数回評価の合算）、PR8の合成引用16/16が合格。[PR6](docs/validation/pr6-model-adoption.md)・[PR7](docs/validation/pr7-summary-deadline.md)・[PR8](docs/validation/pr8-quality-acceptance.md)。実会議の結合受入とは区別する。
- **実機確認済み:** 短時間の2入力、新しい文での再開、通常Meetingの開始→一時停止→再開→終了、AIの実受信後停止/取消、主要キーボード経路・VoiceOver基本操作。マイク発話欠落の旧判定は一覧末尾の確認漏れであり撤回済み。[実入力](docs/validation/meeting-real-input-2026-11-11.md)・[UI](docs/validation/pr6-focus-stability.md)。
- **最新の追加機能:** Gemini・OpenAI・Claude・Kimi・DeepSeek・その他互換クラウド・PC内のQwen等の選択。APIキー分離、モデル一覧／手入力、ローカル接続を実装。ChatGPTログインは除外。
- **持ち越す検証:** Conference回帰 → Zoom/Meet/Teams別2入力受入 → 実音声とAI・候補管理・要約・資料検索・Markdown出力の結合受入。PR #20の品質評価・独立レビュー、UIの残る確認、60分耐久・性能・配布条件も継続する。
- **実施条件:** 実音声は試験環境と参加者同意を確認し、追加実APIは新たな送信範囲・要求上限の承認後に実施する。既存の使用済み評価枠は拡張しない。

## 次の作業の優先順（提案）

1. **既存機能と入力の受入:** Conference回帰（Gate A）→ Zoom/Meet/Teams別の2入力受入（Gate B）。
2. **会議全体の受入:** 実音声→AI回答・候補確認→資料参照→要約→Markdown出力・Sessions保存までを通して確認（Gate C）。リポジトリ参照と選択した実LLMの品質も個別に評価する。
3. **操作性とレビュー:** Sessions・資料ライブラリ・LLM設定を含む狭幅・拡大文字・キーボード・VoiceOver、未確認の画面状態、残る独立レビューを完了（Gate U）。実音声待ちの間にも進められる。
4. **実用判定:** 60分耐久・遅延・メモリ・障害復旧・送信停止・配布署名を確認し、費用照合と利用案内を整理（PR9／Gate D）。

新機能を優先する場合の既存候補は**PDF/OCR**。専門プリセット（Engineering / Sales）や保存記録の編集・AI再生成・自動保存・クラウド同期等は、後続の構想／初版対象外であり、今回の必須残タスクや承認済み実装として扱わない。

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

上表のPR0〜9は計画上の区分で、GitHubのPR番号とは別。追加のPR #20はPR6〜8の資料参照を拡張するもので、受入完了数の分母12は変更しない。

## 品質ゲート

| Gate | 合格の概要 | 状態 |
|---|---|---|
| A | 既存Conference機能の無回帰 | 一部確認済み・実機回帰が残る |
| B | Zoom/Meet/Teamsで2入力を識別・認識 | 短時間ローカル確認済み・アプリ別受入が残る |
| C | AI提案の根拠・誤確定防止・障害時縮退 | 合成品質確認済み・実音声結合が残る |
| U | 全体UI刷新・承認モック整合・操作性 | 主要操作確認済み・全画面/状態の受入が残る |
| D | 60分耐久・性能・プライバシー・実用判定 | 未検証 |

## 残る実機受入・品質検証

上からの実施順を目安とする。実音声待ちの間はレビュー・評価ケース準備を進める。詳細な手順・判定基準はリンク先と[品質ゲート](docs/meeting-copilot-plan.md#4-フェーズごとの受入基準)を参照。

| 完了 | 対象 | 残タスク・確認する結果 | 証跡・手順 |
|---|---|---|---|
| [x] | PR8／レビュー・修正マージ | 独立レビュー・MEDIUM 2件の修正検証・実API評価を完了。PR #19はmain `7efbd3f`でマージ確認済み。PR8全体の受入は継続 | [レビュー](docs/validation/pr8-independent-review.md)・[結果](docs/validation/pr8-quality-acceptance.md) |
| [x] | PR4（短時間ローカル） | 新しい文による再開と通常Meetingの開始・一時停止・再開・終了を確認。会議アプリ別・Gate B全体は次行で継続 | [実入力受入](docs/validation/meeting-real-input-2026-11-11.md)・[診断結果](docs/validation/microphone-diagnostics.md) |
| [ ] | 資料追加導線／新規受入 | 通常／語彙モードの日英精度・ライブ更新と2入力、実モデル質問・補正、狭幅・文字拡大・キーボード・VoiceOverと独立レビュー。ローカル実装・fake UI成功とは区別 | [検証記録](docs/validation/knowledge-entry-points.md) |
| [ ] | Sessions／UI受入 | 通常幅の主要操作と再起動後の復元は確認済み。狭幅・拡大文字・キーボード全経路・VoiceOverを確認。Windowメニューの操作ツールエラーで当該実操作は未完了 | [Sessions検証](docs/validation/sessions.md) |
| [ ] | 資料ライブラリ／UI・レビュー | L12の狭幅・最大文字・キーボード・VoiceOver全経路と独立レビュー。100項目・1,000ファイルの保存版読込／索引復元は測定済み、最大容量の測定は未実施 | [資料ライブラリ検証](docs/validation/knowledge-library.md) |
| [ ] | LLM選択／実モデル・UI | 新規クラウド各社・Qwenの実生成、構造化応答・回答/引用品質・速度を確認。モデル一覧から選択して保存する一連の操作、狭幅・VoiceOver全経路も未確認。ローカル模擬API成功と実モデル成功を区別 | [LLM選択検証](docs/validation/llm-selection.md) |
| [ ] | PR0・5-B／Gate A | Conferenceの実翻訳・文字起こし専用・字幕・停止/再開・辞書・言語切替・Clear・Markdown保存・権限拒否/復旧など、回帰表の未実施項目を実機確認 | [Conference回帰表](docs/validation/conference-baseline.md#conference回帰表) |
| [ ] | PR3・4／Gate B | Zoom/Meet/Teamsそれぞれで内部音声とマイクを識別。入力切替・機器/権限変更・切断/復旧・検証画面閉鎖時の停止、2系統STTの精度・時刻誤差・遅延・CPU/メモリを確認 | [2入力検証](docs/validation/dual-transcription.md)・[詳細計画](docs/meeting-copilot-plan.md) |
| [ ] | PR5-C・6・7・8／Gate C | 通常Meetingの開始・一時停止/再開・終了は実音声で確認済み。候補確認/却下・要約・Markdown保存との結合受入が残る。根拠表示・誤確定防止・提案連発防止、通信断時の音声継続とAIのみの縮退、資料検索との結合を確認 | [PR5-C](docs/validation/pr5-c-meeting.md)・[PR6](docs/validation/pr6-model-adoption.md)・[PR7](docs/validation/pr7-meeting-state.md)・[PR8](docs/validation/pr8-local-rag.md) |
| [x] | PR7（合成要約品質） | 要約60秒化後の3会議・8区間が合格。過去評価と合わせ固定16会議・22区間の品質条件を確認。過去2回のtimeoutは保持し、実音声・Gate Cは別途受入 | [修正・評価結果](docs/validation/pr7-summary-deadline.md) |
| [x] | PR8／合成引用品質 | 日英16/16ケースの意味・言語・引用が合格。命令・矛盾・不足資料を含む。Gate C全体とは区別 | [PR8品質評価](docs/validation/pr8-quality-acceptance.md) |
| [ ] | PR #20／追加機能の品質・レビュー | リポジトリを使う手動質問・自動提案・資料付き要約を実モデルで評価。自然言語からコードへの検索精度、補足と引用の正確さ、実音声との結合を確認。独立レビューと1,000ファイル級の原本走査→選択→索引化の時間・メモリ・操作性も未確認。ライブラリ保存版の索引復元の測定とは区別 | [リポジトリ資料化](docs/validation/repository-knowledge.md)・[自動提案](docs/validation/automatic-knowledge.md) |
| [ ] | PR5-A/B/C・6〜8／Gate U | 承認モックと実装画像の比較、未確認の画面/空・失敗状態、全操作の受入記録を完成。VoiceOver全経路、画面共有・複数画面・高コントラスト等を確認。PR5-Cの独立コード/画像レビューを実施 | [設計検証](docs/design/validation.md)・[PR5-B](docs/validation/pr5-b-conference.md)・[PR5-C](docs/validation/pr5-c-meeting.md)・[確認済み範囲](docs/validation/pr6-focus-stability.md) |
| [ ] | PR0・3・9／Gate B・D | ScreenCaptureKit/Process Tapの権限・Sandbox・配布条件と配布署名での動作を検証 | [詳細計画](docs/meeting-copilot-plan.md) |
| [ ] | PR9／Gate D | 60分実会議の耐久、クラッシュ・メモリ増加・処理滞留、入力切断/再接続、APIタイムアウト・連続開始/停止を確認。発話終了→AI完成のp95目標8秒とSTT遅延を実測し、質問検知率・誤提案率・根拠正確性を記録 | [Gate D・テスト計画](docs/meeting-copilot-plan.md#4-フェーズごとの受入基準) |
| [ ] | PR5-C・6・8・9／Gate D | 参加者への通知・同意、発話/資料の外部送信許可と解除、停止後の取得/送信停止、保持/破棄、ログへの本文/秘密情報非出力を確認 | [詳細計画](docs/meeting-copilot-plan.md)・[PR8検証](docs/validation/pr8-local-rag.md) |
| [ ] | 費用確認／別工程 | 実API評価・取消分を含む使用量と実請求額を照合。推定予算管理額を実請求額と区別する | [PR6モデル採用](docs/validation/pr6-model-adoption.md)・[小窓停止](docs/validation/pr6-final-ui.md) |
| [ ] | 利用案内・資料整合 | 日本語/英語READMEはSessionsとMeetingの現行仕様へ更新済み。他の言語版と利用ガイドを確認。詳細計画・過去の検証記録に残る当時の未検証記述と、現在の残件を区別する | [日本語README](README.ja.md#制限事項)・[英語README](README.md)・[詳細計画](docs/meeting-copilot-plan.md) |

**開始条件・持ち越し:** 短時間実入力と通常Meeting操作を確認し、両入力・素材再生を停止済み。今回追加API0・本文保存0。PR7合成要約品質は3回の評価を通じ確認済み（合計54要求）。旧2回の不明使用量予約US$0.084528を保持し、累計推定管理額US$0.25228725。追加実APIは自動実行しない。#19の変更はmainへマージ済み。PR8の32要求は使用済み。合成試験を実会議・60分耐久・Gate Cの合格に置き換えない。

**後続の未実装機能:** PDF/OCR。永続資料ライブラリはローカル実装・主要検証済み。Sessions初版は読み取り専用で、保存記録の編集・AI再生成・自動保存・クラウド同期は対象外。

**PR #20の到達点:** ローカルのコード・テスト・文書を選択して取り込み、手動質問・自動提案・終了後要約で参照できる。引用にはパス・行・内容ハッシュ・snapshot IDを保持。自動提案と要約の資料許可は独立し、初期オフ。実装と無通信UIは確認済みだが、既存PR6/7/8の実API合格を追加機能の品質保証には流用しない。

## 更新ルール

1. **現在地・PR状態・次の作業・ブロッカー・品質ゲートのみを簡潔に管理。** 詳細手順やチェックリストは詳細計画・PRに記載する。
2. 状態: `TODO / READY / DOING / BLOCKED / REVIEW / DONE`。**DONEはPRマージと受入検証の証跡がある場合のみ**。未検証を完了扱いしない。
3. PR開始・レビュー・マージ・障害発生時に該当行だけ更新し、PRリンク・証跡を加える。進捗は`DONE数/12`で算出する。
4. 解決済みの課題と古い履歴は移動・削除する。**追記による肥大化を避ける。**

## 更新履歴（直近のみ）

- **2026-11-12（資料追加導線）:** 承認済みの事前登録・会議中追加・Conference支援をローカル実装。自動検証・主要fake UIを確認。実音声・実モデル品質・UI網羅は継続。レビュー提出版・未マージ。[結果](docs/validation/knowledge-entry-points.md)。
- **2026-11-12（現状整理）:** ローカルmain `56d7a81`でPR #21〜23のマージを確認。最新テスト件数を467へ修正し、資料ライブラリ・LLM選択の未検証項目と作業優先順を明記。文書整理のみ。受入完了数2/12と各Gateの未完了を維持。
- **2026-11-11（Sessions）:** 計画承認後にローカル実装、423テスト・lint・Debug/Release成功。主要無通信UIを確認し、残るS12を明記。ユーザー依頼でコミット・pushし、[Draft PR #21](https://github.com/Ryuta1346/conflingo/pull/21)を作成。[結果](docs/validation/sessions.md)。
- **2026-11-11（PR #20マージ後の整理）:** main `294bd0c`と検証記録151ファイルのハッシュ一致を確認。追加機能を実装済みへ更新し、実モデル品質・独立レビュー・大規模性能・README整合を残件に明記。受入完了数2/12と各Gate状態は維持。文書整理のみで追加API・音声取得は0。
- **2026-11-11（実音声）:** 診断2試行で日本語4文・英語9文を確認。欠落の旧判定を撤回。新しい文での再開と通常Meetingの開始→一時停止→再開→終了も確認。追加API0。[診断](docs/validation/microphone-diagnostics.md)・[Meeting受入](docs/validation/meeting-real-input-2026-11-11.md)。
- **2026-11-11（品質）:** PR8合成引用16/16合格。PR7要約期限を60秒へ変更し、複数回評価を通じ固定16会議・22区間の品質条件を確認。過去timeoutと使用量予約は保持。[PR8結果](docs/validation/pr8-quality-acceptance.md)・[PR7結果](docs/validation/pr7-summary-deadline.md)。
