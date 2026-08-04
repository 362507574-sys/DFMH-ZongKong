# 淘宝电商套图试运行工作流

本流程同时遵守 `shared/IMAGE_GENERATION_CHANNEL_STANDARD.md` 与 `shared/PRODUCT_ASSET_FIDELITY_STANDARD.md`。淘宝专属结构指纹、逐图绑定和整套验收是在公共底线上的业务增强，不得把单一通道拒绝扩大为全局禁令，也不得降低产品原貌一致性要求。

## 一、定位与边界

本工作流用于淘宝首图组（首页图）、淘宝详情页图以及同时包含二者的完整电商套图。当前属于试运行链路，主流程线程负责定型，测试线程负责小范围验证；正式生产线程只能在本链路升级为正式 Skill 后调用。

普通宣传海报转入 `skills/creating-promotional-posters/SKILL.md`，不得使用本工作流替代普通宣传海报链路，也不得使用普通宣传海报 Skill 替代淘宝电商套图链路。

所有候选素材、提示词、图片、版本和验收证据只能保存在 `temp/taobao-jobs/<job-id>/`。未经用户明确验收，任何候选图片不得进入 `outputs/`。任何付费、对外发布、账号权限变更或未授权第三方素材上传均须先获得用户确认。

## 二、强制执行顺序

以下步骤必须严格依次执行，任一门禁未通过即停止，不得跳步：

### 1. 任务分流

1. 将需求确认成以下一种：普通产品宣传海报、淘宝首图组（首页图）、淘宝详情页图、完整淘宝电商套图。
2. 需求只写“产品图”“淘宝图”或“电商图”时，必须先确认范围。
3. 范围未确认时，任务保持 `intake_pending`，不得进入后续步骤。

### 2. 素材归档

1. 在任务目录保存产品原图、参考素材、正式资料和授权记录，并记录文件名、字节数及 SHA-256。
2. 私人素材须取得针对 ChatGPT 网页的明确上传授权。
3. 默认使用 QQ 浏览器中的 ChatGPT 网页，通过“文件本体复制粘贴”上传；禁止向网页输入本地路径文字，不把原生文件选择窗口作为默认方式。
4. 上传前核对授权、文件及哈希，上传后核对正确素材缩略图；任何一项无法确认时停止。
5. 为每个产品建立独立的产品结构指纹：逐项记录不可变部件、部件数量、连接拓扑、相对几何关系、可见视角边界、允许变化和禁止变化；记录文件保存在任务目录并写入 `promptSet.structureLock`。
6. 可见视角边界只覆盖原图真实展示的角度及其局部裁切。完整正面、完整背面、后上方俯视、底盘等原图不可见角度，必须补充对应产品图后才能使用；不可见结构不得自由补全，也不得用同类产品常见结构代替。
7. 素材、授权、哈希和产品结构指纹完整后，状态才可进入 `assets_archived`。

### 2.1 品类分支绑定

1. 素材归档后必须先绑定 `category.id`、`category.subtype`、`category.profileVersion`、`category.profilePath` 与 `category.profileSha256`，再进入卖点与页面规划。
2. 公共主干负责证据、产品真实性、生成通道、批量调度和最终验收；品类配置负责卖点优先级、推荐视角、结构检查、镜头家族、证明方式、禁用版式与页面节奏。
3. 婴儿车固定使用 `templates/taobao-category-profiles/stroller-v1.json`，状态为 `frozen`；保留已验证的婴儿车卖点、机械关系、轮径比例和提示词链路，只继承公共安全、批量执行和整套验收升级。
4. 鞋类使用 `templates/taobao-category-profiles/shoes-v1.json`，状态为 `pilot`；先按鞋类子类型路由，再把购买结果、性能、结构证明、穿着场景和外观差异排序。
5. 服装使用 `templates/taobao-category-profiles/apparel-v1.json`，状态为 `pilot`；按连衣裙、上衣、下装、外套、套装、男装、针织和中性休闲子类型路由，优先完整穿着廓形、证据支持的面料与垂坠、结构细节、穿搭场景和外观差异。
6. 服装任务必须建立服装身份锁，固定款式、领口、肩袖、门襟、口袋、腰线、长度、下摆、印花、Logo和可见纹理；默认成年模特和自然人体比例。没有资料时禁止把“显瘦、遮肉、舒适、透气、亲肤、不透、抗皱、不起球、不缩水、成分、尺码包容”写成产品事实。
7. 配置文件必须位于 `templates/taobao-category-profiles/`，文件哈希、配置编号和版本必须与任务清单完全一致。配置缺失、哈希漂移、子类型不支持或 `category.confirmed=false` 时停止。

