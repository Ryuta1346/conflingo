# DR3 デザインシステム部品化の検証（2026-11-15）

対象: main `a34283c`（DR2・PR #47マージ済み）への未コミット差分。ユーザーの「進めて」により[計画](../design/dr3-design-system-plan.md)を承認後に実装した。ローカル実装・自動検証済み、状態は **REVIEW**。マージ・網羅的な実機受入の完了とは扱わない。

## 実装した内容

- **文字（D04）:** タイトル24pt、見出し17pt、本文14pt、補助・注記12ptを共通化。製品コード35ファイル・161箇所のcaption／caption2指定を置換した。送信対象・件数・送信先・許可の説明は14pt・本文色に揃え、本文の文字サイズ設定と送信許可の挙動を維持した。
- **ボタン（D06）:** `AppButtonStyle`の主要／通常／破壊／リンクを導入。終了・削除・字幕消去はdestructive role、停止の再試行は通常、根拠への移動はリンクに揃えた。主要ボタンの文字はライトで白、ダークで濃色にし、両配色のコントラスト比4.5:1以上を検証した。選択ナビ・Picker・Toggle・システム確認ダイアログは既存のネイティブ操作を維持した。
- **メッセージ（D07）:** `UserMessage`と`InlineMessage`で情報／成功／警告／失敗を記号と文章で表示。状態所有元で種別を決め、文面から推定しない。日本語の影響・復帰案内とシステム詳細を分け、詳細は初期状態で閉じる。保存、資料取込・検索・用語抽出、接続・キー、AI支援・Web調査、翻訳準備、音声入力などに適用し、`SessionErrorBanner`を削除した。永続形式の変更はない。
- **共通寸法・シート（D15・D16）:** 操作角丸7pt・余白4/8/12/16/24/32を定義し、変更部品・シートへ適用。閲覧シートの右上に閉じる、編集フォームの右下にキャンセル／確定を配置した。LLM設定の外枠を共通化し、通常幅680ptから利用可能幅へ縮め、内部をスクロール可能にした。
- **回帰修正:** Conferenceの低いウィンドウで設定・字幕消去のフォーカスへスクロールを追従させた。Meetingレビュー欄は新しい文字・操作の高さに合わせてヘッダー等の確保量を80ptから96ptへ変更。翻訳失敗の短い行内案内を調整し、原文・訳文の予約高さを維持した。

## 最終検証

macOS 26.5.2 / Xcode 26.6 (17F113)、SwiftLint 0.65.1。fake状態、合成発話、一時保存先を使用し、実API送信・実音声取得は行っていない。

| 確認 | 結果 |
|---|---|
| 非live全テスト | **743テスト・133スイート成功、38.152秒** |
| SwiftLint | **287ファイル、違反0** |
| Releaseビルド | **成功、arm64・x86_64をlipoで確認** |
| 差分の空白検査 | `git diff --check`成功 |
| 旧表示の残存検索 | 製品コードのcaption／caption2、borderedProminent、SessionErrorBannerは0件 |
| ネイティブ描画 | 5幅×2モード×2配色20枚、共通部品2枚、設定1枚、低いウィンドウのフォーカス5枚を保存 |

実行コマンド:

```sh
SWIFTLINT_BIN=/private/tmp/conflingo-swiftlint-0.65.1/swiftlint \
CONFLINGO_CI_OUTPUT_DIR=/private/tmp/conflingo-dr3-baseline \
bash scripts/ci.sh all
```

新規12テスト定義（パラメータケースを含む）は、保存・取込・キーの失敗と復帰、秘密情報の非表示、詳細の開閉と更新時の折り畳み、取消の情報表示、4様式のenabled／disabledと1回だけの実行、キーボードフォーカスとSpace操作、コントラスト、送信説明、設定シートの閉じる位置・無送信、低いConferenceのフォーカス追従を検証した。キーボードテストはネイティブの次フォーカス移動とSpaceのキーイベントを使う。

既存の終了・削除確認、資料許可・世代判定、翻訳再試行、狭幅の根拠リンク、下書き保持、シート・オーバーレイのEscapeとフォーカス復元を含む回帰テストも成功した。ただし、すべての実画面での手動操作を実施したという意味ではない。

## TDDと途中の失敗

