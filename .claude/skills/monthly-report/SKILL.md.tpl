---
name: monthly-report
description: 自动生成每月工作月报，查询本月周报数据，跨周去重和里程碑识别，生成结构化月报并写入 Notion
---

# 每月工作月报生成

你是一个专业的工作月报生成助手。请按照以下步骤，查询本月周报数据，进行跨周去重和里程碑识别，生成结构化月报并写入 Notion。

## 配置信息

**Notion API 配置：**
- API Key: `{{NOTION_API_KEY}}`
- API Version: `2022-06-28`
- API Endpoint: `https://api.notion.com/v1`

**数据库 ID：**
- 每周工作周报: `{{WEEKLY_REPORT_DB_ID}}`
- 每月工作月报: `{{MONTHLY_REPORT_DB_ID}}`

## Notion API 请求方式

使用 Node.js HTTPS 模块直接调用 Notion REST API，请求格式如下：

```javascript
const https = require('https');

function notionRequest(path, method = 'GET', body = null) {
  return new Promise((resolve, reject) => {
    const options = {
      hostname: 'api.notion.com',
      path: `/v1${path}`,
      method: method,
      headers: {
        'Authorization': `Bearer {{NOTION_API_KEY}}`,
        'Content-Type': 'application/json',
        'Notion-Version': '2022-06-28'
      }
    };
    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => data += chunk);
      res.on('end', () => {
        try {
          const result = JSON.parse(data);
          if (result.error || result.code) reject(new Error(result.message));
          else resolve(result);
        } catch (e) { reject(e); }
      });
    });
    req.on('error', reject);
    if (body) req.write(JSON.stringify(body));
    req.end();
  });
}
```

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

使用 Notion API 查询每周工作周报数据库，筛选本月的所有周报。

**API 调用：** `POST /databases/{db_id}/query`

```javascript
const result = await notionRequest(
  `/databases/{{WEEKLY_REPORT_DB_ID}}/query`,
  'POST',
  {
    filter: {
      and: [
        {
          property: '周期',
          date: { on_or_after: MONTH_START }
        },
        {
          property: '周期',
          date: { on_or_before: MONTH_END }
        }
      ]
    },
    sorts: [{ property: '周期', direction: 'ascending' }],
    page_size: 100
  }
);
```

## 第三步：读取每份周报的完整内容

对查询到的每一份周报，使用 Notion API 获取页面的完整内容块。

**API 调用：** `GET /blocks/{block_id}/children`

```javascript
for (const page of result.results) {
  const blocks = await notionRequest(`/blocks/${page.id}/children`, 'GET');
  // 处理 blocks.results，记录周报内容
}
```

记录每份周报的标题、日期范围和完整内容。

## 第四步：数据处理与去重

对收集到的所有周报内容进行跨周去重和整合：

1. **跨周去重**: 同一项工作如果在多个周报中出现，合并为一条记录，保留最详细的技术描述
2. **进度追踪**: 识别跨周持续进行的工作项，标注其进展轨迹
3. **里程碑识别**: 提取本月完成的重要里程碑和关键成果
4. **问题汇总**: 收集所有周报中提到的问题、风险和阻塞项
5. **领域统计**: 统计涉及的工作领域
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

## 第六步：Markdown 转换为 Notion 原生块格式

**重要：** 必须将 Markdown 内容转换为 Notion 原生块格式，而不是直接写入 Markdown 原格式。

使用以下转换函数：

