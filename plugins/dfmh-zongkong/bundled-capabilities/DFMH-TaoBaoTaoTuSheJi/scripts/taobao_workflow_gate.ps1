param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('CheckBeforeUpload', 'CheckAfterUpload', 'CheckBeforeGenerate', 'CheckImageCandidate', 'CheckBeforeNext', 'CheckSet', 'CheckBeforePromote', 'Promote', 'VerifyPromoted', 'Status')]
    [string]$Action,

    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot,

    [Parameter(Mandatory = $true)]
    [string]$ManifestPath,

    [ValidateSet('main', 'production', 'test')]
    [string]$ActorMode = 'test'
)

$ErrorActionPreference = 'Stop'

function Get-NormalizedRoot {
    param([Parameter(Mandatory = $true)][string]$Path)
    return [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
}

function Test-IsWithin {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Root
    )

    $full = [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    $rootFull = Get-NormalizedRoot $Root
    if ($full.Equals($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }
    $prefix = $rootFull + [System.IO.Path]::DirectorySeparatorChar
    return $full.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)
}

function Assert-NoReparsePoints {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$AllowedRoot
    )

    $full = [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    $root = Get-NormalizedRoot $AllowedRoot
    if (-not (Test-IsWithin -Path $full -Root $root)) {
        throw "Path is outside its allowed root: $full"
    }

    $components = New-Object System.Collections.ArrayList
    [void]$components.Add($root)
    if (-not $full.Equals($root, [System.StringComparison]::OrdinalIgnoreCase)) {
        $relative = $full.Substring($root.Length).TrimStart('\', '/')
        $current = $root
        foreach ($part in @($relative -split '[\\/]')) {
            if ([string]::IsNullOrWhiteSpace($part)) { continue }
            $current = Join-Path $current $part
            [void]$components.Add($current)
        }
    }

    foreach ($component in @($components)) {
        $item = Get-Item -LiteralPath $component -Force -ErrorAction SilentlyContinue
        if ($null -ne $item) {
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "ReparsePoint, junction, or symbolic-link paths are not allowed: $component"
            }
        }
    }
}

function Resolve-ProjectPath {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [string]$RequiredRoot = ''
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
    if (-not [string]::IsNullOrWhiteSpace($RequiredRoot)) {
        $required = if ([System.IO.Path]::IsPathRooted($RequiredRoot)) {
            [System.IO.Path]::GetFullPath($RequiredRoot)
        }
        else {
            [System.IO.Path]::GetFullPath((Join-Path $script:rootFull ($RequiredRoot -replace '/', '\')))
        }
        if (-not (Test-IsWithin -Path $required -Root $script:rootFull)) {
            throw "Required root escapes the project root: $RequiredRoot"
        }
        if (-not (Test-IsWithin -Path $resolved -Root $required)) {
            throw "Path must be inside the current task directory: $RelativePath"
        }
    }
    Assert-NoReparsePoints -Path $resolved -AllowedRoot $script:rootFull
    return $resolved
}

function Assert-Text {
    param([object]$Value, [Parameter(Mandatory = $true)][string]$Label)
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        throw "Missing required field: $Label"
    }
}

function Assert-Collection {
    param([object]$Value, [Parameter(Mandatory = $true)][string]$Label)
    if ($null -eq $Value -or @($Value).Count -eq 0) {
        throw "Missing required collection: $Label"
    }
    foreach ($item in @($Value)) {
        if ($null -eq $item) {
            throw "Collection contains an empty value: $Label"
        }
        if ($item -is [string] -and [string]::IsNullOrWhiteSpace([string]$item)) {
            throw "Collection contains an empty value: $Label"
        }
    }
}

function Assert-ConcreteCollection {
    param(
        [object]$Value,
        [Parameter(Mandatory = $true)][string]$Label,
        [int]$MinimumCount = 1,
        [int]$MinimumTextLength = 8
    )
    Assert-Collection $Value $Label
    $items = @($Value)
    if ($items.Count -lt $MinimumCount) {
        throw "$Label must contain at least $MinimumCount concrete entries."
    }
    foreach ($item in $items) {
        $text = [string]$item
        if ([string]::IsNullOrWhiteSpace($text) -or $text.Trim().Length -lt $MinimumTextLength) {
            throw "$Label contains an entry that is too vague to enforce."
        }
    }
}

function Assert-Sha256 {
    param([object]$Value, [Parameter(Mandatory = $true)][string]$Label)
    Assert-Text $Value $Label
    if ([string]$Value -notmatch '^[A-Fa-f0-9]{64}$') {
        throw "$Label must be a SHA-256 value."
    }
}

function Get-NormalizedPromptTemplateSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    $text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $normalized = (($text -replace "`r`n", "`n") -replace "`r", "`n").TrimEnd("`n")
    $bytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes($normalized)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([System.BitConverter]::ToString($sha256.ComputeHash($bytes))).Replace('-', '')
    }
    finally {
        $sha256.Dispose()
    }
}

function Assert-FixedHomePromptTemplate {
    $expectedVersion = 'emperor-fixed-v1'
    $expectedHash = '1A2304654AF97B4883ABF2FA2BE08DEB3F0292399552723D114CD18A63659A89'
    $templateFull = Join-Path $script:rootFull 'templates\TAOBAO_HOME_IMAGE_PROMPT.md'
    $lockFull = Join-Path $script:rootFull 'templates\TAOBAO_HOME_IMAGE_PROMPT.lock.json'

    foreach ($path in @($templateFull, $lockFull)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "The Emperor-fixed Taobao home prompt contract is missing: $path"
        }
        Assert-NoReparsePoints -Path $path -AllowedRoot $script:rootFull
    }

    $lock = Get-Content -LiteralPath $lockFull -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$lock.templatePath -cne 'templates/TAOBAO_HOME_IMAGE_PROMPT.md') {
        throw 'The Taobao home prompt lock points to an unexpected template.'
    }
    if ([string]$lock.version -cne $expectedVersion) {
        throw "The Taobao home prompt version must remain $expectedVersion."
    }
    if ($lock.immutable -isnot [bool] -or $lock.immutable -ne $true) {
        throw 'The Taobao home prompt lock must remain immutable.'
    }
    Assert-Sha256 $lock.normalizedUtf8Sha256 'home prompt lock normalizedUtf8Sha256'
    if (-not [string]::Equals([string]$lock.normalizedUtf8Sha256, $expectedHash, [System.StringComparison]::Ordinal)) {
        throw 'The Taobao home prompt lock hash differs from the Emperor-approved fixed prompt.'
    }

    $actualHash = Get-NormalizedPromptTemplateSha256 -Path $templateFull
    if (-not [string]::Equals($actualHash, $expectedHash, [System.StringComparison]::Ordinal)) {
        throw 'The Taobao home prompt was changed. Additions, deletions, rewrites, and replacements are forbidden.'
    }
}

function Assert-FixedDetailPromptTemplate {
    $expectedVersion = 'emperor-fixed-detail-v1'
    $expectedHash = '9F7C382CAA3CEE25CD616881DB7383F3956AA378B528B57E1CF1C15AE6946A4A'
    $templateFull = Join-Path $script:rootFull 'templates\TAOBAO_DETAIL_IMAGE_PROMPT.md'
    $lockFull = Join-Path $script:rootFull 'templates\TAOBAO_DETAIL_IMAGE_PROMPT.lock.json'

    foreach ($path in @($templateFull, $lockFull)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "The Emperor-fixed Taobao detail prompt contract is missing: $path"
        }
        Assert-NoReparsePoints -Path $path -AllowedRoot $script:rootFull
    }

    $lock = Get-Content -LiteralPath $lockFull -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$lock.templatePath -cne 'templates/TAOBAO_DETAIL_IMAGE_PROMPT.md') {
        throw 'The Taobao detail prompt lock points to an unexpected template.'
    }
    if ([string]$lock.version -cne $expectedVersion) {
        throw "The Taobao detail prompt version must remain $expectedVersion."
    }
    if ($lock.immutable -isnot [bool] -or $lock.immutable -ne $true) {
        throw 'The Taobao detail prompt lock must remain immutable.'
    }
    Assert-Sha256 $lock.normalizedUtf8Sha256 'detail prompt lock normalizedUtf8Sha256'
    if (-not [string]::Equals([string]$lock.normalizedUtf8Sha256, $expectedHash, [System.StringComparison]::Ordinal)) {
        throw 'The Taobao detail prompt lock hash differs from the Emperor-approved fixed prompt.'
    }

    $actualHash = Get-NormalizedPromptTemplateSha256 -Path $templateFull
    if (-not [string]::Equals($actualHash, $expectedHash, [System.StringComparison]::Ordinal)) {
        throw 'The Taobao detail prompt was changed. Additions, deletions, rewrites, and replacements are forbidden.'
    }
}

function Test-HasProperty {
    param(
        [object]$Object,
        [Parameter(Mandatory = $true)][string]$Name
    )
    return ($null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name])
}

function Assert-BooleanProperty {
    param(
        [object]$Object,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Label
    )
    if (-not (Test-HasProperty -Object $Object -Name $Name)) {
        throw "Missing required field: $Label"
    }
    if ($Object.$Name -isnot [bool]) {
        throw "$Label must be a Boolean."
    }
}

function Assert-JsonArrayProperty {
    param(
        [object]$Object,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Label
    )
    if (-not (Test-HasProperty -Object $Object -Name $Name)) {
        throw "Missing required field: $Label"
    }
    if ($Object.$Name -isnot [System.Array]) {
        throw "$Label must be a JSON array."
    }
    return @($Object.$Name)
}

function Assert-NonBlankFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Label
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Label does not exist: $Path"
    }
    $content = Get-Content -Raw -Encoding UTF8 -LiteralPath $Path
    if ([string]::IsNullOrWhiteSpace([string]$content)) {
        throw "$Label must contain a non-blank acceptance record."
    }
}

function Assert-Timestamp {
    param([object]$Value, [Parameter(Mandatory = $true)][string]$Label)
    Assert-Text $Value $Label
    if ([string]$Value -notmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?(?:Z|[+-]\d{2}:\d{2})$') {
        throw "$Label must use an ISO 8601 date-time with an explicit timezone."
    }
    $parsed = [DateTimeOffset]::MinValue
    $valid = [DateTimeOffset]::TryParse(
        [string]$Value,
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::RoundtripKind,
        [ref]$parsed
    )
    if (-not $valid) {
        throw "$Label must be an ISO-compatible timestamp."
    }
}

function Assert-ManifestArrayContract {
    $null = Assert-JsonArrayProperty -Object $script:manifest.product -Name 'assets' -Label 'product.assets'
    $null = Assert-JsonArrayProperty -Object $script:manifest.product -Name 'facts' -Label 'product.facts'
    $null = Assert-JsonArrayProperty -Object $script:manifest.sellingPoints -Name 'items' -Label 'sellingPoints.items'
    if ($null -ne $script:manifest.marketBenchmark) {
        $null = Assert-JsonArrayProperty -Object $script:manifest.marketBenchmark -Name 'references' -Label 'marketBenchmark.references'
    }
    $null = Assert-JsonArrayProperty -Object $script:manifest.promptSet -Name 'items' -Label 'promptSet.items'
    $null = Assert-JsonArrayProperty -Object $script:manifest -Name 'candidates' -Label 'candidates'
    $null = Assert-JsonArrayProperty -Object $script:manifest -Name 'history' -Label 'history'
    $null = Assert-JsonArrayProperty -Object $script:manifest.promotion -Name 'files' -Label 'promotion.files'
    if ($null -ne $script:manifest.promptSet.styleLock -and (Test-HasProperty -Object $script:manifest.promptSet.styleLock -Name 'forbiddenContent')) {
        $null = Assert-JsonArrayProperty -Object $script:manifest.promptSet.styleLock -Name 'forbiddenContent' -Label 'promptSet.styleLock.forbiddenContent'
    }
    if ($null -ne $script:manifest.promptSet.styleLock) {
        foreach ($field in @('proofIntegrationRules', 'forbiddenLayouts')) {
            if (Test-HasProperty -Object $script:manifest.promptSet.styleLock -Name $field) {
                $null = Assert-JsonArrayProperty -Object $script:manifest.promptSet.styleLock -Name $field -Label ("promptSet.styleLock." + $field)
            }
        }
    }
    if ($null -ne $script:manifest.marketBenchmark.styleDecision) {
        foreach ($field in @('visualPrinciples', 'forbiddenPatterns')) {
            if (Test-HasProperty -Object $script:manifest.marketBenchmark.styleDecision -Name $field) {
                $null = Assert-JsonArrayProperty -Object $script:manifest.marketBenchmark.styleDecision -Name $field -Label ("marketBenchmark.styleDecision." + $field)
            }
        }
    }
    if ($null -ne $script:manifest.promptSet.structureLock) {
        foreach ($field in @('immutableComponents', 'connectionTopology', 'relativeGeometry', 'visibleViewBoundary', 'allowedVariations', 'forbiddenVariations')) {
            if (Test-HasProperty -Object $script:manifest.promptSet.structureLock -Name $field) {
                $null = Assert-JsonArrayProperty -Object $script:manifest.promptSet.structureLock -Name $field -Label ("promptSet.structureLock." + $field)
            }
        }
    }
}

