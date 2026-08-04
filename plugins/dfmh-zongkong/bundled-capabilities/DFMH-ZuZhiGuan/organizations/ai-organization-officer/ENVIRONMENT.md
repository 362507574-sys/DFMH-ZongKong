# AI组织官运行环境

- Node.js 24 ESM与`node:test`。
- Windows PowerShell 5.1。
- 原子JSON写入复用根级`scripts/feishu-commander/atomic_store.mjs`。
- 飞书只读知识检索复用根级`scripts/run_feishu_knowledge_preflight.mjs`。
- 本组织没有独立外部服务、账号、密钥或付费依赖。

一键自检：`node organizations/ai-organization-officer/scripts/organization_self_check.mjs`。
