# R6-1 — 同文の別発話をConferenceで保持する計画

2026-11-14 / 基点: ローカルmain `dab817e`（PR #37マージ済み）。
状態: **2026-11-14、ユーザー「進めて」で本計画を承認済み。ローカル実装・検証済み（REVIEW相当）。未コミット・未PR**。
正本: `~/.coding-agents/docs/conflingo/main/r6-1-repeated-final-plan.md`。
Planモードの切替機能は利用できないため、この文書で実装前の計画を提示する。

## 問題と根拠

同じ入力元で同文を連続して発話すると、Conferenceの`SessionStore.appendFinal`が直前本文との一致だけで2件目を捨てる。発話ID・時刻の異なる正当な反復も失われる。`LegacyTranslationAdapter`は既にイベントID/revisionで再送を除外しており、Meetingは別IDの同文を保持する。

未変更の製品ソースを使い、英語・日本語・停止後のadapter再作成を合成入力で再現した。Conferenceは2発話中1件、Meetingは2件を保持し、Conferenceの翻訳キュー・Markdownも1件になる。同IDの再送は両方1件、異なる入力元の同文は両方2件。[再現記録](../validation/r6-1-repeated-final-investigation.md)。停止後のケースはadapterの再作成であり、実機の停止・再開受入ではない。

既存`SessionStoreTests.appendFinalRejectsConsecutiveDuplicate`と`LegacyTranslationAdapterTests.rejectsStaleDuplicateAndForeignEvents`には、別発話の同文も破棄する期待値がある。修正時に正当な反復と再送を分離して更新する。

## 提案する変更

`SessionStore.appendFinal`の本文一致による早期returnだけを削除し、コメントを新しい契約に合わせる。空白のtrimと空文字拒否は保持する。`appendFinal`の各呼出しは別の確定発話を追加し、イベントの再送除外は既存の`LegacyTranslationAdapter`のID/revision判定に任せる。

- 同じ入力元・本文でも別IDなら2件を保持し、それぞれの時刻・入力元・言語・生成されたsegment IDを残す。
- 同じイベントIDの再送、確定後のpartial/新revision、古いrevision、別セッション、対象外入力、空文字の拒否を維持する。
- 同文を含む文末待ちのバッファは現行の文末・400文字・4セグメント・4秒・停止時flush規則に従う。句点付き同文2発話は2翻訳単位、文末なし同文2発話は結合時も両方のsegment IDを含む。
- 変更対象の製品コードは`ConfLingo/Models/SessionStore.swift`を想定する。adapter、normalizer、翻訳キュー、保存形式v1、Meetingの処理は変更しない。
- 新しい時刻閾値、本文ハッシュ、設定項目、発話IDの保存形式への追加は行わない。過去に失われた発話は復元できない。

normalizerはfinalの後に新IDを発行する。そのため音声認識器が別イベントとして出した同文を、正当な反復か認識器の二重出力か本文だけで判定しない。今回保証する再送除外は同一イベントIDの範囲。実音声での出力特性はGate Aで確認する。

## 受入条件とテスト

| 対象 | 期待結果 |
|---|---|
| storeの連続同文 | 英語・日本語、入力元なし／同一入力元で2件。異なるID・連番・各時刻を保持。onFinalが2回、volatileを消去 |
| adapterの別ID | 同一入力元の同文2発話を保持。句点付きは翻訳キューに異なるunit IDで2件 |
| 再送・不正イベント | 同ID再送や確定後の高revisionも1件だけ。古いrevision・別セッション・対象外入力・空文字を拒否 |
| バッファ | 文末なし同文を2件保持し、finishで両segment IDと両本文を含む1単位へflush。二重flushなし |
| 入力経路 | マイクのみ・内部音声のみ・両入力のConferenceにfake音声認識から反復を流して確認。異なる入力元の同文も維持 |
| 再開 | storeを保持した停止→再開で、前回末尾と同文の新発話を保持。Clear後は履歴を持ち越さない |
| 表示・下流 | source表示の2行、翻訳単位、onFinal通知、Markdownの2発話を確認。補正を適用しない条件で評価 |
| 保存 | Conference snapshotの保存→再読込で両segment・時刻・訳文対応を維持。既存v1固定JSONを変更せず成功 |
| Meeting | 同一入力元・別IDの同文2件を保持し、同IDの再送は1件。既存動作を回帰確認 |

テスト対象は`SessionStoreTests`、`LegacyTranslationAdapterTests`、`SessionControllerTests`、`TranscriptEventTests`、表示・保存・Markdownの既存suiteを中心にする。必要に応じ専用回帰テストファイルへまとめる。範囲外の挙動は既存テストで確認し、実装を写しただけのテストは追加しない。

## 実装順

1. 承認後、詳細計画の発話重複の説明とREADME.jaのSessionStore責務を更新する。予定と実装済みを区別する。
2. `tdd`スキルを読み、上記の欠落に対するテストを先に追加する。現行コードで別発話が1件になる失敗を確認し、同ID再送の拒否テストは残す。
3. 本文一致guardの削除とコメント修正を行い、関連テストを成功させる。不要になった旧期待値・資料説明を整理する。
4. 全live評価フラグを0として全テスト、SwiftLint strict/no-cache、Releaseビルド、`git diff --check`を実行する。
5. 結果・残る実機受入を記録し、plan.mdを更新する。R5のレビュー・実機受入と他のR6項目は継続する。

音声取得・実モデル送信は本実装検証に含めない。実機受入は既存Gate A/Bの条件に従う。コミット・PR作成は今回の作業に含まない。

ユーザー指定AGENTS.mdに従って具体案を提示し、2026-11-14のユーザー「進めて」で本計画の実装承認を受領した。

## 実施結果（2026-11-14）

本文一致guardの削除とコメント更新を実装。先行テストの4定義・14ケースの失敗を確認後、関連34定義が成功。全640件中633成功・実API7skip、Lint245ファイル違反0、Release成功。表示モデル・翻訳キュー・保存復元・Markdown・入力3構成の停止/再開を確認した。独立レビュー・実音声受入は継続。[検証結果](../validation/r6-1-repeated-final.md)。
