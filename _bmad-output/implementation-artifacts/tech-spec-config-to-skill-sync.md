---
title: 'Config-to-Skill 配置同步功能'
slug: 'config-to-skill-sync'
created: '2026-02-25'
status: 'ready-for-dev'
stepsCompleted: [1, 2, 3, 4]
tech_stack: [bash, jq, sed, python3]
files_to_modify: [test.sh, .claude/skills/daily-report/SKILL.md.tpl, .claude/skills/weekly-report/SKILL.md.tpl, .claude/skills/monthly-report/SKILL.md.tpl]
code_patterns: [template-placeholder-replacement, jq-json-parsing]
test_patterns: [bash-check-function]
---

# Tech-Spec: Config-to-Skill 配置同步功能

**Created:** 2026-02-25

## Overview

### Problem Statement

3 个 skill 文件中的数据库 ID 和路径是硬编码的，修改 config.json 后需要手动逐个同步，容易遗漏或出错。

### Solution

在 test.sh 中新增 config 同步步骤，采用模板占位符机制。每个 skill 维护一个 .tpl 模板文件，脚本从 config.json 读取配置后自动生成最终的 SKILL.md。

### Scope

**In Scope:**
- 为 3 个 skill 创建 .tpl 模板文件
- test.sh 新增 config → skill 同步步骤（保留原有检查）
- 替换配置项：4 个数据库 ID、项目路径
- 脚本输出提示改为中文

**Out of Scope:**
- 不修改 skill 业务逻辑
- 不修改 config.json 结构
- 不修改 launchd / run-claude-tmux.sh

## Context for Development

### Codebase Patterns

- config.json 使用标准 JSON，jq 可直接解析
- daily-report 使用 bash notion-api.sh 函数（含绝对路径）
- weekly/monthly-report 使用 Notion MCP 工具（仅含数据库 ID）
- test.sh 使用 check() 函数做 PASS/FAIL 检查，8 个检查项

### 占位符映射表

| 占位符 | config.json 路径 | 出现位置 |
| ---- | ------- | ------- |
| {{ACTIVITY_LOGS_DB_ID}} | notion.databases.activity_logs | daily-report (1处) |
| {{DAILY_REPORT_DB_ID}} | notion.databases.daily_report | daily-report (2处), weekly-report (1处) |
| {{WEEKLY_REPORT_DB_ID}} | notion.databases.weekly_report | weekly-report (2处), monthly-report (1处) |
| {{MONTHLY_REPORT_DB_ID}} | notion.databases.monthly_report | monthly-report (2处) |
| {{PROJECT_DIR}} | 脚本自动检测 | daily-report (5处) |

### Files to Reference

| File | Purpose |
| ---- | ------- |
| config.json | 中心配置，含数据库 ID 和路径 |
| test.sh | 系统检查脚本，需新增同步功能 |
| .claude/skills/daily-report/SKILL.md | 日报 skill，5个占位符 |
| .claude/skills/weekly-report/SKILL.md | 周报 skill，3个占位符 |
| .claude/skills/monthly-report/SKILL.md | 月报 skill，3个占位符 |

### Technical Decisions

1. 模板文件命名 SKILL.md.tpl，与 SKILL.md 同目录
2. 使用 sed 做占位符替换，jq 解析 config.json
3. 同步步骤作为 test.sh 新增的第一步（0/9: Config同步）
4. 修正 test.sh 中 skill 路径检查
5. 所有脚本输出提示改为中文
6. {{PROJECT_DIR}} 由脚本运行时自动检测，不从 config.json 读取

## Implementation Plan

### Tasks

- [ ] Task 1: 创建 daily-report 模板文件
  - File: `.claude/skills/daily-report/SKILL.md.tpl`
  - Action: 复制当前 SKILL.md，将 5 处硬编码值替换为占位符
  - Notes: 替换项见占位符映射表，{{PROJECT_DIR}} 替换所有绝对路径前缀

