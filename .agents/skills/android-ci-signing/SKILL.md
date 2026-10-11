---
name: android-ci-signing
description: AndroidアプリのCIビルドで署名鍵を固定し、versionCodeを単調増加させて、デバッグビルド・既存インストールへの更新（上書きインストール）エラー（INSTALL_FAILED_UPDATE_INCOMPATIBLE等）を防ぐ。公開リポジトリでの鍵の扱い、GitHub Actions Secrets、Roomのマイグレーション、Releaseでの配布にも対応する。Android、CI、APK、AAB、署名、keystore、versionCode、デバッグビルド、Secrets、GitHub Actionsに関する作業で使用する。
---

# Android CI：署名固定とビルド番号増加

移行元: Notion「Android CI：署名固定とビルド番号増加」
https://app.notion.com/p/3f50e054862281469820c9fa70e7d3dc

## 目的

CIで作成したAndroidアプリを、既存インストール済みアプリの上書きアップデートとしてインストールできる状態に保つ。

## 必須ルール

- **署名は固定**: 毎回同じkeystore・同じキーエイリアスで署名する。
- **ビルド番号は増加**: `versionCode` は前回より必ず大きくする。同じ値や減少は禁止。
- 同じ `applicationId`（サフィックス含む）を維持する。
- Room等のスキーマを変えるときは明示的なMigrationを用意する（後述）。

更新エラーの主な原因: 署名の変化（CIが毎回新規ランナーで `~/.android/debug.keystore` を作る場合が最有力。`INSTALL_FAILED_UPDATE_INCOMPATIBLE`）、`versionCode` が同じ/下がる、`applicationId` の変化、Migration無しのスキーマ変更（破壊的フォールバックでデータ消失）。

## 署名

- debug keystore（自動生成）でビルドを作らない。CIの実行ごとにkeystoreを新規生成しない。
- CIでは必ず固定鍵で署名する。**鍵（Secret）が無ければCIを失敗させる**。黙ってAGP標準のデバッグ鍵に落ちると元の不具合が再発する。
- 鍵のコミット可否は宛先リポジトリの公開/非公開で決める。push前に匿名APIで確認する（`curl -s https://api.github.com/repos/OWNER/REPO` が取得できれば公開）。
  - 公開リポジトリ: 鍵をコミットしない。GitHub Actions Secretsで供給する。APKも公開されるため、APKにAPIキー等を入れない。
  - 非公開リポジトリの個人デバッグ用途に限り、デバッグ鍵のコミット運用もあり得るが、リリース署名には使わない（要確認の運用。一般的か・推奨かは未確認）。
  - 一度でも公開した鍵は破棄して作り直す（ローテーション）。履歴に残っていても使わない。
- keystore形式は既定のPKCS12を前提にする。PKCS12では**キーパスワード=ストアパスワード**でないと署名できない（別値だと `jarsigner: key associated with <alias> not a private key`）。よってキーパスワード用のSecretは不要。JKSでキーパスワードを別にする運用は旧形式のみ。
- **Secretは2つで足りる**: keystoreファイルを `base64 -w0` した文字列と、パスワード。
- **alias は秘密ではない**ので `build.gradle(.kts)` に定数で書く（Secret/環境変数にしない）。キーストア生成時の `-alias` と一致させる。
- 署名の準備ステップ: Secretが空なら `::error` で止める。復元後に `keytool -list` でパスワード不一致を早期検出する。パスワードをログに出さない（`set -x` 禁止）。
- Secretをユーザーに渡すときは、Secret1つにつき1ファイル（ファイル名=Secret名、中身=値のみ・末尾改行なし）で送る。「NAME=値」を1ファイルにまとめると区切りが分からない。値自体はこのスキルや会話ログに残さない。
- keystoreとパスワードは安全な別の場所にもバックアップする。紛失すると以後アップデートできなくなる可能性がある。

## ビルド番号

- `versionCode` は単調増加させる。方法は次のどちらか。
  - CIの実行番号（`run_number`）に、既存最大値以上になるオフセットを加える。
  - エポックからの分 `(System.currentTimeMillis()/60000).toInt()`。CIでもローカルでも同じ式で単調増加し、オフセット不要（2026-10時点で約3000万、Int上限は約21億）。
- 既存アプリの最大 `versionCode` を下回らないことを確認する。未確認なら実装を確定せず、要確認として扱う。
- `versionName` は人が読む版数であり、`versionCode` とは別に管理する。

## Room・データ保全

- `exportSchema = true` にしてスキーマJSONをコミットする。`version` を上げるたびに明示的なMigrationを書き、`fallbackToDestructiveMigration` は使わない。
- `AndroidManifest` は `allowBackup=false`（自動バックアップ復元でDBだけ古くなる事故を避ける）。
- 起動時のDBオープン失敗は、画面に原因を出す。

## 配布（GitHub Release）

- 成功時に固定タグ（例 `app-debug-latest`）のプレリリースを毎回作り直し、アセット名も固定する。`permissions: contents: write` が必要。
  `gh release delete TAG --cleanup-tag --yes || true` → `gh release create TAG app.apk --prerelease --target $GITHUB_SHA`
- ワークフロー内で署名SHA-256と `versionCode` を出し、Release本文に載せる。
- 非公開リポジトリのReleaseは、GitHubにログインしたブラウザからしか取得できない。

## ビルド後の確認

- `apksigner verify --print-certs` で署名証明書のSHA-256が前回と同じか確認する。
- `aapt dump badging` などで `versionCode` が前回より大きいか確認する。
- いずれかが不一致ならCIを失敗させる。

## 実装前に確認する事項

- push先リポジトリ（間違った宛先へのpushは自力で消せないことがある。ユーザーの既存の別アプリのリポジトリに無関係なアプリをpushしない）と、その公開/非公開。新規リポジトリはClaudeには作れないので、ユーザーに空のリポジトリを作ってもらう。
- 対象プロジェクトのCI基盤（GitHub Actions等）。
- 配布済みの最大 `versionCode`。
- 既存アプリがどのkeystoreで署名されているか、元のkeystoreを保有しているか。

## サンドボックス制約

- クラウドのサンドボックスは Google Maven / Android SDK配布 / Maven Central / Gradle配布に届かない（403）ことがあり、ローカルビルドできない場合がある。コンパイル確認はGitHub Actionsで行う。
- 失敗内容はワークフローの要約ステップで `::error` アノテーションにして、`gh api repos/OWNER/REPO/check-runs/<id>/annotations` で読む（認証なしで読める。ジョブログ全文は認証が必要）。
- `git push` は通っても、ブランチ/タグの削除（`push --delete`）は403で拒否されることがある。Release・Actions履歴の削除は認証付きAPIが必要。

## 更新履歴

- 2026-10-11 personal-record-app の実装で確認した知見を反映（PKCS12のキーパスワード、Secret2つ、alias固定、公開リポジトリの確認、サンドボックス制約）。
