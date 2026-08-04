param()

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$workflowPath = Join-Path $projectRoot 'workflows\PROMOTIONAL_POSTER_PILOT.md'
$agentsPath = Join-Path $projectRoot 'AGENTS.md'
$skillPath = Join-Path $projectRoot 'skills\creating-promotional-posters\SKILL.md'
$sharedBrowserStandardPath = Join-Path $projectRoot 'shared\BROWSER_CONTINUOUS_ACTION_STANDARD.md'
$imageGenerationChannelStandardPath = Join-Path $projectRoot 'shared\IMAGE_GENERATION_CHANNEL_STANDARD.md'
$productAssetFidelityStandardPath = Join-Path $projectRoot 'shared\PRODUCT_ASSET_FIDELITY_STANDARD.md'
$browserControllerPath = Join-Path $projectRoot 'scripts\browser_continuous_action_controller.mjs'
$posterFastlanePath = Join-Path $projectRoot 'scripts\poster_chatgpt_browser_fastlane.mjs'

if (-not (Test-Path -LiteralPath $workflowPath -PathType Leaf)) {
    throw 'Missing promotional poster pilot workflow.'
}

if (-not (Test-Path -LiteralPath $skillPath -PathType Leaf)) {
    throw 'Missing formal creating-promotional-posters Skill.'
}

if (-not (Test-Path -LiteralPath $sharedBrowserStandardPath -PathType Leaf)) {
    throw 'Missing cross-role browser continuous-action standard.'
}

if (-not (Test-Path -LiteralPath $imageGenerationChannelStandardPath -PathType Leaf)) {
    throw 'Missing shared image-generation channel standard.'
}

if (-not (Test-Path -LiteralPath $productAssetFidelityStandardPath -PathType Leaf)) {
    throw 'Missing shared product-asset fidelity standard.'
}

if (-not (Test-Path -LiteralPath $browserControllerPath -PathType Leaf)) {
    throw 'Missing reusable browser continuous-action controller.'
}

if (-not (Test-Path -LiteralPath $posterFastlanePath -PathType Leaf)) {
    throw 'Missing poster ChatGPT browser fast-lane adapter.'
}

$workflow = Get-Content -Raw -Encoding UTF8 -LiteralPath $workflowPath
$agents = Get-Content -Raw -Encoding UTF8 -LiteralPath $agentsPath
$skill = Get-Content -Raw -Encoding UTF8 -LiteralPath $skillPath
$sharedBrowserStandard = Get-Content -Raw -Encoding UTF8 -LiteralPath $sharedBrowserStandardPath
$imageGenerationChannelStandard = Get-Content -Raw -Encoding UTF8 -LiteralPath $imageGenerationChannelStandardPath
$productAssetFidelityStandard = Get-Content -Raw -Encoding UTF8 -LiteralPath $productAssetFidelityStandardPath

function Decode-Text {
    param([string]$Base64)
    return [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Base64))
}

$requiredRules = @(
    (Decode-Text '6ZyA5rGC6ICF5Y+q6ZyA5L2/55So6Ieq54S26K+t6KiA5o+P6L+w5L+u5pS55oSf5Y+X'),
    (Decode-Text '5LiN5b6X6KaB5rGC6ZyA5rGC6ICF5aSN5Yi25oiW5aSN6L+w5YaF6YOo5omn6KGM5riF5Y2V'),
    (Decode-Text '6Ieq6KGM6K+75Y+W5b2T5YmN54mI5pys44CB6aqM5pS26K6w5b2V5ZKM6Zeu6aKY5riF5Y2V'),
    (Decode-Text '5aSa5bmz5Y+w5Lu75Yqh5LiN562J5LqO5oqK5ZCM5LiA54mI5py65qKw57yp5pS+'),
    (Decode-Text '6ZW/5a695q+U5Y+R55Sf5pi+6JGX5Y+Y5YyW5pe25LiN5b6X5LuF6Z2g5omp5bGV55S75biD5oiW5py65qKw5o6S54mI'),
    (Decode-Text 'Q2hhdEdQVCDnvZHpobXljp/lp4vmiJDlm77mnIDnu4jlv4XpobvlvZLmoaPliLDpobnnm67kuJPnlKjnm67lvZUgYHRlbXAvY2hhdGdwdC1kb3dubG9hZHMvYA=='),
    (Decode-Text '6buY6K6k57un57ut5L2/55SoIFFRIOa1j+iniOWZqA=='),
    (Decode-Text '55uu5qCH5paH5Lu25b+F6aG75a2Y5Zyo'),
    (Decode-Text '6K6w5b2V5a6e6ZmF5LiL6L295paH5Lu255qE57ud5a+56Lev5b6E'),
    (Decode-Text '5Ymq5YiH5YiwIGB0ZW1wL2NoYXRncHQtZG93bmxvYWRzL2A='),
    (Decode-Text '56e75Yqo5YmN5ZCOIFNIQS0yNTYg5b+F6aG75LiA6Ie0'),
    (Decode-Text '5Y6f5LiL6L295L2N572u5LiN5YaN5a2Y5Zyo6K+l5paH5Lu2'),
    (Decode-Text '5LiN5b6X6KaG55uW5ZCM5ZCN5paH5Lu2'),
    (Decode-Text '5peg5rOV5a6a5L2N5a6e6ZmF5LiL6L295paH5Lu25pe25YGc5q2i')
)

