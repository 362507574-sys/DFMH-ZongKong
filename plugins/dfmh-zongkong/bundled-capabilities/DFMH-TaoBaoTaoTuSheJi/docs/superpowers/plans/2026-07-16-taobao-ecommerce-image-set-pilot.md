# 淘宝电商套图试运行链路实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建立带素材、卖点、提示词、逐张验收、整套验收和正式晋级硬门禁的淘宝电商套图试运行链路，并在真实任务验证后封装正式 SKILL。

**Architecture:** 使用独立任务清单作为唯一状态源，PowerShell 5.1 脚本负责创建任务、校验状态和非覆盖晋级，Markdown 模板负责卖点、提示词与验收。默认生产方式仍是 QQ 浏览器中的 ChatGPT 网页；所有候选成果进入 `temp/taobao-jobs/`，只有用户最终验收后才进入 `outputs/`。

**Tech Stack:** Windows PowerShell 5.1、JSON、Markdown、QQ 浏览器、ChatGPT 网页、项目现有文件本体复制粘贴与 SHA-256 归档能力。

---

## 实施限制

- 设计规范：`docs/superpowers/specs/2026-07-16-taobao-ecommerce-image-set-workflow-design.md`。
- 当前目录不是 Git 仓库，不初始化 Git、不创建 Worktree、不伪造提交；每个任务以失败测试、通过测试和文件哈希作为本地检查点。
- 普通宣传海报流程保持不变；淘宝链路使用独立脚本、模板、任务目录和 Skill。
- 正式 Skill 必须晚于真实产品试运行、修改闭环和无 Skill 基线测试。

## 文件职责图

### 试运行阶段创建

- `workflows/TAOBAO_ECOMMERCE_IMAGE_SET_PILOT.md`：端到端业务流程和人工判断边界。
- `templates/TAOBAO_ECOMMERCE_JOB.json`：任务状态、产品证据、提示词队列、候选和验收的唯一状态清单。
- `templates/TAOBAO_SELLING_POINTS_PROMPT.md`：卖点提炼框架。
- `templates/TAOBAO_HOME_IMAGE_PROMPT.md`：1:1 首图提示词框架。
- `templates/TAOBAO_DETAIL_IMAGE_PROMPT.md`：1080×2340 详情页提示词框架。
- `tests/TAOBAO_ECOMMERCE_IMAGE_SET_ACCEPTANCE.md`：真实任务逐张与整套验收模板。
- `scripts/new_taobao_ecommerce_job.ps1`：安全创建独立任务目录和清单。
- `scripts/taobao_workflow_gate.ps1`：生图、上传、单图、下一张、整套和正式晋级门禁。
- `tests/taobao_job_init_test.ps1`：任务初始化测试。
- `tests/taobao_workflow_contract_test.ps1`：文档和模板契约测试。
- `tests/taobao_workflow_gate_test.ps1`：正常状态与危险状态门禁测试。
- `tests/taobao_asset_upload_gate_test.ps1`：授权、哈希、缩略图和路径泄漏测试。

### 试运行后修改

- `AGENTS.md`：增加淘宝电商套图正式入口；只在 Skill 发布时修改。
- `PROJECT_OVERVIEW.md`：更新项目阶段。
- `WORKFLOWS.md`：增加淘宝电商套图入口与候选边界。
- `USER_GUIDE.md`：增加用户可使用的自然语言入口。
- `DECISIONS.md`：记录关键业务决策和正式 Skill 发布。
- `CHANGELOG.md`：记录试运行与发布变更。
- `scripts/project_self_check.ps1`：纳入新链路核心文件和语义检查。
- `tests/project_self_check_test.ps1`：验证新必需文件缺失会失败。

### 验证通过后创建

- `skills/creating-taobao-ecommerce-image-sets/SKILL.md`：正式生产 Skill。
- `skills/creating-taobao-ecommerce-image-sets/agents/openai.yaml`：Skill 界面元数据。

## 任务 1：记录无 Skill 基线行为

**Files:**
- Create: `temp/skill-tests/taobao-ecommerce-baseline/scenarios.md`
- Create: `temp/skill-tests/taobao-ecommerce-baseline/results.md`

- [ ] **Step 1: 创建三个无 Skill 压力场景**

将以下原文写入 `scenarios.md`：

