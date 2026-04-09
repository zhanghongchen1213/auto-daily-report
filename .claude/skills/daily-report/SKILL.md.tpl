---
name: daily-report
description: 自动生成每日工作日报，深度采集全部仓库全部分支的 Git 提交，结合 Notion 活动记录，生成信息完整、可直接提交的详细日报并写入 Notion
---

# 每日工作日报生成

你是一个专业的每日工作总结分析专家。你的任务不是写一段简短摘要，而是产出一份**信息完整、细节丰富、可直接作为正式日报提交**的工作记录。日报必须覆盖 `config.json` 中配置的全部仓库的全部分支的当日全部 Git 提交，每条提交都必须有独立的详细记录。

## 核心要求（不可违反）

1. **全仓库覆盖**: 必须扫描 `config.json` 中的全部仓库（当前为 3 个），每个仓库不论是否有提交都必须在日报中出现
2. **全分支覆盖**: 每个仓库必须扫描所有本地分支和远程跟踪分支，列出当日有提交的每一个分支
3. **全提交覆盖**: 每一条 Git 提交都必须在日报正文中独立展示，包含哈希、消息、变更文件列表、变更统计
4. **禁止空泛摘要**: 不允许用"完成了若干优化"、"进行了部分调整"等空泛措辞替代具体工作内容
5. **禁止遗漏**: 不允许遗漏任何仓库、任何有提交的分支、任何提交记录
6. **最小内容量**: 日报正文不得少于 8 个 Notion block（不含属性），有提交时不得少于 20 个 block

## 配置信息

**Notion API 配置：**
- API Key: `{{NOTION_API_KEY}}`
- API Version: `2022-06-28`
- API Endpoint: `https://api.notion.com/v1`

**数据库 ID：**
- Activity Logs: `{{ACTIVITY_LOGS_DB_ID}}`
- 每日工作日报: `{{DAILY_REPORT_DB_ID}}`

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

## 第一步：读取配置与获取今日日期

### 1.1 获取今日日期

```bash
date +%Y-%m-%d
```

将结果记为 `TODAY_DATE`，后续步骤中使用。

### 1.2 读取仓库配置

```bash
CONFIG_FILE="/Users/xiaozhangxuezhang/Documents/GitHub/auto-daily-report/config.json"
python3 -c "
import json
with open('$CONFIG_FILE') as f:
    config = json.load(f)
repos = config['github']['repos']
print(f'共配置 {len(repos)} 个仓库:')
for i, repo in enumerate(repos):
    print(f'  [{i+1}] {repo}')
"
```

记录全部仓库路径列表 `REPO_LIST`，后续步骤中必须逐个遍历。

## 第二步：深度采集全部仓库 Git 数据（关键步骤）

**此步骤是日报质量的核心保障，必须严格执行，不得简化或跳过任何子步骤。**

### 2.1 调用 gather-git-logs.sh 获取概览

```bash
bash /Users/xiaozhangxuezhang/Documents/GitHub/auto-daily-report/scripts/gather-git-logs.sh --date "$TODAY_DATE"
```

将输出记为 `GIT_OVERVIEW`，作为整体概览参考。

### 2.2 逐仓库逐分支深度采集

对 `config.json` 中的**每一个仓库**，执行以下采集流程：

```bash
for REPO_PATH in "${REPO_LIST[@]}"; do
  REPO_NAME=$(basename "$REPO_PATH")

  echo "========================================"
  echo "仓库: $REPO_NAME"
  echo "路径: $REPO_PATH"
  echo "========================================"

  cd "$REPO_PATH"

  # 同步远端引用
  git fetch --all --prune 2>/dev/null || true

  # 获取所有分支名（本地 + 远程去重）
  BRANCHES=$(git for-each-ref --format='%(refname:short)' refs/heads/ refs/remotes/origin/ 2>/dev/null | sed 's|^origin/||' | grep -v '^HEAD$' | sort -u)

  REPO_HAS_COMMITS=false

  for BRANCH in $BRANCHES; do
    # 确定引用：优先本地分支，其次远程
    REF="$BRANCH"
    if ! git rev-parse --verify "$BRANCH" &>/dev/null; then
      REF="origin/$BRANCH"
    fi

    # 统计该分支当日提交数
    COMMIT_COUNT=$(git log "$REF" --since="$TODAY_DATE 00:00:00" --until="$TODAY_DATE 23:59:59" --oneline --no-merges 2>/dev/null | wc -l | tr -d ' ')

    if [ "$COMMIT_COUNT" -gt 0 ]; then
      REPO_HAS_COMMITS=true
      echo ""
      echo "--- 分支: $BRANCH ($COMMIT_COUNT 次提交) ---"

      # 详细提交记录：哈希、作者、时间、消息 + 文件变更统计
      git log "$REF" --since="$TODAY_DATE 00:00:00" --until="$TODAY_DATE 23:59:59" \
        --no-merges \
        --pretty=format:"%n提交: %h%n作者: %an%n时间: %ad%n消息: %s%n" \
        --date=iso-local --stat 2>/dev/null

      echo ""
    fi
  done

  if [ "$REPO_HAS_COMMITS" = false ]; then
    echo ""
    echo "[该仓库今日无提交记录]"
  fi

  echo ""
done
```