### 3. 卖点提炼

1. 只从产品图片可见事实、用户明确提供的事实或正式产品资料中提炼卖点；证据类型只能是 `image_visible`、`user_confirmed` 或 `document_proven`。
2. 先按购买价值分层，再决定顺序和数量：`core_purchase_driver` 为核心效果、功能、使用结果或主要痛点；`supporting_benefit` 为支撑核心利益的材质、结构、机制、舒适性、便利性或场景；`appearance_differentiator` 为配色、造型、纹理和装饰等外观差异。
3. 卖点排序固定为：买家痛点与使用结果 → 核心功能或性能 → 支撑机制、材质与场景 → 外观差异。用户或正式资料已确认的核心购买驱动不得因图片不可见而遗漏。
4. 相近核心卖点可以合并为更强主题，但必须保留原始含义和覆盖关系；相近外观细节必须合并。非外观主导类目通常最多保留 1–2 个外观项，不得拆分外观凑足数量。
5. 首饰、服饰、家居装饰等审美本身是主要购买理由的类目，可以记录 `appearance_led_exception=true` 后提高外观项占比；购买角色仍使用 `appearance_differentiator`。
6. 每项卖点必须填写购买角色、短标题、买家利益、简洁文案、诚实可视化证明方式、宣称边界、证据类型、证据来源、首图组适用性、详情页适用性和已核实状态。
7. 用户确认的一般性能和使用感受可作为 `user_confirmed`；精确数值、认证、检测结论和成分不得自行补写。主观绝对话术在 `claimBoundary` 中记录安全表达边界。
8. 以 5–8 个具有购买价值的卖点为目标。已验证核心项超过 8 个时先语义合并；无法合理合并时全部保留并交由用户定优先级，不得用外观项替换。
9. 如果只有图片且类目的主要功能、性能或使用结果没有证据，即使可见外观事实达到 5 项，也只能输出可见事实和待确认核心卖点，暂停最终确认和提示词生成。
10. `sellingPoints.items` 只保存已验证项，禁止用 `unsupported` 项凑数；参考图、竞品图和行业案例只能用于视觉启发，不得作为本产品事实证据。
11. 具有购买价值的已验证卖点不足 5 项时，只输出已验证项和独立证据缺口，暂停最终确认和提示词生成；只有用户明确批准少于5项的例外，才可继续。
12. 卖点草案写入 `sellingPoints.items`，状态进入 `selling_points_draft`。

`sellingPoints.items` 每个 item 的固定字段如下：

| 字段 | 含义 |
| --- | --- |
| `id` | 卖点编号，如 `S01` |
| `purchaseRole` | `core_purchase_driver`、`supporting_benefit` 或 `appearance_differentiator` |
| `shortTitle` | 适合上图的短标题 |
| `buyerBenefit` | 对买家的直接购买价值 |
| `copy` | 简洁卖点文案 |
| `visualProof` | 后续图片可诚实展示的证明方式 |
| `claimBoundary` | 禁止越过的宣称边界 |
| `evidenceType` | 证据类型 |
| `evidenceReference` | 可追踪的证据来源 |
| `homeEligible` | 是否适合淘宝首图组（首页图） |
| `detailEligible` | 是否适合详情页 |
| `verified` | 证据是否已核实 |

### 4. 用户确认卖点

1. 向用户提交完整编号卖点清单及证据来源。
2. 用户补充或修改后，只调整相关项目，再重新提交完整清单。
3. 只有卖点达到目标下限，或已记录用户批准少于 5 项例外的原话和时间，才可将 `sellingPoints.confirmed` 设为 `true` 并进入 `selling_points_confirmed`。
4. 未确认卖点时禁止规划任何图片提示词。

