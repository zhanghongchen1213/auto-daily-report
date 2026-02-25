# Auto Daily Report

基于 Claude CLI Skills + Notion MCP 的工作日报/周报/月报自动化系统。

通过 macOS launchd 定时调度，自动收集 Git 提交记录和 Notion Activity Logs，由 Claude CLI Skills 生成结构化报告并写入 Notion 数据库。

## 系统架构

```
定时触发 (launchd)
    │
    ├── 日报 (周一~周六 22:00)
    │     └── run-claude-tmux.sh daily-report
    │           └── Claude CLI → /daily-report skill
    │                 ├── 收集 Git 提交日志
    │                 ├── 查询 Notion Activity Logs
    │                 ├── 生成结构化日报
    │                 └── 写入 Notion 日报数据库
    │
    ├── 周报 (周日 22:00)
    │     └── run-claude-tmux.sh weekly-report
    │           └── Claude CLI → /weekly-report skill
    │
    └── 月报 (月底 22:00)
          └── run-claude-tmux.sh monthly-report
                └── Claude CLI → /monthly-report skill
```

## 项目结构

```
auto-daily-report/
├── .claude/
│   └── skills/
│       ├── daily-report.md          # 日报生成 skill
│       ├── weekly-report.md         # 周报生成 skill
│       └── monthly-report.md        # 月报生成 skill
├── config.json                      # 配置文件
├── scripts/
│   ├── run-claude-tmux.sh           # tmux 自动化执行器
│   └── gather-git-logs.sh           # Git 日志收集
├── launchd/
│   ├── com.auto-report.daily.plist
│   ├── com.auto-report.weekly.plist
│   └── com.auto-report.monthly.plist
├── install.sh
├── uninstall.sh
├── test.sh
└── logs/
```

## 前置要求

- macOS（使用 launchd 调度）
- [Claude CLI](https://docs.anthropic.com/en/docs/claude-code) v2.x+
- Git
- Python 3（macOS 自带）
- tmux
- Notion MCP Server 已配置（`~/.claude/.mcp.json`）

## 快速开始

### 1. 配置

编辑 `config.json`，将 `github.repos` 改为你要监控的仓库：

```json
{
  "github": {
    "repos": [
      "/Users/你的用户名/Documents/GitHub/你的项目",
      "https://github.com/你的用户名/远程项目"
    ]
  }
}
```

支持本地路径和远程 GitHub URL（远程仓库会自动 clone 到 `.repo-cache/`）。

### 2. 自检

```bash
bash test.sh
```

### 3. 安装定时任务

```bash
bash install.sh
```

### 4. 手动触发

```bash
# 手动执行日报
bash scripts/run-claude-tmux.sh daily-report

# 手动执行周报
bash scripts/run-claude-tmux.sh weekly-report

# 手动执行月报
bash scripts/run-claude-tmux.sh monthly-report
```

### 5. 卸载

```bash
bash uninstall.sh
```

## 定时调度

| 报告类型 | 触发时间 | launchd plist |
|---------|---------|---------------|
| 日报 | 周一至周六 22:00 | `com.auto-report.daily.plist` |
| 周报 | 周日 22:00 | `com.auto-report.weekly.plist` |
| 月报 | 月底 22:00 | `com.auto-report.monthly.plist` |

## Notion 数据库

| 数据库 | 用途 | ID |
|--------|------|-----|
| Activity Logs | 每日活动记录（数据源） | `d78211d9-eddb-4095-a93a-d1f5640e4c02` |
| 每日工作日报 | 日报输出目标 | `c7b19046-7ddf-44ec-b0f2-839577df4cbe` |
| 每周工作周报 | 周报输出目标 | `7ccdc19a-e680-478b-950f-d89399001571` |
| 每月工作月报 | 月报输出目标 | `7b70e2ab-eae8-4f4e-b1b3-4054b4df0a48` |

## 日志

所有执行日志保存在 `logs/` 目录：

```
logs/
├── daily-2026-02-24.log          # 日报执行日志
├── weekly-2026-W09.log           # 周报执行日志
├── monthly-2026-02.log           # 月报执行日志
├── launchd-daily.out.log         # launchd 标准输出
├── launchd-daily.err.log         # launchd 错误输出
├── launchd-weekly.out.log
├── launchd-weekly.err.log
├── launchd-monthly.out.log
└── launchd-monthly.err.log
```

## 故障排查

查看 launchd 任务状态：

```bash
launchctl list | grep auto-report
```

查看最近的执行日志：

```bash
tail -50 logs/daily-$(date +%Y-%m-%d).log
```

手动重新加载定时任务：

```bash
launchctl unload ~/Library/LaunchAgents/com.auto-report.daily.plist
launchctl load ~/Library/LaunchAgents/com.auto-report.daily.plist
```