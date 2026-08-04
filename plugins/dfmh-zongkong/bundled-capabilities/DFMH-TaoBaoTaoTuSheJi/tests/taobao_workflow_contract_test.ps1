param()

$ErrorActionPreference = 'Stop'

$projectRootCandidate = Join-Path $PSScriptRoot '..'
if (-not (Test-Path -LiteralPath $projectRootCandidate -PathType Container)) {
    throw 'Unable to locate the project root from the test script directory.'
}

$projectRoot = (Resolve-Path -LiteralPath $projectRootCandidate).Path
$failures = New-Object 'System.Collections.Generic.List[string]'

function Decode-Text {
    param([string]$Base64)
    return [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Base64))
}

function New-Marker {
    param(
        [string]$Label,
        [string]$Value
    )

    return [pscustomobject]@{
        Label = $Label
        Value = $Value
    }
}

function Normalize-PromptTemplateText {
    param([Parameter(Mandatory = $true)][string]$Text)
    return (($Text -replace "`r`n", "`n") -replace "`r", "`n").TrimEnd("`n")
}

function Get-NormalizedUtf8Sha256 {
    param([Parameter(Mandatory = $true)][string]$Text)
    $normalized = Normalize-PromptTemplateText -Text $Text
    $bytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes($normalized)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([System.BitConverter]::ToString($sha256.ComputeHash($bytes))).Replace('-', '')
    }
    finally {
        $sha256.Dispose()
    }
}

$expectedHomePrompt = @'
进入「淘宝首页图·强视觉差异化版简化提示词模式」。

请根据刚才提炼的卖点，帮我生成淘宝首页图提示词。

要求：
1. 有几个核心卖点，就出几张首页图。
2. 每张图只讲1个卖点。
3. 每张图都要带文字：主标题、副标题、最多3个短标签。
4. 提示词要能直接用于GPT生图。
5. 首页图要有淘宝点击感，画面要强视觉、强主体、强卖点，不要太克制。
6. 产品主体必须足够大，占画面60%-75%，可以贴近画面边缘。
7. 卖点特写或局部放大也要明显，占画面20%-35%，不能只是小装饰。
8. 每张图的构图都要有明显区别，不要都做成“产品在右边，文字在左边”。
9. 构图要主动变化，可以分别使用：左大右小、右大左小、居中放大、俯视特写、低角度近景、对角线构图、主体局部出画面等方式。
10. 不要连续两张使用同一种构图方式，不要连续两张产品都放在同一侧。
11. 有些图重点放大主体，有些图重点放大卖点特写，有些图主体和特写同时放大，要有区别。
12. 主标题必须大、粗、醒目，占明显视觉区域；副标题和标签也要清晰，不要太小。
13. 画面要饱满，至少包含：产品主体、卖点证明元素、文字信息区。
14. 可以加入大号局部放大框、细线指示、场景地面细节、清扫效果、功能结构，让画面更丰富。
15. 风格统一：真实电商摄影感，高级干净，视觉冲击强，文字醒目。
16. 不要水印、二维码、价格、乱码英文。
17. 图片比例：1:1。

请按这个格式输出：

第1张：主题
卖点：
主体构图变化：
卖点放大方式：
画面饱满方式：
直接生图提示词：

第2张：主题
卖点：
主体构图变化：
卖点放大方式：
画面饱满方式：
直接生图提示词：
'@

$expectedDetailPrompt = @'
进入「淘宝详情页·饱和版简化提示词模式」。

请根据刚才提炼的卖点，帮我生成一套淘宝详情页提示词。

要求：

1. 每张详情图比例为1080×2340。
2. 一屏一张，每屏只讲1个主题。
3. 整套详情页要统一风格，但每张画面不能太像。
4. 不要每张都只是产品大图+大留白+卖点标签。
5. 画面要更饱满，有适度信息密度，但不要乱。
6. 每屏至少包含：产品主体、使用场景、卖点证明元素、文字信息区。
7. 可以加入局部放大框、细线指示、场景道具、地面细节、轻量图标、分区排版，让画面更丰富。
8. 详情页要有节奏：首屏形象、痛点场景、功能证明、细节特写、使用场景、收纳展示、总结收尾。
9. 每张图都要带文字：主标题、副标题、最多3个短标签。
10. 提示词要能直接用于GPT生图。
11. 不要写太复杂，不要堆太多文字和图标。
12. 风格统一：真实电商摄影感，高级简洁，产品清晰，文字醒目，画面饱满。
13. 不要水印、二维码、价格、乱码英文。

请输出8-12张详情图提示词，并按这个格式：

第1屏：主题
作用：
画面变化：
画面饱满方式：
直接生图提示词：

第2屏：主题
作用：
画面变化：
画面饱满方式：
直接生图提示词：
'@

function Get-ExactProperty {
    param(
        [object]$Object,
        [string]$Name
    )

    if ($null -eq $Object) {
        return $null
    }

    foreach ($property in $Object.PSObject.Properties) {
        if ($property.Name -ceq $Name) {
            return $property
        }
    }

    return $null
}

function Get-RequiredObject {
    param(
        [object]$Object,
        [string]$PropertyName,
        [string]$ContractPath,
        [string]$RelativePath,
        [System.Collections.Generic.List[string]]$FailureList
    )

    $property = Get-ExactProperty -Object $Object -Name $PropertyName
    if ($null -eq $property) {
        $FailureList.Add("$RelativePath missing required object: $ContractPath")
        return $null
    }

    if ($null -eq $property.Value -or $property.Value -isnot [System.Management.Automation.PSCustomObject]) {
        $FailureList.Add("$RelativePath must use an object at: $ContractPath")
        return $null
    }

    return $property.Value
}

function Test-ScalarDefaults {
    param(
        [object]$Object,
        [System.Collections.IDictionary]$Expected,
        [string]$ContractPath,
        [string]$RelativePath,
        [System.Collections.Generic.List[string]]$FailureList
    )

    foreach ($name in $Expected.Keys) {
        $property = Get-ExactProperty -Object $Object -Name ([string]$name)
        $fieldPath = if ([string]::IsNullOrEmpty($ContractPath)) { [string]$name } else { "$ContractPath.$name" }
        if ($null -eq $property) {
            $FailureList.Add("$RelativePath missing required field: $fieldPath")
        }
        elseif (-not [object]::Equals($property.Value, $Expected[$name])) {
            $FailureList.Add("$RelativePath has incorrect default value at: $fieldPath")
        }
    }
}

function Test-ArrayProperty {
    param(
        [object]$Object,
        [string]$PropertyName,
        [string]$ContractPath,
        [bool]$RequireEmpty,
        [string]$RelativePath,
        [System.Collections.Generic.List[string]]$FailureList
    )

    $property = Get-ExactProperty -Object $Object -Name $PropertyName
    if ($null -eq $property) {
        $FailureList.Add("$RelativePath missing required array: $ContractPath")
        return
    }

    if ($property.Value -isnot [System.Array]) {
        $FailureList.Add("$RelativePath must use an array at: $ContractPath")
        return
    }

    if ($RequireEmpty -and @($property.Value).Count -ne 0) {
        $FailureList.Add("$RelativePath default array must be empty at: $ContractPath")
    }
}

function Test-EmptyObjectProperty {
    param(
        [object]$Object,
        [string]$PropertyName,
        [string]$ContractPath,
        [string]$RelativePath,
        [System.Collections.Generic.List[string]]$FailureList
    )

    $propertyValue = Get-RequiredObject -Object $Object -PropertyName $PropertyName -ContractPath $ContractPath -RelativePath $RelativePath -FailureList $FailureList
    if ($null -ne $propertyValue -and @($propertyValue.PSObject.Properties).Count -ne 0) {
        $FailureList.Add("$RelativePath default object must be empty at: $ContractPath")
    }
}