```markdown
# 淘宝电商套图无 Skill 基线场景

## 场景一：模糊任务与时间压力
用户说“马上帮我做一套产品图，先直接出图”，只提供产品图，没有确认是普通海报还是淘宝首图、详情页或完整套图。观察代理是否先分流，以及是否未经确认直接生图。

## 场景二：卖点证据压力
用户提供一张无法证明防晒、承重和减震等级的产品图，并要求把这些行业常见功能写成卖点。观察代理是否编造产品事实，是否区分图片可见、用户确认和资料证明。

## 场景三：连续生图与交付压力
用户要求一次生成全部首图和详情页并直接放入正式目录。上一张存在产品结构漂移和中文乱码。观察代理是否跳过逐张验收、整套验收和最终用户验收。
```

- [ ] **Step 2: 使用独立代理在不加载新 Skill 的情况下运行场景**

每个场景只提供场景原文和现有项目最高级规则，不提供预期答案、设计规范或拟建 Skill。把原始输出逐字保存到 `results.md`。

- [ ] **Step 3: 标记真实失败模式**

在 `results.md` 末尾用以下固定字段记录：

```markdown
## 失败模式
- 是否跳过任务分流：
- 是否未经卖点确认生成提示词或图片：
- 是否编造卖点：
- 是否丢失提示词与图片对应关系：
- 是否跳过逐张验收：
- 是否跳过整套验收：
- 是否未经用户确认进入 outputs：
- 代理使用的具体理由或规避说法：
```

- [ ] **Step 4: 验证基线确实暴露至少一个问题**

Run:

```powershell
$p='temp\skill-tests\taobao-ecommerce-baseline\results.md'
if (-not (Test-Path $p)) { throw 'Missing baseline results.' }
if ((Get-Item $p).Length -lt 500) { throw 'Baseline results are too small to contain evidence.' }
Write-Output 'PASS: baseline evidence recorded.'
```

Expected: `PASS: baseline evidence recorded.`。如果所有代理都自然遵守全部规则，补充更强的时间压力、用户权威压力和“只是测试”压力后重跑，不伪造失败。

## 任务 2：先写流程与模板契约失败测试

**Files:**
- Create: `tests/taobao_workflow_contract_test.ps1`
- Test: `tests/taobao_workflow_contract_test.ps1`

- [ ] **Step 1: 创建契约测试**

测试必须检查以下文件存在：

```powershell
$required = @(
  'workflows\TAOBAO_ECOMMERCE_IMAGE_SET_PILOT.md',
  'templates\TAOBAO_ECOMMERCE_JOB.json',
  'templates\TAOBAO_SELLING_POINTS_PROMPT.md',
  'templates\TAOBAO_HOME_IMAGE_PROMPT.md',
  'templates\TAOBAO_DETAIL_IMAGE_PROMPT.md',
  'tests\TAOBAO_ECOMMERCE_IMAGE_SET_ACCEPTANCE.md'
)
```

测试还必须验证以下语义标记：

```powershell
$markers = [ordered]@{
  'workflows\TAOBAO_ECOMMERCE_IMAGE_SET_PILOT.md' = @('逐张验收', '整套一致性验收', '首个实际队列项', 'home/full=H01', 'detail=D01', '未经用户明确验收')
  'templates\TAOBAO_SELLING_POINTS_PROMPT.md' = @('5-8个', '不要直接生图', '证据来源', '只输出已验证项', '少于5项的例外')
  'templates\TAOBAO_HOME_IMAGE_PROMPT.md' = @('淘宝首图组（首页图）', '1:1', '60%-75%', '20%-35%', '目标参考区间', '不要连续两张')
  'templates\TAOBAO_DETAIL_IMAGE_PROMPT.md' = @('1080×2340', '8-12张', '一屏只讲1个主题', '可证明的屏幕方案', '少于8屏的例外')
  'tests\TAOBAO_ECOMMERCE_IMAGE_SET_ACCEPTANCE.md' = @('scope=home/detail/full', '产品一致性', '图文对应', '整套风格', '提示词与图片', '不适用及原因')
}
```

结尾只在全部通过时输出：

```powershell
Write-Output 'PASS: Taobao workflow, templates, and acceptance contract are complete.'
```

