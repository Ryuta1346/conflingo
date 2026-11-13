# R3 — v1保存形式の固定・検証結果

2026-11-14 / 基点: main `0314aed` / [承認済み計画](../design/r3-persistence-golden-plan.md)

## 結果

Sessions・資料ライブラリのv1を6種類の固定JSONで検証する5テスト（引数展開12ケース）を追加した。製品コードの修正は不要だった。fixtureは合成データであり、実ユーザーの保存ファイルや過去リリースから採取したファイルではない。

| 検証 | 結果 |
|---|---|
| 追加テスト | 5テスト・12ケース成功。Meeting／Conferenceの基本・拡張、通常文書・リポジトリを確認 |
| 全テスト | 604件中597成功・実API評価7skip・失敗0、108 suites、47.382秒 |
| SwiftLint 0.65.1 | `--strict --no-cache`、236ファイル、違反0 |
| Release | 署名なし、arm64 / x86_64成功 |
| リソース配置 | テストバンドル内JSON 6件。Releaseアプリ内JSON 0件、テストバンドル0件 |
| 非互換変更の検出 | 必須キー・enum名変更と、任意キー変更による情報消失を検出。下記参照 |

## 固定した利用動作

- 既存JSONを一時ディレクトリへ配置し、`SessionFiles` / `KnowledgeLibraryFiles` のlist/loadと検証を通す。読込による元ファイルの書換えがないことを確認する。
- JSONDecoder→JSONEncoderの構造比較に加え、実ファイルへの新規保存・更新出力も固定JSONと比較する。キー順・空白・エスケープ表記を正規化するが、配列順・キー・値は維持する。
- 保存APIが発行する資料ID・revisionのみ返り値を使って期待値へ反映。日時・タイトルの変更は明示した固定値で検証する。同じ資料の再保存ではrevisionと元ファイルのバイト列が変わらないことも確認する。
- Meetingの2入力、原文／訳文、候補の3確認状態、回答・確認質問・リスク、要約、資料・リポジトリ・Web引用を確認。
- Conferenceの4翻訳状態とfailedの関連値、未翻訳、拡張入力属性、採用補正と元の原文／訳文、用語を確認。
- Markdownには原文・訳文・要約・引用・採用補正が残る。日時表示のタイムゾーンに依存する全文比較は行わない。
- 通常資料と複数ファイルのリポジトリを索引へ復元し、検索・引用の取込日時・パス・snapshot ID・SHA-256が維持されることを確認。

## Red / Greenと検出力

既存の保存契約を追加テストで固定する作業のため、製品コードが正しい基点では追加テストは初回から成功した。資源不足やビルド失敗を互換性のRedとして扱っていない。

`/tmp/conflingo-r3-mutation`にソース・テスト・Xcodeプロジェクト・Configをコピーし、以下のCodingKeys変更を一時的に入れた。encoder / decoderの双方が同じ新キーを使用する状況を作り、fixtureは変更していない。

| 一時変更 | 検出結果 |
|---|---|
| `SessionSnapshot.meeting`のJSON case名を`renamedMeeting`へ、`SavedKnowledge.content`を`renamedContent`へ変更 | MeetingのtypeMismatch、資料のkeyNotFoundを検出。5テスト中4失敗、8 issues。Conferenceは成功 |
| 上記を戻し、`MeetingExportSnapshot.translations`を`renamedTranslations`へ、`ConferenceSnapshot.support`を`renamedSupport`へ変更 | decoderは任意値をnilにするが、拡張JSONの構造比較と値・Markdownの確認が失敗。5テスト中3失敗、12 issues。基本JSONと資料は成功 |

意図的な変更は一時コピーだけに適用し、製品作業コピーには入れていない。一時コピーを元の製品ソースへ戻した後、同じ5テスト・12ケースが0.009秒で再び成功した。

## 実行方法・証跡

