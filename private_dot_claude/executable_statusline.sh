#!/usr/bin/env bash
input=$(cat)
dir=$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // ""')
model=$(printf '%s' "$input" | jq -r '.model.display_name // "?"')
branch=$(git -C "$dir" branch --show-current 2>/dev/null)
env="$dir/.env"
if [ -f "$env" ] && grep -q '^WT_SLUG=' "$env" 2>/dev/null; then
  web=$(grep -E '^WEB_DOMAIN=' "$env" | head -1 | cut -d= -f2- | tr -d '"')
  printf '%s · ⎇ %s · 🌐 %s' "$model" "${branch:-?}" "$web"          # in a worktree: show its app URL
else
  printf '%s · %s · ⎇ %s' "$model" "$(basename "$dir")" "${branch:-?}"
fi
