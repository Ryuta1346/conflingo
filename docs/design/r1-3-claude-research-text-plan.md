# R1-3 ClaudeのWeb調査本文

2026-11-13 / main `ab2c4ae`＋R1-2の未コミット変更。ユーザー「進めて」を、直前に提示したR1-3の修正・検証への承認として記録する。
正本: `~/.coding-agents/docs/conflingo/main/r1-3-claude-research-text-plan.md`。

## 問題・方針

`LLMResearchResponse.claude`は引用を付加した各textブロックを`"\n\n"`で結合する。文の途中でブロックが分かれている場合にも段落が追加される。既存テストはtextブロック1個の応答のみで、この不具合を検出できない。

[Claude Web searchの公式応答例](https://platform.claude.com/docs/en/agents-and-tools/tool-use/web-search-tool#response)には、文の前置きと引用付きの続きが別textブロックで示されている。[引用仕様](https://platform.claude.com/docs/en/build-with-claude/citations#how-citations-work)も、主張とその引用に応じて複数のtextブロックが返ることを説明している。これを根拠に、ブロック境界を段落とみなさず、各textの空白・改行と引用位置をそのまま連結する。

製品コードの変更はClaudeの結合箇所に限定する。Gemini/OpenAIの解析、引用URLの検証・重複排除、応答サイズ上限、保存形式は維持する。実応答サイズ調査は次のR2で扱う。

## 受入条件・手順

1. 資料更新後、検索結果・複数text・複数引用を含む合成応答を追加。日英・絵文字の文中分割と、空白／改行を含むブロック境界が保持されるテストでRedを確認する。
2. 引用マーカーを各ブロック末尾に残し、本文へ追加の区切りを挿入しない最小修正を行う。同一URLの引用番号再利用、表示リンク、JSON往復とMarkdown出力、不明な引用URLの拒否を確認する。
3. 関連テスト・全テスト（実API評価無効）、SwiftLint、Releaseビルド、差分レビューを実施。結果と未検証範囲を本計画とplan.mdへ反映する。

実Claude APIへの送信は行わない。コミット・push・PR作成は対象外。R1-2の変更は保持する。

## 検証結果

- 製品コードはClaudeの結合を`texts.joined()`へ変更し、理由のコメントを追加した。引用の末尾挿入・URL検証・重複排除・サイズ上限・他プロバイダの処理は変更していない。
- `ClaudeResearchResponseTests`に4テスト定義・10ケースを追加。日英の文中分割、絵文字、空文字・空白・タブ・単改行・段落改行、2出典と同一出典の再引用、リンク位置、JSON往復、Markdown出力、不明／危険な引用URLの拒否を検証。
- `red.log`: 4定義中3定義で計9箇所の期待不一致。文中・ブロック境界に余計な空行が入り、Markdownへも残ることを修正前に確認。不正引用の拒否は成功。
- `green.log`: Web調査関連22テスト／4 suites成功。
- `all.log`と`test-summary.json`: **全580テスト／103 suites、574成功・実API評価6skip・失敗0**。R1-2を含む作業ツリー全体を検証した。
- `lint.log`: SwiftLint 0.65.1 strict/no-cache、228ファイル違反0。`git diff --check`成功。
- `release.log`: Releaseビルド成功（`CODE_SIGNING_ALLOWED=NO`、arm64・x86_64）。既存のSDK非推奨・AppIntents等の警告は残る。
- ログ: `/private/tmp/conflingo-r1-3/`。ビルドキャッシュはR1-2と共用。全回帰xcresult: `/private/tmp/conflingo-r1-2/build/Logs/Test/Test-ConfLingo-2026.11.13_21-41-50-+0900.xcresult`。

実Claude APIへの送信は0。今回のフィクスチャは合成応答であり、実モデルの回答・検索品質を保証するものではない。差分は自己レビュー済み、独立レビューは未実施。コミット・push・PR作成・インストール済みアプリ更新は未実施。plan.mdはREVIEWとし、次の実装タスクをR2とする。