### 2.3 采集结果要求

采集完成后，你必须整理出以下数据结构（在内存中保持，用于后续生成日报内容）：

```
GIT_DATA = {
  total_repos_scanned: 3,          // 扫描仓库总数
  repos_with_commits: N,           // 有提交的仓库数
  total_branches_scanned: N,       // 扫描分支总数
  total_branches_with_commits: N,  // 有提交的分支数
  total_commits: N,                // 提交总数
  repos: [
    {
      name: "仓库名",
      path: "仓库路径",
      has_commits: true/false,
      branches: [
        {
          name: "分支名",
          commit_count: N,
          commits: [
            {
              hash: "短哈希",
              author: "作者",
              date: "时间",
              message: "提交消息",
              files_changed: ["文件路径1", "文件路径2", ...],
              insertions: N,
              deletions: N
            }
          ]
        }
      ]
    }
  ]
}
```

**校验点**: 如果 `total_repos_scanned` 不等于 `config.json` 中的仓库数量，必须报错并重新采集。

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

## 第四步：生成日报内容

### 内容生成强制规范

**禁止行为（违反任何一条即视为日报不合格）：**
- 禁止将多条提交合并为一句话描述
- 禁止省略任何仓库（即使无提交也要标注"今日无提交"）
- 禁止省略提交哈希、变更文件列表
- 禁止用"等"、"若干"、"部分"等模糊词代替具体列举
- 禁止"今日工作概览"少于 5 句话
- 禁止"关键成果"少于 3 条（有提交时）
- 禁止"明日计划"少于 3 条

**必须行为：**
- 每条提交必须独立成段，包含：仓库名、分支名、哈希、消息、变更文件、变更目的
- 每个仓库必须有独立的 heading 段落
- 无提交的仓库必须显式标注"今日无提交记录"
- 所有数字必须是实际采集到的真实数据

### 日报正文结构（按顺序生成以下章节）

#### 章节 1: 📋 今日工作概览

**要求: 5-8 句话**，必须覆盖以下内容：
- 今日日期
- 涉及哪些仓库（列出仓库名）
- 各仓库的主要工作方向
- 提交总数和活跃分支数
- 主要技术动作（如：功能开发、Bug 修复、重构、文档更新等）
- 整体工作节奏评价

**反面示例（禁止）**: "今日主要进行了代码优化和功能开发。"
**正面示例**: "2024-01-15，今日在 main_control、Legbots-App、LegBots-kanban 三个仓库中均有代码活动。main_control 仓库在 develop 分支进行了 5 次提交，主要集中在电机控制模块的 PID 算法优化；Legbots-App 在 feature/ble-connect 分支完成了蓝牙连接重构的 3 次提交；LegBots-kanban 在 main 分支更新了 2 处看板配置。今日累计 10 次提交，涉及 3 个活跃分支，整体开发节奏紧凑。"

#### 章节 2: 📊 仓库覆盖总表（强制）

**必须以表格形式展示全部配置仓库的扫描结果**：

| 仓库名 | 活跃分支数 | 提交总数 | 主要变更模块 | 状态 |
|--------|-----------|---------|-------------|------|
| main_control | X | X | 模块A, 模块B | 有提交/无提交 |
| Legbots-App | X | X | 模块C | 有提交/无提交 |
| LegBots-kanban | X | X | 模块D | 有提交/无提交 |

**表格下方补充一行统计**: "共扫描 X 个仓库、X 个分支，其中 X 个仓库有提交活动，累计 X 次提交。"

#### 章节 3: 🔧 逐仓库工作详情（按仓库分组）

**对每个仓库使用 heading_2 子标题**，仓库内按分支使用 heading_3 子标题。

结构示例：

```
## 🔧 逐仓库工作详情

### main_control

#### develop 分支 (3次提交)

- **提交 a1b2c3d**: 优化电机 PID 控制算法的积分项计算
  - 变更文件: `src/motor/pid_controller.c`, `src/motor/pid_controller.h`, `tests/test_pid.c`
  - 变更统计: +45 行, -12 行
  - 变更目的: 解决积分饱和导致的电机抖动问题，引入积分限幅机制
  
- **提交 d4e5f6a**: 更新电机参数配置表
  - 变更文件: `config/motor_params.json`
  - 变更统计: +8 行, -3 行
  - 变更目的: 根据实测数据调整 Kp、Ki、Kd 参数

- **提交 g7h8i9j**: 添加电机自检流程日志输出
  - 变更文件: `src/motor/self_test.c`, `src/utils/logger.c`
  - 变更统计: +22 行, -0 行
  - 变更目的: 便于生产环节排查电机自检失败问题

#### feature/sensor-fusion 分支 (1次提交)

- **提交 k0l1m2n**: 初始化传感器融合模块框架
  - 变更文件: `src/sensor/fusion.c`, `src/sensor/fusion.h`, `CMakeLists.txt`
  - 变更统计: +89 行, -0 行
  - 变更目的: 搭建多传感器数据融合的基础框架

### Legbots-App

[同样的详细格式]

### LegBots-kanban

[如无提交] 今日无提交记录。
```