function Assert-ManifestBooleanContract {
    Assert-BooleanProperty -Object $script:manifest.scope -Name 'homeRequired' -Label 'scope.homeRequired'
    Assert-BooleanProperty -Object $script:manifest.scope -Name 'detailRequired' -Label 'scope.detailRequired'
    if ($null -ne $script:manifest.category) {
        Assert-BooleanProperty -Object $script:manifest.category -Name 'confirmed' -Label 'category.confirmed'
    }
    Assert-BooleanProperty -Object $script:manifest.sellingPoints -Name 'confirmed' -Label 'sellingPoints.confirmed'
    if ($null -ne $script:manifest.marketBenchmark) {
        Assert-BooleanProperty -Object $script:manifest.marketBenchmark -Name 'completed' -Label 'marketBenchmark.completed'
    }
    Assert-BooleanProperty -Object $script:manifest.promptSet -Name 'confirmed' -Label 'promptSet.confirmed'
    if ($null -ne $script:manifest.promptSet.structureLock -and (Test-HasProperty -Object $script:manifest.promptSet.structureLock -Name 'confirmed')) {
        Assert-BooleanProperty -Object $script:manifest.promptSet.structureLock -Name 'confirmed' -Label 'promptSet.structureLock.confirmed'
    }
    Assert-BooleanProperty -Object $script:manifest.assetTransfer -Name 'required' -Label 'assetTransfer.required'
    Assert-BooleanProperty -Object $script:manifest.assetTransfer -Name 'authorizationConfirmed' -Label 'assetTransfer.authorizationConfirmed'
    Assert-BooleanProperty -Object $script:manifest.assetTransfer -Name 'clipboardPrepared' -Label 'assetTransfer.clipboardPrepared'
    Assert-BooleanProperty -Object $script:manifest.assetTransfer -Name 'thumbnailVerified' -Label 'assetTransfer.thumbnailVerified'
    Assert-BooleanProperty -Object $script:manifest.assetTransfer -Name 'pathTextEntered' -Label 'assetTransfer.pathTextEntered'
    if ($null -ne $script:manifest.generation.channelAuthorization -and
        (Test-HasProperty -Object $script:manifest.generation.channelAuthorization -Name 'confirmed')) {
        Assert-BooleanProperty -Object $script:manifest.generation.channelAuthorization -Name 'confirmed' -Label 'generation.channelAuthorization.confirmed'
    }
    if ($null -ne $script:manifest.generation.batchAuthorization -and
        (Test-HasProperty -Object $script:manifest.generation.batchAuthorization -Name 'confirmed')) {
        Assert-BooleanProperty -Object $script:manifest.generation.batchAuthorization -Name 'confirmed' -Label 'generation.batchAuthorization.confirmed'
    }
    Assert-BooleanProperty -Object $script:manifest.generation.styleAnchor -Name 'confirmed' -Label 'generation.styleAnchor.confirmed'
    Assert-BooleanProperty -Object $script:manifest.setAcceptance -Name 'passed' -Label 'setAcceptance.passed'
    Assert-BooleanProperty -Object $script:manifest.approval -Name 'approved' -Label 'approval.approved'
    Assert-BooleanProperty -Object $script:manifest.promotion -Name 'promoted' -Label 'promotion.promoted'

    foreach ($asset in @($script:manifest.product.assets)) {
        Assert-BooleanProperty -Object $asset -Name 'authorizationConfirmed' -Label 'product.assets[].authorizationConfirmed'
    }
    foreach ($fact in @($script:manifest.product.facts)) {
        Assert-BooleanProperty -Object $fact -Name 'verified' -Label 'product.facts[].verified'
    }
    foreach ($item in @($script:manifest.sellingPoints.items)) {
        Assert-BooleanProperty -Object $item -Name 'homeEligible' -Label 'sellingPoints.items[].homeEligible'
        Assert-BooleanProperty -Object $item -Name 'detailEligible' -Label 'sellingPoints.items[].detailEligible'
        Assert-BooleanProperty -Object $item -Name 'verified' -Label 'sellingPoints.items[].verified'
    }
    foreach ($item in @($script:manifest.promptSet.items)) {
        Assert-BooleanProperty -Object $item -Name 'proofAddsNewInformation' -Label 'promptSet.items[].proofAddsNewInformation'
    }
    foreach ($candidate in @($script:manifest.candidates)) {
        if ($null -ne $candidate.quality) {
            foreach ($field in @('productConsistency', 'claimEvidence', 'claimVisualMapping', 'textAccuracy', 'dimensions', 'aiArtifacts', 'forbiddenContent', 'mechanismLegibility', 'relativeProportion', 'structureConsistency', 'benchmarkAlignment', 'categoryFit', 'visualIntegration', 'proofRelevance', 'lowerHalfContinuity', 'moduleNovelty')) {
                Assert-BooleanProperty -Object $candidate.quality -Name $field -Label ("candidates[].quality." + $field)
            }
            if ([string]$candidate.type -eq 'detail') {
                foreach ($field in @('fourLayerCompleteness', 'detailContentDensity', 'singleChatSession')) {
                    Assert-BooleanProperty -Object $candidate.quality -Name $field -Label ("candidates[].quality." + $field)
                }
            }
        }
    }
    if ($null -ne $script:manifest.setAcceptance.checks) {
        foreach ($field in @('productConsistency', 'brandConsistency', 'styleConsistency', 'compositionVariation', 'claimCompleteness', 'claimVisualMapping', 'detailRhythm', 'promptImageVersionMapping', 'mechanismLegibility', 'relativeProportion', 'structureConsistency', 'marketBenchmarkAlignment', 'proofIntegration', 'moduleRepetitionControl', 'lowerHalfContinuity')) {
            if (Test-HasProperty -Object $script:manifest.setAcceptance.checks -Name $field) {
                Assert-BooleanProperty -Object $script:manifest.setAcceptance.checks -Name $field -Label ("setAcceptance.checks." + $field)
            }
        }
    }
}

function Assert-ConfirmationTimestampContract {
    $states = @(
        [pscustomobject]@{ Object = $script:manifest.sellingPoints; Boolean = 'confirmed'; Time = 'confirmedAt'; Label = 'sellingPoints.confirmedAt' },
        [pscustomobject]@{ Object = $script:manifest.marketBenchmark; Boolean = 'completed'; Time = 'completedAt'; Label = 'marketBenchmark.completedAt' },
        [pscustomobject]@{ Object = $script:manifest.promptSet; Boolean = 'confirmed'; Time = 'confirmedAt'; Label = 'promptSet.confirmedAt' },
        [pscustomobject]@{ Object = $script:manifest.generation.styleAnchor; Boolean = 'confirmed'; Time = 'confirmedAt'; Label = 'generation.styleAnchor.confirmedAt' },
        [pscustomobject]@{ Object = $script:manifest.approval; Boolean = 'approved'; Time = 'approvedAt'; Label = 'approval.approvedAt' },
        [pscustomobject]@{ Object = $script:manifest.promotion; Boolean = 'promoted'; Time = 'promotedAt'; Label = 'promotion.promotedAt' }
    )
    foreach ($state in $states) {
        $value = $state.Object.($state.Time)
        if ($state.Object.($state.Boolean) -eq $true -or -not [string]::IsNullOrWhiteSpace([string]$value)) {
            Assert-Timestamp $value $state.Label
        }
    }
}

function Assert-ProductFactsContract {
    $facts = @($script:manifest.product.facts)
    $ids = @{}
    foreach ($fact in $facts) {
        foreach ($field in @('id', 'name', 'value', 'evidenceType', 'evidenceReference')) {
            Assert-Text $fact.$field ("product.facts[]." + $field)
        }
        if ([string]$fact.id -notmatch '^F\d{2}$') {
            throw "product.facts[].id must use F plus two digits: $($fact.id)"
        }
        if (@('image_visible', 'user_confirmed', 'document_proven') -notcontains [string]$fact.evidenceType) {
            throw "Unsupported product fact evidence type: $($fact.evidenceType)"
        }
        Assert-BooleanProperty -Object $fact -Name 'verified' -Label 'product.facts[].verified'
        if ($fact.verified -ne $true) {
            throw "Product fact is not verified: $($fact.id)"
        }
        if ($ids.ContainsKey([string]$fact.id)) {
            throw "Duplicate product fact id: $($fact.id)"
        }
        $ids[[string]$fact.id] = $true
    }
}

function Assert-HistoryContract {
    foreach ($item in @($script:manifest.history)) {
        foreach ($field in @('at', 'actor', 'action', 'itemId', 'version', 'statement')) {
            if (-not (Test-HasProperty -Object $item -Name $field)) {
                throw "Missing required field: history[].$field"
            }
        }
        Assert-Timestamp $item.at 'history[].at'
        Assert-Text $item.actor 'history[].actor'
        Assert-Text $item.action 'history[].action'
        Assert-Text $item.version 'history[].version'
        Assert-Text $item.statement 'history[].statement'
        if ([string]$item.version -notmatch '^V\d+$') {
            throw "history[].version must use V followed by digits: $($item.version)"
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$item.itemId) -and [string]$item.itemId -notmatch '^[HD]\d{2}$') {
            throw "history[].itemId must be empty or use an H/D image id: $($item.itemId)"
        }
    }
}

function Get-TaskSubroot {
    param([Parameter(Mandatory = $true)][string]$Name)
    return Join-Path $script:jobRootFull $Name
}

function Assert-ScopeReady {
    if ($null -eq $script:manifest.scope) {
        throw 'Manifest is missing scope.'
    }
    $mode = [string]$script:manifest.scope.mode
    if (@('home', 'detail', 'full') -notcontains $mode) {
        throw "Unsupported or unconfirmed Taobao scope: $mode"
    }
    if ($script:manifest.scope.homeRequired -ne $true -and $script:manifest.scope.detailRequired -ne $true) {
        throw 'At least one Taobao output type must be enabled.'
    }
    if ($mode -eq 'home' -and ($script:manifest.scope.homeRequired -ne $true -or $script:manifest.scope.detailRequired -eq $true)) {
        throw 'Home-only scope flags are inconsistent.'
    }
    if ($mode -eq 'detail' -and ($script:manifest.scope.detailRequired -ne $true -or $script:manifest.scope.homeRequired -eq $true)) {
        throw 'Detail-only scope flags are inconsistent.'
    }
    if ($mode -eq 'full' -and ($script:manifest.scope.homeRequired -ne $true -or $script:manifest.scope.detailRequired -ne $true)) {
        throw 'Full-set scope must enable both home and detail images.'
    }
    return $mode
}

