# dotfiles

AIエージェントで共通に使うルールとスキルの正本です。

## 構成

- `AGENTS.md` / `CLAUDE.md`: 毎回のセッションで読まれる入口。`CLAUDE.md` は `@AGENTS.md` を取り込むだけで、内容は同じ
- `.claude/rules/`: 共通ルール
- `.claude/skills/`: スキル
- `docs/setup/`: 環境を初期設定するときの手順書（[AIエージェント環境のセットアップ](docs/setup/ai-agent-setup.md)）
- `.work/`: 構築中の方針メモ