### 5. 四平台市场对标与专业风格决策

1. 卖点确认后、生成首图与详情页提示词前，必须完成同类产品视觉对标。固定平台为淘宝/天猫、Amazon、小红书、得物，每个平台至少记录 2 个有效参考，整套不少于 8 个。
2. 对标优先选择相同品类、相近使用场景、相近价格带和相近目标人群；无法满足时必须在观察记录中说明差异，禁止拿不相干品类的流行画面直接套用。
3. 每个 `marketBenchmark.references` 必须记录 `id`、`platform`、`url`、`capturedAt`、`evidencePath`、`observation`。公开链接只用于证明看过什么，关键构图、信息密度、证明方式和视觉节奏必须写入本地证据文件，避免链接失效后无法复核。
4. 市场参考只提供视觉语言、类目习惯和页面节奏，不得作为本产品功能、数值、材质或认证证据。
5. 执行助手以品牌设计师身份给出一个明确的 `marketBenchmark.styleDecision`，不把“高级、科技、运动”等空泛词直接交给生图。固定字段为 `name`、`rationale`、`platformBlend`、`visualPrinciples`、`forbiddenPatterns`、`detailProofStrategy`。
6. 风格决策必须明确禁止 `isolated_floating_detail_box` 与 `consecutive_same_detail_module`：详情证明元素不得作为与产品、场景和版式脱节的裸框悬浮；相邻页面不得重复相同细节框、相同构图家族或相同下半屏模板。
7. 对标报告保存在任务 `benchmark/` 目录，路径写入 `marketBenchmark.reportPath`；完成时间、产品类目、8 个以上参考和风格决策全部有效后，才可将 `marketBenchmark.completed` 设为 `true` 并进入 `benchmark_completed`。

`marketBenchmark.references` 每个 item 的固定字段如下：

| 字段 | 含义 |
| --- | --- |
| `id` | 参考编号，如 `B01` |
| `platform` | `taobao_tmall`、`amazon`、`xiaohongshu` 或 `dewu` |
| `url` | 可复核的公开来源链接 |
| `capturedAt` | 带时区的查看时间 |
| `evidencePath` | 任务内本地观察记录 |
| `observation` | 与本产品套图有关的具体视觉结论 |

### 6. 首图与详情页提示词