function Assert-CategoryReady {
    if ($null -eq $script:manifest.category) {
        throw 'Manifest is missing category binding.'
    }
    foreach ($field in @('id', 'subtype', 'profileVersion', 'profilePath', 'profileSha256')) {
        Assert-Text $script:manifest.category.$field ("category." + $field)
    }
    if ($script:manifest.category.confirmed -ne $true) {
        throw 'The Taobao category profile has not been confirmed.'
    }
    Assert-Sha256 $script:manifest.category.profileSha256 'category.profileSha256'

    $profileRoot = Join-Path $script:rootFull 'templates\taobao-category-profiles'
    $profileFull = Resolve-ProjectPath -RelativePath ([string]$script:manifest.category.profilePath) -RequiredRoot $profileRoot
    if (-not (Test-Path -LiteralPath $profileFull -PathType Leaf)) {
        throw "Category profile does not exist: $($script:manifest.category.profilePath)"
    }
    $actualHash = (Get-FileHash -LiteralPath $profileFull -Algorithm SHA256).Hash
    if ($actualHash -ne [string]$script:manifest.category.profileSha256) {
        throw 'Category profile hash differs from the manifest binding.'
    }
    try {
        $profile = Get-Content -Raw -Encoding UTF8 -LiteralPath $profileFull | ConvertFrom-Json
    }
    catch {
        throw "Category profile is invalid JSON: $($_.Exception.Message)"
    }
    foreach ($field in @('id', 'version', 'state', 'plannerPromptPath', 'imagePromptPath')) {
        Assert-Text $profile.$field ("category profile." + $field)
    }
    if ([string]$profile.id -ne [string]$script:manifest.category.id) {
        throw 'Category profile id differs from category.id.'
    }
    if ([string]$profile.version -ne [string]$script:manifest.category.profileVersion) {
        throw 'Category profile version differs from category.profileVersion.'
    }
    if ([string]$profile.state -notin @('frozen', 'pilot')) {
        throw "Unsupported category profile state: $($profile.state)"
    }
    foreach ($field in @('subtypes', 'applicableCategories', 'excludedCategories', 'sellingPointPriority', 'recommendedViews', 'structureChecks', 'homePageRoles', 'detailPageRoles', 'shotFamilies', 'proofModes', 'forbiddenPatterns', 'copyTone', 'pageRhythm')) {
        $values = Assert-JsonArrayProperty -Object $profile -Name $field -Label ("category profile." + $field)
        Assert-Collection -Value $values -Label ("category profile." + $field)
    }
    if (@($profile.subtypes) -notcontains [string]$script:manifest.category.subtype) {
        throw "Category subtype is not supported by the bound profile: $($script:manifest.category.subtype)"
    }
    return $profile
}

function Assert-GenerationExecutionPolicy {
    if ($null -eq $script:manifest.generation) {
        throw 'Manifest is missing generation state.'
    }
    if ([string]$script:manifest.generation.executionMode -ne 'batch_after_style_anchor') {
        throw 'Taobao generation.executionMode must be batch_after_style_anchor.'
    }
    if ([string]$script:manifest.generation.reviewPolicy -ne 'anchor_once_batch_qc_final_set_review') {
        throw 'Taobao generation.reviewPolicy must be anchor_once_batch_qc_final_set_review.'
    }
    $forbiddenStatuses = @('generated_awaiting_emperor_review', 'awaiting_emperor_review')
    foreach ($item in @($script:manifest.promptSet.items)) {
        if ([string]$item.status -in $forbiddenStatuses) {
            throw "Per-image Emperor review status is forbidden; route $($item.id) to agent QC."
        }
    }
    foreach ($candidate in @($script:manifest.candidates)) {
        if ([string]$candidate.status -in $forbiddenStatuses) {
            throw "Per-image Emperor review status is forbidden; route candidate $($candidate.id) to agent QC."
        }
    }
}

function Assert-BatchAuthorization {
    $authorization = $script:manifest.generation.batchAuthorization
    if ($null -eq $authorization) {
        throw 'Subsequent images require a batchAuthorization record.'
    }
    foreach ($field in @('jobId', 'categoryId', 'profileVersion', 'channel', 'scope', 'statement', 'authorizedAt')) {
        if (-not (Test-HasProperty -Object $authorization -Name $field)) {
            throw "generation.batchAuthorization is missing $field."
        }
        Assert-Text $authorization.$field ("generation.batchAuthorization." + $field)
    }
    if (-not (Test-HasProperty -Object $authorization -Name 'confirmed') -or $authorization.confirmed -ne $true) {
        throw 'generation.batchAuthorization.confirmed must be true.'
    }
    Assert-Timestamp $authorization.authorizedAt 'generation.batchAuthorization.authorizedAt'
    if ([string]$authorization.jobId -ne [string]$script:manifest.jobId) {
        throw 'Batch authorization must match the current jobId.'
    }
    if ([string]$authorization.categoryId -ne [string]$script:manifest.category.id) {
        throw 'Batch authorization must match the current category id.'
    }
    if ([string]$authorization.profileVersion -ne [string]$script:manifest.category.profileVersion) {
        throw 'Batch authorization must match the current category profile version.'
    }
    if ([string]$authorization.channel -ne [string]$script:manifest.generation.channel) {
        throw 'Batch authorization must match the active generation channel.'
    }
    if ([string]$authorization.scope -ne 'remaining_queue_after_anchor') {
        throw 'Batch authorization scope must be remaining_queue_after_anchor.'
    }
}

function Assert-SellingPointsReady {
    if ($null -eq $script:manifest.sellingPoints -or $script:manifest.sellingPoints.confirmed -ne $true) {
        throw 'Selling points have not been confirmed.'
    }
    Assert-Text $script:manifest.sellingPoints.confirmationStatement 'sellingPoints.confirmationStatement'
    Assert-Text $script:manifest.sellingPoints.confirmedAt 'sellingPoints.confirmedAt'
    Assert-Collection $script:manifest.sellingPoints.items 'sellingPoints.items'

    $ids = @{}
    foreach ($item in @($script:manifest.sellingPoints.items)) {
        Assert-Text $item.id 'sellingPoints.items[].id'
        Assert-Text $item.purchaseRole 'sellingPoints.items[].purchaseRole'
        Assert-Text $item.shortTitle 'sellingPoints.items[].shortTitle'
        Assert-Text $item.buyerBenefit 'sellingPoints.items[].buyerBenefit'
        Assert-Text $item.copy 'sellingPoints.items[].copy'
        Assert-Text $item.visualProof 'sellingPoints.items[].visualProof'
        Assert-Text $item.claimBoundary 'sellingPoints.items[].claimBoundary'
        Assert-Text $item.evidenceType 'sellingPoints.items[].evidenceType'
        Assert-Text $item.evidenceReference 'sellingPoints.items[].evidenceReference'
        if (@('core_purchase_driver', 'supporting_benefit', 'appearance_differentiator') -notcontains [string]$item.purchaseRole) {
            throw "Unsupported selling-point purchase role: $($item.purchaseRole)"
        }
        if (@('image_visible', 'user_confirmed', 'document_proven') -notcontains [string]$item.evidenceType) {
            throw "Unsupported selling-point evidence type: $($item.evidenceType)"
        }
        if ([string]$item.id -notmatch '^S\d{2}$') {
            throw "sellingPoints.items[].id must use S plus two digits: $($item.id)"
        }
        Assert-BooleanProperty -Object $item -Name 'homeEligible' -Label 'sellingPoints.items[].homeEligible'
        Assert-BooleanProperty -Object $item -Name 'detailEligible' -Label 'sellingPoints.items[].detailEligible'
        Assert-BooleanProperty -Object $item -Name 'verified' -Label 'sellingPoints.items[].verified'
        if ($item.verified -ne $true) {
            throw "Selling-point evidence is not verified: $($item.id)"
        }
        if ($ids.ContainsKey([string]$item.id)) {
            throw "Duplicate selling-point id: $($item.id)"
        }
        $ids[[string]$item.id] = $item
    }
    $script:sellingPointById = $ids
    return $ids
}

function Assert-StructureLockReady {
    if ($null -eq $script:manifest.promptSet.structureLock) {
        throw 'Confirmed prompt set is missing promptSet.structureLock.'
    }

    $lock = $script:manifest.promptSet.structureLock
    foreach ($field in @('referenceAssetId', 'referencePath', 'referenceSha256', 'recordPath')) {
        Assert-Text $lock.$field ("promptSet.structureLock." + $field)
    }
    Assert-Sha256 $lock.referenceSha256 'promptSet.structureLock.referenceSha256'
    Assert-BooleanProperty -Object $lock -Name 'confirmed' -Label 'promptSet.structureLock.confirmed'
    if ($lock.confirmed -ne $true) {
        throw 'The product structure lock has not been confirmed.'
    }
    Assert-ConcreteCollection $lock.immutableComponents 'promptSet.structureLock.immutableComponents' 3 8
    Assert-ConcreteCollection $lock.connectionTopology 'promptSet.structureLock.connectionTopology' 2 8
    Assert-ConcreteCollection $lock.relativeGeometry 'promptSet.structureLock.relativeGeometry' 1 8
    Assert-ConcreteCollection $lock.visibleViewBoundary 'promptSet.structureLock.visibleViewBoundary' 1 8
    Assert-ConcreteCollection $lock.allowedVariations 'promptSet.structureLock.allowedVariations' 1 8
    Assert-ConcreteCollection $lock.forbiddenVariations 'promptSet.structureLock.forbiddenVariations' 2 8

    $assetMatches = @($script:manifest.product.assets | Where-Object { [string]$_.id -eq [string]$lock.referenceAssetId })
    if ($assetMatches.Count -ne 1) {
        throw 'promptSet.structureLock.referenceAssetId must match exactly one archived product asset.'
    }
    $asset = $assetMatches[0]
    if ([string]$asset.path -ne [string]$lock.referencePath) {
        throw 'promptSet.structureLock.referencePath must match the archived product asset path.'
    }
    if ([string]$asset.sha256 -ne [string]$lock.referenceSha256) {
        throw 'promptSet.structureLock.referenceSha256 must match the archived product asset hash.'
    }

    $referenceFull = Resolve-ProjectPath -RelativePath $lock.referencePath -RequiredRoot (Get-TaskSubroot 'assets')
    if (-not (Test-Path -LiteralPath $referenceFull -PathType Leaf)) {
        throw 'The product structure-lock reference image does not exist.'
    }
    $actualReferenceHash = (Get-FileHash -LiteralPath $referenceFull -Algorithm SHA256).Hash
    if ($actualReferenceHash -ne [string]$lock.referenceSha256) {
        throw 'The product structure-lock reference file hash does not match the manifest.'
    }

    $recordFull = Resolve-ProjectPath -RelativePath $lock.recordPath -RequiredRoot $script:jobRootFull
    Assert-NonBlankFile -Path $recordFull -Label 'Product structure-lock record'
    $script:structureLockRecordHash = (Get-FileHash -LiteralPath $recordFull -Algorithm SHA256).Hash
    return $lock
}

function Assert-MarketBenchmarkReady {
    if ($null -eq $script:manifest.marketBenchmark) {
        throw 'The four-platform market benchmark is missing.'
    }
    if ($script:manifest.marketBenchmark.completed -ne $true) {
        throw 'The four-platform market benchmark has not been completed.'
    }
    Assert-Timestamp $script:manifest.marketBenchmark.completedAt 'marketBenchmark.completedAt'
    Assert-Text $script:manifest.marketBenchmark.productCategory 'marketBenchmark.productCategory'
    Assert-Text $script:manifest.marketBenchmark.reportPath 'marketBenchmark.reportPath'

    $benchmarkRoot = Get-TaskSubroot 'benchmark'
    $reportFull = Resolve-ProjectPath -RelativePath $script:manifest.marketBenchmark.reportPath -RequiredRoot $benchmarkRoot
    Assert-NonBlankFile -Path $reportFull -Label 'Market benchmark report'

    Assert-Collection $script:manifest.marketBenchmark.references 'marketBenchmark.references'
    $references = @($script:manifest.marketBenchmark.references)
    if ($references.Count -lt 8) {
        throw 'marketBenchmark.references must contain at least eight references.'
    }

    $requiredPlatforms = @('taobao_tmall', 'amazon', 'xiaohongshu', 'dewu')
    $platformCounts = @{}
    $referenceIds = @{}
    foreach ($reference in $references) {
        foreach ($field in @('id', 'platform', 'url', 'capturedAt', 'evidencePath', 'observation')) {
            Assert-Text $reference.$field ("marketBenchmark.references[]." + $field)
        }
        if ($referenceIds.ContainsKey([string]$reference.id)) {
            throw "Duplicate market benchmark reference id: $($reference.id)"
        }
        $referenceIds[[string]$reference.id] = $true
        if ($requiredPlatforms -notcontains [string]$reference.platform) {
            throw "Unsupported market benchmark platform: $($reference.platform)"
        }
        if ([string]$reference.url -notmatch '^https?://') {
            throw "Market benchmark reference must use an HTTP(S) URL: $($reference.id)"
        }
        Assert-Timestamp $reference.capturedAt ("marketBenchmark.references[$($reference.id)].capturedAt")
        if (([string]$reference.observation).Trim().Length -lt 12) {
            throw "Market benchmark observation is too vague: $($reference.id)"
        }
        $evidenceFull = Resolve-ProjectPath -RelativePath $reference.evidencePath -RequiredRoot $benchmarkRoot
        Assert-NonBlankFile -Path $evidenceFull -Label ("Market benchmark evidence " + $reference.id)
        $platform = [string]$reference.platform
        if (-not $platformCounts.ContainsKey($platform)) { $platformCounts[$platform] = 0 }
        $platformCounts[$platform]++
    }
    foreach ($platform in $requiredPlatforms) {
        if (-not $platformCounts.ContainsKey($platform) -or [int]$platformCounts[$platform] -lt 2) {
            throw "Market benchmark requires at least two references from platform: $platform"
        }
    }

    $decision = $script:manifest.marketBenchmark.styleDecision
    if ($null -eq $decision) {
        throw 'marketBenchmark.styleDecision is missing.'
    }
    foreach ($field in @('name', 'rationale', 'platformBlend', 'detailProofStrategy')) {
        Assert-Text $decision.$field ("marketBenchmark.styleDecision." + $field)
    }
    Assert-ConcreteCollection $decision.visualPrinciples 'marketBenchmark.styleDecision.visualPrinciples' 3 8
    Assert-ConcreteCollection $decision.forbiddenPatterns 'marketBenchmark.styleDecision.forbiddenPatterns' 2 8
    foreach ($requiredPattern in @('isolated_floating_detail_box', 'consecutive_same_detail_module')) {
        if (@($decision.forbiddenPatterns) -notcontains $requiredPattern) {
            throw "Market benchmark style decision must forbid: $requiredPattern"
        }
    }

    return [pscustomobject]@{
        ReportFull = $reportFull
        ReportPath = [string]$script:manifest.marketBenchmark.reportPath
        Decision = $decision
    }
}

