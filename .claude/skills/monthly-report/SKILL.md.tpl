---
name: monthly-report
description: 自动生成每月工作月报，融合本月周报数据与独立 Git 月度采集，跨周去重和里程碑识别，生成信息完整的结构化月报并写入 Notion
---

# 每月工作月报生成

你是一个专业的工作月报生成助手。你的任务不是简单汇总周报，而是产出一份**信息完整、层次清晰、具备项目月度全景视角**的正式月报。月报必须覆盖本月全部周报数据，同时**独立扫描 `config.json` 中全部仓库的整月 Git 数据**进行交叉校验，确保不遗漏任何月度工作成果。

## 核心要求（不可违反）

1. **双数据源**: 必须同时使用"本月周报"和"独立 Git 月度采集"两个数据源，交叉校验
2. **全仓库覆盖**: 必须扫描 `config.json` 中的全部仓库（当前为 3 个），每个仓库不论是否有提交都必须在月报中出现
3. **全分支覆盖**: 每个仓库必须列出本月所有有提交的分支及其活动概况
4. **月度全景视角**: 必须体现项目月度进展的全景 — 里程碑、关键转折、技术演进、资源投入分布
5. **禁止空泛摘要**: 不允许用"本月主要完成了若干优化"这类空泛摘要，必须保留仓库名、分支名、模块名、关键提交线索
6. **最小内容量**: 月报正文不得少于 40 个 Notion block（有提交时），确保内容充实

## 配置信息

**Notion API 配置：**
- API Key: `{{NOTION_API_KEY}}`
- API Version: `2022-06-28`
- API Endpoint: `https://api.notion.com/v1`

**数据库 ID：**
- 每周工作周报: `{{WEEKLY_REPORT_DB_ID}}`
- 每月工作月报: `{{MONTHLY_REPORT_DB_ID}}`

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

## 第二步：独立采集全部仓库整月 Git 数据（关键步骤）

**此步骤独立于周报，直接从 Git 仓库采集本月完整数据，作为月报的第一数据源。**

### 2.1 调用 gather-git-logs.sh 获取整月概览

```bash
bash /Users/xiaozhangxuezhang/Documents/GitHub/auto-daily-report/scripts/gather-git-logs.sh \
  --since "$MONTH_START 00:00:00" --until "$MONTH_END 23:59:59"
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

  # 获取所有分支名（本地 + 远程去重）
  BRANCHES=$(git for-each-ref --format='%(refname:short)' refs/heads/ refs/remotes/origin/ 2>/dev/null | sed 's|^origin/||' | grep -v '^HEAD$' | sort -u)

  REPO_HAS_COMMITS=false

  for BRANCH in $BRANCHES; do
    REF="$BRANCH"
    if ! git rev-parse --verify "$BRANCH" &>/dev/null; then
      REF="origin/$BRANCH"
    fi

    COMMIT_COUNT=$(git log "$REF" --since="$MONTH_START 00:00:00" --until="$MONTH_END 23:59:59" --oneline --no-merges 2>/dev/null | wc -l | tr -d ' ')

    if [ "$COMMIT_COUNT" -gt 0 ]; then
      REPO_HAS_COMMITS=true
      echo ""
      echo "--- 分支: $BRANCH ($COMMIT_COUNT 次提交) ---"

      # 月度采集使用精简格式（提交数可能较多），但仍包含 stat
      git log "$REF" --since="$MONTH_START 00:00:00" --until="$MONTH_END 23:59:59" \
        --no-merges \
        --pretty=format:"%n提交: %h%n作者: %an%n时间: %ad%n消息: %s%n" \
        --date=iso-local --stat 2>/dev/null

      echo ""
    fi
  done

  if [ "$REPO_HAS_COMMITS" = false ]; then
    echo "[该仓库本月无提交记录]"
  fi
  echo ""
done
```

### 2.3 采集结果要求

整理出完整的月度 Git 数据结构，包含：
- 每个仓库的本月提交总数、活跃分支列表
- 每个分支的提交数量和关键提交摘要
- 每个仓库的周维度提交分布（第1周到第4/5周各多少次提交）
- 全局统计：扫描仓库数、有提交仓库数、活跃分支总数、提交总数

**校验点**: 扫描仓库数必须等于 `config.json` 中的仓库数量。

## 第三步：查询本月周报数据

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

## 第四步：读取每份周报的完整内容

对查询到的每一份周报，使用 Notion API 获取页面的完整内容块。

**API 调用：** `GET /blocks/{block_id}/children`