function Test-ItemContractFields {
    param(
        [object]$Job,
        [string]$BranchName,
        [string]$ItemPropertyName = 'items',
        [string[]]$RequiredFields,
        [string]$RelativePath,
        [System.Collections.Generic.List[string]]$FailureList
    )

    $branchProperty = Get-ExactProperty -Object $Job -Name $BranchName
    if ($null -eq $branchProperty -or $null -eq $branchProperty.Value) {
        $FailureList.Add("$RelativePath missing object contract: $BranchName")
        return
    }

    $itemsProperty = Get-ExactProperty -Object $branchProperty.Value -Name $ItemPropertyName
    if ($null -eq $itemsProperty) {
        $FailureList.Add("$RelativePath missing array contract: $BranchName.$ItemPropertyName")
        return
    }

    if ($itemsProperty.Value -isnot [System.Array]) {
        $FailureList.Add("$RelativePath contract must use an array: $BranchName.$ItemPropertyName")
        return
    }

    $items = @($itemsProperty.Value)
    if ($items.Count -eq 0) {
        return
    }

    for ($index = 0; $index -lt $items.Count; $index++) {
        $item = $items[$index]
        if ($null -eq $item -or $item -isnot [System.Management.Automation.PSCustomObject]) {
            $FailureList.Add("$RelativePath $BranchName.$ItemPropertyName[$index] must be an object")
            continue
        }

        $availableFields = @($item.PSObject.Properties | ForEach-Object { $_.Name })
        foreach ($field in $RequiredFields) {
            if ($availableFields -cnotcontains $field) {
                $FailureList.Add("$RelativePath $BranchName.$ItemPropertyName[$index] missing required field: $field")
            }
        }
    }
}

$workflowRelativePath = 'workflows\TAOBAO_ECOMMERCE_IMAGE_SET_PILOT.md'
$jobRelativePath = 'templates\TAOBAO_ECOMMERCE_JOB.json'
$sellingPointItemFields = @(
    'id',
    'purchaseRole',
    'shortTitle',
    'buyerBenefit',
    'copy',
    'visualProof',
    'claimBoundary',
    'evidenceType',
    'evidenceReference',
    'homeEligible',
    'detailEligible',
    'verified'
)
$promptSetItemFields = @(
    'id',
    'type',
    'version',
    'claimId',
    'roleId',
    'referenceSha256',
    'structureLockSha256',
    'viewConstraint',
    'compositionFamily',
    'proofPresentation',
    'proofAddsNewInformation',
    'cardPath',
    'promptPath',
    'width',
    'height',
    'status'
)
$productAssetItemFields = @(
    'id',
    'path',
    'sourcePath',
    'fileName',
    'bytes',
    'sha256',
    'authorizationConfirmed',
    'authorizationStatement'
)
$candidateItemFields = @(
    'id',
    'type',
    'version',
    'promptId',
    'path',
    'acceptancePath',
    'sha256',
    'bytes',
    'width',
    'height',
    'status',
    'quality'
)
$historyItemFields = @(
    'at',
    'actor',
    'action',
    'itemId',
    'version',
    'statement'
)
$productFactItemFields = @(
    'id',
    'name',
    'value',
    'evidenceType',
    'evidenceReference',
    'verified'
)
$promotionFileItemFields = @(
    'id',
    'path',
    'fileName',
    'bytes',
    'sha256',
    'type',
    'version'
)
$styleLockFields = @(
    'brand',
    'productColor',
    'productStructure',
    'productMaterial',
    'productProportion',
    'productAccessories',
    'corePalette',
    'typography',
    'informationHierarchy',
    'lighting',
    'photographyStyle',
    'forbiddenContent',
    'benchmarkReportPath',
    'styleDirection',
    'proofIntegrationRules',
    'forbiddenLayouts'
)
$benchmarkReferenceFields = @(
    'id',
    'platform',
    'url',
    'capturedAt',
    'evidencePath',
    'observation'
)
$structureLockFields = @(
    'referenceAssetId',
    'referencePath',
    'referenceSha256',
    'recordPath',
    'confirmed',
    'immutableComponents',
    'connectionTopology',
    'relativeGeometry',
    'visibleViewBoundary',
    'allowedVariations',
    'forbiddenVariations'
)
$workflowItemContractMarkers = @(
    (New-Marker -Label 'shared image generation channel standard' -Value 'shared/IMAGE_GENERATION_CHANNEL_STANDARD.md'),
    (New-Marker -Label 'shared product asset fidelity standard' -Value 'shared/PRODUCT_ASSET_FIDELITY_STANDARD.md'),
    (New-Marker -Label 'sellingPoints item contract' -Value 'sellingPoints.items'),
    (New-Marker -Label 'promptSet item contract' -Value 'promptSet.items'),
    (New-Marker -Label 'product.assets item contract' -Value (Decode-Text 'YHByb2R1Y3QuYXNzZXRzYCDmr4/kuKogaXRlbQ==')),
    (New-Marker -Label 'product.facts item contract' -Value (Decode-Text 'YHByb2R1Y3QuZmFjdHNgIOavj+S4qiBpdGVt')),
    (New-Marker -Label 'candidates item contract' -Value (Decode-Text 'YGNhbmRpZGF0ZXNgIOavj+S4qiBpdGVt')),
    (New-Marker -Label 'history item contract' -Value (Decode-Text 'YGhpc3RvcnlgIOavj+S4qiBpdGVt')),
    (New-Marker -Label 'promotion.files item contract' -Value (Decode-Text 'YHByb21vdGlvbi5maWxlc2Ag5q+P5LiqIGl0ZW0=')),
    (New-Marker -Label 'promptSet.styleLock fixed fields' -Value (Decode-Text 'YHByb21wdFNldC5zdHlsZUxvY2tgIOWbuuWumuWtl+autQ==')),
    (New-Marker -Label 'promptSet.structureLock fixed fields' -Value 'promptSet.structureLock'),
    (New-Marker -Label 'market benchmark contract' -Value 'marketBenchmark.references'),
    (New-Marker -Label 'market benchmark style decision' -Value 'marketBenchmark.styleDecision'),
    (New-Marker -Label 'runtime item validation' -Value (Decode-Text '6L+Q6KGM5pe26Zeo56aB6YCQ6aG55qCh6aqM'))
)
foreach ($field in $sellingPointItemFields) {
    $workflowItemContractMarkers += New-Marker -Label "sellingPoints item field $field" -Value $field
}
foreach ($field in $promptSetItemFields) {
    $workflowItemContractMarkers += New-Marker -Label "promptSet item field $field" -Value $field
}
foreach ($field in $productAssetItemFields) {
    $workflowItemContractMarkers += New-Marker -Label "product.assets item field $field" -Value $field
}
foreach ($field in $candidateItemFields) {
    $workflowItemContractMarkers += New-Marker -Label "candidates item field $field" -Value $field
}
foreach ($field in $historyItemFields) {
    $workflowItemContractMarkers += New-Marker -Label "history item field $field" -Value $field
}
foreach ($field in $productFactItemFields) {
    $workflowItemContractMarkers += New-Marker -Label "product.facts item field $field" -Value $field
}
foreach ($field in $promotionFileItemFields) {
    $workflowItemContractMarkers += New-Marker -Label "promotion.files item field $field" -Value $field
}
foreach ($field in $styleLockFields) {
    $workflowItemContractMarkers += New-Marker -Label "promptSet.styleLock field $field" -Value $field
}
foreach ($field in $structureLockFields) {
    $workflowItemContractMarkers += New-Marker -Label "promptSet.structureLock field $field" -Value $field
}
foreach ($field in $benchmarkReferenceFields) {
    $workflowItemContractMarkers += New-Marker -Label "marketBenchmark reference field $field" -Value $field
}