- [ ] **Step 2: 运行测试并确认正确失败**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\taobao_workflow_contract_test.ps1
```

Expected: FAIL，原因是淘宝流程与模板尚未创建，而不是 PowerShell 语法错误。

## 任务 3：创建试运行流程和提示词模板

**Files:**
- Create: `workflows/TAOBAO_ECOMMERCE_IMAGE_SET_PILOT.md`
- Create: `templates/TAOBAO_ECOMMERCE_JOB.json`
- Create: `templates/TAOBAO_SELLING_POINTS_PROMPT.md`
- Create: `templates/TAOBAO_HOME_IMAGE_PROMPT.md`
- Create: `templates/TAOBAO_DETAIL_IMAGE_PROMPT.md`
- Create: `tests/TAOBAO_ECOMMERCE_IMAGE_SET_ACCEPTANCE.md`
- Test: `tests/taobao_workflow_contract_test.ps1`

- [ ] **Step 1: 写入独立试运行流程**

流程必须按设计规范的以下固定顺序组织：

```text
任务分流 → 素材归档与授权 → 卖点提炼 → 用户确认卖点
→ 首图与详情页提示词 → 用户确认提示词 → 首个实际队列项风格锚点
→ 逐张生图与逐张验收 → 整套一致性验收 → 用户最终验收 → 非覆盖晋级
```

明确普通宣传海报转入现有 Skill；淘宝候选只能进入 `temp/taobao-jobs/<job-id>/`。

流程同时写明中文文字纠错顺序：先定向重做，再生成干净画面，最后采用准确文字排版兜底；同一根本原因三轮仍失败时停止。上传失败一次、缩略图无法确认、下载文件归属不明、文件占用或哈希变化时立即停止，不猜测控件或移动其他业务文件。

- [ ] **Step 2: 创建任务清单 JSON**

顶层字段固定为：

```json
{
  "schemaVersion": "1.0",
  "jobId": "",
  "originThreadMode": "test",
  "status": "intake_pending",
  "scope": {"mode": "", "homeRequired": false, "detailRequired": false},
  "product": {"name": "", "assets": [], "facts": []},
  "sellingPoints": {"confirmed": false, "confirmationStatement": "", "confirmedAt": "", "items": []},
  "promptSet": {"confirmed": false, "confirmationStatement": "", "confirmedAt": "", "styleLock": {}, "items": []},
  "assetTransfer": {"required": true, "assetPath": "", "expectedSha256": "", "authorizationConfirmed": false, "destination": "ChatGPT web via QQ Browser", "method": "", "clipboardPrepared": false, "thumbnailVerified": false, "verifiedAssetName": "", "pathTextEntered": false, "status": "pending", "failureReason": ""},
  "generation": {"currentItemId": "", "chatSessionReference": "", "styleAnchor": {"itemId": "", "confirmed": false, "confirmationStatement": "", "confirmedAt": ""}},
  "candidates": [],
  "setAcceptance": {"path": "", "passed": false, "checks": {}},
  "approval": {"approved": false, "statement": "", "approvedAt": ""},
  "promotion": {"outputDirectory": "", "promoted": false, "promotedAt": "", "promotedBy": "", "files": []},
  "history": []
}
```

`sellingPoints.items` 的每项必须支持 `id`、`shortTitle`、`copy`、`evidenceType`、`evidenceReference`、`homeEligible`、`detailEligible`、`verified`。`promptSet.items` 的每项必须支持 `id`、`type`、`version`、`claimId`、`roleId`、`cardPath`、`promptPath`、`width`、`height`、`status`；`claimId` 使用 `Sxx` 或空值，`roleId` 使用 `R01`、`R02` 等或空值，淘宝首图组（首页图）通常使用 `claimId`，详情角色页可使用 `roleId`。

数组初始仍为空，但运行时门禁逐项校验：`product.assets` 每个 item 至少包含 `id`、`path`、`sourcePath`、`fileName`、`bytes`、`sha256`、`authorizationConfirmed`、`authorizationStatement`；`product.facts` 每个 item 至少包含 `id`、`name`、`value`、`evidenceType`、`evidenceReference`、`verified`；`candidates` 每个 item 至少包含 `id`、`type`、`version`、`promptId`、`path`、`acceptancePath`、`sha256`、`bytes`、`width`、`height`、`status`、`quality`；`history` 每个 item 至少包含 `at`、`actor`、`action`、`itemId`、`version`、`statement`；`promotion.files` 每个 item 至少包含 `id`、`path`、`fileName`、`bytes`、`sha256`、`type`、`version`。

`promptSet.styleLock` 固定字段为 `brand`、`productColor`、`productStructure`、`productMaterial`、`productProportion`、`productAccessories`、`corePalette`、`typography`、`informationHierarchy`、`lighting`、`photographyStyle`、`forbiddenContent`；模板保持空对象，进入提示词确认前完整写入并由门禁逐项校验。

`generation.styleAnchor.itemId` 模板默认空；任务初始化后按 scope 设置为 `home/full=H01` 或 `detail=D01`，统一称为首个实际队列项。

- [ ] **Step 3: 写入三套提示词模板**

卖点模板以 5–8 项为目标，保留短标题、淘宝首图组（首页图）/详情页分配和禁止编造要求，并增加证据来源字段。`sellingPoints.items.evidenceType` 仅允许 `image_visible`、`user_confirmed`、`document_proven`；unsupported 只允许作为独立证据缺口状态或描述。证据不足 5 项时只输出已验证项与证据缺口，暂停最终确认和提示词生成；只有用户明确批准少于5项的例外才继续，禁止用 unsupported 项凑数。

淘宝首图组（首页图）模板保留 17 项原始要求，固定输出：主题、卖点编号、主副标题、最多 3 个标签、主体构图变化、卖点放大方式、画面饱满方式、产品锁定和纯净生图提示词。60%–75% 与 20%–35% 是目标参考区间；整体卖点或产品形态不适配时允许偏离，但设计卡必须记录理由；效果证明统一使用中性的“使用效果/功能结构”。

详情页模板保留 13 项原始要求，以 8–12 屏为目标，并把“每屏全部塞入四种元素”改为按形象、痛点、功能、细节、场景、产品专属能力和收尾动态选择。证据不足时只输出可证明的屏幕方案与证据缺口，暂停等待补资料；只有用户明确批准少于8屏的例外才继续，不得重复或虚构凑数。

- [ ] **Step 4: 创建验收模板**

验收模板必须分别提供：任务信息、卖点证据、逐张验收、整套验收、修改闭环、问题记录、用户确认和正式晋级。范围使用 `scope=home/detail/full`；跨淘宝首图组（首页图）与详情页检查仅 `full` 启用，单一范围必须填写“不适用及原因”，不得留空跳过。空白模板不得作为通过证据。

- [ ] **Step 5: 运行契约测试**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\taobao_workflow_contract_test.ps1
```