```javascript
for (const page of result.results) {
  const blocks = await notionRequest(`/blocks/${page.id}/children`, 'GET');
  // 处理 blocks.results，提取周报内容
}
```

从每份周报中提取：
- 周序号和日期范围
- 仓库覆盖总表数据
- 逐仓库工作详情（含提交记录和推进脉络）
- 关键成果列表
- 问题与风险
- 下周计划
- 数据统计

## 第五步：交叉校验与数据整合

**关键**: 将"独立 Git 月度采集数据"与"周报数据"进行交叉比对：

1. **发现周报遗漏**: 如果 Git 采集中有某仓库/分支的提交，但周报中未提及，必须在月报中补充
2. **跨周去重合并**: 同一项工作如果在多个周报中出现，合并为一条记录，保留最详细的技术描述，标注持续周数
3. **进度追踪**: 识别跨周持续进行的工作项，标注其进展轨迹（从第N周的什么状态到第M周的什么状态）
4. **里程碑识别**: 提取本月完成的重要里程碑和关键成果，这些是月报的核心亮点
5. **问题汇总**: 收集所有周报中提到的问题、风险和阻塞项，区分已解决和未解决
6. **领域统计**: 统计涉及的工作领域和每个领域的月度投入程度
7. **数据汇总**: 累计工作周数、工作天数、活动记录总数、提交总数等

**提取属性数据：**
- `workDomains`: 涉及的工作领域数组
- `weekCount`: 本月实际工作周数（有周报的周数）
- `totalActivityCount`: 本月活动记录总数（从周报属性中累加）
- `summary`: 3-5句话的月报摘要

## 第六步：生成月报内容

### 内容生成强制规范

**禁止行为：**
- 禁止将一月工作浓缩为几句空泛摘要
- 禁止省略任何仓库（即使无提交也要标注）
- 禁止将不同仓库/模块的工作混在一起描述
- 禁止省略里程碑的量化成果
- 禁止"本月工作概览"少于 5 句话
- 禁止"工作重点"每个仓库少于 5 条内容
- 禁止"关键成果与里程碑"少于 3 条
- 禁止"下月计划"少于 5 条

**必须行为：**
- 每个仓库必须有独立的 heading 段落
- 无提交的仓库必须显式标注"本月无提交记录"
- 跨周持续的工作项必须标注持续周数和进展轨迹
- 所有数字必须基于实际数据
- 里程碑必须有具体的技术描述和业务价值

### 月报正文结构（按顺序生成以下章节）

#### 章节 1: 📋 本月工作概览

**要求: 5-10 句话**，必须覆盖以下内容：
- 本月年月和工作周数
- 涉及哪些仓库（列出仓库名）
- 各仓库的月度主要方向
- 本月提交总数、活跃分支数、工作天数
- 主要里程碑和重点技术方向
- 整体月度节奏评价

#### 章节 2: 📊 仓库覆盖总表（强制）

**必须以表格形式展示全部配置仓库的本月扫描结果**：

| 仓库名 | 活跃分支数 | 本月提交总数 | 提交周数 | 主要变更模块 | 状态 |
|--------|-----------|-------------|---------|-------------|------|
| main_control | X | X | X周 | 模块A, 模块B | 有提交/无提交 |
| Legbots-App | X | X | X周 | 模块C | 有提交/无提交 |
| LegBots-kanban | X | X | X周 | 模块D | 有提交/无提交 |

#### 章节 3: 🔧 逐仓库工作详情（按仓库分组，月度推进全景）

**对每个仓库使用 heading_2 子标题**，仓库内按主要工作模块/方向使用 heading_3 子标题。

每个仓库必须包含：
- **月度活跃分支列表**: 列出本月所有有提交的分支
- **周维度提交分布**: 标注每周的提交数量
- **月度推进全景**: 月初→月中→月末的工作演进路径，重要节点标注具体日期
- **分支/模块详情**: 按模块分组，列出关键提交和技术变更

结构示例：