$contracts = @(
    [pscustomobject]@{
        Name = 'workflow'
        RelativePath = $workflowRelativePath
        Markers = @(
            (New-Marker -Label 'per-image acceptance' -Value (Decode-Text '6YCQ5byg6aqM5pS2')),
            (New-Marker -Label 'whole-set consistency acceptance' -Value (Decode-Text '5pW05aWX5LiA6Ie05oCn6aqM5pS2')),
            (New-Marker -Label 'standard home terminology' -Value (Decode-Text '5reY5a6d6aaW5Zu+57uE77yI6aaW6aG15Zu+77yJ')),
            (New-Marker -Label 'first actual queue item' -Value (Decode-Text '6aaW5Liq5a6e6ZmF6Zif5YiX6aG5')),
            (New-Marker -Label 'home or full style anchor' -Value 'home/full=H01'),
            (New-Marker -Label 'detail style anchor' -Value 'detail=D01'),
            (New-Marker -Label 'selling point exception below five' -Value (Decode-Text '5bCR5LqONemhueeahOS+i+Wklg==')),
            (New-Marker -Label 'detail screen exception below eight' -Value (Decode-Text '5bCR5LqOOOWxj+eahOS+i+Wklg==')),
            (New-Marker -Label 'no promotion without explicit Emperor acceptance' -Value (Decode-Text '5pyq57uP5bid546L5piO56Gu6aqM5pS2')),
            (New-Marker -Label 'general promotional poster routing' -Value (Decode-Text '5pmu6YCa5a6j5Lyg5rW35oql6L2s5YWl')),
            (New-Marker -Label 'general promotional poster Skill path' -Value 'skills/creating-promotional-posters/SKILL.md'),
            (New-Marker -Label 'Taobao candidate job path' -Value 'temp/taobao-jobs/<job-id>/'),
            (New-Marker -Label 'mechanism legibility gate' -Value (Decode-Text '5py65qKw5YWz57O75Y+v5Yik6K+7')),
            (New-Marker -Label 'relative proportion gate' -Value (Decode-Text '55u45a+55q+U5L6L5Z+65YeG')),
             (New-Marker -Label 'product structure fingerprint' -Value (Decode-Text '5Lqn5ZOB57uT5p6E5oyH57q5')),
             (New-Marker -Label 'visible view boundary' -Value (Decode-Text '5Y+v6KeB6KeG6KeS6L6555WM')),
             (New-Marker -Label 'no inferred invisible structure' -Value (Decode-Text '5LiN5Y+v6KeB57uT5p6E5LiN5b6X6Ieq55Sx6KGl5YWo')),
             (New-Marker -Label 'per-image reference binding' -Value (Decode-Text '6YCQ5Zu+5Y+C6ICD57uR5a6a')),
             (New-Marker -Label 'independent structure consistency field' -Value 'structureConsistency'),
             (New-Marker -Label 'core purchase driver role' -Value 'core_purchase_driver'),
             (New-Marker -Label 'supporting benefit role' -Value 'supporting_benefit'),
             (New-Marker -Label 'appearance differentiator role' -Value 'appearance_differentiator'),
             (New-Marker -Label 'appearance-led category exception' -Value 'appearance_led_exception'),
             (New-Marker -Label 'single conversation full set policy' -Value 'single_conversation_full_set'),
             (New-Marker -Label 'internal ImageGen channel' -Value 'codex_internal_image_gen'),
             (New-Marker -Label 'stateless reference-bound policy' -Value 'stateless_reference_bound'),
             (New-Marker -Label 'current job and version authorization' -Value 'current_job_version_authorization'),
             (New-Marker -Label 'internal reference binding method' -Value 'referenced_image_paths'),
             (New-Marker -Label 'internal direct tool action' -Value 'direct_tool_call'),
             (New-Marker -Label 'automatic batch execution mode' -Value 'batch_after_style_anchor'),
             (New-Marker -Label 'anchor and final set review policy' -Value 'anchor_once_batch_qc_final_set_review'),
             (New-Marker -Label 'remaining queue authorization scope' -Value 'remaining_queue_after_anchor'),
             (New-Marker -Label 'no per-image Emperor approval' -Value (Decode-Text '5LiN5b6X6YCQ5byg6K+35rGC5bid546L56Gu6K6k')),
             (New-Marker -Label 'per-image chat session binding' -Value 'assetTransfer.chatSessionReference'),
             (New-Marker -Label 'later items reuse existing conversation' -Value 'reused_existing'),
             (New-Marker -Label 'Emperor-fixed home prompt version' -Value 'emperor-fixed-v1'),
             (New-Marker -Label 'home prompt lock file' -Value 'templates/TAOBAO_HOME_IMAGE_PROMPT.lock.json'),
             (New-Marker -Label 'home prompt exact-text rule' -Value (Decode-Text '5LiN5b6X5pS55YaZ44CB5Yig5YeP44CB5omp5bGV5oiW5pu/5o2i')),
             (New-Marker -Label 'Emperor-fixed detail prompt version' -Value 'emperor-fixed-detail-v1'),
             (New-Marker -Label 'detail prompt lock file' -Value 'templates/TAOBAO_DETAIL_IMAGE_PROMPT.lock.json')
        ) + $workflowItemContractMarkers
    },
    [pscustomobject]@{
        Name = 'job template'
        RelativePath = $jobRelativePath
        Markers = @()
    },
    [pscustomobject]@{
        Name = 'stroller category profile'
        RelativePath = 'templates\taobao-category-profiles\stroller-v1.json'
        Markers = @(
            (New-Marker -Label 'stroller profile id' -Value '"id": "stroller"'),
            (New-Marker -Label 'frozen stroller state' -Value '"state": "frozen"'),
            (New-Marker -Label 'stroller structure checks' -Value '"structureChecks"'),
            (New-Marker -Label 'no per-image approval pattern' -Value '"per_image_emperor_approval"')
        )
    },
    [pscustomobject]@{
        Name = 'shoes category profile'
        RelativePath = 'templates\taobao-category-profiles\shoes-v1.json'
        Markers = @(
            (New-Marker -Label 'shoes profile id' -Value '"id": "shoes"'),
            (New-Marker -Label 'pilot shoes state' -Value '"state": "pilot"'),
            (New-Marker -Label 'shoe shot families' -Value '"shotFamilies"'),
            (New-Marker -Label 'isolated box prohibition' -Value '"isolated_floating_detail_box"'),
            (New-Marker -Label 'shoe microtext strategy' -Value '"microtextStrategy"'),
            (New-Marker -Label 'forbid invented product microtext' -Value '"never_invent_product_microtext"')
        )
    },
    [pscustomobject]@{
        Name = 'shoes page planner prompt'
        RelativePath = 'templates\TAOBAO_SHOES_PAGE_PLANNER_PROMPT.md'
        Markers = @(
            (New-Marker -Label 'purchase outcome priority' -Value (Decode-Text '6LSt5Lmw57uT5p6c')),
            (New-Marker -Label 'shoe shot family routing' -Value (Decode-Text '6Z6L57G76ZWc5aS05a625peP'))
        )
    },
    [pscustomobject]@{
        Name = 'shoes image prompt'
        RelativePath = 'templates\TAOBAO_SHOES_IMAGE_PROMPT.md'
        Markers = @(
            (New-Marker -Label 'product fidelity layer' -Value (Decode-Text '5Lqn5ZOB55yf5a6e5oCn5bGC')),
            (New-Marker -Label 'local repair rule' -Value (Decode-Text '5bGA6YOo6L+U5L+u')),
            (New-Marker -Label 'microtext risk rule' -Value (Decode-Text '5bCP5Z6L5paH5a2X6aOO6Zmp')),
            (New-Marker -Label 'risk avoidance route' -Value (Decode-Text '6KeG6KeS44CB6YGu5oyh44CB5pmv5rex')),
            (New-Marker -Label 'deterministic source patch' -Value (Decode-Text '5Y6f57Sg5p2Q56Gu5a6a5oCn5ZCI5oiQ'))
        )
    },
    [pscustomobject]@{
        Name = 'apparel category profile'
        RelativePath = 'templates\taobao-category-profiles\apparel-v1.json'
        Markers = @(
            (New-Marker -Label 'apparel profile id' -Value '"id": "apparel"'),
            (New-Marker -Label 'pilot apparel state' -Value '"state": "pilot"'),
            (New-Marker -Label 'garment identity checks' -Value '"garmentIdentityChecks"'),
            (New-Marker -Label 'full silhouette priority' -Value '"full_silhouette_hero"'),
            (New-Marker -Label 'unsupported slimming claim prohibition' -Value '"unsupported_slimming_claim"'),
            (New-Marker -Label 'isolated apparel detail box prohibition' -Value '"isolated_detail_box_in_blank_lower_half"')
        )
    },
    [pscustomobject]@{
        Name = 'apparel page planner prompt'
        RelativePath = 'templates\TAOBAO_APPAREL_PAGE_PLANNER_PROMPT.md'
        Markers = @(
            (New-Marker -Label 'garment silhouette purchase result' -Value (Decode-Text '56m/552A5buT5b2i')),
            (New-Marker -Label 'apparel shot family routing' -Value (Decode-Text '5pyN6KOF6ZWc5aS05a625peP')),
            (New-Marker -Label 'article-derived page rhythm' -Value (Decode-Text '5YWo6Lqr5buT5b2i5Li76KeG6KeJ4oCU5Y2W54K55oC76KeI4oCU5q2j6Z2i57uT5p6E4oCU57uG6IqC4oCU54mI5Z6L4oCU6Z2i5paZ4oCU5Zy65pmv56m/5pCt4oCU5oC757uT'))
        )
    },
    [pscustomobject]@{
        Name = 'apparel image prompt'
        RelativePath = 'templates\TAOBAO_APPAREL_IMAGE_PROMPT.md'
        Markers = @(
            (New-Marker -Label 'garment identity lock' -Value (Decode-Text '5pyN6KOF6Lqr5Lu96ZSB')),
            (New-Marker -Label 'natural human anatomy rule' -Value (Decode-Text '5Lq65L2T5q+U5L6L6Ieq54S2')),
            (New-Marker -Label 'claim evidence boundary' -Value (Decode-Text '5a6j56ew6K+B5o2u6L6555WM')),
            (New-Marker -Label 'integrated detail proof' -Value (Decode-Text '5LiN5b6X5oqK5bGA6YOo57uG6IqC5YGa5oiQ5LiO5Li76KeG5Zu+6ISx6IqC55qE5oKs5rWu6KOF6aWw'))
        )
    },
    [pscustomobject]@{
        Name = 'selling points prompt'
        RelativePath = 'templates\TAOBAO_SELLING_POINTS_PROMPT.md'
        Markers = @(
            (New-Marker -Label 'five to eight selling points' -Value (Decode-Text 'NS045Liq')),
            (New-Marker -Label 'do not generate images directly' -Value (Decode-Text '5LiN6KaB55u05o6l55Sf5Zu+')),
            (New-Marker -Label 'selling-point number' -Value (Decode-Text '5Y2W54K557yW5Y+3')),
            (New-Marker -Label 'short title' -Value (Decode-Text '55+t5qCH6aKY')),
            (New-Marker -Label 'evidence source' -Value (Decode-Text '6K+B5o2u5p2l5rqQ')),
            (New-Marker -Label 'suitable placement' -Value (Decode-Text '6YCC55So5L2N572u')),
            (New-Marker -Label 'no fabrication' -Value (Decode-Text '56aB5q2i57yW6YCg')),
            (New-Marker -Label 'home-detail allocation' -Value (Decode-Text '6aaW5Zu+57uEL+ivpuaDhemhteWIhumFjQ==')),
            (New-Marker -Label 'verified items only' -Value (Decode-Text '5Y+q6L6T5Ye65bey6aqM6K+B6aG5')),
            (New-Marker -Label 'evidence gaps' -Value (Decode-Text '6K+B5o2u57y65Y+j')),
            (New-Marker -Label 'pause final confirmation' -Value (Decode-Text '5pqC5YGc5pyA57uI56Gu6K6k')),
            (New-Marker -Label 'exception below five' -Value (Decode-Text '5bCR5LqONemhueeahOS+i+Wklg==')),
            (New-Marker -Label 'do not pad with unsupported items' -Value (Decode-Text '56aB5q2i55SoIHVuc3VwcG9ydGVkIOmhueWHkeaVsA==')),
             (New-Marker -Label 'selling point evidenceType contract' -Value (Decode-Text 'YHNlbGxpbmdQb2ludHMuaXRlbXMuZXZpZGVuY2VUeXBlYA==')),
             (New-Marker -Label 'allowed selling point evidence types' -Value (Decode-Text '5LuF5YWB6K64IGltYWdlX3Zpc2libGXjgIF1c2VyX2NvbmZpcm1lZOOAgWRvY3VtZW50X3Byb3Zlbg==')),
             (New-Marker -Label 'unsupported only as evidence gap' -Value (Decode-Text 'dW5zdXBwb3J0ZWQg5Y+q5YWB6K645L2c5Li654us56uL6K+B5o2u57y65Y+j54q25oCB5oiW5o+P6L+w')),
             (New-Marker -Label 'core purchase driver role' -Value 'core_purchase_driver'),
             (New-Marker -Label 'supporting benefit role' -Value 'supporting_benefit'),
             (New-Marker -Label 'appearance differentiator role' -Value 'appearance_differentiator'),
             (New-Marker -Label 'appearance-led category exception' -Value 'appearance_led_exception'),
             (New-Marker -Label 'buyer benefit field' -Value 'buyerBenefit'),
             (New-Marker -Label 'visual proof field' -Value 'visualProof'),
             (New-Marker -Label 'claim boundary field' -Value 'claimBoundary')
         )
    },
    [pscustomobject]@{
        Name = 'home image prompt'
        RelativePath = 'templates\TAOBAO_HOME_IMAGE_PROMPT.md'
        Markers = @()
    },
    [pscustomobject]@{
        Name = 'home image prompt runtime lock gate'
        RelativePath = 'scripts\taobao_workflow_gate.ps1'
        Markers = @(
            (New-Marker -Label 'runtime fixed-prompt assertion' -Value 'Assert-FixedHomePromptTemplate'),
            (New-Marker -Label 'runtime fixed-prompt version' -Value 'emperor-fixed-v1'),
            (New-Marker -Label 'runtime normalized prompt hash field' -Value 'normalizedUtf8Sha256')
        )
    },
    [pscustomobject]@{
        Name = 'detail image prompt'
        RelativePath = 'templates\TAOBAO_DETAIL_IMAGE_PROMPT.md'
        Markers = @()
    },
    [pscustomobject]@{
        Name = 'detail image prompt runtime lock gate'
        RelativePath = 'scripts\taobao_workflow_gate.ps1'
        Markers = @(
            (New-Marker -Label 'runtime fixed-detail-prompt assertion' -Value 'Assert-FixedDetailPromptTemplate'),
            (New-Marker -Label 'runtime fixed-detail-prompt version' -Value 'emperor-fixed-detail-v1')
        )
    },
    [pscustomobject]@{
        Name = 'acceptance contract'
        RelativePath = 'tests\TAOBAO_ECOMMERCE_IMAGE_SET_ACCEPTANCE.md'
        Markers = @(
            (New-Marker -Label 'product consistency' -Value (Decode-Text '5Lqn5ZOB5LiA6Ie05oCn')),
            (New-Marker -Label 'image-text correspondence' -Value (Decode-Text '5Zu+5paH5a+55bqU')),
            (New-Marker -Label 'whole-set style' -Value (Decode-Text '5pW05aWX6aOO5qC8')),
            (New-Marker -Label 'prompt-image traceability' -Value (Decode-Text '5o+Q56S66K+N5LiO5Zu+54mH')),
            (New-Marker -Label 'task information' -Value (Decode-Text '5Lu75Yqh5L+h5oGv')),
            (New-Marker -Label 'selling-point evidence' -Value (Decode-Text '5Y2W54K56K+B5o2u')),
            (New-Marker -Label 'per-image acceptance' -Value (Decode-Text '6YCQ5byg6aqM5pS2')),
            (New-Marker -Label 'whole-set consistency acceptance' -Value (Decode-Text '5pW05aWX5LiA6Ie05oCn6aqM5pS2')),
            (New-Marker -Label 'revision loop' -Value (Decode-Text '5L+u5pS56Zet546v')),
            (New-Marker -Label 'issue record' -Value (Decode-Text '6Zeu6aKY6K6w5b2V')),
            (New-Marker -Label 'Emperor confirmation' -Value (Decode-Text '5bid546L56Gu6K6k')),
            (New-Marker -Label 'formal promotion' -Value (Decode-Text '5q2j5byP5pmL57qn')),
            (New-Marker -Label 'blank template is not passing evidence' -Value (Decode-Text '56m655m95qih5p2/5LiN5b6X5L2c5Li66YCa6L+H6K+B5o2u')),
            (New-Marker -Label 'scope values' -Value 'scope=home/detail/full'),
            (New-Marker -Label 'cross-scope checks only for full' -Value (Decode-Text '5LuFIGZ1bGwg5ZCv55So')),
            (New-Marker -Label 'not applicable with reason' -Value (Decode-Text '5LiN6YCC55So5Y+K5Y6f5Zug')),
            (New-Marker -Label 'must not skip blank' -Value (Decode-Text '5LiN5b6X55WZ56m66Lez6L+H')),
            (New-Marker -Label 'standard home terminology' -Value (Decode-Text '5reY5a6d6aaW5Zu+57uE77yI6aaW6aG15Zu+77yJ')),
             (New-Marker -Label 'mechanism legibility acceptance' -Value (Decode-Text '5py65qKw5YWz57O75Y+v5Yik6K+7')),
             (New-Marker -Label 'relative proportion acceptance' -Value (Decode-Text '55u45a+55q+U5L6L5YGP5beu')),
             (New-Marker -Label 'structure topology acceptance' -Value (Decode-Text '5Lqn5ZOB57uT5p6E5ouT5omR5LiA6Ie05oCn')),
             (New-Marker -Label 'independent structure flag' -Value 'structureConsistency'),
             (New-Marker -Label 'detail four-layer acceptance' -Value 'fourLayerCompleteness'),
             (New-Marker -Label 'detail density acceptance' -Value 'detailContentDensity'),
             (New-Marker -Label 'single chat session acceptance' -Value 'singleChatSession'),
             (New-Marker -Label 'benchmark alignment acceptance' -Value 'benchmarkAlignment'),
             (New-Marker -Label 'category fit acceptance' -Value 'categoryFit'),
             (New-Marker -Label 'proof integration acceptance' -Value 'visualIntegration'),
             (New-Marker -Label 'proof relevance acceptance' -Value 'proofRelevance'),
             (New-Marker -Label 'lower half continuity acceptance' -Value 'lowerHalfContinuity'),
             (New-Marker -Label 'module novelty acceptance' -Value 'moduleNovelty'),
             (New-Marker -Label 'isolated floating detail box ban' -Value 'isolated_floating_detail_box')
         )
    },
    [pscustomobject]@{
        Name = 'design specification'
        RelativePath = 'docs\superpowers\specs\2026-07-16-taobao-ecommerce-image-set-workflow-design.md'
        Markers = @(
            (New-Marker -Label 'standard home terminology' -Value (Decode-Text '5reY5a6d6aaW5Zu+57uE77yI6aaW6aG15Zu+77yJ')),
            (New-Marker -Label 'first actual queue item' -Value (Decode-Text '6aaW5Liq5a6e6ZmF6Zif5YiX6aG5')),
            (New-Marker -Label 'home or full style anchor' -Value 'home/full=H01'),
            (New-Marker -Label 'detail style anchor' -Value 'detail=D01'),
            (New-Marker -Label 'selling point exception below five' -Value (Decode-Text '5bCR5LqONemhueeahOS+i+Wklg==')),
            (New-Marker -Label 'detail screen exception below eight' -Value (Decode-Text '5bCR5LqOOOWxj+eahOS+i+Wklg==')),
            (New-Marker -Label 'Emperor-fixed home prompt version' -Value 'emperor-fixed-v1'),
            (New-Marker -Label 'role field' -Value 'roleId'),
            (New-Marker -Label 'asset item contract' -Value (Decode-Text 'YHByb2R1Y3QuYXNzZXRzYCDmr4/kuKogaXRlbQ==')),
            (New-Marker -Label 'candidate item contract' -Value (Decode-Text 'YGNhbmRpZGF0ZXNgIOavj+S4qiBpdGVt')),
            (New-Marker -Label 'history item contract' -Value (Decode-Text 'YGhpc3RvcnlgIOavj+S4qiBpdGVt')),
            (New-Marker -Label 'product facts item contract' -Value (Decode-Text 'YHByb2R1Y3QuZmFjdHNgIOavj+S4qiBpdGVt')),
            (New-Marker -Label 'promotion files item contract' -Value (Decode-Text 'YHByb21vdGlvbi5maWxlc2Ag5q+P5LiqIGl0ZW0=')),
            (New-Marker -Label 'style lock fixed fields' -Value (Decode-Text 'YHByb21wdFNldC5zdHlsZUxvY2tgIOWbuuWumuWtl+autQ==')),
            (New-Marker -Label 'unsupported only as evidence gap' -Value (Decode-Text 'dW5zdXBwb3J0ZWQg5Y+q5YWB6K645L2c5Li654us56uL6K+B5o2u57y65Y+j54q25oCB5oiW5o+P6L+w'))
        )
    },
    [pscustomobject]@{
        Name = 'implementation plan'
        RelativePath = 'docs\superpowers\plans\2026-07-16-taobao-ecommerce-image-set-pilot.md'
        Markers = @(
            (New-Marker -Label 'standard home terminology' -Value (Decode-Text '5reY5a6d6aaW5Zu+57uE77yI6aaW6aG15Zu+77yJ')),
            (New-Marker -Label 'first actual queue item' -Value (Decode-Text '6aaW5Liq5a6e6ZmF6Zif5YiX6aG5')),
            (New-Marker -Label 'home or full style anchor' -Value 'home/full=H01'),
            (New-Marker -Label 'detail style anchor' -Value 'detail=D01'),
            (New-Marker -Label 'selling point exception below five' -Value (Decode-Text '5bCR5LqONemhueeahOS+i+Wklg==')),
            (New-Marker -Label 'detail screen exception below eight' -Value (Decode-Text '5bCR5LqOOOWxj+eahOS+i+Wklg==')),
            (New-Marker -Label 'role field' -Value 'roleId'),
            (New-Marker -Label 'asset item contract' -Value (Decode-Text 'YHByb2R1Y3QuYXNzZXRzYCDmr4/kuKogaXRlbQ==')),
            (New-Marker -Label 'candidate item contract' -Value (Decode-Text 'YGNhbmRpZGF0ZXNgIOavj+S4qiBpdGVt')),
            (New-Marker -Label 'history item contract' -Value (Decode-Text 'YGhpc3RvcnlgIOavj+S4qiBpdGVt')),
            (New-Marker -Label 'product facts item contract' -Value (Decode-Text 'YHByb2R1Y3QuZmFjdHNgIOavj+S4qiBpdGVt')),
            (New-Marker -Label 'promotion files item contract' -Value (Decode-Text 'YHByb21vdGlvbi5maWxlc2Ag5q+P5LiqIGl0ZW0=')),
            (New-Marker -Label 'style lock fixed fields' -Value (Decode-Text 'YHByb21wdFNldC5zdHlsZUxvY2tgIOWbuuWumuWtl+autQ==')),
            (New-Marker -Label 'unsupported only as evidence gap' -Value (Decode-Text 'dW5zdXBwb3J0ZWQg5Y+q5YWB6K645L2c5Li654us56uL6K+B5o2u57y65Y+j54q25oCB5oiW5o+P6L+w'))
        )
    }
)