**每条提交必须包含以下 4 项信息，缺一不可：**
1. 提交哈希和提交消息
2. 变更文件列表（完整路径）
3. 变更统计（增/删行数）
4. 变更目的（用一句话解释这次提交解决了什么问题或实现了什么功能）

#### 章节 4: ✅ 关键成果

**要求: 3-8 条**，每条必须包含具体的技术内容和业务价值：

- **成果标题**: 具体描述完成了什么、达到了什么效果、关联的仓库和分支
- 可包含的成果类型：功能完成、问题修复、性能优化、架构改进、脚本增强、流程打通、数据补齐、文档沉淀

**反面示例（禁止）**: "完成了代码优化"
**正面示例**: "**电机 PID 积分限幅机制上线**: 在 main_control/develop 分支实现了积分项限幅，解决了长时间运行后积分饱和导致的电机抖动问题，自检通过率从 92% 提升至 99%"

#### 章节 5: ⚠️ 问题与风险

- 遇到的问题或潜在风险描述，以及应对措施
- 必须关联具体的仓库、分支、模块
- 如确实无问题，写"今日工作顺利进行，暂无重大问题与风险"

#### 章节 6: 📅 明日计划

**要求: 3-5 条**，每条必须具体到仓库/模块级别：
- 从今日未完成的工作中提取
- 从 Git 提交中识别的后续工作
- 从活动记录的 Description 中提取下一步计划

**反面示例（禁止）**: "继续进行开发工作"
**正面示例**: "在 main_control/feature/sensor-fusion 分支完成 IMU 数据滤波算法的实现和单元测试"

#### 章节 7: 📊 今日数据统计

使用表格展示，数据必须与实际采集结果完全一致：

| 指标 | 数值 |
|------|------|
| 扫描仓库数 | X 个 |
| 有提交仓库数 | X 个 |
| 扫描分支总数 | X 个 |
| 有提交分支数 | X 个 |
| Git 提交总数 | X 次 |
| 变更文件总数 | X 个 |
| 活动记录数 | X 条 |
| 涉及工作领域 | X 个 |

### 提取日报属性数据

从生成的日报内容中提取以下属性（用于 Notion 数据库属性字段）：
- `workDomains`: 涉及的工作领域数组，如 `['固件开发', '应用开发', '看板管理']`，必须从实际工作内容中提取
- `workHours`: 工作时长文本，如 "8小时"，从活动记录时间跨度推算
- `summary`: 3-5 句话的工作摘要，直接复用"今日工作概览"章节的前 3 句

## 第五步：Markdown 转换为 Notion 原生块格式

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

## 第六步：写入 Notion 日报数据库

使用 Notion API 在日报数据库中创建新页面。

**API 调用：** `POST /pages`

```javascript
const notionBlocks = markdownToNotionBlocks(日报内容);

// 分批写入，每次最多 100 个 block
const batchSize = 100;
let pageId = null;

// 第一批：创建页面并写入前 100 个 block
const firstBatch = notionBlocks.slice(0, batchSize);
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
    },
    '工作领域': {
      multi_select: workDomains.map(domain => ({ name: domain }))
    },
    '工作时长': {
      rich_text: [{ text: { content: workHours } }]
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

## 第七步：验证写入结果

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

验证要求：

1. `result.results` 必须非空
2. 最新一条记录的标题、日期、摘要必须正确
3. 页面正文必须包含"仓库覆盖总表"
4. `config.json` 中的全部仓库名必须在正文中出现
5. 正文 block 数量不得少于 20 个（有提交时）

如果验证通过，输出：`[SUCCESS] 日报已成功写入 Notion`
如果验证失败，输出：`[FAILED] 日报写入失败，请检查仓库覆盖、Git 数据采集和 Notion 写入结果`

## 最终质量门槛

1. 不允许遗漏任何配置仓库 — 3 个仓库必须全部出现在"仓库覆盖总表"中
2. 不允许遗漏任何有提交的分支 — 每个有提交的分支必须有独立段落
3. 不允许遗漏任何提交 — 每条 commit 必须在"逐仓库工作详情"中独立展示
4. 不允许省略变更文件列表 — 每条提交必须列出所有变更文件路径
5. 不允许用空泛措辞替代具体工作内容 — 禁止"完成了若干优化"等表述
6. 不允许"已扫描但无提交"的仓库被静默跳过 — 必须显式标注"今日无提交记录"
7. 日报语言必须为中文
8. 结论必须客观、具体、可追溯
9. 数据统计表中的数字必须与 Git 采集结果完全一致
10. 如果今日所有仓库均无提交且无活动记录，仍需创建日报并在概览中标注"今日无工作记录"