| 証跡（ローカル一時ログ） | 失敗・対応・結果 |
|---|---|
| `/private/tmp/conflingo-dr3-red.log` | 新しい表示モデル・部品を参照するテストを先行追加し、未定義によるコンパイル失敗を確認。実行時のアサーション失敗ではない。実装後の`conflingo-dr3-core.log`で当初の6定義が成功 |
| `/private/tmp/conflingo-dr3-presentation-red.log`、`conflingo-dr3-presentation-green.log` | シート幅を調整した後も`fittingSize`の検査が失敗。理想サイズを実表示寸法として比較していたテスト側の誤りを特定し、ホストの実フレームと閉じるボタンの画面内位置を検査する形へ修正。両ログを製品不具合の証拠としては扱わない |
| `/private/tmp/conflingo-dr3-focus-red.log` | 640×520のConferenceで字幕消去へフォーカスしても固定バーの下に残る問題を再現。ScrollViewReaderと既存RevealOnFocusを適用し、`conflingo-dr3-focus-green.log`の6定義・2スイートが成功 |
| `/private/tmp/conflingo-dr3-all.log` | 初回全体実行で翻訳失敗・再試行表示の予約高さが1pt増え、Meetingレビュー本文の高さが最小値より5pt不足。失敗案内の短縮とレビュー欄の高さ確保を修正。既存の期待値は緩めず、`conflingo-dr3-regression-fix.log`の10定義・2スイートが成功 |
| `/private/tmp/conflingo-dr3-keyboard.log` | 4様式のキー操作を追加検証し、7定義・1スイートが成功 |
| `/private/tmp/conflingo-dr3-final.log` | 修正後の全テスト・Lint・両CPU Releaseが成功 |

当初のsandbox内ビルドはSwiftマクロを起動できず失敗したため、承認された制限外実行で検証した。詳細は[事前確認](dr3-baseline-2026-11-15.md)に記録。初回失敗のxcresultは削除せず保存した。

## 画面証跡

以下はNSHostingViewによる合成ネイティブ描画。会議本文はfixtureであり、実会議の記録ではない。画面端に見える本文の切れ目にはスクロール位置によるものが含まれる。全20枚の取得とレイアウト検査に加え、代表の通常幅・狭幅・共通部品・設定・フォーカス画像を目視した。

| 幅 | Meeting | Conference |
|---|---|---|
| 640pt | [ライト](dr3-after/meeting-640-light.png)・[ダーク](dr3-after/meeting-640-dark.png) | [ライト](dr3-after/conference-640-light.png)・[ダーク](dr3-after/conference-640-dark.png) |
| 900pt | [ライト](dr3-after/meeting-900-light.png)・[ダーク](dr3-after/meeting-900-dark.png) | [ライト](dr3-after/conference-900-light.png)・[ダーク](dr3-after/conference-900-dark.png) |
| 1180pt | [ライト](dr3-after/meeting-1180-light.png)・[ダーク](dr3-after/meeting-1180-dark.png) | [ライト](dr3-after/conference-1180-light.png)・[ダーク](dr3-after/conference-1180-dark.png) |
| 1280pt | [ライト](dr3-after/meeting-1280-light.png)・[ダーク](dr3-after/meeting-1280-dark.png) | [ライト](dr3-after/conference-1280-light.png)・[ダーク](dr3-after/conference-1280-dark.png) |
| 1512pt | [ライト](dr3-after/meeting-1512-light.png)・[ダーク](dr3-after/meeting-1512-dark.png) | [ライト](dr3-after/conference-1512-light.png)・[ダーク](dr3-after/conference-1512-dark.png) |

- 共通部品・4種メッセージ・送信説明: [ライト](dr3-after/components-light.png)・[ダーク](dr3-after/components-dark.png)。送信範囲の最大30件、資料の最大5箇所・6,000文字、送信先URLを保持し、説明が折り返されることを確認。
- LLM設定: [640×520](dr3-after/llm-settings-640.png)。右上の閉じる、本文の折り返しを確認。
- 低いMeetingの入力フォーカス: [本文16pt](dr3-after/meeting-focused-16.png)・[32pt](dr3-after/meeting-focused-32.png)・[48pt](dr3-after/meeting-focused-48.png)。
- 低いConferenceの字幕消去フォーカス: [本文16pt](dr3-after/conference-focused-16.png)・[48pt](dr3-after/conference-focused-48.png)。固定の再開バーより上へ表示されることを確認。

## 残る確認・対象外

- 独立した担当者によるコードレビューは未実施。コミット・PR作成・マージは未実施。
- 通常アプリを通した全画面・全状態の手動操作、全シートの長文・狭幅・Escape／起点フォーカスの網羅確認は継続。合成ホストでの代表確認を全経路の受入とは扱わない。
- VoiceOverの実操作は既存のユーザー指示どおり保留。実音声・実API・配布署名での受入、OS設定別の高コントラスト等は今回未実施。
- D15は共通部品と変更したシートへの適用。既存の個別画面のspacing・角丸など全数のトークン置換は行っていない。DR2のナビ幅・レイアウト境界・小窓寸法は維持した。
- D16は外枠と操作位置の統一。Conference資料シートの機能分割、送信範囲パネルの共通化、メニューやReturn、文字サイズ適用の拡張はDR4に残る。
- 新しい主要ボタンのコントラストは検証済みだが、D21の全状態・全画面の実機受入が完了したとは扱わない。

最終成果物: `/private/tmp/conflingo-dr3-baseline/`の`lint.log`、`test.log`、`tests.xcresult`、`release.log`、`architectures.log`。途中の失敗は同ディレクトリの`sandbox-failed-tests.xcresult`・`first-all-failed-tests.xcresult`に保持。画像は本記録と同じリポジトリ配下へ保存した。