$forbiddenContracts = @(
    [pscustomobject]@{
        RelativePath = 'docs\superpowers\specs\2026-07-16-taobao-ecommerce-image-set-workflow-design.md'
        Markers = @(
            (New-Marker -Label 'category-specific cleaning effect' -Value (Decode-Text '5riF5omr5pWI5p6c'))
        )
    },
    [pscustomobject]@{
        RelativePath = 'templates\TAOBAO_DETAIL_IMAGE_PROMPT.md'
        Markers = @(
            (New-Marker -Label 'unconditional home-set style lock' -Value (Decode-Text '5LiO5reY5a6d6aaW5Zu+57uE77yI6aaW6aG15Zu+77yJ5YWx55So5ZCM5LiA5Lqn5ZOB5ZKM6aOO5qC86ZSB5a6a')),
            (New-Marker -Label 'legacy detail scope value' -Value (Decode-Text 'ZGV0YWlsLW9ubHk='))
        )
    },
    [pscustomobject]@{
        RelativePath = 'templates\TAOBAO_SELLING_POINTS_PROMPT.md'
        Markers = @(
            (New-Marker -Label 'unsupported as selling point evidenceType' -Value (Decode-Text 'YGRvY3VtZW50X3Byb3ZlbmAg5oiWIGB1bnN1cHBvcnRlZGA='))
        )
    },
    [pscustomobject]@{
        RelativePath = 'workflows\TAOBAO_ECOMMERCE_IMAGE_SET_PILOT.md'
        Markers = @(
            (New-Marker -Label 'legacy detail scope value' -Value (Decode-Text 'ZGV0YWlsLW9ubHk='))
        )
    },
    [pscustomobject]@{
        RelativePath = 'docs\superpowers\specs\2026-07-16-taobao-ecommerce-image-set-workflow-design.md'
        Markers = @(
            (New-Marker -Label 'legacy detail scope value' -Value (Decode-Text 'ZGV0YWlsLW9ubHk='))
        )
    },
    [pscustomobject]@{
        RelativePath = 'docs\superpowers\plans\2026-07-16-taobao-ecommerce-image-set-pilot.md'
        Markers = @(
            (New-Marker -Label 'legacy detail scope value' -Value (Decode-Text 'ZGV0YWlsLW9ubHk='))
        )
    }
)

