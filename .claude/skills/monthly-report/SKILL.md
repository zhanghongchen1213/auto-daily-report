---
name: monthly-report
description: 自动生成每月工作月报，查询本月周报数据，跨周去重和里程碑识别，生成结构化月报并写入 Notion
---

# 每月工作月报生成

你是一个专业的工作月报生成助手。请按照以下步骤，查询本月周报数据，进行跨周去重和里程碑识别，生成结构化月报并写入 Notion。

## 第一步：计算本月日期范围

运行以下命令获取本月的起止日期：

```bash
python3 -c "
from datetime import datetime
import calendar
today = datetime.now()
first_day = today.replace(day=1)
last_day = today.replace(day=calendar.monthrange(today.year, today.month)[1])
print(f'MONTH_START={first_day.strftime(\"%Y-%m-%d\")}')
print(f'MONTH_END={last_day.strftime(\"%Y-%m-%d\")}')
print(f'MONTH_YEAR={today.strftime(\"%Y\")}')
print(f'MONTH_NUM={today.strftime(\"%m\")}')
"
```

记录 `MONTH_START`、`MONTH_END`、`MONTH_YEAR`、`MONTH_NUM` 等变量，后续步骤中使用。

## 第二步：查询本月周报数据

使用 Notion MCP 工具查询周报数据库，筛选本月的所有周报。

调用 `mcp__notion__API-query-data-source`，参数如下：

- **data_source_id**: `7efbdb06-82de-4688-834c-7a377db93077`
- **filter**:

```json
{
  "and": [
    {
      "property": "周期",
      "date": {
        "on_or_after": "<MONTH_START>"
      }
    },
    {
      "property": "周期",
      "date": {
        "on_or_before": "<MONTH_END>"
      }
    }
  ]
}
```

- **sorts**:

```json
[
  {
    "property": "周期",
    "direction": "ascending"
  }
]
```

## 第三步：读取每份周报的完整内容

对查询到的每一份周报，使用 `mcp__notion__API-get-block-children` 获取页面的完整内容块。

- **block_id** 为每份周报页面的 page_id
- 递归读取所有子块，确保获取完整内容
- 记录每份周报的标题、日期范围和完整内容

## 第四步：数据处理与去重

对收集到的所有周报内容进行跨周去重和整合：

1. **跨周去重**: 同一项工作如果在多个周报中出现，合并为一条记录，保留最详细的技术描述
2. **进度追踪**: 识别跨周持续进行的工作项，标注其进展轨迹
3. **里程碑识别**: 提取本月完成的重要里程碑和关键成果
4. **问题汇总**: 收集所有周报中提到的问题、风险和阻塞项
5. **领域统计**: 统计涉及的工作领域（从周报的 work_domains 属性聚合）
6. **数据统计**: 统计工作周数、工作天数、活动记录总数等

## 第五步：生成月报内容

根据整合后的数据，生成以下 7 个章节的月报内容：

### 📋 本月工作概览
3-5句话概述本月工作主题、整体情况，包括工作周数和主要方向。

### 🎯 工作重点
使用层级结构组织（通常2-4个主要模块）：
- 每个主要模块使用 heading_3 子标题
- 每个模块下可有子模块，使用加粗文本区分
- 具体工作内容保留技术细节
- 标注相关成果或进展

### ✅ 关键成果与里程碑
- 🏆 **里程碑名称**: 具体描述，包含量化数据
- **关键成果**: 描述
- 列出本月最重要的3-6项成果

### ⚠️ 问题与风险
按类别分组（使用 heading_3 子标题）：
- 框架/架构类
- 性能/测试类
- 其他
- 如无某类问题可省略该子分类

### 📅 下月计划
- 列出8-10项下月计划，按优先级排序
- 基于本月工作的延续和周报中提到的后续计划

### 📊 本月数据统计
使用表格展示：

| 指标 | 数值 |
|------|------|
| 工作周数 | X周 |
| 工作天数 | X天 |
| 活动记录总数 | X条 |
| 涉及领域 | X个 |

### 💡 本月工作亮点
2-3句话总结本月最突出的工作亮点和价值贡献。

## 第六步：写入 Notion 月报数据库

使用 `mcp__notion__API-post-page` 在月报数据库中创建新页面。

**数据库 ID**: `2dfc4066-5e1c-484b-bbaf-5a99a4b8490f`

**页面属性**：
- **月报标题（Title）**: "<MONTH_YEAR>年<MONTH_NUM>月工作月报"
- **周期（Date）**: 日期范围 start = <MONTH_START>, end = <MONTH_END>
- **工作领域（Multi-select）**: 从所有周报的 work_domains 属性聚合去重
- **状态**: "已完成"
- **工作周数（Number）**: 从查询到的周报数量得出
- **总活动记录数（Number）**: 所有周报活动记录数之和
- **涉及领域数（Number）**: 工作领域去重后的数量
- **摘要（Rich Text）**: 3-5句话概述本月工作

**页面内容**：使用 `mcp__notion__API-patch-block-children` 将月报内容作为 block children 追加到页面。使用以下 block 类型：

- `heading_2` — 章节标题（如 "📋 本月工作概览"）
- `heading_3` — 子标题（如工作模块名称）
- `bulleted_list_item` — 列表项
- `table` — 数据统计表格
- `paragraph` — 正文段落

**注意**：Notion API 每次最多追加 100 个 block，如果内容较多需要分批写入。

## 重要注意事项

1. 所有数据操作必须通过 Notion MCP 工具完成，不要编造数据
2. 如果某个时间范围内没有周报数据，在月报中如实说明
3. 去重时保留技术细节，不要过度简化
4. 下月计划应基于本月工作的延续和周报中提到的后续计划
5. 数据统计必须准确，基于实际查询到的周报数据计算
6. 工作领域从周报的 work_domains 多选属性聚合，去重后填入月报
7. 月报语言使用中文
8. 保持客观、简洁的写作风格

## 第七步：验证写入结果

使用 `mcp__notion__API-query-data-source` 查询月报数据库，确认本月月报已成功创建。

参数：
- **data_source_id**: `2dfc4066-5e1c-484b-bbaf-5a99a4b8490f`
- **filter**:

```json
{
  "property": "周期",
  "date": {
    "on_or_after": "<MONTH_START>"
  }
}
```

如果查询到结果，输出：`[SUCCESS] 月报已成功写入 Notion`
如果未查询到结果，输出：`[FAILED] 月报写入失败，请检查日志`
