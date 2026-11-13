# R5-2 — ライブ表示の変更前計測

2026-11-14 / main `7888730`＋R5-1の未コミット変更。使用した字幕関連ソースはmainと同じ。R5-2製品コードは未変更。

## 方法

- 現行の`SessionStore`、`MeetingSessionStore`、`TranscriptPresentation`と、それらが使う発話・翻訳単位の型を直接コンパイルした。
- Conferenceの補正値型・翻訳準備状態・SessionModeだけ、今回使用するフィールド／caseを持つ一時的な型へ置き換えた。補正検証や認識・翻訳の実行は計測していない。
- Meetingの表示用getterは現行の`(store.finals + store.partials).sorted { $0.startOffset < $1.startOffset }`をプローブへ転記した。MeetingWorkspace全体は起動していない。
- Swiftの`-O`、macOS arm64。合成300／3,000／30,000件の確定履歴に対し、10回ウォームアップ後、200回の途中更新を3回測り、経過時間の中央値を採用。準備用の履歴投入時間は除外した。
- Conferenceは各発話が1翻訳単位・翻訳済み。別途1件の文末待ちバッファと途中字幕を用意し、原文・訳文の整形とそれぞれの前回配列との比較を行う。末尾20単位の補正あり／なしを比較した。
- Meetingは確定履歴の後ろに途中発話1件を更新。表示用ソートと前回配列との比較を行う。途中発話2件・中間挿入は修正時の順序回帰テスト対象。
- 出力件数と変更検知結果をchecksumへ集計した。checksumは最適化による処理除去を避けるための値で、全文の同値性や正しさを証明するものではない。

## 結果

単位は200更新の合計ms。描画・実音声・API・SwiftUIのbody実行頻度を含まない。

| 確定発話数 | Conference補正なし | Conference補正20件 | Meetingソート・比較 |
|---:|---:|---:|---:|
| 300 | 19.340 | 48.211 | 2.345 |
| 3,000 | 132.840 | 487.065 | 23.134 |
| 30,000 | 1,385.941 | 5,200.837 | 229.730 |

履歴数に伴う増加を確認した。3,000件・補正20件では1更新あたり約2.44ms、30,000件では約26.00ms。ただし実画面のフレーム落ち・CPU使用率・STT遅延を測った結果ではない。

現コードには全履歴のmap/filter、ソート、配列比較が存在する。一方、Meetingのfinalsは受信時点で時刻順、途中発話は入力元ごとに最大1件である。途中更新のたびに全件を整形し直す必要はなく、[R5-2計画](../design/r5-2-live-presentation-plan.md)で確定表示の再利用と表示用参照を提案する。

## 再現用ファイル

- [Probe.swift](r5-2-probe/Probe.swift)：合成入力と計測。
- [Support.swift](r5-2-probe/Support.swift)：計測対象外の値型。
- [baseline.csv](r5-2-probe/baseline.csv)：丸め前の数値。
- [source-hashes.json](r5-2-probe/source-hashes.json)：計測に使用した製品ソース8ファイルのSHA-256。

```sh
mkdir -p /tmp/conflingo-r5-2-probe
xcrun swiftc -O -parse-as-library \
  -module-cache-path /tmp/conflingo-r5-2-probe/module-cache \
  ConfLingo/Models/TranscriptEvent.swift \
  ConfLingo/Models/TranscriptSegment.swift \
  ConfLingo/Models/TranslationUnit.swift \
  ConfLingo/Models/KeywordParser.swift \
  ConfLingo/Models/SentenceBoundary.swift \
  ConfLingo/Models/SessionStore.swift \
  ConfLingo/Models/MeetingSessionStore.swift \
  ConfLingo/Conference/TranscriptPresentation.swift \
  docs/validation/r5-2-probe/Support.swift \
  docs/validation/r5-2-probe/Probe.swift \
  -o /tmp/conflingo-r5-2-probe/probe
/tmp/conflingo-r5-2-probe/probe
```

上記は変更前ソース用。修正後の比較では新しい表示APIへ接続し、途中行・補正・変更検知を含む同じ表示内容を保った状態で測る。単に測定対象の処理を省いて比較しない。

今回は調査用プローブのみを実行し、製品テスト・Lint・Releaseビルドは再実行していない。R5-1の直前の全617テスト・Lint・Release成功とは区別する。音声取得・実API送信・コミットは0。