1. 淘宝首图提示词生成必须逐字使用 `templates/TAOBAO_HOME_IMAGE_PROMPT.md`，固定版本为 `emperor-fixed-v1`；该文件是用户批准的唯一原文，不得改写、删减、扩展或替换，也不得把执行说明、结构锁、验收规则追加到这段提示词中。
2. 每次使用前必须核对 `templates/TAOBAO_HOME_IMAGE_PROMPT.lock.json` 的版本与规范化 UTF-8 SHA-256；任一不一致立即停止。产品真实性、结构一致性和安全要求继续由外围任务记录、逐图参考绑定及验收门禁执行，不能借此修改固定原文。
3. 淘宝详情页提示词生成必须逐字使用 `templates/TAOBAO_DETAIL_IMAGE_PROMPT.md`，固定版本为 `emperor-fixed-detail-v1`；该文件是用户批准的唯一原文，不得改写、删减、扩展或替换，也不得把执行说明、结构锁、验收规则追加到这段提示词中。
4. 每次使用前必须核对 `templates/TAOBAO_DETAIL_IMAGE_PROMPT.lock.json` 的版本与规范化 UTF-8 SHA-256；任一不一致立即停止。详情页四层完整性、内容密度、产品真实性和安全要求继续由外围任务记录、逐图参考绑定及验收门禁执行，不能借此修改固定原文。
5. 每张图同时保存设计卡片与可直接提交的纯净生图提示词；二者使用相同编号和版本。
6. 卖点编号使用 `S` 加两位序号，首图编号使用 `H` 加两位序号，详情页编号使用 `D` 加两位序号，版本使用 `V1` 起。
7. 将统一配色、字体气质、信息层级、摄影质感、光线语言、产品结构、颜色、材质、比例、配件、品牌及禁用内容写入 `promptSet.styleLock`；同时写入 `benchmarkReportPath`、`styleDirection`、`proofIntegrationRules` 与 `forbiddenLayouts`，并与已完成的市场对标结论完全绑定。
8. 将原产品图编号、路径、SHA-256、结构指纹文件、不可变部件、连接拓扑、相对几何、可见视角边界、允许变化和禁止变化写入 `promptSet.structureLock`；未确认结构锁时禁止生图。
9. 每张设计卡和纯净提示词必须继承产品结构指纹与可见视角边界。构图变化只能来自背景、光线、排版、裁切和原图可见区域的独立放大；要求越出可见视角边界时，应改成同视角裁切或等待补图，不得猜测隐藏结构。
10. 每个涉及机械运动的卖点必须记录运动起点、终点、转轴和方向，确保机械关系可判读；每个产品必须从原图记录轮径、轴距、主体高度、部件大小和连接位置等相对比例基准。强视觉不得以结构变形或透视失真为代价。
11. 详情页以 8–12 屏为目标；每屏必须同时写明 `productSubjectLayer`、`useScenarioLayer`、`sellingPointProofLayer`、`textInformationLayer`、`verticalDensityPlan`、`meaningfulContentCoveragePercent` 和 `maxContinuousEmptyHeightPercent`。有效内容覆盖目标为75%–90%，连续空白高度不得超过画布15%；不得只写产品、标题和背景。
12. 每张提示词必须声明 `compositionFamily`、`proofPresentation` 与 `proofAddsNewInformation`。证明方式只能使用 `product_led`、`scene_integrated`、`full_bleed_macro`、`overlap_callout`、`split_story`、`comparison`、`framed_anchored`；禁止孤立裸框。相邻详情页不得重复同一 `compositionFamily`，`framed_anchored` 全套最多 2 屏且不得连续。
13. 证据不足 8 屏时只输出可证明的屏幕方案和证据缺口，暂停整套提示词确认，等待补充资料；只有用户明确批准少于8屏的例外，才可继续。证据不足只能改变证明方式，不得以删除产品主体、使用场景、卖点证明或文字信息层来制造空洞页面。
14. 提示词项目写入 `promptSet.items`，状态进入 `prompts_draft`。
15. 鞋类任务在逐字执行用户固定首页图与详情页提示词框架后，必须再使用 `templates/TAOBAO_SHOES_PAGE_PLANNER_PROMPT.md` 将通用结果整理成鞋类设计卡，并用 `templates/TAOBAO_SHOES_IMAGE_PROMPT.md` 约束单图生图、证明融合、产品真实性和局部返修；这两个适配器不得修改或替代两份用户固定原文。
16. 服装任务在逐字执行用户固定首页图与详情页提示词框架后，必须再使用 `templates/TAOBAO_APPAREL_PAGE_PLANNER_PROMPT.md` 将通用结果整理成服装设计卡，并用 `templates/TAOBAO_APPAREL_IMAGE_PROMPT.md` 约束服装身份、人体自然、穿着关系、宣称证据、镜头家族、细节整合和局部返修；这两个适配器不得修改或替代两份用户固定原文。
17. 服装详情页默认按“全身廓形主视觉—卖点总览—正面结构—细节—版型—面料—场景穿搭—总结”组织；可按真实证据扩展或合并，但不得为凑屏数伪造背面、侧面、尺码、成分、洗护或穿着功效。

`promptSet.items` 每个 item 的固定字段如下：