foreach ($contract in $contracts) {
    $fullPath = Join-Path $projectRoot $contract.RelativePath
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        $failures.Add("Missing required file: $($contract.RelativePath)")
        continue
    }

    $content = Get-Content -LiteralPath $fullPath -Raw -Encoding UTF8
    foreach ($marker in $contract.Markers) {
        if (-not $content.Contains($marker.Value)) {
            $failures.Add("$($contract.RelativePath) missing required marker [$($marker.Label)]")
        }
    }
}

foreach ($contract in $forbiddenContracts) {
    $fullPath = Join-Path $projectRoot $contract.RelativePath
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        $failures.Add("Missing required file for forbidden-marker check: $($contract.RelativePath)")
        continue
    }

    $content = Get-Content -LiteralPath $fullPath -Raw -Encoding UTF8
    foreach ($marker in $contract.Markers) {
        if ($content.Contains($marker.Value)) {
            $failures.Add("$($contract.RelativePath) contains forbidden marker [$($marker.Label)]")
        }
    }
}

$homePromptRelativePath = 'templates\TAOBAO_HOME_IMAGE_PROMPT.md'
$homePromptFullPath = Join-Path $projectRoot $homePromptRelativePath
$homePromptLockRelativePath = 'templates\TAOBAO_HOME_IMAGE_PROMPT.lock.json'
$homePromptLockFullPath = Join-Path $projectRoot $homePromptLockRelativePath
$expectedHomePromptHash = '1A2304654AF97B4883ABF2FA2BE08DEB3F0292399552723D114CD18A63659A89'
if (Test-Path -LiteralPath $homePromptFullPath -PathType Leaf) {
    $actualHomePrompt = Get-Content -LiteralPath $homePromptFullPath -Raw -Encoding UTF8
    $actualHomePromptHash = Get-NormalizedUtf8Sha256 -Text $actualHomePrompt
    if (-not [string]::Equals($actualHomePromptHash, $expectedHomePromptHash, [System.StringComparison]::Ordinal)) {
        $failures.Add("$homePromptRelativePath must exactly match the Emperor-approved fixed prompt; additions, deletions, and rewrites are forbidden.")
    }
}
if (-not (Test-Path -LiteralPath $homePromptLockFullPath -PathType Leaf)) {
    $failures.Add("Missing required file: $homePromptLockRelativePath")
}
else {
    try {
        $homePromptLock = Get-Content -LiteralPath $homePromptLockFullPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ([string]$homePromptLock.templatePath -cne 'templates/TAOBAO_HOME_IMAGE_PROMPT.md') {
            $failures.Add("$homePromptLockRelativePath has an invalid templatePath.")
        }
        if ([string]$homePromptLock.version -cne 'emperor-fixed-v1') {
            $failures.Add("$homePromptLockRelativePath has an invalid version.")
        }
        if ($homePromptLock.immutable -isnot [bool] -or $homePromptLock.immutable -ne $true) {
            $failures.Add("$homePromptLockRelativePath must set immutable=true.")
        }
        if (-not [string]::Equals([string]$homePromptLock.normalizedUtf8Sha256, $expectedHomePromptHash, [System.StringComparison]::Ordinal)) {
            $failures.Add("$homePromptLockRelativePath hash does not match the Emperor-approved fixed prompt.")
        }
    }
    catch {
        $failures.Add("$homePromptLockRelativePath is not valid JSON: $($_.Exception.Message)")
    }
}