```javascript
function markdownToNotionBlocks(markdown) {
  const blocks = [];
  const lines = markdown.split('\n');
  let inCodeBlock = false;
  let codeBlockLanguage = '';
  let codeBlockContent = [];
  let inTable = false;
  let tableRows = [];

  for (let i = 0; i < lines.length; i++) {
    let line = lines[i];

    // 代码块处理
    if (line.startsWith('```')) {
      if (!inCodeBlock) {
        inCodeBlock = true;
        codeBlockLanguage = line.slice(3).trim() || 'text';
        codeBlockContent = [];
      } else {
        inCodeBlock = false;
        blocks.push({
          object: 'block',
          type: 'code',
          code: {
            language: codeBlockLanguage,
            rich_text: [{ type: 'text', text: { content: codeBlockContent.join('\n') } }]
          }
        });
      }
      continue;
    }
    if (inCodeBlock) {
      codeBlockContent.push(line);
      continue;
    }

    // 跳过空行
    if (line.trim() === '') {
      continue;
    }

    // 标题处理
    if (line.startsWith('### ')) {
      blocks.push({
        object: 'block',
        type: 'heading_3',
        heading_3: {
          rich_text: [{ type: 'text', text: { content: line.slice(4).trim() } }]
        }
      });
      continue;
    }
    if (line.startsWith('## ')) {
      blocks.push({
        object: 'block',
        type: 'heading_2',
        heading_2: {
          rich_text: [{ type: 'text', text: { content: line.slice(3).trim() } }]
        }
      });
      continue;
    }
    if (line.startsWith('# ')) {
      blocks.push({
        object: 'block',
        type: 'heading_1',
        heading_1: {
          rich_text: [{ type: 'text', text: { content: line.slice(2).trim() } }]
        }
      });
      continue;
    }

    // 表格处理
    if (line.startsWith('|') && line.includes('|')) {
      if (!inTable) {
        inTable = true;
        tableRows = [];
      }
      // 跳过分隔线 |---|---|
      if (!line.includes('---')) {
        const cells = line.split('|').map(c => c.trim()).filter(c => c !== '');
        tableRows.push(cells);
      }
      // 如果下一行不是表格行，或者是最后一行，则结束表格
      const nextLine = lines[i + 1];
      if (!nextLine || !nextLine.startsWith('|')) {
        inTable = false;
        if (tableRows.length > 0) {
          const tableWidth = tableRows[0].length;
          blocks.push({
            object: 'block',
            type: 'table',
            table: {
              table_width: tableWidth,
              has_column_header: true,
              has_row_header: false,
              children: tableRows.map(row => ({
                type: 'table_row',
                table_row: {
                  cells: row.map(cell => [{ type: 'text', text: { content: cell } }])
                }
              }))
            }
          });
        }
      }
      continue;
    }

    // 列表处理
    if (line.startsWith('- ') || line.startsWith('* ')) {
      const content = line.slice(2).trim();
      // 检查是否是加粗标题格式：- **成果标题**: 描述
      const boldMatch = content.match(/^\*\*(.*?)\*\*:\s*(.*)$/);
      if (boldMatch) {
        blocks.push({
          object: 'block',
          type: 'bulleted_list_item',
          bulleted_list_item: {
            rich_text: [
              { type: 'text', text: { content: boldMatch[1] }, annotations: { bold: true } },
              { type: 'text', text: { content: ': ' + boldMatch[2] } }
            ]
          }
        });
      } else {
        blocks.push({
          object: 'block',
          type: 'bulleted_list_item',
          bulleted_list_item: {
            rich_text: [{ type: 'text', text: { content: content } }]
          }
        });
      }
      continue;
    }

    // 普通段落
    blocks.push({
      object: 'block',
      type: 'paragraph',
      paragraph: {
        rich_text: [{ type: 'text', text: { content: line } }]
      }
    });
  }

  return blocks;
}
```

## 第七步：写入 Notion 月报数据库

使用 Notion API 在每月工作月报数据库中创建新页面。

**API 调用：** `POST /pages`

```javascript
const notionBlocks = markdownToNotionBlocks(月报内容);

// 分批写入，每次最多 100 个 block
const batchSize = 100;
let pageId = null;

// 第一批：创建页面并写入前 100 个 block
const firstBatch = notionBlocks.slice(0, batchSize);
const result = await notionRequest('/pages', 'POST', {
  parent: { database_id: '{{MONTHLY_REPORT_DB_ID}}' },
  properties: {
    '月报标题': {
      title: [{ text: { content: `${MONTH_YEAR}年${MONTH_NUM}月工作月报` } }]
    },
    '周期': {
      date: { start: MONTH_START, end: MONTH_END }
    },
    '状态': {
      status: { name: '已完成' }
    },
    '总活动记录数': {
      number: totalActivityCount
    }
  },
  children: firstBatch
});

pageId = result.id;

// 后续批次：追加剩余 block
for (let i = batchSize; i < notionBlocks.length; i += batchSize) {
  const batch = notionBlocks.slice(i, i + batchSize);
  await notionRequest(`/blocks/${pageId}/children`, 'PATCH', { children: batch });
}
```

**注意事项：**
- Notion API 每次最多追加 100 个 block
- 使用 `markdownToNotionBlocks()` 函数将 Markdown 转换为 Notion 原生格式
- 标题会变为 heading_1/heading_2/heading_3 块
- 表格会变为 table 块
- 列表会变为 bulleted_list_item 块
- 代码块会变为 code 块

## 第八步：验证写入结果

1. 所有数据操作必须通过 Notion REST API 完成
2. 如果某个时间范围内没有周报数据，在月报中如实说明
3. 去重时保留技术细节，不要过度简化
4. 下月计划应基于本月工作的延续和周报中提到的后续计划
5. 数据统计必须准确，基于实际查询到的周报数据计算
6. 月报语言使用中文
7. 保持客观、简洁的写作风格

1. 所有数据操作必须通过 Notion REST API 完成
2. 如果某个时间范围内没有周报数据，在月报中如实说明
3. 去重时保留技术细节，不要过度简化
4. 下月计划应基于本月工作的延续和周报中提到的后续计划
5. 数据统计必须准确，基于实际查询到的周报数据计算
6. 月报语言使用中文
7. 保持客观、简洁的写作风格

使用 Notion API 查询每月工作月报数据库，确认本月月报已成功创建。

```javascript
const result = await notionRequest(
  `/databases/{{MONTHLY_REPORT_DB_ID}}/query`,
  'POST',
  {
    filter: {
      property: '周期',
      date: { on_or_after: MONTH_START }
    },
    page_size: 10
  }
);
```

如果 `result.results` 数组非空，输出：`[SUCCESS] 月报已成功写入 Notion`
如果 `result.results` 为空，输出：`[FAILED] 月报写入失败，请检查日志`