| 字段 | 含义 |
| --- | --- |
| `id` | 图片编号，如 `H02` 或 `D03` |
| `type` | `home` 或 `detail` |
| `version` | 版本，如 `V1` |
| `claimId` | 对应卖点编号，使用 `Sxx` 或空值；首图通常填写此项 |
| `roleId` | 对应页面作用编号，使用 `R01`、`R02` 等或空值；详情角色页可填写此项 |
| `referenceSha256` | 当前原产品图 SHA-256 |
| `structureLockSha256` | 当前产品结构指纹记录 SHA-256 |
| `viewConstraint` | 当前图片允许使用的原图视角边界 |
| `compositionFamily` | 本图构图家族，用于阻止相邻页面模板重复 |
| `proofPresentation` | 卖点证明与主体/场景的整合方式 |
| `proofAddsNewInformation` | 证明模块是否提供不同于主图的新信息，必须为 `true` |
| `cardPath` | 设计卡片路径 |
| `promptPath` | 纯净提示词路径 |
| `width` | 目标宽度 |
| `height` | 目标高度 |
| `status` | 当前项目状态 |

### 7. 用户确认提示词

1. 向用户提交整套设计卡片、纯净提示词、图片顺序及风格锁定项。
2. 只有记录用户明确确认原话和时间、将 `promptSet.confirmed` 设为 `true` 后，状态才可进入 `prompts_confirmed`。
3. 确认后不得静默换词、增加功能、调整卖点顺序或改变产品事实；修改必须创建新版本并保留旧版。
4. 未确认整套提示词时禁止调用任何生图工具。

### 7.1 生图通道选择

1. 默认正式通道仍为 `generation.channel=chatgpt_web_qq`、`generation.channelStatus=default`；执行 QQ 浏览器中的 ChatGPT 网页链路。
2. `generation.channel=codex_internal_image_gen` 仅用于用户明确批准的当前实验任务，必须保持 `generation.channelStatus=experimental`，不得据单次测试自动升级为全局默认或正式 Skill。
3. 内部通道每张图开始前必须记录 `generation.channelAuthorization`，执行 `current_job_version_authorization`：`jobId`、`itemId`、`promptVersion`、`channel` 必须精确匹配当前任务，另含用途、用户授权原话、授权时间及布尔值 `confirmed=true`。上一张图、上一版本或其他任务的授权不得复用。
4. 两种通道都必须执行逐图参考绑定、产品结构锁、单图验收和整套验收；改变通道不能降低产品原貌、尺寸、文字、构图或视觉整合标准。

### 8. 首个实际队列项（风格锚点）

1. 根据已确认范围初始化 `generation.styleAnchor.itemId`：`home/full=H01`，`detail=D01`；JSON 模板默认空值，不得在任务初始化前固定编号。
2. 网页通道使用 `generation.chatSessionPolicy=single_conversation_full_set`。只允许在首个实际队列项开始前打开一次 QQ 浏览器中的 ChatGPT 干净新对话，并记录稳定的 `generation.chatSessionReference`、`generation.chatSessionOpenedForItemId` 和 `generation.newConversationCount=1`。
3. 网页通道的首图、后续首图、详情首屏和后续详情屏全部继续使用这一个对话窗口；`full` 范围从最后一张首图切换到 D01 时不得点击新建对话，不得打开独立详情页会话。
4. 网页通道通过上传前后门禁后，只提交首个实际队列项 `V1` 的纯净生图提示词；首项的 `assetTransfer.conversationAction` 记录为 `opened_new`，会话引用必须与 `generation.chatSessionReference` 一致。
5. 内部通道使用 `generation.chatSessionPolicy=stateless_reference_bound`、`generation.newConversationCount=0`、空的 `chatSessionOpenedForItemId`，并将 `assetTransfer.conversationAction` 固定为 `direct_tool_call`；不得虚构已经打开、复用或继承了网页对话。
6. 内部通道通过门禁后，以 `referenced_image_paths` 直接绑定结构锁中的原产品文件本体；工具返回文件必须先归档到当前任务 `candidates/`，再按目标比例进行确定性裁切或缩放并核对最终尺寸，不得把工具默认输出位置直接当正式候选。
7. 执行模式固定为 `generation.executionMode=batch_after_style_anchor`，复核策略固定为 `generation.reviewPolicy=anchor_once_batch_qc_final_set_review`。
8. 用户确认风格锚点时，同时记录任务级 `generation.batchAuthorization`，授权范围固定为 `remaining_queue_after_anchor`，并绑定当前 `jobId`、`category.id`、`category.profileVersion` 与生图通道。
9. 风格锚点确认后，逐图 `generation.channelAuthorization` 可以继承同一任务级批量授权生成当前编号与版本的精确记录，不再要求用户重复授权。不得逐张请求用户确认，也不得使用 `generated_awaiting_emperor_review` 或 `awaiting_emperor_review`。
10. 下载或接收并归档图片，核对图片、提示词、编号、版本和哈希。
11. 图片质量检查通过后，必须由用户确认视觉方向，并将确认原话和时间写入 `generation.styleAnchor`。
12. 风格锚点未确认时禁止生成后续首图或详情页图。

