---
name: weekly-report
description: 自动生成每周工作周报，查询本周日报数据，跨天去重分析，生成结构化周报并写入 Notion
---

# 每周工作周报生成

你是一个专业的工作周报生成助手。请按照以下步骤，查询本周日报数据，进行跨天去重分析，生成结构化周报并写入 Notion。

## 第一步：计算本周日期范围

运行以下命令获取本周的起止日期（周一到周日）：

```bash
# 获取本周一和本周日的日期
python3 -c "
from datetime import datetime, timedelta
today = datetime.now()
monday = today - timedelta(days=today.weekday())
sunday = monday + timedelta(days=6)
print(f'WEEK_START={monday.strftime(\"%Y-%m-%d\")}')
print(f'WEEK_END={sunday.strftime(\"%Y-%m-%d\")}')
print(f'WEEK_NUMBER={monday.isocalendar()[1]}')
print(f'WEEK_START_YEAR={monday.strftime(\"%Y\")}')
print(f'WEEK_START_MMDD={monday.strftime(\"%m/%d\")}')
print(f'WEEK_END_MMDD={sunday.strftime(\"%m/%d\")}')
"
```

记录 `WEEK_START`、`WEEK_END`、`WEEK_NUMBER` 等变量，后续步骤中使用。

## 第二步：查询本周日报数据

使用 Notion MCP 工具查询日报数据库，筛选本周已完成的日报。

调用 `mcp__notion__API-query-data-source`，参数如下：

- **data_source_id**: `fd9e5cb4-2ab8-488f-a16c-9f1b3ced7d66`
- **filter**:

```json
{
  "and": [
    {
      "property": "日期",
      "date": {
        "on_or_after": "<WEEK_START>"
      }
    },
    {
      "property": "日期",
      "date": {
        "on_or_before": "<WEEK_END>"
      }
    },
    {
      "property": "状态",
      "status": {
        "equals": "已完成"
      }
    }
  ]
}
```

按日期升序排列结果。

## 第三步：读取每篇日报的完整内容

对查询到的每一篇日报，使用 `mcp__notion__API-get-block-children` 获取页面的完整内容块。

- **block_id** 为每篇日报页面的 page_id
- 递归读取所有子块，确保获取完整内容
- 记录每篇日报的：日期、工作内容条目、关键成果、遇到的问题、明日计划

## 第四步：数据分析与整合

对收集到的所有日报数据进行跨天分析：

1. **跨天去重**: 识别跨多天出现的相同工作项，合并为一条记录并标注持续天数
2. **趋势分析**: 分析工作重心的变化趋势，识别本周主要投入方向
3. **成果聚合**: 汇总所有已完成的关键成果和里程碑
4. **问题归类**: 将各天遇到的问题按类别归类，识别反复出现的阻塞项
5. **领域统计**: 统计涉及的工作领域和每个领域的投入程度

## 第五步：生成周报内容

基于分析结果，生成以下 6 个章节的周报内容：

### 📋 本周工作概览
3-5句话概述本周工作情况、整体节奏和主要方向。

### 🎯 工作重点
按工作领域分组（3-5个领域），每个领域使用 heading_3 子标题：
- 具体工作内容，合并跨天重复项，标注持续天数
- 相关子任务和进展

### ✅ 关键成果
- **成果标题**: 具体描述，包含量化数据（如有）

### ⚠️ 问题与风险
- 问题描述及影响范围，如有解决方案请注明
- 未解决的阻塞项及建议处理方式
- 如本周无明显问题，可写"本周工作进展顺利，暂无重大问题与风险"

### 📅 下周计划
- 从本周未完成项和日报中的"明日计划"中提取
- 按优先级排序

### 📊 本周数据统计
使用表格展示：

| 指标 | 数值 |
|------|------|
| 工作天数 | X天 |
| 活动记录总数 | X条 |
| 涉及领域 | X个 |
| 完成事项 | X项 |
| 未完成/进行中 | X项 |

## 第六步：写入 Notion 周报数据库

使用 `mcp__notion__API-post-page` 在周报数据库中创建新页面。

**数据库 ID**: `7efbdb06-82de-4688-834c-7a377db93077`

**页面属性**：
- **周报标题（Title）**: "<WEEK_START_YEAR>年第<WEEK_NUMBER>周工作周报 (<WEEK_START_MMDD> - <WEEK_END_MMDD>)"
- **周期（Date）**: 日期范围 start = <WEEK_START>, end = <WEEK_END>
- **工作领域（Multi-select）**: 从日报中聚合的工作领域标签
- **状态（Status）**: "已完成"
- **工作日天数（Number）**: 本周实际有日报的工作天数
- **总活动记录数（Number）**: 本周所有日报中的活动记录总条数
- **涉及领域数（Number）**: 本周涉及的工作领域数量
- **摘要（Rich Text）**: 3-5句话的本周工作概述

**页面内容**：使用 `mcp__notion__API-patch-block-children` 将周报内容作为 block children 追加到页面。使用以下 block 类型：

- `heading_2` — 章节标题（如 "📋 本周工作概览"）
- `heading_3` — 子标题（如工作领域名称）
- `bulleted_list_item` — 列表项
- `table` — 数据统计表格
- `paragraph` — 正文段落

**注意**：Notion API 每次最多追加 100 个 block，如果内容较多需要分批写入。

## 重要注意事项

1. 所有数据操作必须通过 Notion MCP 工具完成，不要编造数据
2. 如果某天没有日报数据，在统计中如实反映
3. 周报语言使用中文
4. 保持客观、简洁的写作风格
5. 如果查询不到任何日报数据，请创建一个标注"本周无日报数据"的周报页面
6. 跨天去重时保留技术细节，不要过度简化
7. 下周计划应基于本周工作的延续和日报中提到的后续计划

## 第七步：验证写入结果

使用 `mcp__notion__API-query-data-source` 查询周报数据库，确认本周周报已成功创建。

参数：
- **data_source_id**: `7efbdb06-82de-4688-834c-7a377db93077`
- **filter**:

```json
{
  "and": [
    {
      "property": "周期",
      "date": {
        "on_or_after": "<WEEK_START>"
      }
    },
    {
      "property": "周期",
      "date": {
        "on_or_before": "<WEEK_END>"
      }
    }
  ]
}
```

如果查询到结果，输出：`[SUCCESS] 周报已成功写入 Notion`
如果未查询到结果，输出：`[FAILED] 周报写入失败，请检查日志`
