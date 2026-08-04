# 控制中心交接

本目录保存登记候选、激活状态和验证证据；根级登记只由控制中心维护。

## 当前状态

- 组织：`ai-organization-officer`
- 本地成熟度：`operational-v2`
- 根级状态：`operational`
- 人才配置：`formal`
- 人才培养：`formal`
- 流程复制：`formal`
- 正式任务：`organization`
- 同级组织调用：`contract_only`

## 根级激活凭证

1. 组织专项测试和自检通过；
2. 控制中心兼容回归通过；
3. 三个正式Skill、三个正式资产和三技能链路清单哈希一致；
4. 根控制中心已把三项运行映射全部标记为`available`；
5. 根注册表已开启`acceptsFormalTasks=true`并由路由测试验证`organization`执行模式。

普通宣传海报和淘宝电商套图仍为根级公共能力，不进入本组织三个核心技能。

## 项目隔离舱边界

本次既有组织建设资产保留在`organizations/ai-organization-officer/`，不自动迁移。新建正式业务项目使用`business-projects/<enterpriseId>/<businessProjectId>/`隔离舱。需要使用掌舵官、增长战略官、成交官或品牌官成果时，只读取控制中心写入任务上下文的精确版本和SHA-256；禁止扫描其他组织目录或其他项目。

候选通过组织门禁后，只能由控制中心发布到当前项目 `shared-artifacts/`。AI组织官不得直接写共享成果区、覆盖历史版本或把其他项目的近似资料当作当前项目事实。

## V2正式接入

- 调用契约：`contracts/organization-invocation-v2.schema.json`
- 运行入口：`scripts/organization_v2_runtime.mjs`
- 回传契约：`contracts/return-package-v2.schema.json`
- 当前组织链：`enterprises/ai-digital-employee-control-center/assets/organization-chain/versions/2.json`

V2已由控制中心完成根注册、正式任务路由和`operational`激活。后续升级仍须由控制中心更新根级状态，组织侧只提交版本化变更与验证证据。