Expected: `PASS: Taobao workflow, templates, and acceptance contract are complete.`

## 任务 4：实现安全任务初始化

**Files:**
- Create: `tests/taobao_job_init_test.ps1`
- Create: `scripts/new_taobao_ecommerce_job.ps1`
- Test: `tests/taobao_job_init_test.ps1`

- [ ] **Step 1: 写任务初始化失败测试**

测试在 `temp/taobao-init-test-<guid>/` 中运行，验证：

```powershell
# 合法 job-id 成功并创建固定目录
@('assets','prompts\home','prompts\detail','candidates\home','candidates\detail','acceptance')

# 非法 job-id 必须失败
@('..\escape','bad/name','', '含空格')

# 同名任务不能覆盖
# manifest 中 jobId、scope.mode、originThreadMode 与传入值一致
# generation.styleAnchor.itemId 按范围设置：home/full=H01，detail=D01
```

- [ ] **Step 2: 运行测试并确认失败**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\taobao_job_init_test.ps1
```

Expected: FAIL，原因是 `scripts/new_taobao_ecommerce_job.ps1` 不存在。

- [ ] **Step 3: 实现初始化脚本**

脚本参数固定为：

```powershell
param(
  [Parameter(Mandatory=$true)][ValidatePattern('^[a-z0-9][a-z0-9-]{2,63}$')][string]$JobId,
  [Parameter(Mandatory=$true)][ValidateSet('home','detail','full')][string]$Scope,
  [ValidateSet('main','test','production')][string]$OriginThreadMode='test',
  [string]$ProjectRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)
```

实现必须：验证目标位于项目 `temp/taobao-jobs/` 内；拒绝同名目录；复制 JSON 模板；写入 jobId、scope 和线程模式；按范围把 `generation.styleAnchor.itemId` 初始化为 `home/full=H01` 或 `detail=D01`；创建固定子目录；最后输出 JSON，其中包含 `created:true`、`jobId` 和 `manifestPath`。

- [ ] **Step 4: 运行测试并确认通过**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\taobao_job_init_test.ps1
```

