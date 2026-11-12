# 両モード共通の資料・発話支援 — 実装・検証記録

2026-11-12 / `feature/shared-session-assistance` / ローカル実装・検証済み

ユーザー「1」でWebを含む範囲、「進めて」で実装計画を承認。その後の「ウェブ調査はllmの範疇で対応」に従い、独立したBrave検索と専用キーを廃止し、選択中LLMのWeb検索へ変更した。[現在の計画](../design/shared-session-assistance-plan.md)。

## 現在の実装

- Conference / Meetingの両方で資料＋確定発話への手動質問・自動提案・手動Web調査を利用できる。準備画面でマイク/外部入力、システム音声、両方を選べる。Conferenceの広幅画面では字幕の横に支援を表示する。
- Web調査は既存LLMの接続・モデル・キーを共用する。Geminiの`google_search`、OpenAI Responsesの`web_search`、Claude Messagesの`web_search_20250305`に接続する。モデル・契約の検索対応は実APIでの確認が必要。Kimi/DeepSeek/その他互換/ローカルの接続は、本実装ではWeb調査未対応と表示する。通常の資料・発話支援は維持する。
- 調査内容、選択/直近の発話（最大30件・12,000文字）、関連資料（最大5箇所・6,000文字）をLLMへ送る。LLMが検索語を決め、文脈を検索に使う可能性を許可画面へ明記した。音声は送らない。
- 1操作1LLM要求、同時1件、自動再送なし、全体60秒、初期20操作/セッション。OpenAIは`max_tool_calls=1`、Claudeは`max_uses=1`を指定。モデル内部の検索回数や料金を操作数で保証しない。取消した要求も操作数に含む。
- 完了したJSON応答だけを受理する。プロバイダの検索実行証跡と出典メタデータがない、打ち切り/未完了、未知のローカル引用ID、不正なURL等は成功扱いにしない。本文で生成されたURLから出典を作らない。
- APIの引用位置にクリック可能なWeb参照番号を表示する。発話/資料の引用は要求に実在するIDだけ許可する。Web引用は最大20件まで受理し、超過時は切り捨てずエラーにする。Geminiの引用位置はUTF-8バイト位置、OpenAIは文字位置として扱い、日本語/絵文字も検証した。
- Geminiが返す検索候補HTMLも表示・明示保存する。WebViewは非永続、ページJavaScript無効、コンテンツルールで自動外部読込を禁止し、利用者のHTTP(S)リンククリックだけ既定ブラウザへ渡す。HTMLは64KiB以下。
- 回答と発話/資料/Web引用は保存・再閲覧・Markdownに対応する。Webページ本文や生の検索レスポンスを保存しない。取得時刻は公開日ではない。保存時に検索候補HTMLを保持するが、MarkdownにはHTMLを実行可能な形で出力しない。
- 既存の取消・設定/資料変更による許可解除・遅延結果排除を維持した。Braveクライアント、専用設定/Keychainアクセス、2段階の検索→LLM生成、外部抜粋向けJSONスキーマを除去した。

## 検証結果

macOS 26.5.2 / arm64。実API・実録音を使うテストは有効化していない。

| 検証 | 結果 |
|---|---|
| 全テスト | **542件中536件成功、6件skip、失敗0**／96 suites。xcresultで確認。パラメータ展開後は761成功・6skip |
| Lint | SwiftLint 0.65.1、`lint --strict --no-cache`。217ファイル、違反0 |
| Debug | 全テストを含めビルド・実行成功 |
| Release | `CODE_SIGNING_ALLOWED=NO`でビルド成功。署名・配布は未実施 |
| 画面描画 | 合成データによるConference 1440×900とWeb調査520×720ライト/ダーク。別キー入力を削除し、インライン引用が表示されることを画像で確認 |
| 差分 | `git diff --check`成功 |

6件skipは既存の明示的に有効化する実モデル評価。今回の成功件数に実API品質評価を含まない。Braveを使う前段階の検証は534成功・6skipだったが、現在の回帰結果は上表に置き換える。

