# Conference / Meeting 共通支援 — 実装計画と変更結果

2026-11-12 / ユーザー指示「ウェブ調査はllmの範疇で対応」による既存承認計画の修正。資料→テスト→実装→検証の順に変更済み。独立検索サービスの導入は撤回する。

- Brave検索、専用キー設定、検索→別LLM生成という2段階処理を削除する。登録済みLLMの接続先・モデル・認証をそのまま使う。
- GeminiのGoogle Search grounding、OpenAI Responsesのweb_search、Claude Messagesのweb_searchを接続する。モデル・契約の実対応はAPI応答で確認し、その他の接続はWeb検索未対応として表示する。通常の資料・発話AI支援は継続する。
- 1操作1LLM要求、手動開始、自動再送なし、全体60秒、初期20操作/セッション。OpenAI/Claudeはツール上限1を指定する。モデル内部の検索回数・課金は操作数と一致する保証がない。
- 調査内容・選択/直近の発話・関連資料をLLMへ送る。LLMが検索語を決め、文脈が検索へ使われる可能性を許可画面に明記する。検索語だけを外部へ送るという旧説明は削除する。
- 非ストリーミングの完了応答だけを受理。実行済みツールとAPI出典メタデータを確認し、検索未実行・出典なし・不完全応答は調査完了にしない。モデル本文中のURLを出典として採用しない。
- Web引用はAPIメタデータから本文のクリック可能な参照番号とURL一覧へ変換する。発話/資料は要求に含めたIDだけ引用可能。Geminiが返す検索候補表示も保持・表示する。本文・出典・検索候補を明示保存/出力へ接続する。
- 検索候補HTMLは非永続WebView、JavaScriptと自動外部読込を無効化し、利用者がクリックしたHTTP(S)リンクだけブラウザへ開く。
- 不要なBrave専用テストはLLMプロバイダ別要求/応答・出典/拒否・上限/取消・保存のテストへ置換。全テスト、Lint、Releaseビルド、主要描画を再確認する。実API/実音声評価は今回実施しない。

公式資料確認: [Gemini grounding](https://ai.google.dev/gemini-api/docs/generate-content/google-search)、[OpenAI web search](https://developers.openai.com/api/docs/guides/tools-web-search)、[Claude web search](https://platform.claude.com/docs/en/agents-and-tools/tool-use/web-search-tool)。検索サービス別キーを撤回する点はユーザー指定、それ以外の具体方式は実装判断。

## 維持した共通要件

- 用途（Conference/Meeting）と開催形式・音声入力を分け、両モードにマイク/外部入力、システム音声、両方を提供する。
- 準備中・実行中の資料登録/ライブラリ選択、資料＋発話への質問、自動提案を両モードで利用できる。Conferenceは字幕の横、Meetingは会話・論点の文脈で支援を表示する。
- 既存の字幕・翻訳・資料だけの質問・補正を維持し、回答の引用から発話/資料/Web出典へ戻れるようにする。
- 送信許可、入力上限、取消、資料/接続/セッション変更時の古い結果排除、保存/再閲覧/Markdownを継続する。旧保存形式は省略可能な新項目で読み取りを維持する。

## 実装と検証

ローカル実装済み。全542件中536件成功・実API評価6件skip、95から96 suitesへ増加。Lint217ファイル違反0、Debugテスト/Releaseビルド成功。WebKitリンク制御の未登録をテストで検出して修正し、日本語・絵文字を含むインライン引用と保存も確認した。

検証の証跡、未評価事項、公式API参照は[検証記録](../validation/shared-session-assistance.md)を参照。実APIの接続・回答品質、実音声の入力別受入、VoiceOver等の網羅操作確認は未実施。配布は行っていない。

正本: `~/.coding-agents/docs/conflingo/feature-shared-session-assistance/shared-session-assistance-plan.md`。

PR構成: 既存PR #27（`feature/transcription-default`）をベースとし、共通支援の変更だけを`feature/shared-session-assistance`へ切り出す。
