# AGENTS.md

AIエージェント共通のルールとスキルの正本リポジトリです。

- 共通ルール（必須）: `.claude/rules/` 配下。自動で読み込まれない環境では、配下の `.md` を読む。
- スキル: `.claude/skills/<名前>/SKILL.md`。作業内容が `description` に合うときだけ本文を読む。
- 環境を初期設定するときだけ: [docs/setup/ai-agent-setup.md](docs/setup/ai-agent-setup.md)（通常のセッションでは読まない）
