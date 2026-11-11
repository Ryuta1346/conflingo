# PR7 終了後要約の期限修正・再評価計画

2026-11-11 / `feature/pr8-quality-acceptance` / Draft PR #19と同じブランチ。
**ユーザー「susumete」で承認済み（2026-11-11）。実装・検証完了、承認済み実APIは8/8区間合格。**
正本: `~/.coding-agents/docs/conflingo/feature-pr8-quality-acceptance/pr7-summary-deadline-plan.md`。

## 問題と変更後の振る舞い

[計測付き評価](../validation/pr7-summary-remaining.md)のS08-en-1は23.286秒で受信を開始し、29.746秒にも受信していたが、30.036秒で全体期限により取り消された。計数は0.190秒、完成後の通知には未到達。日本語の30発話区間も25.557〜28.623秒を要した。現行コードはcoordinator・URLRequest・URLSessionがそれぞれ30秒である。

会議終了後の要約は**1区間あたり60秒**に変更する。会議中の手動質問、資料検索付き回答、自動提案は30秒を維持する。例えば40秒で完了する要約は保存できるようになり、60秒を超えた場合は取消・後続区間停止となる。受信開始によって全体期限を延長しない。

最初の受信までの待ちをネットワークとAPI内部処理に分解できていない。60秒は今回の観測に基づく検証対象であり、成功を保証する値ではない。モデル・thinking・出力上限・プロンプト・区間分割・品質条件は変更しない。

## 最小実装

1. `InsightRequest`に用途を明示するenum（通常支援／終了後要約）を追加する。既定は通常支援。`MeetingSummaryPlan`だけが要約用途を指定し、用途から30／60秒を返す。既存のmanual／automatic triggerと資料利用判定は維持する。
2. `GeminiInsightClient`のURLRequestへ用途別期限を渡す。`URLSessionInsightTransport`のrequest／resource期限を当該URLRequestに揃える。coordinatorだけを変更してHTTPが30秒で終了する不整合を解消する。
3. `MeetingSummaryCoordinator`の区間期限をrequestの用途から取得する。短時間テスト用の明示overrideは維持する。全体期限はKeychain取得を含むclient開始から計測し、プレビューでリセットしない。通常の`InsightCoordinator`は30秒を維持する。
4. 承認後、現行仕様の資料を60秒へ更新する。過去評価の30秒と失敗記録は残す。期限以外のUI・永続化・候補確認状態は変更しない。

対象: `ConfLingo/Meeting/Services/{InsightClient,GeminiInsightClient,InsightHTTPTransport,MeetingSummaryCoordinator}.swift`、`ConfLingo/Meeting/MeetingSummary.swift`、関連テスト、評価設定・資料。期限の数値以外で共通プロンプトやpayloadが変わっていないことを差分で確認する。

## TDDとローカル受入

- 通常・RAG・自動提案のrequestは30秒、要約planの全区間は60秒となることと、生成HTTPの期限への伝播を検証する。
- URLSession設定のrequest／resource期限が要求に従うことを確認する。既存の偽HTTP手法を使い、実APIなしで検証する。
- 短縮した期限を使い、従来期限を越えるストリームの完了、期限超過時の取消、後続区間0要求、既存完成要約の保持を確認する。短縮テストだけで本番60秒設定を証明せず、用途からの値の検証と組み合わせる。
- 明示取消・reset・遅れて届く応答の拒否、Keychainエラー、未同意の送信0、通常回答のtimeoutを既存回帰で確認する。
- 新評価枠の固定8区間・16要求・US$1、旧台帳拒否、使用量不明時の停止、liveフラグ相互排他を先にRedにして実装する。
- 資料更新→Red→最小実装→Greenの順とし、SwiftLint strict、実APIを除く全体テスト、Debug/Releaseビルド、差分チェックを実行する。

## 新しい実API枠（承認対象）

- 評価IDを`pr7-summary-deadline-20261111`、opt-inを`CONFLINGO_SUMMARY_DEADLINE_LIVE`として固定する。実施日が変わっても、この承認済みIDを別の追加枠へ使い回さない。
- S08-ja（3区間）→S08-en（3区間）→S07-en（2区間）を各1回。未合格5区間と、期限変更の回帰として既合格3区間を含む。**生成8＋計数8＝最大16要求、推定US$1以内**。
- `gemini-3.8-flash`／medium／8192 token、入力上限6000 token、同じfixture・構造・意味・言語・Markdown条件を維持する。計測wrapperも維持する。
- [2026-11-11確認の料金](https://aistudio.google.com/docs/pricing#gemini-3.8-flash)では入力US$0.75、思考込み出力US$3.75／100万token。計数無料。20%余裕込み8区間上限想定はUS$0.338112。実行前に料金条件を再確認し、値上げで承認額を超える見込みなら送信しない。
- 先行2枠の38要求・既知US$0.0989775・不明予約US$0.084528＝管理額US$0.1835055を保持する。上限想定を追加した累計はUS$0.5216175、新規US$1枠を含む管理上の最大はUS$1.1835055。実請求額の保証ではない。
- 新しい永続台帳へ送信前予約し、旧2台帳と評価JSONは不変にする。開始済みの台帳再開、同一区間再送、複数liveフラグ同時指定を拒否する。PR6/PR8/既存PR7評価の側からも新フラグとの同時起動を拒否する。
- timeout・通信失敗・取消・usage欠落・上限超過・記録失敗では後続を停止し、不明分の予約を保持する。残枠の自動消化や60→90秒への再延長はしない。
- 製品Keychainを使用する。再ビルドでOS認証が必要なら既存の読取専用確認を使い、キーを表示・移動しない。回答本文は認証付きloopbackのメモリで意味判定後に破棄し、計測・根拠対応・判定・使用量・ハッシュのみ保存する。

## 完了条件と報告

ローカル検証が成功し、新枠3/3会議・8/8区間が60秒以内で品質条件を満たした場合に、この修正の受入を合格とする。過去2回のtimeoutは履歴として残し、単一実行で16/16会議が成功したとは報告しない。失敗しても結果と未実施区間・送信数・予約額を保存する。

60秒への変更で停止した通信を待つ時間も最大30秒増える。20区間を逐次処理する上限、利用者の取消操作、候補の未確認状態は維持する。合成8区間の評価で実音声p95・60分耐久・PR7全体・Gate Cを合格にしない。

結果は`docs/validation/pr7-summary-deadline.md`と本文なしJSONへ記録し、plan.mdと関連資料・正本を同期する。PR #19の同じブランチへ変更を重ねる。コミット・pushは明示指示があるまで実行しない。

## 実施結果（2026-11-11）

要約だけ60秒へ変更し、372テスト／63 suites・lint142ファイル違反0・Debug/Release成功。31秒後の応答が既定設定で完了する回帰を確認。新規実APIは3/3会議・8/8区間合格、16要求・推定US$0.06878175。旧予約込み累計US$0.25228725。今回の実APIは全区間30秒未満であり、期限延長による実APIの改善効果や長期安定性は未証明。[結果](../validation/pr7-summary-deadline.md)。