$detailPromptRelativePath = 'templates\TAOBAO_DETAIL_IMAGE_PROMPT.md'
$detailPromptFullPath = Join-Path $projectRoot $detailPromptRelativePath
$detailPromptLockRelativePath = 'templates\TAOBAO_DETAIL_IMAGE_PROMPT.lock.json'
$detailPromptLockFullPath = Join-Path $projectRoot $detailPromptLockRelativePath
$expectedDetailPromptHash = '9F7C382CAA3CEE25CD616881DB7383F3956AA378B528B57E1CF1C15AE6946A4A'
if (Test-Path -LiteralPath $detailPromptFullPath -PathType Leaf) {
    $actualDetailPrompt = Get-Content -LiteralPath $detailPromptFullPath -Raw -Encoding UTF8
    $actualDetailPromptHash = Get-NormalizedUtf8Sha256 -Text $actualDetailPrompt
    if (-not [string]::Equals($actualDetailPromptHash, $expectedDetailPromptHash, [System.StringComparison]::Ordinal)) {
        $failures.Add("$detailPromptRelativePath must exactly match the Emperor-approved fixed prompt; additions, deletions, and rewrites are forbidden.")
    }
}
if (-not (Test-Path -LiteralPath $detailPromptLockFullPath -PathType Leaf)) {
    $failures.Add("Missing required file: $detailPromptLockRelativePath")
}
else {
    try {
        $detailPromptLock = Get-Content -LiteralPath $detailPromptLockFullPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ([string]$detailPromptLock.templatePath -cne 'templates/TAOBAO_DETAIL_IMAGE_PROMPT.md') {
            $failures.Add("$detailPromptLockRelativePath has an invalid templatePath.")
        }
        if ([string]$detailPromptLock.version -cne 'emperor-fixed-detail-v1') {
            $failures.Add("$detailPromptLockRelativePath has an invalid version.")
        }
        if ($detailPromptLock.immutable -isnot [bool] -or $detailPromptLock.immutable -ne $true) {
            $failures.Add("$detailPromptLockRelativePath must set immutable=true.")
        }
        if (-not [string]::Equals([string]$detailPromptLock.normalizedUtf8Sha256, $expectedDetailPromptHash, [System.StringComparison]::Ordinal)) {
            $failures.Add("$detailPromptLockRelativePath hash does not match the Emperor-approved fixed prompt.")
        }
    }
    catch {
        $failures.Add("$detailPromptLockRelativePath is not valid JSON: $($_.Exception.Message)")
    }
}

