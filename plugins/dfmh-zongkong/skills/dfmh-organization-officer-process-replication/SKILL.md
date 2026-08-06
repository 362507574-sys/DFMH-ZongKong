---
name: dfmh-organization-officer-process-replication
description: Use when the task requires AI组织官 流程复制 in the DFMH control center.
---

# AI组织官｜流程复制

执行前必须完整读取 `${CODEX_HOME}/dfmh-zongkong/capabilities/zd/organizations/ai-organization-officer/skills/process-replication/SKILL.md`，并按其中的输入、步骤、质量门禁、重试和停止条件执行。总控只负责路由与隔离，不得降低原能力的业务验收标准。

## 使用入口

1. 若总控尚未初始化，先调用 `dfmh-zongkong-bootstrap`，取得 `status=installed` 的真实回执。
2. 正式项目使用“项目：项目名称＋希望得到的结果”发起；普通问答不要新建项目。
3. 安装成功只代表能力入口可读取，不会提升原组织登记的成熟度或正式任务许可。
