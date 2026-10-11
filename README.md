# dotfiles

AIエージェントで共通に使うルールとスキルの正本です。

## 構成

- `AGENTS.md` / `CLAUDE.md`: 毎回のセッションで読まれる入口。`CLAUDE.md` は `@AGENTS.md` を取り込むだけで、内容は同じ
- `.agents/rules/`: 共通ルールの正本
- `.agents/skills/`: スキルの正本
- `.claude/rules/`、`.claude/skills/`: 上の2つへのシンボリックリンク（Claude Code 用）
- `generated/`: ルールとスキルの一覧。自動読み込みが使えない環境で一括取得するための暫定回避案
- `docs/setup/`: 環境を初期設定するときの手順書（[AIエージェント環境のセットアップ](docs/setup/ai-agent-setup.md)）
- `.work/`: 構築中の方針メモ
