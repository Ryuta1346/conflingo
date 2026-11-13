# R5-3 — 検索語選択の調査・再現

2026-11-14 / ローカルmain `a607f6e`。以下は製品・テストコード未変更時点の調査記録で、修正後の検証ではない。現在は[修正・ローカル検証済み](r5-3-query-selection.md)。

## 原因と影響

`KnowledgeIndex.search`の`Array(Set(terms)).sorted().prefix(32)`により、文字順が後ろの語は入力位置と無関係に除外される。2,000文字以内の短い合成入力で再現し、入力文字数制限とは切り分けた。

`KnowledgeStore`の資料画面検索・手動質問、`localReferences`、`retrieveForAutomatic`、`retrieveForSummary`が同じ検索へ到達する。後三者は2,000文字単位で検索し、順位を統合して最大5件を採用する。この分割・統合を変更する必要はない。

## 現行実装での結果

40個の異なる英単語（amber〜cabin）を後続語として使用。すべて対象語より文字順が早い。

| 入力／経路 | 結果 |
|---|---|
| `zebra`のみ | 一致 |
| 冒頭`zebra`＋31語（全32語） | 一致 |
| 冒頭`zebra`＋32語（全33語） | 不一致 |
| 冒頭`zebra`＋40語（262文字） | 不一致 |
| 40語＋末尾`zebra` | 不一致 |
| `月額`のみ | 一致 |
| 冒頭`月額`＋40語（259文字） | 不一致 |
| `zebra`を5回＋40語 | 不一致 |
| 保存・別索引に復元後、冒頭`月額`＋40語 | 不一致 |
| リポジトリ`src/zebraTarget.swift`、質問`zebraTarget` | 一致 |
| 同じリポジトリ、冒頭`zebraTarget`＋40語 | 不一致 |

現在の失敗状態をassertする診断プローブが終了コード0で完了した。これは不具合の再現確認であり、製品テストの合格を意味しない。[ソース](r5-3-probe/Probe.swift)・[出力](r5-3-probe/baseline.txt)・[製品ソースハッシュ](r5-3-probe/source-hashes.txt)。

以下は変更前の`a607f6e`の製品ソースを使った再現コマンド。プローブは不具合の存在をassertするため、修正後のソースでは失敗する。修正後の確認には`KnowledgeQuerySelectionTests`を使う。

```sh
mkdir -p /tmp/conflingo-r5-3-probe
xcrun swiftc -O -parse-as-library \
  -module-cache-path /tmp/conflingo-r5-3-probe/module-cache \
  ConfLingo/Knowledge/KnowledgeIndex.swift \
  ConfLingo/Knowledge/KnowledgeDocument.swift \
  ConfLingo/Knowledge/RepositoryImporter.swift \
  ConfLingo/KnowledgeLibrary/KnowledgeArchive.swift \
  docs/validation/r5-3-probe/Probe.swift \
  -o /tmp/conflingo-r5-3-probe/probe
/tmp/conflingo-r5-3-probe/probe
```

全テスト・Lint・Releaseは今回未実行。音声取得・実API送信は0。ローカルgit履歴でPR #36のマージを確認したが、GitHub上のレビュー完了は確認していない。

## 次の作業

[実装計画](../design/r5-3-query-selection-plan.md)は承認済み。初出順で重複除去した32語への変更をTDDで実装し、[検証を完了](r5-3-query-selection.md)。末尾の重要語も常に取得できるようにする変更ではなく、冒頭対象が文字順だけで脱落する偏りの修正とする。
