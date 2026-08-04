param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('CheckBeforeGenerate', 'CheckBeforeUpload', 'CheckAfterUpload', 'CheckCandidate', 'CheckBeforePromote', 'Promote', 'VerifyPromoted', 'Status')]
    [string]$Action,

    [string]$ProjectRoot = '',

    [Parameter(Mandatory = $true)]
    [string]$ManifestPath,

    [ValidateSet('main', 'test', 'production')]
    [string]$ActorMode = 'test'
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}

function Get-NormalizedRoot {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
}

function Test-IsWithin {
    param([string]$Path, [string]$Root)
    $full = [System.IO.Path]::GetFullPath($Path)
    $rootFull = (Get-NormalizedRoot $Root) + [System.IO.Path]::DirectorySeparatorChar
    return $full.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)
}

function Assert-NoReparsePoints {
    param([string]$Path, [string]$AllowedRoot)
    $full = [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    $root = Get-NormalizedRoot $AllowedRoot
    if (-not $full.Equals($root, [System.StringComparison]::OrdinalIgnoreCase) -and -not (Test-IsWithin -Path $full -Root $root)) {
        throw "Path is outside its allowed root: $full"
    }
    $components = New-Object System.Collections.ArrayList
    [void]$components.Add($root)
    if (-not $full.Equals($root, [System.StringComparison]::OrdinalIgnoreCase)) {
        $current = $root
        foreach ($part in @($full.Substring($root.Length).TrimStart('\', '/') -split '[\\/]')) {
            if ([string]::IsNullOrWhiteSpace($part)) { continue }
            $current = Join-Path $current $part
            [void]$components.Add($current)
        }
    }
    foreach ($component in @($components)) {
        $item = Get-Item -LiteralPath $component -Force -ErrorAction SilentlyContinue
        if ($null -ne $item -and ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "ReparsePoint, junction, or symbolic-link paths are not allowed: $component"
        }
    }
}

function Resolve-ProjectPath {
    param(
        [string]$RelativePath,
        [string]$RequiredRoot
    )
    if ([string]::IsNullOrWhiteSpace($RelativePath)) {
        throw 'A required project-relative path is empty.'
    }
    if ([System.IO.Path]::IsPathRooted($RelativePath)) {
        throw "Absolute paths are not allowed in the manifest: $RelativePath"
    }
    $resolved = [System.IO.Path]::GetFullPath((Join-Path $script:rootFull ($RelativePath -replace '/', '\')))
    if (-not (Test-IsWithin -Path $resolved -Root $script:rootFull)) {
        throw "Manifest path escapes the project root: $RelativePath"
    }
    if ($RequiredRoot) {
        $required = Join-Path $script:rootFull $RequiredRoot
        if (-not (Test-IsWithin -Path $resolved -Root $required)) {
            throw "Path must be inside $RequiredRoot/: $RelativePath"
        }
    }
    Assert-NoReparsePoints -Path $resolved -AllowedRoot $script:rootFull
    return $resolved
}

function Assert-Text {
    param([object]$Value, [string]$Label)
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        throw "Missing required field: $Label"
    }
}

function Assert-Collection {
    param([object]$Value, [string]$Label)
    if ($null -eq $Value -or @($Value).Count -eq 0) {
        throw "Missing required collection: $Label"
    }
    foreach ($item in @($Value)) {
        if ([string]::IsNullOrWhiteSpace([string]$item)) {
            throw "Collection contains an empty value: $Label"
        }
    }
}

function Test-HasProperty {
    param([object]$Object, [string]$Name)
    return ($null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name])
}

function Assert-Sha256 {
    param([object]$Value, [string]$Label)
    Assert-Text $Value $Label
    if ([string]$Value -notmatch '^[A-Fa-f0-9]{64}$') {
        throw "$Label must be a SHA-256 value."
    }
}

function Assert-ConcreteCollection {
    param(
        [object]$Value,
        [string]$Label,
        [int]$MinimumCount = 1,
        [int]$MinimumLength = 8
    )
    $items = @($Value)
    if ($items.Count -lt $MinimumCount) {
        throw "$Label must contain at least $MinimumCount concrete entries."
    }
    foreach ($item in $items) {
        if ([string]::IsNullOrWhiteSpace([string]$item) -or ([string]$item).Trim().Length -lt $MinimumLength) {
            throw "$Label contains a vague or empty entry."
        }
    }
}

function Assert-DesignTranslationReady {
    if ($null -eq $script:manifest.designTranslation) {
        throw 'Manifest is missing designTranslation.'
    }
    $design = $script:manifest.designTranslation

    if ($null -eq $design.framework) {
        throw 'Manifest is missing designTranslation.framework.'
    }
    foreach ($field in @('id', 'version', 'path', 'sha256')) {
        Assert-Text $design.framework.$field ("designTranslation.framework." + $field)
    }
    Assert-Sha256 $design.framework.sha256 'designTranslation.framework.sha256'
    $frameworkFull = Resolve-ProjectPath -RelativePath $design.framework.path -RequiredRoot 'templates'
    if (-not (Test-Path -LiteralPath $frameworkFull -PathType Leaf)) {
        throw 'The bound poster prompt framework does not exist.'
    }
    if ((Get-FileHash -LiteralPath $frameworkFull -Algorithm SHA256).Hash -ne [string]$design.framework.sha256) {
        throw 'The bound poster prompt framework hash does not match.'
    }

    if ($null -eq $design.visualDNA) {
        throw 'Manifest is missing designTranslation.visualDNA.'
    }
    foreach ($field in @('composition', 'environment', 'lighting', 'palette', 'typography', 'texture', 'whitespace')) {
        Assert-Text $design.visualDNA.$field ("designTranslation.visualDNA." + $field)
        if (([string]$design.visualDNA.$field).Trim().Length -lt 12) {
            throw "designTranslation.visualDNA.$field is too vague."
        }
    }
    Assert-ConcreteCollection $design.visualDNA.avoidPatterns 'designTranslation.visualDNA.avoidPatterns' 5 6
    if ($design.visualDNA.referenceRequired -eq $true) {
        Assert-ConcreteCollection $design.visualDNA.referenceAssetIds 'designTranslation.visualDNA.referenceAssetIds' 1 3
        $referenceAssets = @($design.visualDNA.referenceAssets)
        if ($referenceAssets.Count -eq 0) {
            throw 'Reference visual DNA requires archived reference asset evidence.'
        }
        $referenceById = @{}
        foreach ($referenceAsset in $referenceAssets) {
            foreach ($field in @('id', 'path', 'sha256', 'role')) {
                Assert-Text $referenceAsset.$field ("designTranslation.visualDNA.referenceAssets[]." + $field)
            }
            Assert-Sha256 $referenceAsset.sha256 'designTranslation.visualDNA.referenceAssets[].sha256'
            if ($referenceById.ContainsKey([string]$referenceAsset.id)) {
                throw "Duplicate visual reference asset id: $($referenceAsset.id)"
            }
            $referenceFull = Resolve-ProjectPath -RelativePath $referenceAsset.path -RequiredRoot 'temp\poster-jobs'
            if (-not (Test-Path -LiteralPath $referenceFull -PathType Leaf)) {
                throw "Visual reference asset does not exist: $($referenceAsset.id)"
            }
            if ((Get-FileHash -LiteralPath $referenceFull -Algorithm SHA256).Hash -ne [string]$referenceAsset.sha256) {
                throw "Visual reference asset hash does not match: $($referenceAsset.id)"
            }
            $referenceById[[string]$referenceAsset.id] = $true
        }
        foreach ($id in @($design.visualDNA.referenceAssetIds)) {
            if (-not $referenceById.ContainsKey([string]$id)) {
                throw "Visual DNA references an unarchived asset id: $id"
            }
        }
    }

    Assert-Text $design.riskLevel 'designTranslation.riskLevel'
    if (@('routine_locked_direction', 'reference_sensitive', 'high_aesthetic_uncertainty') -notcontains [string]$design.riskLevel) {
        throw "Unsupported design-translation risk level: $($design.riskLevel)"
    }
    if ($null -eq $design.directionSelection) {
        throw 'Manifest is missing designTranslation.directionSelection.'
    }
    $selection = $design.directionSelection
    foreach ($field in @('mode', 'selectedId', 'selectedBy', 'selectionStatement', 'selectedAt')) {
        Assert-Text $selection.$field ("designTranslation.directionSelection." + $field)
    }
    if (@('user', 'agent_authorized') -notcontains [string]$selection.selectedBy) {
        throw 'Design direction must be selected by the user or under explicit agent decision authorization.'
    }
    $options = @($selection.options)
    $requiresThree = @('reference_sensitive', 'high_aesthetic_uncertainty') -contains [string]$design.riskLevel
    if ($requiresThree) {
        if ([string]$selection.mode -ne 'three_direction_preselection' -or $options.Count -ne 3) {
            throw 'Reference-sensitive or high-uncertainty work requires exactly three preselected design directions.'
        }
    }
    elseif ([string]$selection.mode -ne 'direct_confirmed' -or $options.Count -lt 1) {
        throw 'A routine locked direction requires at least one recorded direction.'
    }
    $optionIds = @{}
    foreach ($option in $options) {
        foreach ($field in @('id', 'label', 'composition', 'lighting', 'palette', 'commercialFit', 'risk')) {
            Assert-Text $option.$field ("designTranslation.directionSelection.options[]." + $field)
        }
        if ($optionIds.ContainsKey([string]$option.id)) {
            throw "Duplicate design direction id: $($option.id)"
        }
        $optionIds[[string]$option.id] = $true
    }
    if (-not $optionIds.ContainsKey([string]$selection.selectedId)) {
        throw 'The selected design direction is not one of the recorded options.'
    }

    if ($null -eq $design.promptBuild) {
        throw 'Manifest is missing designTranslation.promptBuild.'
    }
    $promptBuild = $design.promptBuild
    foreach ($field in @('version', 'path', 'sha256')) {
        Assert-Text $promptBuild.$field ("designTranslation.promptBuild." + $field)
    }
    if ($promptBuild.frameworkApplied -ne $true) {
        throw 'The final prompt is not recorded as assembled from the bound framework.'
    }
    if ([string]$promptBuild.version -ne [string]$script:manifest.generation.route.currentVersion -or [string]$promptBuild.version -ne [string]$script:manifest.candidate.version) {
        throw 'The final prompt is not bound to the current generation version.'
    }
    Assert-Sha256 $promptBuild.sha256 'designTranslation.promptBuild.sha256'
    $promptFull = Resolve-ProjectPath -RelativePath $promptBuild.path -RequiredRoot 'temp\poster-jobs'
    if (-not (Test-Path -LiteralPath $promptFull -PathType Leaf)) {
        throw 'The final generation prompt file does not exist.'
    }
    if ((Get-FileHash -LiteralPath $promptFull -Algorithm SHA256).Hash -ne [string]$promptBuild.sha256) {
        throw 'The final generation prompt hash does not match.'
    }
    $promptText = Get-Content -Raw -Encoding UTF8 -LiteralPath $promptFull
    foreach ($marker in @('[CONFIRMED_BRIEF]', '[PLATFORM_PROFILE]', '[CATEGORY_ADAPTER]', '[REFERENCE_VISUAL_DNA]', '[COMPOSITION]', '[MATERIAL_AND_LIGHT]', '[TYPOGRAPHY]', '[ANTI_AI_FAILURES]', '[GENERATION_PLAN]', '[VISUAL_PASS]', '[LAYOUT_PASS]', '[OUTPUT]')) {
        if (-not $promptText.Contains($marker)) {
            throw "The final prompt is missing framework section: $marker"
        }
    }
}

function Assert-PlatformCategoryAndSeriesReady {
    if ($null -eq $script:manifest.deliveryProfile) {
        throw 'Manifest is missing deliveryProfile.'
    }
    $delivery = $script:manifest.deliveryProfile
    foreach ($field in @('platform', 'contentMode', 'aspectRatio', 'safeArea', 'profilePath', 'profileVersion', 'profileSha256')) {
        Assert-Text $delivery.$field ("deliveryProfile." + $field)
    }
    if (@('xiaohongshu', 'wechat_moments', 'wechat_chat', 'generic_poster') -notcontains [string]$delivery.platform) {
        throw "Unsupported delivery platform profile: $($delivery.platform)"
    }
    if (@('single_poster', 'platform_cover', 'carousel_series', 'dual_intent_pair') -notcontains [string]$delivery.contentMode) {
        throw "Unsupported delivery content mode: $($delivery.contentMode)"
    }
    if ([string]$delivery.platform -eq 'xiaohongshu' -and [string]$delivery.aspectRatio -ne '3:4') {
        throw 'The current Xiaohongshu profile requires a 3:4 task aspect ratio.'
    }
    if ([string]$delivery.platform -eq 'xiaohongshu' -and $delivery.mobileFirst -ne $true) {
        throw 'The Xiaohongshu platform profile must be mobile-first.'
    }
    Assert-Sha256 $delivery.profileSha256 'deliveryProfile.profileSha256'
    $platformProfileFull = Resolve-ProjectPath -RelativePath $delivery.profilePath -RequiredRoot 'skills\creating-promotional-posters\references'
    if (-not (Test-Path -LiteralPath $platformProfileFull -PathType Leaf)) {
        throw 'The bound platform profile file does not exist.'
    }
    if ((Get-FileHash -LiteralPath $platformProfileFull -Algorithm SHA256).Hash -ne [string]$delivery.profileSha256) {
        throw 'The bound platform profile hash does not match.'
    }

    if ($null -eq $script:manifest.categoryProfile) {
        throw 'Manifest is missing categoryProfile.'
    }
    $category = $script:manifest.categoryProfile
    foreach ($field in @('id', 'adapterPath', 'adapterVersion', 'adapterSha256', 'humanSubject', 'safetyProfile')) {
        Assert-Text $category.$field ("categoryProfile." + $field)
    }
    if (@('intimate_apparel_adult', 'fashion_apparel', 'electronics', 'toys', 'general') -notcontains [string]$category.id) {
        throw "Unsupported poster category adapter: $($category.id)"
    }
    if (@('none', 'adult', 'child', 'mixed') -notcontains [string]$category.humanSubject) {
        throw "Unsupported categoryProfile.humanSubject: $($category.humanSubject)"
    }
    Assert-Sha256 $category.adapterSha256 'categoryProfile.adapterSha256'
    $categoryAdapterFull = Resolve-ProjectPath -RelativePath $category.adapterPath -RequiredRoot 'skills\creating-promotional-posters\references'
    if (-not (Test-Path -LiteralPath $categoryAdapterFull -PathType Leaf)) {
        throw 'The bound category-adapter file does not exist.'
    }
    if ((Get-FileHash -LiteralPath $categoryAdapterFull -Algorithm SHA256).Hash -ne [string]$category.adapterSha256) {
        throw 'The bound category-adapter hash does not match.'
    }
    if ([string]$category.id -eq 'intimate_apparel_adult') {
        if ([string]$category.humanSubject -ne 'adult') {
            throw 'An intimate-apparel human subject must be explicitly recorded as adult.'
        }
        if ([string]$category.safetyProfile -ne 'adult_nonsexual_retail_v1') {
            throw 'An adult intimate-apparel task must use adult_nonsexual_retail_v1.'
        }
        Assert-ConcreteCollection $category.fidelityFocus 'categoryProfile.fidelityFocus' 3 5
    }
    if ([string]$category.id -eq 'toys' -and @('child', 'mixed') -contains [string]$category.humanSubject -and [string]$category.safetyProfile -ne 'child_safe_product_v1') {
        throw 'A toy task with child subjects must use child_safe_product_v1.'
    }

    if ($null -eq $script:manifest.generation -or $null -eq $script:manifest.generation.series) {
        throw 'Manifest is missing generation.series.'
    }
    $series = $script:manifest.generation.series
    foreach ($field in @('requestMode', 'anchorStrategy', 'anchorStatus', 'promptLoadPolicy', 'safetyBlockPolicy')) {
        Assert-Text $series.$field ("generation.series." + $field)
    }
    if ([int]$series.requestedOutputs -lt 1 -or [int]$series.currentIndex -lt 1 -or [int]$series.currentIndex -gt [int]$series.requestedOutputs) {
        throw 'generation.series requestedOutputs/currentIndex are invalid.'
    }
    if ([string]$series.requestMode -ne 'sequential_single' -or [int]$series.outputsPerRequest -ne 1) {
        if ([string]$category.id -eq 'intimate_apparel_adult') {
            throw 'An adult intimate-apparel request may generate only one image per request.'
        }
        throw 'The standard poster workflow supports one image per request and sequential series generation.'
    }
    if ([int]$series.maxAttemptsPerOutput -ne 2) {
        throw 'generation.series.maxAttemptsPerOutput must be exactly 2.'
    }
    if ([string]$series.promptLoadPolicy -ne 'single_frame_single_composition_single_pose') {
        throw 'The prompt load policy must be single_frame_single_composition_single_pose.'
    }
    if ([string]$series.safetyBlockPolicy -ne 'compact_safety_block') {
        throw 'The safety block policy must be compact_safety_block.'
    }
    if ([int]$series.requestedOutputs -gt 1 -and [string]$series.anchorStrategy -ne 'first_approved_anchor') {
        throw 'A poster series must use the first approved output as its continuity anchor.'
    }
    if ([int]$series.currentIndex -gt 1) {
        if ([string]$series.anchorStatus -ne 'approved') {
            throw 'Later series outputs require an approved style anchor.'
        }
        Assert-ConcreteCollection $series.continuityLock 'generation.series.continuityLock' 4 6
    }
}

function Assert-CampaignIntentReady {
    if ($null -eq $script:manifest.campaignIntent) {
        throw 'Manifest is missing campaignIntent.'
    }
    $intent = $script:manifest.campaignIntent
    foreach ($field in @('primary', 'secondary', 'splitReason', 'primaryAction')) {
        Assert-Text $intent.$field ("campaignIntent." + $field)
    }
    Assert-Collection $intent.deliveryOrder 'campaignIntent.deliveryOrder'
    Assert-Collection $intent.candidateRoles 'campaignIntent.candidateRoles'

    $allowedPrimary = @('general_campaign', 'event_notice', 'sales_conversion')
    $allowedSecondary = @('none', 'event_notice', 'sales_conversion')
    if ($allowedPrimary -notcontains [string]$intent.primary) {
        throw "Unsupported campaign primary intent: $($intent.primary)"
    }
    if ($allowedSecondary -notcontains [string]$intent.secondary) {
        throw "Unsupported campaign secondary intent: $($intent.secondary)"
    }
    if ([string]$script:manifest.deliveryProfile.platform -eq 'wechat_chat' -and @('event_notice', 'sales_conversion') -notcontains [string]$intent.primary) {
        throw 'A wechat_chat task must use event_notice or sales_conversion as its primary intent.'
    }

    $isDual = [string]$intent.secondary -ne 'none'
    if ($isDual -and [string]$intent.primary -eq [string]$intent.secondary) {
        throw 'Primary and secondary campaign intents must be different.'
    }
    if ($isDual) {
        if ($intent.splitRequired -ne $true) {
            throw 'Two independent WeChat chat actions require separate posters.'
        }
        if ([string]$script:manifest.deliveryProfile.platform -ne 'wechat_chat') {
            throw 'Dual-intent poster pairs are currently supported only by wechat_chat.'
        }
        if ([string]$script:manifest.deliveryProfile.contentMode -ne 'dual_intent_pair') {
            throw 'A dual-intent WeChat chat task must use dual_intent_pair.'
        }
        if ([int]$script:manifest.generation.series.requestedOutputs -ne 2) {
            throw 'A dual-intent WeChat chat pair requires exactly two requested outputs.'
        }
        $order = @($intent.deliveryOrder)
        $roles = @($intent.candidateRoles)
        if ($order.Count -ne 2 -or $roles.Count -ne 2) {
            throw 'A dual-intent pair must record exactly two delivery-order and candidate-role entries.'
        }
        foreach ($required in @('event_notice', 'sales_conversion')) {
            if ($order -notcontains $required -or $roles -notcontains $required) {
                throw 'A dual-intent pair must contain both event_notice and sales_conversion roles.'
            }
        }
        if (@($order | Select-Object -Unique).Count -ne 2 -or @($roles | Select-Object -Unique).Count -ne 2) {
            throw 'A dual-intent pair cannot duplicate its delivery order or candidate roles.'
        }
    }
    else {
        if ($intent.splitRequired -eq $true) {
            throw 'A single campaign intent must not be marked as a required dual split.'
        }
        if ([string]$script:manifest.deliveryProfile.contentMode -eq 'dual_intent_pair') {
            throw 'dual_intent_pair requires two different campaign intents.'
        }
        $order = @($intent.deliveryOrder)
        $roles = @($intent.candidateRoles)
        if ($order.Count -ne 1 -or [string]$order[0] -ne [string]$intent.primary) {
            throw 'A single campaign intent must have one matching delivery-order entry.'
        }
        if ($roles.Count -ne 1 -or [string]$roles[0] -ne [string]$intent.primary) {
            throw 'A single campaign intent must have one matching candidate role.'
        }
    }

    if ([string]$script:manifest.deliveryProfile.platform -ne 'wechat_chat' -and [string]$script:manifest.deliveryProfile.contentMode -eq 'dual_intent_pair') {
        throw 'Only wechat_chat may use dual_intent_pair.'
    }
}

function Assert-GenerationRouteReady {
    if ($null -eq $script:manifest.generation -or $null -eq $script:manifest.generation.route) {
        throw 'Manifest is missing generation.route.'
    }

    $route = $script:manifest.generation.route
    foreach ($field in @('currentMethod', 'currentVersion', 'authorizationType', 'authorizationJobId', 'authorizationVersion', 'authorizationStatement', 'authorizedAt')) {
        Assert-Text $route.$field ("generation.route." + $field)
    }
    if ([string]$route.authorizationJobId -ne [string]$script:manifest.jobId) {
        throw 'Generation-route authorization is not bound to the current job.'
    }
    if ([string]$route.currentVersion -ne [string]$route.authorizationVersion) {
        throw 'Generation-route authorization is not bound to the current version.'
    }
    if ([string]$route.currentVersion -ne [string]$script:manifest.candidate.version) {
        throw 'Generation route version must match candidate.version.'
    }

    $allowedMethods = @('ChatGPT web via QQ Browser', 'Codex built-in image_gen', 'deterministic_local_composite')
    if ($allowedMethods -notcontains [string]$route.currentMethod) {
        throw "Unsupported generation route: $($route.currentMethod)"
    }
    if ([string]$route.currentMethod -eq 'Codex built-in image_gen' -and [string]$route.authorizationType -ne 'user_explicit_current_job') {
        throw 'Codex built-in image_gen requires explicit authorization bound to the current job and version.'
    }
    if ([string]$route.currentMethod -eq 'Codex built-in image_gen' -and [string]$route.authorizationStatement -notmatch '(?i)image_gen') {
        throw 'Built-in generation authorization must explicitly name image_gen; material-use permission is not sufficient.'
    }
    if ([string]$route.currentMethod -eq 'ChatGPT web via QQ Browser' -and @('project_default', 'user_explicit_current_job') -notcontains [string]$route.authorizationType) {
        throw 'QQ Browser route must use project-default or current-job explicit authorization.'
    }

    if ($null -eq $route.fallback) {
        throw 'Manifest is missing generation.route.fallback.'
    }
    $fallback = $route.fallback
    if (-not [string]::IsNullOrWhiteSpace([string]$fallback.method)) {
        if ($fallback.changesConfirmedDirection -eq $true -and $fallback.confirmed -ne $true) {
            throw 'A fallback that changes the confirmed direction requires renewed user confirmation.'
        }
        if ($fallback.confirmed -eq $true) {
            Assert-Text $fallback.confirmationStatement 'generation.route.fallback.confirmationStatement'
            Assert-Text $fallback.confirmedAt 'generation.route.fallback.confirmedAt'
        }
    }

    $refusalCounts = @{}
    $allowedRefusalCategories = @('sexual_policy', 'minor_safety', 'nudity_policy', 'violence_policy', 'privacy_policy', 'copyright_policy', 'other_policy', 'network_error', 'technical_error')
    foreach ($refusal in @($script:manifest.generation.refusals)) {
        foreach ($field in @('method', 'version', 'category', 'scope', 'occurredAt', 'originalMessage')) {
            Assert-Text $refusal.$field ("generation.refusals[]." + $field)
        }
        if (@('current_attempt', 'current_channel') -notcontains [string]$refusal.scope) {
            throw 'A generation refusal must remain scoped to the current attempt or current channel.'
        }
        if ($allowedRefusalCategories -notcontains [string]$refusal.category) {
            throw "Unsupported generation refusal category: $($refusal.category)"
        }
        $key = ([string]$refusal.method + '|' + [string]$refusal.category)
        if (-not $refusalCounts.ContainsKey($key)) { $refusalCounts[$key] = 0 }
        $refusalCounts[$key]++
        if ($refusalCounts[$key] -gt 2) {
            throw "The same generation channel and refusal category exceeded the two-attempt stop condition: $key"
        }
    }

    foreach ($key in $refusalCounts.Keys) {
        if ($key.StartsWith(([string]$route.currentMethod + '|'), [System.StringComparison]::OrdinalIgnoreCase) -and $refusalCounts[$key] -ge 2) {
            throw 'The current generation channel already reached the same-root refusal stop condition.'
        }
    }
}

function Assert-ProductSourceReady {
    if ($null -eq $script:manifest.productPoster -or $script:manifest.productPoster.required -ne $true) {
        return
    }
    if ($null -eq $script:manifest.productPoster.productSource -or $script:manifest.productPoster.productSource.required -ne $true) {
        throw 'A product poster requires archived product source assets.'
    }

    $source = $script:manifest.productPoster.productSource
    $assets = @($source.assets)
    if ($assets.Count -eq 0) {
        throw 'A product poster requires at least one archived product source asset.'
    }
    $assetById = @{}
    foreach ($asset in $assets) {
        foreach ($field in @('id', 'path', 'sha256', 'role', 'view')) {
            Assert-Text $asset.$field ("productPoster.productSource.assets[]." + $field)
        }
        Assert-Sha256 $asset.sha256 'productPoster.productSource.assets[].sha256'
        if ($asset.approved -ne $true) {
            throw "Product source asset is not approved: $($asset.id)"
        }
        if ($assetById.ContainsKey([string]$asset.id)) {
            throw "Duplicate product source asset id: $($asset.id)"
        }
        $assetFull = Resolve-ProjectPath -RelativePath $asset.path -RequiredRoot 'temp\poster-jobs'
        if (-not (Test-Path -LiteralPath $assetFull -PathType Leaf)) {
            throw "Product source asset does not exist: $assetFull"
        }
        if ((Get-FileHash -LiteralPath $assetFull -Algorithm SHA256).Hash -ne [string]$asset.sha256) {
            throw "Product source asset hash does not match: $($asset.id)"
        }
        $assetById[[string]$asset.id] = $asset
    }

    if ($null -eq $source.identityLock) {
        throw 'A product poster requires a product identity lock.'
    }
    $lock = $source.identityLock
    Assert-Text $lock.recordPath 'productPoster.productSource.identityLock.recordPath'
    Assert-Sha256 $lock.recordSha256 'productPoster.productSource.identityLock.recordSha256'
    if ($lock.confirmed -ne $true) {
        throw 'The product identity lock is not confirmed.'
    }
    Assert-ConcreteCollection $lock.immutableComponents 'productPoster.productSource.identityLock.immutableComponents' 3 8
    Assert-ConcreteCollection $lock.connectionTopology 'productPoster.productSource.identityLock.connectionTopology' 2 8
    Assert-ConcreteCollection $lock.relativeGeometry 'productPoster.productSource.identityLock.relativeGeometry' 1 8
    Assert-ConcreteCollection $lock.appearanceTraits 'productPoster.productSource.identityLock.appearanceTraits' 1 8
    Assert-ConcreteCollection $lock.visibleViewBoundary 'productPoster.productSource.identityLock.visibleViewBoundary' 1 8
    Assert-ConcreteCollection $lock.allowedVariations 'productPoster.productSource.identityLock.allowedVariations' 1 8
    Assert-ConcreteCollection $lock.forbiddenVariations 'productPoster.productSource.identityLock.forbiddenVariations' 2 8

    $lockFull = Resolve-ProjectPath -RelativePath $lock.recordPath -RequiredRoot 'temp\poster-jobs'
    if (-not (Test-Path -LiteralPath $lockFull -PathType Leaf)) {
        throw 'Product identity-lock record does not exist.'
    }
    if ((Get-FileHash -LiteralPath $lockFull -Algorithm SHA256).Hash -ne [string]$lock.recordSha256) {
        throw 'Product identity-lock record hash does not match.'
    }

    if ($null -eq $source.currentBinding) {
        throw 'A product poster requires a current product-source binding.'
    }
    $binding = $source.currentBinding
    foreach ($field in @('jobId', 'version', 'method', 'status')) {
        Assert-Text $binding.$field ("productPoster.productSource.currentBinding." + $field)
    }
    if ([string]$binding.jobId -ne [string]$script:manifest.jobId) {
        throw 'Product-source binding is not bound to the current job.'
    }
    if ([string]$binding.version -ne [string]$script:manifest.generation.route.currentVersion) {
        throw 'Product-source binding is not bound to the current version.'
    }
    if ([string]$binding.method -ne [string]$script:manifest.generation.route.currentMethod) {
        throw 'Product-source binding is not bound to the current generation method.'
    }
    if (@('ready_to_upload', 'upload_verified', 'candidate_verified') -notcontains [string]$binding.status) {
        throw "Unsupported product-source binding status: $($binding.status)"
    }
    $bindingIds = @($binding.referenceAssetIds)
    $bindingHashes = @($binding.referenceSha256s)
    if ($bindingIds.Count -eq 0 -or $bindingIds.Count -ne $bindingHashes.Count) {
        throw 'Product-source binding must contain matching asset ids and hashes.'
    }
    for ($i = 0; $i -lt $bindingIds.Count; $i++) {
        $id = [string]$bindingIds[$i]
        if (-not $assetById.ContainsKey($id)) {
            throw "Product-source binding references an unknown asset: $id"
        }
        if ([string]$bindingHashes[$i] -ne [string]$assetById[$id].sha256) {
            throw "Product-source binding hash does not match asset: $id"
        }
    }

    if ([string]$script:manifest.generation.route.currentMethod -eq 'ChatGPT web via QQ Browser') {
        if ($script:manifest.assetTransfer.required -ne $true) {
            throw 'A QQ Browser product generation requires the current product source to be uploaded.'
        }
        foreach ($field in @('referenceAssetId', 'bindingJobId', 'bindingVersion', 'bindingMethod')) {
            Assert-Text $script:manifest.assetTransfer.$field ("assetTransfer." + $field)
        }
        if (-not $assetById.ContainsKey([string]$script:manifest.assetTransfer.referenceAssetId)) {
            throw 'assetTransfer.referenceAssetId is not an approved product source asset.'
        }
        $transferAsset = $assetById[[string]$script:manifest.assetTransfer.referenceAssetId]
        if ([string]$script:manifest.assetTransfer.assetPath -ne [string]$transferAsset.path -or [string]$script:manifest.assetTransfer.expectedSha256 -ne [string]$transferAsset.sha256) {
            throw 'Asset transfer path and hash must match the bound product source asset.'
        }
        if ([string]$script:manifest.assetTransfer.bindingJobId -ne [string]$script:manifest.jobId -or [string]$script:manifest.assetTransfer.bindingVersion -ne [string]$binding.version -or [string]$script:manifest.assetTransfer.bindingMethod -ne [string]$binding.method) {
            throw 'Asset transfer is not bound to the current job, version, and method.'
        }
    }
}

function Assert-BriefReady {
    Assert-Text $script:manifest.jobId 'jobId'
    Assert-Text $script:manifest.originThreadMode 'originThreadMode'
    if (@('main', 'test', 'production') -notcontains [string]$script:manifest.originThreadMode) {
        throw "Unsupported originThreadMode: $($script:manifest.originThreadMode)"
    }
    Assert-Text $script:manifest.brief.taskType 'brief.taskType'
    if (@('general_poster', 'product_sales_poster') -notcontains [string]$script:manifest.brief.taskType) {
        throw "Unsupported poster task type: $($script:manifest.brief.taskType)"
    }
    if ([string]$script:manifest.brief.taskType -eq 'product_sales_poster' -and ($null -eq $script:manifest.productPoster -or $script:manifest.productPoster.required -ne $true)) {
        throw 'A product_sales_poster task cannot disable the product-poster branch.'
    }
    if ([string]$script:manifest.brief.taskType -eq 'general_poster' -and $null -ne $script:manifest.productPoster -and $script:manifest.productPoster.required -eq $true) {
        throw 'A manifest with the product-poster branch enabled must use brief.taskType=product_sales_poster.'
    }
    Assert-Text $script:manifest.brief.theme 'brief.theme'
    Assert-Text $script:manifest.brief.purpose 'brief.purpose'
    Assert-Collection $script:manifest.brief.channels 'brief.channels'
    Assert-Text $script:manifest.brief.audience 'brief.audience'
    Assert-Collection $script:manifest.brief.mandatoryCopy 'brief.mandatoryCopy'
    Assert-Text $script:manifest.brief.editableCopyPolicy 'brief.editableCopyPolicy'
    Assert-Collection $script:manifest.brief.assets 'brief.assets'
    Assert-Text $script:manifest.brief.style 'brief.style'
    Assert-Text $script:manifest.brief.colors 'brief.colors'
    Assert-Collection $script:manifest.brief.forbidden 'brief.forbidden'
    Assert-Text $script:manifest.brief.size 'brief.size'
    Assert-Text $script:manifest.brief.outputFormat 'brief.outputFormat'
    Assert-Text $script:manifest.brief.deadline 'brief.deadline'

    if (@($script:manifest.brief.missing).Count -gt 0) {
        throw ('Brief still has missing fields: ' + (@($script:manifest.brief.missing) -join ', '))
    }
    if ($script:manifest.brief.confirmed -ne $true) {
        throw 'The complete brief has not been confirmed.'
    }
    Assert-Text $script:manifest.brief.confirmedAt 'brief.confirmedAt'
    Assert-Text $script:manifest.brief.confirmationStatement 'brief.confirmationStatement'

    $allowed = @('ready_to_generate', 'candidate_ready', 'awaiting_final_approval', 'approved', 'promoted')
    if ($allowed -notcontains [string]$script:manifest.status) {
        throw "Manifest status does not allow generation: $($script:manifest.status)"
    }

    Assert-ProductPosterReady
    Assert-GenerationRouteReady
    Assert-ProductSourceReady
    Assert-DesignTranslationReady
    Assert-PlatformCategoryAndSeriesReady
    Assert-CampaignIntentReady
}

function Assert-ProductPosterReady {
    if ($null -eq $script:manifest.productPoster -or $script:manifest.productPoster.required -ne $true) {
        return
    }

    $allowedStages = @('new_launch', 'daily_promotion', 'event_promotion', 'evergreen_brand', 'other_confirmed')
    if ($allowedStages -notcontains [string]$script:manifest.productPoster.campaignStage) {
        throw "Unsupported product poster campaign stage: $($script:manifest.productPoster.campaignStage)"
    }
    Assert-Text $script:manifest.productPoster.usageScenarioDecision 'productPoster.usageScenarioDecision'
    Assert-Text $script:manifest.productPoster.referencePolicy 'productPoster.referencePolicy'

    if ($null -eq $script:manifest.productPoster.variantPolicy) {
        throw 'Missing required field: productPoster.variantPolicy'
    }
    $allowedVariantModes = @('single', 'same_content_different_style', 'different_content_roles')
    $variantMode = [string]$script:manifest.productPoster.variantPolicy.mode
    if ($allowedVariantModes -notcontains $variantMode) {
        throw "Unsupported product poster variant mode: $variantMode"
    }
    if ($variantMode -eq 'same_content_different_style') {
        if ($script:manifest.productPoster.variantPolicy.contentLocked -ne $true) {
            throw 'Same-content product variants must lock the content contract.'
        }
        Assert-Collection $script:manifest.productPoster.variantPolicy.contentContract 'productPoster.variantPolicy.contentContract'
        Assert-Text $script:manifest.productPoster.variantPolicy.contentContractHash 'productPoster.variantPolicy.contentContractHash'
        if ([string]$script:manifest.productPoster.variantPolicy.contentContractHash -notmatch '^[A-Fa-f0-9]{64}$') {
            throw 'productPoster.variantPolicy.contentContractHash must be a SHA-256 value.'
        }
        Assert-Collection $script:manifest.productPoster.variantPolicy.allowedDifferences 'productPoster.variantPolicy.allowedDifferences'
    }

    $claims = @($script:manifest.productPoster.claims)
    if ($claims.Count -eq 0) {
        throw 'A product poster requires a verified claim-evidence table before generation.'
    }
    $allowedEvidenceTypes = @('user_confirmed', 'source_asset_visible', 'product_document')
    $claimIds = @{}
    foreach ($claim in $claims) {
        Assert-Text $claim.id 'productPoster.claims[].id'
        Assert-Text $claim.copy 'productPoster.claims[].copy'
        Assert-Text $claim.evidenceType 'productPoster.claims[].evidenceType'
        Assert-Text $claim.evidenceReference 'productPoster.claims[].evidenceReference'
        Assert-Text $claim.visualRequirement 'productPoster.claims[].visualRequirement'
        Assert-Text $claim.forbiddenVisual 'productPoster.claims[].forbiddenVisual'
        if ($allowedEvidenceTypes -notcontains [string]$claim.evidenceType) {
            throw "Unsupported product claim evidence type: $($claim.evidenceType)"
        }
        if ($claim.verified -ne $true) {
            throw "Product claim is not verified: $($claim.id)"
        }
        if ($claimIds.ContainsKey([string]$claim.id)) {
            throw "Duplicate product claim id: $($claim.id)"
        }
        $claimIds[[string]$claim.id] = $true
    }
}

function Assert-CandidateReady {
    Assert-BriefReady
    $allowed = @('candidate_ready', 'awaiting_final_approval', 'approved', 'promoted')
    if ($allowed -notcontains [string]$script:manifest.status) {
        throw "Manifest status does not contain a candidate: $($script:manifest.status)"
    }

    Assert-Text $script:manifest.generation.method 'generation.method'
    Assert-Text $script:manifest.generation.model 'generation.model'
    Assert-Text $script:manifest.generation.sourceReference 'generation.sourceReference'
    Assert-Text $script:manifest.generation.originalDownloadPath 'generation.originalDownloadPath'
    Assert-Text $script:manifest.candidate.role 'candidate.role'
    if ([string]$script:manifest.generation.method -ne [string]$script:manifest.generation.route.currentMethod) {
        throw 'Candidate generation.method does not match the authorized current route.'
    }

    $candidateFull = Resolve-ProjectPath -RelativePath $script:manifest.candidate.path -RequiredRoot 'temp'
    if (-not (Test-Path -LiteralPath $candidateFull -PathType Leaf)) {
        throw "Candidate file does not exist: $candidateFull"
    }

    $acceptanceFull = Resolve-ProjectPath -RelativePath $script:manifest.candidate.acceptancePath -RequiredRoot 'temp'
    if (-not (Test-Path -LiteralPath $acceptanceFull -PathType Leaf)) {
        throw "Acceptance evidence does not exist: $acceptanceFull"
    }

    Assert-Text $script:manifest.candidate.version 'candidate.version'
    Assert-Text $script:manifest.candidate.sha256 'candidate.sha256'
    Assert-Text $script:manifest.candidate.format 'candidate.format'
    if ([int64]$script:manifest.candidate.bytes -le 0) { throw 'candidate.bytes must be greater than zero.' }
    if ([int]$script:manifest.candidate.width -le 0) { throw 'candidate.width must be greater than zero.' }
    if ([int]$script:manifest.candidate.height -le 0) { throw 'candidate.height must be greater than zero.' }
    if ([double]$script:manifest.candidate.dpi -le 0) { throw 'candidate.dpi must be greater than zero.' }

    $actualHash = (Get-FileHash -LiteralPath $candidateFull -Algorithm SHA256).Hash
    if ($actualHash -ne [string]$script:manifest.candidate.sha256) {
        throw 'Candidate SHA-256 does not match the manifest.'
    }
    $actualBytes = (Get-Item -LiteralPath $candidateFull).Length
    if ($actualBytes -ne [int64]$script:manifest.candidate.bytes) {
        throw 'Candidate byte length does not match the manifest.'
    }

    $qualityFields = @('fileIntegrity', 'dimensionsChecked', 'textChecked', 'visualChecked', 'qrChecked', 'aiArtifactsChecked')
    foreach ($field in $qualityFields) {
        if ($script:manifest.candidate.quality.$field -ne $true) {
            throw "Candidate quality check is incomplete: $field"
        }
    }

    if ($null -eq $script:manifest.candidate.designReview) {
        throw 'Candidate is missing a design-direction and anti-AI aesthetic review.'
    }
    $designReview = $script:manifest.candidate.designReview
    Assert-Text $designReview.reviewPath 'candidate.designReview.reviewPath'
    Assert-Sha256 $designReview.reviewSha256 'candidate.designReview.reviewSha256'
    $designReviewFull = Resolve-ProjectPath -RelativePath $designReview.reviewPath -RequiredRoot 'temp\poster-jobs'
    if (-not (Test-Path -LiteralPath $designReviewFull -PathType Leaf)) {
        throw 'Candidate design review file does not exist.'
    }
    if ((Get-FileHash -LiteralPath $designReviewFull -Algorithm SHA256).Hash -ne [string]$designReview.reviewSha256) {
        throw 'Candidate design review hash does not match.'
    }
    foreach ($field in @('visualDNAAligned', 'antiAIPatternsAbsent', 'commercialAestheticChecked', 'passed')) {
        if ($designReview.$field -ne $true) {
            throw "Candidate design review did not pass: $field"
        }
    }
    if ($script:manifest.designTranslation.visualDNA.referenceRequired -eq $true -and $designReview.referenceCompared -ne $true) {
        throw 'A reference-sensitive candidate was not compared with the reference visual DNA.'
    }
    if (@($designReview.unresolvedDifferences).Count -gt 0) {
        throw 'Candidate design review contains unresolved differences.'
    }

    if ($null -ne $script:manifest.productPoster -and $script:manifest.productPoster.required -eq $true) {
        $productQualityFields = @('productStructureChecked', 'claimProvenanceChecked', 'claimVisualMappingChecked', 'variantContentConsistencyChecked', 'usageScenarioChecked')
        foreach ($field in $productQualityFields) {
            if ($script:manifest.candidate.quality.$field -ne $true) {
                throw "Product candidate quality check is incomplete: $field"
            }
        }

        if ($null -eq $script:manifest.candidate.productEvidence) {
            throw 'Product candidate is missing itemized claim-to-visual evidence.'
        }
        Assert-Text $script:manifest.candidate.productEvidence.reviewStatement 'candidate.productEvidence.reviewStatement'
        $mappings = @($script:manifest.candidate.productEvidence.mapping)
        $claims = @($script:manifest.productPoster.claims)
        if ($mappings.Count -ne $claims.Count) {
            throw 'Every product claim must have exactly one candidate visual mapping record.'
        }
        $mappingById = @{}
        foreach ($mapping in $mappings) {
            Assert-Text $mapping.claimId 'candidate.productEvidence.mapping[].claimId'
            Assert-Text $mapping.displayedCopy 'candidate.productEvidence.mapping[].displayedCopy'
            Assert-Text $mapping.visualShown 'candidate.productEvidence.mapping[].visualShown'
            Assert-Text $mapping.sourceReference 'candidate.productEvidence.mapping[].sourceReference'
            if ($mapping.mappingVerified -ne $true) {
                throw "Product claim-to-visual mapping is not verified: $($mapping.claimId)"
            }
            if ($mappingById.ContainsKey([string]$mapping.claimId)) {
                throw "Duplicate product visual mapping id: $($mapping.claimId)"
            }
            $mappingById[[string]$mapping.claimId] = $mapping
        }
        foreach ($claim in $claims) {
            if (-not $mappingById.ContainsKey([string]$claim.id)) {
                throw "Missing product visual mapping for claim: $($claim.id)"
            }
            if ([string]$mappingById[[string]$claim.id].displayedCopy -ne [string]$claim.copy) {
                throw "Displayed product claim differs from the locked claim text: $($claim.id)"
            }
        }

        if ($null -eq $script:manifest.candidate.productEvidence.fidelityReview) {
            throw 'Product candidate is missing a product-fidelity review.'
        }
        $fidelity = $script:manifest.candidate.productEvidence.fidelityReview
        Assert-Collection $fidelity.referenceAssetIds 'candidate.productEvidence.fidelityReview.referenceAssetIds'
        if ($fidelity.structureCompared -ne $true) { throw 'Product structure was not compared with the source asset.' }
        if ($fidelity.appearanceCompared -ne $true) { throw 'Product appearance was not compared with the source asset.' }
        if ($fidelity.unsupportedViewsAbsent -ne $true) { throw 'Unsupported product views were not ruled out.' }
        if (@($fidelity.differences).Count -gt 0) { throw 'Product candidate contains unresolved source differences.' }
        if ($fidelity.passed -ne $true) { throw 'Product-fidelity review did not pass.' }
        Assert-Text $fidelity.reviewStatement 'candidate.productEvidence.fidelityReview.reviewStatement'

        $boundIds = @($script:manifest.productPoster.productSource.currentBinding.referenceAssetIds)
        foreach ($id in @($fidelity.referenceAssetIds)) {
            if ($boundIds -notcontains [string]$id) {
                throw "Product-fidelity review references an asset not bound to this version: $id"
            }
        }
        if ([string]$script:manifest.productPoster.productSource.currentBinding.status -ne 'candidate_verified') {
            throw 'Product-source binding must be candidate_verified before candidate validation.'
        }
        if ([string]$script:manifest.generation.route.currentMethod -eq 'ChatGPT web via QQ Browser' -and [string]$script:manifest.assetTransfer.status -ne 'verified') {
            throw 'QQ Browser product candidate requires a verified product-source upload.'
        }
    }

    $isDualIntentPair = ($script:manifest.campaignIntent.splitRequired -eq $true)
    if ($isDualIntentPair) {
        if ($null -eq $script:manifest.candidateSet) {
            throw 'A dual-intent task is missing candidateSet.'
        }
        if ($script:manifest.candidateSet.required -ne $true) {
            throw 'A dual-intent task must require an independent candidateSet.'
        }

        $expectedRoles = @($script:manifest.candidateSet.expectedRoles)
        if ($expectedRoles.Count -ne 2 -or $expectedRoles -notcontains 'event_notice' -or $expectedRoles -notcontains 'sales_conversion') {
            throw 'candidateSet.expectedRoles must contain event_notice and sales_conversion exactly once.'
        }
        if (@($expectedRoles | Select-Object -Unique).Count -ne 2) {
            throw 'candidateSet.expectedRoles contains duplicate roles.'
        }
        if ($expectedRoles -notcontains [string]$script:manifest.candidate.role) {
            throw 'The current candidate role is not part of the dual-intent pair.'
        }

        $entries = @($script:manifest.candidateSet.entries)
        if ($entries.Count -lt 1 -or $entries.Count -gt 2) {
            throw 'A dual-intent candidateSet must contain one or two independently checked entries.'
        }
        $seenRoles = @{}
        foreach ($entry in $entries) {
            Assert-Text $entry.role 'candidateSet.entries[].role'
            Assert-Text $entry.path 'candidateSet.entries[].path'
            Assert-Text $entry.acceptancePath 'candidateSet.entries[].acceptancePath'
            Assert-Sha256 $entry.acceptanceSha256 'candidateSet.entries[].acceptanceSha256'
            Assert-Text $entry.designReviewPath 'candidateSet.entries[].designReviewPath'
            Assert-Sha256 $entry.designReviewSha256 'candidateSet.entries[].designReviewSha256'
            Assert-Text $entry.version 'candidateSet.entries[].version'
            Assert-Sha256 $entry.sha256 'candidateSet.entries[].sha256'
            Assert-Text $entry.checkedAt 'candidateSet.entries[].checkedAt'
            if ([int64]$entry.bytes -le 0) { throw 'candidateSet.entries[].bytes must be greater than zero.' }
            if ($entry.passed -ne $true) { throw "Candidate-set entry did not pass: $($entry.role)" }
            if ($expectedRoles -notcontains [string]$entry.role) { throw "Unexpected candidate-set role: $($entry.role)" }
            if ($seenRoles.ContainsKey([string]$entry.role)) { throw "Duplicate candidate-set role: $($entry.role)" }
            $seenRoles[[string]$entry.role] = $true

            $entryFull = Resolve-ProjectPath -RelativePath $entry.path -RequiredRoot 'temp\poster-jobs'
            if (-not (Test-Path -LiteralPath $entryFull -PathType Leaf)) { throw "Candidate-set file does not exist: $($entry.role)" }
            if ((Get-FileHash -LiteralPath $entryFull -Algorithm SHA256).Hash -ne [string]$entry.sha256) { throw "Candidate-set hash does not match: $($entry.role)" }
            if ((Get-Item -LiteralPath $entryFull).Length -ne [int64]$entry.bytes) { throw "Candidate-set byte length does not match: $($entry.role)" }

            $entryAcceptanceFull = Resolve-ProjectPath -RelativePath $entry.acceptancePath -RequiredRoot 'temp\poster-jobs'
            if (-not (Test-Path -LiteralPath $entryAcceptanceFull -PathType Leaf)) { throw "Candidate-set acceptance evidence does not exist: $($entry.role)" }
            if ((Get-FileHash -LiteralPath $entryAcceptanceFull -Algorithm SHA256).Hash -ne [string]$entry.acceptanceSha256) { throw "Candidate-set acceptance hash does not match: $($entry.role)" }

            $entryReviewFull = Resolve-ProjectPath -RelativePath $entry.designReviewPath -RequiredRoot 'temp\poster-jobs'
            if (-not (Test-Path -LiteralPath $entryReviewFull -PathType Leaf)) { throw "Candidate-set design review does not exist: $($entry.role)" }
            if ((Get-FileHash -LiteralPath $entryReviewFull -Algorithm SHA256).Hash -ne [string]$entry.designReviewSha256) { throw "Candidate-set design review hash does not match: $($entry.role)" }
        }

        $currentEntries = @($entries | Where-Object { [string]$_.role -eq [string]$script:manifest.candidate.role })
        if ($currentEntries.Count -ne 1) { throw 'The current dual-intent candidate must have exactly one ledger entry.' }
        $currentEntry = $currentEntries[0]
        if ([string]$currentEntry.path -ne [string]$script:manifest.candidate.path -or
            [string]$currentEntry.acceptancePath -ne [string]$script:manifest.candidate.acceptancePath -or
            [string]$currentEntry.designReviewPath -ne [string]$script:manifest.candidate.designReview.reviewPath -or
            [string]$currentEntry.version -ne [string]$script:manifest.candidate.version -or
            [string]$currentEntry.sha256 -ne [string]$script:manifest.candidate.sha256) {
            throw 'The current candidate fields do not match its candidateSet ledger entry.'
        }
    }
    else {
        if ($null -ne $script:manifest.candidateSet -and $script:manifest.candidateSet.required -eq $true) {
            throw 'A single-intent task must not require a candidate pair.'
        }
        if ([string]$script:manifest.candidate.role -ne [string]$script:manifest.campaignIntent.primary) {
            throw 'A single-intent candidate role must match campaignIntent.primary.'
        }
    }

    return [pscustomobject]@{
        CandidateFull = $candidateFull
        AcceptanceFull = $acceptanceFull
        Hash = $actualHash
    }
}

function Assert-AssetUploadReady {
    Assert-BriefReady
    if ($null -eq $script:manifest.assetTransfer) {
        throw 'Manifest is missing assetTransfer state.'
    }
    if ($script:manifest.assetTransfer.required -ne $true) {
        throw 'This task does not require an external asset upload.'
    }
    Assert-Text $script:manifest.assetTransfer.assetPath 'assetTransfer.assetPath'
    Assert-Text $script:manifest.assetTransfer.expectedSha256 'assetTransfer.expectedSha256'
    Assert-Text $script:manifest.assetTransfer.destination 'assetTransfer.destination'
    if ($script:manifest.assetTransfer.destination -ne 'ChatGPT web via QQ Browser') {
        throw "Unsupported asset upload destination: $($script:manifest.assetTransfer.destination)"
    }
    if ($script:manifest.assetTransfer.authorizationConfirmed -ne $true) {
        throw 'The user has not authorized this asset upload.'
    }
    Assert-Text $script:manifest.assetTransfer.authorizationStatement 'assetTransfer.authorizationStatement'
    Assert-Text $script:manifest.assetTransfer.authorizationAt 'assetTransfer.authorizationAt'
    if ($script:manifest.assetTransfer.pathTextEntered -eq $true) {
        throw 'A local file path was entered as webpage text; stop and clear the composer before continuing.'
    }

    $assetFull = Resolve-ProjectPath -RelativePath $script:manifest.assetTransfer.assetPath -RequiredRoot 'temp\poster-jobs'
    if (-not (Test-Path -LiteralPath $assetFull -PathType Leaf)) {
        throw "Upload asset does not exist: $assetFull"
    }
    $actualHash = (Get-FileHash -LiteralPath $assetFull -Algorithm SHA256).Hash
    if ($actualHash -ne [string]$script:manifest.assetTransfer.expectedSha256) {
        throw 'Upload asset SHA-256 does not match the manifest.'
    }

    return [pscustomobject]@{
        AssetFull = $assetFull
        FileName = [System.IO.Path]::GetFileName($assetFull)
        Hash = $actualHash
    }
}

function Assert-AssetUploadVerified {
    $asset = Assert-AssetUploadReady
    if ($script:manifest.assetTransfer.method -ne 'clipboard_file_paste') {
        throw 'The verified upload method must be clipboard_file_paste.'
    }
    if ($script:manifest.assetTransfer.clipboardPrepared -ne $true) {
        throw 'The image file was not verified on the clipboard.'
    }
    if ($script:manifest.assetTransfer.thumbnailVerified -ne $true) {
        throw 'The ChatGPT webpage asset thumbnail has not been verified.'
    }
    Assert-Text $script:manifest.assetTransfer.verifiedAssetName 'assetTransfer.verifiedAssetName'
    if ($script:manifest.assetTransfer.verifiedAssetName -ne $asset.FileName) {
        throw 'The verified webpage asset name does not match the archived file.'
    }
    Assert-Text $script:manifest.assetTransfer.verifiedAt 'assetTransfer.verifiedAt'
    if ($script:manifest.assetTransfer.status -ne 'verified') {
        throw "Asset transfer status must be verified: $($script:manifest.assetTransfer.status)"
    }
    if ($null -ne $script:manifest.productPoster -and $script:manifest.productPoster.required -eq $true) {
        if (@('upload_verified', 'candidate_verified') -notcontains [string]$script:manifest.productPoster.productSource.currentBinding.status) {
            throw 'Product-source binding must be upload_verified after webpage thumbnail verification.'
        }
    }
    return $asset
}

function Assert-Timestamp {
    param([object]$Value, [string]$Label)
    Assert-Text $Value $Label
    $parsed = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse([string]$Value, [ref]$parsed)) { throw "$Label must be a valid timestamp." }
}

function Get-RelativeProjectPath {
    param([string]$FullPath)
    return $FullPath.Substring($script:rootFull.Length).TrimStart('\', '/').Replace('\', '/')
}

function Get-PromotionReceiptPath {
    $jobDirectory = Split-Path -Parent $script:manifestFull
    Assert-NoReparsePoints -Path $jobDirectory -AllowedRoot $script:rootFull
    return Join-Path $jobDirectory 'promotion-receipt.json'
}

function Write-BytesAtomically {
    param([string]$Path, [byte[]]$Bytes)
    $temporary = Join-Path (Split-Path -Parent $Path) ('.gate-' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [System.IO.File]::WriteAllBytes($temporary, $Bytes)
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            $backup = Join-Path (Split-Path -Parent $Path) ('.gate-' + [guid]::NewGuid().ToString('N') + '.bak')
            try { [System.IO.File]::Replace($temporary, $Path, $backup) }
            finally { if (Test-Path -LiteralPath $backup -PathType Leaf) { Remove-Item -LiteralPath $backup -Force } }
        }
        else { [System.IO.File]::Move($temporary, $Path) }
    }
    finally { if (Test-Path -LiteralPath $temporary -PathType Leaf) { Remove-Item -LiteralPath $temporary -Force } }
}

function Convert-JsonToUtf8Bytes {
    param([object]$Value, [int]$Depth = 20)
    $json = $Value | ConvertTo-Json -Depth $Depth
    return (New-Object System.Text.UTF8Encoding($false)).GetBytes($json)
}

function Add-PromotionEvidence {
    param(
        [System.Collections.ArrayList]$Target,
        [hashtable]$Seen,
        [string]$RelativePath,
        [string]$Kind,
        [string]$Role,
        [string]$RequiredRoot = '',
        [string]$ExpectedSha256 = ''
    )
    Assert-Text $Kind 'promotion evidence kind'
    Assert-Text $Role ("promotion evidence role for $Kind")
    $full = Resolve-ProjectPath -RelativePath $RelativePath -RequiredRoot $RequiredRoot
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "Promotion evidence file does not exist: $Kind/$Role" }
    $relative = Get-RelativeProjectPath $full
    $key = $Kind + '|' + $Role + '|' + $relative
    if ($Seen.ContainsKey($key)) { return }
    $bytes = [int64](Get-Item -LiteralPath $full).Length
    if ($bytes -le 0) { throw "Promotion evidence file is empty: $Kind/$Role" }
    $sha256 = [string](Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash
    if ($ExpectedSha256 -and $sha256 -ne $ExpectedSha256) { throw "Promotion evidence hash differs from the manifest: $Kind/$Role" }
    [void]$Target.Add([ordered]@{ path=$relative; bytes=$bytes; sha256=$sha256; kind=$Kind; role=$Role })
    $Seen[$key] = $true
}

function Get-PromotionEvidence {
    $evidence = New-Object System.Collections.ArrayList
    $seen = @{}
    Add-PromotionEvidence -Target $evidence -Seen $seen -RelativePath ([string]$script:manifest.designTranslation.framework.path) -Kind 'prompt_framework' -Role 'global' -RequiredRoot 'templates' -ExpectedSha256 ([string]$script:manifest.designTranslation.framework.sha256)
    if ($script:manifest.designTranslation.visualDNA.referenceRequired -eq $true) {
        foreach ($reference in @($script:manifest.designTranslation.visualDNA.referenceAssets)) {
            Add-PromotionEvidence -Target $evidence -Seen $seen -RelativePath ([string]$reference.path) -Kind 'visual_reference' -Role ([string]$reference.id) -RequiredRoot 'temp\poster-jobs' -ExpectedSha256 ([string]$reference.sha256)
        }
    }
    Add-PromotionEvidence -Target $evidence -Seen $seen -RelativePath ([string]$script:manifest.designTranslation.promptBuild.path) -Kind 'generation_prompt' -Role ([string]$script:manifest.candidate.version) -RequiredRoot 'temp\poster-jobs' -ExpectedSha256 ([string]$script:manifest.designTranslation.promptBuild.sha256)
    Add-PromotionEvidence -Target $evidence -Seen $seen -RelativePath ([string]$script:manifest.deliveryProfile.profilePath) -Kind 'platform_profile' -Role ([string]$script:manifest.deliveryProfile.platform) -RequiredRoot 'skills\creating-promotional-posters\references' -ExpectedSha256 ([string]$script:manifest.deliveryProfile.profileSha256)
    Add-PromotionEvidence -Target $evidence -Seen $seen -RelativePath ([string]$script:manifest.categoryProfile.adapterPath) -Kind 'category_adapter' -Role ([string]$script:manifest.categoryProfile.id) -RequiredRoot 'skills\creating-promotional-posters\references' -ExpectedSha256 ([string]$script:manifest.categoryProfile.adapterSha256)

    if ($null -ne $script:manifest.productPoster -and $script:manifest.productPoster.required -eq $true) {
        foreach ($asset in @($script:manifest.productPoster.productSource.assets)) {
            Add-PromotionEvidence -Target $evidence -Seen $seen -RelativePath ([string]$asset.path) -Kind 'product_asset' -Role ([string]$asset.id) -RequiredRoot 'temp\poster-jobs' -ExpectedSha256 ([string]$asset.sha256)
        }
        $identityLock = $script:manifest.productPoster.productSource.identityLock
        Add-PromotionEvidence -Target $evidence -Seen $seen -RelativePath ([string]$identityLock.recordPath) -Kind 'product_identity_lock' -Role 'current' -RequiredRoot 'temp\poster-jobs' -ExpectedSha256 ([string]$identityLock.recordSha256)
        if ($null -ne $script:manifest.assetTransfer -and $script:manifest.assetTransfer.required -eq $true) {
            Add-PromotionEvidence -Target $evidence -Seen $seen -RelativePath ([string]$script:manifest.assetTransfer.assetPath) -Kind 'asset_transfer' -Role ([string]$script:manifest.candidate.version) -RequiredRoot 'temp\poster-jobs' -ExpectedSha256 ([string]$script:manifest.assetTransfer.expectedSha256)
        }
    }

    if ($script:manifest.campaignIntent.splitRequired -eq $true) {
        foreach ($entry in @($script:manifest.candidateSet.entries | Sort-Object -Property role)) {
            Add-PromotionEvidence -Target $evidence -Seen $seen -RelativePath ([string]$entry.path) -Kind 'candidate' -Role ([string]$entry.role) -RequiredRoot 'temp\poster-jobs' -ExpectedSha256 ([string]$entry.sha256)
            Add-PromotionEvidence -Target $evidence -Seen $seen -RelativePath ([string]$entry.acceptancePath) -Kind 'acceptance' -Role ([string]$entry.role) -RequiredRoot 'temp\poster-jobs' -ExpectedSha256 ([string]$entry.acceptanceSha256)
            Add-PromotionEvidence -Target $evidence -Seen $seen -RelativePath ([string]$entry.designReviewPath) -Kind 'design_review' -Role ([string]$entry.role) -RequiredRoot 'temp\poster-jobs' -ExpectedSha256 ([string]$entry.designReviewSha256)
        }
        $pairReview = $script:manifest.candidateSet.pairReview
        Add-PromotionEvidence -Target $evidence -Seen $seen -RelativePath ([string]$pairReview.reviewPath) -Kind 'pair_review' -Role 'dual_intent_pair' -RequiredRoot 'temp\poster-jobs' -ExpectedSha256 ([string]$pairReview.reviewSha256)
    }
    else {
        Add-PromotionEvidence -Target $evidence -Seen $seen -RelativePath ([string]$script:manifest.candidate.path) -Kind 'candidate' -Role ([string]$script:manifest.candidate.role) -RequiredRoot 'temp\poster-jobs' -ExpectedSha256 ([string]$script:manifest.candidate.sha256)
        Add-PromotionEvidence -Target $evidence -Seen $seen -RelativePath ([string]$script:manifest.candidate.acceptancePath) -Kind 'acceptance' -Role ([string]$script:manifest.candidate.role) -RequiredRoot 'temp\poster-jobs'
        Add-PromotionEvidence -Target $evidence -Seen $seen -RelativePath ([string]$script:manifest.candidate.designReview.reviewPath) -Kind 'design_review' -Role ([string]$script:manifest.candidate.role) -RequiredRoot 'temp\poster-jobs' -ExpectedSha256 ([string]$script:manifest.candidate.designReview.reviewSha256)
    }
    return @($evidence)
}

function Assert-PromotionEvidenceBinding {
    param([object[]]$Recorded, [object[]]$Current)
    if ($Recorded.Count -eq 0 -or $Recorded.Count -ne $Current.Count) { throw 'Promotion receipt evidence count differs.' }
    for ($i = 0; $i -lt $Current.Count; $i++) {
        foreach ($field in @('path','sha256','kind','role')) {
            if ([string]$Recorded[$i].$field -ne [string]$Current[$i].$field) { throw "Promotion receipt evidence binding differs at index $i." }
        }
        if ([int64]$Recorded[$i].bytes -ne [int64]$Current[$i].bytes) { throw "Promotion receipt evidence byte length differs at index $i." }
    }
}

function Get-PromotionLockPath {
    $jobDirectory = Split-Path -Parent $script:manifestFull
    Assert-NoReparsePoints -Path $jobDirectory -AllowedRoot $script:rootFull
    return Join-Path $jobDirectory '.promotion.lock'
}

function Read-PromotionLockOwner {
    param([string]$OwnerPath)
    try {
        if (-not (Test-Path -LiteralPath $OwnerPath -PathType Leaf)) { return $null }
        $item = Get-Item -LiteralPath $OwnerPath -Force
        if ($item.Length -le 0 -or $item.Length -gt 4096 -or ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { return $null }
        $owner = Get-Content -Raw -Encoding UTF8 -LiteralPath $OwnerPath | ConvertFrom-Json
        if ([string]$owner.schemaVersion -ne '1.0' -or [string]$owner.nonce -notmatch '^[a-f0-9]{32}$' -or [int]$owner.pid -le 0 -or [int64]$owner.processStartUtcTicks -le 0) { return $null }
        $acquiredAt = [DateTimeOffset]::MinValue
        if (-not [DateTimeOffset]::TryParse([string]$owner.acquiredAt, [ref]$acquiredAt)) { return $null }
        return $owner
    }
    catch { return $null }
}

function Test-SamePromotionLockOwner {
    param([object]$Left, [object]$Right)
    return $null -ne $Left -and $null -ne $Right -and
        [string]$Left.nonce -eq [string]$Right.nonce -and
        [int]$Left.pid -eq [int]$Right.pid -and
        [int64]$Left.processStartUtcTicks -eq [int64]$Right.processStartUtcTicks -and
        [string]$Left.acquiredAt -eq [string]$Right.acquiredAt
}

function Test-PromotionLockOwnerAlive {
    param([object]$Owner)
    try {
        $process = Get-Process -Id ([int]$Owner.pid) -ErrorAction Stop
        return [int64]$process.StartTime.ToUniversalTime().Ticks -eq [int64]$Owner.processStartUtcTicks
    }
    catch { return $false }
}

function Move-PromotionLockToIsolation {
    param([string]$LockPath, [object]$ExpectedOwner, [string]$Purpose)
    $isolation = $LockPath + '.' + $Purpose + '-' + $PID + '-' + [guid]::NewGuid().ToString('N')
    try { [System.IO.Directory]::Move($LockPath, $isolation) }
    catch [System.IO.IOException] { return $false }
    catch [System.UnauthorizedAccessException] { return $false }

    $isolatedOwner = Read-PromotionLockOwner -OwnerPath (Join-Path $isolation 'owner.json')
    if (-not (Test-SamePromotionLockOwner -Left $isolatedOwner -Right $ExpectedOwner)) {
        if (-not (Test-Path -LiteralPath $LockPath)) {
            try { [System.IO.Directory]::Move($isolation, $LockPath) } catch { }
        }
        throw 'Promotion lock owner changed during atomic isolation; manual recovery is required.'
    }
    Remove-Item -LiteralPath $isolation -Recurse -Force
    return $true
}

function Enter-PromotionLock {
    param([int]$TimeoutMilliseconds = 15000, [int]$StaleMilliseconds = 30000)
    $lockPath = Get-PromotionLockPath
    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMilliseconds)
    $process = Get-Process -Id $PID -ErrorAction Stop
    $owner = [ordered]@{
        schemaVersion = '1.0'
        nonce = [guid]::NewGuid().ToString('N')
        pid = [int]$PID
        processStartUtcTicks = [int64]$process.StartTime.ToUniversalTime().Ticks
        acquiredAt = [DateTimeOffset]::UtcNow.ToString('o')
    }
    $staging = $lockPath + '.staging-' + $PID + '-' + [string]$owner.nonce
    New-Item -ItemType Directory -Path $staging -ErrorAction Stop | Out-Null
    try {
        [System.IO.File]::WriteAllBytes((Join-Path $staging 'owner.json'), (Convert-JsonToUtf8Bytes -Value $owner -Depth 4))
        while ($true) {
            try {
                [System.IO.Directory]::Move($staging, $lockPath)
                return [pscustomobject]@{ LockPath=$lockPath; Owner=$owner }
            }
            catch [System.IO.IOException] { }
            catch [System.UnauthorizedAccessException] { }

            $lockItem = Get-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue
            if ($null -ne $lockItem -and ($lockItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Promotion lock path must not be a reparse point.' }
            $existingOwner = Read-PromotionLockOwner -OwnerPath (Join-Path $lockPath 'owner.json')
            if ($null -ne $existingOwner) {
                if (Test-SamePromotionLockOwner -Left $existingOwner -Right $owner) { throw 'Reentrant promotion lock acquisition is not allowed.' }
                $acquired = [DateTimeOffset]::Parse([string]$existingOwner.acquiredAt)
                $age = ([DateTimeOffset]::UtcNow - $acquired).TotalMilliseconds
                if ($age -ge $StaleMilliseconds -and -not (Test-PromotionLockOwnerAlive -Owner $existingOwner)) {
                    if (Move-PromotionLockToIsolation -LockPath $lockPath -ExpectedOwner $existingOwner -Purpose 'stale') { continue }
                }
            }
            if ([DateTime]::UtcNow -ge $deadline) { throw 'Timed out waiting for the promotion transaction lock.' }
            Start-Sleep -Milliseconds 25
        }
    }
    finally {
        if (Test-Path -LiteralPath $staging -PathType Container) { Remove-Item -LiteralPath $staging -Recurse -Force }
    }
}

function Exit-PromotionLock {
    param([object]$Lock)
    $current = Read-PromotionLockOwner -OwnerPath (Join-Path $Lock.LockPath 'owner.json')
    if (-not (Test-SamePromotionLockOwner -Left $current -Right $Lock.Owner)) { throw 'Promotion lock owner differs during release; refusing to remove it.' }
    if (-not (Move-PromotionLockToIsolation -LockPath $Lock.LockPath -ExpectedOwner $Lock.Owner -Purpose 'release')) { throw 'Promotion lock disappeared during release.' }
}

function Get-VerifiedPromotedOutputs {
    $candidate = Assert-CandidateReady
    if ([string]$script:manifest.status -ne 'promoted' -or $script:manifest.promotion.promoted -ne $true) {
        throw 'Manifest is not a promoted poster result.'
    }
    if ($script:manifest.approval.approved -ne $true) { throw 'The promoted poster is missing final approval.' }
    Assert-Text $script:manifest.approval.statement 'approval.statement'
    Assert-Timestamp $script:manifest.approval.approvedAt 'approval.approvedAt'
    Assert-Timestamp $script:manifest.promotion.promotedAt 'promotion.promotedAt'
    if (@('main', 'production') -notcontains [string]$script:manifest.promotion.promotedBy) { throw 'promotion.promotedBy is not a formal actor.' }

    $outputs = New-Object System.Collections.ArrayList
    if ($script:manifest.campaignIntent.splitRequired -eq $true) {
        $entries = @($script:manifest.candidateSet.entries)
        $items = @($script:manifest.promotion.outputItems)
        if ($entries.Count -ne 2 -or $items.Count -ne 2) { throw 'A promoted dual-intent pair must contain exactly two outputs.' }
        $pairReview = $script:manifest.candidateSet.pairReview
        Assert-Text $pairReview.reviewPath 'candidateSet.pairReview.reviewPath'
        Assert-Sha256 $pairReview.reviewSha256 'candidateSet.pairReview.reviewSha256'
        $pairReviewFull = Resolve-ProjectPath -RelativePath $pairReview.reviewPath -RequiredRoot 'temp\poster-jobs'
        if (-not (Test-Path -LiteralPath $pairReviewFull -PathType Leaf) -or (Get-FileHash -LiteralPath $pairReviewFull -Algorithm SHA256).Hash -ne [string]$pairReview.reviewSha256) {
            throw 'Dual-intent pair review evidence is missing or changed.'
        }
        foreach ($field in @('visualConsistencyChecked', 'factConsistencyChecked', 'distinctPrimaryActionsChecked', 'passed')) {
            if ($pairReview.$field -ne $true) { throw "Dual-intent pair review did not pass: $field" }
        }
        foreach ($role in @('event_notice', 'sales_conversion')) {
            $entryMatches = @($entries | Where-Object { [string]$_.role -eq $role })
            $itemMatches = @($items | Where-Object { [string]$_.role -eq $role })
            if ($entryMatches.Count -ne 1 -or $itemMatches.Count -ne 1) { throw "Promoted pair mapping is incomplete: $role" }
            $entry = $entryMatches[0]; $item = $itemMatches[0]
            if ([string]$item.candidatePath -ne [string]$entry.path -or [string]$item.sha256 -ne [string]$entry.sha256) { throw "Promoted pair mapping differs from candidate evidence: $role" }
            $outputFull = Resolve-ProjectPath -RelativePath $item.outputPath -RequiredRoot 'outputs'
            if (-not (Test-Path -LiteralPath $outputFull -PathType Leaf)) { throw "Promoted output does not exist: $role" }
            $hash = (Get-FileHash -LiteralPath $outputFull -Algorithm SHA256).Hash
            $bytes = (Get-Item -LiteralPath $outputFull).Length
            if ($hash -ne [string]$entry.sha256 -or $bytes -ne [int64]$entry.bytes) { throw "Promoted output integrity differs: $role" }
            [void]$outputs.Add([ordered]@{ role=$role; path=[string]$item.outputPath; fileName=[System.IO.Path]::GetFileName($outputFull); bytes=[int64]$bytes; sha256=[string]$hash })
        }
    }
    else {
        $outputFull = Resolve-ProjectPath -RelativePath $script:manifest.promotion.outputPath -RequiredRoot 'outputs'
        if (-not (Test-Path -LiteralPath $outputFull -PathType Leaf)) { throw 'Promoted poster output does not exist.' }
        $hash = (Get-FileHash -LiteralPath $outputFull -Algorithm SHA256).Hash
        $bytes = (Get-Item -LiteralPath $outputFull).Length
        if ($hash -ne [string]$script:manifest.candidate.sha256 -or $bytes -ne [int64]$script:manifest.candidate.bytes) { throw 'Promoted poster output integrity differs from the candidate.' }
        [void]$outputs.Add([ordered]@{ role=[string]$script:manifest.candidate.role; path=[string]$script:manifest.promotion.outputPath; fileName=[System.IO.Path]::GetFileName($outputFull); bytes=[int64]$bytes; sha256=[string]$hash })
    }
    return @($outputs)
}

function Assert-PromotionReceipt {
    param([object[]]$Outputs)
    $receiptPath = Get-PromotionReceiptPath
    if (-not (Test-Path -LiteralPath $receiptPath -PathType Leaf)) { throw 'Gate-owned promotion receipt is missing.' }
    Assert-NoReparsePoints -Path $receiptPath -AllowedRoot $script:rootFull
    $receipt = Get-Content -Raw -Encoding UTF8 -LiteralPath $receiptPath | ConvertFrom-Json
    if ([string]$receipt.schemaVersion -ne '1.0' -or [string]$receipt.receiptKind -ne 'promotion-gate-receipt' -or [string]$receipt.gateKind -ne 'promotional-poster') { throw 'Promotion receipt type is invalid.' }
    if ([string]$receipt.nonce -notmatch '^[a-f0-9]{32}$') { throw 'Promotion receipt nonce is invalid.' }
    if ([string]$receipt.jobId -ne [string]$script:manifest.jobId -or [string]$receipt.manifestPath -ne (Get-RelativeProjectPath $script:manifestFull)) { throw 'Promotion receipt job binding is invalid.' }
    $manifestHash = (Get-FileHash -LiteralPath $script:manifestFull -Algorithm SHA256).Hash
    if ([string]$receipt.manifestSha256 -ne $manifestHash -or [string]$receipt.promotedAt -ne [string]$script:manifest.promotion.promotedAt -or [string]$receipt.promotedBy -ne [string]$script:manifest.promotion.promotedBy) { throw 'Promotion receipt manifest binding is invalid.' }
    $receiptOutputs = @($receipt.outputs)
    if ($receiptOutputs.Count -ne $Outputs.Count) { throw 'Promotion receipt output count differs.' }
    for ($i = 0; $i -lt $Outputs.Count; $i++) {
        foreach ($field in @('role','path','fileName','sha256')) { if ([string]$receiptOutputs[$i].$field -ne [string]$Outputs[$i].$field) { throw "Promotion receipt output binding differs at index $i." } }
        if ([int64]$receiptOutputs[$i].bytes -ne [int64]$Outputs[$i].bytes) { throw "Promotion receipt output byte length differs at index $i." }
    }
    $currentEvidence = @(Get-PromotionEvidence)
    Assert-PromotionEvidenceBinding -Recorded @($receipt.evidence) -Current $currentEvidence
    return [pscustomobject]@{ Receipt=$receipt; ManifestHash=$manifestHash; ReceiptPath=$receiptPath; Evidence=$currentEvidence }
}

function Assert-PromotionReady {
    $candidate = Assert-CandidateReady
    if ($ActorMode -eq 'test') {
        throw 'Test-thread actors cannot promote files to outputs/.'
    }
    if ($script:manifest.status -ne 'approved') {
        throw "Manifest must be approved before promotion: $($script:manifest.status)"
    }
    if ($script:manifest.approval.approved -ne $true) {
        throw 'The user has not approved the final candidate.'
    }
    Assert-Text $script:manifest.approval.statement 'approval.statement'
    Assert-Text $script:manifest.approval.approvedAt 'approval.approvedAt'
    if ($script:manifest.promotion.promoted -eq $true) {
        throw 'This manifest has already been promoted.'
    }
    if (Test-Path -LiteralPath (Get-PromotionReceiptPath)) {
        throw 'A stale promotion receipt already exists for this job.'
    }

    $promotionItems = @()
    if ($script:manifest.campaignIntent.splitRequired -eq $true) {
        $entries = @($script:manifest.candidateSet.entries)
        if ($entries.Count -ne 2) {
            throw 'A dual-intent pair requires two independently checked candidateSet entries before promotion.'
        }

        $pairReview = $script:manifest.candidateSet.pairReview
        if ($null -eq $pairReview) { throw 'A dual-intent pair is missing pairReview.' }
        Assert-Text $pairReview.reviewPath 'candidateSet.pairReview.reviewPath'
        Assert-Sha256 $pairReview.reviewSha256 'candidateSet.pairReview.reviewSha256'
        $pairReviewFull = Resolve-ProjectPath -RelativePath $pairReview.reviewPath -RequiredRoot 'temp\poster-jobs'
        if (-not (Test-Path -LiteralPath $pairReviewFull -PathType Leaf)) { throw 'The pair-review evidence file does not exist.' }
        if ((Get-FileHash -LiteralPath $pairReviewFull -Algorithm SHA256).Hash -ne [string]$pairReview.reviewSha256) { throw 'The pair-review evidence hash does not match.' }
        foreach ($field in @('visualConsistencyChecked', 'factConsistencyChecked', 'distinctPrimaryActionsChecked', 'passed')) {
            if ($pairReview.$field -ne $true) { throw "Dual-intent pair review did not pass: $field" }
        }

        $outputItems = @($script:manifest.promotion.outputItems)
        if ($outputItems.Count -ne 2) { throw 'promotion.outputItems must contain exactly two dual-intent outputs.' }
        foreach ($role in @('event_notice', 'sales_conversion')) {
            $entryMatches = @($entries | Where-Object { [string]$_.role -eq $role })
            $outputMatches = @($outputItems | Where-Object { [string]$_.role -eq $role })
            if ($entryMatches.Count -ne 1 -or $outputMatches.Count -ne 1) { throw "Dual-intent promotion must map exactly one candidate and output for: $role" }
            $entry = $entryMatches[0]
            $item = $outputMatches[0]
            Assert-Text $item.candidatePath 'promotion.outputItems[].candidatePath'
            Assert-Text $item.outputPath 'promotion.outputItems[].outputPath'
            Assert-Sha256 $item.sha256 'promotion.outputItems[].sha256'
            if ([string]$item.candidatePath -ne [string]$entry.path -or [string]$item.sha256 -ne [string]$entry.sha256) {
                throw "Promotion output does not match its candidate ledger entry: $role"
            }
            $candidateFull = Resolve-ProjectPath -RelativePath $item.candidatePath -RequiredRoot 'temp\poster-jobs'
            $outputFull = Resolve-ProjectPath -RelativePath $item.outputPath -RequiredRoot 'outputs'
            if (Test-Path -LiteralPath $outputFull) { throw "Refusing to overwrite an existing formal output: $outputFull" }
            $promotionItems += [pscustomobject]@{ Role = $role; CandidateFull = $candidateFull; OutputFull = $outputFull; Hash = [string]$entry.sha256 }
        }
    }
    else {
        $outputFull = Resolve-ProjectPath -RelativePath $script:manifest.promotion.outputPath -RequiredRoot 'outputs'
        if (Test-Path -LiteralPath $outputFull) { throw "Refusing to overwrite an existing formal output: $outputFull" }
        $promotionItems = @([pscustomobject]@{ Role = [string]$script:manifest.candidate.role; CandidateFull = $candidate.CandidateFull; OutputFull = $outputFull; Hash = $candidate.Hash })
    }

    return [pscustomobject]@{ Items = @($promotionItems); IsPair = ($script:manifest.campaignIntent.splitRequired -eq $true) }
}

$promotionLock = $null
try {
    $rootFull = Get-NormalizedRoot $ProjectRoot
    if (-not (Test-Path -LiteralPath $rootFull -PathType Container)) {
        throw "Project root does not exist: $rootFull"
    }

    $manifestFull = [System.IO.Path]::GetFullPath($ManifestPath)
    if (-not (Test-IsWithin -Path $manifestFull -Root $rootFull)) {
        throw 'Manifest must be inside the project root.'
    }
    if (-not (Test-Path -LiteralPath $manifestFull -PathType Leaf)) {
        throw "Manifest does not exist: $manifestFull"
    }

    if ($Action -eq 'Promote') {
        $promotionLock = Enter-PromotionLock
        if (-not (Test-Path -LiteralPath $manifestFull -PathType Leaf)) { throw 'Manifest disappeared after the promotion lock was acquired.' }
    }

    $originalManifestBytes = [System.IO.File]::ReadAllBytes($manifestFull)
    $manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $manifestFull | ConvertFrom-Json
    if ($manifest.schemaVersion -ne '1.0') {
        throw "Unsupported manifest schemaVersion: $($manifest.schemaVersion)"
    }

    switch ($Action) {
        'CheckBeforeGenerate' {
            Assert-BriefReady
            Write-Output 'PASS: brief is complete and confirmed; generation is allowed.'
        }
        'CheckBeforeUpload' {
            $null = Assert-AssetUploadReady
            Write-Output 'PASS: asset is archived, hash-verified, and authorized for upload.'
        }
        'CheckAfterUpload' {
            $null = Assert-AssetUploadVerified
            Write-Output 'PASS: clipboard file upload and webpage thumbnail are verified.'
        }
        'CheckCandidate' {
            $null = Assert-CandidateReady
            Write-Output 'PASS: candidate evidence is complete and isolated in temp/.'
        }
        'CheckBeforePromote' {
            $null = Assert-PromotionReady
            Write-Output 'PASS: approved candidate is ready for formal promotion.'
        }
        'Promote' {
            $promotion = Assert-PromotionReady
            $promotionEvidence = @(Get-PromotionEvidence)
            foreach ($item in @($promotion.Items)) {
                $outputParent = Split-Path -Parent $item.OutputFull
                if (-not (Test-Path -LiteralPath $outputParent -PathType Container)) {
                    New-Item -ItemType Directory -Force -Path $outputParent | Out-Null
                }
            }

            $createdPaths = @()
            $manifestWritten = $false
            $receiptPath = Get-PromotionReceiptPath
            try {
                foreach ($item in @($promotion.Items)) {
                    Copy-Item -LiteralPath $item.CandidateFull -Destination $item.OutputFull
                    $createdPaths += $item.OutputFull
                    $outputHash = (Get-FileHash -LiteralPath $item.OutputFull -Algorithm SHA256).Hash
                    if ($outputHash -ne $item.Hash) {
                        throw "Promoted output SHA-256 differs from the candidate: $($item.Role)"
                    }
                }

                $currentEvidence = @(Get-PromotionEvidence)
                Assert-PromotionEvidenceBinding -Recorded $promotionEvidence -Current $currentEvidence

                $manifest.status = 'promoted'
                $manifest.promotion.promoted = $true
                $manifest.promotion.promotedAt = (Get-Date).ToString('o')
                $manifest.promotion.promotedBy = $ActorMode
                Write-BytesAtomically -Path $manifestFull -Bytes (Convert-JsonToUtf8Bytes -Value $manifest -Depth 20)
                $manifestWritten = $true
                $manifestHash = (Get-FileHash -LiteralPath $manifestFull -Algorithm SHA256).Hash
                $receiptOutputs = @()
                foreach ($item in @($promotion.Items)) {
                    $receiptOutputs += [ordered]@{
                        role = [string]$item.Role
                        path = Get-RelativeProjectPath $item.OutputFull
                        fileName = [System.IO.Path]::GetFileName($item.OutputFull)
                        bytes = [int64](Get-Item -LiteralPath $item.OutputFull).Length
                        sha256 = [string](Get-FileHash -LiteralPath $item.OutputFull -Algorithm SHA256).Hash
                    }
                }
                $receipt = [ordered]@{
                    schemaVersion = '1.0'; receiptKind = 'promotion-gate-receipt'; gateKind = 'promotional-poster'
                    nonce = [guid]::NewGuid().ToString('N'); jobId = [string]$manifest.jobId
                    manifestPath = Get-RelativeProjectPath $manifestFull; manifestSha256 = $manifestHash
                    promotedAt = [string]$manifest.promotion.promotedAt; promotedBy = [string]$manifest.promotion.promotedBy
                    outputs = @($receiptOutputs)
                    evidence = @($promotionEvidence)
                }
                Write-BytesAtomically -Path $receiptPath -Bytes (Convert-JsonToUtf8Bytes -Value $receipt -Depth 10)
                $promotedPaths = @($promotion.Items | ForEach-Object { $_.OutputFull.Substring($rootFull.Length).TrimStart('\', '/') })
                Write-Output "PASS: promoted $($promotedPaths.Count) output(s): $($promotedPaths -join ', ')"
            }
            catch {
                if (Test-Path -LiteralPath $receiptPath -PathType Leaf) { Remove-Item -LiteralPath $receiptPath -Force }
                if ($manifestWritten) { Write-BytesAtomically -Path $manifestFull -Bytes $originalManifestBytes }
                foreach ($createdPath in $createdPaths) {
                    if (Test-Path -LiteralPath $createdPath -PathType Leaf) {
                        Remove-Item -LiteralPath $createdPath -Force
                    }
                }
                throw
            }
        }
        'VerifyPromoted' {
            $outputs = @(Get-VerifiedPromotedOutputs)
            $binding = Assert-PromotionReceipt -Outputs $outputs
            [ordered]@{
                schemaVersion = '1.0'; verified = $true; gateKind = 'promotional-poster'; jobId = [string]$manifest.jobId
                manifestPath = Get-RelativeProjectPath $manifestFull; manifestSha256 = [string]$binding.ManifestHash
                receiptNonce = [string]$binding.Receipt.nonce; promotedAt = [string]$manifest.promotion.promotedAt
                promotedBy = [string]$manifest.promotion.promotedBy; outputs = @($outputs); verifiedAt = (Get-Date).ToUniversalTime().ToString('o')
            } | ConvertTo-Json -Depth 10 -Compress
        }
        'Status' {
            [pscustomobject]@{
                jobId = $manifest.jobId
                status = $manifest.status
                briefConfirmed = $manifest.brief.confirmed
                missingCount = @($manifest.brief.missing).Count
                candidatePath = $manifest.candidate.path
                approved = $manifest.approval.approved
                promoted = $manifest.promotion.promoted
                assetTransferStatus = if ($null -ne $manifest.assetTransfer) { $manifest.assetTransfer.status } else { 'legacy_manifest' }
            } | ConvertTo-Json -Depth 4
        }
    }
    if ($null -ne $promotionLock) { Exit-PromotionLock -Lock $promotionLock; $promotionLock = $null }
    exit 0
}
catch {
    $failureMessage = $_.Exception.Message
    if ($null -ne $promotionLock) {
        try { Exit-PromotionLock -Lock $promotionLock; $promotionLock = $null }
        catch { $failureMessage = $failureMessage + ' Promotion lock release also failed: ' + $_.Exception.Message }
    }
    Write-Error $failureMessage
    exit 1
}
