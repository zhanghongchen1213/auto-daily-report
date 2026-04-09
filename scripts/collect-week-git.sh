#!/usr/bin/env bash
# Collect per-branch git logs for a week range (all repos in config.json)
set -uo pipefail

WEEK_START="${1:?WEEK_START YYYY-MM-DD}"
WEEK_END="${2:?WEEK_END YYYY-MM-DD}"
CONFIG_FILE="${3:-/Users/xiaozhangxuezhang/Documents/GitHub/auto-daily-report/config.json}"

while IFS= read -r REPO_PATH; do
  [[ -z "$REPO_PATH" ]] && continue
  REPO_NAME=$(basename "$REPO_PATH")

  echo "========================================"
  echo "仓库: $REPO_NAME"
  echo "路径: $REPO_PATH"
  echo "========================================"

  cd "$REPO_PATH" || { echo "[SKIP] 路径不存在"; continue; }
  git fetch --all --prune 2>/dev/null || true

  REPO_HAS_COMMITS=false

  while IFS= read -r BRANCH; do
    [[ -z "$BRANCH" ]] && continue
    REF="$BRANCH"
    if ! git rev-parse --verify "$BRANCH" &>/dev/null; then
      REF="origin/$BRANCH"
    fi

    COMMIT_COUNT=$(git log "$REF" --since="$WEEK_START 00:00:00" --until="$WEEK_END 23:59:59" --oneline --no-merges 2>/dev/null | wc -l | tr -d ' ')

    if [[ "${COMMIT_COUNT:-0}" -gt 0 ]]; then
      REPO_HAS_COMMITS=true
      echo ""
      echo "--- 分支: $BRANCH ($COMMIT_COUNT 次提交) ---"

      git log "$REF" --since="$WEEK_START 00:00:00" --until="$WEEK_END 23:59:59" \
        --no-merges \
        --pretty=format:"%n提交: %h%n作者: %an%n时间: %ad%n消息: %s%n" \
        --date=iso-local --stat 2>/dev/null

      echo ""
    fi
  done < <(git for-each-ref --format='%(refname:short)' refs/heads/ refs/remotes/origin/ 2>/dev/null | sed 's|^origin/||' | grep -v '^HEAD$' | grep -v '^origin$' | sort -u)

  if [[ "$REPO_HAS_COMMITS" == false ]]; then
    echo "[该仓库本周无提交记录]"
  fi
  echo ""
done < <(python3 -c "import json; [print(r) for r in json.load(open('$CONFIG_FILE'))['github']['repos']]")
