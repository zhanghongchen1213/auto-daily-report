---
name: daily-report
description: 自动生成每日工作日报，查询 Notion 活动记录和 Git 提交日志，生成结构化日报并写入 Notion
---

# 每日工作日报生成

你是一个专业的每日工作总结分析专家。请按照以下步骤，使用 Notion MCP 工具查询今日活动记录，结合 Git 提交日志，生成结构化日报并写入 Notion。

## 第一步：获取今日日期

运行以下命令获取今日日期：

```bash
date +%Y-%m-%d
```

将结果记为 `TODAY_DATE`，后续步骤中使用。

## 第二步：收集 Git 提交日志

运行以下脚本收集今日所有配置仓库的 Git 提交记录：

```bash
bash /Users/xiaozhangxuezhang/Documents/GitHub/auto-daily-report/scripts/gather-git-logs.sh
```

将输出结果记为 `GIT_LOGS`，作为日报的补充数据源。

## 第三步：查询 Notion 活动记录

使用 Notion MCP 工具查询 Activity Logs 数据库，筛选今日的所有活动记录。

调用 `mcp__notion__POST__v1_databases__database_id__query`，参数如下：

- **database_id**: `d78211d9-eddb-4095-a93a-d1f5640e4c02`
- **filter**:

```json
{
  "property": "Date",
  "date": {
    "equals": "<TODAY_DATE>"
  }
}
```

从每条记录中提取以下字段：

- **Name**: 活动标题
- **Description**: 详细说明（核心数据源）
- **Tags**: 工作领域标签
- **StartTime / EndTime**: 时间信息

## 第四步：分析与生成日报内容

基于活动记录和 Git 提交日志，进行以下分析：

1. **去重合并**: 识别相似或重复的活动，合并为一条记录
2. **分类整理**: 按工作领域（固件开发、硬件开发、插件开发、系统优化等）分组
3. **重点提炼**: 提取关键成果、技术要点、遇到的问题
4. **计划识别**: 从描述中识别未完成任务或下一步计划

生成以下 6 个章节的日报内容：

### 📋 今日工作概览
2-3句话概述今日主要工作内容，涵盖所有工作领域。

### 🎯 工作重点
按工作领域分组，每个领域使用 heading_3 子标题：
- 具体工作内容描述
- 相关细节或进展

### ✅ 关键成果
- **成果标题**: 具体描述完成了什么，达到了什么效果

### ⚠️ 问题与风险
- 遇到的问题或潜在风险描述，以及应对措施
- 如无问题，写"今日工作顺利，暂无重大问题与风险"

### 📅 明日计划
- 明日计划工作项（从描述中的未完成任务和下一步计划提取）

### 📊 今日数据统计
使用表格展示：

| 指标 | 数值 |
|------|------|
| 活动记录数 | X条 |
| 工作时长 | X小时 |
| 涉及领域 | X个 |
| Git提交数 | X次 |

## 第五步：写入 Notion 日报数据库

使用 `mcp__notion__POST__v1_pages` 在日报数据库中创建新页面。

**数据库 ID**: `c7b19046-7ddf-44ec-b0f2-839577df4cbe`

**页面属性**：
- **标题（Name/Title）**: "<TODAY_DATE> 每日工作日报"
- **日期（Date）**: <TODAY_DATE>
- **状态（Status）**: "已完成"

**页面内容**：使用 `mcp__notion__PATCH__v1_blocks__block_id__children` 将日报内容作为 block children 追加到页面。使用以下 block 类型：

- `heading_2` — 章节标题（如 "📋 今日工作概览"）
- `heading_3` — 子标题（如工作领域名称）
- `bulleted_list_item` — 列表项
- `table` — 数据统计表格
- `paragraph` — 正文段落

**注意**：Notion API 每次最多追加 100 个 block，如果内容较多需要分批写入。

## 重要注意事项

1. 所有数据操作必须通过 Notion MCP 工具完成，不要编造数据
2. 统计表中的数值必须替换为实际数据
3. 工作时长根据活动记录的 StartTime/EndTime 估算
4. 如果今日无活动记录和 Git 提交，仍需创建日报并标注"今日无工作记录"
5. 日报语言使用中文
6. 保持客观、简洁的写作风格