foreach ($rule in $requiredRules) {
    if (-not $workflow.Contains($rule)) {
        throw "Missing natural-language modification rule: $rule"
    }
}

$hardGateRules = @(
    'creating-promotional-posters',
    'CheckBeforeGenerate',
    'CheckCandidate',
    'CheckBeforePromote',
    (Decode-Text '5Lu75L2V5pmu6YCa5a6j5Lyg5rW35oql5Lu75Yqh'),
    (Decode-Text '5b+F6aG75YWI5Yib5bu65Lu75Yqh5riF5Y2V'),
    (Decode-Text '5pyq57uP6ZyA5rGC56Gu6K6k5LiN5b6X6LCD55So5Lu75L2V55Sf5Zu+5bel5YW3'),
    (Decode-Text '5rWL6K+V57q/56iL5LiN5b6X55u05o6l5YaZ5YWlIGBvdXRwdXRzL2A='),
    (Decode-Text '6buY6K6k5L2/55SoIFFRIOa1j+iniOWZqOS4reeahCBDaGF0R1BUIOe9kemhtQ=='),
    (Decode-Text '5pyq57uP5bid546L5piO56Gu6aqM5pS2')
)

$hardGateCorpus = $agents + "`n" + $workflow + "`n" + $skill
foreach ($rule in $hardGateRules) {
    if (-not $hardGateCorpus.Contains($rule)) {
        throw "Missing promotional-poster hard gate: $rule"
    }
}

$productPosterRules = @(
    (Decode-Text '5Lqn5ZOB6ZSA5ZSu5rW35oql'),
    (Decode-Text '5Y2W54K56K+B5o2u6KGo'),
    (Decode-Text '5bey56Gu6K6k5Y2W54K5'),
    (Decode-Text '5Zu+54mH5Y+v6KeB57uT5p6E'),
    (Decode-Text '5oCn6IO95LiO5Y+C5pWw'),
    (Decode-Text '5YaF5a655LiA6Ie044CB5Y+q5pS55Y+Y6KeG6KeJ6aOO5qC8'),
    (Decode-Text '5paH5a2X44CB57yW5Y+344CB6YWN5Zu+5ZKM5Lqn5ZOB6YOo5L2N'),
    (Decode-Text '5bmy5YeA5Lya6K+d')
)

foreach ($rule in $productPosterRules) {
    if (-not $hardGateCorpus.Contains($rule)) {
        throw "Missing product-poster rule: $rule"
    }
}

