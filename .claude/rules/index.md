# Shared Rules Index

このディレクトリは、セッション間・プロジェクト間で共有する共通ルールを管理します。本文の正本はGitHubです。

## 必須の読み込み

- [セッション・プロジェクト運用ルール](session-project-workflow.md)

## 運用

- この一覧は、`.claude/rules/` を自動で読み込めない環境で一括取得するための暫定回避案です。`AGENTS.md` / `CLAUDE.md` からは参照しません。
- そのような環境では、作業開始時にこの一覧を読み、必須ルールを読み込みます。
- 新しいルールを追加したら、この一覧にも追記します。
- ルール本文は必要な範囲で簡潔に保ち、スキル固有の詳細手順は `.claude/skills/` に置きます。
- ChatGPTなど外部からの自動指示注入ができない環境では、このファイルの存在だけでルールが適用されたとはみなしません。セットアップ手順は [docs/setup/ai-agent-setup.md](../../docs/setup/ai-agent-setup.md) を参照してください。

## 移行元

- Notion「Claude運用ルール」: https://app.notion.com/p/3ef0e054862281de8b5bce704e172315
