#!/usr/bin/env node
/**
 * 生成并发布指定周报到 Notion（读取 config.json 中的 API Key）
 */
import https from 'https';
import fs from 'fs';

const config = JSON.parse(
  fs.readFileSync(
    new URL('../config.json', import.meta.url),
    'utf8'
  )
);

const TOKEN = config.notion.api_key;
const WEEKLY_DB = config.notion.databases.weekly_report;

const WEEK_START = process.argv[2] || '2026-03-30';
const WEEK_END = process.argv[3] || '2026-04-05';
const WEEK_NUMBER = parseInt(process.argv[4] || '14', 10);
const WEEK_START_YEAR = '2026';
const WEEK_START_MMDD = '03/30';
const WEEK_END_MMDD = '04/05';

function notionRequest(path, method = 'GET', body = null) {
  return new Promise((resolve, reject) => {
    const options = {
      hostname: 'api.notion.com',
      path: `/v1${path}`,
      method,
      headers: {
        Authorization: `Bearer ${TOKEN}`,
        'Content-Type': 'application/json',
        'Notion-Version': '2022-06-28',
      },
    };
    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => (data += chunk));
      res.on('end', () => {
        try {
          const result = JSON.parse(data);
          if (result.error || result.code)
            reject(new Error(result.message || JSON.stringify(result)));
          else resolve(result);
        } catch (e) {
          reject(e);
        }
      });
    });
    req.on('error', reject);
    if (body) req.write(JSON.stringify(body));
    req.end();
  });
}

/** @param {string} text */
function splitRichTextChunks(text, max = 1900) {
  if (text.length <= max) return [text];
  const chunks = [];
  let i = 0;
  while (i < text.length) {
    chunks.push(text.slice(i, i + max));
    i += max;
  }
  return chunks;
}

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
            rich_text: [
              {
                type: 'text',
                text: { content: codeBlockContent.join('\n').slice(0, 1990) },
              },
            ],
          },
        });
      }
      continue;
    }
    if (inCodeBlock) {
      codeBlockContent.push(line);
      continue;
    }

    if (line.trim() === '') {
      continue;
    }

    if (line.startsWith('### ')) {
      blocks.push({
        object: 'block',
        type: 'heading_3',
        heading_3: {
          rich_text: [{ type: 'text', text: { content: line.slice(4).trim().slice(0, 1990) } }],
        },
      });
      continue;
    }
    if (line.startsWith('## ')) {
      blocks.push({
        object: 'block',
        type: 'heading_2',
        heading_2: {
          rich_text: [{ type: 'text', text: { content: line.slice(3).trim().slice(0, 1990) } }],
        },
      });
      continue;
    }
    if (line.startsWith('# ')) {
      blocks.push({
        object: 'block',
        type: 'heading_1',
        heading_1: {
          rich_text: [{ type: 'text', text: { content: line.slice(2).trim().slice(0, 1990) } }],
        },
      });
      continue;
    }

    if (line.startsWith('|') && line.includes('|')) {
      if (!inTable) {
        inTable = true;
        tableRows = [];
      }
      if (!line.includes('---')) {
        const cells = line.split('|').map((c) => c.trim()).filter((c) => c !== '');
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
              children: tableRows.map((row) => ({
                type: 'table_row',
                table_row: {
                  cells: row.map((cell) => [
                    { type: 'text', text: { content: String(cell).slice(0, 1990) } },
                  ]),
                },
              })),
            },
          });
        }
      }
      continue;
    }

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
              { type: 'text', text: { content: ': ' + boldMatch[2].slice(0, 1800) } },
            ],
          },
        });
      } else {
        for (const chunk of splitRichTextChunks(content)) {
          blocks.push({
            object: 'block',
            type: 'bulleted_list_item',
            bulleted_list_item: {
              rich_text: [{ type: 'text', text: { content: chunk } }],
            },
          });
        }
      }
      continue;
    }

    for (const chunk of splitRichTextChunks(line)) {
      blocks.push({
        object: 'block',
        type: 'paragraph',
        paragraph: {
          rich_text: [{ type: 'text', text: { content: chunk } }],
        },
      });
    }
  }

  return blocks;
}

