# DFMH-ChengJiaoGuan

## AI成交官｜成交转化系统

帮助企业洞察客户、设计成交策略并训练可复制的销售能力。

- 当前成熟度：`designing`
- 正式任务许可：`false`
- 使用边界：当前为设计/试运行版本，默认用于候选分析和内部验证，不代表已经获得正式对外发布权限。

## 三个核心技能

| 技能 | Skill ID | 主要输出 |
| --- | --- | --- |
| 客户洞察 | `customer-insight` | 客户画像、购买动机、成交阶段、核心顾虑 |
| 成交策略 | `deal-strategy` | 沟通策略、价值塑造、异议处理、成交路径 |
| 销售训练 | `sales-training` | AI模拟客户、销售陪练、销售评分、销冠经验复制 |

## 这个仓库能做什么

1. 接收企业、项目和任务资料，并严格保持项目隔离。
2. 按三个核心技能形成分析、方案、执行动作、验收指标和停止条件。
3. 区分已知事实、公开资料、推断和信息缺口，不用模拟数据冒充真实经营结果。
4. 通过版本化文件和本地门禁保留可复核的执行证据。

## 使用方法

1. 安装 Node.js 20 或更高版本。
2. 将任务资料放在仓库外的独立任务目录中，不要提交客户隐私、密钥或真实业务数据到公开仓库。
3. 先阅读根目录 `AGENTS.md`、`QUICKSTART.md`、`PUBLIC_PACKAGE_CONTRACT.json`，再读取 `organizations/ai-deal-officer/AGENTS.md` 和三个技能的 `SKILL.md`。
4. 执行 `npm test` 检查仓库结构、公开执行契约、本地依赖和敏感信息。

## 目录

- `organizations/ai-deal-officer/skills/`：三个核心技能。
- `organizations/ai-deal-officer/workflows/`：技能对应业务流程。
- `organizations/ai-deal-officer/scripts/`：确定性运行与校验组件。
- `organizations/ai-deal-officer/templates/`：候选、计划和交付模板。
- `control-center/registries/`：本组织的精简登记与输出目录。
- `shared/`：技能引用的公共只读标准。

## 控制中心边界

本仓库是可独立分发的单组织能力包，不包含飞书机器人凭据、客户资料、历史任务、临时文件或总控私有配置。它不等于完整AI数字员工控制中心，也不自动具备五组织编排、飞书调度、跨项目资产共享或私有知识库能力。公共海报和淘宝电商套图能力仍由外部控制中心按登记表调用，不在本仓库重复打包。

## 发布信息

- 生成时间：2026-08-04T07:09:17.420Z
- GitHub 仓库可见性：public
- 许可：保留所有权利，未经授权不得转售或公开再分发。
