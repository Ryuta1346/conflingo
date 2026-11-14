# R6-2/3 — Meeting翻訳のセッション再利用と用語保護

> 2026-11-14提出追記: ユーザー「コミットしてPR作成」に基づき、実装 `dee4d81`を[Draft PR #39](https://github.com/Ryuta1346/conflingo/pull/39)へ提出済み。未マージ・独立レビュー待ち。以下の未コミット・未PRはローカル検証完了時点の記録。

2026-11-14 / 調査基点: ローカルmain `b526a1b`（PR #38マージ済み）。
状態: **2026-11-14、ユーザー「進めて」によりR6-2/3の実装を承認済み。ローカル実装・自動検証済み。未コミット・未PR**。
正本: `~/.coding-agents/docs/conflingo/main/r6-meeting-translation-plan.md`。
Planモードへの切替機能は利用できないため、この文書で実装前の計画を提示する。
今回の「OK進めて」は、直前に提示した次候補の調査・計画作成として受領した。

## 調査結果

1. `MeetingTranslations.swift`の`AppleMeetingTranslator.translate`は、発話ごとに`TranslationSession(installedSource:target:)`を生成する。キューは既に正規化した原語・翻訳先のペア単位で直列化されているが、OSセッションは再利用していない。生成コスト・実際の遅延は未測定で、性能不良を再現済みとは扱わない。
2. `MeetingWorkspace`は確定発話と翻訳先だけを翻訳処理へ渡す。`DocumentTerms`の採用語は認識ヒントに渡されるが、翻訳のmask/unmask経路がない。
3. `MeetingKnowledgeControls`は`DocumentTermsView`へ`targetLanguage: nil`を渡す。Meetingには現在、訳語の言語を指定・確認するUIがない。資料の用語表から読み込んだ訳語が内部に残る場合も、その訳語の言語は確定していないため翻訳には使わない。
4. Conferenceには既存の`TermProtector.mask/unmask`と、トークン復元失敗時の原文による再翻訳がある。Meetingの既存用語を保護するために新しい置換アルゴリズムは不要。
5. `TranslationSession`はローカルSDKでSendable準拠していない。Swift 6・strict concurrency・`NonisolatedNonsendingByDefault`を有効にした独立コードで、actor内にセッションを保持して複数回呼ぶ形の型検査が成功した。リポジトリはSwift 6 / Approachable Concurrencyを使用する。製品組込みのビルド成功・実モデル動作を示す結果ではない。

AppleはinstalledSource初期化をUI外の翻訳に利用でき、モデル未導入時は翻訳が失敗すると説明している。既存の常駐Viewによるモデル準備を維持し、その後に翻訳用セッションを作る。
参考: [TranslationSession](https://developer.apple.com/documentation/translation/translationsession)、[installedSource初期化](https://developer.apple.com/documentation/translation/translationsession/init(installedsource:target:))。
調査用コード: `/tmp/conflingo-r6-translation-research/SessionReuse.swift`。型検査のみで、翻訳・モデル取得・音声取得は実行していない。

## R6-2 — 言語ペア単位のセッション再利用

- `AppleMeetingTranslator`の言語ペア別workerで、1つの`TranslationSession`を生成し、同じ非同期ループ内で保持する。非Sendableオブジェクトをactorへ保存せず、`@unchecked Sendable`等で検査を回避しない。
- `MeetingTranslationLane`の長寿命タスクが翻訳クライアントを保持する。`MeetingTranslations`は小さなfactoryでlane用クライアントを作り、テストでは生成回数を数えられるfakeへ差し替える。既存の単一client注入はfactoryへ置き換え、不要な互換initializerは追加しない。
- 同じ言語ペアの2入力は同じlane・クライアントを利用する。逆方向・異なる翻訳先は別lane。同じlaneの要求は引き続き直列とする。actorの再入可能性だけに直列制御を任せない。
- 準備成功前は翻訳を実行しない。通常の発話追加、キューが空になった後の追加、一時停止・再開、個別翻訳失敗の再試行では同じクライアントを使用する。
- 準備の再試行で世代を更新する場合はクライアントも更新する。古い準備通知・翻訳結果・終了処理が新しい世代の状態を変更しないよう、会議IDとlane世代を照合する。
- 会議破棄・新規会議ではタスクを取消し、laneとクライアントの参照を破棄する。旧処理が戻った後も結果を混入させない。実行中のOS処理の即時解放は保証せず、終了後に解放されることを確認する。
- 一時停止・終了時は既存どおり取得済み発話を処理する。UI移動・小窓切替でセッションを作り直さない。プロセス全体のキャッシュは追加しない。

## R6-3 — 既存の採用用語の原文表記を保持

今回の提案範囲は、Meetingで利用者が既に採用した用語を翻訳中に保護すること。原語言語ごとの採用語と100語上限を維持し、認識方式が通常モードでも翻訳には適用する。

- `MeetingWorkspace`から翻訳処理へ、原語と言語ペアに応じた用語を取得する接続を追加する。**各発話の翻訳開始時**に値をコピーし、その要求とフォールバック中は固定する。待機中の発話は開始時点の最新版を使い、個別再試行は再試行開始時点の版を使う。
- 現在のMeeting UIが採用した用語は、すべて`target: nil`として既存`TermProtector`へ渡し、原文表記を復元する。認識用として読み込まれた訳語や、翻訳先に対応づけられていない訳語を適用しない。別の原語言語の用語は混ぜない。
- 翻訳クライアントへ原文とは別の翻訳入力文字列を渡し、maskした文字列を翻訳→unmaskする。`TranscriptEvent`の原文・ID・時刻・AI根拠を変更しない。
- トークンの寛容復元でも未解決なら、同じセッションで原文を1回だけ再翻訳する。この場合は用語保持を保証しない。再翻訳の失敗・空応答は当該発話の翻訳失敗として表示し、壊れた中間訳を完成訳にしない。取消時にフォールバックを開始しない。
- 用語適用・解除、資料追加・削除成功による既存の用語resetは、以降に開始する要求へ反映する。完了訳の自動再翻訳は行わない。
- 用語UIの案内を「認識ヒントと翻訳時の原文表記保持」に合わせる。Conferenceでの訳語編集・表示は維持する。通常画面・小窓・保存・Markdownには復元済みの完成訳だけを渡す。

**別段階:** Meetingでの固定訳語入力と翻訳先の指定UI。同じ原語で2入力の翻訳先が異なるケースを含め、用語辞書を原語単位から言語ペア単位に拡張するか設計してから着手する。今回の範囲には新しい辞書UI、資料文脈によるAI補正、Conference翻訳処理の共通化を含めない。

## 変更対象

| 対象 | 変更 |
|---|---|
| `Meeting/Services/MeetingTranslations.swift` | lane別クライアント、生成・破棄、世代判定、用語保護 |
| `Meeting/MeetingWorkspace.swift` | factory注入、原語別採用語の接続 |
| `Meeting/MeetingPreview.swift`・fake利用テスト | 新しい注入契約へ更新 |
| `Meeting/Views/MeetingKnowledgeControls.swift`・`KnowledgeLibrary/DocumentTermsView.swift` | Meeting用語の説明を実装範囲へ合わせる |
| 翻訳・用語・保存関連テスト | 下記の公開動作とライフサイクルの回帰 |
| 詳細計画・Meeting翻訳設計・日英README・日本語ガイド・plan.md | 予定と完了を区別して仕様・残件を更新 |

保存形式v1、Conferenceの製品コード、認識エンジン、AI送信経路は変更対象にしない。

## 受入条件・TDD

| 対象 | 期待する結果 |
|---|---|
| 再利用 | 同じペアの連続発話・キュー再開・2入力でクライアント/バックエンド生成1回。別ペアでは別インスタンス |
| 実バックエンドの生成 | Apple adapter内の生成箇所を差し替えられる最小のfactoryで、複数translate呼出し時にセッション生成1回を検証。laneのfake生成回数だけで再利用の証拠を代用しない |
| 寿命・取消 | 一時停止/再開で維持、準備世代変更・会議resetで更新、遅延完了を拒否。旧処理終了後に旧所有者を解放 |
| 準備・失敗 | 準備失敗→再試行、片方向失敗時の他方向継続、個別翻訳失敗後の次発話・再試行を維持 |
| 用語保護 | 日英・英日、入力別の原語、長い語優先・単語境界・反復・大小文字を既存TermProtectorと結合して保持 |
| 用語の版 | 待機中の変更は次の処理へ反映、処理中・フォールバックでは固定。解除・資料変更後は旧用語を再利用しない |
| 誤適用防止 | 認識用候補に訳語が含まれていても固定訳として使わない。別原語の用語・不採用の候補は使わない |
| 復元失敗 | 寛容復元、原文の再翻訳1回、再翻訳失敗・空応答・取消を区別し、失敗時は後続発話を継続 |
| 原文・保存 | 原文不変、発話と完成訳の対応、停止時final、保存復元・Markdownの完成訳、既存v1固定JSONを維持 |
| UI | Meeting用語説明の通常/狭幅、原文・訳文の通常画面/小窓、翻訳待ち・失敗・再試行表示を合成入力で確認 |

## 実装順と検証

1. 承認後に関連資料へ予定仕様・受入条件を反映する。
2. R6-2を`tdd`スキルで実施。生成回数とライフサイクルのRedを確認→最小実装→関連・全テスト、SwiftLint strict/no-cache、Releaseビルド。独立してリリース可能な状態を保つ。
3. R6-3を同じ順で実施。用語が翻訳入力へ渡らないRedを確認→最小実装→用語・翻訳・保存・UIの確認、全テスト・Lint・Releaseビルド。
4. `git diff --check`、不要な旧注入経路・資料矛盾の確認、結果と未検証事項を記録する。テスト・lint件数は実行結果から記載し、以前の640件を流用しない。

全live評価フラグは0。実モデルの速度・用語保持率、実音声、Gate A/B/C/U/Dの受入は別途継続する。事前調査では製品のLint・テスト・ビルドは未実行だった。実装後の結果は末尾を参照。コミット、PR、インストール済みアプリ更新は明示指示時に行う。

## 承認対象

R6-2のセッション再利用と、R6-3の**採用用語の原文表記保持まで**を順に実装する。Meetingの固定訳語UIは後続とする。ユーザー指定AGENTS.mdの「実装前に実装計画を作成し承認を得る」に従い、2026-11-14のユーザー「進めて」で本計画の実装承認を受領した。

## 実装時の技術調整（2026-11-14）

製品ビルドのSIL段階で、セッションを保持したオブジェクトから`@concurrent`なTranslation APIを呼ぶ案はデータ競合診断となった。事前の`swiftc -typecheck`だけでは検出できていなかった。`swiftc -c`と製品ビルドで確認できる、セッションをworkerのタスク領域に保持する方式へ調整する。AsyncStreamで発話IDを渡し、処理開始・完了の状態更新だけをMainActorへ戻す。言語ペアごとの再利用、用語版の固定、保存・UIの契約は維持する。

## 実施結果（2026-11-14）

R6-2/3を実装。R6-2のバックエンド生成回数とR6-3の用語未適用についてRed→Greenを確認した。最終は全656件中649成功・実API7skip、Lint249ファイル違反0、arm64/x86_64 Release成功。420pt/780ptの合成UI、保存復元・Markdown、旧処理破棄を確認。実モデル品質・速度改善・独立レビューは継続。[詳細と途中の失敗](../validation/r6-meeting-translation.md)。