const MARKDOWN = `# 📋 本周工作概览

本周为 2026 年第 ${WEEK_NUMBER} 个自然周，周期 ${WEEK_START_MMDD} 至 ${WEEK_END_MMDD}（周一至周日）。配置内三个仓库 main_control、Legbots-App、LegBots-kanban 均已扫描；其中 LegBots-kanban 为绝对主力，Legbots-App 本周无提交，main_control 在远端 origin/feature_mit_control 上存在 1 次与日报一致的固件侧修复提交（本地 feature_mit_control 指针未包含该提交时，以远端为准）。独立 Git 统计在 LegBots-kanban 的 develop 上共 37 条非合并提交（与 pad接口api、zhc 分支在本周窗口内提交哈希去重后完全一致，仅分支尖端不同）。日报侧本周共有 6 篇「已完成」日报（03/30–04/04），04/05（周日）无已完成日报记录；03/30–03/31 多为空档，自 04/01 起提交密度显著抬升。技术主线为云端优先架构落地、RBAC 与设备生命周期、维修/库存/质量分析桌面端闭环、uni-app 库存移动端与打印扫码链路等。全周 Git 变更约 +67831 / -122989 行（含大规模文档与助手目录清理导致的删除峰值），触及约 791 个不重复路径。整体节奏呈「前半周蓄力、中段架构与业务爆发、末段移动端与标签打印收尾」的形态。

# 📊 仓库覆盖总表

| 仓库名 | 活跃分支数 | 本周提交总数 | 提交天数 | 主要变更模块 | 状态 |
|--------|------------|--------------|----------|--------------|------|
| main_control | 1 | 1 | 1 天 | NVS/启动、电机与步态、语音、openspec 清理 | 有提交 |
| Legbots-App | 0 | 0 | 0 天 | — | 无提交 |
| LegBots-kanban | 3 | 37 | 5 天 | 云端后端与 Flyway、Electron 桌面、UniApp 库存移动、文档/BMAD | 有提交 |

说明：LegBots-kanban 的 develop、origin/pad接口api、origin/zhc 在本周时间窗内指向同一组 37 个提交对象（哈希去重后不再叠加计数）；下文在 develop 下完整列出提交明细，并在 pad接口api / zhc 小节标注「提交集合与 develop 一致」以避免重复粘贴。

# 🔧 逐仓库工作详情

## main_control

**活跃分支列表**：origin/feature_mit_control（本地 feature_mit_control 若未快进合并，请以远端为准）。

**日维度提交分布**：周五（04/03）1 次；其余日期 0 次。

**推进脉络**：本周仅在 04/03 于 feature_mit_control 线上出现一次与 NVS 宏及启动流程相关的修复与清理提交，属于「点状修复 + 大文件/过期 openspec 降噪」；至周末未观察到更多延续提交，遗留工作主要在实机回归与分支同步。

**提交明细**

### origin/feature_mit_control 分支（1 次提交）

- **提交 20f7bd4**（2026-04-03，ZhangHongChen）：fix: 修复NVS_CLEAR_VERSION宏逻辑错误并优化启动流程
  - 变更统计：17 个文件，+66 行，-3156 行（含删除大体积 sysmon.txt 与过期 openspec 文档树）
  - 技术要点：修正 NVS 清理相关宏、统一启动与调试路径，同步电机/步态/语音侧调用与头文件约束，降低误用风险。

## Legbots-App

**本周无提交记录**（对本地与 origin 可见分支在 2026-03-30 00:00–2026-04-05 23:59:59 窗口内无非合并提交）。

**推进脉络**：Git 维度静默；若产品侧有规划，建议下周确认是否在 develop 恢复节奏并与 kanban/固件接口对齐。

## LegBots-kanban

**活跃分支列表**：develop（本地）、origin/pad接口api、origin/zhc — 本周窗口内三者提交集合一致。

**日维度提交分布（develop，按作者时区日期）**：周二 03/31 共 7 次；周三 04/01 共 13 次；周四 04/02 共 4 次；周五 04/03 共 7 次；周六 04/04 共 6 次；周一 03/30 与周日 04/05 为 0 次。

**推进脉络**：周二至周三完成云端认证/用户/固件管理与 IPC 集成，并在一日内经历备份能力实现后又随架构决策移除备份域、启用 Flyway、清理本地 DB 与海量助手目录；周三晚集中交付 RBAC 与设备生命周期状态机。周四聚焦维修/库存/权限大改与无障碍与固件刷写前清理。周五强化设备读取链路、维修历史与质量分析、uni-app/蓝牙/小程序示例与大型设计稿。周六转向库存移动端（UniApp + Spring Boot）从骨架到仪表盘/个人中心/二维码标签与接口收敛。**未闭环**：多环境 Flyway 基线一致性、超大二进制与设计稿的仓库体积治理、移动端与桌面端权限模型长期对齐。

### develop 分支（37 次提交，按时间正序）

- **提交 0cc20bc** | 2026-03-31 | ZhangHongChen | feat: 添加前后端分离架构和本地开发环境配置 | 155 files, +3533 -2099
- **提交 69f4f26** | 2026-03-31 | ZhangHongChen | chore: 更新忽略规则并避免本地目录再次被跟踪 | 1 files, +5 -1
- **提交 8cf1099** | 2026-03-31 | ZhangHongChen | feat(cloud): 实现云端认证与用户管理功能 | 33 files, +1540 -673
- **提交 a6f159b** | 2026-03-31 | ZhangHongChen | feat(auth): 增加本地环境认证支持并优化脚本 | 14 files, +585 -189
- **提交 e80c3d5** | 2026-03-31 | ZhangHongChen | feat(用户管理): 切换到云端用户管理并添加创建时间字段 | 2 files, +60 -46
- **提交 ac4074a** | 2026-03-31 | ZhangHongChen | feat(firmware): 实现云端固件管理功能 | 11 files, +1377 -308
- **提交 bbbc481** | 2026-03-31 | ZhangHongChen | feat: 集成云端后端服务并重构前端IPC处理逻辑 | 21 files, +3249 -1393
- **提交 fa7c5e8** | 2026-04-01 | ZhangHongChen | feat(quality-analysis): 新增质量分析模块并优化设备状态转换 | 14 files, +518 -134
- **提交 3271f38** | 2026-04-01 | ZhangHongChen | feat(backup): 实现云端备份与恢复功能 | 10 files, +1232 -266
- **提交 05f0201** | 2026-04-01 | ZhangHongChen | feat: 添加固件文件上传大小限制及错误处理 | 8 files, +37 -1
- **提交 d6e9819** | 2026-04-01 | ZhangHongChen | fix: 修复JDBC插入语句返回生成主键的方式 | 4 files, +4 -8
- **提交 d9ceb50** | 2026-04-01 | ZhangHongChen | refactor(backend): 移除备份功能并清理相关代码 | 32 files, +1622 -6182
- **提交 ba262d6** | 2026-04-01 | ZhangHongChen | feat: 为业务表添加设备序列号和MAC地址快照字段 | 7 files, +739 -121
- **提交 fdae40b** | 2026-04-01 | ZhangHongChen | refactor(db): 移除备份表和迁移脚本，启用Flyway并调整设备删除逻辑 | 6 files, +8 -488
- **提交 69febd5** | 2026-04-01 | ZhangHongChen | chore: stop tracking local assistant folders | 353 files, +382 -70951
- **提交 2e3e854** | 2026-04-01 | ZhangHongChen | docs: 更新项目文档以反映云端优先架构 | 13 files, +1002 -966
- **提交 872efcf** | 2026-04-01 | ZhangHongChen | refactor(frontend): 移除本地数据库遗留代码并清理相关文件 | 49 files, +124 -6765
- **提交 492d50c** | 2026-04-01 | ZhangHongChen | docs: 更新文档以反映前端业务链路强制收敛到云端 | 9 files, +94 -27
- **提交 62831fa** | 2026-04-01 | ZhangHongChen | docs: 添加历史功能基线文档并清理旧规划文件 | 79 files, +344 -22680
- **提交 3347e8a** | 2026-04-01 | ZhangHongChen | feat: 实现角色权限系统与设备生命周期状态机 | 67 files, +1875 -1714
- **提交 441dc53** | 2026-04-02 | ZhangHongChen | feat: 实现维修流程、库存管理和权限控制 | 45 files, +3372 -5766
- **提交 19e19f9** | 2026-04-02 | ZhangHongChen | feat(frontend): 增加无障碍标签并汉化界面文本 | 6 files, +106 -83
- **提交 7dd26d6** | 2026-04-02 | ZhangHongChen | feat: 添加固件刷写前的设备历史清理逻辑 | 14 files, +234 -334
- **提交 82ef8e3** | 2026-04-02 | ZhangHongChen | feat: 添加设备历史治理、错误日志和维修记录删除功能 | 28 files, +1932 -993
- **提交 422717f** | 2026-04-03 | ZhangHongChen | feat(device): 增强设备读取稳定性和状态管理 | 7 files, +1541 -292
- **提交 e83e8ae** | 2026-04-03 | ZhangHongChen | feat(设备重刷): 增加按MAC地址清除已刷写设备档案的功能 | 7 files, +201 -10
- **提交 333b40a** | 2026-04-03 | ZhangHongChen | feat(设备): 添加刷新设备登记信息功能 | 6 files, +142 -2
- **提交 e02b32b** | 2026-04-03 | ZhangHongChen | feat: 新增维修历史页面并扩展质量分析统计 | 13 files, +1164 -5
- **提交 dfac672** | 2026-04-03 | ZhangHongChen | chore: 更新BMAD配置时间戳并添加前端Java SDK文档及示例 | 9 files, +617 -8
- **提交 16b7aad** | 2026-04-03 | ZhangHongChen | feat: 新增蓝牙设备管理和搜索页面功能 | 8 files, +7916 insertions
- **提交 e4527d4** | 2026-04-03 | ZhangHongChen | feat: 更新登录页面设计并新增uni-app文件 | 2 files, +7780 -1
- **提交 e57ccbe** | 2026-04-04 | ZhangHongChen | feat: 更新库存管理移动端项目结构与功能 | 48 files, +15735 -356
- **提交 87b8a07** | 2026-04-04 | ZhangHongChen | feat: 新增项目上下文文档与移动端功能模块 | 43 files, +6929 -10
- **提交 1540043** | 2026-04-04 | 鸿尘客 | feat: 完成数据展示与个人中心功能模块 | 33 files, +1697 -61
- **提交 a23cb7a** | 2026-04-04 | 鸿尘客 | refactor: 更新个人中心页面逻辑 | 1 files, +5 -2
- **提交 14a8097** | 2026-04-04 | 鸿尘客 | feat: 更新打印功能以支持二维码标签 | 14 files, +288 -28
- **提交 7624a33** | 2026-04-04 | 鸿尘客 | refactor: 移除设备查询接口并优化库存管理逻辑 | 4 files, +141 -27

### pad接口api / zhc 分支

与 develop 本周提交哈希集合完全一致；若需代码审阅，请直接对照上文 develop 下列出的 37 个哈希。

# ✅ 关键成果

- **云端优先架构在 LegBots-kanban 落地**：通过移除备份域、清理本地 SQLite 路径、Flyway 接管迁移与文档对齐，桌面端业务读写统一走云端 API（对应 d9ceb50、872efcf、2e3e854 等多提交协同）。
- **RBAC 与设备生命周期状态机**：3347e8a 一次性引入权限枚举、管理员覆写审计与生命周期规则，并与前后端页面权限路由联动。
- **维修—库存—质量分析业务链**：441dc53、82ef8e3、e02b32b 等提交贯通维修流程、库存域、质量分析与设备历史治理。
- **库存管理移动端从 0 到可用**：e57ccbe、87b8a07、1540043、14a8097、7624a33 等完成 UniApp 工程、出入库与蓝牙/打印/扫码适配、仪表盘与个人中心、二维码标签解析与接口收敛。
- **main_control 固件侧关键修复**：20f7bd4 修正 NVS_CLEAR_VERSION 与启动分支逻辑并清理大文件/openspec，降低版本切换风险。
- **多端资产与示例沉淀**：16b7aad、dfac672、e4527d4 等引入大规模 uni-app 设计稿、蓝牙/小程序示例与 Java 打印 SDK 文档，缩短后续联调周期。

# ⚠️ 问题与风险

- **备份功能反复**：04/01 先 3271f38 增加云端备份，随后 d9ceb50 整体移除备份域，架构决策在短时间内反转，后续需加强评审与里程碑冻结。
- **超大规模删除与二进制入库**：69febd5、62831fa 等单次删除上万行；16b7aad、e4527d4 等引入超大 .pen 与二进制，仓库体积与 CI 检出成本上升，建议评估 Git LFS 与制品库分流。
- **Flyway 脚本版本与多环境基线**：多轮迁移文件增删与重排，需要在干净库与存量库上双重验证，避免部署环境冲突。
- **本地分支落后于远端**：main_control 的示例表明仅扫描本地分支可能漏提交，自动化采集应合并 origin/* 或显式 git fetch 后比对。
- **Notion 活动日志为 0**：与日报属性一致，过程留痕不足，存在工时与会议交叉验证缺口。

# 📅 下周计划

- **LegBots-kanban/develop**：补齐权限与生命周期相关单测/集成测试；对 Flyway 在空库与生产克隆库上做一次完整迁移演练；评估将超大设计稿与二进制迁出主仓库。
- **LegBots-kanban/移动端**：完成库存移动端与后端联调清单（登录会话、出入库异常态、扫码/打印失败重试）；收敛无用设备查询接口后的监控与告警。
- **main_control/feature_mit_control**：将本地分支与 origin 对齐并完成 NVS/步态/语音相关实机回归用例。
- **Legbots-App**：确认下一迭代是否恢复 develop 提交节奏，并与 kanban 公共 API 变更对齐。
- **流程**：恢复或补录 Activity Logs / 日历类留痕，便于周报与审计对齐。

# 📊 本周数据统计

| 指标 | 数值 |
|------|------|
| 工作天数（已完成日报篇数） | 6 天 |
| 扫描仓库数 | 3 个 |
| 有提交仓库数 | 2 个 |
| 活跃分支总数 | 4 个（main_control: feature_mit_control；kanban: develop/pad接口api/zhc 计 3） |
| Git 提交总数（跨仓库去重合计） | 38 次 |
| 变更文件总数（kanban develop 不重复路径约） | 791 个 |
| 活动记录总数（Notion 日报属性汇总） | 0 条 |
| 涉及工作领域（周报属性枚举） | 8 个 |
`;

