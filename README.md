# 基于 Claude Code Skills + Notion 的工作日报/周报/月报自动化管理系统

> 利用 macOS launchd 定时调度，自动收集 Git 提交记录与 Notion 活动日志，通过 Claude Code Skills 生成结构化报告并写入 Notion 数据库。全程无需人工干预，开箱即用。

> **项目地址**：[auto-daily-report](https://github.com/xiaozhangxuezhang/auto-daily-report)
> 如果觉得有帮助，欢迎 ⭐ Star 支持一下！

## 功能特性

- **日报自动生成** — 每日收集 Git 提交 + Notion 活动记录，生成结构化日报
- **周报自动聚合** — 汇总本周日报，跨天去重分析，生成周报
- **月报自动汇总** — 汇总本月周报，里程碑识别，生成月报
- **配置集中管理** — 单一 `config.json` 管理所有 Notion 数据库 ID，一键同步到 Skill 文件
- **定时无人值守** — macOS launchd 调度，tmux 可视化执行，支持 iTerm / Terminal
- **月末智能判断** — 月报仅在当月最后一天触发
- **日志自动轮转** — 保留最近 30 天日志，自动清理

### 效果展示

<p align="center">
  <img src="https://i.imgs.ovh/2026/02/25/yNj17Q.md.png" alt="日报生成效果" />
  <br/>
  <em>▲ 自动生成的结构化日报</em>
</p>

<p align="center">
  <img src="https://i.imgs.ovh/2026/02/25/yNj3AF.md.png" alt="Notion 数据库视图" />
  <br/>
  <em>▲ Notion 数据库中的报告记录</em>
</p>

## 系统要求

| 依赖                                                                | 说明                                     |
| ------------------------------------------------------------------- | ---------------------------------------- |
| macOS                                                               | 使用 launchd 进行定时调度                |
| [Claude Code](https://docs.anthropic.com/en/docs/claude-code) v2.x+ | AI 报告生成引擎                          |
| Git                                                                 | 提交记录收集                             |
| Python 3                                                            | JSON 解析（macOS 自带）                  |
| tmux                                                                | 终端会话管理                             |
| jq（可选）                                                          | JSON 解析加速，未安装时自动回退到 Python |
| Notion 账号                                                         | 数据源 + 报告输出目标                    |

### Notion MCP Server 配置

Claude Code 需要配置 Notion MCP Server 才能读写 Notion 数据库。编辑 `~/.claude/.mcp.json`，添加：

```json
{
  "mcpServers": {
    "notion": {
      "command": "npx",
      "args": ["-y", "@notionhq/notion-mcp-server"],
      "env": {
        "OPENAPI_MCP_HEADERS": "{\"Authorization\":\"Bearer <你的 Notion Integration Token>\",\"Notion-Version\":\"2022-06-28\"}"
      }
    }
  }
}
```

> **获取 Token**: 前往 [Notion Integrations](https://www.notion.so/profile/integrations/internal) 创建 Integration，获取 Internal Integration Token，并将其关联到目标数据库页面。

## 快速开始

### 1. 克隆项目

```bash
git clone https://github.com/xiaozhangxuezhang/auto-daily-report.git
cd auto-daily-report
```

### 2. 编辑配置文件

```bash
cp config.json config.json.bak  # 备份默认配置
vim config.json                 # 编辑为你的实际配置
```

将 `config.json` 中的仓库路径和 Notion 数据库 ID 替换为你自己的值（详见 [配置说明](#配置说明)）。

### 3. 运行自检 & 配置同步

```bash
bash test.sh
```

该命令会：

1. 将 `config.json` 中的数据库 ID 同步到所有 Skill 模板文件
2. 验证配置文件、脚本、Skill 文件、launchd plist 等是否完整可用
3. 检查 Claude CLI、tmux 等依赖是否就绪

全部通过后输出 `全部检查通过!`。

### 4. 安装定时任务

```bash
bash install.sh
```

### 5. 验证安装

```bash
launchctl list | grep auto-report
```

看到 3 条记录即表示安装成功。

## 配置说明

所有配置集中在 `config.json` 中管理：

```json
{
  "github": {
    "repos": ["/Users/你的用户名/Documents/GitHub/你的项目"]
  },
  "notion": {
    "databases": {
      "activity_logs": "你的活动记录数据库ID",
      "daily_report": "你的日报数据库ID",
      "weekly_report": "你的周报数据库ID",
      "monthly_report": "你的月报数据库ID"
    }
  },
  "claude": {
    "cli_path": "/usr/local/bin/claude"
  }
}
```

### 配置字段说明

| 字段                 | 说明                                                                                   |
| -------------------- | -------------------------------------------------------------------------------------- |
| `github.repos`       | Git 仓库路径列表，支持本地绝对路径和远程 URL（远程仓库自动 clone 到`.repo-cache/`）    |
| `notion.databases.*` | 4 个 Notion 数据库 ID（activity_logs / daily_report / weekly_report / monthly_report） |
| `claude.cli_path`    | Claude CLI 可执行文件路径，可通过 `which claude` 获取                                  |

> **如何获取 Notion 数据库 ID**: 打开 Notion 数据库页面，URL 中 `notion.so/` 后、`?v=` 前的 32 位字符串即为数据库 ID。

## 项目结构

```
auto-daily-report/
├── config.json                          # 集中配置文件（数据库 ID、仓库路径等）
├── test.sh                              # 自检 + 配置同步脚本
├── install.sh                           # 安装 launchd 定时任务
├── uninstall.sh                         # 卸载定时任务
├── .claude/
│   └── skills/
│       ├── daily-report/
│       │   ├── SKILL.md                 # 日报生成 Skill（由模板生成，勿手动编辑）
│       │   └── SKILL.md.tpl             # 日报 Skill 模板（含占位符）
│       ├── weekly-report/
│       │   ├── SKILL.md                 # 周报生成 Skill
│       │   └── SKILL.md.tpl             # 周报 Skill 模板
│       └── monthly-report/
│           ├── SKILL.md                 # 月报生成 Skill
│           └── SKILL.md.tpl             # 月报 Skill 模板
├── scripts/
│   ├── run-claude-tmux.sh               # tmux 自动化执行器（核心调度脚本）
│   └── gather-git-logs.sh               # Git 提交日志收集
├── launchd/
│   ├── com.auto-report.daily.plist      # 日报定时任务
│   ├── com.auto-report.weekly.plist     # 周报定时任务
│   └── com.auto-report.monthly.plist    # 月报定时任务
└── logs/                                # 执行日志（自动生成）
```

## 工作原理

```
┌─────────────────────────────────────────────────────────┐
│                    macOS launchd                         │
│  ┌──────────┐  ┌──────────┐  ┌───────────┐             │
│  │ 日报 plist│  │ 周报 plist│  │ 月报 plist │             │
│  │ 周一~六   │  │ 周日     │  │ 月末      │             │
│  │ 22:00    │  │ 22:00    │  │ 22:00     │             │
│  └────┬─────┘  └────┬─────┘  └─────┬─────┘             │
└───────┼──────────────┼──────────────┼───────────────────┘
        │              │              │
        ▼              ▼              ▼
┌─────────────────────────────────────────────────────────┐
│              run-claude-tmux.sh                          │
│  1. 创建 tmux 会话                                       │
│  2. 打开 iTerm/Terminal 可视化窗口                         │
│  3. 启动 Claude CLI 交互模式                              │
│  4. 发送 /daily-report 或 /weekly-report 等 Skill 命令    │
│  5. 等待 1 小时后自动关闭                                  │
└────────────────────────┬────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────┐
│                Claude Code Skills                        │
│                                                          │
│  /daily-report          /weekly-report    /monthly-report│
│  ├─ gather-git-logs.sh  ├─ 查询日报DB     ├─ 查询周报DB  │
│  ├─ 查询 Activity Logs  ├─ 跨天去重分析   ├─ 里程碑识别  │
│  ├─ 生成结构化日报       ├─ 生成周报       ├─ 生成月报    │
│  └─ 写入日报 DB          └─ 写入周报 DB    └─ 写入月报 DB │
└─────────────────────────────────────────────────────────┘
```

## 使用方式

### 手动触发报告

```bash
# 生成日报
bash scripts/run-claude-tmux.sh daily-report

# 生成周报
bash scripts/run-claude-tmux.sh weekly-report

# 生成月报（仅月末有效，非月末会自动跳过）
bash scripts/run-claude-tmux.sh monthly-report
```

### 在 Claude Code 中直接使用 Skill

在项目目录下启动 Claude Code，直接输入 Skill 命令：

```
> /daily-report    # 生成今日日报
> /weekly-report   # 生成本周周报
> /monthly-report  # 生成本月月报
```

### 运行系统自检

```bash
bash test.sh
```

自检包含 9 项检查（编号 0~8），涵盖配置同步、文件完整性、依赖可用性等。

### 卸载定时任务

```bash
bash uninstall.sh
```

## 配置同步机制

本项目采用**模板占位符**机制管理 Skill 文件中的配置值：

```
config.json  ──→  test.sh (sync_config)  ──→  SKILL.md.tpl  ──→  SKILL.md
  (源数据)          (sed 替换)                  (模板)            (最终文件)
```

### 模板占位符列表

| 占位符                     | 来源                                            | 用于                          |
| -------------------------- | ----------------------------------------------- | ----------------------------- |
| `{{PROJECT_DIR}}`          | 脚本运行时自动获取                              | daily-report                  |
| `{{ACTIVITY_LOGS_DB_ID}}`  | `config.json → notion.databases.activity_logs`  | daily-report                  |
| `{{DAILY_REPORT_DB_ID}}`   | `config.json → notion.databases.daily_report`   | daily-report, weekly-report   |
| `{{WEEKLY_REPORT_DB_ID}}`  | `config.json → notion.databases.weekly_report`  | weekly-report, monthly-report |
| `{{MONTHLY_REPORT_DB_ID}}` | `config.json → notion.databases.monthly_report` | monthly-report                |

### 工作流程

1. 编辑 `config.json` 中的数据库 ID
2. 运行 `bash test.sh`，自动将配置同步到 `.claude/skills/*/SKILL.md`
3. Skill 文件即可被 Claude Code 正确调用

> **注意**: `SKILL.md` 由模板自动生成，请勿手动编辑。如需修改 Skill 逻辑，请编辑对应的 `SKILL.md.tpl` 模板文件。

## 定时调度

| 报告类型 | 触发时间                   | launchd plist                   | 说明                       |
| -------- | -------------------------- | ------------------------------- | -------------------------- |
| 日报     | 周一至周六 22:00           | `com.auto-report.daily.plist`   | 收集当天 Git + Notion 数据 |
| 周报     | 周日 22:00                 | `com.auto-report.weekly.plist`  | 汇总本周所有日报           |
| 月报     | 每天 22:00（内部判断月末） | `com.auto-report.monthly.plist` | 仅月末最后一天实际执行     |

> 月报 plist 每天都会触发，但 `run-claude-tmux.sh` 内置月末判断逻辑，非月末会立即退出（exit 0），不会启动 Claude。

## 日志管理

所有执行日志保存在 `logs/` 目录，自动轮转保留 30 天：

```
logs/
├── daily-report-20260225.log        # 日报执行日志
├── weekly-report-20260223.log       # 周报执行日志
├── monthly-report-20260228.log      # 月报执行日志
├── launchd-daily.out.log            # launchd 标准输出
├── launchd-daily.err.log            # launchd 错误输出
├── launchd-weekly.out.log
├── launchd-weekly.err.log
├── launchd-monthly.out.log
└── launchd-monthly.err.log
```

## 故障排查

### 查看 launchd 任务状态

```bash
launchctl list | grep auto-report
```

### 查看最近执行日志

```bash
# 查看今日日报日志
tail -50 logs/daily-report-$(date +%Y%m%d).log

# 查看 launchd 错误输出
cat logs/launchd-daily.err.log
```

### 重新加载定时任务

```bash
launchctl unload ~/Library/LaunchAgents/com.auto-report.daily.plist
launchctl load ~/Library/LaunchAgents/com.auto-report.daily.plist
```

### 常见问题排查表

| 现象                             | 可能原因                       | 解决方法                                                         |
| -------------------------------- | ------------------------------ | ---------------------------------------------------------------- |
| `test.sh` 报 "配置文件不存在"    | `config.json` 缺失             | 确认项目根目录存在`config.json`                                  |
| Skill 文件中仍有`{{xxx}}` 占位符 | 未运行`test.sh` 同步           | 执行`bash test.sh`                                               |
| Claude CLI 启动超时              | Claude 未安装或路径错误        | 检查`config.json` 中 `claude.cli_path`，运行 `which claude` 确认 |
| Notion 写入失败                  | MCP Server 未配置或 Token 无效 | 检查`~/.claude/.mcp.json` 配置                                   |
| 月报未执行                       | 非月末触发                     | 正常行为，月报仅月末最后一天执行                                 |
| tmux 会话异常                    | 残留会话冲突                   | `tmux kill-server` 清理后重试                                    |

## 常见问题

**Q: 修改了 `config.json` 后需要做什么？**

运行 `bash test.sh`，它会自动将新配置同步到所有 Skill 文件。

**Q: 可以同时监控多个 Git 仓库吗？**

可以。在 `config.json` 的 `github.repos` 数组中添加多个路径即可，支持本地路径和远程 URL 混用：

```json
{
  "github": {
    "repos": [
      "/Users/me/project-a",
      "/Users/me/project-b",
      "https://github.com/me/project-c"
    ]
  }
}
```

**Q: 如何自定义报告的触发时间？**

编辑 `launchd/` 目录下对应的 plist 文件，修改 `StartCalendarInterval` 中的 `Hour` 和 `Minute` 字段，然后重新运行 `bash install.sh`。

**Q: 没有安装 jq 会影响使用吗？**

不会。`test.sh` 优先使用 jq 解析 JSON，未安装时自动回退到 Python 3（macOS 自带）。

**Q: 如何自定义 Skill 的报告内容和格式？**

编辑 `.claude/skills/*/SKILL.md.tpl` 模板文件，修改报告生成逻辑，然后运行 `bash test.sh` 重新同步。

**Q: 远程仓库的提交记录如何收集？**

`gather-git-logs.sh` 会自动将远程 URL clone 到 `.repo-cache/` 目录，后续执行时自动 `git pull` 更新。

## License

MIT
