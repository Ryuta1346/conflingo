> 利用者確認追補（2026-11-10）: VoiceOverの読み上げ・キャプション・Control+Option+Spaceによる設定ボタン操作を利用者確認として記録。[証跡と制約](validation/pr6-focus-stability.md)。基本確認の質問は回答済み。全画面の読み順・実会議等の網羅確認とは区別する。

> 反復確認追補（2026-11-10）: [フォーカス45回・主画面/小窓往復3回が成功](validation/pr6-focus-stability.md)。VoiceOver本体のプロセス起動は確認したが、実読み上げは利用者の観測回答待ち。製品変更・追加API送信なし。

> キーボード追補（2026-11-10）: [一意の識別子を持つ無通信コピー](validation/pr6-keyboard-isolation.md)で、設定・言語選択・開始/停止/再開/終了・小窓の主要キー経路を確認。VoiceOver実操作と一時的なフォーカス停滞の原因は未確定。製品変更・追加API送信なし。

> 最新UI追補（2026-11-10）: [小窓の実受信中停止・取消・部分回答保持](validation/pr6-final-ui.md)をAXPressで確認。旧停止UI枠を1件使用し11/12、直近60/60枠は変更なし。言語メニューの矢印/Enter操作は成功、キーボード網羅・VoiceOver実操作は未確認。以下の小窓未完了記述は追補前の履歴。

> 製品採用結果（2026-11-10）: 3.8 Flash / medium・8192へ変更済み。290テスト・Debug/Release・lint成功。承認済み60要求を実施し品質52/52合格、新ビルドのKeychain・言語復元・主画面AI停止/一時停止/会議終了・再開後回答を確認。小窓の受信中停止・キーボード網羅/VoiceOver等は未完了。平均完了5.80秒、最大21.73秒。[結果](validation/pr6-model-adoption.md)。以下は各時点の履歴。

> 最新方針（2026-11-10）: ユーザー要望によりAI回答言語を事前設定する。その他の意味の誤りは、独自の根拠判定処理より先にモデル/推論量の改善を比較する。[調査・実装/評価計画](design/pr6-answer-language-model-plan.md)。ユーザーが両方を承認。回答言語設定を実装し290テスト・Debug/Release・lint109ファイル違反0、非録音UIの双方向反映を確認。72要求も完了し、minimal 19/24、high 22/24、3.8 Flash/medium 24/24。得られた71応答は指定言語に一致。[結果](validation/pr6-answer-language-model.md)。製品既定の変更と全体回帰は未実施、PR6全体の受入は未完了を維持。

> 継続修正（2026-11-10）: ユーザー「次進めて」により[言語・根拠整合の計画](design/pr6-grounding-language-plan.md)をローカル実装・検証済み。旧28ケースの言語検査、対照6ケース、プロンプトを更新。287テスト・Debug/Release・lint107ファイル違反0。[検証記録](validation/pr6-grounding-language.md)。追加62要求も完了し48合格・9不合格・5要確認。言語不一致4件と因果の補完等が残り、次は要求言語・主張と根拠の契約を設計する。PR6/Gate C未合格を維持。

# ConfLingo — リアルタイム会議支援プロダクト 改善・実装計画

> 2026-11-10追補: 混在文脈の品質修正後52要求に合格し、[修正後UI/Keychain・実受信後停止](validation/pr6-stop-acceptance.md)も確認。[非録音UIの追加受入](validation/pr6-nonrecording-ui-acceptance.md)では通常起動の準備・設定遷移と主要キーボード操作を確認。別署名ビルドのキー読出しエラー、VoiceOver・通信中クリック等は残る。本文中の旧評価値は各時点の記録。通常起動の開始後・実音声等の受入は未完了。
> 同日追加: 最新ビルドの追加認証はユーザー指示でスキップ。許可済みビルドで[合成36ケースの根拠](validation/pr6-semantic-acceptance.md)を照合し、35件合格・英語レビュー完了回答1件を要確認とした。[追加8要求の停止UI](validation/pr6-native-stop-acceptance.md)では主画面・小窓の受信後クリックと取消を確認。一時停止/終了は完了後クリックで未確認、日本語質問への英語回答1件を観測。承認枠44/44要求を使用。PR6/Gate Cは未完了を維持する。

> 認証再開後: 最新ビルド自身のKeychain読出し・登録状態の受入は[再検証で合格](validation/pr6-keychain-auth-resume.md)。非対話読出しと製品登録状態の2テスト、および通常起動の設定シート・設定ページで確認した。追加API0件。上記の認証スキップは過去時点の記録。
> 最新追加: [追加12要求枠の確認](validation/pr6-followup-acceptance.md)で10要求を実行し、一時停止・会議終了の受信後クリックと取消、再開後の新規回答完了を確認。無通信で主要キーボード経路と狭幅・48pt表示も確認。品質4件は言語一致、意味2件合格・2件要確認。過去の言語不一致は未解決、VoiceOver等も残るためREVIEWを維持。

> 最新品質改善: [承認済み計画](design/pr6-focused-answer-quality-plan.md)を実装し68要求を完了。候補60件は54合格・4不合格・2要確認。286テスト・Debug/Release・lint106ファイル違反0。言語不一致・根拠にない依存関係等が残り、PR6/Gate Cは未合格。[全件の評価記録と次の対応](validation/pr6-focused-answer-quality.md)。今回の実API評価は認証済みホスト内の候補クライアントで行い、新ビルド自身のUI/Keychain受入とは区別する。