```sh
# 実API評価の8フラグをすべて0にした環境で実行
xcodebuild test -project ConfLingo.xcodeproj -scheme ConfLingo \
  -destination 'platform=macOS' -derivedDataPath /tmp/conflingo-r3-build \
  CODE_SIGNING_ALLOWED=NO

/tmp/conflingo-swiftlint-0.65.1/swiftlint lint --strict --no-cache

xcodebuild -project ConfLingo.xcodeproj -scheme ConfLingo \
  -configuration Release -derivedDataPath /tmp/conflingo-r3-release \
  CODE_SIGNING_ALLOWED=NO build
```

追加テスト・変異確認は`-only-testing:ConfLingoTests/SessionsGoldenTests -only-testing:ConfLingoTests/KnowledgeGoldenTests`で実行。
実APIフラグは`CONFLINGO_LIVE_AI`、`CONFLINGO_FOCUSED_LIVE_AI`、`CONFLINGO_GROUNDING_LIVE_AI`、`CONFLINGO_RAG_LIVE`、`CONFLINGO_SUMMARY_LIVE`、`CONFLINGO_SUMMARY_REMAINING_LIVE`、`CONFLINGO_SUMMARY_DEADLINE_LIVE`、`CONFLINGO_R2_SIZE_LIVE`。初回の追加テスト時も有効なフラグがないことを確認した。

ローカルログ:
- `/tmp/conflingo-r3-focused.log`
- `/tmp/conflingo-r3-all.log`
- `/tmp/conflingo-r3-lint.log`
- `/tmp/conflingo-r3-release.log`
- `/tmp/conflingo-r3-mutation-required.log`
- `/tmp/conflingo-r3-mutation-optional.log`
- `/tmp/conflingo-r3-restored.log`

全テストのxcresult: `/tmp/conflingo-r3-build/Logs/Test/Test-ConfLingo-2026.11.14_00-18-08-+0900.xcresult`。
サンドボックス内の初回ビルドはSwiftマクロサーバー起動に失敗し、許可された通常環境で再実行した。一時コピーの初回はConfig不足によるビルド失敗があり、コピーを補ってから上記の変異確認を行った。PATHにSwiftLintがないため、既存の0.65.1バイナリを使用した。

## fixtureのSHA-256

| ファイル | SHA-256 |
|---|---|
| `r3-conference-basic.json` | `0b80d43e0222f057133b0021c534ab351a57ca66a2525c03a86fef50ba40c395` |
| `r3-conference-extended.json` | `2c1460d52cc10c018b08b83de3524d3e73e01016fa8f2196221d3efa48ba9dc6` |
| `r3-knowledge-document.json` | `b9b46bcc6f2d03ab2c9e5e2d72233110b9ea5050339e1bbdf4c77e36906bdfc2` |
| `r3-knowledge-repository.json` | `878d5b0d3c5ae77e5dad3d979883ed4a00e5dd2d3ccdddce734a906e3e029612` |
| `r3-meeting-basic.json` | `3cdb9f6648772cc0775fbadf87e1f16af75581ee676d8876a2dca3727f74a862` |
| `r3-meeting-extended.json` | `d4962699194cc75d6144914156ac0411ba376301143e4b829e045b208802ed9b` |

## 完了範囲・残件

自己レビューで、ランダムな期待値の生成がfixtureに混入しないこと、実ユーザーデータへのアクセスがないこと、非互換変更による情報欠落を検出すること、テスト資源がReleaseへ入らないことを確認した。ユーザー「コミットand PR作成」に基づき、`test/persistence-v1-golden`で`a59f0d6`をコミット・pushし、[Draft PR #34](https://github.com/Ryuta1346/conflingo/pull/34)を作成した（担当Ryuta1346）。2026-11-14にGitHub APIとローカルmainで、PR #34が`8fd8144a85900717bf5ca328af12dc559e9dc544`へマージ済みと確認した（GitHubのmerged_atは2026-11-13 15:29:35 UTC）。レビュー提出・コメントはともに0件だったが、同日にユーザー「レビューは完了してR4進めてる」からレビュー完了を確認した。レビュー本文・手段は未取得。R3はDONEとし、R4へ進む。今回の状態確認ではテストを再実行していない。

R4、実会議の品質ゲート、R2の他社実測などは今回の対象外。追加実API・音声取得は0。固定JSONでの互換性確認は実ユーザーデータ全件の検証を意味しない。