```
### main_control

本月提交 45 次，涉及 develop、feature/sensor-fusion、hotfix/motor-stall 三个分支。周维度分布: 第1周 12 次, 第2周 15 次, 第3周 10 次, 第4周 8 次。

月度推进全景: 月初启动电机控制算法优化 → 第2周完成 PID 积分限幅并通过验证 → 第3周开始传感器融合模块开发 → 月末完成融合框架搭建，待下月补充滤波算法。

#### 电机控制模块优化 (develop 分支, 28次提交)

- 第1-2周: PID 算法优化
  - 完成积分限幅机制，解决长时间运行抖动问题
  - 更新参数配置表，基于实测数据调优
  - 关键提交: a1b2c3d, d4e5f6a, g7h8i9j
  - 涉及文件: `src/motor/pid_controller.c`, `config/motor_params.json`, `tests/test_pid.c`

- 第3周: 自检流程增强
  - 添加详细日志输出，便于生产排查
  - 关键提交: k0l1m2n
  ...

#### 传感器融合模块 (feature/sensor-fusion 分支, 17次提交)
...

### Legbots-App
...

### LegBots-kanban
[如无提交] 本月无提交记录。
```

#### 章节 4: ✅ 关键成果与里程碑

**要求: 3-10 条**，分为里程碑和关键成果两类：

里程碑（用 🏆 标记）:
- **里程碑名称**: 具体描述，包含量化数据、关联仓库/分支、完成时间
- 里程碑是月度最重要的 2-3 项成果

关键成果:
- **成果标题**: 具体描述，关联仓库/分支

**正面示例**: "🏆 **电机控制算法全面优化完成**: 在 main_control/develop 分支历经 4 周 28 次提交，完成了 PID 积分限幅、参数自适应、自检流程增强三项改进，电机自检通过率从 92% 提升至 99.5%，生产线故障率下降 60%"

#### 章节 5: ⚠️ 问题与风险

按类别分组（使用 heading_3 子标题），每类问题必须关联具体仓库/模块：

可能的类别：
- 架构/设计类
- 性能/稳定性类
- 流程/工具类
- 人力/资源类

每个问题必须包含：
- 问题描述和影响范围
- 当前状态（已解决/进行中/待处理）
- 已解决的标注解决方案
- 未解决的标注建议处理方式和优先级

如本月无明显问题，可写"本月工作进展顺利，暂无重大问题与风险"

#### 章节 6: 📅 下月计划

**要求: 5-10 条**，按优先级排序，每条必须具体到仓库/模块级别：
- 从本月未完成的工作中提取
- 从各周报中的"下周计划"中汇总未执行的项目
- 从月度技术演进趋势中预判的后续工作
- 新增的计划项（基于本月发现的问题或新需求）

#### 章节 7: 📊 本月数据统计

使用表格展示：

| 指标 | 数值 |
|------|------|
| 工作周数 | X 周 |
| 工作天数 | X 天 |
| 扫描仓库数 | X 个 |
| 有提交仓库数 | X 个 |
| 活跃分支总数 | X 个 |
| Git 提交总数 | X 次 |
| 活动记录总数 | X 条 |
| 涉及工作领域 | X 个 |
| 完成里程碑数 | X 个 |

#### 章节 8: 💡 本月工作亮点

**要求: 3-5 句话**，总结本月最突出的工作亮点和价值贡献：
- 必须关联具体的仓库和技术成果
- 必须包含量化数据（如有）
- 体现技术深度和业务价值

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

## 第八步：写入 Notion 月报数据库

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
    },
    '工作领域': {
      multi_select: workDomains.map(domain => ({ name: domain }))
    },
    '涉及领域数': {
      number: workDomains.length
    },
    '工作周数': {
      number: weekCount
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

验证要求：

1. `result.results` 必须非空
2. 最新一条记录的标题、周期、摘要必须正确
3. 页面正文必须包含"仓库覆盖总表"
4. 全部仓库名必须在正文中出现
5. 正文 block 数量不得少于 40 个（有提交时）

如果验证通过，输出：`[SUCCESS] 月报已成功写入 Notion`
如果验证失败，输出：`[FAILED] 月报写入失败，请检查仓库覆盖、Git 数据采集和 Notion 写入结果`

## 最终质量门槛

1. 不允许遗漏任何配置仓库 — 全部仓库必须出现在"仓库覆盖总表"中
2. 不允许遗漏 Git 月度采集中发现但周报未提及的提交活动
3. 不允许用空泛措辞替代具体工作内容
4. 不允许省略月度推进全景 — 每个仓库必须有月度演进叙述
5. 不允许"已扫描但无提交"的仓库被静默跳过
6. 跨周去重时保留技术细节，不要过度简化
7. 里程碑必须有量化数据和业务价值描述
8. 下月计划必须具体到仓库/模块级别，不允许写泛化口号
9. 数据统计表中的数字必须与实际采集结果一致
10. 月报语言必须为中文
11. 如果本月所有仓库均无提交且无周报数据，仍需创建月报并标注"本月无工作记录"