### 9. 逐张验收（内部质量门禁）与自动推进

1. 风格锚点确认后，`home` 范围按 `H02` 到最后一张首图继续；`full` 范围按 `H02` 到最后一张首图，再按 `D01` 到最后一张详情图；`detail` 范围按 `D02` 到最后一张详情图继续，不得打乱已确认顺序。
2. 网页通道的首个实际队列项之后，每张图的 `assetTransfer.conversationAction` 必须为 `reused_existing`，`assetTransfer.chatSessionReference` 必须等于 `generation.chatSessionReference`。点击侧栏“新建对话”、为详情页另开会话、让 `newConversationCount` 大于1或无法确认仍在原会话时立即停止。
3. 网页通道每张图片执行逐图参考绑定：提交当前纯净提示词前，都必须在同一个GPT对话窗口重新附带 `promptSet.structureLock.referencePath` 指向的原产品文件本体，逐次复核 SHA-256 与网页缩略图，并把本次上传绑定的 `itemId`、`promptVersion`、`verifiedAt`、`chatSessionReference`、`conversationAction` 写入 `assetTransfer`。任一项与 `generation.currentItemId`、当前提示词版本、本次核对时间或整套会话引用不符，门禁立即停止；不得复用上一张图片的 `verified` 状态。不得用“同一对话已经记住产品”代替本轮参考图；同一对话只用于继承风格，不作为产品几何证据。
4. 内部通道每张图片都重新以 `referenced_image_paths` 绑定同一份已归档产品原图并复核 SHA-256；不得依赖上一张生成图作为产品几何依据，也不得把 `clipboardPrepared` 或 `thumbnailVerified` 伪记为 `true`。当前授权、图片编号、提示词版本、参考图和结构锁任一不匹配即停止。
5. 每张下载或接收归档时禁止覆盖同名文件；如需移动到任务目录，移动前后必须确认 SHA-256 和字节数一致，任一条件不满足即停止归档并保留证据。
6. 每张归档后由执行助手立即按 `tests/TAOBAO_ECOMMERCE_IMAGE_SET_ACCEPTANCE.md` 检查；这是内部质量门禁，不是用户逐图审批点。
7. 检查产品一致性、单一卖点、证据、图文对应、文字准确、尺寸构图、AI 异常及禁用内容；详情页还必须检查四层完整性、有效内容覆盖与连续空白比例。机械功能必须通过机械关系可判读门禁，轮径、轴距、主体高度、部件大小和连接位置必须通过原图相对比例基准门禁。
8. 每张候选图必须与对标报告并排复核 `benchmarkAlignment`、`categoryFit`、`visualIntegration`、`proofRelevance`、`lowerHalfContinuity`、`moduleNovelty`。局部证明若与主体和场景脱节、只是赤裸裸放入一个框、重复上一屏模块、没有增加信息，或造成下半屏割裂，任一项必须为 `false` 并退回当前图。
9. 产品结构拓扑一致性是独立硬门禁：逐项对照 `immutableComponents`、`connectionTopology`、`relativeGeometry` 和 `visibleViewBoundary`；任一部件被替换、增删，连接关系改变，比例失真，或画面越出可见视角边界，`quality.structureConsistency` 必须为 `false`，不得由颜色、风格或整体轮廓相似抵消。
10. 当前图片未通过时，只修改当前图片并创建新版本，不得提交下一条提示词；网页通道继续原GPT对话，内部通道继续无状态调用并重新绑定原产品图。当前图片通过后必须自动激活并生成下一编号，不向用户发送“通过/继续”请求。
11. 产品漂移最多三轮，依次强化结构指纹、重新附原图和收紧构图要求；网页通道禁止自动新建对话，内部通道禁止把上一轮结果冒充原图。第三轮仍失败时停止并报告证据。越出可见视角边界不是重试问题，必须改构图或补充对应角度产品图。鞋舌、鞋垫、鞋底或标牌上的小型产品文字不属于普通画面文字：不得让模型反复猜写。非当前卖点时先用视角、遮挡或景深自然规避；必须清晰展示时使用原素材确定性合成并单独验收，素材不足则改镜头。
12. 只有授权失效、素材或视角缺失、账号权限、安全拦截、连续三轮同根因失败或会改变已确认产品/场景/视觉方向时才停止并报告；普通文字错误、构图失衡、局部空洞、风格轻微漂移和单图返修均由执行助手自主处理。
13. 全部图片通过后，状态进入 `single_images_passed`，一次性提交整套结果供用户验收。

