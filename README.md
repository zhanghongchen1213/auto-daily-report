# Auto Daily Report

基于 Claude CLI + Notion MCP 的工作日报/周报/月报自动化生成系统。

通过 macOS launchd 定时调度，自动读取 Git 提交记录和 Notion Activity Logs，生成结构化报告并写入 Notion 数据库。

## 系统架构

```
定时触发 (launchd)
    │
    ├── 日报 (周一~周六 22:00)
    │     ├── 收集 Git 提交日志
    │     ├── 查询 Notion Activity Logs
    │     ├── Claude 生成 6 段式日报
    │     └── 写入 Notion 日报数据库
    │
    ├── 周报 (周六 16:30)
    │     ├── 查询本周已完成日报
    │     ├── Claude 跨天去重 + 趋势分析
    │     └── 写入 Notion 周报数据库
    │
    └── 月报 (每月最后工作日 17:00)
          ├── 查询本月所有周报
          ├── Claude 跨周去重 + 里程碑识别
          └── 写入 Notion 月报数据库
```

## 项目结构

```
auto-daily-report/
├── config.json                              # 配置文件
├── scripts/
│   ├── gather-git-logs.sh                   # Git 日志收集（支持本地路径和远程 URL）
│   ├── daily-report.sh                      # 日报生成入口
│   ├── weekly-report.sh                     # 周报生成入口
│   └── monthly-report.sh                    # 月报生成入口
├── prompts/
│   ├── daily-report-prompt.prompt           # 日报 Claude 提示词模板
│   ├── weekly-report-prompt.prompt          # 周报 Claude 提示词模板
│   └── monthly-report-prompt.prompt         # 月报 Claude 提示词模板
├── launchd/
│   ├── com.auto-report.daily.plist          # 日报定时任务
│   ├── com.auto-report.weekly.plist         # 周报定时任务
│   └── com.auto-report.monthly.plist        # 月报定时任务
├── install.sh                               # 安装定时任务
├── uninstall.sh                             # 卸载定时任务
├── test.sh                                  # 系统自检
└── .gitignore
```

## 前置要求

- macOS（使用 launchd 调度）
- [Claude CLI](https://docs.anthropic.com/en/docs/claude-code) v2.x+
- Git
- Python 3（macOS 自带）
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

### 4. 手动触发（测试用）

```bash
# 立即生成今日日报
bash scripts/daily-report.sh

# 立即生成本周周报
bash scripts/weekly-report.sh

# 强制生成本月月报（跳过"最后工作日"检查）
bash scripts/monthly-report.sh --force
```

### 5. 卸载

```bash
bash uninstall.sh
```

## 定时调度

| 报告类型 | 触发时间 | launchd plist |
|---------|---------|---------------|
| 日报 | 周一至周六 22:00 | `com.auto-report.daily.plist` |
| 周报 | 周六 16:30 | `com.auto-report.weekly.plist` |
| 月报 | 每月 28-31 日 17:00 | `com.auto-report.monthly.plist` |

月报脚本内置了"最后工作日"判断逻辑：在 28-31 日每天都会被 launchd 触发，但只有当天确实是该月最后一个工作日（周一至周五）时才会执行生成。

## Notion 数据库

| 数据库 | 用途 | ID |
|--------|------|-----|
| Activity Logs | 每日活动记录（数据源） | `2e0be665-a1c7-8011-afd5-c9dcf345b1a5` |
| 每日工作日报 | 日报输出目标 | `2e0be665-a1c7-8110-b3ef-f939ed259679` |
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