function Get-PromptItems {
    if ($null -eq $script:manifest.promptSet -or $script:manifest.promptSet.confirmed -ne $true) {
        throw 'The Taobao prompt set has not been confirmed.'
    }
    Assert-Text $script:manifest.promptSet.confirmationStatement 'promptSet.confirmationStatement'
    Assert-Text $script:manifest.promptSet.confirmedAt 'promptSet.confirmedAt'
    Assert-Collection $script:manifest.promptSet.items 'promptSet.items'
    $benchmark = Assert-MarketBenchmarkReady

    if ($null -eq $script:manifest.promptSet.styleLock) {
        throw 'Confirmed prompt set is missing promptSet.styleLock.'
    }
    foreach ($field in @('brand', 'productColor', 'productStructure', 'productMaterial', 'productProportion', 'productAccessories', 'corePalette', 'typography', 'informationHierarchy', 'lighting', 'photographyStyle', 'benchmarkReportPath', 'styleDirection')) {
        Assert-Text $script:manifest.promptSet.styleLock.$field ("promptSet.styleLock." + $field)
    }
    Assert-Collection $script:manifest.promptSet.styleLock.forbiddenContent 'promptSet.styleLock.forbiddenContent'
    Assert-ConcreteCollection $script:manifest.promptSet.styleLock.proofIntegrationRules 'promptSet.styleLock.proofIntegrationRules' 2 8
    Assert-ConcreteCollection $script:manifest.promptSet.styleLock.forbiddenLayouts 'promptSet.styleLock.forbiddenLayouts' 2 8
    if ([string]$script:manifest.promptSet.styleLock.benchmarkReportPath -ne [string]$benchmark.ReportPath) {
        throw 'promptSet.styleLock.benchmarkReportPath must match marketBenchmark.reportPath.'
    }
    foreach ($requiredPattern in @('isolated_floating_detail_box', 'consecutive_same_detail_module')) {
        if (@($script:manifest.promptSet.styleLock.forbiddenLayouts) -notcontains $requiredPattern) {
            throw "promptSet.styleLock.forbiddenLayouts must include: $requiredPattern"
        }
    }
    $null = Assert-StructureLockReady

    $items = @($script:manifest.promptSet.items)
    $ids = @{}
    foreach ($item in $items) {
        Assert-Text $item.id 'promptSet.items[].id'
        Assert-Text $item.type 'promptSet.items[].type'
        Assert-Text $item.version 'promptSet.items[].version'
        Assert-Sha256 $item.referenceSha256 'promptSet.items[].referenceSha256'
        Assert-Sha256 $item.structureLockSha256 'promptSet.items[].structureLockSha256'
        Assert-Text $item.viewConstraint 'promptSet.items[].viewConstraint'
        Assert-Text $item.compositionFamily 'promptSet.items[].compositionFamily'
        Assert-Text $item.proofPresentation 'promptSet.items[].proofPresentation'
        Assert-BooleanProperty -Object $item -Name 'proofAddsNewInformation' -Label 'promptSet.items[].proofAddsNewInformation'
        if ($item.proofAddsNewInformation -ne $true) {
            throw "Prompt proof must add new information: $($item.id)"
        }
        $allowedProofPresentations = @('product_led', 'scene_integrated', 'full_bleed_macro', 'overlap_callout', 'split_story', 'comparison', 'framed_anchored')
        if ($allowedProofPresentations -notcontains [string]$item.proofPresentation) {
            throw "Unsupported or isolated proof presentation: $($item.id)/$($item.proofPresentation)"
        }
        Assert-Text $item.cardPath 'promptSet.items[].cardPath'
        Assert-Text $item.promptPath 'promptSet.items[].promptPath'
        Assert-Text $item.status 'promptSet.items[].status'
        if (@('home', 'detail') -notcontains [string]$item.type) {
            throw "Unsupported prompt item type: $($item.type)"
        }
        if ([string]$item.version -notmatch '^V\d+$') {
            throw "Prompt item version must use V followed by digits: $($item.version)"
        }
        if ([string]$item.referenceSha256 -ne [string]$script:manifest.promptSet.structureLock.referenceSha256) {
            throw "Prompt item referenceSha256 does not match the structure-lock reference: $($item.id)"
        }
        if ([string]$item.structureLockSha256 -ne [string]$script:structureLockRecordHash) {
            throw "Prompt item structureLockSha256 does not match the current structure-lock record: $($item.id)"
        }
        if (([string]$item.viewConstraint).Trim().Length -lt 8) {
            throw "Prompt item viewConstraint is too vague to enforce: $($item.id)"
        }
        if (-not (Test-HasProperty -Object $item -Name 'claimId')) {
            throw 'Missing required field: promptSet.items[].claimId'
        }
        if (-not (Test-HasProperty -Object $item -Name 'roleId')) {
            throw 'Missing required field: promptSet.items[].roleId'
        }
        $claimId = [string]$item.claimId
        $roleId = [string]$item.roleId
        if (-not [string]::IsNullOrWhiteSpace($claimId) -and $claimId -notmatch '^S\d{2}$') {
            throw "Prompt claimId must use S plus two digits: $claimId"
        }
        if (-not [string]::IsNullOrWhiteSpace($roleId) -and $roleId -notmatch '^R\d{2}$') {
            throw "Prompt roleId must use R plus two digits: $roleId"
        }
        if (-not [string]::IsNullOrWhiteSpace($claimId)) {
            if ($null -eq $script:sellingPointById -or -not $script:sellingPointById.ContainsKey($claimId)) {
                throw "Prompt references an unknown selling point: $claimId"
            }
            $linkedSellingPoint = $script:sellingPointById[$claimId]
            if ($item.type -eq 'home' -and $linkedSellingPoint.homeEligible -ne $true) {
                throw "Home prompt references a selling point not eligible for home images: $claimId"
            }
            if ($item.type -eq 'detail' -and $linkedSellingPoint.detailEligible -ne $true) {
                throw "Detail prompt references a selling point not eligible for detail images: $claimId"
            }
        }
        if ($item.type -eq 'home') {
            if ([string]::IsNullOrWhiteSpace($claimId)) {
                throw "Home prompt must reference a selling point: $($item.id)"
            }
            if (-not [string]::IsNullOrWhiteSpace($roleId)) {
                throw "Home prompt must not use a detail-page roleId: $($item.id)"
            }
        }
        elseif ([string]::IsNullOrWhiteSpace($claimId) -and [string]::IsNullOrWhiteSpace($roleId)) {
            throw "Detail prompt must declare a claimId or roleId: $($item.id)"
        }
        if ([int]$item.width -le 0 -or [int]$item.height -le 0) {
            throw "Prompt item dimensions must be positive: $($item.id)"
        }
        if ($ids.ContainsKey([string]$item.id)) {
            throw "Duplicate prompt item id: $($item.id)"
        }
        $ids[[string]$item.id] = $true
    }
    $detailItems = @($items | Where-Object { $_.type -eq 'detail' })
    $framedCount = 0
    for ($detailIndex = 0; $detailIndex -lt $detailItems.Count; $detailIndex++) {
        $detailItem = $detailItems[$detailIndex]
        if ([string]$detailItem.proofPresentation -eq 'framed_anchored') { $framedCount++ }
        if ($detailIndex -gt 0) {
            $previousDetailItem = $detailItems[$detailIndex - 1]
            if ([string]$detailItem.compositionFamily -eq [string]$previousDetailItem.compositionFamily) {
                throw "Consecutive detail prompts repeat the same compositionFamily: $($previousDetailItem.id)/$($detailItem.id)"
            }
            if ([string]$detailItem.proofPresentation -eq 'framed_anchored' -and [string]$previousDetailItem.proofPresentation -eq 'framed_anchored') {
                throw "Consecutive detail prompts repeat framed_anchored proof: $($previousDetailItem.id)/$($detailItem.id)"
            }
        }
    }
    if ($framedCount -gt 2) {
        throw 'A detail prompt set may use framed_anchored proof at most twice.'
    }
    return $items
}

function Assert-QueueMatchesScope {
    param(
        [Parameter(Mandatory = $true)][object[]]$Items,
        [Parameter(Mandatory = $true)][string]$Mode
    )
    $homeItems = @($Items | Where-Object { $_.type -eq 'home' })
    $detailItems = @($Items | Where-Object { $_.type -eq 'detail' })
    if ($Mode -eq 'home' -and ($homeItems.Count -eq 0 -or $detailItems.Count -ne 0)) {
        throw 'Home-only scope must contain only home prompt items.'
    }
    if ($Mode -eq 'detail' -and ($detailItems.Count -eq 0 -or $homeItems.Count -ne 0)) {
        throw 'Detail-only scope must contain only detail prompt items.'
    }
    if ($Mode -eq 'full' -and ($homeItems.Count -eq 0 -or $detailItems.Count -eq 0)) {
        throw 'Full-set scope must contain both home and detail prompt items.'
    }
    if ($Mode -eq 'full') {
        $seenDetail = $false
        foreach ($item in $Items) {
            if ($item.type -eq 'detail') { $seenDetail = $true }
            if ($seenDetail -and $item.type -eq 'home') {
                throw 'Full-set queue must place every home image before detail images.'
            }
        }
    }

    for ($index = 0; $index -lt $homeItems.Count; $index++) {
        $expectedId = 'H{0:D2}' -f ($index + 1)
        if ([string]$homeItems[$index].id -ne $expectedId) {
            throw "Home prompt queue must use ordered continuous numbering; expected $expectedId but found $($homeItems[$index].id)."
        }
    }
    for ($index = 0; $index -lt $detailItems.Count; $index++) {
        $expectedId = 'D{0:D2}' -f ($index + 1)
        if ([string]$detailItems[$index].id -ne $expectedId) {
            throw "Detail prompt queue must use ordered continuous numbering; expected $expectedId but found $($detailItems[$index].id)."
        }
    }
}