### 10. 整套一致性验收

1. 对 `home`、`detail`、`full` 三种范围均核对产品、品牌、卖点术语、配色、字体气质、信息层级、光线和摄影质感的一致性，并将整套 `setAcceptance.checks.structureConsistency` 作为独立必过项。
2. 核对相邻图片构图、机位和产品位置有明显变化；对照 `marketBenchmark.styleDecision` 检查 `marketBenchmarkAlignment`、`proofIntegration`、`moduleRepetitionControl`、`lowerHalfContinuity` 全部通过。任何连续裸框、重复细节模块或下半屏割裂均不得由“整体风格统一”抵消。
3. 核对数量、编号、尺寸、文件名、提示词、版本和验收记录一一对应。
4. 记录路径写入 `setAcceptance.path`，全部检查真实通过后才可将 `setAcceptance.passed` 设为 `true`。
5. 未通过时只返修受影响图片，并重新执行对应单图检查和整套检查。

### 11. 用户最终验收

1. 只有全部单图与整套检查均通过，才能提交用户验收。
2. 必须记录用户明确验收原话和时间，并将 `approval.approved` 设为 `true`。
3. 未经用户明确验收不得进入 outputs，也不得把沉默、空白表格或代理自评当作验收。

### 12. 非覆盖晋级

1. 只有 `approval.approved=true` 且整套检查通过时才允许晋级。
2. 正式目录必须是新的、未占用的版本目录；禁止覆盖既有正式成果。
3. 晋级后记录目标目录、操作者、时间、文件清单和哈希，并将状态改为 `promoted`。
4. 测试线程不得执行正式晋级；只能由主流程线程或获准的正式生产链路执行。

## 三、数组项目契约

数组默认均为空；写入运行数据后，运行时门禁逐项校验，缺少任何必需字段即停止：

