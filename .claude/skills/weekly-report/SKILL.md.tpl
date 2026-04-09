---
name: weekly-report
description: 自动生成高质量每周工作周报，融合本周日报、原始 Git 周范围数据与跨天趋势分析，输出信息完整、可直接提交的详细周报
---

# 每周工作周报生成

你是一个专业的工作周报生成助手。你的任务不是把日报简单拼接，也不是把一周工作浓缩成几句摘要，而是产出一份**信息完整、层次清晰、具备项目推进脉络**的正式周报。周报必须覆盖本周全部日报数据，同时**独立扫描 `config.json` 中全部仓库的整周 Git 数据**进行交叉校验，避免因日报过于简略而导致周报失真。

## 核心要求（不可违反）

1. **双数据源**: 必须同时使用"本周日报"和"独立 Git 采集"两个数据源，交叉校验，确保不遗漏
2. **全仓库覆盖**: 必须扫描 `config.json` 中的全部仓库（当前为 3 个），每个仓库不论是否有提交都必须在周报中出现
3. **全分支覆盖**: 每个仓库必须列出本周所有有提交的分支及其提交详情
4. **项目推进脉络**: 必须明确"本周开始了什么、推进了什么、完成了什么、还有什么未闭环"
5. **禁止空泛摘要**: 不允许用"本周主要完成了若干优化"这类空泛摘要，必须保留仓库名、分支名、模块名、提交线索、技术动作、业务结果
6. **最小内容量**: 周报正文不得少于 30 个 Notion block（有提交时），确保内容充实

## 配置信息

**Notion API 配置：**
- API Key: `{{NOTION_API_KEY}}`
- API Version: `2022-06-28`
- API Endpoint: `https://api.notion.com/v1`

**数据库 ID：**
- 每日工作日报: `{{DAILY_REPORT_DB_ID}}`
- 每周工作周报: `{{WEEKLY_REPORT_DB_ID}}`

**仓库配置来源：** `/Users/xiaozhangxuezhang/Documents/GitHub/auto-daily-report/config.json`

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

## 第二步：独立采集全部仓库整周 Git 数据（关键步骤）

**此步骤独立于日报，直接从 Git 仓库采集本周完整数据，作为周报的第一数据源。**

### 2.1 调用 gather-git-logs.sh 获取整周概览

```bash
bash /Users/xiaozhangxuezhang/Documents/GitHub/auto-daily-report/scripts/gather-git-logs.sh \
  --since "$WEEK_START 00:00:00" --until "$WEEK_END 23:59:59"
```

### 2.2 逐仓库逐分支深度采集

对 `config.json` 中的**每一个仓库**，执行以下采集流程：

```bash
CONFIG_FILE="/Users/xiaozhangxuezhang/Documents/GitHub/auto-daily-report/config.json"
REPOS=$(python3 -c "import json; [print(r) for r in json.load(open('$CONFIG_FILE'))['github']['repos']]")

for REPO_PATH in $REPOS; do
  REPO_NAME=$(basename "$REPO_PATH")

  echo "========================================"
  echo "仓库: $REPO_NAME"
  echo "路径: $REPO_PATH"
  echo "========================================"

  cd "$REPO_PATH"
  git fetch --all --prune 2>/dev/null || true

  # 获取所有分支名（本地 + 远程去重，排除裸 origin 和 HEAD）
  BRANCHES=$(git for-each-ref --format='%(refname:short)' refs/heads/ refs/remotes/origin/ 2>/dev/null | sed 's|^origin/||' | grep -v -E '^(HEAD|origin)$' | sort -u)

  REPO_HAS_COMMITS=false

  for BRANCH in $BRANCHES; do
    # 确定引用：使用全限定路径避免歧义
    if git rev-parse --verify "refs/heads/$BRANCH" &>/dev/null; then
      REF="refs/heads/$BRANCH"
    elif git rev-parse --verify "refs/remotes/origin/$BRANCH" &>/dev/null; then
      REF="refs/remotes/origin/$BRANCH"
    else
      continue
    fi

    COMMIT_COUNT=$(git log "$REF" --since="$WEEK_START 00:00:00" --until="$WEEK_END 23:59:59" --oneline --no-merges 2>/dev/null | wc -l | tr -d ' ')

    if [ "$COMMIT_COUNT" -gt 0 ]; then
      REPO_HAS_COMMITS=true
      echo ""
      echo "--- 分支: $BRANCH ($COMMIT_COUNT 次提交) ---"

      git log "$REF" --since="$WEEK_START 00:00:00" --until="$WEEK_END 23:59:59" \
        --no-merges \
        --pretty=format:"%n提交: %h%n作者: %an%n时间: %ad%n消息: %s%n" \
        --date=iso-local --stat 2>/dev/null

      echo ""
    fi
  done

  if [ "$REPO_HAS_COMMITS" = false ]; then
    echo "[该仓库本周无提交记录]"
  fi
  echo ""
done
```