| テスト | 確認内容 |
|---|---|
| `LLMWebResearchTests` | 3プロバイダの接続先/モデル/認証/検索ツール、1操作1要求、未対応接続の無送信、検索出典なし・不完全応答・不正URL・未知発話引用の拒否、日英/絵文字の引用リンク、保存と出力、検索候補のナビゲーションデリゲート登録 |
| `WebResearchTests` | 許可前無送信、発話＋資料の文脈、選択した過去発話、入力上限、取消/呼出元取消、モデル/キー/資料/セッション変更後の遅延排除、期限、操作回数上限、未対応接続 |
| `ResearchTransportTests` | URLProtocolの模擬HTTPで200 JSON、401/403/429/500/302、HTML拒否、256KiB受信上限、自動再送なし |
| `SharedAssistanceTests` | 両モードの資料/発話支援、Conference自動提案、入力3構成、system-onlyでマイク権限不要、停止時確定、再開時刻と言語、保存/Markdown、Meetingの録音前質問 |
| 既存全体 | 字幕/翻訳、資料/ライブラリ、候補/要約、停止/再開、旧保存形式等の回帰 |

TDD: 新しいLLM検索契約の未実装をREDで確認後、要求/応答を実装。検索候補のWKNavigationDelegateがSwiftの関数型差異で登録されない問題をテストで再現し、修正後に全体GREENを確認した。前段階で修正した録音再開時の支援用時刻巻き戻り、Conferenceの発話付き回答保存、Meetingの回答出力も維持している。

## 再実行と証跡

```sh
xcodebuild test -project ConfLingo.xcodeproj -scheme ConfLingo \
  -destination 'platform=macOS' -derivedDataPath /tmp/conflingo-shared-build \
  CODE_SIGNING_ALLOWED=NO
swiftlint lint --strict --no-cache
xcodebuild build -project ConfLingo.xcodeproj -scheme ConfLingo -configuration Release \
  -destination 'platform=macOS' -derivedDataPath /tmp/conflingo-shared-release \
  CODE_SIGNING_ALLOWED=NO
```

SwiftLintはPATHにないため`/tmp/conflingo-swiftlint-0.65.1/swiftlint`を使用。Swiftマクロ/xcresultのキャッシュ書き込みにはサンドボックス外実行が必要だった。既存の旧Keychain API・Releaseプレビュー分岐等の警告は残る。今回追加したWebKitデリゲート警告は解消した。

- テスト: `/tmp/conflingo-native-final-tests.log`
- xcresult: `/tmp/conflingo-shared-build/Logs/Test/Test-ConfLingo-2026.11.12_20-57-19-+0900.xcresult`
- Lint: `/tmp/conflingo-native-lint.log`
- Release: `/tmp/conflingo-native-release.log`
- 描画: `/tmp/conflingo-conference-wide.png`、`/tmp/conflingo-research-light.png`、`/tmp/conflingo-research-dark.png`

## 未評価・残る受入

- 実LLMのWeb検索権限・接続・料金・回答品質、実Google検索候補HTMLの表示。公式API形式を模した応答で検証しており、実モデルで検索成功を確認したという意味ではない。
- 新しい入力選択の実機マイク/外部機器/システム音声/両方、切断・再接続、Zoom/Meet/Teams別の音声品質。
- 日英の品質評価（根拠あり/なし/矛盾/日付/埋込指示/複数根拠）、文字拡大・キーボード/VoiceOver・全幅/全状態・長時間性能。引用ID検証やプロンプトだけで事実性・注入耐性は保証しない。
- Meetingのセッション保存は既存どおり会議終了後。Conferenceは音声がなくても完成回答を保存できる。

実API評価を追加する際は素材・接続先・要求数・費用上限を具体化する。使い方は[日本語ガイド](../usage.ja.md#webで調べる)を参照。

公式仕様確認: [Gemini Search grounding](https://ai.google.dev/gemini-api/docs/generate-content/google-search)と[引用位置のバイト定義](https://ai.google.dev/api/generate-content#Segment)、[OpenAI Web search](https://developers.openai.com/api/docs/guides/tools-web-search)、[Claude Web search](https://platform.claude.com/docs/en/agents-and-tools/tool-use/web-search-tool)。
