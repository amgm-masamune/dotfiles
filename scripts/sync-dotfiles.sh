#!/usr/bin/env bash
# dotfiles を ~/dotfiles に clone/pull し、~/.claude に共通ルールとスキルのリンクを足す。
#
# 使い方（標準入力のJSONは読み捨てる）:
#   sync-dotfiles.sh install   環境のセットアップスクリプト用: 同期 + リンク + フック登録
#   sync-dotfiles.sh session   SessionStart フック用: 同期 + リンク。スキルが増減したら再読み込みを要求
#   sync-dotfiles.sh turn      UserPromptSubmit フック用: 同期 + リンク。更新があったルールの本文を出す
#
# 方針
# - ~/.claude にある既存のファイルは消さない・上書きしない。足すのは次の2種類のリンクだけ。
#     ~/.claude/rules/<名前>   -> ~/dotfiles/.agents/rules/<名前>
#     ~/.claude/skills/<名前>  -> ~/dotfiles/.agents/skills/<名前>
#   別の中身が既にある名前はそのまま残し、session のときだけ知らせる。
#   消すのは「~/dotfiles を指していて、リンク先が無くなったリンク」だけ。
# - 標準出力はモデルのコンテキストに入る。変化も失敗も無いときは何も出さない。
#   ルールを pull で更新しても、読み込み済みの本文は自動では入れ替わらない。
#   そのため更新されたルールだけ、本文をここから出す。
# - 失敗しても exit 0（セッションやターンを止めない）。失敗は標準出力で知らせる。
# - 環境変数: DOTFILES_REPO, DOTFILES_DIR, CLAUDE_CONFIG_DIR,
#   DOTFILES_MAX_CONTEXT_CHARS（出力するルール本文の上限）, DOTFILES_SYNC_LOG（実行ログ）

set -u

