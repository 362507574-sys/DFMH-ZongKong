param()

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Read-ProjectFile {
    param([string]$RelativePath)
    $full = Join-Path $projectRoot ($RelativePath -replace '/', '\')
    Assert-True (Test-Path -LiteralPath $full -PathType Leaf) ("Missing required file: " + $RelativePath)
    return Get-Content -Raw -Encoding UTF8 -LiteralPath $full
}

function Assert-ContainsAll {
    param([string]$Text, [string[]]$Needles, [string]$Label)
    foreach ($needle in $Needles) {
        Assert-True $Text.Contains($needle) ("$Label is missing required contract: $needle")
    }
}

$skill = Read-ProjectFile 'skills/creating-promotional-posters/SKILL.md'
$workflow = Read-ProjectFile 'workflows/PROMOTIONAL_POSTER_PILOT.md'
$framework = Read-ProjectFile 'templates/PROMOTIONAL_POSTER_PROMPT_V1.md'
$platformProfiles = Read-ProjectFile 'skills/creating-promotional-posters/references/PLATFORM_PROFILES.md'
$categoryAdapters = Read-ProjectFile 'skills/creating-promotional-posters/references/CATEGORY_ADAPTERS.md'
$gate = Read-ProjectFile 'scripts/poster_workflow_gate.ps1'
$jobTemplateText = Read-ProjectFile 'templates/PROMOTIONAL_POSTER_JOB.json'
$jobTemplate = $jobTemplateText | ConvertFrom-Json

$skillNeedles = @(
    'platform_profile_binding',
    'category_adapter_binding',
    'sequential_single_generation',
    'one_core_skill_with_profiles',
    'one_image_per_request',
    'wechat_chat_dual_intent_split',
    'one_primary_action_per_poster'
)
Assert-ContainsAll -Text $skill -Needles $skillNeedles -Label "Poster Skill"

$workflowNeedles = @(
    'platform_profile_routing',
    'category_adapter_routing',
    'sequential_single_generation',
    'first_approved_anchor',
    'no_multi_image_batch_for_sensitive_apparel',
    'wechat_chat_dual_intent_split',
    'event_notice',
    'sales_conversion'
)
Assert-ContainsAll -Text $workflow -Needles $workflowNeedles -Label "Poster Workflow"

$platformNeedles = @(
    'xiaohongshu',
    'wechat_moments',
    'wechat_chat',
    'generic_poster',
    '3:4',
    'profile_not_fixed_aesthetic_formula',
    'event_notice',
    'sales_conversion',
    'one_primary_action_per_poster'
)
Assert-ContainsAll -Text $platformProfiles -Needles $platformNeedles -Label "Platform profiles"

$categoryNeedles = @(
    'intimate_apparel_adult',
    'fashion_apparel',
    'electronics',
    'toys',
    'adult_nonsexual_retail_v1',
    'no_invented_ports_screens_accessories_features_or_specs',
    'product_identity_lock'
)
Assert-ContainsAll -Text $categoryAdapters -Needles $categoryNeedles -Label "Category adapters"

$frameworkNeedles = @(
    'V4',
    '[PLATFORM_PROFILE]',
    '[CATEGORY_ADAPTER]',
    '[GENERATION_PLAN]',
    'single_frame_single_composition_single_pose',
    'compact_safety_block'
)
Assert-ContainsAll -Text $framework -Needles $frameworkNeedles -Label "Prompt framework"

$gateNeedles = @(
    'Assert-PlatformCategoryAndSeriesReady',
    'Assert-CampaignIntentReady',
    'deliveryProfile',
    'campaignIntent',
    'candidateSet',
    'pairReview',
    'promotion.outputItems',
    'categoryProfile',
    'generation.series',
    'sequential_single',
    'An adult intimate-apparel request may generate only one image per request.'
)
Assert-ContainsAll -Text $gate -Needles $gateNeedles -Label "Poster gate"

Assert-True ($null -ne $jobTemplate.deliveryProfile) 'Job template is missing deliveryProfile.'
Assert-True ($null -ne $jobTemplate.campaignIntent) 'Job template is missing campaignIntent.'
Assert-True ($jobTemplate.campaignIntent.primary -eq 'general_campaign') 'Job template must default to general_campaign.'
Assert-True ($jobTemplate.campaignIntent.secondary -eq 'none') 'Job template must default to one primary intent.'
Assert-True ($null -ne $jobTemplate.candidateSet) 'Job template is missing candidateSet.'
Assert-True ($jobTemplate.candidateSet.required -eq $false) 'A single-poster template must not require a candidate pair.'
Assert-True ($null -ne $jobTemplate.candidateSet.pairReview) 'Job template is missing pairReview.'
Assert-True ($null -ne $jobTemplate.promotion.outputItems) 'Job template is missing promotion.outputItems.'
Assert-True ($null -ne $jobTemplate.categoryProfile) 'Job template is missing categoryProfile.'
Assert-True ($null -ne $jobTemplate.generation.series) 'Job template is missing generation.series.'
Assert-True ($jobTemplate.generation.series.requestMode -eq 'sequential_single') 'Job template must default to sequential single-image generation.'
Assert-True ([int]$jobTemplate.generation.series.outputsPerRequest -eq 1) 'Job template must default to one output per request.'
Assert-True ([int]$jobTemplate.generation.series.maxAttemptsPerOutput -eq 2) 'Each output must have a bounded two-attempt stop condition.'

Write-Output 'PASS: platform profiles, category adapters, prompt load control, and sequential generation contracts are present.'
