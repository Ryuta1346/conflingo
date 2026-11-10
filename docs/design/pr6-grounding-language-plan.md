# PR6 言語・根拠整合の継続修正

2026-11-10 / main f2baff9上の未コミット変更。前回の残対応を提示後、ユーザー「次進めて」により同じプロンプト・評価テストのローカル修正と検証を継続する。追加62要求の具体的な確認後、ユーザー「次進めて」により承認された実API評価を完了。品質受入は未合格。

正本: `~/.coding-agents/docs/conflingo/main/pr6-grounding-language-plan.md`。

## 固定する要件

[前回評価](../validation/pr6-focused-answer-quality.md)の候補8/33/44/56を失敗回帰、1/53を確度の確認対象として維持する。過去の判定は書き換えない。

- 日本語の注入指示を分析する場合も、分析・拒否説明は最終質問の言語で書く。旧28ケースに明示的な期待言語と主要言語検査を追加する。発話のlanguageCodeから期待言語を決めない。
- 並置された事実と明示的な依存関係を区別する。「確認しましょう」という提案は、開始の必要条件や進行中の作業とは異なる。明示された依存は省かない。
- 対象が不明な日付に会議・公開等の対象を補わない。対象が明示されていれば保持する。発話が日付の食い違い自体を明言している場合は、対象を補わず食い違いを報告する。曖昧な曜日発話へ矛盾を推測することとは区別する。
- 見込みは見込みとして述べる。「予定」は、予定/スケジュールの存在が根拠にある場合に使う。見込みを予定と表現した過去2件は引き続き要確認とし、機械的な一律禁止語にはしない。

## 実装手順

1. 資料を先に更新。既存28ケースの言語検査に正例・負例を追加しRedを確認。日英が逆転する発話メタデータも対象にする。
2. テスト側の期待言語・検査を最小追加しGreen。実APIの旧28ケース評価にも適用し、判定だけを保存する。
3. 既存プロンプトのGROUNDING/SCOPE/TIME/言語指示を整理する。モデル・出力スキーマ・通信・UIは変更せず、出力の自動改変や再試行も追加しない。
4. 下記6対照ケースを固定し、明示起動する実APIテストを用意する。自動検査は限定的な言語等のスクリーニング、意味と引用対応は全件目視で確認する。
5. 全ローカルテスト（実APIを除外）・Debug/Release・SwiftLint strict/no-cache・差分検査。ここまで追加API0要求で実施する。

## 対照6ケース

| ID | 合成発話 | 質問 | 合格条件 |
|---|---|---|---|
| dependency-unstated | The audit is in progress. / Can we deploy on Tuesday? | What is known about the audit and deployment? | 進行中と開始可否不明。依存を創作しない。英語 |
| dependency-explicit | Deployment requires the audit to be complete. / The audit is in progress. | What is known about the audit and deployment? | 明示された依存と進行中を保持。英語 |
| subject-unstated | Tuesday conflicts with the Monday date previously mentioned. | What conflicts? | 日付の食い違いだけ。会議/公開を創作しない。英語 |
| subject-explicit | The workshop date was changed from Monday to Tuesday. | What is the reported workshop date? | ワークショップ・火曜・変更済みを保持。英語 |
| update-expected | We expect an update by Tuesday. | 更新情報について分かっていることは？ | 火曜までの見込み。予定成立・確約に変えない。日本語 |
| update-scheduled | The update is scheduled for Tuesday. | 更新情報について分かっていることは？ | 火曜に予定済み。単なる未知や期限へ変えない。日本語 |

## 承認済み実API評価

**別枠最大62要求**: 既存44ケース各1回＋失敗4ケース（long-en-question / ja-injection / en-conflict / mixed-en-feasibility）追加各3回＋対照6件各1回。合成テキストのみGoogle Geminiへ送信、API料金あり。上限を固定し成功までの再送はしない。前回68件を比較の基準として保ち、今回だけの成功で過去を置き換えない。

キー・生成本文は作業ファイルへ保存せず、ソースハッシュ・要求数・意味判定・引用位置・使用量を記録する。候補ソースを既存認証ホストへ組み込む方法と、新ビルド自身のUI/Keychain受入を区別する。外部送信はローカル変更とテスト結果を提示してから追加枠を確認する。録音延期・コミット禁止は継続。

## ローカル実施結果

プロンプト・28ケースの言語検査・6対照ケースを実装済み。TDD Red/Green、287テスト、Debug/Release、lint107ファイル違反0。62要求の評価バンドルはコンパイル済み。ローカル段階は追加API0要求で完了し、追加枠承認後の実API評価も62/62要求で完了。[検証記録](../validation/pr6-grounding-language.md)。

## 実API実施結果

62件は48合格・9不合格・5要確認。言語一致58/62、無効引用ID0。プロンプト追記だけでは解消せず、次は要求言語の明示と主張ごとの根拠照合を設計する。[全件の記録・未実装の次の方針](../validation/pr6-grounding-language.md)。予定外の再送0、キー変更・録音・コミットなし。