MODE=${1:-turn}
REPO=${DOTFILES_REPO:-https://github.com/amgm-masamune/dotfiles}
DIR=${DOTFILES_DIR:-$HOME/dotfiles}
CFG=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
MAX=${DOTFILES_MAX_CONTEXT_CHARS:-8000}
LOG=${DOTFILES_SYNC_LOG:-$HOME/.dotfiles-sync.log}

OLD="" NEW="" ERR="" FRESH=0 RULE_LINKS=0 RULE_ADDED=0 SKILL_LINKS=0
CONFLICTS=() RULES_CHANGED=() RULES_DELETED=() SKILLS_CHANGED=()
MSG=""

log() { printf '%s %s %s\n' "$(date +%FT%T%z)" "$MODE" "$*" >>"$LOG" 2>/dev/null || true; }
say() { MSG+="$1"$'\n'; }
clean() { sed -E 's#(://)[^/@ ]+@#\1<cred>@#g' | tr '\n' ' ' | cut -c1-300; }

lock() {
  mkdir -p "$(dirname "$DIR")" 2>/dev/null || return 0
  if ( : >"$DIR.lock" ) 2>/dev/null; then
    exec 9>"$DIR.lock"
    flock -w 30 9 2>/dev/null || true
  fi
}

sync_repo() {
  local o
  if [ -d "$DIR/.git" ]; then
    OLD=$(git -C "$DIR" rev-parse HEAD 2>/dev/null || true)
    o=$(timeout 25 git -C "$DIR" pull --ff-only -q 2>&1) || ERR=$(printf '%s' "$o" | clean)
  elif [ -z "$(ls -A "$DIR" 2>/dev/null)" ]; then
    if o=$(timeout 120 git clone -q --depth 1 "$REPO" "$DIR" 2>&1); then
      FRESH=1
    else
      ERR=$(printf '%s' "$o" | clean)
    fi
  else
    ERR="$DIR は git リポジトリではなく、空でもないため同期できない"
  fi
  NEW=$(git -C "$DIR" rev-parse HEAD 2>/dev/null || true)
}

# $1=リンク元ディレクトリ $2=リンク先ディレクトリ $3=rules|skills
link_entries() {
  local src=$1 dst_dir=$2 kind=$3 e name dst cur n=0 added=0
  [ -d "$src" ] || return 0
  # リンク先ディレクトリごと利用者がリンクしている場合は触らない
  [ -L "$dst_dir" ] && return 0
  if [ -d "$dst_dir" ]; then
    for dst in "$dst_dir"/*; do
      [ -L "$dst" ] || continue
      cur=$(readlink -- "$dst")
      case $cur in
        "$src"/*) [ -e "$dst" ] || { rm -f -- "$dst" && n=$((n + 1)); } ;;
      esac
    done
  fi
  for e in "$src"/*; do
    [ -e "$e" ] || continue
    name=${e##*/}
    dst=$dst_dir/$name
    if [ -L "$dst" ]; then
      cur=$(readlink -- "$dst")
      [ "$cur" = "$e" ] && continue
      case $cur in
        "$DIR"/*) ln -sfn -- "$e" "$dst" && n=$((n + 1)) && added=$((added + 1)) ;;
        *) CONFLICTS+=("$dst") ;;
      esac
    elif [ -e "$dst" ]; then
      CONFLICTS+=("$dst")
    else
      mkdir -p "$dst_dir" && ln -s -- "$e" "$dst" && n=$((n + 1)) && added=$((added + 1))
    fi
  done
  if [ "$kind" = rules ]; then
    RULE_LINKS=$((RULE_LINKS + n))
    RULE_ADDED=$((RULE_ADDED + added))
  else
    SKILL_LINKS=$((SKILL_LINKS + n))
  fi
}

collect_changes() {
  [ -n "$OLD" ] && [ -n "$NEW" ] && [ "$OLD" != "$NEW" ] || return 0
  git -C "$DIR" cat-file -e "$OLD^{commit}" 2>/dev/null || return 0
  local f
  while IFS= read -r f; do RULES_CHANGED+=("${f#.agents/rules/}"); done \
    < <(git -C "$DIR" diff --name-only --diff-filter=AMR "$OLD" "$NEW" -- .agents/rules 2>/dev/null)
  while IFS= read -r f; do RULES_DELETED+=("${f#.agents/rules/}"); done \
    < <(git -C "$DIR" diff --name-only --diff-filter=D "$OLD" "$NEW" -- .agents/rules 2>/dev/null)
  while IFS= read -r f; do
    f=${f#.agents/skills/}
    SKILLS_CHANGED+=("${f%%/*}")
  done < <(git -C "$DIR" diff --name-only "$OLD" "$NEW" -- .agents/skills 2>/dev/null)
  if [ ${#SKILLS_CHANGED[@]} -gt 0 ]; then
    mapfile -t SKILLS_CHANGED < <(printf '%s\n' "${SKILLS_CHANGED[@]}" | sort -u)
  fi
}

render_rules() {
  local rel body used=0
  local -a skipped=()
  for rel in "$@"; do
    [ -f "$DIR/.agents/rules/$rel" ] || continue
    body=$(cat "$DIR/.agents/rules/$rel")
    if [ $((used + ${#body})) -gt "$MAX" ]; then
      skipped+=("$rel")
      continue
    fi
    say "--- ルール: $rel"
    say "$body"
    used=$((used + ${#body}))
  done
  for rel in ${skipped[@]+"${skipped[@]}"}; do
    say "（長いため省略。$CFG/rules/$rel を読むこと）"
  done
}

reg_hooks() {
  local f=$CFG/settings.json tmp s=$DIR/scripts/sync-dotfiles.sh
  if ! command -v jq >/dev/null 2>&1; then
    say "[dotfiles] jq が無いため、フックを登録できなかった"
    return 0
  fi
  mkdir -p "$CFG"
  [ -s "$f" ] || echo '{}' >"$f"
  tmp=$(mktemp) || return 0
  if jq --arg s "$s" '
      def put($ev; $arg; $t):
        .hooks[$ev] = ((.hooks[$ev] // [])
          | map(select(([.hooks[]?.command] | any(startswith($s))) | not))
          + [{hooks: [{type: "command", command: ($s + " " + $arg), timeout: $t}]}]);
      put("SessionStart"; "session"; 150) | put("UserPromptSubmit"; "turn"; 40)
    ' "$f" >"$tmp"; then
    cat "$tmp" >"$f"
    say "[dotfiles] フックを登録した: $f"
  else
    say "[dotfiles] $f を JSON として読めず、フックを登録できなかった"
  fi
  rm -f "$tmp"
}

compose() {
  local -a show=()
  local reason=""
  if [ -n "$ERR" ]; then
    say "[dotfiles 同期失敗] $DIR を最新化できなかった: $ERR"
    say "最新化済みとして扱わず、ユーザーに失敗を伝えること。"
  fi
  if [ "$MODE" = install ]; then
    : # セットアップスクリプトの出力はモデルに渡らないので、ルール本文は出さない
  elif [ "$FRESH" = 1 ] || { [ "$MODE" = session ] && [ "$RULE_ADDED" -gt 0 ]; }; then
    if [ -d "$DIR/.agents/rules" ]; then
      mapfile -t show < <(cd "$DIR/.agents/rules" && find . -type f -name '*.md' | sed 's#^\./##' | sort)
    fi
    reason="共通ルールを導入した"
  elif [ ${#RULES_CHANGED[@]} -gt 0 ]; then
    show=("${RULES_CHANGED[@]}")
    reason="共通ルールが更新された（${OLD:0:7}→${NEW:0:7}）"
  fi
  if [ ${#show[@]} -gt 0 ]; then
    say "[dotfiles 更新] $reason。以下を最新の内容として、以降はこれに従うこと。"
    render_rules "${show[@]}"
  fi
  if [ ${#RULES_DELETED[@]} -gt 0 ]; then
    say "[dotfiles 更新] 削除された共通ルール（以降は従わない）: ${RULES_DELETED[*]}"
  fi
  local n
  local -a skills_up=() skills_gone=()
  for n in ${SKILLS_CHANGED[@]+"${SKILLS_CHANGED[@]}"}; do
    if [ ! -d "$DIR/.agents/skills/$n" ]; then
      skills_gone+=("$n")
    elif [ "$(readlink -- "$CFG/skills/$n" 2>/dev/null)" = "$DIR/.agents/skills/$n" ]; then
      skills_up+=("$n")
    fi
  done
  if [ ${#skills_up[@]} -gt 0 ]; then
    say "[dotfiles 更新] 更新されたスキル: ${skills_up[*]}。該当する作業では $CFG/skills/<名前>/SKILL.md を読み直すこと。"
  fi
  if [ ${#skills_gone[@]} -gt 0 ]; then
    say "[dotfiles 更新] 削除されたスキル（以降は使わない）: ${skills_gone[*]}"
  fi
  if [ "$MODE" != turn ] && [ ${#CONFLICTS[@]} -gt 0 ]; then
    say "[dotfiles] 既存の別の中身があるため、上書きせずスキップ: ${CONFLICTS[*]}"
  fi
}

emit() {
  local event=UserPromptSubmit reload=false
  [ "$MODE" = session ] && event=SessionStart
  [ "$MODE" = session ] && [ "$SKILL_LINKS" -gt 0 ] && reload=true
  if [ "$MODE" = install ]; then
    [ -n "$MSG" ] && printf '%s' "$MSG"
    return 0
  fi
  [ -z "$MSG" ] && [ "$reload" = false ] && return 0
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg e "$event" --arg c "$MSG" --argjson r "$reload" '
      {hookSpecificOutput: ({hookEventName: $e}
        + (if $c != "" then {additionalContext: $c} else {} end)
        + (if $r then {reloadSkills: true} else {} end))}'
  else
    printf '%s' "$MSG"
  fi
}

main() {
  [ -t 0 ] || cat >/dev/null 2>&1
  lock
  sync_repo
  if [ -d "$DIR/.agents" ]; then
    link_entries "$DIR/.agents/rules" "$CFG/rules" rules
    link_entries "$DIR/.agents/skills" "$CFG/skills" skills
    collect_changes
  fi
  [ "$MODE" = install ] && reg_hooks
  compose
  log "old=${OLD:0:7} new=${NEW:0:7} fresh=$FRESH links=rules:$RULE_LINKS/skills:$SKILL_LINKS${ERR:+ error=yes}"
  emit
  return 0
}

# main の定義を読み切ってから実行する（pull でこのファイルが書き換わっても壊れないようにする）
main "$@"
exit 0
