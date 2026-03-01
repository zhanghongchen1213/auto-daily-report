#!/bin/bash
# gather-git-logs.sh - 从配置的仓库收集指定时间范围的 git 提交日志（默认今日）

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  gather-git-logs.sh [--date YYYY-MM-DD]
  gather-git-logs.sh [--since "YYYY-MM-DD HH:MM[:SS]"] [--until "YYYY-MM-DD HH:MM[:SS]"]

Options:
  --date   统计指定日期 00:00:00~23:59:59 的提交
  --since  指定起始时间（可与 --until 配合）
  --until  指定结束时间（可与 --since 配合）
  -h, --help  显示帮助
EOF
}

# 默认统计今日
SINCE_VALUE="today 00:00"
UNTIL_VALUE="today 23:59:59"
NO_COMMIT_MSG="今日无代码提交记录"
DATE_VALUE=""
HAS_CUSTOM_RANGE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --date)
      if [ $# -lt 2 ]; then
        echo "Error: --date requires a value (YYYY-MM-DD)" >&2
        usage
        exit 1
      fi
      DATE_VALUE="$2"
      if [[ ! "$DATE_VALUE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        echo "Error: Invalid --date format, expected YYYY-MM-DD" >&2
        exit 1
      fi
      shift 2
      ;;
    --since)
      if [ $# -lt 2 ]; then
        echo "Error: --since requires a value" >&2
        usage
        exit 1
      fi
      SINCE_VALUE="$2"
      HAS_CUSTOM_RANGE=true
      shift 2
      ;;
    --until)
      if [ $# -lt 2 ]; then
        echo "Error: --until requires a value" >&2
        usage
        exit 1
      fi
      UNTIL_VALUE="$2"
      HAS_CUSTOM_RANGE=true
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Error: Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [ -n "$DATE_VALUE" ] && [ "$HAS_CUSTOM_RANGE" = true ]; then
  echo "Error: --date cannot be used together with --since/--until" >&2
  exit 1
fi

if [ -n "$DATE_VALUE" ]; then
  SINCE_VALUE="$DATE_VALUE 00:00:00"
  UNTIL_VALUE="$DATE_VALUE 23:59:59"
  NO_COMMIT_MSG="$DATE_VALUE 无代码提交记录"
elif [ "$HAS_CUSTOM_RANGE" = true ]; then
  NO_COMMIT_MSG="指定时间范围内无代码提交记录"
fi

# 定位脚本目录与项目根目录
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
# 配置文件，包含需要统计的仓库路径
CONFIG_FILE="$PROJECT_DIR/config.json"

# 确保配置文件存在
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: config.json not found at $CONFIG_FILE" >&2
  exit 1
fi

# 使用 python3 读取配置中的仓库路径列表
REPOS=$(python3 -c "
import json, sys
with open('$CONFIG_FILE') as f:
    config = json.load(f)
for repo in config.get('github', {}).get('repos', []):
    print(repo)
")

# 未配置仓库则直接退出
if [ -z "$REPOS" ]; then
  echo "Error: No repos configured in config.json" >&2
  exit 1
fi

# 远程仓库的本地缓存目录
CACHE_DIR="$PROJECT_DIR/.repo-cache"

# 用于汇总多仓库日志
HAS_COMMITS=false
ALL_LOGS=""

# 将远程 URL 解析为本地路径（自动 clone/fetch）
resolve_repo() {
  local repo="$1"

  # 本地路径：直接返回
  if [[ "$repo" != http* && "$repo" != git@* ]]; then
    echo "$repo"
    return
  fi

  # 远程 URL：clone 或 fetch 到缓存目录
  mkdir -p "$CACHE_DIR"
  local repo_name
  repo_name=$(basename "$repo" .git)
  local local_path="$CACHE_DIR/$repo_name"

  if [ -d "$local_path/.git" ]; then
    git -C "$local_path" fetch --all --prune --quiet 2>/dev/null || true
  else
    git clone --quiet "$repo" "$local_path" 2>/dev/null || {
      echo "Warning: Failed to clone $repo" >&2
      return 1
    }
  fi
  echo "$local_path"
}

refresh_repo_refs() {
  local repo_path="$1"
  git -C "$repo_path" fetch --all --prune --quiet 2>/dev/null || \
    git -C "$repo_path" fetch --prune --quiet 2>/dev/null || {
      echo "Warning: Failed to fetch latest refs for $repo_path, using existing refs" >&2
      return 1
    }
}

# 逐个仓库读取提交
while IFS= read -r repo; do
  [ -z "$repo" ] && continue

  # 解析仓库路径（支持远程 URL 和本地路径）
  LOCAL_PATH=$(resolve_repo "$repo") || continue

  # 跳过不存在或不是 git 仓库的路径
  if [ ! -d "$LOCAL_PATH/.git" ]; then
    echo "Warning: $LOCAL_PATH is not a git repository, skipping" >&2
    continue
  fi

  # 尝试同步远端引用（本地路径和缓存路径都执行）
  refresh_repo_refs "$LOCAL_PATH" || true

  # 记录仓库名，并查询指定时间范围内、所有分支（含 origin/*）的非 merge 提交
  REPO_NAME=$(basename "$LOCAL_PATH")
  LOGS=$(git -C "$LOCAL_PATH" log \
    --all \
    --since="$SINCE_VALUE" \
    --until="$UNTIL_VALUE" \
    --pretty=format:"%h - %s (%an, %ad)%d" \
    --date=iso-local \
    --no-merges 2>/dev/null || true)

  # 有提交则追加到总日志中
  if [ -n "$LOGS" ]; then
    HAS_COMMITS=true
    ALL_LOGS+="### $REPO_NAME"$'\n'"$LOGS"$'\n\n'
  fi
done <<< "$REPOS"

# 输出最终结果，无提交时返回默认文案
if [ "$HAS_COMMITS" = true ]; then
  echo "$ALL_LOGS"
else
  echo "$NO_COMMIT_MSG"
fi
