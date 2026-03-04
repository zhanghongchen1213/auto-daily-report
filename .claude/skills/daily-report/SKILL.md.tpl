---
name: daily-report
description: 自动生成每日工作日报，查询 Notion 活动记录和 Git 提交日志，生成结构化日报并写入 Notion
---

# 每日工作日报生成

你是一个专业的每日工作总结分析专家。请按照以下步骤，查询今日活动记录，结合 Git 提交日志，生成结构化日报并写入 Notion。

## 配置信息

**Notion API 配置：**
- API Key: `{{NOTION_API_KEY}}`
- API Version: `2022-06-28`
- API Endpoint: `https://api.notion.com/v1`

**数据库 ID：**
- Activity Logs: `{{ACTIVITY_LOGS_DB_ID}}`
- 每日工作日报: `{{DAILY_REPORT_DB_ID}}`

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

## 第一步：获取今日日期

运行以下命令获取今日日期：

```bash
date +%Y-%m-%d
```

将结果记为 `TODAY_DATE`，后续步骤中使用。

## 第二步：收集 Git 提交日志

运行以下脚本收集今日所有配置仓库的 Git 提交记录：

```bash
bash {{PROJECT_DIR}}/scripts/gather-git-logs.sh --date "$TODAY_DATE"
```

将输出结果记为 `GIT_LOGS`，作为日报的补充数据源。

## 第三步：查询 Notion 活动记录

使用 Notion API 查询 Activity Logs 数据库，筛选今日活动记录。

**API 调用：** `POST /databases/{db_id}/query`

```javascript
const result = await notionRequest(
  `/databases/{{ACTIVITY_LOGS_DB_ID}}/query`,
  'POST',
  {
    filter: {
      property: 'Date',
      date: { equals: TODAY_DATE }
    },
    page_size: 100
  }
);
```

从查询结果的每条记录中提取以下字段：
- **Name**: `properties.Name?.title?.[0]?.plain_text || '无标题'`
- **Description**: `properties.Description?.rich_text?.[0]?.plain_text || ''`
- **Tags**: `properties.Tags?.multi_select?.map(t => t.name) || []`
- **Date**: `properties.Date?.date?.start`

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

使用 Notion API 在日报数据库中创建新页面。

**API 调用：** `POST /pages`

```javascript
const result = await notionRequest('/pages', 'POST', {
  parent: { database_id: '{{DAILY_REPORT_DB_ID}}' },
  properties: {
    '日报标题': {
      title: [{ text: { content: `${TODAY_DATE} 每日工作日报` } }]
    },
    '日期': {
      date: { start: TODAY_DATE }
    },
    '状态': {
      status: { name: '已完成' }
    },
    '活动记录数': {
      number: activities.length
    }
  },
  children: [
    {
      object: 'block',
      type: 'paragraph',
      paragraph: {
        rich_text: [{ type: 'text', text: { content: 日报内容 } }]
      }
    }
  ]
});
```

**注意事项：**
- Notion API 每次最多追加 100 个 block
- 如果内容较多需要分批写入
- 大段文本可以拆分成多个 paragraph block

## 重要注意事项

1. 所有 Notion 数据操作必须通过 Notion REST API 完成
2. 统计表中的数值必须替换为实际数据
3. 如果今日无活动记录和 Git 提交，仍需创建日报并标注"今日无工作记录"
4. 日报语言使用中文
5. 保持客观、简洁的写作风格

## 第六步：验证写入结果

使用 Notion API 查询日报数据库，筛选今日日期的记录，确认日报已成功创建。

```javascript
const result = await notionRequest(
  `/databases/{{DAILY_REPORT_DB_ID}}/query`,
  'POST',
  {
    filter: {
      property: '日期',
      date: { equals: TODAY_DATE }
    },
    page_size: 10
  }
);
```

如果 `result.results` 数组非空，输出：`[SUCCESS] 日报已成功写入 Notion`
如果 `result.results` 为空，输出：`[FAILED] 日报写入失败，请检查日志`
