---
name: weekly-report
description: 自动生成每周工作周报，查询本周日报数据，跨天去重分析，生成结构化周报并写入 Notion
---

# 每周工作周报生成

你是一个专业的工作周报生成助手。请按照以下步骤，查询本周日报数据，进行跨天去重分析，生成结构化周报并写入 Notion。

## 配置信息

**Notion API 配置：**
- API Key: `{{NOTION_API_KEY}}`
- API Version: `2022-06-28`
- API Endpoint: `https://api.notion.com/v1`

**数据库 ID：**
- 每日工作日报: `{{DAILY_REPORT_DB_ID}}`
- 每周工作周报: `{{WEEKLY_REPORT_DB_ID}}`

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

使用 Notion API 查询日报数据库，筛选本周已完成的日报。

**API 调用：** `POST /databases/{db_id}/query`

```javascript
const result = await notionRequest(
  `/databases/{{DAILY_REPORT_DB_ID}}/query`,
  'POST',
  {
    filter: {
      and: [
        {
          property: '日期',
          date: { on_or_after: WEEK_START }
        },
        {
          property: '日期',
          date: { on_or_before: WEEK_END }
        },
        {
          property: '状态',
          status: { equals: '已完成' }
        }
      ]
    },
    sorts: [{ property: '日期', direction: 'ascending' }],
    page_size: 100
  }
);
```

## 第三步：读取每篇日报的完整内容

对查询到的每一篇日报，使用 Notion API 获取页面的完整内容块。

**API 调用：** `GET /blocks/{block_id}/children`

```javascript
for (const page of result.results) {
  const blocks = await notionRequest(`/blocks/${page.id}/children`, 'GET');
  // 处理 blocks.results，记录日报内容
}
```

记录每篇日报的：日期、工作内容条目、关键成果、遇到的问题、明日计划。

## 第四步：数据分析与整合

对收集到的所有日报数据进行跨天分析：

1. **跨天去重**: 识别跨多天出现的相同工作项，合并为一条记录并标注持续天数
2. **趋势分析**: 分析工作重心的变化趋势，识别本周主要投入方向
3. **成果聚合**: 汇总所有已完成的关键成果和里程碑
4. **问题归类**: 将各天遇到的问题按类别归类，识别反复出现的阻塞项
5. **领域统计**: 统计涉及的工作领域和每个领域的投入程度
6. **提取属性数据**:
   - `workDomains`: 涉及的工作领域数组，如 ['固件开发', '文档编写', '系统优化']
   - `workDaysCount`: 本周实际工作天数（有日报的天数）
   - `summary`: 3-5句话的周报摘要，提取自"本周工作概览"章节

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

## 第七步：写入 Notion 周报数据库

使用 Notion API 在每周工作周报数据库中创建新页面。

**API 调用：** `POST /pages`

```javascript
const notionBlocks = markdownToNotionBlocks(周报内容);

// 分批写入，每次最多 100 个 block
const batchSize = 100;
let pageId = null;

// 第一批：创建页面并写入前 100 个 block
const firstBatch = notionBlocks.slice(0, batchSize);
const result = await notionRequest('/pages', 'POST', {
  parent: { database_id: '{{WEEKLY_REPORT_DB_ID}}' },
  properties: {
    '周报标题': {
      title: [{ text: { content: `${WEEK_START_YEAR}年第${WEEK_NUMBER}周工作周报 (${WEEK_START_MMDD} - ${WEEK_END_MMDD})` } }]
    },
    '周期': {
      date: { start: WEEK_START, end: WEEK_END }
    },
    '状态': {
      status: { name: '已完成' }
    },
    '总活动记录数': {
      number: totalActivityCount
    },
    '工作领域': {
      multi_select: workDomains.map(domain => ({ name: domain }))
    },
    '涉及领域数': {
      number: workDomains.length
    },
    '工作日天数': {
      number: workDaysCount
    },
    '摘要': {
      rich_text: [{ text: { content: summary } }]
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

## 重要注意事项

1. 所有数据操作必须通过 Notion REST API 完成
2. 如果某天没有日报数据，在统计中如实反映
3. 周报语言使用中文
4. 保持客观、简洁的写作风格
5. 如果查询不到任何日报数据，请创建一个标注"本周无日报数据"的周报页面
6. 跨天去重时保留技术细节，不要过度简化
7. 下周计划应基于本周工作的延续和日报中提到的后续计划

## 第八步：验证写入结果

使用 Notion API 查询每周工作周报数据库，确认本周周报已成功创建。

```javascript
const result = await notionRequest(
  `/databases/{{WEEKLY_REPORT_DB_ID}}/query`,
  'POST',
  {
    filter: {
      and: [
        {
          property: '周期',
          date: { on_or_after: WEEK_START }
        },
        {
          property: '周期',
          date: { on_or_before: WEEK_END }
        }
      ]
    },
    page_size: 10
  }
);
```

如果 `result.results` 数组非空，输出：`[SUCCESS] 周报已成功写入 Notion`
如果 `result.results` 为空，输出：`[FAILED] 周报写入失败，请检查日志`
