# DR1 小修正（D03・D05・D14）修正計画

- 作成日: 2026-11-15
- 対象: conflingo / main `daa871f`（PR #45マージ後）
- 状態: 承認待ち。コード変更なし。
- 依頼: 「plan.md をもとに次進めて」。[plan.md](../../plan.md#uiデザインレビュー対応2026-11-15)のDR1。
- 指摘の出典: [UIデザインレビュー](ui-design-review-2026-11-15.md)のD03・D05・D14。

## 作業環境の制約

この計画はLinuxのクラウド環境で作成した。Xcode・macOSがなく、**ビルド・テスト・アプリ起動はこの環境で実行できない。** plan.mdが求める「現在の見え方の実機確認」と「合成UIでの確認」はここでは行えない。代替は[検証と完了判定](#検証と完了判定)に記す。

## 目的と受入条件

| ID | 現状（コードで確認） | 合格条件 |
|---|---|---|
| D03 | `MeetingTransport.swift:49-51`。「一時停止」「会議を終了」が隣接し、終了は確認なしで振り返りへ移る。終了後は `MeetingWorkspace.swift:296` の `page != .review` で再開できない。一時停止中の「会議を終了」（:58）も同じ | 「会議を終了」を押すと確認が出て、取消で会議がそのまま続く。確定したときだけ振り返りへ移る。取得中・一時停止中の両方で同じ。終了ボタンは一時停止から離れた右端にある |
| D05 | `MeetingWorkspaceView.swift:228`。候補カードの状態ラベルは、確認済み・却下・中断・生成中のすべてが琥珀色＋疑問符 | 状態ごとに色と記号が変わる（下表）。文字は従来どおり併記し、色だけに頼らない |
| D14 | 同じ画面が「保存したセッション」「Sessions」「保存」「ライブラリ」と4通りに呼ばれる。Meeting Liveの見出しが `Meeting / General` | 保存したセッションの画面名が全箇所で1つの呼び方（狭幅は決めた短縮形）に揃う。Meeting Liveの見出しから `General` が消える |

D14のうち、入力名・操作名・AI注記の揺れはDR1の範囲外（plan.mdのDR1は画面名と `Meeting / General` のみ）。

## 修正方針

### D03 終了の確認

既存の破棄確認（`requestDiscard`／`showsDiscardConfirmation`／`confirmDiscard`）と同じ形にする。

1. `MeetingWorkspace` に `showsEndConfirmation`、`requestEnd()`、`confirmEnd()` を追加する。`requestEnd()` は終了できる状態（振り返り以外・遷移中でない）のときだけ確認を出す。`end()` 自体は変更しない（既存テスト約70箇所が直接呼んでおり、停止処理の契約を変えない）。
2. `MeetingTransport` の「会議を終了」2箇所を `requestEnd()` へ差し替える。
3. `MeetingWorkspaceView` に確認ダイアログを追加する。文面は既存の確認と同じく「何が起き、何が残るか」を書く。
   - 題名: 「会議を終了しますか？」
   - 本文: 「終了すると、この会議の文字起こしは再開できません。ここまでの発話とAIの回答は振り返りに残り、保存とMarkdownの書き出しができます。」
   - ボタン: 「キャンセル」（取消）／「会議を終了」（破壊）
4. ボタン配置: 取得中は「一時停止」と「会議を終了」の間隔を24ptに広げ、「会議を終了」を右端に置く。一時停止中は「準備へ戻る」「再開」を先に並べ、「会議を終了」を同じ間隔で右端に離す。
5. 確認待ちの間に状態が変わった場合（停止失敗など）は、`confirmEnd()` 側で再判定して何もしない。`reset()` で `showsEndConfirmation` を戻す。

**採らない案: 振り返りから「会議を再開」。** 終了時に要約・保存・書き出しの対象が確定する前提（`MeetingSummaryCoordinator`、`sessionSnapshot`、保存済みセッションとの対応）を崩すため、影響範囲が大きく「小修正」に収まらない。必要なら別項目として計画する。

小窓（`MeetingFloatingPanel`）には終了ボタンがないため変更しない。

### D05 状態ラベル

`MeetingInsightCard` の表示判定を、文字・記号・色調をまとめて返す1つの値に切り出す（ビュー外でテストできる形にする）。

| 状態 | 文字（変更なし） | 記号 | 色 |
|---|---|---|---|
| 候補・確認済み | 確認済み | `checkmark.circle` | positive |
| 候補・却下 | 却下 | `xmark.circle` | secondary |
| 候補・未確認 | 未確認 | `questionmark.circle` | warning（現状維持） |
| 生成中 | 生成中・未検証 | `ellipsis.circle` | secondary |
| 中断 | 中断 | `exclamationmark.triangle` | warning |
| 完了（候補以外） | 要確認 | `questionmark.circle` | warning（現状維持） |

文字の統一（要確認／未確認など）はD14の範囲外部分にあたるため変更しない。保存したセッションの候補表示（`SavedSessionView.swift:77`）は状態を見出しの文字で示し、色付きラベルを使っていないため変更しない。

### D14 画面名

正とする名称は **「保存したセッション」**（サイドバー・README・確認ダイアログ・設定の説明で既に使用）。

| 場所 | 現状 | 変更後 |
|---|---|---|
| 上部バー（`ContentView.swift:280`） | Sessions | 保存したセッション |
| 狭幅ナビ（`AppShellView.swift:36`） | 保存 | **保存済み**（要判断） |
| 一覧の小見出し（`SessionsView.swift:18`） | ライブラリ | ConfLingo（設定・Homeと同じ） |
| 詳細の小見出し（`SavedSessionView.swift:17`） | Sessions | 保存したセッション |
| Meeting Liveの見出し（`MeetingWorkspaceView.swift:127`） | Meeting / General | Meeting / ライブ（「Meeting / 準備」「Meeting / 振り返り」と対） |

狭幅ナビは横幅が限られるため短縮形が要る。「保存」は操作に見えるという指摘なので、状態を表す「保存済み」を推奨する。代案は「セッション」。

コード上の型名・ファイル名（`SessionsView` など）と、開発者向け文書の「Sessions」は変更しない。利用者向けREADMEは既に「保存したセッション」で揃っている。

## テスト設計

`ConfLingoTests` の既存方式（Swift Testing、`DualFixture`、`NSHostingView`）に合わせる。修正前に失敗することを確認できるものを先に書く。

- **D03（状態）:** 取得中に `requestEnd()` → 確認が立ち、`phase == .listening` と `page == .live` のまま。取消後も継続。`confirmEnd()` で `page == .review`。一時停止中も同じ。振り返り・遷移中の `requestEnd()` は確認を出さない。確認を出さずに `confirmEnd()` を呼んでも終了しない。
- **D03（画面）:** `MeetingTransport` をホストし、「会議を終了」を実行しても `page` が変わらず確認が立つこと。
- **D05:** 6状態それぞれの記号・色調の対応。確認済みが warning でないこと、却下・生成中が疑問符でないこと。
- **D14:** 上部バー・狭幅ナビ・一覧・詳細・Meeting Liveをホストし、表示文字列に「Sessions」「General」が含まれず、決めた名称が含まれること。狭幅ナビの「保存」単独ラベルがないこと。
- 既存テストで旧文言に依存するものは、grepでは見つかっていない（「Sessions」「Meeting / General」「会議を終了」を検査するテストなし）。実行時に失敗が出たら個別に直す。

## 検証と完了判定

この環境で実行できないものを、実行済みとして記録しない。

1. **自動検証:** GitHub Actionsの「macOS validation」（Lint・非liveテスト・両CPU Release）で確認する。このワークフローは `pull_request`・mainへのpush・手動実行（`workflow_dispatch`）で動く。作業ブランチへのpushだけでは動かないため、**手動実行するか、Draft PRを作るかを承認時に決める。**
2. **Red/Green:** 追加テストが修正前に失敗することは、CIを2回回さない限りこの環境では確認できない。既定では「修正後に成功」のみを記録し、Red未確認と明記する。
3. **実機・合成UIの確認:** 現在の見え方の確認、確認ダイアログの表示、状態ラベルの色、640pt幅での終了ボタンの位置、ライト／ダークは**未実施として残す**。Macでの確認手順を検証記録に書き、ユーザー側の確認待ちとする。
4. 結果は `docs/validation/dr1-small-fixes-2026-11-15.md` に記録し、plan.mdのDR1を更新する。実機確認が済むまでDR1は `REVIEW`、Gate Uと受入完了数2/12は据え置く。

## 実施順序

1. 承認後、plan.mdのDR1を `DOING` にする。
2. テストを追加する（D03→D05→D14）。
3. D03→D05→D14の順に修正する。
4. 作業ブランチ `claude/plan-md-next-steps-4kdj96` へコミット・pushし、決めた方法でCIを実行する。失敗があれば直す。
5. 検証記録とplan.mdを更新する。

保存形式・通信処理・AI送信の許可・音声入力には触れない。実音声・有料API・実Keychainは使わない。

## 承認時に決めること

1. **D03の方式:** 確認ダイアログ（推奨）／振り返りからの再開（別計画）。
2. **狭幅ナビの名称:** 保存済み（推奨）／セッション。
3. **CIの回し方:** 作業ブランチで手動実行（推奨、PRなし）／Draft PRを作成／pushのみでCIは回さない。
