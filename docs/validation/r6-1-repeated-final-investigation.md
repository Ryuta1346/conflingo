# R6-1 — 同文確定発話の欠落調査

2026-11-14 / ローカルmain `dab817e` / 製品ソース未変更。
[修正計画](../design/r6-1-repeated-final-plan.md)。

## 原因

`SessionStore.appendFinal`の直前本文一致guardが、同一入力元からの別発話まで拒否する。`LegacyTranslationAdapter.receive`のID/revision判定を通過した後に拒否されるため、segment追加・onFinal通知・翻訳バッファ投入が行われない。表示、保存、共通支援へ渡す元データも失われる。Meetingのstoreは本文一致で除外しない。

製品の呼出し元は`LegacyTranslationAdapter`とプレビュー。adapterは同IDのfinalを受理した後、同IDのイベントをrevisionに関係なく拒否する。翻訳キューにもunit IDによる重複除外がある。本文一致guardを外す際は、これらの再送拒否を維持する。

## 合成再現

[Probe.swift](r6-1-probe/Probe.swift)から未変更のnormalizer、store、adapter、翻訳キュー、Markdown出力を実行。表示キャッシュ型のみ空のスタブを用いたため、UI・キャッシュ動作はこのプローブの評価対象外。SpeechResultを直接作成し、音声認識器とEvent Hub、controllerは経由しない。

| ケース | Conference件数 | Meeting件数 | Conference翻訳キュー件数 | Markdown発話数 |
|---|---:|---:|---:|---:|
| 同一入力元・別IDの「Yes.」2回 | 1 | 2 | 1 | 1 |
| 同IDの再送 | 1 | 1 | 1 | 1 |
| 異なる入力元の同文 | 2 | 2 | 2 | 2 |
| adapter終了・再作成後に同文 | 1 | 2 | 1 | 1 |
| 同一入力元・別IDの「はい。」2回 | 1 | 2 | 1 | 1 |

全5ケースで現行動作のpreconditionが成功。これは不具合再現の確認であり、望ましい仕様に対するテスト合格ではない。再作成ケースは実機の停止・再開ではない。保存への影響はstoreからのデータフロー上の確認であり、このプローブでディスク保存は実行していない。

以下は修正前 `dab817e` の製品ソースで実行した記録。プローブは旧動作をassertするため、修正後のソースに対する回帰テストには使わない。修正後の検証は`RepeatedUtteranceTests`等で行う。

```sh
mkdir -p /tmp/conflingo-r6-1
xcrun swiftc -parse-as-library -module-cache-path /tmp/conflingo-r6-1/module-cache \
  ConfLingo/Models/{TranscriptEvent,TranscriptSegment,TranslationUnit,KeywordParser,SentenceBoundary,SessionStore,MeetingSessionStore,SessionMode}.swift \
  ConfLingo/Services/{LegacyTranslationAdapter,TranslationCoordinator}.swift \
  ConfLingo/Export/MarkdownExporter.swift docs/validation/r6-1-probe/Probe.swift \
  -o /tmp/conflingo-r6-1/probe
/tmp/conflingo-r6-1/probe
```

初回コンパイルはsandboxによるObservationMacros起動失敗で実行に到達しなかった。権限付きコンパイル成功後、プローブを実行した。現行コードの失敗を示すTDD Redとは扱わない。

調査のみのため全テスト・Lint・Releaseは未実行。製品コード・テスト変更、音声取得、実API送信、コミットは0。既存の637件中630成功・7skipはR5-3時点の記録であり、今回の実行結果ではない。