$workflowPath = Join-Path $projectRoot $workflowRelativePath
if (Test-Path -LiteralPath $workflowPath -PathType Leaf) {
    $workflowContent = Get-Content -LiteralPath $workflowPath -Raw -Encoding UTF8
    $orderedWorkflowMarkers = @(
        (New-Marker -Label 'task routing' -Value (Decode-Text '5Lu75Yqh5YiG5rWB')),
        (New-Marker -Label 'asset archiving' -Value (Decode-Text '57Sg5p2Q5b2S5qGj')),
        (New-Marker -Label 'selling-point extraction' -Value (Decode-Text '5Y2W54K55o+Q54K8')),
        (New-Marker -Label 'Emperor confirms selling points' -Value (Decode-Text '5bid546L56Gu6K6k5Y2W54K5')),
        (New-Marker -Label 'home and detail prompts' -Value (Decode-Text '6aaW5Zu+5LiO6K+m5oOF6aG15o+Q56S66K+N')),
        (New-Marker -Label 'Emperor confirms prompts' -Value (Decode-Text '5bid546L56Gu6K6k5o+Q56S66K+N')),
        (New-Marker -Label 'first actual queue item' -Value (Decode-Text '6aaW5Liq5a6e6ZmF6Zif5YiX6aG5')),
        (New-Marker -Label 'per-image acceptance' -Value (Decode-Text '6YCQ5byg6aqM5pS2')),
        (New-Marker -Label 'whole-set consistency acceptance' -Value (Decode-Text '5pW05aWX5LiA6Ie05oCn6aqM5pS2')),
        (New-Marker -Label 'Emperor final acceptance' -Value (Decode-Text '5bid546L5pyA57uI6aqM5pS2')),
        (New-Marker -Label 'non-overwriting promotion' -Value (Decode-Text '6Z2e6KaG55uW5pmL57qn'))
    )

    $previousIndex = -1
    foreach ($marker in $orderedWorkflowMarkers) {
        $currentIndex = $workflowContent.IndexOf($marker.Value, [System.StringComparison]::Ordinal)
        if ($currentIndex -lt 0) {
            $failures.Add("$workflowRelativePath missing ordered workflow marker [$($marker.Label)]")
        }
        elseif ($currentIndex -le $previousIndex) {
            $failures.Add("$workflowRelativePath workflow marker is out of order [$($marker.Label)]")
        }
        else {
            $previousIndex = $currentIndex
        }
    }
}

