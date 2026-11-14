> 提出対象: 第1段階 `a36bac5`、構成ルート分離 `50e479c`。2026-11-14のユーザー「コミットand PR作成」により、検証記録と合わせてPR提出する。マージ・実機受入は未完了。

> 2026-11-14 第2段階・構成ルート分離: `AppComposition`へサービス生成を集約し、主画面・小窓・検証画面で共有。通常並列の全688件中681成功・実API7skip、Lint259ファイル違反0、arm64/x86_64 Release成功。独立レビュー2観点の指摘0件。実装コミット済み・未マージ。[計画](docs/design/app-composition-plan.md)・[結果](docs/validation/app-composition-2026-11-14.md)。

> 2026-11-14 第1段階完了: レビュー4指摘（SSE上限・UI待機・用語更新競合・資料許可解除）、LLM失敗診断、開発画面Debug限定を承認後に実装。通常並列の全682件中675成功・実API7skip、Lint257ファイル違反0、arm64/x86_64 Release成功。修正後の独立レビュー指摘0件。実装コミット済み・未マージ。[結果](docs/validation/remaining-implementation-2026-11-14.md)・[計画](docs/design/remaining-work-plan.md)。構造整理と実機受入は継続。

> 2026-11-14 R6-4: Keychainの全操作の排他制御と認証UI設定の復元失敗処理を実装。全667件中660成功・実API7skip（最終はXcode並列テスト無効）、Lint251ファイル違反0、Release成功。ローカル実装・自動検証済み、[PR #40](https://github.com/Ryuta1346/conflingo/pull/40)でローカルmain `33c8ae6`へマージ済み。独立レビュー・実機受入は継続。[結果](docs/validation/r6-keychain-interaction.md)・[計画](docs/design/r6-keychain-interaction-plan.md)。

> 2026-11-14 R6-2/3: Meeting翻訳の言語ペア別セッション再利用と採用用語の原文表記保持を実装。全656件中649成功・実API7skip、Lint249ファイル違反0、Release成功。ローカル実装・自動検証済み、[PR #39](https://github.com/Ryuta1346/conflingo/pull/39)でローカルmain `18d0fcb`へマージ済み。独立レビュー・実モデル品質・実音声受入は継続。[結果](docs/validation/r6-meeting-translation.md)・[計画](docs/design/r6-meeting-translation-plan.md)。

> 2026-11-14 R6-1: Conferenceで同文の別発話が欠落する問題を修正。全640件中633成功・実API7skip、Lint245ファイル違反0、Release成功。ローカル実装・検証済み、[PR #38](https://github.com/Ryuta1346/conflingo/pull/38)はローカルmain `b526a1b`へマージ済み。独立レビュー・実音声受入は未確認。R5-3はPR #37でmain `dab817e`へマージ済み。R5のレビュー・実機受入とR6の残項目は継続。[結果](docs/validation/r6-1-repeated-final.md)・[計画](docs/design/r6-1-repeated-final-plan.md)。

> 2026-11-13 R2: 受信全体の予算を2 MiBへ分離し、長文のSSE分割による拒否を修正。全599件中592成功・実API7skip、Lint233ファイル違反0、Release成功。Gemini実測4/4要求は成功（旧上限超過なし）。PR #33はmain `0314aed`へマージ済み。他社実測・独立レビューは未完了。[結果](docs/validation/r2-response-size-investigation.md)・[計画](docs/design/r2-response-limit-plan.md)。

> 2026-11-13 R1-3レビュー追補: 検索ツール前後の段落を保持するよう修正。全583件中577成功・実API評価6skip、Lint228ファイル違反0。[追補](docs/design/r1-3-claude-research-text-plan.md)。

> 2026-11-13 R1-3: Claudeの複数textブロック間に余分な段落が入る問題を修正。全580件中574成功・実API評価6skip、Lint228ファイル違反0、Release成功。[結果](docs/design/r1-3-claude-research-text-plan.md)。R1-2もローカル検証済みで、両修正を[Draft PR #32](https://github.com/Ryuta1346/conflingo/pull/32)へ提出済み。R1-2の実モデル再試行は未受入。[R1-2の結果](docs/design/r1-2-translation-preparation-plan.md)。R1-1はmain `ab2c4ae`で[PR #31](https://github.com/Ryuta1346/conflingo/pull/31)のマージを確認。実機の機器切替・Gate Bは未受入。[R1-1の結果](docs/design/r1-1-microphone-configuration-plan.md)。

> 2026-11-13 アーキテクチャ／コードレビュー: main `f43ee38`の全体を静的に確認（レビュー時のビルド・テストは未実行）。高3・中5・低5件と構造課題7件を指摘し、ユーザー承認により[レビュー対応](#レビュー対応2026-11-13承認)のR1→R4の順で進める。R1-1〜3はマージ済み（残る実機受入は継続）、R2・R3もマージ済み、R4もマージ済み（実機受入・独立レビュー確認は継続）。

> 2026-11-13 レビュー指摘2件を修正: 英語検索の大小文字・アポストロフィと、狭幅の根拠リンクからの発話表示を回帰確認。全558件中552成功・実API評価6skip、Lint・Release成功。[詳細](docs/design/review-followup-fix-plan.md)。

> 2026-11-13 実用確認: main `0d31dd8`上で狭幅字幕・ナビゲーションと日本語検索「月額」の修正を完了。全554件中548成功・実API評価6skip・失敗0、Lint220ファイル違反0、Release成功。合成UIで字幕・保存/終了操作・キーボード移動、および`月額`検索→引用本文を確認。資料質問→引用→保存→再起動→Markdown、署名済みSandboxでの資料取込・再利用も確認済み。実音声・実API・耐久・VoiceOver全経路などを残すためGate全体は未合格。[今回の結果](docs/validation/practical-acceptance-2026-11-12.md)・[検索修正計画](docs/design/japanese-search-fix-plan.md)。

> 2026-11-12 共通支援: Conference／Meetingの資料＋発話への質問、自動提案、手動Web調査、入力3構成を実装。Web調査はLLM内蔵検索を使い、別の検索APIキーは不要。PR #28までローカルmainへマージ済み。[計画](docs/design/shared-session-assistance-plan.md)・[検証記録](docs/validation/shared-session-assistance.md)。

# ConfLingo — 開発・進捗管理

- **追加実装（PR提出対象）:** Meetingの入力別オンデバイス翻訳、原文＋訳文、小窓・保存・Markdown対応。503テスト／89 suites成功、Lint198ファイル違反0、Debug/Release成功、日英・英日の実モデル応答、主要合成UI、ローカル反映を確認。実会議の品質・結合受入は継続。[検証記録](docs/validation/meeting-translation.md)。

> **本ファイルは常に簡潔明瞭に保つ。** 詳細な仕様・タスク説明・受入条件は [詳細計画](docs/meeting-copilot-plan.md) に集約し、ここに重複させない。

## 現在地

- **資料追加導線（PR #24マージ済み）:** ライブラリ直接登録、Meeting／Conference実行中の資料追加・選択、Conferenceの資料質問・用語適用・補正を実装。自動検証・主要fake UIを確認し、実音声・実モデル品質とUI網羅受入を残す。[結果](docs/validation/knowledge-entry-points.md)。
- 更新: **2026-11-14／main `33c8ae6`を基点とする`fix/review-followups-app-composition`**。R1-1〜3・R2・R3・R4・R5-1/2/3・R6-1/2/3/4はマージ済み。独立レビュー4指摘の修正とR6の診断ログ・開発画面Debug限定はローカル実装・検証済み、修正後レビュー指摘0件。[結果](docs/validation/remaining-implementation-2026-11-14.md)。実モデル・実機受入と品質ゲートは継続。
- **実装:** PR0〜8、リポジトリ参照（PR #20）、Sessions（PR #21）、資料ライブラリ（PR #22）、LLM選択（PR #23）はマージ済み。PR9（結合・性能・安全性検証）は未着手。
- **受入:** **2/12区分がDONE**（PR1・2）。これは実装率ではなく、マージと受入証跡が揃った区分数。PR0はDOING、PR3〜8はREVIEWを維持する。Gate A/B/C/U/Dはいずれも全体合格前。
- **直近の検証記録:** 構成ルート分離後、通常並列の全688件中681成功・実API7skip・失敗0、Lint259ファイル違反0、arm64/x86_64 Release成功。[結果](docs/validation/app-composition-2026-11-14.md)。前段階の字幕AX空状態・翻訳待機不足の修正も全体回帰に含む。
- **品質確認済み:** PR6の合成回答52/52、PR7の固定16会議・22区間（複数回評価の合算）、PR8の合成引用16/16が合格。[PR6](docs/validation/pr6-model-adoption.md)・[PR7](docs/validation/pr7-summary-deadline.md)・[PR8](docs/validation/pr8-quality-acceptance.md)。実会議の結合受入とは区別する。
- **実機確認済み:** 短時間の2入力、新しい文での再開、通常Meetingの開始→一時停止→再開→終了、AIの実受信後停止/取消、主要キーボード経路・VoiceOver基本操作。マイク発話欠落の旧判定は一覧末尾の確認漏れであり撤回済み。[実入力](docs/validation/meeting-real-input-2026-11-11.md)・[UI](docs/validation/pr6-focus-stability.md)。
- **最新の追加機能:** Gemini・OpenAI・Claude・Kimi・DeepSeek・その他互換クラウド・PC内のQwen等の選択。APIキー分離、モデル一覧／手入力、ローカル接続を実装。ChatGPTログインは除外。
- **持ち越す検証:** Conference回帰 → Zoom/Meet/Teams別2入力受入 → 実音声とAI・候補管理・要約・資料検索・Markdown出力の結合受入。PR #20の品質評価・独立レビュー、UIの残る確認、60分耐久・性能・配布条件も継続する。
- **実施条件:** 実音声は試験環境と参加者同意を確認し、追加実APIは新たな送信範囲・要求上限の承認後に実施する。既存の使用済み評価枠は拡張しない。

## 次の作業の優先順（提案）

**先行:** PR #40までマージ済み。独立レビュー4指摘とLLM失敗診断・開発画面Debug限定は[ローカル実装・検証・レビュー完了](docs/validation/remaining-implementation-2026-11-14.md)、実装コミット済み・未マージ。構成ルート分離は[ローカル実装・自動検証・独立レビュー完了](docs/validation/app-composition-2026-11-14.md)。次の実装候補は共通支援/通知整理、LLM分岐/SSE集約、CIで、[計画第2段階](docs/design/remaining-work-plan.md)の具体化から進める。以下の実音声・実モデル受入は継続。

1. **既存機能と入力の受入:** Conference回帰（Gate A）→ Zoom/Meet/Teams別の2入力受入（Gate B）。
2. **会議全体の受入:** 実音声→AI回答・候補確認→資料参照→要約→Markdown出力・Sessions保存までを通して確認（Gate C）。リポジトリ参照と選択した実LLMの品質も個別に評価する。
3. **操作性とレビュー:** Sessions・資料ライブラリ・LLM設定を含む狭幅・拡大文字・キーボード・VoiceOver、未確認の画面状態、残る独立レビューを完了（Gate U）。実音声待ちの間にも進められる。
4. **実用判定:** 60分耐久・遅延・メモリ・障害復旧・送信停止・配布署名を確認し、費用照合と利用案内を整理（PR9／Gate D）。

新機能を優先する場合の既存候補は**PDF/OCR**。専門プリセット（Engineering / Sales）や保存記録の編集・AI再生成・自動保存・クラウド同期等は、後続の構想／初版対象外であり、今回の必須残タスクや承認済み実装として扱わない。

## レビュー対応（2026-11-13承認）

上から順に実施する。各項目は着手時に修正計画（`docs/design/`）を作り、回帰テスト追加→修正→全テスト・Lint・Releaseビルドで確認する。指摘は静的レビューによるもので、再現確認は各項目の最初に行う。

| 順 | 対象 | 内容・完了条件 | 状態 |
|---|---|---|---|
| R1-1 | マイクの機器・構成変更 | 構成変更を検知し、入力停止・エラー表示・再開始案内へ接続。合成通知・Conference／Meeting結合・全回帰成功。PRマージ済み、実機の抜き差し等は未受入。[結果](docs/design/r1-1-microphone-configuration-plan.md)・[PR #31](https://github.com/Ryuta1346/conflingo/pull/31) | REVIEW |
| R1-2 | 翻訳モデル準備失敗の表示 | 準備失敗の通知・訳文表示・再試行を実装。文字起こし継続、未翻訳分の再投入、取消・旧実行の無視を自動検証。実モデル失敗→再試行は未受入。[PR #32](https://github.com/Ryuta1346/conflingo/pull/32)マージ済み。[結果](docs/design/r1-2-translation-preparation-plan.md) | REVIEW |
| R1-3 | ClaudeのWeb調査本文 | 複数textブロックの空白・改行・引用位置を保って連結するよう修正。日英・絵文字・重複出典・保存/Markdownを合成応答で検証済み。[PR #32](https://github.com/Ryuta1346/conflingo/pull/32)マージ済み。[結果](docs/design/r1-3-claude-research-text-plan.md) | REVIEW |
| R2 | 受信上限の分離 | 総受信2 MiBはPR #33マージ済み。独立レビューで見つかったSSE結合改行のイベント予算算入漏れもローカル修正・境界テスト・レビュー完了、実装コミット済み。他社実測は未完了。[修正結果](docs/validation/remaining-implementation-2026-11-14.md) | REVIEW |
| R3 | 保存形式の固定 | 固定JSON6種でv1の読込・保存契約を検証。全回帰・Lint・Release成功、非互換変更の検出を確認。R4の前提。[PR #34](https://github.com/Ryuta1346/conflingo/pull/34)はmain `8fd8144`へマージ済み。レビュー完了はユーザー確認済み。[結果](docs/validation/r3-persistence-golden.md)・[計画](docs/design/r3-persistence-golden-plan.md) | DONE |
| R4 | 文字起こし経路の一本化 | `DualTranscriptionController`統合はPR #35でマージ済み。独立静的レビューの製品指摘0件。実機Gate Aは未完了。[結果](docs/validation/r4-transcription-unification.md)・[レビュー](docs/validation/remaining-review-2026-11-14.md) | REVIEW |
| R5 | 中優先の残り | 最大100区間要約・ライブ表示・検索語選択はPR #36/#37でマージ済み。UIテストの翻訳完了待機不足と共有AX設定の競合をローカル修正。通常並列全体成功、修正後レビュー指摘0件、実装コミット済み。実モデル品質・長時間耐久は継続。[結果](docs/validation/remaining-implementation-2026-11-14.md) | REVIEW |
| R6 | 低優先・構造の残り | R6-1〜4はPR #38〜40でマージ済み、独立レビュー指摘0件。LLM失敗診断・検証画面Debug限定もローカル実装・検証・レビュー完了、実装コミット済み。README構成図は更新済み。構成ルート分離も[ローカル実装・自動検証・独立レビュー完了](docs/validation/app-composition-2026-11-14.md)。残る構造課題は共通支援モジュール化、通知統一、LLM分岐/SSE集約、CI。実モデル・Keychain実認証・実音声は未受入。[結果](docs/validation/remaining-implementation-2026-11-14.md) | DOING |

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
| [ ] | 資料追加導線／新規受入 | 用語ライブ更新競合・資料取り外し後の許可解除漏れをローカル修正し、自動検証・独立レビュー完了、実装コミット済み。日英精度・2入力・実モデル質問/補正・UI全経路は継続 | [検証記録](docs/validation/knowledge-entry-points.md)・[修正結果](docs/validation/remaining-implementation-2026-11-14.md) |
| [ ] | Sessions／UI受入 | 通常幅の主要操作と再起動後の復元は確認済み。狭幅・拡大文字・キーボード全経路・VoiceOverを確認。Windowメニューの操作ツールエラーで当該実操作は未完了 | [Sessions検証](docs/validation/sessions.md) |
| [ ] | 資料ライブラリ／UI・レビュー | L12の狭幅・最大文字・キーボード・VoiceOver全経路。独立レビューは実施済み（資料導線の2指摘は修正済み、実装コミット済み）。100項目・1,000ファイルの保存版読込／索引復元は測定済み、最大容量の測定は未実施 | [資料ライブラリ検証](docs/validation/knowledge-library.md) |
| [ ] | LLM選択／実モデル・UI | 新規クラウド各社・Qwenの実生成、構造化応答・回答/引用品質・速度を確認。モデル一覧から選択して保存する一連の操作、狭幅・VoiceOver全経路も未確認。ローカル模擬API成功と実モデル成功を区別 | [LLM選択検証](docs/validation/llm-selection.md) |
| [ ] | PR0・5-B／Gate A | Conferenceの実翻訳・文字起こし専用・字幕・停止/再開・辞書・言語切替・Clear・Markdown保存・権限拒否/復旧など、回帰表の未実施項目を実機確認 | [Conference回帰表](docs/validation/conference-baseline.md#conference回帰表) |
| [ ] | PR3・4／Gate B | Zoom/Meet/Teamsそれぞれで内部音声とマイクを識別。入力切替・機器/権限変更・切断/復旧・検証画面閉鎖時の停止、2系統STTの精度・時刻誤差・遅延・CPU/メモリを確認 | [2入力検証](docs/validation/dual-transcription.md)・[詳細計画](docs/meeting-copilot-plan.md) |
| [ ] | PR5-C・6・7・8／Gate C | 通常Meetingの開始・一時停止/再開・終了は実音声で確認済み。候補確認/却下・要約・Markdown保存との結合受入が残る。根拠表示・誤確定防止・提案連発防止、通信断時の音声継続とAIのみの縮退、資料検索との結合を確認 | [PR5-C](docs/validation/pr5-c-meeting.md)・[PR6](docs/validation/pr6-model-adoption.md)・[PR7](docs/validation/pr7-meeting-state.md)・[PR8](docs/validation/pr8-local-rag.md) |
| [x] | PR7（合成要約品質） | 要約60秒化後の3会議・8区間が合格。過去評価と合わせ固定16会議・22区間の品質条件を確認。過去2回のtimeoutは保持し、実音声・Gate Cは別途受入 | [修正・評価結果](docs/validation/pr7-summary-deadline.md) |
| [x] | PR8／合成引用品質 | 日英16/16ケースの意味・言語・引用が合格。命令・矛盾・不足資料を含む。Gate C全体とは区別 | [PR8品質評価](docs/validation/pr8-quality-acceptance.md) |
| [ ] | PR #20／追加機能の品質・レビュー | リポジトリを使う手動質問・自動提案・資料付き要約を実モデルで評価。自然言語からコードへの検索精度、補足と引用の正確さ、実音声との結合を確認。独立レビューは実施済み・指摘0件。1,000ファイル級の原本走査→選択→索引化の時間・メモリ・操作性も未確認。ライブラリ保存版の索引復元の測定とは区別 | [リポジトリ資料化](docs/validation/repository-knowledge.md)・[自動提案](docs/validation/automatic-knowledge.md) |
| [ ] | PR5-A/B/C・6〜8／Gate U | 承認モックと実装画像の比較、未確認の画面/空・失敗状態、全操作の受入記録を完成。VoiceOver全経路、画面共有・複数画面・高コントラスト等を確認。PR5-Cの独立コード/履歴画像レビューは完了。現行版の画像・実操作受入は継続 | [設計検証](docs/design/validation.md)・[PR5-B](docs/validation/pr5-b-conference.md)・[PR5-C](docs/validation/pr5-c-meeting.md)・[確認済み範囲](docs/validation/pr6-focus-stability.md) |
| [ ] | PR0・3・9／Gate B・D | ScreenCaptureKit/Process Tapの権限・Sandbox・配布条件と配布署名での動作を検証 | [詳細計画](docs/meeting-copilot-plan.md) |
| [ ] | PR9／Gate D | 60分実会議の耐久、クラッシュ・メモリ増加・処理滞留、入力切断/再接続、APIタイムアウト・連続開始/停止を確認。発話終了→AI完成のp95目標8秒とSTT遅延を実測し、質問検知率・誤提案率・根拠正確性を記録 | [Gate D・テスト計画](docs/meeting-copilot-plan.md#4-フェーズごとの受入基準) |
| [ ] | PR5-C・6・8・9／Gate D | 参加者への通知・同意、発話/資料の外部送信許可と解除、停止後の取得/送信停止、保持/破棄、ログへの本文/秘密情報非出力を確認 | [詳細計画](docs/meeting-copilot-plan.md)・[PR8検証](docs/validation/pr8-local-rag.md) |
| [ ] | 費用確認／別工程 | 実API評価・取消分を含む使用量と実請求額を照合。推定予算管理額を実請求額と区別する | [PR6モデル採用](docs/validation/pr6-model-adoption.md)・[小窓停止](docs/validation/pr6-final-ui.md) |
| [x] | 利用案内・資料整合（今回範囲） | README5言語の現行機能・構成、英語要約上限、日英の診断ログ案内を更新。実装結果・未受入を進捗資料へ反映。今後の構造/仕様変更時は再整合する | [更新記録](docs/validation/remaining-review-2026-11-14.md)・[修正結果](docs/validation/remaining-implementation-2026-11-14.md) |

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
