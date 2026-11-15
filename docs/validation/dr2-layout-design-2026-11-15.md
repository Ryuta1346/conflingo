# DR2 現行画面確認・モック検証（2026-11-15）

本書は実装前の現行画面・モック確認の記録。後続でユーザー承認を受け、ローカル実装・検証済み。[最新の結果](dr2-layout-2026-11-15.md)。

対象main `0948f48`。[計画](../design/dr2-layout-plan.md)・[承認シート](../design/dr2-layout-approval.md)・[操作モック](../design/mockups/dr2/index.html)。

## 現行画面

現行Swiftコードのコピーを `/private/tmp/conflingo-dr2-baseline` に置き、既存SharedAssistanceLayoutTestsへ撮影用ケースのみ追加した。製品Swiftコードとリポジトリのテストは変更していない。NSHostingViewの幅をptで指定し、高さ800ptで描画。OSのダーク配色による画像で、音声・翻訳は合成、AIはfakeを使った。Conferenceは停止中、Meetingは合成入力の取得中。

| 幅pt | Meeting（現行） | Conference（現行） | Meeting（改訂モック） | Conference（改訂モック） |
|---|---|---|---|---|
| 640 | [画像](dr2-before/meeting-640.png) | [画像](dr2-before/conference-640.png) | [画像](../design/mockups/dr2/meeting-640.png) | [画像](../design/mockups/dr2/conference-640.png) |
| 900 | [画像](dr2-before/meeting-900.png) | [画像](dr2-before/conference-900.png) | [画像](../design/mockups/dr2/meeting-900.png) | [画像](../design/mockups/dr2/conference-900.png) |
| 1180 | [画像](dr2-before/meeting-1180.png) | [画像](dr2-before/conference-1180.png) | [画像](../design/mockups/dr2/meeting-1180.png) | [画像](../design/mockups/dr2/conference-1180.png) |
| 1280 | [画像](dr2-before/meeting-1280.png) | [画像](dr2-before/conference-1280.png) | [画像](../design/mockups/dr2/meeting-1280.png) | [画像](../design/mockups/dr2/conference-1280.png) |
| 1512 | [画像](dr2-before/meeting-1512.png) | [画像](dr2-before/conference-1512.png) | [画像](../design/mockups/dr2/meeting-1512.png) | [画像](../design/mockups/dr2/conference-1512.png) |

現行1280ptではConferenceの字幕が縦積み、Meetingの右欄はAI設定でほぼ埋まることを画像で確認した。保存ブロックが字幕より上にあることも確認した。合成描画を通常起動アプリの手操作・実音声受入として扱わない。

### 再現と結果

- Xcode 26.6 (17F113)、arm64 macOS。
- [撮影ハーネス](dr2-before/SharedAssistanceLayoutTests.swift.txt)をコピー側の同名テストへ配置。
- 実行: `xcodebuild test -project /private/tmp/conflingo-dr2-baseline/ConfLingo.xcodeproj -scheme ConfLingo -destination 'platform=macOS,arch=arm64' -derivedDataPath /private/tmp/conflingo-dr2-native-build -only-testing:ConfLingoTests/SharedAssistanceLayoutTests -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO`。
- **3テスト定義・1suite成功、5.793秒**。うち追加の撮影定義は5幅×2モードの10ケース、ほか既存2定義。全テスト実行ではない。
- ログ: `/private/tmp/conflingo-dr2-native.log`。xcresult: `/private/tmp/conflingo-dr2-native-build/Logs/Test/Test-ConfLingo-2026.11.15_16-30-20-+0900.xcresult`。
- 初回はsandbox制約と一時コピーのConfig不足でビルド失敗。Configを補い、許可されたXcode実行へ変更。メソッド名だけの絞り込みでは0テストだったため、その結果は検証成功に数えず、上記スイート単位で再実行した。

## 改訂モック

HTML/CSS/JavaScriptのみ。従来のPR5-Aモックは承認当時の版として保持し、DR2の改訂版を別ディレクトリへ追加した。外部ライブラリ・外部通信なし。状態や保存操作は画面内のシミュレーションであり、ファイル保存やAI実行は行わない。資料の詳細機能・LLM接続編集・終了後の振り返りは既存画面へ接続する計画で、モックでは案内を表示する。

- 画像はブラウザ幅640／900／1180／1280／1512 CSS px、高さ900px。アプリ領域高さ800pxで、上部にレビュー専用の切替UIを置いている。
- 10ケースすべてで `document.documentElement.scrollWidth <= innerWidth`。
- 境界819/820・831/832・899/900・1023/1024・1184/1185・1345/1346を確認。Meetingは832pxから2列、Conferenceは820pxから字幕2列、1346pxから支援欄を加える。2列→1列の逆戻りなし。
- 900pxで支援欄を開き、質問を入力→閉じる→開くと同じ下書きが残る。
- AI許可前は質問不可、許可すると入力済み質問が送信可能、AI停止で再び無効。
- 停止状態で保存ボタンが有効となり、モックの保存状態が表示される。
- 1512pxでも支援欄を閉じて再表示できる。
- [Meeting 1280pxのダーク画像](../design/mockups/dr2/meeting-1280-dark.png)も撮影。
- `node --check docs/design/mockups/dr2/app.js` 成功。
- 現行SwiftコードのLint: SwiftLint 0.65.1、277ファイル・違反0。ログ `/private/tmp/conflingo-dr2-design-lint.log`。モックのJavaScriptを検査するLintではない。

## 未実施

- 改訂案のSwiftUI実装・TDDのRed/Green・全テスト・Releaseビルド。
- 改訂案のネイティブ画像、リサイズ時のスクロール位置、根拠リンク、保存失敗、キーボードでのフォーカス復帰、拡大文字のネイティブ受入。
- VoiceOverはユーザー指示で保留を維持。実音声・実APIは追加していない。

記録時点ではDR2はDOING（設計・承認待ち）。DR1の実機受入、Gate U、受入完了数2/12は変更しない。
