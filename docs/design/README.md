# ConfLingo — PR5-A Design Review

2026-11-08 / v0.1 / **モックの方向性はユーザー承認済み**。PR5-A/BはPR #10でマージ済み、残る受入待ち（REVIEW）。PR5-Cは実装・自動検証済み（REVIEW）。

## 操作モック

**[プロトタイプを開く](mockups/index.html)** · サーバー起動中は [ローカルプレビュー](http://127.0.0.1:8765/mockups/)

外部ライブラリ・フォント・AI通信なし。HTMLを直接ブラウザで開けます。コピー操作などはlocalhost環境を推奨します。

```sh
python3 -m http.server 8765 --bind 127.0.0.1 --directory docs/design
```

上部の「画面」「状態」「配色」「文字」はレビュー専用の操作です。9画面と46の画面別状態を閲覧できます。これは46種類の異なる製品状態を意味せず、同じ状態の画面別組み合わせです。

1. Meeting Liveで提案の根拠を開き、会話との対応を見る。
2. 「小さく表示」でFloatingへ。一時停止・AI停止・非表示・展開を試す。
3. 「会議を終了」からReviewへ進み、候補を確認/却下する。
4. 上部でMeeting準備へ移動し、通知・同意とAI許可の違いを見る。
5. Conferenceの準備で文字起こしのみ・辞書管理を試し、字幕画面で拡大/停止/書き出しを確認する。
6. 上部の状態で権限拒否、入力切断、停止失敗、AI送信中、オフラインを比較する。

固定した架空の日本語・英語の会話を使っています。言語設定を変えてもサンプル本文の翻訳は行いません。状態選択の「通常」は表示確認用の稼働例であり、実OSの許可取得を意味しません。保存・削除・辞書編集はページ内だけで、リロードすると初期化されます。Markdown書き出しだけはサンプルファイルをダウンロードします。

## 画面一覧

| 画面 | 役割 | 画像 |
|---|---|---|
| Home | 字幕/会議の入口、明示保存したセッション | [Light](mockups/home-light.png) |
| Conference準備 | 言語・専用モード・用語辞書 | [Light](mockups/conference-setup-light.png) |
| Conference字幕 | 原文/翻訳、表示調整、開始停止、書き出し | [Light](mockups/conference-light.png) |
| Meeting準備 | 入力別言語、通知・同意、AI送信範囲 | [Light](mockups/preparation-light.png) |
| Meeting Live | 提案、根拠、会話、手動質問 | [Light](mockups/meeting-light.png) / [Dark](mockups/meeting-dark.png) / [720px・拡大](mockups/meeting-narrow.png) |
| Floating | 重要提案1件と入力/AI状態、停止 | [Light](mockups/floating-light.png) |
| Meeting Review | 候補確認・却下、保存/破棄、書き出し | [Light](mockups/review-light.png) |
| Sessions | 明示保存した会議の検索・閲覧・削除 | [Light](mockups/sessions-light.png) |
| Settings | 入力、辞書、送信と保持の方針、表示 | [Light](mockups/settings-light.png) |

通常画像は1512×1100のブラウザで撮影。狭幅画像は720×900、文字125%で全ページ撮影。実Macのウィンドウ/VoiceOver/画面共有の検証ではありません。

## 設計資料

- [情報設計・現行UX監査・旧新対応表](app-information-architecture.md)
- [デザインシステム・部品と操作規則](design-system.md)
- [状態・操作フロー・受入仕様](ux-states-and-flows.md)
- [検証結果と制約](validation.md)
- [作業計画](pr5-a-design-plan.md)

## 承認した方向性

Conferenceでは字幕を最優先にし、Meetingでは提案を主領域・発話を補助領域に置きます。既存の辞書・文字拡大・保存は維持します。音声収集、クラウド送信、セッション保存は別々に表示し、候補は明示確認するまで未確定にします。

2026-11-08、チャットでMeeting / Conference / Floating / Reviewの4画像を提示した後、ユーザーから「OK」を受領。これをモックの方向性の承認として記録します。個別状態・全操作・実機受入をユーザーが検証したという意味ではありません。

[PR5-B実装計画](pr5-b-implementation-plan.md)は承認済み。実装したConferenceの[ネイティブ画像・検証結果](../validation/pr5-b-conference.md)を確認できます。PR5-A/BはPR #10でマージ済みです。個別状態・全操作の受入記録は未完了のためREVIEWを維持し、Gate U合格やDONEとは扱いません。画像は承認時の版として保持しているため、画像内の「承認待ち」は撮影時の表示です。

[PR5-C実装計画](pr5-c-implementation-plan.md)を承認後、Meeting UI・小窓・PR4接続を実装しました。[検証記録・ネイティブ画像](../validation/pr5-c-meeting.md)を参照してください。実音声受入は延期中です。