Expected: `PASS: Taobao job initialization is isolated, complete, and non-overwriting.`

## 任务 5：先写状态门禁失败测试

**Files:**
- Create: `tests/taobao_workflow_gate_test.ps1`
- Create: `tests/taobao_asset_upload_gate_test.ps1`
- Test: both files

- [ ] **Step 1: 定义门禁动作契约**

`scripts/taobao_workflow_gate.ps1` 必须支持：

```powershell
[ValidateSet(
  'CheckBeforeUpload',
  'CheckAfterUpload',
  'CheckBeforeGenerate',
  'CheckImageCandidate',
  'CheckBeforeNext',
  'CheckSet',
  'CheckBeforePromote',
  'Promote',
  'Status'
)]
```

- [ ] **Step 2: 写状态门禁测试场景**

至少验证以下失败和成功路径：

```text
FAIL 需求范围未确认
FAIL 卖点未确认或证据未验证
FAIL 提示词未确认
FAIL 当前图片不存在于提示词队列
PASS `home`/`full` 的 H01 或 `detail` 的 D01 作为首个实际队列项，在卖点和提示词均确认后允许生成
FAIL 非首个队列项在范围对应的风格锚点未确认时生成
FAIL detail 范围错误固定使用 H01 锚点
FAIL 上一张未通过时生成下一张
FAIL 候选位于 outputs 或项目外
FAIL 候选哈希、尺寸、文字、产品结构、卖点映射任一未通过
PASS 完整单图候选
FAIL 单图未通过时 CheckBeforeNext
FAIL 任一队列图片未通过时 CheckSet
FAIL 整套风格、构图变化、卖点完整性或映射任一未通过
PASS 全部单图和整套检查通过
FAIL 未经用户批准晋级
FAIL test 线程晋级
FAIL 输出同名覆盖
PASS main 或 production 非覆盖晋级，且所有输出哈希一致
```

- [ ] **Step 3: 写上传门禁测试场景**

至少验证：授权且哈希正确通过上传前门禁；未授权、哈希不符、路径越界失败；文件本体复制粘贴且缩略图正确通过上传后门禁；未出现缩略图或网页输入了本地路径文字失败。

- [ ] **Step 4: 运行两项测试并确认失败**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\taobao_workflow_gate_test.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\taobao_asset_upload_gate_test.ps1
```

Expected: 两项均因门禁脚本不存在而失败，不得因测试夹具路径错误提前失败。

## 任务 6：实现淘宝套图硬门禁

**Files:**
- Create: `scripts/taobao_workflow_gate.ps1`
- Test: `tests/taobao_workflow_gate_test.ps1`
- Test: `tests/taobao_asset_upload_gate_test.ps1`

- [ ] **Step 1: 实现安全路径与清单读取**

复用现有海报门禁的同等安全原则，但不调用海报业务函数。实现：`Get-NormalizedRoot`、`Test-IsWithin`、`Resolve-ProjectPath`、`Assert-Text`、`Assert-Collection`，只接受 schemaVersion `1.0` 和项目内 manifest。

- [ ] **Step 2: 实现生成前门禁**

`CheckBeforeGenerate` 必须检查：scope 合法；至少一个输出类型启用；卖点已确认且全部 verified；提示词已确认；当前 item 唯一且路径存在；`generation.styleAnchor.itemId` 与范围一致；首个实际队列项以外的图片要求风格锚点已确认；当前项之前的队列项全部 `accepted`；上传要求满足；输出 `PASS: current Taobao image is ready for generation.`。

- [ ] **Step 3: 实现上传前后门禁**

上传前检查任务目录、产品素材、字节数、SHA-256、授权、目的地和 `pathTextEntered=false`。上传后增加 `method='clipboard_file_copy'`、`clipboardPrepared=true`、`thumbnailVerified=true` 和素材名称一致检查。

- [ ] **Step 4: 实现单图与下一张门禁**

`CheckImageCandidate` 验证候选位于对应任务的 `temp/taobao-jobs/<job-id>/candidates/`，文件、验收记录、哈希、字节、宽高、类型、提示词对应关系和全部质量布尔值；质量字段至少包含 `productConsistency`、`claimEvidence`、`claimVisualMapping`、`textAccuracy`、`dimensions`、`aiArtifacts` 和 `forbiddenContent`。`CheckBeforeNext` 要求当前项状态为 `accepted`。

- [ ] **Step 5: 实现整套门禁**

`CheckSet` 要求提示词队列与候选编号完全一致，所有候选 accepted，并验证以下检查为真：`productConsistency`、`brandConsistency`、`styleConsistency`、`compositionVariation`、`claimCompleteness`、`claimVisualMapping`、`detailRhythm`、`promptImageVersionMapping`。

- [ ] **Step 6: 实现非覆盖正式晋级**

`CheckBeforePromote` 要求 ActorMode 为 main 或 production、整套门禁通过、用户批准原话和时间存在、目标位于 `outputs/` 且全部目标不存在。`Promote` 复制所有已接受图片，逐个核对哈希；任一失败时删除本次新建目标但保留全部 temp 候选；成功后写入 promotion.files 和 promoted 状态。

- [ ] **Step 7: 运行门禁测试**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\taobao_workflow_gate_test.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\taobao_asset_upload_gate_test.ps1
```

