# Sessions 永続保存 — 検証記録

2026-11-11 / main `294bd0c`をベースに検証。実装コミット `e95f8ae`、ブランチ `feature/session-persistence`、[Draft PR #21](https://github.com/Ryuta1346/conflingo/pull/21)（未マージ）。
ユーザー「1で」で対象選択、「進めて」で[計画](../design/sessions-implementation-plan.md)を承認。

**実装・自動検証・主要な無通信UI操作を確認。狭幅・拡大文字・キーボード全経路・VoiceOverの実操作は残る。**

## 実装

- Meetingの会議終了後とConferenceの停止後に「このMacに保存」。自動保存なし。
- 版付きJSONをSandboxのApplication Support配下の`ConfLingo/Sessions/<UUID>.json`に保持。1セッション1ファイル、ファイルI/Oはactorで直列化、置換はatomic。
- 一覧・日本語/英字の名前検索・Homeの最近5件・読み取り専用詳細・Markdown再出力・確認付き削除。
- Meetingの確定発話、完成カード、候補の確認状態、完成要約と資料引用を保存。資料名・相対パス・行・内容ハッシュ・snapshot ID・抜粋を保持。Conferenceの原文・取得済み訳文・未完了/失敗状態を保持。
- 音声、途中字幕、生成中カード、未完成要約、APIキー、送信許可、資料全文の検索索引は保存しない。再読込は実行中のworkspaceやcontrollerへ復元せず、録音・翻訳・AI送信を開始しない。
- 同一会議の再保存は更新、Clear/reset後は別ID。候補・要約・遅延翻訳が変われば再保存が必要と表示。保存中の重複操作・破棄を抑止し、遅延完了を別の内容の保存成功にしない。
- 保存/削除失敗では前の保存版を保持。破損・未知版・不正参照を拒否し、正常な他の記録は一覧に残す。

## 自動検証

| 検証 | 結果 |
|---|---|
| 最終全体 | **423テスト／70 suites成功、31.346秒** |
| Sessions追加 | **17テスト**。保存I/O、会議との境界、一覧状態、競合、障害、性能 |
| SwiftLint | **159ファイル・違反0**。0.65.1、`--no-cache --strict` |
| Debug | 最終全体テストのビルド成功 |
| Release | 成功。最終の保存中ControlBar無効化後にも再ビルド |
| 実API・実音声 | **0**。自動テストは全`CONFLINGO_`環境変数を除去 |

Red/Greenの記録:

1. `SessionSnapshot`未実装のコンパイル失敗→保存処理実装後5テスト成功。最初のsandbox内実行はSwift macro pluginの起動制限で失敗したためRedに数えず、通常Xcode権限で未実装による失敗を確認した。
2. `SessionsLibrary`・保存境界未実装による失敗→一覧・検索・保存状態を実装し9テスト成功。
3. 追加境界16テスト中、開始日時不明が1970年として出力される1件が失敗→MarkdownExporterの日時をoptionalにし、「未取得」として出力。既知日時の既存出力は全体テストで維持。
4. 保存中の競合テストを追加。保存中に変更された内容は未保存扱い、同時保存は受け付けず、破棄操作は抑止。最終423テスト成功。

S01〜S11は自動テストと下記UIで確認。S12は主要操作の確認までで、狭幅・拡大文字・キー網羅・VoiceOver実操作が未完了。

### 100件の合成データ

各240発話と資料引用・要約を持つ100セッションで、一覧読み込み**0.126030417秒**、1件の読み込み**0.001203959秒**。検索結果と件数を照合。

XCTestホストの既往最大常駐メモリ（`getrusage`）は一覧読み込みの前後とも285,491,200 bytes。全テスト並行実行中のプロセス最大値であり、Sessions単独の使用量、現在の常駐量、長時間のリークなしを意味しない。

ログは`/private/tmp/conflingo-sessions-{red,green,state-red,state-green,ui-green,boundary-red,full,final,release,final-lint}.log`。既存のKeychain非推奨、ReleaseのDEBUG分岐、AppIntentsメタデータ抽出に関する警告が残る。新規のソース警告は観測していない。

## ネイティブUI

別bundle ID `com.gavrri.conflingo.sessions-preview` のDebugコピー、`--meeting-preview --meeting-state=repository-review`を使用。fake音声・fake AI・fakeキー保存・アプリが作る架空のリポジトリだけを使った。保存先はプレビュー用の一時ディレクトリ。利用者の本番保存データは操作していない。

1. Meetingで「このMacに保存」→保存済み・ボタン無効化を確認。
2. 一覧で1件表示、日本語の部分一致、存在しない名前の空状態を確認。
3. 読み取り専用詳細に完成カード・確定発話を表示。発話根拠ボタンで該当発話へ移動。
4. 現在のMeetingに戻って発話・保存状態が保持されることを確認。
5. fakeの資料付き要約を生成し、「保存後に変更あり」を確認。明示再保存後、同じ記録に要約・補足・資料引用を表示。
6. 保存詳細の資料引用を開き、`ReviewService.swift`の相対パス・1–2行・内容ハッシュ・snapshot ID・保存した抜粋を確認。Escapeで閉じる。
7. 保存詳細からOS保存パネルで`/private/tmp/sessions-acceptance-2026-11-11.md`へ再出力。成功表示とファイル内の要約・補足・引用・12発話を照合。
8. 削除確認をEscapeで取消→詳細を保持。再度削除を確定→一覧から消去。元のMeetingの内容は保持され「未保存」に戻り、同じ内容を明示的に再保存できた。外部Markdownも残った。
9. Conferenceの合成字幕を開き、停止状態で原文・訳文を保存。Homeの最近の保存でConference、Meetingの順に表示。Conferenceの保存詳細で原文と訳文を閲覧。
10. Cmd+Q後のアプリ再選択で新しい未保存Meetingのプレビューに戻った。保存一覧には先のMeetingとConferenceが残り、先の開始/保存日時・完成要約・引用を再閲覧できた。

ネイティブUIに使ったDebug dylibのSHA-256は`c69b1a99cbd5e39cb8810cac7b3d6914af2b1764698a4f69e71e16250f914302`。全422テスト成功時点のコピー。後続の製品差分は保存処理中のConference ControlBar無効化1行で、最終423テスト・lint・Releaseの対象に含めた。

### 操作ツールの制約

- fake要約のボタンは、画面の通常文言を理由に自動承認レビューが一度拒否した。プロセス引数に`--meeting-live-ai`がないこと、`MeetingPreview`がネットワークを使わない`PreviewInsightClient`へ接続すること、コピーと検証ビルドのハッシュ一致を提示してから同じ操作を再試行し、許可された。実APIは0。
- 最初のアプリ選択に長い応答待ちが発生。その後の主要操作は観測できた。
- 狭幅確認のWindowメニュー操作が`element ID is no longer valid`になり、再取得・再選択でも復旧しなかった。狭幅・拡大文字・キーボード全経路・VoiceOverの実操作を合格扱いしない。通常幅の画面とAXツリー、検索、Escape、保存パネルのキーボード経路までを確認済みとする。

## レビューと完了範囲

単独で保存モデル・root/ファイル名・未知版・原子的書込み・同一ID更新・破損分離・削除対象・会議との分離・遅延処理・Markdown互換・引用保持を確認。独立レビュー/独立QAは未実施。

- 実装・自動検証・主要UI: 確認済み。
- 計画全体の受入: **S12の残りがあるため未完了**。UI網羅の最終QA判定は保留。
- 未実装の後続: 保存記録の編集/AI再生成、PDF/OCR、永続資料ライブラリ、自動保存/クラッシュ復旧/クラウド同期。
- 実音声結合・会議アプリ別・60分耐久・配布署名・既存Gate・請求照合は従来どおり残る。受入完了数2/12は変更しない。
- ユーザー「コミットしてPR作成」の依頼によりコミット・push・[Draft PR #21](https://github.com/Ryuta1346/conflingo/pull/21)作成済み。担当: Ryuta1346。マージは未実施。
