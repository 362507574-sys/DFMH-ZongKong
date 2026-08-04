# AI组织官工作流程

## 通用闭环

识别企业、任务和权限 → 飞书知识前置 → 读取企业档案 → 区分战略、组织、岗位、资源、管理、流程与个人问题 → 路由人才配置、人才培养或流程复制 → 形成候选 → 事实、隐私、公平、劳动合规和一致性审核 → 使用者决定 → 小范围试运行 → 非覆盖晋级 → 复盘。

## 三技能正式链路

1. 人才配置执行`workflows/TALENT_ALLOCATION_PILOT.md`（保留首轮实践兼容文件名），输出批准后的岗位与人才正式资产。
2. 人才培养执行`workflows/TALENT_DEVELOPMENT_PILOT.md`（保留首轮实践兼容文件名），固定绑定人才配置的精确版本和SHA-256。
3. 流程复制执行`workflows/PROCESS_REPLICATION_PILOT.md`，固定绑定人才配置与人才培养两个正式资产，输出SOP、知识库、工资考勤与组织复制体系。

三技能链路已完成验证；根控制中心已开启正式接单，运行时仍以控制中心注册表和精确Skill绑定为准。

## 状态

`received → identifying_context → knowledge_preflight → diagnosing → candidate_building → quality_review → waiting_decision → pilot_running/approved → archived_formal → health_review_due`。

`waiting_input`、`waiting_collaboration`、`collaboration_received`和`revising`按实际情况进入；`cancelled`和`failed`为终态。禁止跳过使用者决策和正式晋级门禁。

## V2统一运行闭环

`planning → evidence → executing → validating → debugging/ waiting_decision → formalizing → completed`。`waiting_input`、`waiting_collaboration`、`blocked`、`failed`、`cancelled`和`archived`按真实状态进入。

调试固定执行保存现场、根因、影响、最小修复、重新验收和关联回归；同一根因最多三轮。恢复必须核对企业、项目、任务、版本和副作用安全。下游变更通过总控重新调用上游Skill。
