# DR3 事前確認（2026-11-15）

対象: main `a34283c`（DR2・PR #47マージ済み）。製品・テストコードを変更する前の確認。[実装計画](../design/dr3-design-system-plan.md)はこの事前確認時点では承認待ち。後続の承認・実装結果は[検証記録](dr3-design-system-2026-11-15.md)を参照。

## 確認結果

- macOS 26.5.2 / Xcode 26.6 (17F113)。既存の`WorkspaceRegionLayoutTests.captureApprovedWidths(width:isMeeting:)`を実行。
- **1定義・10ケース成功、8.764秒**。640／900／1180／1280／1512pt × Meeting／Conferenceをそれぞれライト／ダークで描画し、20枚を取得。fake AI・合成発話のみ使用。
- このテストは幅の収まりと画像取得を確認するもの。全回帰・Lint・ReleaseやDR3の受入成功を意味しない。今回の変更は計画・進捗・事前確認資料のみ。
- 最初のsandbox内ビルドは`sandbox-exec: sandbox_apply: Operation not permitted`に続いてSwiftマクロが起動できず、exit 65。承認された制限外実行で成功。製品のコンパイル不具合とは判定しない。

## 画像を見て確認したこと

- [Meeting 1280pt・ライト](dr3-before/meeting-1280-light.png): 提案・質問欄はDR2の配置。発話の時刻・入力元・補助文が小さい。根拠リンクが通常操作と同じ矩形ボタンで、終了と一時停止も近い見た目。
- [Conference 640pt・ダーク](dr3-before/conference-640-dark.png): 上部保存は折り返されている。字幕消去が通常操作と同じボタンの見た目。字幕内の一部文字はスクロール領域の境界にかかっており、今回の取得画像だけで文字欠けの原因を断定しない。
- このNSHostingViewの画像では通常ボタンや主操作が灰色に見える。元レビューの「全ボタンが青い」を現環境で再現できたとは扱わない。キーウィンドウ・非キーウィンドウの違いを含め、実装時に4様式の区別とダーク配色のコントラストを確認する。
- 送信説明・失敗・シート内部の状態は今回の既存テストの撮影対象外。実装時にfake状態を追加して別途確認する。通常アプリの網羅操作・実音声・実API・VoiceOverは未実施。

## 証跡

- 初回ログ: `/private/tmp/conflingo-dr3-baseline.log`
- 成功ログ: `/private/tmp/conflingo-dr3-baseline-native.log`
- xcresult: `/private/tmp/conflingo-dr3-baseline/native-tests.xcresult`
- 全画像: `/private/var/folders/xw/hvgffbv53gb1mzy10jtn3_xc0000gn/T/conflingo-dr2-after-{meeting|conference}-{幅}-{light|dark}.png`（既存テストの出力名を使用。今回は17:32に再取得）。目視した代表2枚を本記録とともに保存。