$iterationAuthorizationRules = @(
    (Decode-Text '5piO56Gu55qE5ZCM6IyD5Zu05L+u5pS55Y+N6aaI5pys6Lqr5Y2z5Li65omn6KGM5o6I5p2D'),
    (Decode-Text '5LiN5b6X5YaN5qyh6K+35rGC56Gu6K6k5paH5a2X5L+u5pS55pa55qGI'),
    (Decode-Text '6Ieq5Yqo5a6M5oiQ54mI5pys5L+d5a2Y44CB5Ye65Zu+44CB5qOA5p+l44CB6Zeu6aKY5pu05paw5ZKM5aSN5rWL'),
    (Decode-Text '5Y+q5pyJ5pS55Y+Y5Lu75Yqh5pa55ZCR55qE5q2n5LmJ44CB5LuY6LS544CB5a+55aSW5Y+R5biD44CB5LiN5Y+v6YCG6KaG55uW44CB6LSm5Y+35p2D6ZmQ5oiW5a6J5YWo6aOO6Zmp5omN6K+35rGC5pyA5bCR5b+F6KaB56Gu6K6k')
)

foreach ($rule in $iterationAuthorizationRules) {
    if (-not $hardGateCorpus.Contains($rule)) {
        throw "Missing automatic-iteration authorization rule: $rule"
    }
}

$continuousActionRules = @(
    (Decode-Text '5rWP6KeI5Zmo6L+e57ut5Yqo5L2c'),
    (Decode-Text '5p2h5Lu25qOA5rWL5Luj5pu/5Zu65a6a562J5b6F'),
    (Decode-Text '55Sf5oiQ5a6M5oiQ5Yiw56Gu6K6k5LiL6L29'),
    (Decode-Text '5ZCM5LiA5qyh6L+e57ut5omn6KGM'),
    (Decode-Text 'MiDnp5LlhoXmiZPlvIDlm77niYc='),
    (Decode-Text 'MiDnp5LlhoXngrnlh7vkuIvovb0='),
    (Decode-Text 'MyDnp5LlhoXnoa7orqTkuIvovb0='),
    (Decode-Text '5Yqo5L2c5pe26Ze057q/'),
    (Decode-Text '5o+Q6YCf5LiN5b6X5YeP5bCR44CB57yp5bCP5oiW6Lez6L+H5a6M5pW05a6h5Zu+')
)

$continuousActionCorpus = $sharedBrowserStandard + "`n" + $workflow + "`n" + $skill
foreach ($rule in $continuousActionRules) {
    if (-not $continuousActionCorpus.Contains($rule)) {
        throw "Missing continuous browser-action rule: $rule"
    }
}

if (-not $agents.Contains('shared/BROWSER_CONTINUOUS_ACTION_STANDARD.md')) {
    throw 'AGENTS.md does not route cross-role browser work to the shared continuous-action standard.'
}

$routeAndFidelityRules = @(
    'shared/IMAGE_GENERATION_CHANNEL_STANDARD.md',
    'shared/PRODUCT_ASSET_FIDELITY_STANDARD.md',
    'current_job_version_authorization',
    'channel_scoped_refusal',
    'confirmed_direction_change',
    'product_source_binding',
    'unsupported_view_boundary'
)

$routeAndFidelityCorpus = $agents + "`n" + $workflow + "`n" + $skill + "`n" + $imageGenerationChannelStandard + "`n" + $productAssetFidelityStandard
foreach ($rule in $routeAndFidelityRules) {
    if (-not $routeAndFidelityCorpus.Contains($rule)) {
        throw "Missing generation-route or product-fidelity rule: $rule"
    }
}

$designTranslationRules = @(
    'prompt_framework_binding',
    'reference_visual_dna',
    'three_direction_preselection',
    'final_prompt_provenance',
    'reference_aesthetic_comparison',
    'ANTI_AI_FAILURES'
)

$designTranslationCorpus = $workflow + "`n" + $skill
foreach ($rule in $designTranslationRules) {
    if (-not $designTranslationCorpus.Contains($rule)) {
        throw "Missing design-translation rule: $rule"
    }
}

foreach ($requiredReference in @('shared/IMAGE_GENERATION_CHANNEL_STANDARD.md', 'shared/PRODUCT_ASSET_FIDELITY_STANDARD.md')) {
    if (-not $skill.Contains($requiredReference)) {
        throw "Promotional-poster Skill does not load shared standard: $requiredReference"
    }
    if (-not $workflow.Contains($requiredReference)) {
        throw "Promotional-poster Workflow does not load shared standard: $requiredReference"
    }
}

Write-Output 'PASS: poster workflow enforces brief confirmation, continuous browser actions, full visual review, candidate isolation, and approved promotion.'
