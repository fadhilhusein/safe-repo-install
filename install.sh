#!/usr/bin/env bash
# install.sh - copy the safe-repo-install skill into your AI tool skill folders.
#
# Usage: ./install.sh [--claude] [--codex] [--agents] [--all] [--dest DIR]
#                     [--force] [--uninstall] [-h|--help]
#
# Default (no target flags): Claude Code (~/.claude/skills) and Codex (~/.codex/skills).
# This script only copies three paths (SKILL.md, scripts/, references/).
# It never runs anything from the skill.

set -eu

NAME="safe-repo-install"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

do_claude=0 do_codex=0 do_agents=0 force=0 uninstall=0 custom=""

usage() {
  sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
  case "$1" in
    --claude) do_claude=1 ;;
    --codex) do_codex=1 ;;
    --agents) do_agents=1 ;;
    --all) do_claude=1 do_codex=1 do_agents=1 ;;
    --dest)
      shift
      [ $# -gt 0 ] || { echo "error: --dest needs a directory" >&2; exit 2; }
      custom="$1"
      ;;
    --force) force=1 ;;
    --uninstall) uninstall=1 ;;
    -h | --help) usage; exit 0 ;;
    *) echo "error: unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

if [ "$do_claude$do_codex$do_agents" = "000" ] && [ -z "$custom" ]; then
  do_claude=1
  do_codex=1
fi

targets=()
[ "$do_claude" -eq 1 ] && targets+=("$HOME/.claude/skills")
[ "$do_codex" -eq 1 ] && targets+=("$HOME/.codex/skills")
[ "$do_agents" -eq 1 ] && targets+=("$HOME/.agents/skills")
[ -n "$custom" ] && targets+=("$custom")

for base in "${targets[@]}"; do
  dest="$base/$NAME"

  if [ "$uninstall" -eq 1 ]; then
    if [ -d "$dest" ]; then
      rm -rf "$dest"
      echo "removed  $dest"
    else
      echo "absent   $dest"
    fi
    continue
  fi

  if [ -e "$dest" ]; then
    if [ "$force" -eq 1 ]; then
      rm -rf "$dest"
    elif [ -t 0 ]; then
      printf '%s already exists. Overwrite? [y/N] ' "$dest"
      read -r ans
      case "$ans" in
        y | Y | yes | YES) rm -rf "$dest" ;;
        *) echo "skipped  $dest"; continue ;;
      esac
    else
      echo "skipped  $dest (exists, rerun with --force to overwrite)"
      continue
    fi
  fi

  mkdir -p "$dest/scripts" "$dest/references"
  cp "$SRC/SKILL.md" "$dest/SKILL.md"
  cp "$SRC/scripts/audit_repo.sh" "$dest/scripts/audit_repo.sh"
  cp "$SRC/references/manual-checks.md" "$dest/references/manual-checks.md"
  chmod +x "$dest/scripts/audit_repo.sh" 2>/dev/null || true
  echo "installed $dest"
done

if [ "$uninstall" -eq 0 ]; then
  echo
  echo "Done. Restart Claude Code / Codex so the skill loads."
fi
