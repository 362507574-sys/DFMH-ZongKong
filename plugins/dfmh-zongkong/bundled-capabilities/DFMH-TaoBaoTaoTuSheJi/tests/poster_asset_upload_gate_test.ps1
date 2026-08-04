param()

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$gatePath = Join-Path $projectRoot 'scripts\poster_workflow_gate.ps1'
$sandbox = Join-Path $projectRoot ('temp\poster-upload-gate-test-' + [guid]::NewGuid().ToString('N'))
$sandboxFull = [System.IO.Path]::GetFullPath($sandbox)
$projectTempFull = [System.IO.Path]::GetFullPath((Join-Path $projectRoot 'temp')) + [System.IO.Path]::DirectorySeparatorChar

function Invoke-Gate {
    param([string]$Action, [string]$ManifestPath)
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $gatePath -Action $Action -ProjectRoot $sandboxFull -ManifestPath $ManifestPath -ActorMode test 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
    return [pscustomobject]@{ ExitCode = $exitCode; Output = ($output -join "`n") }
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Set-Manifest {
    param(
        [string]$ManifestPath,
        [bool]$Authorized = $true,
        [bool]$ThumbnailVerified = $false,
        [bool]$PathTextEntered = $false,
        [string]$Method = ''
    )
    $assetRelative = 'temp/poster-jobs/upload-gate/asset.png'
    $assetFull = Join-Path $sandboxFull ($assetRelative -replace '/', '\')
    $hash = (Get-FileHash -LiteralPath $assetFull -Algorithm SHA256).Hash
    $frameworkRelative = 'templates/PROMOTIONAL_POSTER_PROMPT_V1.md'
    $frameworkFull = Join-Path $sandboxFull ($frameworkRelative -replace '/', '\')
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $frameworkFull) | Out-Null
    Copy-Item -LiteralPath (Join-Path $projectRoot 'templates\PROMOTIONAL_POSTER_PROMPT_V1.md') -Destination $frameworkFull -Force
    $frameworkHash = (Get-FileHash -LiteralPath $frameworkFull -Algorithm SHA256).Hash
    $platformRelative = 'skills/creating-promotional-posters/references/PLATFORM_PROFILES.md'
    $platformFull = Join-Path $sandboxFull ($platformRelative -replace '/', '\')
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $platformFull) | Out-Null
    Copy-Item -LiteralPath (Join-Path $projectRoot 'skills\creating-promotional-posters\references\PLATFORM_PROFILES.md') -Destination $platformFull -Force
    $platformHash = (Get-FileHash -LiteralPath $platformFull -Algorithm SHA256).Hash
    $categoryRelative = 'skills/creating-promotional-posters/references/CATEGORY_ADAPTERS.md'
    $categoryFull = Join-Path $sandboxFull ($categoryRelative -replace '/', '\')
    Copy-Item -LiteralPath (Join-Path $projectRoot 'skills\creating-promotional-posters\references\CATEGORY_ADAPTERS.md') -Destination $categoryFull -Force
    $categoryHash = (Get-FileHash -LiteralPath $categoryFull -Algorithm SHA256).Hash
    $promptRelative = 'temp/poster-jobs/upload-gate/prompts/final-V1.txt'
    $promptFull = Join-Path $sandboxFull ($promptRelative -replace '/', '\')
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $promptFull) | Out-Null
    [System.IO.File]::WriteAllText($promptFull, '[CONFIRMED_BRIEF] upload fixture [PLATFORM_PROFILE] generic poster [CATEGORY_ADAPTER] general category [REFERENCE_VISUAL_DNA] locked editorial direction [COMPOSITION] asymmetric social composition [MATERIAL_AND_LIGHT] natural light and material [TYPOGRAPHY] restrained sans serif [ANTI_AI_FAILURES] no plastic no fake studio no template [GENERATION_PLAN] one image one pose [VISUAL_PASS] visual base [LAYOUT_PASS] verified layout [OUTPUT] publishable poster')
    $promptHash = (Get-FileHash -LiteralPath $promptFull -Algorithm SHA256).Hash
    $manifest = [ordered]@{
        schemaVersion = '1.0'
        jobId = 'upload-gate'
        originThreadMode = 'test'
        status = 'ready_to_generate'
        brief = [ordered]@{
            taskType = 'general_poster'
            theme = 'Synthetic upload test'; purpose = 'Workflow verification'; channels = @('social')
            audience = 'Adults'; mandatoryCopy = @('Title'); editableCopyPolicy = 'May optimize'
            assets = @($assetRelative); style = 'Editorial'; colors = 'Pink'; forbidden = @('Fake QR')
            size = '1080x1440'; outputFormat = 'PNG'; deadline = 'No deadline'; missing = @(); assumptions = @()
            confirmed = $true; confirmedAt = '2026-07-14T18:00:00+08:00'; confirmationStatement = 'Confirmed'
        }
        deliveryProfile = [ordered]@{
            platform = 'generic_poster'; contentMode = 'single_poster'; aspectRatio = 'custom'; mobileFirst = $false
            safeArea = 'Keep all verified content inside a documented safe area'
            profilePath = $platformRelative; profileVersion = 'V1'; profileSha256 = $platformHash
        }
        campaignIntent = [ordered]@{
            primary = 'general_campaign'; secondary = 'none'; splitRequired = $false
            splitReason = 'Single primary action'; deliveryOrder = @('general_campaign')
            primaryAction = 'Complete the verified upload test action'; companionMessageRequired = $false
            candidateRoles = @('general_campaign')
        }
        categoryProfile = [ordered]@{
            id = 'general'; adapterPath = $categoryRelative; adapterVersion = 'V1'; adapterSha256 = $categoryHash
            humanSubject = 'none'; safetyProfile = 'general_commercial_v1'; fidelityFocus = @(); confirmedDirectionChange = $false
        }
        assetTransfer = [ordered]@{
            required = $true
            assetPath = $assetRelative
            expectedSha256 = $hash
            destination = 'ChatGPT web via QQ Browser'
            authorizationConfirmed = $Authorized
            authorizationStatement = if ($Authorized) { 'Approved synthetic upload test' } else { '' }
            authorizationAt = if ($Authorized) { '2026-07-14T18:01:00+08:00' } else { '' }
            method = $Method
            clipboardPrepared = ($Method -eq 'clipboard_file_paste')
            thumbnailVerified = $ThumbnailVerified
            verifiedAssetName = if ($ThumbnailVerified) { 'asset.png' } else { '' }
            verifiedAt = if ($ThumbnailVerified) { '2026-07-14T18:02:00+08:00' } else { '' }
            pathTextEntered = $PathTextEntered
            status = if ($ThumbnailVerified) { 'verified' } else { 'authorized' }
            failureReason = ''
        }
        designTranslation = [ordered]@{
            framework = [ordered]@{ id = 'PROMOTIONAL_POSTER_PROMPT_V1'; version = 'V3'; path = $frameworkRelative; sha256 = $frameworkHash }
            riskLevel = 'routine_locked_direction'
            visualDNA = [ordered]@{
                referenceRequired = $false
                referenceAssetIds = @()
                referenceAssets = @()
                composition = 'Asymmetric editorial subject with a clear mobile reading path'
                environment = 'Believable real commercial environment with physical depth'
                lighting = 'Soft natural directional light with realistic material falloff'
                palette = 'Warm neutral restrained palette with authoritative asset colors'
                typography = 'Modern restrained sans serif hierarchy for mobile viewing'
                texture = 'Natural skin fabric and environmental texture without plastic rendering'
                whitespace = 'Intentional breathing room around the subject and headline'
                avoidPatterns = @('plastic skin', 'fake studio', 'gold rim light', 'template layout', 'meaningless decoration')
            }
            directionSelection = [ordered]@{
                mode = 'direct_confirmed'
                options = @([ordered]@{ id = 'D1'; label = 'Locked editorial'; composition = 'asymmetric editorial layout'; lighting = 'soft natural key light'; palette = 'warm neutral'; commercialFit = 'confirmed social campaign'; risk = 'low routine risk' })
                selectedId = 'D1'
                selectedBy = 'user'
                selectionStatement = 'Synthetic fixture direction confirmed'
                selectedAt = '2026-07-17T17:00:00+08:00'
            }
            promptBuild = [ordered]@{ version = 'V1'; path = $promptRelative; sha256 = $promptHash; frameworkApplied = $true }
        }
        generation = [ordered]@{
            method = ''; model = ''; sourceReference = ''; originalDownloadPath = ''; paid = $false
            route = [ordered]@{
                currentMethod = 'ChatGPT web via QQ Browser'
                currentVersion = 'V1'
                authorizationType = 'project_default'
                authorizationJobId = 'upload-gate'
                authorizationVersion = 'V1'
                authorizationStatement = 'Project default QQ Browser ChatGPT web route'
                authorizedAt = '2026-07-14T18:00:00+08:00'
                fallback = [ordered]@{ method = ''; changesConfirmedDirection = $false; directionChangeConfirmed = $false; confirmationStatement = ''; confirmedAt = '' }
            }
            series = [ordered]@{
                requestedOutputs = 1; requestMode = 'sequential_single'; outputsPerRequest = 1; currentIndex = 1
                anchorStrategy = 'first_approved_anchor'; anchorStatus = 'not_required'; continuityLock = @()
                maxAttemptsPerOutput = 2; promptLoadPolicy = 'single_frame_single_composition_single_pose'; safetyBlockPolicy = 'compact_safety_block'
            }
            refusals = @()
        }
        candidate = [ordered]@{ path = ''; acceptancePath = ''; version = 'V1'; sha256 = ''; bytes = 0; width = 0; height = 0; dpi = 0; format = 'PNG'; quality = [ordered]@{ fileIntegrity = $false; dimensionsChecked = $false; textChecked = $false; visualChecked = $false; qrChecked = $false; aiArtifactsChecked = $false } }
        approval = [ordered]@{ approved = $false; statement = ''; approvedAt = '' }
        promotion = [ordered]@{ outputPath = ''; promoted = $false; promotedAt = ''; promotedBy = '' }
        history = @()
    }
    $manifest | ConvertTo-Json -Depth 15 | Set-Content -Encoding UTF8 -LiteralPath $ManifestPath
}

New-Item -ItemType Directory -Force -Path (Join-Path $sandboxFull 'temp\poster-jobs\upload-gate'), (Join-Path $sandboxFull 'outputs') | Out-Null

try {
    $assetPath = Join-Path $sandboxFull 'temp\poster-jobs\upload-gate\asset.png'
    [System.IO.File]::WriteAllBytes($assetPath, [Convert]::FromBase64String('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII='))
    $manifestPath = Join-Path $sandboxFull 'temp\poster-jobs\upload-gate\manifest.json'

    Set-Manifest -ManifestPath $manifestPath -Authorized $true
    $before = Invoke-Gate -Action 'CheckBeforeUpload' -ManifestPath $manifestPath
    Assert-True ($before.ExitCode -eq 0) ('Authorized verified local asset should pass before-upload gate: ' + $before.Output)

    Set-Manifest -ManifestPath $manifestPath -Authorized $false
    $unauthorized = Invoke-Gate -Action 'CheckBeforeUpload' -ManifestPath $manifestPath
    Assert-True ($unauthorized.ExitCode -ne 0) 'An unauthorized asset upload must fail.'

    Set-Manifest -ManifestPath $manifestPath -Authorized $true -ThumbnailVerified $true -Method 'clipboard_file_paste'
    $after = Invoke-Gate -Action 'CheckAfterUpload' -ManifestPath $manifestPath
    Assert-True ($after.ExitCode -eq 0) ('Verified clipboard upload should pass after-upload gate: ' + $after.Output)

    Set-Manifest -ManifestPath $manifestPath -Authorized $true -ThumbnailVerified $false -Method 'clipboard_file_paste'
    $noThumbnail = Invoke-Gate -Action 'CheckAfterUpload' -ManifestPath $manifestPath
    Assert-True ($noThumbnail.ExitCode -ne 0) 'Upload without a verified thumbnail must fail.'

    Set-Manifest -ManifestPath $manifestPath -Authorized $true -ThumbnailVerified $true -PathTextEntered $true -Method 'clipboard_file_paste'
    $pathLeak = Invoke-Gate -Action 'CheckAfterUpload' -ManifestPath $manifestPath
    Assert-True ($pathLeak.ExitCode -ne 0) 'Upload that entered a local path as text must fail.'

    Write-Output 'PASS: poster upload gate accepted verified clipboard transfer and rejected three unsafe states.'
}
finally {
    if (Test-Path -LiteralPath $sandboxFull) {
        $verified = [System.IO.Path]::GetFullPath($sandboxFull)
        if (-not $verified.StartsWith($projectTempFull, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw 'Refusing to remove an upload gate sandbox outside project temp.'
        }
        Remove-Item -LiteralPath $verified -Recurse -Force
    }
}