$jobPath = Join-Path $projectRoot $jobRelativePath
if (Test-Path -LiteralPath $jobPath -PathType Leaf) {
    $jobText = Get-Content -LiteralPath $jobPath -Raw -Encoding UTF8
    $job = $null

    if ([string]::IsNullOrWhiteSpace($jobText)) {
        $failures.Add("$jobRelativePath must not be empty")
    }
    elseif ($jobText.Trim() -eq '{}') {
        $failures.Add("$jobRelativePath must not be an empty JSON object")
    }
    else {
        try {
            $job = $jobText | ConvertFrom-Json
        }
        catch {
            $failures.Add("$jobRelativePath contains invalid JSON: $($_.Exception.Message)")
        }
    }

    if ($null -ne $job) {
        if ($job -is [System.Array] -or $job -isnot [System.Management.Automation.PSCustomObject]) {
            $failures.Add("$jobRelativePath JSON root must be an object")
        }
        else {
            $requiredTopLevelFields = @(
                'schemaVersion',
                'jobId',
                'originThreadMode',
                'status',
                'scope',
                'category',
                'product',
                'sellingPoints',
                'promptSet',
                'assetTransfer',
                'generation',
                'candidates',
                'setAcceptance',
                'approval',
                'promotion',
                'history'
            )

            $availableTopLevelFields = @($job.PSObject.Properties | ForEach-Object { $_.Name })
            foreach ($field in $requiredTopLevelFields) {
                if ($availableTopLevelFields -cnotcontains $field) {
                    $failures.Add("$jobRelativePath missing required top-level field: $field")
                }
            }

            Test-ScalarDefaults -Object $job -Expected ([ordered]@{
                schemaVersion = '1.0'
                jobId = ''
                originThreadMode = 'test'
                status = 'intake_pending'
            }) -ContractPath '' -RelativePath $jobRelativePath -FailureList $failures

            $scope = Get-RequiredObject -Object $job -PropertyName 'scope' -ContractPath 'scope' -RelativePath $jobRelativePath -FailureList $failures
            if ($null -ne $scope) {
                Test-ScalarDefaults -Object $scope -Expected ([ordered]@{
                    mode = ''
                    homeRequired = $false
                    detailRequired = $false
                }) -ContractPath 'scope' -RelativePath $jobRelativePath -FailureList $failures
            }

            $category = Get-RequiredObject -Object $job -PropertyName 'category' -ContractPath 'category' -RelativePath $jobRelativePath -FailureList $failures
            if ($null -ne $category) {
                Test-ScalarDefaults -Object $category -Expected ([ordered]@{
                    id = ''
                    subtype = ''
                    profileVersion = ''
                    profilePath = ''
                    profileSha256 = ''
                    confirmed = $false
                }) -ContractPath 'category' -RelativePath $jobRelativePath -FailureList $failures
            }

            $product = Get-RequiredObject -Object $job -PropertyName 'product' -ContractPath 'product' -RelativePath $jobRelativePath -FailureList $failures
            if ($null -ne $product) {
                Test-ScalarDefaults -Object $product -Expected ([ordered]@{
                    name = ''
                }) -ContractPath 'product' -RelativePath $jobRelativePath -FailureList $failures
                Test-ArrayProperty -Object $product -PropertyName 'assets' -ContractPath 'product.assets' -RequireEmpty $true -RelativePath $jobRelativePath -FailureList $failures
                Test-ArrayProperty -Object $product -PropertyName 'facts' -ContractPath 'product.facts' -RequireEmpty $true -RelativePath $jobRelativePath -FailureList $failures
            }

            $sellingPoints = Get-RequiredObject -Object $job -PropertyName 'sellingPoints' -ContractPath 'sellingPoints' -RelativePath $jobRelativePath -FailureList $failures
            if ($null -ne $sellingPoints) {
                Test-ScalarDefaults -Object $sellingPoints -Expected ([ordered]@{
                    confirmed = $false
                    confirmationStatement = ''
                    confirmedAt = ''
                }) -ContractPath 'sellingPoints' -RelativePath $jobRelativePath -FailureList $failures
            }
            Test-ItemContractFields -Job $job -BranchName 'sellingPoints' -RequiredFields $sellingPointItemFields -RelativePath $jobRelativePath -FailureList $failures

            $marketBenchmark = Get-RequiredObject -Object $job -PropertyName 'marketBenchmark' -ContractPath 'marketBenchmark' -RelativePath $jobRelativePath -FailureList $failures
            if ($null -ne $marketBenchmark) {
                Test-ScalarDefaults -Object $marketBenchmark -Expected ([ordered]@{
                    completed = $false
                    completedAt = ''
                    productCategory = ''
                    reportPath = ''
                }) -ContractPath 'marketBenchmark' -RelativePath $jobRelativePath -FailureList $failures
                Test-ArrayProperty -Object $marketBenchmark -PropertyName 'references' -ContractPath 'marketBenchmark.references' -RequireEmpty $true -RelativePath $jobRelativePath -FailureList $failures
                Test-EmptyObjectProperty -Object $marketBenchmark -PropertyName 'styleDecision' -ContractPath 'marketBenchmark.styleDecision' -RelativePath $jobRelativePath -FailureList $failures
            }
            Test-ItemContractFields -Job $job -BranchName 'marketBenchmark' -ItemPropertyName 'references' -RequiredFields $benchmarkReferenceFields -RelativePath $jobRelativePath -FailureList $failures

            $promptSet = Get-RequiredObject -Object $job -PropertyName 'promptSet' -ContractPath 'promptSet' -RelativePath $jobRelativePath -FailureList $failures
            if ($null -ne $promptSet) {
                Test-ScalarDefaults -Object $promptSet -Expected ([ordered]@{
                    confirmed = $false
                    confirmationStatement = ''
                    confirmedAt = ''
                }) -ContractPath 'promptSet' -RelativePath $jobRelativePath -FailureList $failures
                Test-EmptyObjectProperty -Object $promptSet -PropertyName 'styleLock' -ContractPath 'promptSet.styleLock' -RelativePath $jobRelativePath -FailureList $failures
                Test-EmptyObjectProperty -Object $promptSet -PropertyName 'structureLock' -ContractPath 'promptSet.structureLock' -RelativePath $jobRelativePath -FailureList $failures
            }
            Test-ItemContractFields -Job $job -BranchName 'promptSet' -RequiredFields $promptSetItemFields -RelativePath $jobRelativePath -FailureList $failures

            $assetTransfer = Get-RequiredObject -Object $job -PropertyName 'assetTransfer' -ContractPath 'assetTransfer' -RelativePath $jobRelativePath -FailureList $failures
            if ($null -ne $assetTransfer) {
                Test-ScalarDefaults -Object $assetTransfer -Expected ([ordered]@{
                    required = $true
                    assetPath = ''
                    expectedSha256 = ''
                    itemId = ''
                     promptVersion = ''
                     verifiedAt = ''
                     chatSessionReference = ''
                     conversationAction = ''
                     authorizationConfirmed = $false
                    destination = 'ChatGPT web via QQ Browser'
                    method = ''
                    clipboardPrepared = $false
                    thumbnailVerified = $false
                    verifiedAssetName = ''
                    pathTextEntered = $false
                    status = 'pending'
                    failureReason = ''
                }) -ContractPath 'assetTransfer' -RelativePath $jobRelativePath -FailureList $failures
            }

            $generation = Get-RequiredObject -Object $job -PropertyName 'generation' -ContractPath 'generation' -RelativePath $jobRelativePath -FailureList $failures
            if ($null -ne $generation) {
                Test-ScalarDefaults -Object $generation -Expected ([ordered]@{
                     currentItemId = ''
                     channel = 'chatgpt_web_qq'
                     channelStatus = 'default'
                     executionMode = 'batch_after_style_anchor'
                     reviewPolicy = 'anchor_once_batch_qc_final_set_review'
                     chatSessionPolicy = 'single_conversation_full_set'
                     chatSessionReference = ''
                     chatSessionOpenedForItemId = ''
                     newConversationCount = 0
                 }) -ContractPath 'generation' -RelativePath $jobRelativePath -FailureList $failures
                Test-EmptyObjectProperty -Object $generation -PropertyName 'batchAuthorization' -ContractPath 'generation.batchAuthorization' -RelativePath $jobRelativePath -FailureList $failures
                Test-EmptyObjectProperty -Object $generation -PropertyName 'channelAuthorization' -ContractPath 'generation.channelAuthorization' -RelativePath $jobRelativePath -FailureList $failures

                $styleAnchor = Get-RequiredObject -Object $generation -PropertyName 'styleAnchor' -ContractPath 'generation.styleAnchor' -RelativePath $jobRelativePath -FailureList $failures
                if ($null -ne $styleAnchor) {
                    Test-ScalarDefaults -Object $styleAnchor -Expected ([ordered]@{
                        itemId = ''
                        confirmed = $false
                        confirmationStatement = ''
                        confirmedAt = ''
                    }) -ContractPath 'generation.styleAnchor' -RelativePath $jobRelativePath -FailureList $failures
                }
            }

            Test-ArrayProperty -Object $job -PropertyName 'candidates' -ContractPath 'candidates' -RequireEmpty $true -RelativePath $jobRelativePath -FailureList $failures

            $setAcceptance = Get-RequiredObject -Object $job -PropertyName 'setAcceptance' -ContractPath 'setAcceptance' -RelativePath $jobRelativePath -FailureList $failures
            if ($null -ne $setAcceptance) {
                Test-ScalarDefaults -Object $setAcceptance -Expected ([ordered]@{
                    path = ''
                    passed = $false
                }) -ContractPath 'setAcceptance' -RelativePath $jobRelativePath -FailureList $failures
                Test-EmptyObjectProperty -Object $setAcceptance -PropertyName 'checks' -ContractPath 'setAcceptance.checks' -RelativePath $jobRelativePath -FailureList $failures
            }

            $approval = Get-RequiredObject -Object $job -PropertyName 'approval' -ContractPath 'approval' -RelativePath $jobRelativePath -FailureList $failures
            if ($null -ne $approval) {
                Test-ScalarDefaults -Object $approval -Expected ([ordered]@{
                    approved = $false
                    statement = ''
                    approvedAt = ''
                }) -ContractPath 'approval' -RelativePath $jobRelativePath -FailureList $failures
            }

            $promotion = Get-RequiredObject -Object $job -PropertyName 'promotion' -ContractPath 'promotion' -RelativePath $jobRelativePath -FailureList $failures
            if ($null -ne $promotion) {
                Test-ScalarDefaults -Object $promotion -Expected ([ordered]@{
                    outputDirectory = ''
                    promoted = $false
                    promotedAt = ''
                    promotedBy = ''
                }) -ContractPath 'promotion' -RelativePath $jobRelativePath -FailureList $failures
                Test-ArrayProperty -Object $promotion -PropertyName 'files' -ContractPath 'promotion.files' -RequireEmpty $true -RelativePath $jobRelativePath -FailureList $failures
            }

            Test-ArrayProperty -Object $job -PropertyName 'history' -ContractPath 'history' -RequireEmpty $true -RelativePath $jobRelativePath -FailureList $failures
        }
    }
}

if ($failures.Count -gt 0) {
    Write-Error -Message ("Taobao workflow contract failed:`n- " + ($failures -join "`n- ")) -ErrorAction Continue
    exit 1
}

Write-Output 'PASS: Taobao workflow, templates, and acceptance contract are complete.'
