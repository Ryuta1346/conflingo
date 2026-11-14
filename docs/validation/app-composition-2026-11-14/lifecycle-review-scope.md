# 構成ルート分離: 状態・寿命レビュー

- 固定入力: `/tmp/conflingo-composition-review/review.diff` と同フォルダ内の7ファイル。`hashes.json` のSHA-256に全7件一致。
- 基準: `docs/design/app-composition-plan.md`、parallel-review / review-common 2.7。
- 確認対象: AppCompositionの生成・Appによる保持、ContentViewの注入とObservable参照、翻訳taskの世代・停止処理との接続、主画面と小窓の同一Meeting参照、Conference支援の字幕store/LLMSettings接続、同一AudioInputUseによる排他、AppStorageの設定suite、プレビューの初期画面と合成クライアント、DebugとReleaseの条件分岐。
- 周辺参照: SessionController、TranslationCoordinator、ConferenceKnowledgeWorkspace、MeetingFloatingPanel、MeetingWorkspace、各サービスのObservation宣言。
- 結果: 今回の追加行に基づく具体的な回帰は確認できず、findingsは空。既存のView task・閉じる処理・小窓展開の挙動を今回の問題として再指摘していない。
- 制約: 静的独立レビュー。追加のテスト・ビルド・実アプリUI操作は実行していない。関連27テスト成功は親からの報告であり、本レビュー独自の実行結果ではない。全体テストとReleaseビルドは親が検証中。ウィンドウ閉鎖/再表示、実Translation framework、実入力・実APIの受入完了は主張しない。製品コード・テスト・Gitへの変更なし。
