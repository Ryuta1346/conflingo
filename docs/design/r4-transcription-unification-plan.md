# R4 — Conference文字起こし経路の一本化

2026-11-14 / 調査基点: main `8fd8144`（PR #34マージ済み）。
正本: `~/.coding-agents/docs/conflingo/main/r4-transcription-unification-plan.md`。

## 状態・承認範囲

ユーザー「レビューは完了してR4進めてる」によりR3のレビュー完了とR4の実装継続を確認。承認済み計画に基づきローカル実装・自動検証済み、REVIEW。
Planモード切替ツールが提供されていないため、この文書で計画と承認状態を管理する。

GitHub APIとローカルmainでPR #34のマージを確認済み。GitHubのレビュー提出は0件だったが、2026-11-14にユーザーからレビュー完了の申告があった。R3の開始条件は充足し、レビュー持ち越しは不要。独立レビューの本文・手段は本作業では取得していない。

## 調査結果（実装前）

- `SessionController.start`は初回のマイク単独だけ旧経路へ進む。内部音声／両入力、または一度共通経路を使った後は`DualTranscriptionController`を利用する。Clearで旧経路に戻るため、選択履歴によって実行経路が変わる。
- 旧経路は権限確認・入力利用権・Hub・normalizer・失敗処理・停止処理を重複して持つ。`meetingStore`は製品側の利用者がなく、テストだけが参照する。
- 共通経路には入力停止→認識終了→Hub終了→Conference購読の終了という順序と、停止失敗時の利用権保持・再試行がある。
- 既存のマイク単独テストは、再開後の字幕`startTime`を入力内時刻 `[1, 1]`、支援用の`sessionOffset`を共通時計 `[1, 26]`としている。共通経路のadapterは`commonTimeline: true`のため、単純な分岐削除では字幕・Markdownの時刻が変わる。
- 一部の停止テストは入力を開始せず`store.phase = .listening`だけを設定する。共通controllerとの状態不一致を作るため、fake入力の実際の開始→停止を通すテストへ置き換える。

## 変更範囲

| 対象 | 予定する変更 |
|---|---|
| `ConfLingo/Services/SessionController.swift` | 全入力選択で共通controllerを使用。旧入力処理、`usingDual`、重複したHub／normalizer／利用権／停止task、未使用`meetingStore`を削除。Conferenceのphase・エラー・字幕／翻訳adapterの接続に責務を絞る |
| `ConfLingo/Services/LegacyTranslationAdapter.swift` | 原則既存APIを利用。入力内時刻と共通時計の扱いを維持するため、必要な最小変更だけ行う |
| `ConfLingoTests/SessionControllerTests.swift`、`CoreEventSessionTests.swift`等 | fake入力を開始して公開動作を検証。旧`meetingStore`への検証を字幕・支援・保存結果、または注入した共通controllerのstoreへ移す |
| `AudioInputUseTests`、`SharedAssistanceTests`、`MicrophoneConfigurationSessionTests`等 | 権限注入をAudioSourceへ集約。競合・機器変更・翻訳再試行・共通支援の回帰を確認 |
| 計画・詳細計画・検証記録 | 実装前に契約を反映し、実行後に結果と未受入範囲を記録 |

`SessionController`のテスト用`requestPermission`注入は削除し、既存のfake `AudioSource`／`MicrophoneAudioSource`の権限注入を使う。製品呼出し元が使わない互換引数は残さない。`DualTranscriptionController`の共通動作は原則変更せず、必要性が再現テストで確認できた箇所に限定する。
保存形式・fixture・Meetingの製品仕様・LLM処理は変更しない。

## 保持する契約と回帰ケース

