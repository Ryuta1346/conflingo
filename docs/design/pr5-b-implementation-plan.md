# PR5-B — デザインシステム・Conference刷新 実装計画

2026-11-08 / **ユーザー「進めて」により計画承認済み・実装/自動検証済み（REVIEW）**。

PR5-Aの主要4画面（Meeting、Conference、Floating、Review）を画像提示した後、ユーザーから「OK」を受領。これをモックの方向性の承認として記録する。製品実装・各状態の実機受入・本計画の承認とは区別する。

## 目的と完成する範囲

承認された外観をSwiftUIの共通部品にし、Conferenceを「準備→字幕→停止/再開/書き出し」の一貫した体験へ刷新する。言語、用語辞書、文字起こし専用、既存設定値とMarkdown形式を維持する。

| 対象 | 本PRで完成する動作 |
|---|---|
| デザインシステム | Light/Darkの色、文字、余白、サーフェス、状態表示、空/エラー表示、操作部品 |
| App Shell | Home / Conference / Settingsの実装済み画面だけを表示。通常はサイドバー、狭幅は省スペースの切替 |
| Home | Conferenceへの開始導線。履歴一覧やMeetingの未実装項目は表示しない |
| Conference準備 | セッション名、認識言語、翻訳先、専用モード、高速確定、辞書管理、モデル準備/非対応/復帰案内 |
| Conference字幕 | 通常幅で原文/翻訳の左右表示、狭幅で上下表示、専用モード1ペイン。途中/確定/翻訳待ち/翻訳失敗を区別 |
| 操作 | Start/Stop/停止再試行、設定へ戻る際の停止確認、停止後Clear確認、Markdown保存、文字拡大、最前面 |
| Settings | 既存の表示設定・辞書への導線、既存ショートカットの案内。実体のないAI設定は追加しない |

Meeting、Floating、AI、Sessions永続化、ローカル資料検索は5-C/6/7/8へ引き継ぐ。既存の2つの音声検証ウィンドウと入力競合防止を維持し、製品ナビゲーションに未実装のリンクを出さない。

## 現行コードから確認した制約

- `ContentView`が`SessionStore`、`SessionController`、`TranslationCoordinator`、`ModelAvailabilityService`、`KeywordProfileStore`を保持し、`.task`と`.translationTask`でモデル準備・翻訳を行う。子画面ごとの再生成へ移すと会話と処理を失う危険がある。
- `SessionPhase`はidle/preparing/listening/stopping。`SessionController.isStopping == false`かつstoppingは再試行可能な停止失敗を表す。UI独自の「停止済み」を別に持たない。
- `SessionController.stop()`はlistening/stoppingで有効。開始準備中にstopが完了したと見せて遷移してはいけない。
- `KeywordProfileStore`はUserDefaultsに既存キーで永続化し、最後の辞書を削除させない。移設によるキー変更・リセット・新しい移行処理は不要。
- 認識言語と翻訳先は`LanguageCatalog`と実行時の対応リストを使う。モックの日英固定サンプルを製品の言語制約にしない。
- `ControlBar`内にNSSavePanelとMarkdown書き出しがある。保存時の名前・日時・units/segments・言語の渡し方をそのまま引き継ぐ。
- Xcodeは同期ルートグループを使う。新しいSwiftファイルのためだけに個別のpbxproj参照を大量追加しない。

## 構成と変更候補

ファイル名は役割を示す案。責務が増えない限り、独立クラスやプロトコルを新設しない。

| ファイル/領域 | 変更 |
|---|---|
| `ConfLingo/Views/ContentView.swift` | 安定したルートとして既存の状態・準備・翻訳処理の所有を保ち、App Shell/各表示へ注入。翻訳ループを画面の条件分岐の外側に置く |
| `ConfLingo/App/AppShellView.swift` | Home/Conference/Settingsと現在地。表示状態だけを管理する。業務データのコピーを持たない |
| `ConfLingo/App/HomeView.swift`, `SettingsView.swift` | 実装済み操作だけの入口・設定。既存設定Bindingを共有 |
| `ConfLingo/DesignSystem/` | 色/文字/余白の定義、状態ラベル、空/エラー、必要な共通ボタン・パネル。Meeting専用部品を先行実装しない |
| `ConfLingo/Conference/Views/ConferenceSetupView.swift` | 言語・モード・セッション名、辞書管理導線。準備/失敗から設定変更と再試行へ戻れる表示 |
| `ConfLingo/Conference/Views/ConferenceLiveView.swift` | 字幕のレイアウト、表示操作、入力状態、設定変更導線 |
| `ConfLingo/Conference/Views/KeywordProfileEditor.swift` | 選択・用語編集・追加・改名・複製・削除。既存storeへ操作を渡す |
| `ConfLingo/Views/TranscriptPane.swift` | 時刻がある場合の表示、途中/確定/待ち/失敗ラベル、選択コピー、読み返し時のスクロール追従制御 |
| `ConfLingo/Views/ControlBar.swift` | 操作配置と外観を刷新。既存start/stop/exportの境界を維持。分割後に不要になった旧描画を除去 |
| `ConfLingo/Views/SetupView.swift` | 対象の認識言語名を表示し、固定の「英語」文言を解消。進捗不明時は割合を表示しない |
| `ConfLingo/ConfLingoApp.swift` | 新ルートと通常ウィンドウ寸法、既存最前面設定の接続。既存音声検証Windowを維持 |
| `ConfLingoTests/` | 遷移/停止失敗/状態保持など、新規に発生する振る舞いのテスト。既存テストを再利用 |
| `docs/usage.ja.md`, `docs/usage.md`, `docs/design/`, `docs/validation/` | 実装前に契約を更新、実装後に操作案内・比較画像・検証証跡を反映 |