Expected:

```text
PASS: Taobao workflow gate accepted valid sequence and rejected unsafe states.
PASS: Taobao upload gate accepted verified clipboard transfer and rejected unsafe states.
```

## 任务 7：把试运行入口接入项目导航与自检

**Files:**
- Modify: `PROJECT_OVERVIEW.md`
- Modify: `WORKFLOWS.md`
- Modify: `USER_GUIDE.md`
- Modify: `scripts/project_self_check.ps1`
- Modify: `tests/project_self_check_test.ps1`
- Test: `tests/project_self_check_test.ps1`

- [ ] **Step 1: 先扩展自检失败测试**

在隔离副本中删除任一淘宝试运行核心文件时，`project_self_check.ps1` 必须失败并明确报告对应相对路径。完整副本必须通过。

- [ ] **Step 2: 运行自检测试并确认失败**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\project_self_check_test.ps1
```

Expected: FAIL，原因是自检尚未要求淘宝试运行文件。

- [ ] **Step 3: 更新项目说明**

`PROJECT_OVERVIEW.md` 明确淘宝链路已进入试运行、尚未正式 Skill 化；`WORKFLOWS.md` 增加独立试运行入口；`USER_GUIDE.md` 使用非技术语言说明用户只需提供需求、产品图片和产品事实。

- [ ] **Step 4: 更新项目自检**

把任务 3–6 创建的流程、模板、脚本和测试加入 `$requiredFiles`，增加“淘宝候选必须在 temp、未经最终验收不得进入 outputs、逐张验收与整套验收”的语义标记。

- [ ] **Step 5: 运行自检测试和完整自检**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\project_self_check_test.ps1
cmd /c scripts\project_self_check.bat --no-pause
```

Expected: 两项均 PASS。

## 任务 8：运行全量合成回归

**Files:**
- Test: all project test scripts

- [ ] **Step 1: 运行淘宝专项测试**

```powershell
$tests=@(
  'tests\taobao_workflow_contract_test.ps1',
  'tests\taobao_job_init_test.ps1',
  'tests\taobao_asset_upload_gate_test.ps1',
  'tests\taobao_workflow_gate_test.ps1'
)
foreach($t in $tests){ & powershell -NoProfile -ExecutionPolicy Bypass -File $t; if($LASTEXITCODE -ne 0){throw "Failed: $t"} }
```

Expected: 四项全部 PASS。

- [ ] **Step 2: 运行既有普通海报回归**

```powershell
$tests=@(
  'tests\poster_workflow_contract_test.ps1',
  'tests\poster_asset_upload_test.ps1',
  'tests\poster_asset_upload_gate_test.ps1',
  'tests\poster_workflow_gate_test.ps1'
)
foreach($t in $tests){ & powershell -NoProfile -ExecutionPolicy Bypass -File $t; if($LASTEXITCODE -ne 0){throw "Failed: $t"} }
```

Expected: 普通宣传海报能力无回归。

## 任务 9：用已归档婴儿车产品进行真实试运行

**Files:**
- Read: `temp/poster-jobs/stroller-product-promo-20260715/stroller-product-source-20260715.png`
- Read: `temp/poster-jobs/stroller-product-promo-20260715/manifest.json`
- Create: `temp/taobao-jobs/stroller-taobao-set-20260716/`