1. **入力選択:** マイク単独・内部音声単独・両入力を同じcontrollerで処理し、選択していない入力の権限要求・開始は0回。初回、選択切替後、Clear後も確認する。
2. **字幕・翻訳:** 部分結果→確定結果、停止時の最終結果、文末待ちのbufferを欠落・二重投入なく翻訳へ渡す。翻訳準備失敗中も文字起こしを継続し、再試行で未翻訳を処理できる。
3. **時刻・再開:** マイク単独の既存字幕時刻は入力内時刻、支援用時刻はセッション共通時計を維持する。内部音声／両入力の共通時計も維持する。開始→停止→再開→言語切替→Clearで時刻・言語・本文・古いcallbackの無視を確認する。選択履歴による時刻差を増やさないよう、入力切替ケースも固定する。
4. **設定:** glossaryが入力開始時に利用でき、認識モード・fastResults・言語・context更新が選択入力へ渡る。停止中のcontext更新は成功扱いにしない。
5. **権限と失敗:** 入力競合では権限要求前に拒否。権限拒否、準備取消、開始失敗、機器構成変更、購読overflowで入力を停止し、原因を表示して再開始できる。マイク権限拒否では復旧先の案内も維持する。
6. **停止:** 準備中の取消と二重停止を安全に扱う。入力停止失敗ではstoppingと利用権を保持し、停止再試行成功後に解放する。認識終了だけの失敗と入力停止失敗を区別する。
7. **保存・支援:** 字幕から支援へ渡る入力元・時刻・言語・根拠、Markdown、R3のv1固定JSONが維持される。

## 実装・検証手順

1. 計画承認後、詳細計画のConference契約とplan.mdのR4を更新する。未実装の契約には予定と明記する。
2. TDD: マイク単独で注入済み共通controllerの入力を使うこと、Clear後も同じ選択入力だけが開始されることを、fakeの開始・権限回数と字幕出力でテストする。旧コードで意図した失敗を確認する。ビルド不能や権限ダイアログをRedの代わりにしない。
3. 最小実装で全選択を共通経路へ委譲し、Conferenceの購読・終了処理だけを残す。時刻仕様を変えず、旧storeと不要な注入・状態を整理する。
4. 上記回帰ケースを既存テストと対応付け、不足分を追加する。内部状態だけを手動で作るテストは、fakeで開始するテストへ移行する。テストの期待値を変更する場合は契約上の理由を記録する。
5. 関連テスト→全テスト（実API評価無効）→SwiftLint→Releaseビルドを実施する。R3の固定fixtureは変更しない。
6. `docs/validation/r4-transcription-unification.md`へRed/Green・回帰結果と実機未検証を記録し、不要コード・資料整合性を最終確認する。実装時点ではコミット・PR作成を含めず、後続のユーザー「コミットしてPR作成」で別途承認された。

実行コマンド（予定）:

```sh
xcodebuild test -project ConfLingo.xcodeproj -scheme ConfLingo \
  -destination 'platform=macOS' -derivedDataPath /tmp/conflingo-r4-build \
  CODE_SIGNING_ALLOWED=NO
/tmp/conflingo-swiftlint-0.65.1/swiftlint lint --strict --no-cache
xcodebuild -project ConfLingo.xcodeproj -scheme ConfLingo \
  -configuration Release -derivedDataPath /tmp/conflingo-r4-release \
  CODE_SIGNING_ALLOWED=NO build
```

既存の実API評価フラグ8種をすべて0にして実行する。実音声取得・追加実APIはこの計画では実施しない。

## 完了条件と持ち越し

- Conferenceの全入力が共通経路を使用し、旧処理と`SessionController.meetingStore`が残らない。
- 字幕・翻訳・停止／再開・設定・権限・入力利用権・支援／保存の回帰テストが成功する。
- 全テスト・Lint・Releaseが成功し、検証証跡がある。
- R3レビューはユーザー確認により完了。R4の自動検証成功をGate Aの実機合格に置き換えず、Conference実翻訳・字幕・辞書・言語切替・権限復旧・機器抜き差し等は既存の回帰表で継続する。
- マージ・実機受入前にR4をDONEにしない。

## 実装結果

全入力を共通controllerへ統合し、旧マイク経路と未使用storeを削除した。adapter自体の変更は不要だった。入力選択に応じた字幕時刻を既存引数で指定する。共通controllerには、先行テストで失われることを確認したマイク権限拒否時の設定案内だけを追加した。

経路選択と権限案内のRedを確認後、関連51テスト成功。全609件中602成功・実API7skip、Lint236ファイル違反0、Release arm64／x86_64成功。[検証記録](../validation/r4-transcription-unification.md)。ユーザーの依頼により`2310f7a`をコミット・pushし、[Draft PR #35](https://github.com/Ryuta1346/conflingo/pull/35)を作成済み（担当Ryuta1346）。実機受入・独立レビュー・マージは未実施。