## 操作契約

1. 状態と翻訳の所有者はルートで存続する。設定シートの開閉、サイドバー、狭幅レイアウト変更でStore/Controllerを作り直さない。
2. 言語・専用モード・高速確定・辞書変更はidleでのみ可能。認識中に設定変更を要求したら確認→既存stopをawait→idleを確認して移動。キャンセルや停止失敗では字幕画面に留まる。
3. preparing中は開始の重複と遷移を抑止し、準備中の表示を出す。stopping中も遷移/Clearを抑止。停止失敗では再試行を出す。
4. セッション名・既存字幕・翻訳結果は停止や画面移動で消去しない。Clearはidleで確認後のみ。保存キャンセル/書込失敗でも内容を保持する。
5. 原文と訳文は1対1に対応するとは限らない。訳文は文単位で複数segmentをまとめる現行仕様を保持し、見た目の行揃えのために偽の対応関係を作らない。
6. 過去字幕を読んでいる間は新しい字幕で強制移動しない。「最新へ」で追従を再開する。原文/訳文は独立して扱う。
7. 翻訳待ち/失敗は訳文側の状態として表示し、原文収集の停止と混同しない。UIの状態表示は実際のmodel/store/controllerの結果から作る。
8. `fontSize`、`alwaysOnTop`、言語ID、モード、辞書のUserDefaultsキーを維持する。フォントサイズ10〜48、⌘R、⌘＋/⌘−を維持。モック初期値で既存設定を上書きしない。
9. 通常幅では左右字幕、狭幅では上下字幕を使う。高さ不足時は本文をスクロールでき、停止操作は画面内に残す。色のみで状態を伝えない。
10. 実ウィンドウ閉鎖/再表示や検証画面との競合も確認対象にする。新しい閉鎖制御が必要な場合は既存開始停止契約の範囲で実装し、失敗を成功扱いしない。

## 実施順序

1. **資料:** 本計画承認後、専用ブランチ`feature/design-system-conference`を用意。現在の未コミット設計資料を保全し、作業開始時の差分を記録する。承認済みPR5-A画像を比較基準にし、仕様の変更理由を記録する。
2. **Red:** 画面遷移で状態が失われない、停止成功まで遷移しない、停止失敗から再試行、Clear取消で保持、非idle設定抑止の振る舞いをfakeでテストし、意図した失敗を確認する。新しいロジックがない見た目の色/余白を検査するだけの単体テストは増やさない。
3. **Green:** まず状態所有を維持した表示分離。次に必要なトークン/部品、準備画面、字幕画面、設定/辞書/保存を実装する。各段階で関連テストを通す。
4. **Refactor:** 旧の重複描画/未使用Binding/不要なファイルを除去。音声/Hub/翻訳のロジックを書き換えない。表示分離に必要な依存注入は最小限にする。
5. **検証:** Debug build、関連テスト→全テスト、SwiftLint、diff check。実音声を開始しない描画fixture/Previewを用いてLight/Dark、狭幅、長文、拡大、空/準備/失敗を確認する。可能な非録音のネイティブ操作も確認する。
6. **報告:** モック比較画像、実行コマンド/結果、差分理由、実機未検証を記録。実音声延期は維持し、承認なしの録音・再生・実認識を行わない。コミットはユーザー明示指示がある場合のみ。

## 受入条件と検証

| ID | 合格条件 | 検証 |
|---|---|---|
| B01 | Home→準備→字幕、停止後の設定/再開で履歴・名前・設定を保持 | fakeを用いた状態/遷移テスト、ネイティブ非録音fixture |
| B02 | 開始待ち/停止待ちの二重操作を抑止、停止失敗時は遷移せず再試行 | SessionController既存テスト＋新しい遷移テスト |
| B03 | 全対応言語・同一言語衝突解決、専用モード・高速確定を維持 | LanguageCatalog既存テスト、UI選択確認 |
| B04 | 辞書CRUDと選択・用語を維持。最後の辞書削除不可 | KeywordProfileStore既存テスト＋UI操作 |
| B05 | partial/final/翻訳待ち/失敗を識別し、文単位翻訳を保持 | 合成イベント/描画fixture、既存翻訳回帰 |
| B06 | Clear取消、書き出し取消/失敗で内容を保持。既存Markdownを維持 | 既存MarkdownExporter snapshot、保存ダイアログ確認 |
| B07 | 表示幅/画面変更で認識・翻訳所有者を再生成しない | 保留翻訳を含む状態保持テスト、画面移動の確認 |
| B08 | 通常1280×800、720×560、Light/Dark、字幕最大48ptで操作に到達できる | ネイティブ描画/スクリーンショット比較。高さ不足は縦スクロール可 |
| B09 | ⌘R・⌘＋/⌘−・最前面、選択コピー、読み返し/最新への復帰 | 非録音fixture、キーボード/フォーカス確認 |
| B10 | 既存2音声検証ウィンドウと入力競合防止に回帰がない | AudioInputUse/DualLifecycle等の既存テスト |
| B11 | build/test/lint成功、未実装項目と検証用fakeが通常製品UIに現れない | 全自動検証、通常起動の画面確認 |

VoiceOver、ウィンドウ閉鎖/再表示、設定変更時の実モデル取得、実音声認識/翻訳、音声停止はそれぞれ実施可否と結果を分けて記録する。モック一致や自動テストだけでGate A/U全体を合格としない。

## 承認対象

このPRの実装範囲、既存処理を保持する構成、操作契約、TDDと検証範囲。2026-11-08に承認後の実装を完了。結果と未検証項目は[検証記録](../validation/pr5-b-conference.md)を参照。PR5-Aのデザイン承認を、未提示だった本計画の承認として扱わない。
