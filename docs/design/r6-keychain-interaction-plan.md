# R6-4 — Keychain操作の排他制御と認証UI設定の復元

> 2026-11-14マージ確認: 実装 `5fad038`を含む[PR #40](https://github.com/Ryuta1346/conflingo/pull/40)はローカルmain `33c8ae6`へマージ済み。独立レビュー・実機受入は継続。以下の未コミット・未PRはローカル検証完了時点の記録。

2026-11-14 / 調査基点: ローカルmain `18d0fcb`（PR #39マージ済み）。
状態: **2026-11-14、ユーザー「進めて」により計画承認済み。ローカル実装・自動検証済み。未コミット・未PR。**
正本: `~/.coding-agents/docs/conflingo/main/r6-keychain-interaction-plan.md`。

計画作成時の「進めて」は調査・計画作成として受領し、その後の計画提示に対する「進めて」で実装承認を受領した。Planモードへの切替機能は利用できないため、この文書で実装前の計画を提示する。

## 確認した事実

- `APIKeyCredentials.swift`の`KeychainAPIKeyStore.readSynchronously`は、staticな`readLock`で読出しを直列化し、`SecKeychainGetUserInteractionAllowed`で保存した設定を一時的にfalseにして読出し、deferで戻す。
- `save`の`SecItemUpdate`→必要時の`SecItemAdd`と、`delete`の`SecItemDelete`はこのlockを取得しない。読出しはdetached task、書込みはMainActor上の同期処理なので、別接続の読出しを含めて重なり得る。OSでの実障害は今回未再現。
- 復元時の`SecKeychainSetUserInteractionAllowed`の戻り値は無視される。復元が失敗しても、キー取得成功・未登録という結果を返せる。
- 製品コード内のSecurity Keychain呼出しはこのストアに集約されている。LLM設定の接続先変更・削除も同じストアを通る。
- `APIKeyCredentialsTests`には一意なテスト用項目の登録・読出し・置換・削除と、古いrefreshによる状態上書き防止がある。一方、読出しと書込みの交差、元設定false、設定復元の失敗を注入するテストはない。
- `GeminiInsightClient`と`LLMInsightClient`はキー取得後に取消を確認する。`SelectedLLMClient`は設定revisionも照合する。既存の「キー取得待ち取消後はHTTP送信0」を維持する。

既存の[受入記録](../validation/pr6-app-acceptance.md)は、file-based Keychainの認証待ち対策として現在の非対話読出しを導入した経緯を記録している。現在のSDKの`Security.framework/Headers/SecItem.h:1016`にも、旧Keychainでは`kSecUseNoAuthenticationUI`だけでUIを抑止できない旨の記載がある。`SecKeychain.h:634`以降でGet/Setの戻り値と非推奨指定を確認した。旧APIを単に削除して同等動作とみなす根拠はない。

SDK基点: `/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/Security.framework/Headers/`。今回の調査はソース・既存証跡・ローカルSDKの確認のみで、利用者のキーやOS設定を読み書きしていない。

## 提案する変更

### 1. 全ストア共通の排他制御

- 現在の読出し専用lockを、全`KeychainAPIKeyStore`で共有する操作境界へ移す。read/save/deleteのSecurity呼出しをすべて同じlockで保護する。serviceごとのlockにはしない。
- readでは、元設定取得→非対話化→読出し→元設定復元の全体を保護する。saveではUpdate→必要時Addを一続きの処理として保護する。deleteも同じ境界を通す。
- lockを保持する同期区間にawaitやMainActorへの同期呼出しを入れない。readのバックグラウンド実行、save/deleteの既存同期APIを維持する。
- Security呼出しだけを差し替える小さな内部境界を設け、fakeで処理の重なりと失敗を検証する。汎用の永続化基盤や独立モジュールは追加しない。

### 2. 復元と失敗の扱い

- 元設定true/falseを保存し、読出し成功・項目なし・読出し失敗・不正データのいずれも元設定に戻してから結果を返す。
- 元設定取得失敗時は読出しを始めない。非対話化失敗時も読出しを始めず、取得済みの元設定への復元を試みる。
- 復元失敗時はキーやnilを成功として返さず、既存の`InsightFailure.keyStorage`を返す。OSによる復元成功を保証したとは扱わない。
- 復元失敗時の元設定を共有境界内に保持する。以後の操作は同じlock内でその値への復元を先に1回試み、成功するまで項目の読出し・保存・削除へ進まない。失敗した状態を「新しい元設定」として取り込まない。無制限の自動リトライはしない。
- 復元済みなら、書込みは従来のクエリ・認証方針で実行する。読出し用の一時設定を保存・削除へ漏らさない。

### 3. 維持する契約と限界

- service/account、既存キー、ACL、署名条件、保存先、同期属性を維持する。Data Protection Keychainへの移行やキー再登録は含めない。
- 未登録と認証・保存失敗の表示を区別する。接続先変更時の削除失敗で設定を確定しない既存動作、送信許可解除、古いrefresh結果の排除を維持する。
- この排他制御が保護するのはアプリが所有するストア経路。OS内部や将来追加される別の直接呼出しまで直列化できるとは主張しない。
- 同期save/deleteは実行中のreadを待ち得る。read側がMainActorへ戻らない構造をテスト・レビューし、循環待ちを作らない。OS応答時間やUI無停止はこの変更で保証しない。全書込みの非同期化はUI・接続設定の状態遷移まで広げるため別課題とする。
- 非推奨APIの警告は残る。本件は非推奨APIの除去や性能改善の完了を目標にしない。

## 変更対象

| 対象 | 内容 |
|---|---|
| `ConfLingo/Meeting/Services/APIKeyCredentials.swift` | 共通操作境界への接続、既存ストアAPI維持 |
| 同ディレクトリの小さなKeychain操作ファイル（必要時のみ） | 共通lock、Security境界、復元処理 |
| `ConfLingoTests/APIKeyCredentialsTests.swift`・Keychain境界テスト | 競合・失敗・保存契約の回帰 |
| `ConfLingoTests/LLMSettingsTests.swift`・既存クライアントテスト | 既存の設定失敗・取消契約を確認。必要な不足ケースのみ追加 |
| `plan.md`・本計画・新しい検証記録 | 実装結果と未受入を区別して更新 |

## 受入条件

| ID | 期待する振る舞い |
|---|---|
| K01 | serviceの異なる2つのreadも直列化され、元設定true/falseの双方を保存・復元する |
| K02 | readが非対話化した区間にsave/deleteのSecurity呼出しが入らない。復元後に書込みを開始する |
| K03 | Update→Addの間にも別のread/save/deleteが入らず、Update成功時はAddしない |
| K04 | 読出し成功・項目なし・OSエラー・不正なデータ/UTF-8の各結果で復元を実行し、結果を正しく区別する |
| K05 | 設定取得・非対話化の失敗では項目を読まない。復元失敗は成功結果を返さず、後続の復元成功まで全項目操作を抑止する |
| K06 | 保存・削除の失敗でもlockを解放し、続く操作が進む。元設定falseを勝手にtrueにしない |
| K07 | 一意な専用テスト項目で未登録→保存→読出し→置換→削除を維持。利用者の既存キーには書き込まない |
| K08 | 古いrefreshによる状態上書き防止、接続先変更時の失敗、キー取得待ち取消後のHTTP送信0を維持 |

並行テストはfake境界の開始・解放合図で順序を固定し、sleepの長さに依存させない。テストの失敗・タイムアウト時にも待機を解放して後続を止めない。実Securityのプロセス全体設定を競合させるテストは行わない。

## 実装順と検証

1. 計画承認後に`tdd`スキルを適用。予定仕様を関連資料へ反映してから、K02/K05を中心に最小の注入境界とテストを追加する。現行の競合・復元失敗無視で意図したRedを確認する。
2. 共通排他・復元処理を最小実装し、関連テストをGreenにする。不要になったread専用lockや重複処理を除去する。
3. 全テスト、SwiftLint strict/no-cache、Releaseビルド、`git diff --check`を実行する。実API評価フラグはすべて0にする。コマンド基準は[直前の検証記録](../validation/r6-meeting-translation.md#再実行と証跡)。
4. 実行結果を`docs/validation/r6-keychain-interaction.md`へ記録する。新署名での利用者キー認証・実モデル・実音声・Gate全体の受入を自動テストの成功に置き換えない。

計画作成時点では資料のみで製品lint・テスト・ビルドは未実行。実装後の結果を別途記録する。独立レビュー完了は確認できておらず、R5/R6の受入をDONEへ変更しない。

## 承認対象

共通の排他制御、認証UI設定の復元失敗の通知と後続操作の抑止、上記の回帰テストを実装する。ユーザー指定AGENTS.mdの「実装前に実装計画を作成し承認を得る」に従い、2026-11-14のユーザー「進めて」でこの具体的な計画への承認を受領した。

## 実施結果（2026-11-14）

承認済みの共通排他・復元失敗処理を実装。共有状態は`Mutex<Bool?>`で保護し、SwiftのSendable検査を回避せずに扱う。11テスト定義（38ケース）を追加した。Redは3テスト定義・12 issues、Green後の最終全体は667件中660成功・実API7skip、121 suites、165.252秒（Xcode並列テスト無効）。Lint251ファイル違反0、arm64/x86_64 Release成功。

途中で新しい並行テストの共有スレッドプール待機を専用Threadへ修正した。既存UI2件のタイミング失敗は単独・最終全体で再確認し成功したが、不安定性を残件として記録する。同期save/deleteの待機、既存非推奨API警告、独立レビュー・実機受入は継続。[検証結果と途中の失敗](../validation/r6-keychain-interaction.md)。