- 作成日: 2026-11-07
- 対象: [Ryuta1346/conflingo](https://github.com/Ryuta1346/conflingo)
- 確認した基準: `main` / `b1a20319bc5eec5717d7840a2fc67547c0556fc7`（2026-06-18）
- 状態: **PR0実機確認持ち越し／PR1・PR2完了／PR3・PR4マージ済み、実機受入待ち／PR5-A/B/Cマージ済み、残る受入待ち／PR6品質修正・合成実API・修正後UI・公開停止操作の受入確認済み、残る受入待ち**（2026-11-08：ローカルmain `e167765`で確認。PR4 #9: `c714f9c`、PR5-A/B #10: `c34ddd1`、PR5-C #11: `e167765`。PR5-C修正後236テスト・build・lint成功の既存記録あり。Gate A/B/U未完了。[PR4検証](validation/dual-transcription.md)・[PR5-B検証](validation/pr5-b-conference.md)・[PR5-C検証](validation/pr5-c-meeting.md)）
- 前提: macOS 26+、Apple Silicon、Swift 6 / SwiftUI、既存のSpeech.frameworkとTranslation.frameworkを生かす

## 0. 結論・プロダクト戦略

ConfLingoを別製品として作り直さず、既存の「文字起こし・翻訳」を**入力・表示の基盤**にして、**会話理解・判断支援・ナレッジ参照**を追加する。**UI/UXはConferenceを含むアプリ全体を再設計し、共通デザインシステムの下に統一する**（既存操作と保存データの互換は維持）。最初の狙いは会議録ではなく、会議中に根拠のある応答や確認事項を適切なタイミングで提示すること。

- **Conferenceモード:** 従来のマイク音声→オンデバイス文字起こし→オンデバイス翻訳。既存利用者の体験・保存形式を維持。
- **Meetingモード:** マイク + Mac内部音声 → オンデバイス文字起こし → 会話イベント → AI提案・会議状態追跡。
- **専門プリセット:** 最初はGeneralを実用化。Engineering / Salesは共通基盤上の分析ルール・辞書・参照先の違いとして追加。
- **Local-first:** 音声・認識・翻訳は原則Macで完結。AI支援が有効な会議だけ、必要最小限の文字列・検索結果を外部AIへ送信。
- **UI/UX全面刷新（採用済み）:** 先に高品質モックで完成形を定義 → SwiftUIのデザイントークン・共通コンポーネントを整備 → ConferenceとMeetingに反映。PR5は **PR5-A / PR5-B / PR5-C** に分割する。

### MVPに含める

1. Zoom / Google Meet / Teamsで再生される音声とマイク入力を並行取得する。
2. 日本語・英語を手動選択してリアルタイム認識し、「自分／相手側」の入力元を区別する。
3. 発話内容から質問候補・回答提案・確認質問・リスク・決定候補・アクション候補を生成する。
4. AI提案の根拠となる発話時刻と、利用可能な場合は参照資料を表示する。
5. 会議中は最前面・小窓UI。終了時に会話・確認済み決定事項・宿題をMarkdown保存する。
6. 既存の翻訳・専門用語辞書・履歴・Markdown出力を壊さない。

### 初期MVPでは含めない

- 会議ボットの参加、クラウド音声録音保存、複数相手の人物名への自動話者識別。
- Zoom/Teamsの専用API連携、他人への自動メッセージ送信、タスクの自動登録、同意なき会議録画。
- Windows / iOS、組織共通のナレッジ管理、多数の外部サービスへの双方向同期。
- 自動発言・音声合成・無人会議代理。

## 1. 既存実装の確認結果と改修箇所

| ファイル | 現状 | 改修方針 |
|---|---|---|
| `ConfLingo/Services/AudioCaptureService.swift` | `AVAudioEngine`のマイク入力を`AsyncStream<AnalyzerInput>`へ変換 | 既存機能を残しつつマイク用AudioSourceアダプタを追加 |
| `ConfLingo/Services/SpeechTranscriptionService.swift` | `SpeechAnalyzer`/`SpeechTranscriber`、VAD、確定・途中結果、翻訳キューへ直接渡す | 結果を型付き`TranscriptEvent`として配信し、翻訳と分析へ分岐させる |
| `ConfLingo/Services/SessionController.swift` | マイク入力1系統・文字起こし1系統の開始停止 | 2入力の起動・停止・権限・失敗時縮退、セッション共通時計を扱う |
| `ConfLingo/Models/SessionStore.swift` | `english`/`japanese`前提、翻訳単位バッファ、UI状態 | 既存モード用に残す。新MeetingSessionStoreを設け段階的に統合 |
| `ConfLingo/Models/TranscriptSegment.swift` | 原文プロパティが`english`固定 | Meeting用に言語非依存のイベントモデルを新設。変換アダプタで互換維持 |
| `ConfLingo/Services/TranslationCoordinator.swift` | 文単位・ID重複排除キュー | AI分析とは独立したConsumerとして維持、再接続時重複を検証 |
| `ConfLingo/Models/KeywordProfileStore.swift` | 辞書プロファイルをUserDefaultsに永続化 | Meetingプリセットと専門用語に再利用 |
| `ConfLingo/Views/ContentView.swift` | 文字起こし／翻訳画面、設定・翻訳処理が集中 | `AppShellView`に責務を分離。画面ナビゲーションを統一し、既存Conferenceも全面刷新 |
| `ConfLingo/Views/ControlBar.swift` | Start/Stop・保存・Clear・最前面 | `SessionTransportControls`等の共通部品へ分離し、Conference/Meetingの操作・状態表示を統一 |
| `ConfLingo/Export/MarkdownExporter.swift` | 文字起こし・翻訳のMarkdown生成 | 従来出力互換を維持。MeetingExporterを追加 |
| `ConfLingo/ConfLingo.entitlements` | App Sandbox有効、マイク・ネットワーク・ユーザー選択ファイルの権限 | システム音声方式に応じて権限・配布制約を検証 |

**重要:** `SessionStore` / `TranscriptSegment` の既存構造を最初から全置換しない。新しい会議用ドメインを追加し、従来モードへのアダプタで回帰リスクを下げる。

## 2. 目標アーキテクチャ

```text
                   ConfLingo macOS App (SwiftUI)
 ┌──────────────────────────────────────────────────────┐
 │ MicrophoneAudioSource     SystemAudioSource          │
 │ (既存AVAudioEngine)       (まずScreenCaptureKitで検証)│
 └─────────┬───────────────────────┬────────────────────┘
           │ PCM + source + clock  │ PCM + source + clock
           ▼                       ▼
      SpeechPipeline(self)    SpeechPipeline(remote)
          SpeechAnalyzer / SpeechTranscriber
           └───────────┬───────────┘
                       ▼
           TranscriptEventHub (Actor)
            ├─ LegacyTranslationAdapter → 翻訳字幕
            ├─ MeetingSessionStore → 発話・時系列
            └─ ConversationEventDetector
                        ├─ Question / Clarification
                        ├─ Risk / Contradiction
                        └─ DecisionCandidate / ActionCandidate
                       ▼
             AI Insight Coordinator
             ├─ Local rules / throttling
             ├─ Knowledge Retrieval (local FTS5 first)
             └─ InsightClient (明示的許可時のみ)
                  ├─ Gemini直接接続 / 利用者のキー (PR6)
                  └─ 他社直接接続 / 運営Proxy (後続)
                       ▼
          MeetingCopilotView + MeetingExporter
```

### 2.1 音声の共通インターフェース

- `AudioSource`プロトコルを定義。`start()` / `stop()` / 音声PCMストリーム / 入力元識別子 / 権限状態を公開。
- `MicrophoneAudioSource`は現行`AudioCaptureService`をアダプタで包む。
- `SystemAudioSource`は最初にScreenCaptureKitを使用。`capturesAudio = true`、`excludesCurrentProcessAudio = true`を基本とし、録音対象の選び方と権限を実機で検証。
- Process Tapは独立した技術検証。アプリ単位で取得できるメリットはあるが、現行App Sandboxとの互換性・署名/配布制約を確認するまで本線に入れない。
- 音声コールバックで重い処理をしない。音声バッファを低負荷で受け渡し、サンプルレート/チャンネル変換は専用処理系で行う。
- マイクと内部音声にそれぞれ認識インスタンスを割り当てる。2つの`SpeechAnalyzer`を同時に安定動作させられるか早期に検証する。
- 自分のスピーカー出力がマイクに回り込む場合の重複抑制を検討。ヘッドフォン利用を推奨し、無理に高精度話者分離を約束しない。

#### PR2の実装契約（2026-11-08承認・自動検証済み）

- `AudioSource`はMainActor上で入力元、権限状態、ライフサイクル状態、権限要求、指定フォーマットでの開始、冪等な停止を公開する。
- `MicrophoneAudioSource`が既存キャプチャを包む。権限の参照はダイアログを出さず、未許可での開始は拒否する。権限待ち中の重複要求をまとめ、キャンセルされた呼び出しから入力を開始しない。
- 状態はidle→starting→running→stopping→idle。二重開始は既存ストリームを保持してエラー、開始失敗は後始末してidle、再開は新しいストリームとする。
- 共通境界はSpeechに依存しないPCMフレームを流す。コールバックのバッファは所有権を確保してから渡し、渡した後は変更しない。AnalyzerInputへの変換は認識サービスで行う。
- SessionControllerの既定構成は権限要求とSpeechTranscriptionServiceで同じ入力源を使う。停止順は入力停止→認識finalize・最終結果取り込み→Hub終了を維持する。
- 自動受入は権限、PCM内容・順序、二重開始・停止、開始失敗・再開、旧入力混入防止、既存Conference回帰、build/test/lint。結果は[PR2検証記録](validation/audio-abstraction.md)へ記載する。
- 実音声試験の延期を継続する。実デバイスのリソース解放・認識結果の同等性は未検証として扱う。

#### PR3の実装契約（2026-11-08承認、実装・自動検証済み）

- AudioSourceの開始・停止を非同期化し、PCMストリームに開始後のエラーを伝達できるようにする。開始中キャンセル・同時停止・再開の世代分離を検証する。
- 同時停止の各呼び出し元へは状態・タスク参照の後処理完了後に返す。正常停止直後の再開と、停止失敗直後の再試行を保証する。
- ScreenCaptureKitでMacの出力音声を取得し、自プロセス音声を除外する。マイクと画面サンプルは取得せず、音声ファイル保存は行わない。
- 明示操作のみで権限要求・入力開始を行う。許可のBool値だけから未決定／拒否を断定しない。
- 独立した検証ウィンドウで権限、入力レベル、フレーム数、開始停止、エラーを確認する。2入力STT・Meeting UIは後続PR。
- PCMは独立所有し、256フレームの待機上限超過はエラー終了する。正常停止・入力形式変更ではリサンプラーの末尾を排出する。停止失敗は状態を保持して再試行し、閉じる操作時の失敗では検証画面を再表示する。
- 自動受入はfake OS境界と合成PCMで行う。実音声試験の延期は継続し、Zoom/Meet/Teamsと配布版での成功は未検証として残す。
- [方式比較ADR](adr/002-system-audio-capture.md)と[検証記録](validation/system-audio.md)に根拠と結果を記録する。

#### PR4の実装契約（2026-11-08承認、実装・自動検証済み）

- PR3レビュー→PR4というユーザー指示に従って実装・マージ済み。PR0/3の実音声試験延期を継続し、PR3のマージと実機受入を区別する。
- 計画の保存先: `~/.coding-agents/docs/conflingo/feature-dual-transcription/000_pr4-dual-transcription-plan.md`。ユーザー承認済み（「進めて」）。TDDで実装し、[検証記録](validation/dual-transcription.md)に結果を記録した。
- 2入力に独立した認識系統・入力別言語を割り当て、共通Timeline・Hub・MeetingSessionStoreへ接続する。入力開始通知を時刻基準とするため、サンプル時刻の厳密同期と時刻誤差は実機検証が必要。
- 発話ID/revisionによる重複除外と時刻順の安定整列を行う。別入力の同じ発話内容は保持する。片系失敗時は両入力を停止し、停止失敗の再試行・最後のfinalの取り込みを保証する。
- 独立した2入力検証画面を用意し、既存Conference・単独音声検証との競合起動を防ぐ。完成Meeting UIはPR5-C。実機受入までGate BとPR4のDONE判定は保留する。

### 2.2 会話イベントモデル

新規型の例（最終的な名称・フィールドは実装時に調整可）：

```swift
enum AudioOrigin: String, Codable, Sendable {
    case microphone
    case systemAudio
}

struct TranscriptEvent: Identifiable, Sendable {
    let id: UUID
    let sessionID: UUID
    let origin: AudioOrigin
    let languageCode: String
    let startOffset: TimeInterval
    let endOffset: TimeInterval?
    let text: String
    let isFinal: Bool
    let revision: Int
}

enum InsightKind: String, Codable, Sendable {
    case answerSuggestion, followUpQuestion, risk
    case decisionCandidate, actionCandidate
}

enum InsightStatus: String, Codable, Sendable {
    case suggested, acknowledged, dismissed
}
```

- 会議の共通時刻（monotonic clock）を基準とし、Start→Stop→再開時に経過時刻がリセットされないようにする。
- 途中結果は同じ発話IDに対するrevisionとして更新。**確定結果だけ**判断・アクション候補の確定入力にする。
- `EventHub`は複数Consumerにファンアウト。遅いAI通信によって音声や字幕を止めない。
- UI用のpartialイベントは古いものを破棄可能。finalイベントは重要データとして保持し、容量上限時はエラー通知/縮退（無制限キューにしない）。

#### PR1の実装契約（2026-11-08承認・自動検証済み）

- 同一発話のpartial→finalは同じIDと増加するrevisionを使う。空文字、古いrevision、確定後のpartialは履歴を更新しない。別入力・別発話は同じテキストでも保持する。
- PR1の正規化は認識範囲の開始位置で発話を識別し、終了位置が伸びるpartial更新ではIDを維持する。final後は次のIDへ切り替える。実SpeechTranscriberの範囲更新挙動は実音声試験で確認する。
- 会議時刻は単調増加時計を基準にし、停止中も含む経過時間を再開時の認識時刻へ加算する。Clearで会議IDと時計を初期化する。既存Conferenceの保存時刻は従来どおり各入力開始からの時刻を保つ。
- Hubは購読先ごとにfinal待機256件と入力元ごとの最新partialを保持する。partialがfinalを追い出さない。final超過は送信側・購読側へ通知し、該当購読先を終了する。他の購読先は継続する。過去履歴は再送しない。
- Conferenceの必須購読失敗は既存エラー表示と入力停止へつなぐ。将来の任意AI購読失敗はConferenceを止めない。
- LegacyTranslationAdapterが既存の文境界・4秒タイムアウト・翻訳キューを維持する。認識結果の読取完了→Hub終了→購読処理完了→残りの翻訳flushの順で停止する。
- 辞書は入力開始時に適用する。自動停止中のstop呼び出しも同じ終了処理の完了を待ち、最後の翻訳を確定してからidleへ戻る。
- 開始失敗・認識失敗・停止で購読とタイマーを解放する。再開で会議IDと履歴を維持し、Clearで既存・Meetingストアをまとめて初期化する。
- Clearはidleであれば字幕が空でも利用できること。字幕なしで停止したセッションでも会議IDと時計を初期化でき、preparing / listening / stoppingでは利用できないこと。
- 実入力はマイクのみ。内部音声、2入力同期、UI刷新、AI、永続化は後続PR。合成入力による検証と実機回帰は区別する。
- 自動受入は発話更新、複数配信、容量上限、購読取消、停止直前final、失敗・再開・Clear、既存字幕・翻訳・辞書・Markdown回帰、build/test/lint。結果は[PR1検証記録](validation/core-events.md)へ記載する。

### 2.3 AI支援パイプライン

PR6の具体化は[実装計画](design/pr6-implementation-plan.md)と[ヒアリング記録](design/pr6-hearing.md)を参照。2026-11-08のインタビューでGemini BYOK直接接続、合成会話による先行検証、低コスト優先・自動提案初期オフを確認済み。PR4実機受入の持ち越しはPR6について別途承認済み。実装計画全体はユーザー「OK」により承認後、Geminiアダプタ・Keychain・手動質問・自動提案・停止連動を実装し、263テストとモックUI操作を確認した。[PR6検証記録](validation/pr6-insights.md)。その後の実API受入は冒頭の最新記録を参照。以下の検索・要約・専門モードは後続段階を含む目標仕様。

1. 文字起こしイベントを発話単位に正規化し、直近の会話履歴と要約状態を更新する。
2. **手動質問**は送信許可後に利用者の操作で実行。**自動提案**は初期オフとし、会議ごとにオンにした場合だけ質問検出・重要な矛盾・決定候補等でトリガーする。
3. 類似したイベントはdebounce/dedupし、提案の連続表示を抑制する。初期値は自動提案最大2件/分、最短間隔12秒（実測調整）。
4. 必要なときだけナレッジ検索し、直近の発言・要約・検索結果をLLMへ渡す。
5. ストリーミングでカードを表示する。提案の種類・発話根拠ID・資料根拠・根拠不足を構造化する。
6. 「候補」と「確定事項」は厳密に区別。ユーザーの明示的な承認なしにAIが合意済みに変えない。
7. ネットワーク断は字幕・既存翻訳を止めず、AI支援のみ利用不可表示にする。

#### AI生成の品質ルール

- 知らない仕様・価格・日程を断定しない。根拠がなければ「要確認」を表示。
- 参照文書のソース（タイトル・該当箇所）を必ず返す。ただし文書なしの一般アドバイスはその旨を明示。
- 前の発言と矛盾する場合は引用発話と時刻を示す。
- 自動提案は控えめに。手動`Ask AI`を最優先する。
- 会議モード（General / Engineering / Sales）ごとに検出ルールとプロンプトを切り替える。

### 2.4 AI接続方式の分離

- **PR6の個人PoC:** 利用者のGemini APIキーをKeychainに保存し、アプリから直接接続する。従来の「PR6でHono Proxyを実装」案はインタビュー回答により変更。運営Proxyは今回作らない。
- **本番の目標:** 利用者自身のキーによる直接接続と、ConfLingo運営Proxy経由のAI提供を利用者が選択できる。OpenAI/Anthropic/GeminiほかのProviderを追加可能にする。
- UIと会議処理は共通の`InsightClient`境界を使用し、認証・HTTP・ストリーム変換をProvider/接続経路ごとのアダプタへ置く。今回はGeminiとモックだけを実装する。
- 音声PCMは送らず、**外部送信が有効なときのみ**質問文と必要な確定発話・参照IDを送る。資料スニペットはPR8以降。会議ID/要求IDの照合はローカルで行い、不要な識別情報は送らない。
- Geminiの応答を生成中/本文更新/完了/失敗の内部イベントへ変換する。外部APIが独自の`insight.created`形式を返す前提にはしない。
- 採用仕様はGemini 3.8 Flash / medium、出力枠8192（製品反映・品質52件合格）。初期モデルはGemini 3.1 Flash-Liteだった。料金・終了予定・保持条件を[PR6計画](design/pr6-implementation-plan.md)に記録。高額モデルへ自動切替せず、自動提案初期オフ、文脈/出力上限で費用を抑える。
- 運営Proxyは後続で認証・利用/支出上限・運営キー秘匿・保持条件を具体化する。Hono最小APIはその段階の候補。利用者のサブスク連携は公式に提供・許可される手段の有無を別途調査し、未確認のまま実装可能としない。

### 2.5 ナレッジ検索

- 初期MVPは**少量のローカル資料のインポート**（Markdown / Text、PDFは抽出結果を要検証）。
- ローカルSQLite FTS5（キーワード検索）でまず根拠抽出を成立させる。複雑なベクトル基盤をMVPの先行条件にしない。
- `KnowledgeReference`には文書ID、タイトル、位置、スニペット、取り込み日時を保存。
- 仕様書のRAG検索は`Engineering`の重要機能だが、外部モデルへの資料送信は会議ごとに明示許可。
- 組織共有ナレッジ、Embedding、reranking、pgvector/専用ベクトルDB、GitHub/NotionコネクタはMVP検証後に追加する。

### 2.6 UI/UX全面刷新方針（採用済み）

PR5を単発のMeeting画面追加にはしない。**デザイン設計（5-A）→ UI基盤および既存Conference刷新（5-B）→ Meeting Copilot UI（5-C）** の3段階で、同じ情報設計・操作体系を使う。

#### PR5-Aの設計成果物（2026-11-08・モック方向性承認済み）

- [レビュー入口・画面一覧](design/README.md)から9画面の操作モック、ライト/ダーク・狭幅画像を確認できる。
- [情報設計](design/app-information-architecture.md)、[デザインシステム](design/design-system.md)、[状態・フロー・受入仕様](design/ux-states-and-flows.md)を作成。現行コードの観察と将来仕様を区別した。
- [検証記録](design/validation.md): 主要操作24項目、拡大表示368ケース、構文・lint確認。製品Swiftコード・音声経路は未変更。モックの操作試験はネイティブ受入の代替ではない。
- 主要4画面の画像提示後、ユーザー「OK」によりモック方向性を承認。PR5-A/BはPR #10、PR5-CはPR #11（`e167765`）でマージ済み。個別受入の残項目があるためREVIEWを維持。Gate U全体は未完了。ローカルSessionsの永続化担当とAI接続先・保持表示は後続実装計画で確定する。
- [PR5-B実装計画](design/pr5-b-implementation-plan.md)を作成済み。共通デザイン部品とConference刷新を対象とし、ユーザー「進めて」により計画承認後に実装。レビュー修正後211テスト・Debug/Release build・lint成功、非録音の画面/操作を確認。マージ済み、実機受入待ちのためREVIEW。[PR5-B検証記録](validation/pr5-b-conference.md)。

#### PR5-Cの実装計画（2026-11-08承認・実装/自動検証済み）

- [実装計画](design/pr5-c-implementation-plan.md)に範囲・操作契約・テスト・受入条件を記載。ブランチは`feature/meeting-ui`。ユーザー「進めて」により計画承認後、実装・非録音ネイティブ操作を確認。展開時の停止確認と発話順のレビュー修正後、236テスト・Debug/Release build・lint成功。[検証記録](validation/pr5-c-meeting.md)。別エージェントによる独立レビューと実音声受入は未実施。
- Meeting Preparation/Live/Review、根拠表示、コンパクト/展開/非表示を対象とする。AI通信はPR6、候補確定・Meeting出力はPR7、資料検索はPR8に残す。
- **承認済みの方針:** PR4実機受入の延期を維持して接続コードとfake結合検証を先行する。従来の「PR4受入後に結合」の条件変更は、本計画承認により適用する。実音声受入・Gate A/B/Uは未完了のまま管理する。

#### 2.6.1 情報設計と画面マップ

```text
AppShell
├── Home / Recent Sessions
├── Conference
│   ├── Session Setup（言語ペア・マイク・専門用語辞書）
│   └── Live Captions（原文 / 翻訳 / 字幕履歴）
├── Meeting
│   ├── Preparation（参加者への通知・同意確認 / 入力 / AI / 資料）
│   ├── Live（Insights優先 / 文脈・全文の展開 / 会議状態）
│   └── Review（決定・アクション候補 / 根拠 / Export）
├── Sessions（検索・閲覧・削除。初期MVPではローカル保存済みセッションに限定）
└── Settings（音声・言語・AI・データ保持・ショートカット）
```

- `Conference` / `Meeting`は**同じアプリ内の独立モード**。会議中の誤操作を避けるため、実行中のモード切替は確認を要求する。
- 既存のConference機能（多言語音声認識、翻訳、辞書プロファイル、最前面、フォントサイズ、Markdown出力）を全面刷新したUIに移す。機能を削らない。
- `Sessions`は自動クラウド保存を意味しない。ローカルに保存したものだけが一覧に現れる。保存OFFの会議は終了時に破棄できる。
- 初期リリースで表示するが機能がないナビゲーション項目を作らない。先行デザインでのみ将来画面を扱う場合は、実装範囲外を明示する。

#### 2.6.2 画面ごとの役割

| 画面 | 主要情報と操作 | 重要なUX要件 |
|---|---|---|
| App Shell / Home | Conference/Meetingの開始、最近の保存セッション、入力の接続状態 | 1〜2クリックで開始地点に到達。初期設定不足を明示 |
| Conference Live | 原文・翻訳の2ペイン、partial/final差分、用語辞書、再開/保存 | 従来操作を維持しつつ字幕が最優先。長文・フォント拡大・左右/上下レイアウトを検証 |
| Meeting Preparation | 会議名、入力元、言語、プリセット、ナレッジ、音声取得・AI送信の許可 | **収集する音声・送信するデータ・保存先**を開始前に説明 |
| Meeting Live Expanded | 今必要なAI提案、時系列発話、未決定事項、根拠リンク、Ask AI | 「AIによる提案」と「確定した事実」を混同しない。会議の妨げにならない |
| Meeting Floating | 最新の重要提案1件、次の質問、警告、録音/送信状態、折りたたみ/拡大 | サイズ変更可。必要時だけ表示。クリック・ショートカットで復帰 |
| Meeting Review | タイムライン、AI抽出した決定・宿題候補、確認/却下、Markdown出力 | AIの候補は未確定から開始。根拠発話へ移動できる |
| Sessions | 保存済み会議・字幕の検索、エクスポート、削除 | 保持・破棄の結果を明示。意図しない自動保存を防ぐ |
| Settings | マイク/システム音声、認識言語、LLM送信、秘密情報、保持、キー操作 | プライバシー設定と動作の対応が一目で分かる |

#### 2.6.3 デザインシステム

- **macOSネイティブ優先:** SwiftUI標準のメニュー、フォーカス、Window、アクセシビリティ、状態表現を活用。Web風の過度な装飾を避ける。
- **トークン:** 背景/サーフェス/境界/テキスト/ステータス、文字サイズ・行間、余白、角丸、階層、アイコン、フォーカス・hover・disabled状態。
- **共通コンポーネント:** `ModeSwitcher`、`SessionTransportControls`、`AudioSourceStatus`、`CloudSharingStatus`、`TranscriptTimeline`、`InsightCard`、`EvidenceLink`、`DecisionCandidateCard`、`EmptyState`、`ErrorBanner`。
- **AIカードの情報優先順位:** ①提案内容 ②理由・引用元 ③未確認/リスク ④ユーザー操作。未検証の数値的「確信度」は出さない。
- **状態設計:** idle / requestingPermission / preparing / listening / paused / stopping / error / offline / reconnecting / AI-disabled / no-knowledge / no-insights を画面ごとに定義。
- **アクセシビリティ:** VoiceOverラベル、キーボード操作、フォーカス順序、Dynamic Type相当の文字拡大、視認性・コントラスト、色だけに頼らない状態表示、Reduce Motion対応。
- **画面サイズ:** MacBook 14インチを優先し、狭いウィンドウ・分割表示・大きな文字サイズでも操作が隠れないこと。
- **モックと実装の整合:** PR5-Aのモックを設計上の基準とし、PR5-B/Cのスクリーンショットを同一状態・サイズで比較。デザイン変更は差分と理由を記録。

#### 2.6.4 フローティングUIのルール

- コンパクト/展開/非表示の3状態。デスクトップ上での位置・幅・高さを保存する。
- コンパクト時は最新の**重要度が高い提案を最大1件**表示。会議中の原文全文を常時流さない。
- `Ask AI`は手動起動可能。自動提案は静かに更新し、モーダルや強制フォーカス変更をしない。
- 録音中（マイク/システム）、クラウド送信中、クラウドAI停止中を常時区別する。
- `Pause Capture` / `Stop Session` / `Disable Cloud AI`を意味別に分け、停止時の実際の音声・ネットワーク状態と一致させる。
- 画面共有時の振る舞いは実機で検証。**「画面共有に映らない」ことは保証しない**。必要に応じて明示的な非表示操作を提供する。

#### 2.6.5 UI受入条件

- Conferenceの従来主要操作を、新UI上ですべて再現できる。
- Recording / AI Sending / Paused / Disconnected / Permission Denied の各状態で表示が正しい。
- Live中に入力・表示・AI分析のいずれかが失敗しても、影響のない機能は継続する。
- UI内で根拠のない断定、AI候補の自動確定、同意なしの送信が起きない。
- 長い日英字幕、多数のInsight、複数画面、縮小幅、文字拡大、キーボード操作を試験する。
- 最終受入は**モック比較 + 自動UIテスト + 実機利用テスト**の3点で行う。

## 3. 実装PR計画と依存関係

見積もりはAIコード生成・レビューを活用する1名開発の**純作業日**（待機/審査/予期せぬOS問題は別）。PRは原則独立・小さめ、各PRで`xcodebuild test`を通す。

| PR | 優先 | 主な実装 | 完了条件 | 概算 |
|---|---|---|---|---|
| **PR0: Baseline** | P0 | 現行ビルド・テスト、同意/権限・ベンチ用音声、計測基盤、設計ADR | 既存操作のベースラインを記録 | 1–2日 |
| **PR1: Core Events** | P0 | `AudioOrigin`/`TranscriptEvent`/`TranscriptEventHub`/`MeetingSessionStore`、テスト | 既存字幕・翻訳を壊さずイベント配信 | 2–3日 |
| **PR2: Audio Abstraction** | P0 | `AudioSource`、既存マイクのAdapter、開始停止の状態機械 | 従来モードと同じ認識結果、停止後リソース解放 | 1–2日 |
| **PR3: System Audio Spike** | P0 | ScreenCaptureKit実装、権限表示、CoreAudio Tap比較メモ | Zoom/Meet/Teamsでシステム音声入力成功、結果をADRに記載 | 2–4日 |
| **PR4: Dual Transcription** | P0 | マイク/内部音声の2認識系統、共通時計、VAD、重複/順序の処理 | 会議中に両側の字幕が同時に出て区別できる | 2–4日 |
| **PR5-A: UX/UI Design** | P1 | 既存ConferenceのUX監査、全体画面マップ、情報階層、高品質モック・状態別プロトタイプ | 必須画面・状態・操作フローのモック承認、UI受入仕様確定 | 2–3日 |
| **PR5-B: Design System & Conference** | P1 | SwiftUIデザイントークン/共通部品、App Shell、Conference全面リデザイン、設定/保存の整流化 | 既存Conference機能を落とさず、承認モックに合わせた画面・操作が動く | 3–5日 |
| **PR5-C: Meeting Copilot UI** | P1 | Preparation/Live/Review、Insight/根拠カード、コンパクト・展開フローティングUI | モックイベントと実データで全状態を操作でき、会議中の認知負荷を抑えられる | 3–5日 |
| **PR6: Insight Engine** | P0 | 手動質問、自動提案（初期オフ）、Gemini BYOK直接接続、将来の接続切替境界、ストリーミング | 質問に対し会議文脈を使った提案、失敗時縮退 | 3–5日 |
| **PR7: Meeting State** | P1 | 決定候補・アクション候補、確認/却下、要約、Markdown出力 | 誤って自動確定しない・根拠が追える | 2–3日 |
| **PR8: Local RAG** | P1 | ファイル取り込み、全文検索、根拠参照、資料送信制御 | 登録資料の該当箇所を根拠として提示 | 3–5日 |
| **PR9: Hardening** | P1 | 60分試験、入力切断/再接続、権限/プライバシー、ログ・テスト・CI | 下記受入基準を満たす | 3–5日 |

**技術の重要経路:** PR0→PR1→PR2→PR3→PR4→PR6。PR7/PR8はPR6の安定後に実装。**UIの重要経路:** PR0→PR5-A→PR5-B→PR5-C。PR5-AはPR1〜4と並行開始できるが、PR5-Bは承認済みモックの後に行う。PR5-Cはモックイベントを使ってPR6と並行実装し、結合検証で統合する。

**初期PoC:** PR0–4 + PR6の最小機能（簡易UI、手動Ask AI、モックナレッジ）で約2–3週間。UI PoCは完成UIとは区別する。

**UI設計マイルストーン:** PR5-A承認→PR5-B Conference改修承認→PR5-C Meeting表示承認。前ステージの未承認モックで次の段階を作り込まない。

**実用MVP:** PR0–9（PR5はA/B/Cに分割）を通し、部分並行で**約6–10週間**を初期目標。UI刷新分を含めて再見積もりし、技術検証結果によって調整する。

## 4. フェーズごとの受入基準

### Gate A — 既存機能を壊さない

- `xcodebuild -project ConfLingo.xcodeproj -scheme ConfLingo -configuration Debug build`が成功。
- `xcodebuild test -project ConfLingo.xcodeproj -scheme ConfLingo -destination 'platform=macOS'`が成功。
- マイク単独、英語→日本語翻訳、文字起こし専用、専門用語辞書、途中字幕/確定字幕、Start/Stop再開、Markdown出力が動作。
- 既存Markdownの内容が予期なく変わらない（スナップショットテスト）。

### Gate B — 会議音声が実際に取れる

- Zoom、Google Meet、Teamsの**それぞれ**で相手側の音声が認識される（公開テスト音声や同意済みのテスト会議で検証）。
- ヘッドフォン/内蔵スピーカー、マイク有効/無効を切り替えても状態表示が破綻しない。
- 会議途中で音声機器・入出力権限が変わったとき、通知し再開できる。
- 2つの入力が混同されず、発話順序・時刻を保持する。
- 2つのSpeechAnalyzer同時実行の性能・メモリ・認識精度を確認。成立しなければ認識方式を再評価する。

### Gate C — AI提案が有用

現在の回答言語契約は、利用者が事前選択した日本語/Englishを質問・発話の言語に優先して手動/自動の回答へ適用する。[言語設定計画](design/pr6-answer-language-model-plan.md)。以下は変更前の評価履歴。

2026-11-09承認の[PR6回答品質改善計画](design/pr6-response-quality-plan.md)のQ01〜Q06を追加受入条件とする。質問言語での回答、具体的な不足説明、雑談の候補誤分類防止、曖昧さと矛盾の区別を合成24件で検証した。最終23/24合格、明示された日程を曖昧扱いするQ05残件があり、Gate Cは未合格。[検証記録](validation/pr6-response-quality.md)。

- テスト会議で、質問→回答候補、確認事項、技術上の懸念、決定候補が発生する。
- AIの回答に会議中の関連発話ID/時刻が表示される。
- 文書参照時は根拠資料を開ける。根拠がない回答は明確に未確認扱い。
- AIの無限連続提案や同一提案の連発が発生しない。
- `decisionCandidate`は必ずユーザー確認前は未確定として表示される。
- ネットワーク切断時は字幕・オンデバイス翻訳が継続し、AI機能のみ一時停止する。

### Gate U — UI/UX全面刷新の品質（PR5-A/B/C）

- PR5-Aの主要画面のモックが定義され、実装前にデザインと利用フローをレビュー済み。
- Conferenceの言語切替、専門用語辞書、字幕、翻訳、Start/Stop、Clear、Export、最前面、文字拡大を新UIでも利用できる。
- MeetingのPreparation→Live→Reviewを、キーボード中心でも完了できる。
- コンパクト/展開ウィンドウ、音声取得・AI送信の状態、プライバシー操作、失敗・空状態を実装している。
- 14インチMacBookでの通常ウィンドウ、狭い分割表示、大きい文字サイズ、VoiceOverの基本操作を確認。
- 承認したモックと実装のスクリーンショットを比較し、意図しない構造差分を修正または記録。

### Gate D — 利用者に出せるMVP

- 実際の60分会議でクラッシュなし、継続的なメモリ増加・処理滞留なし。
- **目標値（要実測）:** 質問発話の終了→AIカード完成がp95で8秒以内。入力認識のpartial表示・final確定も分けて計測。
- 評価データに対する質問検知率、誤提案率、ソース根拠の正確性を記録。数値の閾値は最初の評価セットで決める。
- 音声収集中とクラウド送信中の状態をUIから確認可能。停止操作後はキャプチャ/送信を止める。
- 保持しない設定では会議音声・文字起こしを自動永続化しない。保存設定がある場合は削除できる。
- デスクトップにAPI秘密鍵を埋め込まない。デバッグログに会議本文・秘密情報を出さない。

## 5. テスト計画

| 種別 | テスト内容 |
|---|---|
| 単体 | 文末確定、重複排除、Partialの更新、確定順序、Stop/再開時刻、会議状態遷移 |
| 音声統合 | マイクのみ、システム音声のみ、両方、無音、同時発話、ヘッドフォン切替 |
| 翻訳回帰 | 既存翻訳タスク、用語保護・プロファイル、Markdown形式、開始停止 |
| AI評価 | 事前に正解を定義した日本語/英語会議テキストで質問・矛盾・決定候補を検出 |
| RAG評価 | 登録した資料を参照した回答と根拠の一致、未登録情報への不正な断定を検出 |
| 耐久性 | 60分連続動作、ネットワーク断、APIタイムアウト、連続Start/Stop、会議アプリ終了 |
| セキュリティ | 権限拒否時挙動、送信OFF時の通信なし、秘密鍵/ログ露出、ファイル削除、メモリ破棄 |
| UI単体・スナップショット | Conference/Meeting各画面の状態別描画、同一モック状態の画像差分、ダーク/ライト両対応 |
| UI実機・アクセシビリティ | 14インチ画面、狭いウィンドウ、拡大文字、VoiceOver、キーボード、画面共有時の表示確認 |

テスト用録音は自作または利用許諾が明確な素材を使用する。参加者の許諾なく実会議を保存・クラウド送信しない。

## 6. リスク・設計上の論点

| リスク | 重要度 | 対応 |
|---|---|---|
| **ScreenCaptureKitの音声範囲・許可** | 高 | 該当アプリの音声を正しく取得できるか、実機で先行検証。画面取得権限を求めるUIを明示 |
| **CoreAudio TapとApp Sandbox** | 高 | 実験ブランチ/PoCで検証。Sandbox無効化や配布方針変更は製品判断なしに行わない |
| **2系統のオンデバイス認識負荷** | 高 | CPU/メモリ、温度、バッテリー、遅延を計測。必要なら認識系統・方式を切替可能に |
| **同時発話・エコー・入力重複** | 高 | 入力元タグ/時刻合わせ、ヘッドフォン推奨、重複検知、利用時の注意表示 |
| **AI提案の誤り** | 高 | 根拠提示、確信度らしい数値を安易に表示しない、候補状態、手動確定のみ |
| **プライバシー/会議相手の同意** | 高 | 明示的な権限・外部送信許可、不要データを送らない、保存はオプトイン |
| **字幕/翻訳の回帰** | 中 | Legacyモードを残し、イベントモデルをアダプタで接続。既存テスト + 操作試験 |
| **大幅なUI刷新による既存利用者の混乱** | 中 | 主要ショートカット・機能・保存形式を維持し、旧新対応表と移行テストを作成 |
| **フローティングUIが会議画面や共有画面を妨げる** | 中 | サイズ/表示状態の制御、フォーカス奪取なし、画面共有時の動作実機検証 |
| **クラウド遅延/コスト** | 中 | 発言単位でトリガー、抑制、キャッシュ、上限、手動Ask AI優先 |
| **言語切り替え・混在発話** | 中 | 最初は入力ごとに認識言語を手動指定。多言語自動切替は将来課題 |

## 7. 初期ディレクトリ追加案

```text
ConfLingo/
  Audio/
    AudioSource.swift
    MicrophoneAudioSource.swift
    SystemAudioCaptureService.swift
    AudioClock.swift
  DesignSystem/                       # PR5-B
    Tokens/
      ColorTokens.swift
      TypographyTokens.swift
      SpacingTokens.swift
    Components/
      SessionTransportControls.swift
      AudioSourceStatus.swift
      CloudSharingStatus.swift
      TranscriptTimeline.swift
      InsightCard.swift
      EvidenceLink.swift
      EmptyState.swift
  App/
    AppShellView.swift                 # PR5-B
    HomeView.swift
    SettingsView.swift
  Conference/
    Views/
      ConferenceLiveView.swift        # PR5-B
      ConferenceSetupView.swift
  Meeting/
    Models/
      TranscriptEvent.swift
      MeetingSession.swift
      MeetingInsight.swift
      MeetingDecision.swift
      KnowledgeReference.swift
    Services/
      TranscriptEventHub.swift
      MeetingSessionStore.swift
      ConversationEventDetector.swift
      InsightCoordinator.swift
      KnowledgeSearchService.swift
      MeetingExporter.swift
    Views/
      MeetingPreparationView.swift
      MeetingLiveView.swift
      MeetingFloatingPanel.swift      # PR5-C
      MeetingInsightsPane.swift
      MeetingReviewView.swift
  Sessions/
    Views/
      SessionHistoryView.swift
docs/
  design/
    app-information-architecture.md   # PR5-A
    design-system.md
    ux-states-and-flows.md
    mockups/                          # PR5-A: 採用済みモック・状態別比較資料
  Services/
    AudioCaptureService.swift          # 既存を段階的にAdapter化
    SpeechTranscriptionService.swift   # 既存をイベント発行型へ
    TranslationCoordinator.swift       # 維持
server/                              # PR6対象外。運営Proxyを実装する後続段階で追加
  src/
    index.ts
    routes/insights.ts
    services/llm.ts
    middleware/auth.ts
ConfLingoTests/
  Meeting/
    TranscriptEventHubTests.swift
    MeetingSessionStoreTests.swift
    ConversationEventDetectorTests.swift
    MeetingExporterTests.swift
```

> これはファイル設計案であり、現時点でこれらのファイルが存在するという意味ではない。

## 8. 実装順を決める判断基準

- **最初の最大の不確実性:** 内部音声の取り込みと、マイク+内部音声のオンデバイス同時文字起こし。
- **次の不確実性:** 十分な認識精度と低遅延でAI提案が本当に会議の役に立つか。
- **UI設計上の先行判断:** PR5-AでConferenceを含む全画面・状態を可視化し、実装前に採用モックを確定する。PR5-B/Cではそのモックを基準に比較する。
- **後回しでよい不確実性:** 商用RAG基盤、SaaS課金、ユーザー組織、外部サービス連携。
- Gate Bで2系統認識が失敗したら、ソースごとのSTTエンジン差し替えを試す。すぐにMacアプリや既存翻訳エンジン自体を作り直さない。
- Gate Cで提案精度が低ければ、UIを先に作り込まず、テストコーパス・イベント検知とプロンプトを修正する。

## 9. 最初の着手指示（Codex/Claude Code向け）

1. `main`を変更せず`feature/meeting-copilot`を作成する。
2. `README.ja.md`と現行のSwiftソース/テストを読み、`xcodebuild build` / `xcodebuild test`のベースラインを取得する。
3. 本計画のPR0→PR1から実装。既存翻訳機能の入出力を保ったまま、`TranscriptEventHub`を追加する。
4. PR3ではScreenCaptureKitのマイクとは別のシステム音声ストリームを作成し、単独キャプチャが動くか先に検証する。
5. PR4で2音声ソース・共通タイムライン・文字起こしを完成させる。権限拒否やソース切断でのエラー処理必須。
6. PR5-AをPR1〜4と並行して開始する。Conference/Meeting/Home/Sessions/Settingsの情報設計と主要状態モックを作成し、**UI承認をPR5-B/Cの着手条件にする**。
7. PR5-Bで共通デザインシステムとConference画面を刷新する。従来の翻訳・辞書・履歴・ショートカット・保存形式の無回帰を確認。
8. PR5-CでMeeting Preparation/Live/Reviewおよびコンパクト/展開フローティングUIを実装する。まずモックデータで表示/操作、次に実会話イベントへ結合。
9. PR6は最初にモックイベント・モックAIでE2Eを完成させ、次にGemini直接接続アダプタへ差し替える。実音声試験は延期し、実AIも合成会話テキストで検証する。
10. PRごとに変更点・回帰テスト・測定結果・残課題を記録する。実機テストが必要な項目を自動テスト合格と混同しない。

## 10. 成果物とGo/No-Go

### 初期PoCで得たいもの

- マイクと会議アプリ音声を取れるMacアプリ。
- 相手側の質問を認識してAIカードを出せる画面。
- 短い会話履歴と、固定した少量の資料に基づく回答候補。
- 認識・AI提案の速度、CPU/メモリ、誤提案の計測結果。

### 実用MVPで得たいもの

- 1時間の会議で破綻しない利用体験。
- General / Engineering / Salesの基本プリセット。
- 資料を根拠とする提案と、決定候補/アクション候補のユーザー確認。
- 会議後Markdown出力、保存・削除・送信の透明な制御。
- 既存Conference翻訳の無回帰。
- デザインシステム、Conference全面刷新、Meeting Copilotの各画面とフローティングUIが採用モックと一致すること。

**Go判断:** Gate A/Bを通過したらAI実装へ、Gate Cで支援価値を評価する。UIはPR5-Aでデザイン承認、PR5-B/CでGate Uを通過する。**Gate C/U/Dを満たして**招待制の実利用検証を始める。

---

### 技術参考（公式ドキュメント）

- Apple ScreenCaptureKit: https://developer.apple.com/documentation/screencapturekit
- Apple `SCStreamConfiguration.capturesAudio`: https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/capturesaudio
- Apple Core Audio taps: https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps
- Apple `SpeechAnalyzer`: https://developer.apple.com/documentation/speech/speechanalyzer

2026-11-10: 実UIの複数発話で回答言語と不明/未定の逸脱を確認。ユーザー「修正して」により[混在文脈の品質修正](design/pr6-mixed-context-quality-fix.md)を承認。質問を末尾の独立partへ置き、複数発話の回帰評価を追加する。修正後280テスト・build/lint成功、新規24＋既存28要求の実API品質評価に合格。後続の[6要求の受入](validation/pr6-stop-acceptance.md)で修正後UI/Keychain、実受信後の公開停止操作3経路と再開を確認。ネイティブクリックの時刻相関・通常起動全体等は残り、PR6/Gate Cは未完了。