- [ ] Task 2: 创建 weekly-report 模板文件
  - File: `.claude/skills/weekly-report/SKILL.md.tpl`
  - Action: 复制当前 SKILL.md，将 3 处硬编码 ID 替换为占位符
  - Notes: {{DAILY_REPORT_DB_ID}} x1, {{WEEKLY_REPORT_DB_ID}} x2

- [ ] Task 3: 创建 monthly-report 模板文件
  - File: `.claude/skills/monthly-report/SKILL.md.tpl`
  - Action: 复制当前 SKILL.md，将 3 处硬编码 ID 替换为占位符
  - Notes: {{WEEKLY_REPORT_DB_ID}} x1, {{MONTHLY_REPORT_DB_ID}} x2

- [ ] Task 4: test.sh 新增 sync_config 函数
  - File: `test.sh`
  - Action: 在 check() 函数后新增 sync_config() 函数，逻辑如下：
    1. 用 jq 从 config.json 读取 4 个数据库 ID
    2. 用 SCRIPT_DIR 计算 PROJECT_DIR
    3. 对每个 .tpl 文件执行 sed 替换，输出到对应的 SKILL.md
    4. 输出同步结果（中文提示）
  - Notes: jq 不可用时回退到 python3 -c "import json..."

- [ ] Task 5: test.sh 新增同步步骤调用
  - File: `test.sh`
  - Action: 在检查项之前新增 "[0/9] 配置同步" 步骤，调用 sync_config
  - Notes: 原有 8 项检查编号改为 1/9 ~ 8/9

- [ ] Task 6: 修正 test.sh skill 路径检查
  - File: `test.sh`
  - Action: 将 skill 检查路径从 `.claude/skills/daily-report.md` 改为 `.claude/skills/daily-report/SKILL.md`（三个 skill 同理）
  - Notes: 同时检查 .tpl 模板文件是否存在

- [ ] Task 7: test.sh 所有英文提示改为中文
  - File: `test.sh`
  - Action: 将所有 echo/check 输出的英文描述替换为中文
  - Notes: 包括 PASS/FAIL 标签、检查项描述、结果汇总

### Acceptance Criteria

- [ ] AC 1: Given config.json 中 daily_report ID 为 "abc-123", when 执行 test.sh, then .claude/skills/daily-report/SKILL.md 中所有 {{DAILY_REPORT_DB_ID}} 被替换为 "abc-123"
- [ ] AC 2: Given config.json 中 4 个数据库 ID 均已配置, when 执行 test.sh, then 3 个 SKILL.md 中共 11 处占位符全部被正确替换
- [ ] AC 3: Given .tpl 模板文件不存在, when 执行 test.sh, then 同步步骤输出失败提示并跳过（不影响后续检查）
- [ ] AC 4: Given jq 未安装, when 执行 test.sh, then 自动回退到 python3 解析 config.json 并正常完成同步
- [ ] AC 5: Given 执行 test.sh 完成, then 所有输出提示均为中文
- [ ] AC 6: Given skill 目录结构为 .claude/skills/<name>/SKILL.md, when 执行 test.sh 检查步骤, then 路径检查通过

## Additional Context

### Dependencies

- jq（推荐）或 python3（回退）— 解析 config.json
- sed — 模板占位符替换
- 无外部服务依赖

### Testing Strategy

- 手动测试：执行 test.sh，验证同步输出和检查结果全部通过
- 对比验证：diff SKILL.md 和手动替换的预期结果
- 边界测试：删除 jq 后验证 python3 回退路径
- 回归测试：确认原有 8 项检查仍正常工作

### Notes

- .tpl 文件应纳入 git 版本控制，生成的 SKILL.md 可选择性 gitignore
- 未来新增配置项只需：在 config.json 加字段 → 在 .tpl 加占位符 → 在 sync_config 加一行 sed
- sed 替换使用 `|` 作为分隔符（避免路径中 `/` 冲突）
