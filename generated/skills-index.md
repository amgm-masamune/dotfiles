# Skills Index

`.agents/skills/` にある、作業内容に応じて読み込むスキルの一覧です（`.claude/skills/` はそこへのシンボリックリンク）。全スキルを毎回読むのではなく、ここで該当スキルを探してから個別ファイルを取得してください。

## スキル一覧

| スキル | 用途・トリガー | 本文 |
|---|---|---|
| Android CI：署名固定とビルド番号増加 | Android / CI / ビルド / デバッグビルド / APK / AAB / 署名 / keystore / versionCode / 更新（上書きインストール）エラー / 公開リポジトリ / Secrets / GitHub Actions | [android-ci-signing/SKILL.md](../.agents/skills/android-ci-signing/SKILL.md) |

## 運用

- この一覧は、スキルを自動で発見できない環境で一括取得するための暫定回避案です。`AGENTS.md` / `CLAUDE.md` からは参照しません。
- スキルを追加・変更したら、この一覧を更新します。
- この一覧は入口・索引であり、スキル本文の代わりではありません。
- GitHub Actionsで一覧生成を自動化する場合も、本文を二重管理せず、本文ファイルから一覧を生成します。

## 移行元

- Notion「スキル」データベースの「Android CI：署名固定とビルド番号増加」
- https://app.notion.com/p/3f50e054862281469820c9fa70e7d3dc