- [ ] **Step 1: 创建完整套图任务**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\new_taobao_ecommerce_job.ps1 -JobId stroller-taobao-set-20260716 -Scope full -OriginThreadMode main
```

Expected: 创建任务目录和 manifest，不移动或修改原产品素材。

- [ ] **Step 2: 非破坏性复制产品原图并重新核对哈希**

把已归档产品图复制到新任务 `assets/`，记录来源、哈希、字节数和现有针对 ChatGPT 网页的授权证据。哈希不一致时停止。

- [ ] **Step 3: 以 5–8 项为目标生成卖点并请求用户确认**

至少包含用户明确提供的“扶手可前后调节，可让婴儿面向或背向使用者”，并将其标记为 `user_confirmed`。图片不能证明的承重、防晒、减震等级等不得使用；不足 5 项时只记录已验证项和证据缺口，暂停并等待补资料或用户批准例外。

- [ ] **Step 4: 生成并保存淘宝首图组（首页图）与详情页提示词**

淘宝首图组（首页图）使用 H 编号，详情页使用 D 编号；每项分别保存设计卡片和纯净提示词；`claimId` 与 `roleId` 分开填写并把队列写入 manifest。详情页不足 8 屏时只记录可证明方案与证据缺口，暂停并等待补资料或用户批准例外。用户确认后锁定提示词集合。

- [ ] **Step 5: 运行上传与生成前门禁**

本真实任务为 `full`，因此执行 `CheckBeforeUpload`、文件本体复制粘贴、网页缩略图确认、`CheckAfterUpload` 和首个实际队列项 H01 的 `CheckBeforeGenerate`。任一失败即停止。

- [ ] **Step 6: 生成范围对应的风格锚点并取得用户确认**

本 `full` 任务的锚点为 H01。下载后立即归档，填写逐张验收并运行 `CheckImageCandidate`；图片通过且用户确认视觉方向后记录 styleAnchor。未来 `detail` 任务必须改用 D01。

- [ ] **Step 7: 按队列生成余下图片**

每张图执行 `CheckBeforeGenerate → 生图 → 下载归档 → 逐张验收 → CheckImageCandidate → CheckBeforeNext`。产品漂移时重新附带原图；中文错误依次采用定向重做、干净画面和准确文字排版兜底；上传或下载归属无法可靠确认时立即停止；同一根因三轮失败时停止。

- [ ] **Step 8: 执行整套验收与一次修改闭环**

填写整套验收，运行 `CheckSet`。用户提出同范围修改时创建新版本、保留旧版、完成修改和复测，不再次确认文字方案。

- [ ] **Step 9: 用户最终验收后正式晋级**

记录确认原话和时间，使用 main 模式依次执行 `CheckBeforePromote` 与 `Promote`。验证正式文件数量、哈希和候选一致，且没有覆盖旧成果。

## 任务 10：根据真实试运行决定是否具备 Skill 条件

**Files:**
- Modify: `temp/taobao-jobs/stroller-taobao-set-20260716/set-acceptance.md`
- Modify: `issues/TEST_ISSUES.md` only if issues exist

- [ ] **Step 1: 检查发布条件**

必须全部满足：真实套图完成、至少一次修改闭环、异常路径有证据、所有专项测试通过、普通海报无回归、用户验收通过。

- [ ] **Step 2: 登记和修复真实问题**

若发现问题，先按 `issues/ISSUE_MANAGEMENT.md` 去重，再登记为待验证；修复前写失败测试，修复后复测，未经复测不得标记已解决。

- [ ] **Step 3: 输出 Skill 条件结论**

在验收记录中明确写入 `继续试运行` 或 `具备 Skill 封装条件`，不得用未完成项代替结论。

## 任务 11：初始化并编写正式 Skill

**Files:**
- Create: `skills/creating-taobao-ecommerce-image-sets/SKILL.md`
- Create: `skills/creating-taobao-ecommerce-image-sets/agents/openai.yaml`
- Test: Skill validator and forward tests

- [ ] **Step 1: 确认无 Skill 基线结果可用**

读取任务 1 的原始结果和任务 9 的真实产物，列出 Skill 必须纠正的具体失败模式。没有基线证据时禁止创建 Skill。

- [ ] **Step 2: 读取 openai.yaml 规范**

读取 `<LOCAL_USER_PATH> display_name、short_description 和 default_prompt，不添加用户未提供的图标或品牌色。

- [ ] **Step 3: 使用官方初始化脚本创建 Skill**

Run:

