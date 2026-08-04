---
name: taobao-ecommerce-image-set-pilot
description: Use when the user wants a Taobao product image set, main images, detail images, or a coordinated ecommerce image series.
---

# 淘宝套图设计技能（试运行版）

当前成熟度为 `pilot`。执行前必须阅读 `workflows/TAOBAO_ECOMMERCE_IMAGE_SET_PILOT.md`、`shared/IMAGE_GENERATION_CHANNEL_STANDARD.md` 与 `shared/PRODUCT_ASSET_FIDELITY_STANDARD.md`。

## 核心边界

1. 产品原图、可见视角、卖点证据和当前任务版本未绑定时，禁止进入生图。
2. 套图逐张生成、逐张审核，不以拼图或批量占位图冒充正式交付。
3. 当前仓库是可下载验证的试运行能力包，不声明已经达到正式生产成熟度。
4. 正式使用前执行 `npm test`，并按流程门禁完成需求、素材、候选和晋级检查。
