---
name: android-ci-signing
description: AndroidアプリのCIビルドで署名鍵を固定し、versionCodeを単調増加させて既存インストールへの更新を維持する。Android、CI、APK、AAB、署名、keystore、versionCode、GitHub Actionsに関する作業で使用する。
---

# Android CI：署名固定とビルド番号増加

移行元: Notion「Android CI：署名固定とビルド番号増加」
https://app.notion.com/p/3f50e054862281469820c9fa70e7d3dc

## 目的

CIで作成したAndroidアプリを、既存インストール済みアプリの上書きアップデートとしてインストールできる状態に保つ。

## 必須ルール

- **署名は固定**: 毎回同じkeystore・同じキーエイリアスで署名する。
- **ビルド番号は増加**: `versionCode` は前回より必ず大きくする。同じ値や減少は禁止。
- 同じ `applicationId` を維持する。

## 署名

- debug keystore（自動生成）でリリース用ビルドを作らない。
- CIの実行ごとにkeystoreを新規生成しない。
- keystore本体をリポジトリにコミットしない。GitHub Actions Secrets等のシークレット保管先にbase64で保存し、ビルド時に復元する。
- 必要なSecretsの例: keystore（base64）、storePassword、keyAlias、keyPassword。
- `build.gradle` の `signingConfigs.release` は環境変数から設定する。
- keystoreと各パスワードは安全な別の場所にもバックアップする。紛失すると以後アップデートできなくなる可能性がある。

## ビルド番号

- `versionCode` はCIの実行番号（例: GitHub Actionsの `run_number`）に、既存最大値以上になるオフセットを加える方法などで、必ず単調増加させる。
- 初回は、配布済みの最大 `versionCode` を確認してからオフセットを決める。未確認なら実装を確定せず、要確認として扱う。
- `versionName` は人が読む版数であり、`versionCode` とは別に管理する。
- Gradleには `-PversionCode=...` などで値を渡す方法を検討する。

## ビルド後の確認

- `apksigner verify --print-certs` で署名証明書のSHA-256が前回と同じか確認する。
- `aapt dump badging` などで `versionCode` が前回より大きいか確認する。
- いずれかが不一致ならCIを失敗させる。

## 実装前に確認する事項

- 対象プロジェクトのCI基盤（GitHub Actions等）。
- 配布済みの最大 `versionCode`。
- 既存アプリがどのkeystoreで署名されているか、元のkeystoreを保有しているか。