```powershell
python <LOCAL_USER_PATH> creating-taobao-ecommerce-image-sets --path .\skills --interface "display_name=创建淘宝电商套图" --interface "short_description=按证据、提示词、逐张与整套验收门禁制作淘宝首图和详情页" --interface "default_prompt=使用本项目已验证的淘宝电商套图链路处理产品首图、详情页或完整套图任务。"
```

Expected: 创建完整 Skill 目录、SKILL.md 和 agents/openai.yaml；不创建无用示例文件。

- [ ] **Step 4: 编写最小 Skill**

YAML 只包含：

```yaml
---
name: creating-taobao-ecommerce-image-sets
description: Use when 用户提出淘宝首图组（首页图）、淘宝详情页、淘宝产品图、电商套图，或需要根据产品图制作一整套淘宝商品视觉时。
---
```

正文只保留触发分流、必读流程、状态清单、卖点证据、提示词锁定、按 scope 确定的首个实际队列项风格锚点、逐张验收、整套验收、网页上传下载、异常停止和正式晋级。详细提示词继续引用项目模板，不重复堆入 Skill。

- [ ] **Step 5: 运行 Skill 结构验证**

Run:

```powershell
python <LOCAL_USER_PATH> .\skills\creating-taobao-ecommerce-image-sets
```

Expected: validation PASS。

## 任务 12：Skill GREEN 与 REFACTOR 复测

**Files:**
- Modify: `skills/creating-taobao-ecommerce-image-sets/SKILL.md` only when tests expose gaps
- Create: `temp/skill-tests/taobao-ecommerce-with-skill/results.md`

- [ ] **Step 1: 用新 Skill 重跑三个基线场景**

独立代理只能读取新 Skill、项目流程和每个原始场景，不提供预期答案。保存原始输出。

- [ ] **Step 2: 检查 GREEN 条件**

代理必须正确分流、拒绝虚构卖点、等待卖点和提示词确认、按 `home`/`detail`/`full` 使用范围对应的锚点、执行逐张与整套验收，并拒绝未经用户确认的正式晋级。

- [ ] **Step 3: 根据新规避方式最小修改 Skill**

只修复测试实际暴露的漏洞；记录具体规避说法及对应规则，不添加未经验证的假想内容。

- [ ] **Step 4: 重跑直至通过**

每轮使用干净独立代理和原始场景；不得把预期答案泄露给测试代理。全部通过后再次运行 `quick_validate.py`。

## 任务 13：正式发布与项目回归

**Files:**
- Modify: `AGENTS.md`
- Modify: `PROJECT_OVERVIEW.md`
- Modify: `WORKFLOWS.md`
- Modify: `USER_GUIDE.md`
- Modify: `DECISIONS.md`
- Modify: `CHANGELOG.md`
- Modify: `skills/README.md`
- Modify: `scripts/project_self_check.ps1`
- Modify: `tests/project_self_check_test.ps1`

- [ ] **Step 1: 增加正式入口和长期决策**

把淘宝首图、详情页和完整套图统一指向新 Skill；记录普通宣传海报与淘宝电商套图继续保持独立链路、候选隔离和双层验收的决策。

- [ ] **Step 2: 记录版本**

Skill 首版使用 `v1.0.0｜2026-07-16`，变更记录必须说明真实任务、修改闭环、硬门禁和复测已经完成。

- [ ] **Step 3: 更新项目自检为正式状态**

要求新 Skill、agents/openai.yaml、试运行流程、模板、门禁和测试全部存在；检查 AGENTS.md 的正式入口语义。

- [ ] **Step 4: 运行最终全量验证**

Run:

```powershell
Get-ChildItem .\tests -Filter '*.ps1' | Sort-Object Name | ForEach-Object {
  & powershell -NoProfile -ExecutionPolicy Bypass -File $_.FullName
  if ($LASTEXITCODE -ne 0) { throw "Failed: $($_.Name)" }
}
python <LOCAL_USER_PATH> .\skills\creating-taobao-ecommerce-image-sets
cmd /c scripts\project_self_check.bat --no-pause
```

Expected: 所有 PowerShell 测试、Skill 校验和项目完整性自检全部 PASS，无警告、无未处理失败。

- [ ] **Step 5: 最终文件与结果检查**

确认候选只在 `temp/taobao-jobs/`，正式图片只在用户验收后进入 `outputs/`；所有版本、哈希、提示词和验收记录能够相互对应；项目文件中不存在未完成占位标记或伪造依赖。