const workDomains = [
  '固件开发',
  'Web开发',
  '软件开发',
  '设备管理',
  '文档编写',
  '系统优化',
  '项目管理',
  '调试测试',
];

const summary = `2026年第${WEEK_NUMBER}周（${WEEK_START_MMDD}-${WEEK_END_MMDD}）以 LegBots-kanban 为主战场完成云端优先架构、RBAC、维修/库存/质量分析与 UniApp 库存移动端等高密度交付；main_control 在 origin/feature_mit_control 完成 1 次 NVS/启动相关修复；Legbots-App 无提交。全周 Git 约 38 次提交、日报 6 篇已完成。`;

async function main() {
  const dup = await notionRequest(`/databases/${WEEKLY_DB}/query`, 'POST', {
    filter: {
      and: [
        { property: '周期', date: { on_or_after: WEEK_START } },
        { property: '周期', date: { on_or_before: WEEK_END } },
      ],
    },
    page_size: 5,
  });

  if (dup.results?.length) {
    const t = dup.results[0].properties?.['周报标题']?.title?.[0]?.plain_text;
    console.log('[SKIP] 该周期已存在周报:', t || dup.results[0].id);
    process.exit(0);
  }

  const notionBlocks = markdownToNotionBlocks(MARKDOWN);
  console.log('[INFO] block count:', notionBlocks.length);

  const batchSize = 100;
  const firstBatch = notionBlocks.slice(0, batchSize);

  const pageBody = {
    parent: { database_id: WEEKLY_DB },
    properties: {
      周报标题: {
        title: [
          {
            text: {
              content: `${WEEK_START_YEAR}年第${WEEK_NUMBER}周工作周报 (${WEEK_START_MMDD} - ${WEEK_END_MMDD})`,
            },
          },
        ],
      },
      周期: {
        date: { start: WEEK_START, end: WEEK_END },
      },
      状态: {
        status: { name: '已完成' },
      },
      总活动记录数: { number: 0 },
      工作领域: {
        multi_select: workDomains.map((name) => ({ name })),
      },
      涉及领域数: { number: workDomains.length },
      工作日天数: { number: 6 },
      摘要: {
        rich_text: [{ text: { content: summary.slice(0, 1990) } }],
      },
    },
    children: firstBatch,
  };

  const result = await notionRequest('/pages', 'POST', pageBody);
  const pageId = result.id;
  console.log('[INFO] page id:', pageId);

  for (let i = batchSize; i < notionBlocks.length; i += batchSize) {
    const batch = notionBlocks.slice(i, i + batchSize);
    await notionRequest(`/blocks/${pageId}/children`, 'PATCH', { children: batch });
  }

  const verify = await notionRequest(`/databases/${WEEKLY_DB}/query`, 'POST', {
    filter: {
      and: [
        { property: '周期', date: { on_or_after: WEEK_START } },
        { property: '周期', date: { on_or_before: WEEK_END } },
      ],
    },
    page_size: 5,
  });

  if (!verify.results?.length) {
    console.log('[FAILED] 周报写入失败，请检查仓库覆盖、Git 数据采集和 Notion 写入结果');
    process.exit(1);
  }

  const children = await notionRequest(`/blocks/${pageId}/children`, 'GET');
  const n = (children.results || []).length;
  console.log('[INFO] first page children count:', n);
  console.log('[SUCCESS] 周报已成功写入 Notion');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