- `product.assets` 每个 item 至少包含：`id`、`path`、`sourcePath`、`fileName`、`bytes`、`sha256`、`authorizationConfirmed`、`authorizationStatement`。
- `product.facts` 每个 item 至少包含：`id`、`name`、`value`、`evidenceType`、`evidenceReference`、`verified`。
- `marketBenchmark.references` 每个 item 至少包含：`id`、`platform`、`url`、`capturedAt`、`evidencePath`、`observation`；四个平台每个平台至少 2 项。
- `marketBenchmark.styleDecision` 至少包含：`name`、`rationale`、`platformBlend`、`visualPrinciples`、`forbiddenPatterns`、`detailProofStrategy`。
- `promptSet.items` 每个 item 至少包含：`id`、`type`、`version`、`claimId`、`roleId`、`referenceSha256`、`structureLockSha256`、`viewConstraint`、`compositionFamily`、`proofPresentation`、`proofAddsNewInformation`、`cardPath`、`promptPath`、`width`、`height`、`status`。其中三个结构绑定字段必须分别匹配原产品图哈希、当前结构锁记录哈希和该图可使用的原图支持视角。
- `candidates` 每个 item 至少包含：`id`、`type`、`version`、`promptId`、`path`、`acceptancePath`、`sha256`、`bytes`、`width`、`height`、`status`、`quality`；其中 `quality` 为逐张质量检查对象。
- `history` 每个 item 至少包含：`at`、`actor`、`action`、`itemId`、`version`、`statement`。
- `promotion.files` 每个 item 至少包含：`id`、`path`、`fileName`、`bytes`、`sha256`、`type`、`version`。
- `promptSet.styleLock` 固定字段为：`brand`、`productColor`、`productStructure`、`productMaterial`、`productProportion`、`productAccessories`、`corePalette`、`typography`、`informationHierarchy`、`lighting`、`photographyStyle`、`forbiddenContent`、`benchmarkReportPath`、`styleDirection`、`proofIntegrationRules`、`forbiddenLayouts`。JSON 模板初始仍为空对象；进入提示词确认前必须完整写入并由运行时门禁逐项校验。
- `promptSet.structureLock` 固定字段为：`referenceAssetId`、`referencePath`、`referenceSha256`、`recordPath`、`confirmed`、`immutableComponents`、`connectionTopology`、`relativeGeometry`、`visibleViewBoundary`、`allowedVariations`、`forbiddenVariations`。JSON 模板初始为空对象；进入提示词确认前必须完整写入，参考资产、路径和哈希必须与 `product.assets` 中同一产品原图完全一致。结构指纹不得使用“与原图一致”等空泛描述代替：不可变部件至少 3 项、连接拓扑至少 2 项、禁止变化至少 2 项，其余结构数组至少 1 项，且每项必须是可执行的具体描述。
- `assetTransfer` 的逐图绑定字段为：`itemId`、`promptVersion`、`verifiedAt`、`chatSessionReference`、`conversationAction`；网页通道与当前编号、版本、本次缩略图核对时间和整套唯一GPT对话一一对应，内部通道与当前编号、版本、本次原图哈希核对时间和直接工具调用一一对应。
- `generation.channel` 默认固定为 `chatgpt_web_qq`；仅有当前任务、当前图片和当前提示词版本的明确实验授权时允许改为 `codex_internal_image_gen`。
- 网页通道的 `generation.chatSessionPolicy` 为 `single_conversation_full_set`，`chatSessionOpenedForItemId` 必须等于风格锚点，`newConversationCount` 必须始终为1。内部通道的策略为 `stateless_reference_bound`，不得记录网页会话，`newConversationCount` 必须为0。

## 四、状态与恢复

合法状态顺序为：

`intake_pending` → `assets_archived` → `selling_points_draft` → `selling_points_confirmed` → `benchmark_pending` → `benchmark_completed` → `prompts_draft` → `prompts_confirmed` → `style_anchor_pending` → `generating` → `single_images_passed` → `set_review_pending` → `user_acceptance_pending` → `approved` → `promoted`。

任务中断后，从 `generation.currentItemId` 或第一个未通过的图片编号继续。网页通道恢复 `generation.chatSessionReference` 对应的原GPT对话，找不到原对话或无法证明会话一致时停止，不得自动开新对话冒充续作；内部通道重新核对当前授权并重新绑定原产品图，不得声称恢复网页上下文。局部修改只递增当前图片版本，不改变其他图片版本；大幅改变视觉方向时停止当前整套并等待用户决定是否从首张建立新的整套版本。旧提示词、图片和验收记录不得覆盖。

## 五、异常与停止条件

- 同一素材文件本体复制粘贴失败一次，即停止自动上传；不得连续猜测按钮或坐标。
- 无法确认正确素材缩略图时，禁止提交提示词。
- 下载文件无法可靠定位、文件占用、同名目标已存在，或剪切前后 SHA-256、字节数、目标存在与源文件消失任一验证失败时，停止归档。
- 中文错误最多依次尝试定向重做、无错误文字干净画面、准确文字排版兜底。
- 同一根本原因连续处理三轮仍失败时停止，保留提示词、候选图、时间线和问题证据。
- 明确局部修改只递增当前图片版本并在原GPT对话复测；不得以修改、首图转详情或恢复任务为理由自动新建对话。改变产品、品牌、任务类型或整套视觉方向时停止当前任务并等待用户决定是否建立新的整套版本。
