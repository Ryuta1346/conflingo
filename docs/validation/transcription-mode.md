# 開始モードと訳文領域の検証

2026-11-12。仕様: [開始モードと訳文領域](../design/transcription-mode.md)。

## 実装

- Meeting / Conferenceの準備画面を「文字起こし / リアルタイム翻訳」の2択に統一。新規セッションは文字起こし、一時停止・再開は選択を維持する。
- 翻訳先の言語設定とモードを分離。旧Conferenceの永続設定 `transcriptionOnly` は参照せず、既存設定が翻訳有効でも新規セッションは翻訳しない。
- Meetingは翻訳対象の認識途中の発話にも訳文欄を用意。過去に文字起こしのみで確定した発話へ、切替だけで翻訳待ち欄を後付けしない。
- Conferenceは2ペインを維持し、認識途中・文の確定待ち・翻訳単位に原文に応じた予約高さを設定する。
- 共通のSwiftUI Layoutが原文の折返し＋1行、最低約2行分と実際の内容の高さから表示高を決める。同じ幅・文字サイズでは高さを縮めず、失敗・再試行・短い訳文への差替えで後続項目を引き上げない。
- 訳文が予約高を超えた場合は全文が収まるまで広げる。文字サイズ・幅が変わった場合は再計算する。予約用の非表示テキストはアクセシビリティから除外する。

## テスト結果

| 検証 | 結果 |
|---|---|
| Red | 旧実装で新規Meetingが翻訳を要求すること、および翻訳到着時に高さが16ptフォントで30pt・32ptフォントで111pt変化することを検出 |
| 初回Green | 13テスト・4スイート成功 |
| 全回帰 | 511テスト・91スイート成功（Swift Testingの集計）。外部AIの実API評価6件は既定でスキップ |
| 最終表示調整後 | TranslationReservationTests / TranscriptPresentationTests / ConferenceLayoutTests、8テスト・3スイート成功 |
| SwiftLint 0.65.1 | strict / no-cache、203ファイル、違反0件 |
| git diff --check | 成功 |
| Release build | 最終差分で成功（CODE_SIGNING_ALLOWED=NO） |

開始モードのテストは、新規Meetingの翻訳呼出し・翻訳準備レーンが0件であること、停止時の最終原文を出力できること、翻訳選択後の片側無効、一時停止・再開、新しい会議へのリセット、Conferenceの翻訳モデル不要を検証した。

表示のテストは、幅280ptで16/24/32ptの文字、認識途中→確定、翻訳待ち→完了、失敗→再試行、予約領域を超える長文、短文への差替え、文字サイズ変更を検証した。既存の通常Meeting・小窓・Conferenceのリサイズと履歴閲覧位置の回帰テストも成功した。

## 実画面確認

ビルドしたDebugアプリの `--meeting-preview --scenario setup` を使用し、音声取得や実AI送信を行わず確認した。

- Meetingの初期選択が「文字起こし」、翻訳先は非表示。
- 「リアルタイム翻訳」を選ぶと入力別の翻訳先と説明を表示。
- Conferenceも同じ選択UIを表示。「文字起こし」で翻訳先を隠し、高速確定を表示。
- Conferenceの合成字幕で原文・訳文の2ペイン、全文と予約余白を確認。

実音声・実翻訳エンジンでの遅延や精度は今回再検証していない。翻訳表示の遅延はテスト用翻訳器で再現した。インストール済みアプリは更新していない。

## 再実行とログ

```sh
xcodebuild test -project ConfLingo.xcodeproj -scheme ConfLingo \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/conflingo-mode-build CODE_SIGNING_ALLOWED=NO
/private/tmp/conflingo-swiftlint-0.65.1/swiftlint lint --strict --no-cache
xcodebuild build -project ConfLingo.xcodeproj -scheme ConfLingo -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/conflingo-mode-release CODE_SIGNING_ALLOWED=NO
```

ログ: `/private/tmp/conflingo-mode-{red,green,all,final,lint,release}.log`。
最初のサンドボックス内ビルドはSwiftマクロの起動制約で失敗したため、その後は通常のXcode実行環境で検証した。
