# R5-3 — 検索語の初出順選択・検証結果

> 2026-11-14マージ確認: 実装 `bd01b29`を含む[PR #37](https://github.com/Ryuta1346/conflingo/pull/37)はローカルmain `dab817e`へマージ済み。独立レビュー完了・実機受入は未確認。以下の未コミット・未PR等の記述はローカル検証完了時点の記録。

2026-11-14 / 基点: ローカルmain `a607f6e`＋今回の未コミット変更。
状態: **承認済み範囲をローカル実装・検証済み（REVIEW相当）。未コミット・未PR**。
[実装計画](../design/r5-3-query-selection-plan.md)・[変更前の再現記録](r5-3-query-selection-investigation.md)。

## 変更

`KnowledgeIndex.search`で、文字順にソートした32語の選択を、初出順で重複除去した32語の選択へ変更した。先頭の英語・日本語・識別子が後続語の綴りだけで脱落する問題を修正した。製品変更は既出語Setの追加と式の置換のみ。

正規化と識別子展開の順序、2,000文字・32語の上限、OR検索、SQLパラメータ化・引用符処理、パス重み付きBM25とrowid順、最大10件、保存形式・引用・送信許可は維持した。33語目以降の重要語を検索できる保証はない。

## TDD

`KnowledgeQuerySelectionTests`に8テスト定義・14ケースを追加した。現行コードで5テスト定義が失敗（29 issues）、境界・重複除去・短文順位の3定義は成功した。検索漏れによる空結果と、33語目の文字順が早い語が先頭対象を押し出す結果を確認。修正後は既存の`KnowledgeIndexTests`・`RepositoryKnowledgeTests`と合わせて25テスト／3 suites成功。

最初のサンドボックス内ビルドは`ObservationMacros`の起動権限で失敗し、テストに到達しなかった。この環境エラーはRedの証拠に含めず、権限付き再実行で上記の検索動作の失敗を確認した。

| 対象 | 結果 |
|---|---|
| 長文の先頭対象 | `zebra`・大文字・全角・`月額`＋40語で対象だけを取得 |
| 語数境界 | 31／32語目は取得、33語目のみ一致する資料は対象外。文字順が早い33語目も先頭語を押し出さない |
| 重複／除外語 | 大小文字・全角の同語と日英stop wordを繰り返しても32語枠を消費しない |
| 識別子 | camelCase／snake_caseの原語を先頭に指定した長文検索でリポジトリパスに一致し、参照全体・snapshot ID・hash・位置を保持 |
| 保存復元 | 別索引へ復元した日本語資料を長文で検索でき、2行目・offset 1,199と本文を保持 |
| 入力と構文 | 2,000文字より後の対象は検索しない。引用符・FTS記号を含む長文でも意図した資料だけを取得。空相当は0件 |
| 順位 | 短文のパス一致優先・同点の挿入順、検索語を逆順にしたときの順位一致を確認 |
| 全体回帰 | 資料質問・自動提案・要約・保存・ライブラリ・入力・表示を含む既存テストが成功 |

## 最終検証

- 全637テスト／115 suites：630成功、実API評価7skip、失敗0。Swift Testing表示の所要時間57.395秒。xcresultの集計と照合済み。
- SwiftLint 0.65.1 strict/no-cache：244ファイル、違反0。
- Release：arm64／x86_64、署名なしビルド成功。
- `git diff --check`成功。製品差分の選択順・上限・SQL・不要なソートの除去を自己レビューした。独立レビューは未実施。

```sh
env CONFLINGO_LIVE_AI=0 CONFLINGO_FOCUSED_LIVE_AI=0 \
  CONFLINGO_GROUNDING_LIVE_AI=0 CONFLINGO_RAG_LIVE=0 \
  CONFLINGO_SUMMARY_LIVE=0 CONFLINGO_SUMMARY_REMAINING_LIVE=0 \
  CONFLINGO_SUMMARY_DEADLINE_LIVE=0 CONFLINGO_R2_SIZE_LIVE=0 \
  xcodebuild test -project ConfLingo.xcodeproj -scheme ConfLingo \
  -destination 'platform=macOS' -derivedDataPath /tmp/conflingo-r5-build \
  CODE_SIGNING_ALLOWED=NO
/tmp/conflingo-swiftlint-0.65.1/swiftlint lint --strict --no-cache
xcodebuild -project ConfLingo.xcodeproj -scheme ConfLingo \
  -configuration Release -derivedDataPath /tmp/conflingo-r5-release \
  CODE_SIGNING_ALLOWED=NO build
```

ログ: `/tmp/conflingo-r5-3-{red,red-test,focused,full,lint,release}.log`。
全体結果: `/tmp/conflingo-r5-build/Logs/Test/Test-ConfLingo-2026.11.14_07-14-50-+0900.xcresult`。
集計: `/tmp/conflingo-r5-3-test-summary.json`。

既存Keychain APIのdeprecated、ContentViewの到達不能コード、AppIntentsメタデータ省略のビルド警告が残る。合成UIのScrollGeometry警告、macOSサービス接続と接続端末のログも出たが、テスト・ビルドの失敗は0。

音声取得・実API送信・コミット・PR作成は行っていない。R5-1/2はPR #36でマージ済みだが、独立レビュー完了・実機品質・長時間耐久は未確認。R5全体をDONEや品質ゲート合格に変更しない。次はR5の差分レビュー・PR反映と残る受入。後続の実装候補はR6の調査・計画。