function Get-CurrentPromptContext {
    $mode = Assert-ScopeReady
    $null = Assert-CategoryReady
    $null = Assert-SellingPointsReady
    $items = @(Get-PromptItems)
    Assert-QueueMatchesScope -Items $items -Mode $mode
    Assert-Text $script:manifest.generation.currentItemId 'generation.currentItemId'
    $matches = @($items | Where-Object { $_.id -eq [string]$script:manifest.generation.currentItemId })
    if ($matches.Count -ne 1) {
        throw "generation.currentItemId must match exactly one prompt item: $($script:manifest.generation.currentItemId)"
    }
    $current = $matches[0]
    $index = [array]::IndexOf($items, $current)

    $cardRoot = Get-TaskSubroot ('prompts\' + [string]$current.type)
    $cardFull = Resolve-ProjectPath -RelativePath $current.cardPath -RequiredRoot $cardRoot
    $promptFull = Resolve-ProjectPath -RelativePath $current.promptPath -RequiredRoot $cardRoot
    if (-not (Test-Path -LiteralPath $cardFull -PathType Leaf)) {
        throw "Current design card does not exist: $($current.cardPath)"
    }
    if (-not (Test-Path -LiteralPath $promptFull -PathType Leaf)) {
        throw "Current clean prompt does not exist: $($current.promptPath)"
    }

    $expectedAnchor = [string]$items[0].id
    if ($mode -in @('home', 'full') -and $expectedAnchor -ne 'H01') {
        throw 'Home or full scope must begin with H01.'
    }
    if ($mode -eq 'detail' -and $expectedAnchor -ne 'D01') {
        throw 'Detail-only scope must begin with D01.'
    }
    if ([string]$script:manifest.generation.styleAnchor.itemId -ne $expectedAnchor) {
        throw "Style anchor must be the first actual queue item: $expectedAnchor"
    }
    if ($index -gt 0) {
        if ($script:manifest.generation.styleAnchor.confirmed -ne $true) {
            throw 'The style anchor has not been confirmed for subsequent images.'
        }
        Assert-Text $script:manifest.generation.styleAnchor.confirmationStatement 'generation.styleAnchor.confirmationStatement'
        Assert-Text $script:manifest.generation.styleAnchor.confirmedAt 'generation.styleAnchor.confirmedAt'
        Assert-BatchAuthorization
        for ($i = 0; $i -lt $index; $i++) {
            if ([string]$items[$i].status -ne 'accepted') {
                throw "A preceding prompt item is not accepted: $($items[$i].id)"
            }
        }
    }

    return [pscustomobject]@{
        Mode = $mode
        Items = $items
        Current = $current
        Index = $index
        CardFull = $cardFull
        PromptFull = $promptFull
    }
}

function Get-GenerationChannel {
    if ($null -eq $script:manifest.generation) {
        throw 'Manifest is missing generation state.'
    }
    Assert-Text $script:manifest.generation.channel 'generation.channel'
    $channel = [string]$script:manifest.generation.channel
    if ($channel -notin @('chatgpt_web_qq', 'codex_internal_image_gen')) {
        throw "Unsupported Taobao generation channel: $channel"
    }
    return $channel
}

function Assert-InternalChannelAuthorization {
    param(
        [Parameter(Mandatory = $true)][object]$CurrentPrompt
    )

    $authorization = $script:manifest.generation.channelAuthorization
    if ($null -eq $authorization) {
        throw 'Internal ImageGen requires current_job_version_authorization.'
    }
    foreach ($field in @('jobId', 'itemId', 'promptVersion', 'channel', 'purpose', 'statement', 'authorizedAt')) {
        if (-not (Test-HasProperty -Object $authorization -Name $field)) {
            throw "generation.channelAuthorization is missing $field."
        }
        Assert-Text $authorization.$field ("generation.channelAuthorization." + $field)
    }
    if (-not (Test-HasProperty -Object $authorization -Name 'confirmed')) {
        throw 'generation.channelAuthorization is missing confirmed.'
    }
    if ($authorization.confirmed -ne $true) {
        throw 'Internal ImageGen current_job_version_authorization is not confirmed.'
    }
    Assert-Timestamp $authorization.authorizedAt 'generation.channelAuthorization.authorizedAt'
    if ([string]$authorization.jobId -ne [string]$script:manifest.jobId) {
        throw 'Internal ImageGen authorization must match the current jobId.'
    }
    if ([string]$authorization.itemId -ne [string]$script:manifest.generation.currentItemId) {
        throw 'Internal ImageGen authorization must match the current itemId.'
    }
    if ([string]$authorization.promptVersion -ne [string]$CurrentPrompt.version) {
        throw 'Internal ImageGen authorization must match the current prompt version.'
    }
    if ([string]$authorization.channel -ne 'codex_internal_image_gen') {
        throw 'Internal ImageGen authorization must name codex_internal_image_gen.'
    }
}

function Assert-AssetUploadReady {
    if ($null -eq $script:manifest.assetTransfer) {
        throw 'Manifest is missing assetTransfer state.'
    }
    if ($script:manifest.assetTransfer.required -ne $true) {
        throw 'The Taobao product asset upload requirement is not enabled.'
    }
    Assert-Text $script:manifest.assetTransfer.assetPath 'assetTransfer.assetPath'
    Assert-Sha256 $script:manifest.assetTransfer.expectedSha256 'assetTransfer.expectedSha256'
    Assert-Text $script:manifest.assetTransfer.itemId 'assetTransfer.itemId'
    Assert-Text $script:manifest.assetTransfer.promptVersion 'assetTransfer.promptVersion'
    Assert-Text $script:manifest.assetTransfer.chatSessionReference 'assetTransfer.chatSessionReference'
    Assert-Text $script:manifest.assetTransfer.conversationAction 'assetTransfer.conversationAction'
    Assert-Text $script:manifest.generation.currentItemId 'generation.currentItemId'
    if ([string]$script:manifest.assetTransfer.itemId -ne [string]$script:manifest.generation.currentItemId) {
        throw 'assetTransfer.itemId must match generation.currentItemId for this upload.'
    }
    $currentPromptMatches = @($script:manifest.promptSet.items | Where-Object { [string]$_.id -eq [string]$script:manifest.generation.currentItemId })
    if ($currentPromptMatches.Count -ne 1) {
        throw 'The upload binding item must match exactly one prompt item.'
    }
    $currentPrompt = $currentPromptMatches[0]
    if ([string]$script:manifest.assetTransfer.promptVersion -ne [string]$currentPrompt.version) {
        throw 'assetTransfer.promptVersion must match the current prompt item version.'
    }
    $generationChannel = Get-GenerationChannel
    Assert-Text $script:manifest.generation.channelStatus 'generation.channelStatus'
    Assert-Text $script:manifest.generation.chatSessionPolicy 'generation.chatSessionPolicy'
    Assert-Text $script:manifest.generation.chatSessionReference 'generation.chatSessionReference'
    $newConversationCount = $script:manifest.generation.newConversationCount
    if (($newConversationCount -isnot [int]) -and ($newConversationCount -isnot [long])) {
        throw 'generation.newConversationCount must be a JSON integer.'
    }
    if ([string]$script:manifest.assetTransfer.chatSessionReference -ne [string]$script:manifest.generation.chatSessionReference) {
        throw 'assetTransfer.chatSessionReference must match the active generation execution reference.'
    }

    if ($generationChannel -eq 'chatgpt_web_qq') {
        if ([string]$script:manifest.generation.channelStatus -ne 'default') {
            throw 'The QQ Browser ChatGPT channel must use channelStatus=default.'
        }
        if ([string]$script:manifest.generation.chatSessionPolicy -ne 'single_conversation_full_set') {
            throw 'Taobao web image generation must use single_conversation_full_set.'
        }
        Assert-Text $script:manifest.generation.chatSessionOpenedForItemId 'generation.chatSessionOpenedForItemId'
        if ([string]$script:manifest.generation.chatSessionOpenedForItemId -ne [string]$script:manifest.generation.styleAnchor.itemId) {
            throw 'The only GPT conversation must be opened for the first actual queue item.'
        }
        if ([int64]$newConversationCount -ne 1) {
            throw 'Exactly one GPT conversation may be opened for the entire Taobao image set.'
        }
        $promptItems = @($script:manifest.promptSet.items)
        $currentPromptIndex = -1
        for ($promptIndex = 0; $promptIndex -lt $promptItems.Count; $promptIndex++) {
            if ([string]$promptItems[$promptIndex].id -eq [string]$script:manifest.generation.currentItemId) {
                $currentPromptIndex = $promptIndex
                break
            }
        }
        if ($currentPromptIndex -lt 0) {
            throw 'Cannot determine the current prompt position for GPT conversation continuity.'
        }
        $expectedConversationAction = if ($currentPromptIndex -eq 0) { 'opened_new' } else { 'reused_existing' }
        if ([string]$script:manifest.assetTransfer.conversationAction -ne $expectedConversationAction) {
            throw "assetTransfer.conversationAction must be $expectedConversationAction for $($script:manifest.generation.currentItemId)."
        }
        if ([string]$script:manifest.assetTransfer.destination -ne 'ChatGPT web via QQ Browser') {
            throw "Unsupported web asset upload destination: $($script:manifest.assetTransfer.destination)"
        }
    }
    else {
        if ([string]$script:manifest.generation.channelStatus -ne 'experimental') {
            throw 'The Codex internal ImageGen channel must remain experimental.'
        }
        if ([string]$script:manifest.generation.chatSessionPolicy -ne 'stateless_reference_bound') {
            throw 'Codex internal ImageGen must use stateless_reference_bound.'
        }
        if ([string]$script:manifest.generation.chatSessionOpenedForItemId -ne '') {
            throw 'Codex internal ImageGen must not claim that a ChatGPT conversation was opened.'
        }
        if ([int64]$newConversationCount -ne 0) {
            throw 'Codex internal ImageGen must keep newConversationCount at 0.'
        }
        if ([string]$script:manifest.assetTransfer.conversationAction -ne 'direct_tool_call') {
            throw 'Codex internal ImageGen must record conversationAction=direct_tool_call.'
        }
        if ([string]$script:manifest.assetTransfer.destination -ne 'Codex internal ImageGen') {
            throw "Unsupported internal asset binding destination: $($script:manifest.assetTransfer.destination)"
        }
        Assert-InternalChannelAuthorization -CurrentPrompt $currentPrompt
    }

    if ($script:manifest.assetTransfer.authorizationConfirmed -ne $true) {
        throw 'The product asset upload has not been authorized.'
    }
    if ($script:manifest.assetTransfer.pathTextEntered -eq $true) {
        throw 'A local file path was entered as webpage text; stop before continuing.'
    }

    Assert-Collection $script:manifest.product.assets 'product.assets'
    $assetMatches = @($script:manifest.product.assets | Where-Object { $_.path -eq [string]$script:manifest.assetTransfer.assetPath })
    if ($assetMatches.Count -ne 1) {
        throw 'assetTransfer.assetPath must match exactly one archived product asset.'
    }
    $asset = $assetMatches[0]
    Assert-Text $asset.id 'product.assets[].id'
    Assert-Text $asset.path 'product.assets[].path'
    Assert-Text $asset.sourcePath 'product.assets[].sourcePath'
    Assert-Text $asset.fileName 'product.assets[].fileName'
    Assert-Sha256 $asset.sha256 'product.assets[].sha256'
    Assert-Text $asset.authorizationStatement 'product.assets[].authorizationStatement'
    if ($asset.authorizationConfirmed -ne $true) {
        throw 'The archived product asset is not authorized for upload.'
    }
    if ([int64]$asset.bytes -le 0) {
        throw 'product.assets[].bytes must be greater than zero.'
    }

    $assetRoot = Get-TaskSubroot 'assets'
    $assetFull = Resolve-ProjectPath -RelativePath $asset.path -RequiredRoot $assetRoot
    if (-not (Test-Path -LiteralPath $assetFull -PathType Leaf)) {
        throw "Archived product asset does not exist: $($asset.path)"
    }
    if ([System.IO.Path]::GetFileName($assetFull) -ne [string]$asset.fileName) {
        throw 'Archived product asset fileName does not match its path.'
    }
    $actualBytes = (Get-Item -LiteralPath $assetFull).Length
    if ($actualBytes -ne [int64]$asset.bytes) {
        throw 'Archived product asset byte length does not match the manifest.'
    }
    $actualHash = (Get-FileHash -LiteralPath $assetFull -Algorithm SHA256).Hash
    if ($actualHash -ne [string]$asset.sha256 -or $actualHash -ne [string]$script:manifest.assetTransfer.expectedSha256) {
        throw 'Archived product asset SHA-256 does not match the manifest.'
    }

    return [pscustomobject]@{
        Asset = $asset
        AssetFull = $assetFull
        FileName = [System.IO.Path]::GetFileName($assetFull)
        Hash = $actualHash
        Bytes = $actualBytes
    }
}

function Assert-AssetUploadVerified {
    $assetContext = Assert-AssetUploadReady
    Assert-Timestamp $script:manifest.assetTransfer.verifiedAt 'assetTransfer.verifiedAt'
    $generationChannel = Get-GenerationChannel
    if ($generationChannel -eq 'chatgpt_web_qq') {
        if ([string]$script:manifest.assetTransfer.method -ne 'clipboard_file_copy') {
            throw 'The verified web upload method must be clipboard_file_copy.'
        }
        if ($script:manifest.assetTransfer.clipboardPrepared -ne $true) {
            throw 'The product asset file was not verified on the clipboard.'
        }
        if ($script:manifest.assetTransfer.thumbnailVerified -ne $true) {
            throw 'The ChatGPT webpage product thumbnail has not been verified.'
        }
    }
    else {
        if ([string]$script:manifest.assetTransfer.method -ne 'referenced_image_paths') {
            throw 'Codex internal ImageGen must bind the source through referenced_image_paths.'
        }
        if ($script:manifest.assetTransfer.clipboardPrepared -ne $false) {
            throw 'Codex internal ImageGen must not claim a clipboard preparation step.'
        }
        if ($script:manifest.assetTransfer.thumbnailVerified -ne $false) {
            throw 'Codex internal ImageGen must not claim a webpage thumbnail verification step.'
        }
    }
    Assert-Text $script:manifest.assetTransfer.verifiedAssetName 'assetTransfer.verifiedAssetName'
    if ([string]$script:manifest.assetTransfer.verifiedAssetName -ne [string]$assetContext.FileName) {
        throw 'The verified bound asset name does not match the archived product file.'
    }
    if ([string]$script:manifest.assetTransfer.status -ne 'verified') {
        throw "Asset transfer status must be verified: $($script:manifest.assetTransfer.status)"
    }
    return $assetContext
}

function Get-ImageDimensions {
    param([Parameter(Mandatory = $true)][string]$Path)
    $extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    if ($extension -notin @('.png', '.jpg', '.jpeg')) {
        throw "Only PNG and JPEG candidate images can be verified by this PowerShell 5.1 gate: $Path"
    }
    Add-Type -AssemblyName System.Drawing
    $image = [System.Drawing.Image]::FromFile($Path)
    try {
        $expectedGuid = if ($extension -eq '.png') {
            [System.Drawing.Imaging.ImageFormat]::Png.Guid
        }
        else {
            [System.Drawing.Imaging.ImageFormat]::Jpeg.Guid
        }
        if ($image.RawFormat.Guid -ne $expectedGuid) {
            throw "Candidate file content does not match its PNG/JPEG extension: $Path"
        }
        return [pscustomobject]@{ Width = [int]$image.Width; Height = [int]$image.Height }
    }
    finally {
        $image.Dispose()
    }
}

function Assert-CandidateForPrompt {
    param(
        [Parameter(Mandatory = $true)][object]$PromptItem,
        [Parameter(Mandatory = $true)][object]$Candidate
    )

    foreach ($field in @('id', 'type', 'version', 'promptId', 'path', 'acceptancePath', 'sha256', 'bytes', 'width', 'height', 'status')) {
        Assert-Text $Candidate.$field ("candidates[]." + $field)
    }
    if ([string]$Candidate.id -ne [string]$PromptItem.id -or [string]$Candidate.promptId -ne [string]$PromptItem.id) {
        throw "Candidate does not match its prompt item: $($Candidate.id)"
    }
    if ([string]$Candidate.type -ne [string]$PromptItem.type) {
        throw "Candidate type differs from its prompt item: $($Candidate.id)"
    }
    if ([string]$Candidate.version -ne [string]$PromptItem.version) {
        throw "Candidate version differs from its prompt item: $($Candidate.id)"
    }
    if ([int]$Candidate.width -ne [int]$PromptItem.width -or [int]$Candidate.height -ne [int]$PromptItem.height) {
        throw "Candidate dimensions differ from its prompt item: $($Candidate.id)"
    }
    Assert-Sha256 $Candidate.sha256 'candidates[].sha256'
    if ([int64]$Candidate.bytes -le 0) {
        throw 'candidates[].bytes must be greater than zero.'
    }

    $candidateRoot = Get-TaskSubroot ('candidates\' + [string]$Candidate.type)
    $candidateFull = Resolve-ProjectPath -RelativePath $Candidate.path -RequiredRoot $candidateRoot
    $acceptanceRoot = Get-TaskSubroot 'acceptance'
    $acceptanceFull = Resolve-ProjectPath -RelativePath $Candidate.acceptancePath -RequiredRoot $acceptanceRoot
    if (-not (Test-Path -LiteralPath $candidateFull -PathType Leaf)) {
        throw "Candidate image does not exist: $($Candidate.path)"
    }
    Assert-NonBlankFile -Path $acceptanceFull -Label 'Candidate acceptance record'
    if ([System.IO.Path]::GetExtension($candidateFull).ToLowerInvariant() -notin @('.png', '.jpg', '.jpeg')) {
        throw "Unsupported candidate image format: $($Candidate.path)"
    }

    $actualBytes = (Get-Item -LiteralPath $candidateFull).Length
    if ($actualBytes -ne [int64]$Candidate.bytes) {
        throw "Candidate byte length does not match the manifest: $($Candidate.id)"
    }
    $actualHash = (Get-FileHash -LiteralPath $candidateFull -Algorithm SHA256).Hash
    if ($actualHash -ne [string]$Candidate.sha256) {
        throw "Candidate SHA-256 does not match the manifest: $($Candidate.id)"
    }
    $actualDimensions = Get-ImageDimensions -Path $candidateFull
    if ($actualDimensions.Width -ne [int]$Candidate.width -or $actualDimensions.Height -ne [int]$Candidate.height) {
        throw "Candidate file dimensions do not match the manifest: $($Candidate.id)"
    }

    if ($null -eq $Candidate.quality) {
        throw "Candidate quality evidence is missing: $($Candidate.id)"
    }
    foreach ($field in @('productConsistency', 'claimEvidence', 'claimVisualMapping', 'textAccuracy', 'dimensions', 'aiArtifacts', 'forbiddenContent', 'mechanismLegibility', 'relativeProportion', 'structureConsistency', 'benchmarkAlignment', 'categoryFit', 'visualIntegration', 'proofRelevance', 'lowerHalfContinuity', 'moduleNovelty')) {
        if ($Candidate.quality.$field -ne $true) {
            throw "Candidate quality check is incomplete: $($Candidate.id).quality.$field"
        }
    }
    if ([string]$Candidate.type -eq 'detail') {
        foreach ($field in @('fourLayerCompleteness', 'detailContentDensity', 'singleChatSession')) {
            if ($Candidate.quality.$field -ne $true) {
                throw "Detail candidate quality check is incomplete: $($Candidate.id).quality.$field"
            }
        }
    }

    return [pscustomobject]@{
        Prompt = $PromptItem
        Candidate = $Candidate
        CandidateFull = $candidateFull
        AcceptanceFull = $acceptanceFull
        Hash = $actualHash
        Bytes = $actualBytes
    }
}

function Get-CurrentCandidateContext {
    $promptContext = Get-CurrentPromptContext
    $matches = @($script:manifest.candidates | Where-Object { $_.id -eq [string]$promptContext.Current.id })
    if ($matches.Count -ne 1) {
        throw "Current prompt must match exactly one candidate: $($promptContext.Current.id)"
    }
    return Assert-CandidateForPrompt -PromptItem $promptContext.Current -Candidate $matches[0]
}

function Assert-SetReady {
    $mode = Assert-ScopeReady
    $null = Assert-SellingPointsReady
    $promptItems = @(Get-PromptItems)
    Assert-QueueMatchesScope -Items $promptItems -Mode $mode
    Assert-Collection $script:manifest.candidates 'candidates'
    $candidates = @($script:manifest.candidates)

    if ($candidates.Count -ne $promptItems.Count) {
        throw 'Prompt queue and candidate count do not match.'
    }
    $candidateIds = @{}
    $candidateContexts = New-Object System.Collections.ArrayList
    foreach ($prompt in $promptItems) {
        if ([string]$prompt.status -ne 'accepted') {
            throw "Prompt item is not accepted: $($prompt.id)"
        }
        $matches = @($candidates | Where-Object { $_.id -eq [string]$prompt.id })
        if ($matches.Count -ne 1) {
            throw "Prompt item must match exactly one candidate: $($prompt.id)"
        }
        if ($candidateIds.ContainsKey([string]$matches[0].id)) {
            throw "Duplicate candidate id: $($matches[0].id)"
        }
        $candidateIds[[string]$matches[0].id] = $true
        if ([string]$matches[0].status -ne 'accepted') {
            throw "Candidate is not accepted: $($matches[0].id)"
        }
        [void]$candidateContexts.Add((Assert-CandidateForPrompt -PromptItem $prompt -Candidate $matches[0]))
    }

    Assert-Text $script:manifest.setAcceptance.path 'setAcceptance.path'
    $setAcceptanceFull = Resolve-ProjectPath -RelativePath $script:manifest.setAcceptance.path -RequiredRoot (Get-TaskSubroot 'acceptance')
    Assert-NonBlankFile -Path $setAcceptanceFull -Label 'Full-set acceptance record'
    if ($script:manifest.setAcceptance.passed -ne $true) {
        throw 'The full-set acceptance has not passed.'
    }
    foreach ($field in @('productConsistency', 'brandConsistency', 'styleConsistency', 'compositionVariation', 'claimCompleteness', 'claimVisualMapping', 'detailRhythm', 'promptImageVersionMapping', 'mechanismLegibility', 'relativeProportion', 'structureConsistency', 'marketBenchmarkAlignment', 'proofIntegration', 'moduleRepetitionControl', 'lowerHalfContinuity')) {
        if ($script:manifest.setAcceptance.checks.$field -ne $true) {
            throw "Full-set acceptance check is incomplete: $field"
        }
    }

    return [pscustomobject]@{
        PromptItems = $promptItems
        CandidateContexts = @($candidateContexts)
        AcceptanceFull = $setAcceptanceFull
    }
}

function Assert-PromotionReady {
    if (@('main', 'production') -notcontains $ActorMode) {
        throw 'Only main or production actors can promote Taobao image sets.'
    }
    if ([string]$script:manifest.status -ne 'approved') {
        throw "Manifest must be approved before promotion: $($script:manifest.status)"
    }
    if ($script:manifest.approval.approved -ne $true) {
        throw 'The Emperor has not approved the final Taobao image set.'
    }
    Assert-Text $script:manifest.approval.statement 'approval.statement'
    Assert-Text $script:manifest.approval.approvedAt 'approval.approvedAt'
    if ($script:manifest.promotion.promoted -eq $true) {
        throw 'This Taobao image set has already been promoted.'
    }
    if (Test-Path -LiteralPath (Get-PromotionReceiptPath)) {
        throw 'A stale promotion receipt already exists for this Taobao job.'
    }
    $setContext = Assert-SetReady

    Assert-Text $script:manifest.promotion.outputDirectory 'promotion.outputDirectory'
    $outputFull = Resolve-ProjectPath -RelativePath $script:manifest.promotion.outputDirectory -RequiredRoot 'outputs'
    if (Test-Path -LiteralPath $outputFull) {
        throw "Refusing to overwrite an existing formal output directory: $outputFull"
    }

    $targets = New-Object System.Collections.ArrayList
    $targetNames = @{}
    foreach ($candidateContext in @($setContext.CandidateContexts)) {
        $fileName = [System.IO.Path]::GetFileName($candidateContext.CandidateFull)
        if ($targetNames.ContainsKey($fileName)) {
            throw "Two candidates would use the same formal output file name: $fileName"
        }
        $targetNames[$fileName] = $true
        $targetFull = Join-Path $outputFull $fileName
        if (Test-Path -LiteralPath $targetFull) {
            throw "Refusing to overwrite an existing formal output: $targetFull"
        }
        [void]$targets.Add([pscustomobject]@{
            Context = $candidateContext
            FileName = $fileName
            TargetFull = $targetFull
        })
    }

    return [pscustomobject]@{
        SetContext = $setContext
        OutputFull = $outputFull
        Targets = @($targets)
    }
}

function Write-ManifestAtomically {
    param([Parameter(Mandatory = $true)][object]$Value)
    $manifestDirectory = Split-Path -Parent $script:manifestFull
    $tempPath = Join-Path $manifestDirectory ('.manifest-' + [guid]::NewGuid().ToString('N') + '.tmp')
    $backupPath = Join-Path $manifestDirectory ('.manifest-' + [guid]::NewGuid().ToString('N') + '.bak')
    try {
        $json = $Value | ConvertTo-Json -Depth 30
        [System.IO.File]::WriteAllText($tempPath, $json, (New-Object System.Text.UTF8Encoding($false)))
        [System.IO.File]::Replace($tempPath, $script:manifestFull, $backupPath)
        if (Test-Path -LiteralPath $backupPath -PathType Leaf) {
            Remove-Item -LiteralPath $backupPath -Force
        }
    }
    catch {
        if (Test-Path -LiteralPath $tempPath -PathType Leaf) {
            Remove-Item -LiteralPath $tempPath -Force
        }
        if (Test-Path -LiteralPath $backupPath -PathType Leaf) {
            Copy-Item -LiteralPath $backupPath -Destination $script:manifestFull -Force
            Remove-Item -LiteralPath $backupPath -Force
        }
        throw
    }
}

function Get-RelativeProjectPath {
    param([Parameter(Mandatory = $true)][string]$FullPath)
    return $FullPath.Substring($script:rootFull.Length).TrimStart('\', '/').Replace('\', '/')
}

function Get-PromotionReceiptPath {
    return Join-Path $script:jobRootFull 'promotion-receipt.json'
}

function Write-BytesAtomically {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][byte[]]$Bytes)
    Assert-NoReparsePoints -Path (Split-Path -Parent $Path) -AllowedRoot $script:rootFull
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
    param([Parameter(Mandatory = $true)][object]$Value, [int]$Depth = 30)
    return (New-Object System.Text.UTF8Encoding($false)).GetBytes(($Value | ConvertTo-Json -Depth $Depth))
}

function New-PromotionEvidenceDescriptor {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$Kind,
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][string]$RequiredRoot,
        [switch]$RequireNonBlank
    )

    Assert-Text $RelativePath 'promotion evidence path'
    Assert-Text $Kind 'promotion evidence kind'
    Assert-Text $Id 'promotion evidence id'
    $full = Resolve-ProjectPath -RelativePath $RelativePath -RequiredRoot $RequiredRoot
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
        throw "Promotion evidence does not exist: $RelativePath"
    }
    if ($RequireNonBlank) {
        Assert-NonBlankFile -Path $full -Label ("Promotion evidence $Kind/$Id")
    }
    $bytes = (Get-Item -LiteralPath $full).Length
    if ($bytes -le 0) {
        throw "Promotion evidence is empty: $RelativePath"
    }
    $sha256 = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash
    return [ordered]@{
        path = Get-RelativeProjectPath -FullPath $full
        kind = $Kind
        id = $Id
        bytes = [int64]$bytes
        sha256 = [string]$sha256
    }
}

