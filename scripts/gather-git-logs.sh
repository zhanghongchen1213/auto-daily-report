#!/bin/bash
# gather-git-logs.sh - 从配置的仓库收集当天的 git 提交日志

set -euo pipefail

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

# 将远程 URL 解析为本地路径（自动 clone/pull）
resolve_repo() {
  local repo="$1"

  # 本地路径：直接返回
  if [[ "$repo" != http* && "$repo" != git@* ]]; then
    echo "$repo"
    return
  fi

  # 远程 URL：clone 或 pull 到缓存目录
  mkdir -p "$CACHE_DIR"
  local repo_name
  repo_name=$(basename "$repo" .git)
  local local_path="$CACHE_DIR/$repo_name"

  if [ -d "$local_path/.git" ]; then
    git -C "$local_path" pull --quiet 2>/dev/null || true
  else
    git clone --quiet "$repo" "$local_path" 2>/dev/null || {
      echo "Warning: Failed to clone $repo" >&2
      return 1
    }
  fi
  echo "$local_path"
}

# 逐个仓库读取当日提交
while IFS= read -r repo; do
  [ -z "$repo" ] && continue

  # 解析仓库路径（支持远程 URL 和本地路径）
  LOCAL_PATH=$(resolve_repo "$repo") || continue

  # 跳过不存在或不是 git 仓库的路径
  if [ ! -d "$LOCAL_PATH/.git" ]; then
    echo "Warning: $LOCAL_PATH is not a git repository, skipping" >&2
    continue
  fi

  # 记录仓库名，并查询当天 00:00~23:59 的非 merge 提交
  REPO_NAME=$(basename "$LOCAL_PATH")
  LOGS=$(git -C "$LOCAL_PATH" log \
    --since="today 00:00" \
    --until="today 23:59" \
    --pretty=format:"%h - %s (%an, %ar)" \
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
  echo "今日无代码提交记录"
fi