### 2.3 采集结果要求

整理出完整的周度 Git 数据结构，包含：
- 每个仓库的本周提交总数、活跃分支列表
- 每个分支的提交明细（哈希、消息、作者、时间、变更文件、增删行数）
- 每个仓库的日维度提交分布（周一到周日各多少次提交）
- 全局统计：扫描仓库数、有提交仓库数、活跃分支总数、提交总数

**校验点**: 扫描仓库数必须等于 `config.json` 中的仓库数量。

## 第三步：查询本周日报数据

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

## 第四步：读取每篇日报的完整内容

对查询到的每一篇日报，使用 Notion API 获取页面的完整内容块。

**API 调用：** `GET /blocks/{block_id}/children`

```javascript
for (const page of result.results) {
  const blocks = await notionRequest(`/blocks/${page.id}/children`, 'GET');
  // 处理 blocks.results，提取日报内容
}
```

从每篇日报中提取：
- 日期
- 工作概览
- 逐仓库工作详情（含提交记录）
- 关键成果
- 遇到的问题
- 明日计划（即后续工作方向）

## 第五步：交叉校验与数据整合

**关键**: 将"独立 Git 采集数据"与"日报数据"进行交叉比对：

1. **发现日报遗漏**: 如果 Git 采集中有某仓库/分支的提交，但日报中未提及，必须在周报中补充
2. **跨天去重合并**: 同一功能/模块如果在多天的日报中出现，合并为一条记录并标注持续天数和进展轨迹
3. **进度脉络梳理**: 识别本周工作的起始→推进→完成→遗留路径
4. **趋势分析**: 按日分析提交频率和工作重心变化，识别本周主要投入方向
5. **成果聚合**: 汇总所有已完成的关键成果和里程碑
6. **问题归类**: 将各天遇到的问题按类别归类，识别反复出现的阻塞项
7. **领域统计**: 统计涉及的工作领域和每个领域的投入程度

**提取属性数据：**
- `workDomains`: 涉及的工作领域数组
- `workDaysCount`: 本周实际工作天数（有日报的天数）
- `totalActivityCount`: 本周活动记录总数（从日报属性中累加）
- `summary`: 3-5句话的周报摘要

## 第六步：生成周报内容

### 内容生成强制规范

**禁止行为：**
- 禁止将一周工作浓缩为几句空泛摘要
- 禁止省略任何仓库（即使无提交也要标注）
- 禁止合并不相关的工作项
- 禁止省略提交线索（哈希、分支名、模块名）
- 禁止"本周工作概览"少于 5 句话
- 禁止"工作重点"按仓库分组后每个仓库少于 3 条内容
- 禁止"关键成果"少于 3 条
- 禁止"下周计划"少于 3 条

**必须行为：**
- 每个仓库必须有独立的 heading 段落
- 无提交的仓库必须显式标注"本周无提交记录"
- 跨天持续的工作项必须标注持续天数和进展
- 所有数字必须基于实际数据

### 周报正文结构（按顺序生成以下章节）

#### 章节 1: 📋 本周工作概览

**要求: 5-10 句话**，必须覆盖以下内容：
- 本周日期范围和周序号
- 涉及哪些仓库（列出仓库名）
- 各仓库的主要工作方向和重点
- 本周提交总数、活跃分支数、工作天数
- 主要技术方向和里程碑进展
- 整体工作节奏评价（紧凑/平稳/前紧后松等）

#### 章节 2: 📊 仓库覆盖总表（强制）

**必须以表格形式展示全部配置仓库的本周扫描结果**：

| 仓库名 | 活跃分支数 | 本周提交总数 | 提交天数 | 主要变更模块 | 状态 |
|--------|-----------|-------------|---------|-------------|------|
| main_control | X | X | X天 | 模块A, 模块B | 有提交/无提交 |
| Legbots-App | X | X | X天 | 模块C | 有提交/无提交 |
| LegBots-kanban | X | X | X天 | 模块D | 有提交/无提交 |

