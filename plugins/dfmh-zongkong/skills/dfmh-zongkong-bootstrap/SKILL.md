---
name: dfmh-zongkong-bootstrap
description: Install, initialize, update, diagnose, or safely remove the DFMH control center after the plugin is added.
---

# DFMH总控初始化

读取插件根目录的 QUICKSTART 与配置示例。自动检查环境、创建本机运行目录、生成空白配置、运行自检并保存可回滚状态。不得把示例占位符视为真实凭据；飞书没有配置时保持关闭并继续提供本地能力。

## 初始化动作

1. 定位当前插件根目录，执行其 `scripts/bootstrap.mjs`；不要要求用户手工创建目录。
2. 只有脚本返回 `status=installed`，且本机状态记录显示7个能力包已解压，才宣布初始化成功。
3. 成功后列出：5个组织、15个组织技能、2个公共技能；同时逐项保留原组织成熟度和正式任务许可。
4. 飞书未配置时返回 `feishu=not_configured`，本地控制中心继续可用，不得索要发布者的凭据。