function Get-PromotionEvidence {
    param([Parameter(Mandatory = $true)][object]$SetContext)

    $evidence = New-Object System.Collections.ArrayList
    foreach ($asset in @($script:manifest.product.assets)) {
        foreach ($field in @('id', 'path', 'sha256')) { Assert-Text $asset.$field ("product.assets[]." + $field) }
        Assert-Sha256 $asset.sha256 'product.assets[].sha256'
        if ([int64]$asset.bytes -le 0) { throw 'product.assets[].bytes must be greater than zero.' }
        $entry = New-PromotionEvidenceDescriptor -RelativePath ([string]$asset.path) -Kind 'product-asset' -Id ([string]$asset.id) -RequiredRoot (Get-TaskSubroot 'assets')
        if ([string]$entry.sha256 -ne [string]$asset.sha256 -or [int64]$entry.bytes -ne [int64]$asset.bytes) {
            throw "Product asset promotion evidence differs from the manifest: $($asset.id)"
        }
        [void]$evidence.Add($entry)
    }

    $lock = $script:manifest.promptSet.structureLock
    $structureEntry = New-PromotionEvidenceDescriptor -RelativePath ([string]$lock.recordPath) -Kind 'product-structure-lock' -Id ([string]$lock.referenceAssetId) -RequiredRoot $script:jobRootFull -RequireNonBlank
    if ([string]$structureEntry.sha256 -ne [string]$script:structureLockRecordHash) {
        throw 'Product structure-lock promotion evidence changed during validation.'
    }
    [void]$evidence.Add($structureEntry)

    foreach ($promptItem in @($SetContext.PromptItems)) {
        $promptRoot = Get-TaskSubroot ('prompts\' + [string]$promptItem.type)
        [void]$evidence.Add((New-PromotionEvidenceDescriptor -RelativePath ([string]$promptItem.cardPath) -Kind 'design-card' -Id ([string]$promptItem.id) -RequiredRoot $promptRoot -RequireNonBlank))
        [void]$evidence.Add((New-PromotionEvidenceDescriptor -RelativePath ([string]$promptItem.promptPath) -Kind 'clean-prompt' -Id ([string]$promptItem.id) -RequiredRoot $promptRoot -RequireNonBlank))
    }

    foreach ($context in @($SetContext.CandidateContexts)) {
        $candidateEntry = New-PromotionEvidenceDescriptor -RelativePath ([string]$context.Candidate.path) -Kind 'candidate-image' -Id ([string]$context.Candidate.id) -RequiredRoot (Get-TaskSubroot ('candidates\' + [string]$context.Candidate.type))
        if ([string]$candidateEntry.sha256 -ne [string]$context.Hash -or [int64]$candidateEntry.bytes -ne [int64]$context.Bytes) {
            throw "Candidate promotion evidence changed during validation: $($context.Candidate.id)"
        }
        [void]$evidence.Add($candidateEntry)
        [void]$evidence.Add((New-PromotionEvidenceDescriptor -RelativePath ([string]$context.Candidate.acceptancePath) -Kind 'candidate-acceptance' -Id ([string]$context.Candidate.id) -RequiredRoot (Get-TaskSubroot 'acceptance') -RequireNonBlank))
    }

    [void]$evidence.Add((New-PromotionEvidenceDescriptor -RelativePath ([string]$script:manifest.setAcceptance.path) -Kind 'set-acceptance' -Id 'set' -RequiredRoot (Get-TaskSubroot 'acceptance') -RequireNonBlank))

    $seenPaths = @{}
    $seenKeys = @{}
    foreach ($entry in @($evidence)) {
        $pathKey = ([string]$entry.path).ToLowerInvariant()
        $identityKey = ([string]$entry.kind + ':' + [string]$entry.id).ToLowerInvariant()
        if ($seenPaths.ContainsKey($pathKey)) { throw "Duplicate promotion evidence path: $($entry.path)" }
        if ($seenKeys.ContainsKey($identityKey)) { throw "Duplicate promotion evidence identity: $($entry.kind)/$($entry.id)" }
        $seenPaths[$pathKey] = $true
        $seenKeys[$identityKey] = $true
    }
    return @($evidence)
}

function Get-VerifiedPromotedOutputs {
    if ([string]$script:manifest.status -ne 'promoted' -or $script:manifest.promotion.promoted -ne $true) { throw 'Manifest is not a promoted Taobao result.' }
    if ($script:manifest.approval.approved -ne $true) { throw 'The promoted Taobao set is missing final approval.' }
    Assert-Text $script:manifest.approval.statement 'approval.statement'
    Assert-Timestamp $script:manifest.approval.approvedAt 'approval.approvedAt'
    Assert-Timestamp $script:manifest.promotion.promotedAt 'promotion.promotedAt'
    if (@('main', 'production') -notcontains [string]$script:manifest.promotion.promotedBy) { throw 'promotion.promotedBy is not a formal actor.' }

    $setContext = Assert-SetReady
    foreach ($prompt in @($setContext.PromptItems)) {
        $promptRoot = Get-TaskSubroot ('prompts\' + [string]$prompt.type)
        $cardFull = Resolve-ProjectPath -RelativePath $prompt.cardPath -RequiredRoot $promptRoot
        $promptFull = Resolve-ProjectPath -RelativePath $prompt.promptPath -RequiredRoot $promptRoot
        Assert-NonBlankFile -Path $cardFull -Label ("Design card " + [string]$prompt.id)
        Assert-NonBlankFile -Path $promptFull -Label ("Clean prompt " + [string]$prompt.id)
    }

    Assert-Text $script:manifest.promotion.outputDirectory 'promotion.outputDirectory'
    $outputDirectory = Resolve-ProjectPath -RelativePath $script:manifest.promotion.outputDirectory -RequiredRoot 'outputs'
    if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) { throw 'Promoted Taobao output directory does not exist.' }
    $files = @($script:manifest.promotion.files)
    $contexts = @($setContext.CandidateContexts)
    if ($files.Count -ne $contexts.Count) { throw 'Promoted Taobao file ledger count differs from the accepted set.' }
    $outputs = New-Object System.Collections.ArrayList
    for ($index = 0; $index -lt $contexts.Count; $index++) {
        $context = $contexts[$index]; $file = $files[$index]
        foreach ($field in @('id','path','fileName','sha256','type','version')) { Assert-Text $file.$field ("promotion.files[]." + $field) }
        Assert-Sha256 $file.sha256 'promotion.files[].sha256'
        $expectedName = [System.IO.Path]::GetFileName($context.CandidateFull)
        if ([string]$file.id -ne [string]$context.Candidate.id -or [string]$file.type -ne [string]$context.Candidate.type -or [string]$file.version -ne [string]$context.Candidate.version -or [string]$file.fileName -ne $expectedName) { throw "Promoted file mapping differs from candidate at index $index." }
        $outputFull = Resolve-ProjectPath -RelativePath $file.path -RequiredRoot $outputDirectory
        if ([System.IO.Path]::GetFileName($outputFull) -ne [string]$file.fileName -or -not (Test-Path -LiteralPath $outputFull -PathType Leaf)) { throw "Promoted output is missing or misnamed at index $index." }
        $hash = (Get-FileHash -LiteralPath $outputFull -Algorithm SHA256).Hash
        $bytes = (Get-Item -LiteralPath $outputFull).Length
        if ($hash -ne [string]$context.Hash -or $hash -ne [string]$file.sha256 -or $bytes -ne [int64]$context.Bytes -or $bytes -ne [int64]$file.bytes) { throw "Promoted output integrity differs at index $index." }
        [void]$outputs.Add([ordered]@{ id=[string]$file.id; type=[string]$file.type; version=[string]$file.version; path=[string]$file.path; fileName=[string]$file.fileName; bytes=[int64]$bytes; sha256=[string]$hash })
    }
    $script:lastVerifiedSetContext = $setContext
    return @($outputs)
}

function Assert-PromotionReceipt {
    param(
        [Parameter(Mandatory = $true)][object[]]$Outputs,
        [Parameter(Mandatory = $true)][object[]]$Evidence
    )
    $receiptPath = Get-PromotionReceiptPath
    if (-not (Test-Path -LiteralPath $receiptPath -PathType Leaf)) { throw 'Gate-owned promotion receipt is missing.' }
    Assert-NoReparsePoints -Path $receiptPath -AllowedRoot $script:rootFull
    $receipt = Get-Content -Raw -Encoding UTF8 -LiteralPath $receiptPath | ConvertFrom-Json
    if ([string]$receipt.schemaVersion -ne '1.0' -or [string]$receipt.receiptKind -ne 'promotion-gate-receipt' -or [string]$receipt.gateKind -ne 'taobao-ecommerce') { throw 'Promotion receipt type is invalid.' }
    if ([string]$receipt.nonce -notmatch '^[a-f0-9]{32}$') { throw 'Promotion receipt nonce is invalid.' }
    if ([string]$receipt.jobId -ne [string]$script:manifest.jobId -or [string]$receipt.manifestPath -ne (Get-RelativeProjectPath -FullPath $script:manifestFull)) { throw 'Promotion receipt job binding is invalid.' }
    $manifestHash = (Get-FileHash -LiteralPath $script:manifestFull -Algorithm SHA256).Hash
    if ([string]$receipt.manifestSha256 -ne $manifestHash -or [string]$receipt.promotedAt -ne [string]$script:manifest.promotion.promotedAt -or [string]$receipt.promotedBy -ne [string]$script:manifest.promotion.promotedBy) { throw 'Promotion receipt manifest binding is invalid.' }
    $receiptOutputs = @($receipt.outputs)
    if ($receiptOutputs.Count -ne $Outputs.Count) { throw 'Promotion receipt output count differs.' }
    for ($index = 0; $index -lt $Outputs.Count; $index++) {
        foreach ($field in @('id','type','version','path','fileName','sha256')) { if ([string]$receiptOutputs[$index].$field -ne [string]$Outputs[$index].$field) { throw "Promotion receipt output binding differs at index $index." } }
        if ([int64]$receiptOutputs[$index].bytes -ne [int64]$Outputs[$index].bytes) { throw "Promotion receipt output byte length differs at index $index." }
    }
    if (-not (Test-HasProperty -Object $receipt -Name 'evidence')) {
        throw 'Promotion receipt evidence[] is missing; run Promote again to create a current receipt.'
    }
    $receiptEvidence = @($receipt.evidence)
    if ($receiptEvidence.Count -eq 0) { throw 'Promotion receipt evidence[] is empty; run Promote again to create a current receipt.' }
    if ($receiptEvidence.Count -ne $Evidence.Count) { throw 'Promotion receipt evidence count differs.' }
    $requiredEvidenceFields = @('path', 'kind', 'id', 'bytes', 'sha256')
    for ($index = 0; $index -lt $Evidence.Count; $index++) {
        $receiptEntry = $receiptEvidence[$index]
        if ($null -eq $receiptEntry) { throw "Promotion receipt evidence entry is null at index $index." }
        $actualFieldNames = @($receiptEntry.PSObject.Properties.Name)
        if ($actualFieldNames.Count -ne $requiredEvidenceFields.Count -or @($requiredEvidenceFields | Where-Object { $actualFieldNames -notcontains $_ }).Count -ne 0) {
            throw "Promotion receipt evidence fields differ at index $index."
        }
        foreach ($field in @('path', 'kind', 'id', 'sha256')) {
            Assert-Text $receiptEntry.$field ("promotion receipt evidence[]." + $field)
            if ([string]$receiptEntry.$field -ne [string]$Evidence[$index].$field) {
                throw "Promotion receipt evidence binding differs at index $index."
            }
        }
        Assert-Sha256 $receiptEntry.sha256 'promotion receipt evidence[].sha256'
        if ([int64]$receiptEntry.bytes -le 0 -or [int64]$receiptEntry.bytes -ne [int64]$Evidence[$index].bytes) {
            throw "Promotion receipt evidence byte length differs at index $index."
        }
        $receiptEvidenceFull = Resolve-ProjectPath -RelativePath ([string]$receiptEntry.path) -RequiredRoot $script:jobRootFull
        if (-not (Test-Path -LiteralPath $receiptEvidenceFull -PathType Leaf)) {
            throw "Promotion receipt evidence is missing at index $index."
        }
        Assert-NoReparsePoints -Path $receiptEvidenceFull -AllowedRoot $script:jobRootFull
    }
    return [pscustomobject]@{ Receipt=$receipt; ManifestHash=$manifestHash }
}

try {
    $rootFull = Get-NormalizedRoot $ProjectRoot
    if (-not (Test-Path -LiteralPath $rootFull -PathType Container)) {
        throw "Project root does not exist: $rootFull"
    }
    Assert-FixedHomePromptTemplate
    Assert-FixedDetailPromptTemplate

    $manifestFull = [System.IO.Path]::GetFullPath($ManifestPath)
    if (-not (Test-IsWithin -Path $manifestFull -Root $rootFull)) {
        throw 'Manifest must be inside the project root.'
    }
    $taobaoJobsRoot = Join-Path $rootFull 'temp\taobao-jobs'
    if (-not (Test-IsWithin -Path $manifestFull -Root $taobaoJobsRoot)) {
        throw 'Manifest must be inside temp/taobao-jobs/.'
    }
    Assert-NoReparsePoints -Path $manifestFull -AllowedRoot $rootFull
    if (-not (Test-Path -LiteralPath $manifestFull -PathType Leaf)) {
        throw "Manifest does not exist: $manifestFull"
    }

    $originalManifestBytes = [System.IO.File]::ReadAllBytes($manifestFull)
    $manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $manifestFull | ConvertFrom-Json
    if ([string]$manifest.schemaVersion -ne '1.0') {
        throw "Unsupported manifest schemaVersion: $($manifest.schemaVersion)"
    }
    Assert-Text $manifest.jobId 'jobId'
    if ([string]$manifest.jobId -notmatch '^[a-z0-9][a-z0-9-]{2,63}$') {
        throw "Unsafe jobId: $($manifest.jobId)"
    }
    if ([string]$manifest.jobId -match '^(con|prn|aux|nul|com[1-9]|lpt[1-9])$') {
        throw "jobId is a reserved Windows device name: $($manifest.jobId)"
    }
    $jobRootFull = Join-Path $taobaoJobsRoot ([string]$manifest.jobId)
    $expectedManifestFull = [System.IO.Path]::GetFullPath((Join-Path $jobRootFull 'manifest.json'))
    if (-not $manifestFull.Equals($expectedManifestFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'Manifest path does not match its jobId task directory.'
    }

    Assert-ManifestArrayContract
    Assert-ManifestBooleanContract
    Assert-ConfirmationTimestampContract
    Assert-ProductFactsContract
    Assert-HistoryContract
    if ($Action -notin @('CheckBeforeUpload', 'CheckAfterUpload')) {
        $null = Assert-CategoryReady
        Assert-GenerationExecutionPolicy
    }

    switch ($Action) {
        'CheckBeforeUpload' {
            $null = Assert-AssetUploadReady
            Write-Output 'PASS: Taobao product asset is archived, hash-verified, and authorized for upload.'
        }
        'CheckAfterUpload' {
            $null = Assert-AssetUploadVerified
            Write-Output 'PASS: Taobao product asset binding is verified for the active generation channel.'
        }
        'CheckBeforeGenerate' {
            $null = Get-CurrentPromptContext
            $null = Assert-AssetUploadVerified
            Write-Output 'PASS: current Taobao image is ready for generation.'
        }
        'CheckImageCandidate' {
            $null = Get-CurrentCandidateContext
            Write-Output 'PASS: current Taobao image candidate passed isolated evidence checks.'
        }
        'CheckBeforeNext' {
            $promptContext = Get-CurrentPromptContext
            $candidateContext = Get-CurrentCandidateContext
            if ([string]$promptContext.Current.status -ne 'accepted' -or [string]$candidateContext.Candidate.status -ne 'accepted') {
                throw 'The current Taobao image has not been accepted; the next prompt is blocked.'
            }
            Write-Output 'PASS: current Taobao image passed agent QC; the next item may proceed automatically without Emperor approval.'
        }
        'CheckSet' {
            $null = Assert-SetReady
            Write-Output 'PASS: complete Taobao image set passed consistency and mapping checks.'
        }
        'CheckBeforePromote' {
            $null = Assert-PromotionReady
            Write-Output 'PASS: approved Taobao image set is ready for non-overwrite promotion.'
        }
        'Promote' {
            $promotion = Assert-PromotionReady
            $outputDirectoryCreated = $false
            $manifestWritten = $false
            $receiptWritten = $false
            $receiptPath = Get-PromotionReceiptPath
            try {
                New-Item -ItemType Directory -Path $promotion.OutputFull | Out-Null
                $outputDirectoryCreated = $true
                Assert-NoReparsePoints -Path $promotion.OutputFull -AllowedRoot $script:rootFull
                $promotionFiles = New-Object System.Collections.ArrayList
                foreach ($target in @($promotion.Targets)) {
                    Assert-NoReparsePoints -Path $target.Context.CandidateFull -AllowedRoot $script:rootFull
                    Assert-NoReparsePoints -Path $target.TargetFull -AllowedRoot $script:rootFull
                    Copy-Item -LiteralPath $target.Context.CandidateFull -Destination $target.TargetFull
                    $outputHash = (Get-FileHash -LiteralPath $target.TargetFull -Algorithm SHA256).Hash
                    $outputBytes = (Get-Item -LiteralPath $target.TargetFull).Length
                    if ($outputHash -ne [string]$target.Context.Hash -or $outputBytes -ne [int64]$target.Context.Bytes) {
                        throw "Promoted output integrity differs from candidate: $($target.Context.Candidate.id)"
                    }
                    $targetRelative = [string]$manifest.promotion.outputDirectory + '/' + [string]$target.FileName
                    [void]$promotionFiles.Add([ordered]@{
                        id = [string]$target.Context.Candidate.id
                        path = $targetRelative.Replace('\', '/')
                        fileName = [string]$target.FileName
                        bytes = [int64]$outputBytes
                        sha256 = [string]$outputHash
                        type = [string]$target.Context.Candidate.type
                        version = [string]$target.Context.Candidate.version
                    })
                }

                $manifest.status = 'promoted'
                $manifest.promotion.promoted = $true
                $manifest.promotion.promotedAt = (Get-Date).ToString('o')
                $manifest.promotion.promotedBy = $ActorMode
                $manifest.promotion.files = @($promotionFiles)
                Write-ManifestAtomically -Value $manifest
                $manifestWritten = $true
                $manifestHash = (Get-FileHash -LiteralPath $manifestFull -Algorithm SHA256).Hash
                $promotionEvidence = @(Get-PromotionEvidence -SetContext $promotion.SetContext)
                $receipt = [ordered]@{
                    schemaVersion = '1.0'; receiptKind = 'promotion-gate-receipt'; gateKind = 'taobao-ecommerce'
                    nonce = [guid]::NewGuid().ToString('N'); jobId = [string]$manifest.jobId
                    manifestPath = Get-RelativeProjectPath -FullPath $manifestFull; manifestSha256 = $manifestHash
                    promotedAt = [string]$manifest.promotion.promotedAt; promotedBy = [string]$manifest.promotion.promotedBy
                    outputs = @($promotionFiles)
                    evidence = @($promotionEvidence)
                }
                Write-BytesAtomically -Path $receiptPath -Bytes (Convert-JsonToUtf8Bytes -Value $receipt -Depth 15)
                $receiptWritten = $true
                Write-Output "PASS: promoted Taobao image set to $($manifest.promotion.outputDirectory)"
            }
            catch {
                if ($receiptWritten -and (Test-Path -LiteralPath $receiptPath -PathType Leaf)) { Remove-Item -LiteralPath $receiptPath -Force }
                if ($manifestWritten) { Write-BytesAtomically -Path $manifestFull -Bytes $originalManifestBytes }
                if ($outputDirectoryCreated -and (Test-Path -LiteralPath $promotion.OutputFull -PathType Container)) {
                    Remove-Item -LiteralPath $promotion.OutputFull -Recurse -Force
                }
                throw
            }
        }
        'VerifyPromoted' {
            $null = Assert-ScopeReady
            $outputs = @(Get-VerifiedPromotedOutputs)
            $evidence = @(Get-PromotionEvidence -SetContext $script:lastVerifiedSetContext)
            $binding = Assert-PromotionReceipt -Outputs $outputs -Evidence $evidence
            [ordered]@{
                schemaVersion = '1.0'; verified = $true; gateKind = 'taobao-ecommerce'; jobId = [string]$manifest.jobId
                manifestPath = Get-RelativeProjectPath -FullPath $manifestFull; manifestSha256 = [string]$binding.ManifestHash
                receiptNonce = [string]$binding.Receipt.nonce; promotedAt = [string]$manifest.promotion.promotedAt
                promotedBy = [string]$manifest.promotion.promotedBy; outputs = @($outputs); verifiedAt = (Get-Date).ToUniversalTime().ToString('o')
            } | ConvertTo-Json -Depth 10 -Compress
        }
        'Status' {
            [pscustomobject]@{
                jobId = $manifest.jobId
                status = $manifest.status
                scope = $manifest.scope.mode
                currentItemId = $manifest.generation.currentItemId
                generationChannel = $manifest.generation.channel
                generationChannelStatus = $manifest.generation.channelStatus
                styleAnchorItemId = $manifest.generation.styleAnchor.itemId
                styleAnchorConfirmed = $manifest.generation.styleAnchor.confirmed
                promptCount = @($manifest.promptSet.items).Count
                candidateCount = @($manifest.candidates).Count
                setPassed = $manifest.setAcceptance.passed
                approved = $manifest.approval.approved
                promoted = $manifest.promotion.promoted
                assetTransferStatus = $manifest.assetTransfer.status
            } | ConvertTo-Json -Depth 4
        }
    }
    exit 0
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