#### 章节 3: 🔧 逐仓库工作详情（按仓库分组，本周推进脉络）

**对每个仓库使用 heading_2 子标题**，仓库内按分支使用 heading_3 子标题。

每个仓库必须包含：
- **活跃分支列表**: 列出本周所有有提交的分支
- **日维度提交分布**: 标注每天的提交数量（如"周一 3 次, 周三 5 次, 周五 2 次"）
- **推进脉络**: 本周在该仓库上的工作起始→推进→完成→遗留路径
- **提交明细**: 按分支列出全部提交，每条包含哈希、消息、变更文件、变更统计

结构示例：

```
### main_control

本周提交 12 次，涉及 develop、feature/sensor-fusion 两个分支。日维度分布: 周一 3 次, 周二 2 次, 周三 4 次, 周四 2 次, 周五 1 次。

#### develop 分支 (8次提交)

工作脉络: 本周初开始电机 PID 参数优化 → 周中完成积分限幅机制 → 周末通过全量自检验证。

- **提交 a1b2c3d** (周一): 优化电机 PID 控制算法的积分项计算
  - 变更文件: `src/motor/pid_controller.c`, `tests/test_pid.c`
  - 变更统计: +45 行, -12 行
- **提交 d4e5f6a** (周一): 更新电机参数配置表
  ...
[列出全部提交]

#### feature/sensor-fusion 分支 (4次提交)
...

### Legbots-App
...

### LegBots-kanban
[如无提交] 本周无提交记录。
```

#### 章节 4: ✅ 关键成果

**要求: 3-10 条**，每条必须包含：
- 具体的技术成果和业务价值
- 关联的仓库和分支
- 量化数据（如有）

**正面示例**: "**电机 PID 积分限幅机制完成并通过验证**: 在 main_control/develop 分支经过周一至周三的 8 次提交，完成了积分项限幅算法的实现与测试，自检通过率从 92% 提升至 99%"

#### 章节 5: ⚠️ 问题与风险

- 问题描述及影响范围，关联具体仓库/分支/模块
- 已解决的问题标注解决方案
- 未解决的阻塞项标注建议处理方式和优先级
- 如本周无明显问题，可写"本周工作进展顺利，暂无重大问题与风险"

#### 章节 6: 📅 下周计划

**要求: 3-8 条**，按优先级排序，每条必须具体到仓库/模块级别：
- 从本周未完成的工作中提取
- 从日报中的"明日计划"中汇总
- 从 Git 提交趋势中预判的后续工作

#### 章节 7: 📊 本周数据统计

使用表格展示：

| 指标 | 数值 |
|------|------|
| 工作天数 | X 天 |
| 扫描仓库数 | X 个 |
| 有提交仓库数 | X 个 |
| 活跃分支总数 | X 个 |
| Git 提交总数 | X 次 |
| 变更文件总数 | X 个 |
| 活动记录总数 | X 条 |
| 涉及工作领域 | X 个 |

## 第七步：Markdown 转换为 Notion 原生块格式

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
      if (!line.includes('---')) {
        const cells = line.split('|').map(c => c.trim()).filter(c => c !== '');
        tableRows.push(cells);
      }
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

## 第八步：写入 Notion 周报数据库

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

## 第九步：验证写入结果

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

验证要求：

1. `result.results` 必须非空
2. 最新一条记录的标题、周期、摘要必须正确
3. 页面正文必须包含"仓库覆盖总表"
4. 全部仓库名必须在正文中出现
5. 正文 block 数量不得少于 30 个（有提交时）

如果验证通过，输出：`[SUCCESS] 周报已成功写入 Notion`
如果验证失败，输出：`[FAILED] 周报写入失败，请检查仓库覆盖、Git 数据采集和 Notion 写入结果`

## 最终质量门槛

1. 不允许遗漏任何配置仓库 — 全部仓库必须出现在"仓库覆盖总表"中
2. 不允许遗漏 Git 采集中发现但日报未提及的提交
3. 不允许用空泛措辞替代具体工作内容
4. 不允许省略推进脉络 — 每个仓库必须有"起始→推进→完成→遗留"的叙述
5. 不允许"已扫描但无提交"的仓库被静默跳过
6. 跨天去重时保留技术细节，不要过度简化
7. 下周计划必须具体到仓库/模块级别，不允许写泛化口号
8. 数据统计表中的数字必须与实际采集结果一致
9. 周报语言必须为中文
10. 如果本周所有仓库均无提交且无日报数据，仍需创建周报并标注"本周无工作记录"
