param()

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$gatePath = Join-Path $projectRoot 'scripts\poster_workflow_gate.ps1'
$templatePath = Join-Path $projectRoot 'templates\PROMOTIONAL_POSTER_JOB.json'

if (-not (Test-Path -LiteralPath $gatePath -PathType Leaf)) {
    throw 'Missing poster workflow gate script.'
}
if (-not (Test-Path -LiteralPath $templatePath -PathType Leaf)) {
    throw 'Missing promotional poster job template.'
}

$sandbox = Join-Path $projectRoot ('temp\poster-gate-test-' + [guid]::NewGuid().ToString('N'))
$sandboxFull = [System.IO.Path]::GetFullPath($sandbox)
$projectTempFull = [System.IO.Path]::GetFullPath((Join-Path $projectRoot 'temp')) + [System.IO.Path]::DirectorySeparatorChar
$defaultRootArtifacts = @()
if (-not $sandboxFull.StartsWith($projectTempFull, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Refusing to create test sandbox outside project temp.'
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Invoke-Gate {
    param(
        [string]$Action,
        [string]$ManifestPath,
        [string]$ActorMode = 'main'
    )
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $gatePath -Action $Action -ProjectRoot $sandboxFull -ManifestPath $ManifestPath -ActorMode $ActorMode 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
    return [pscustomobject]@{ ExitCode = $exitCode; Output = ($output -join "`n") }
}

function Invoke-GateWithDefaultProjectRoot {
    param(
        [string]$Action,
        [string]$ManifestPath,
        [string]$ActorMode = 'main'
    )
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $gatePath -Action $Action -ManifestPath $ManifestPath -ActorMode $ActorMode 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
    return [pscustomobject]@{ ExitCode = $exitCode; Output = ($output -join "`n") }
}

function Start-ConcurrentGateWorker {
    param(
        [string]$WorkerPath,
        [string]$WorkerId,
        [string]$ManifestPath,
        [string]$BarrierRoot
    )
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = 'powershell.exe'
    $startInfo.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $WorkerPath + '" -WorkerId "' + $WorkerId + '" -GatePath "' + $gatePath + '" -ProjectRoot "' + $sandboxFull + '" -ManifestPath "' + $ManifestPath + '" -BarrierRoot "' + $BarrierRoot + '"'
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    if (-not $process.Start()) { throw "Failed to start concurrent gate worker: $WorkerId" }
    return $process
}

function Wait-ForPaths {
    param([string[]]$Paths, [int]$TimeoutMilliseconds = 10000)
    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMilliseconds)
    while ($true) {
        if (@($Paths | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) }).Count -eq 0) { return }
        if ([DateTime]::UtcNow -ge $deadline) { throw 'Timed out waiting for concurrent gate worker barrier.' }
        Start-Sleep -Milliseconds 20
    }
}

function Write-Manifest {
    param(
        [string]$Name,
        [string]$Status = 'ready_to_generate',
        [bool]$BriefConfirmed = $true,
        [string[]]$Missing = @(),
        [string]$CandidateRelativePath = '',
        [bool]$IncludeSource = $true,
        [bool]$IncludeAcceptance = $true,
        [bool]$QualityPassed = $true,
        [bool]$ProductPoster = $false,
        [bool]$ProductEvidenceReady = $true,
        [bool]$ProductMappingPassed = $true,
        [bool]$Approved = $false,
        [string]$OriginThreadMode = 'test',
        [string]$Platform = 'generic_poster',
        [string]$CategoryId = 'general',
        [string]$HumanSubject = 'none',
        [string]$SafetyProfile = 'general_commercial_v1',
        [int]$RequestedOutputs = 1,
        [int]$OutputsPerRequest = 1,
        [string]$PrimaryIntent = 'general_campaign',
        [string]$SecondaryIntent = 'none',
        [bool]$SplitRequired = $false
    )

    $jobDir = Join-Path $sandboxFull ('temp\poster-jobs\' + $Name)
    New-Item -ItemType Directory -Force -Path $jobDir | Out-Null
    $candidatePath = if ($CandidateRelativePath) { $CandidateRelativePath } else { 'temp/poster-jobs/' + $Name + '/candidate.png' }
    $acceptancePath = 'temp/poster-jobs/' + $Name + '/acceptance.md'
    $manifestPath = Join-Path $jobDir 'manifest.json'
    $productAssetRelative = 'temp/poster-jobs/' + $Name + '/source-product.png'
    $productAssetFull = Join-Path $sandboxFull ($productAssetRelative -replace '/', '\')
    $productLockRelative = 'temp/poster-jobs/' + $Name + '/product-identity-lock.md'
    $productLockFull = Join-Path $sandboxFull ($productLockRelative -replace '/', '\')
    $productAssetHash = ''
    $productLockHash = ''
    if ($ProductPoster) {
        $sourcePng = [Convert]::FromBase64String('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=')
        [System.IO.File]::WriteAllBytes($productAssetFull, $sourcePng)
        [System.IO.File]::WriteAllText($productLockFull, 'Synthetic product identity lock for deterministic gate testing.')
        $productAssetHash = (Get-FileHash -LiteralPath $productAssetFull -Algorithm SHA256).Hash
        $productLockHash = (Get-FileHash -LiteralPath $productLockFull -Algorithm SHA256).Hash
    }

    $frameworkRelative = 'templates/PROMOTIONAL_POSTER_PROMPT_V1.md'
    $frameworkFull = Join-Path $sandboxFull ($frameworkRelative -replace '/', '\')
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $frameworkFull) | Out-Null
    if (-not (Test-Path -LiteralPath $frameworkFull -PathType Leaf)) {
        Copy-Item -LiteralPath (Join-Path $projectRoot 'templates\PROMOTIONAL_POSTER_PROMPT_V1.md') -Destination $frameworkFull
    }
    $frameworkHash = (Get-FileHash -LiteralPath $frameworkFull -Algorithm SHA256).Hash
    $platformProfileRelative = 'skills/creating-promotional-posters/references/PLATFORM_PROFILES.md'
    $platformProfileFull = Join-Path $sandboxFull ($platformProfileRelative -replace '/', '\')
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $platformProfileFull) | Out-Null
    if (-not (Test-Path -LiteralPath $platformProfileFull -PathType Leaf)) {
        Copy-Item -LiteralPath (Join-Path $projectRoot 'skills\creating-promotional-posters\references\PLATFORM_PROFILES.md') -Destination $platformProfileFull
    }
    $platformProfileHash = (Get-FileHash -LiteralPath $platformProfileFull -Algorithm SHA256).Hash
    $categoryAdapterRelative = 'skills/creating-promotional-posters/references/CATEGORY_ADAPTERS.md'
    $categoryAdapterFull = Join-Path $sandboxFull ($categoryAdapterRelative -replace '/', '\')
    if (-not (Test-Path -LiteralPath $categoryAdapterFull -PathType Leaf)) {
        Copy-Item -LiteralPath (Join-Path $projectRoot 'skills\creating-promotional-posters\references\CATEGORY_ADAPTERS.md') -Destination $categoryAdapterFull
    }
    $categoryAdapterHash = (Get-FileHash -LiteralPath $categoryAdapterFull -Algorithm SHA256).Hash
    $promptRelative = 'temp/poster-jobs/' + $Name + '/prompts/final-V1.txt'
    $promptFull = Join-Path $sandboxFull ($promptRelative -replace '/', '\')
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $promptFull) | Out-Null
    $promptText = '[CONFIRMED_BRIEF] synthetic brief [PLATFORM_PROFILE] bound platform profile [CATEGORY_ADAPTER] bound category adapter [REFERENCE_VISUAL_DNA] synthetic visual DNA [COMPOSITION] balanced editorial composition [MATERIAL_AND_LIGHT] natural material and believable light [TYPOGRAPHY] restrained typography [ANTI_AI_FAILURES] no plastic skin no fake studio no template look [GENERATION_PLAN] one image one composition one pose [VISUAL_PASS] generate the visual base [LAYOUT_PASS] apply verified copy and layout [OUTPUT] complete publishable poster'
    [System.IO.File]::WriteAllText($promptFull, $promptText)
    $promptHash = (Get-FileHash -LiteralPath $promptFull -Algorithm SHA256).Hash
    $designReviewRelative = 'temp/poster-jobs/' + $Name + '/reviews/design-review-V1.md'
    $designReviewFull = Join-Path $sandboxFull ($designReviewRelative -replace '/', '\')
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $designReviewFull) | Out-Null
    [System.IO.File]::WriteAllText($designReviewFull, 'Synthetic reference aesthetic comparison and anti-AI review evidence.')
    $designReviewHash = (Get-FileHash -LiteralPath $designReviewFull -Algorithm SHA256).Hash

    $manifest = [ordered]@{
        schemaVersion = '1.0'
        jobId = $Name
        originThreadMode = $OriginThreadMode
        status = $Status
        brief = [ordered]@{
            taskType = if ($ProductPoster) { 'product_sales_poster' } else { 'general_poster' }
            theme = 'Synthetic poster test'
            purpose = 'Workflow verification'
            channels = @('social')
            audience = 'Adults'
            mandatoryCopy = @('Synthetic title')
            editableCopyPolicy = 'Agent may optimize non-factual copy'
            assets = @('No external assets required')
            style = 'Editorial commercial poster'
            colors = 'Warm neutral'
            forbidden = @('Fake QR code')
            size = '1080x1440'
            outputFormat = 'PNG'
            deadline = 'No deadline'
            missing = @($Missing)
            assumptions = @()
            confirmed = $BriefConfirmed
            confirmedAt = if ($BriefConfirmed) { '2026-07-14T17:00:00+08:00' } else { '' }
            confirmationStatement = if ($BriefConfirmed) { 'Confirmed for automated test' } else { '' }
        }
        deliveryProfile = [ordered]@{
            platform = $Platform
            contentMode = if ($SplitRequired) { 'dual_intent_pair' } elseif ($RequestedOutputs -gt 1) { 'carousel_series' } else { 'single_poster' }
            aspectRatio = if ($Platform -eq 'xiaohongshu') { '3:4' } else { 'custom' }
            mobileFirst = ($Platform -eq 'xiaohongshu')
            safeArea = 'Keep verified copy and product inside the documented platform-safe region'
            profilePath = $platformProfileRelative
            profileVersion = 'V1'
            profileSha256 = $platformProfileHash
        }
        campaignIntent = [ordered]@{
            primary = $PrimaryIntent
            secondary = $SecondaryIntent
            splitRequired = $SplitRequired
            splitReason = if ($SplitRequired) { 'Two independent actions require separate posters' } else { 'Single primary action' }
            deliveryOrder = if ($SplitRequired) { @('event_notice', 'sales_conversion') } else { @($PrimaryIntent) }
            primaryAction = 'Complete the single verified action'
            companionMessageRequired = $true
            candidateRoles = if ($SplitRequired) { @('event_notice', 'sales_conversion') } else { @($PrimaryIntent) }
        }
        categoryProfile = [ordered]@{
            id = $CategoryId
            adapterPath = $categoryAdapterRelative
            adapterVersion = 'V1'
            adapterSha256 = $categoryAdapterHash
            humanSubject = $HumanSubject
            safetyProfile = $SafetyProfile
            fidelityFocus = if ($CategoryId -eq 'intimate_apparel_adult') { @('cup and silhouette geometry', 'center gore and underband topology', 'side wing and strap routing') } else { @() }
            confirmedDirectionChange = $false
        }
        productPoster = [ordered]@{
            required = $ProductPoster
            campaignStage = if ($ProductPoster) { 'daily_promotion' } else { 'not_applicable' }
            usageScenarioDecision = if ($ProductPoster) { 'required_with_product_as_primary_subject' } else { 'not_applicable' }
            referencePolicy = if ($ProductPoster) { 'Reference controls layout only, never product facts' } else { 'not_applicable' }
            variantPolicy = [ordered]@{
                mode = if ($ProductPoster) { 'same_content_different_style' } else { 'single' }
                contentLocked = if ($ProductPoster) { $true } else { $false }
                contentContract = if ($ProductPoster) { @('Synthetic title', 'Confirmed reversible handle') } else { @() }
                contentContractHash = if ($ProductPoster) { ('A' * 64) } else { '' }
                allowedDifferences = if ($ProductPoster) { @('visual style') } else { @() }
            }
            productSource = [ordered]@{
                required = $ProductPoster
                assets = if ($ProductPoster) {
                    @([ordered]@{
                        id = 'SRC-01'
                        path = $productAssetRelative
                        sha256 = $productAssetHash
                        role = 'authoritative product reference'
                        view = 'front three-quarter source view'
                        approved = $true
                    })
                } else { @() }
                identityLock = [ordered]@{
                    recordPath = if ($ProductPoster) { $productLockRelative } else { '' }
                    recordSha256 = if ($ProductPoster) { $productLockHash } else { '' }
                    confirmed = $ProductPoster
                    immutableComponents = if ($ProductPoster) { @('molded cup pair remains connected to the same underband', 'two shoulder straps connect to the original cup corners', 'side wings remain attached to both cup and back band') } else { @() }
                    connectionTopology = if ($ProductPoster) { @('each shoulder strap connects one cup to the rear band', 'both cups connect through the same center gore and underband') } else { @() }
                    relativeGeometry = if ($ProductPoster) { @('cup pair stays centered above one continuous underband') } else { @() }
                    appearanceTraits = if ($ProductPoster) { @('source color material trim and unbranded appearance stay unchanged') } else { @() }
                    visibleViewBoundary = if ($ProductPoster) { @('use only the archived front three-quarter view and crops from it') } else { @() }
                    allowedVariations = if ($ProductPoster) { @('background lighting typography and safe crop may change') } else { @() }
                    forbiddenVariations = if ($ProductPoster) { @('do not add remove or reconnect product components', 'do not invent a back bottom or internal view absent from source') } else { @() }
                }
                currentBinding = [ordered]@{
                    jobId = $Name
                    version = 'V1'
                    method = 'ChatGPT web via QQ Browser'
                    referenceAssetIds = if ($ProductPoster) { @('SRC-01') } else { @() }
                    referenceSha256s = if ($ProductPoster) { @($productAssetHash) } else { @() }
                    status = if ($ProductPoster) { 'ready_to_upload' } else { 'not_required' }
                }
            }
            claims = if ($ProductPoster -and $ProductEvidenceReady) {
                @([ordered]@{
                    id = '01'
                    copy = 'Confirmed reversible handle'
                    evidenceType = 'user_confirmed'
                    evidenceReference = 'Synthetic user confirmation'
                    visualRequirement = 'Show both directions or an explicit neutral diagram'
                    forbiddenVisual = 'Single unrelated handle crop'
                    verified = $true
                })
            } else { @() }
        }
        assetTransfer = [ordered]@{
            required = $ProductPoster
            assetPath = if ($ProductPoster) { $productAssetRelative } else { '' }
            expectedSha256 = if ($ProductPoster) { $productAssetHash } else { '' }
            referenceAssetId = if ($ProductPoster) { 'SRC-01' } else { '' }
            bindingJobId = if ($ProductPoster) { $Name } else { '' }
            bindingVersion = 'V1'
            bindingMethod = 'ChatGPT web via QQ Browser'
            destination = 'ChatGPT web via QQ Browser'
            authorizationConfirmed = $ProductPoster
            authorizationStatement = if ($ProductPoster) { 'Synthetic upload authorization' } else { '' }
            authorizationAt = if ($ProductPoster) { '2026-07-17T17:00:00+08:00' } else { '' }
            method = ''
            clipboardPrepared = $false
            thumbnailVerified = $false
            verifiedAssetName = ''
            verifiedAt = ''
            pathTextEntered = $false
            status = if ($ProductPoster) { 'pending' } else { 'not_required' }
            failureReason = ''
        }
        designTranslation = [ordered]@{
            framework = [ordered]@{
                id = 'PROMOTIONAL_POSTER_PROMPT_V1'
                version = 'V1'
                path = $frameworkRelative
                sha256 = $frameworkHash
            }
            riskLevel = if ($ProductPoster) { 'reference_sensitive' } else { 'routine_locked_direction' }
            visualDNA = [ordered]@{
                referenceRequired = $ProductPoster
                referenceAssetIds = if ($ProductPoster) { @('SRC-01') } else { @() }
                referenceAssets = if ($ProductPoster) { @([ordered]@{ id = 'SRC-01'; path = $productAssetRelative; sha256 = $productAssetHash; role = 'visual direction reference' }) } else { @() }
                composition = 'Editorial subject with intentional asymmetry and a clear mobile reading path'
                environment = 'Believable real commercial environment with physical depth and natural imperfections'
                lighting = 'Soft directional light with realistic falloff and no synthetic glowing outline'
                palette = 'Warm neutral restrained palette with product color remaining authoritative'
                typography = 'Modern restrained typography with a clear three-level information hierarchy'
                texture = 'Natural skin fabric and material texture without waxy or plastic rendering'
                whitespace = 'Deliberate breathing room around the subject and headline without empty template blocks'
                avoidPatterns = @('plastic skin', 'fake studio backdrop', 'gold rim light cliche', 'template poster layout', 'meaningless decoration')
            }
            directionSelection = [ordered]@{
                mode = if ($ProductPoster) { 'three_direction_preselection' } else { 'direct_confirmed' }
                options = if ($ProductPoster) {
                    @(
                        [ordered]@{ id = 'D1'; label = 'Natural editorial'; composition = 'cropped lifestyle portrait'; lighting = 'soft window daylight'; palette = 'warm neutral'; commercialFit = 'social commerce cover'; risk = 'product details need close review' },
                        [ordered]@{ id = 'D2'; label = 'Modern minimal'; composition = 'asymmetric product hero'; lighting = 'large softbox realism'; palette = 'black cream'; commercialFit = 'premium retail campaign'; risk = 'may feel too restrained' },
                        [ordered]@{ id = 'D3'; label = 'Magazine crop'; composition = 'dynamic fashion crop'; lighting = 'natural contrast'; palette = 'brown charcoal'; commercialFit = 'aspirational social post'; risk = 'text space requires control' }
                    )
                } else {
                    @([ordered]@{ id = 'D1'; label = 'Confirmed editorial'; composition = 'locked editorial layout'; lighting = 'soft natural key light'; palette = 'warm neutral'; commercialFit = 'confirmed campaign use'; risk = 'low routine risk' })
                }
                selectedId = 'D1'
                selectedBy = if ($ProductPoster) { 'agent_authorized' } else { 'user' }
                selectionStatement = 'Selected from recorded directions for deterministic workflow testing'
                selectedAt = '2026-07-17T17:00:00+08:00'
            }
            promptBuild = [ordered]@{
                version = 'V1'
                path = $promptRelative
                sha256 = $promptHash
                frameworkApplied = $true
            }
        }
        generation = [ordered]@{
            route = [ordered]@{
                currentMethod = 'ChatGPT web via QQ Browser'
                currentVersion = 'V1'
                authorizationType = 'project_default'
                authorizationJobId = $Name
                authorizationVersion = 'V1'
                authorizationStatement = 'Project default production route'
                authorizedAt = 'project_rule'
                fallback = [ordered]@{
                    method = ''
                    changesConfirmedDirection = $false
                    confirmed = $false
                    confirmationStatement = ''
                    confirmedAt = ''
                }
            }
            series = [ordered]@{
                requestedOutputs = $RequestedOutputs
                requestMode = 'sequential_single'
                outputsPerRequest = $OutputsPerRequest
                currentIndex = 1
                anchorStrategy = 'first_approved_anchor'
                anchorStatus = if ($RequestedOutputs -gt 1) { 'pending' } else { 'not_required' }
                continuityLock = @()
                maxAttemptsPerOutput = 2
                promptLoadPolicy = 'single_frame_single_composition_single_pose'
                safetyBlockPolicy = 'compact_safety_block'
            }
            method = if ($IncludeSource) { 'ChatGPT web via QQ Browser' } else { '' }
            model = if ($IncludeSource) { 'Not exposed by provider' } else { '' }
            sourceReference = if ($IncludeSource) { 'synthetic://test-conversation' } else { '' }
            originalDownloadPath = if ($IncludeSource) { 'temp/chatgpt-downloads/synthetic-source.png' } else { '' }
            paid = $false
            refusals = @()
        }
        candidate = [ordered]@{
            role = $PrimaryIntent
            path = $candidatePath
            acceptancePath = if ($IncludeAcceptance) { $acceptancePath } else { '' }
            version = 'V1'
            sha256 = ''
            bytes = 0
            width = 1
            height = 1
            dpi = 96
            format = 'PNG'
            quality = [ordered]@{
                fileIntegrity = $QualityPassed
                dimensionsChecked = $QualityPassed
                textChecked = $QualityPassed
                visualChecked = $QualityPassed
                qrChecked = $QualityPassed
                aiArtifactsChecked = $QualityPassed
                productStructureChecked = if ($ProductPoster) { $QualityPassed } else { $false }
                claimProvenanceChecked = if ($ProductPoster) { $QualityPassed } else { $false }
                claimVisualMappingChecked = if ($ProductPoster) { ($QualityPassed -and $ProductMappingPassed) } else { $false }
                variantContentConsistencyChecked = if ($ProductPoster) { $QualityPassed } else { $false }
                usageScenarioChecked = if ($ProductPoster) { $QualityPassed } else { $false }
            }
            productEvidence = [ordered]@{
                mapping = if ($ProductPoster) {
                    @([ordered]@{
                        claimId = '01'
                        displayedCopy = 'Confirmed reversible handle'
                        visualShown = 'Two directions or an explicit neutral diagram'
                        sourceReference = 'Synthetic user confirmation'
                        mappingVerified = $ProductMappingPassed
                    })
                } else { @() }
                reviewStatement = if ($ProductPoster) { 'Synthetic item-by-item review' } else { '' }
                fidelityReview = [ordered]@{
                    referenceAssetIds = if ($ProductPoster) { @('SRC-01') } else { @() }
                    structureCompared = if ($ProductPoster) { $QualityPassed } else { $false }
                    appearanceCompared = if ($ProductPoster) { $QualityPassed } else { $false }
                    unsupportedViewsAbsent = if ($ProductPoster) { $QualityPassed } else { $false }
                    differences = @()
                    passed = if ($ProductPoster) { $QualityPassed } else { $false }
                    reviewStatement = if ($ProductPoster) { 'Synthetic source-to-candidate fidelity review' } else { '' }
                }
            }
            designReview = [ordered]@{
                reviewPath = $designReviewRelative
                reviewSha256 = $designReviewHash
                referenceCompared = $ProductPoster
                visualDNAAligned = $QualityPassed
                antiAIPatternsAbsent = $QualityPassed
                commercialAestheticChecked = $QualityPassed
                unresolvedDifferences = @()
                passed = $QualityPassed
            }
        }
        candidateSet = [ordered]@{
            required = $SplitRequired
            expectedRoles = if ($SplitRequired) { @('event_notice', 'sales_conversion') } else { @() }
            entries = @()
            pairReview = [ordered]@{
                reviewPath = ''
                reviewSha256 = ''
                visualConsistencyChecked = $false
                factConsistencyChecked = $false
                distinctPrimaryActionsChecked = $false
                passed = $false
            }
        }
        approval = [ordered]@{
            approved = $Approved
            statement = if ($Approved) { 'Confirmed final result' } else { '' }
            approvedAt = if ($Approved) { '2026-07-14T17:05:00+08:00' } else { '' }
        }
        promotion = [ordered]@{
            outputPath = 'outputs/' + $Name + '-final.png'
            outputItems = @()
            promoted = $false
            promotedAt = ''
            promotedBy = ''
        }
    }

    $manifest | ConvertTo-Json -Depth 12 | Set-Content -Encoding UTF8 -LiteralPath $manifestPath
    return $manifestPath
}

function Add-CandidateEvidence {
    param([string]$ManifestPath)
    $manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $ManifestPath | ConvertFrom-Json
    $candidateFull = Join-Path $sandboxFull ($manifest.candidate.path -replace '/', '\')
    $candidateParent = Split-Path -Parent $candidateFull
    New-Item -ItemType Directory -Force -Path $candidateParent | Out-Null
    $png = [Convert]::FromBase64String('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=')
    [System.IO.File]::WriteAllBytes($candidateFull, $png)

    if ($manifest.candidate.acceptancePath) {
        $acceptanceFull = Join-Path $sandboxFull ($manifest.candidate.acceptancePath -replace '/', '\')
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $acceptanceFull) | Out-Null
        [System.IO.File]::WriteAllText($acceptanceFull, 'Synthetic acceptance evidence')
    }

    $manifest.candidate.sha256 = (Get-FileHash -LiteralPath $candidateFull -Algorithm SHA256).Hash
    $manifest.candidate.bytes = (Get-Item -LiteralPath $candidateFull).Length
    if ($manifest.candidateSet.required -eq $true) {
        $acceptanceHash = (Get-FileHash -LiteralPath $acceptanceFull -Algorithm SHA256).Hash
        $entry = [pscustomobject]@{
            role = [string]$manifest.candidate.role
            path = [string]$manifest.candidate.path
            acceptancePath = [string]$manifest.candidate.acceptancePath
            acceptanceSha256 = $acceptanceHash
            designReviewPath = [string]$manifest.candidate.designReview.reviewPath
            designReviewSha256 = [string]$manifest.candidate.designReview.reviewSha256
            version = [string]$manifest.candidate.version
            sha256 = [string]$manifest.candidate.sha256
            bytes = [int64]$manifest.candidate.bytes
            checkedAt = '2026-07-20T17:00:00+08:00'
            passed = $true
        }
        $remaining = @($manifest.candidateSet.entries | Where-Object { [string]$_.role -ne [string]$manifest.candidate.role })
        $manifest.candidateSet.entries = @($remaining) + @($entry)
    }
    if ($manifest.productPoster.required -eq $true) {
        $manifest.productPoster.productSource.currentBinding.status = 'candidate_verified'
        $manifest.assetTransfer.method = 'clipboard_file_paste'
        $manifest.assetTransfer.clipboardPrepared = $true
        $manifest.assetTransfer.thumbnailVerified = $true
        $manifest.assetTransfer.verifiedAssetName = [System.IO.Path]::GetFileName([string]$manifest.assetTransfer.assetPath)
        $manifest.assetTransfer.verifiedAt = '2026-07-17T17:01:00+08:00'
        $manifest.assetTransfer.status = 'verified'
    }
    $manifest | ConvertTo-Json -Depth 12 | Set-Content -Encoding UTF8 -LiteralPath $ManifestPath
}

function Add-DualCandidateEvidence {
    param([string]$ManifestPath)
    foreach ($role in @('event_notice', 'sales_conversion')) {
        $manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $ManifestPath | ConvertFrom-Json
        $manifest.candidate.role = $role
        $manifest.candidate.path = 'temp/poster-jobs/' + $manifest.jobId + '/' + $role + '-candidate.png'
        $manifest.candidate.acceptancePath = 'temp/poster-jobs/' + $manifest.jobId + '/' + $role + '-acceptance.md'
        $candidateVersion = if ($role -eq 'event_notice') { 'EVENT-V1' } else { 'SALES-V1' }
        $manifest.candidate.version = $candidateVersion
        $manifest.designTranslation.promptBuild.version = $candidateVersion
        $manifest.generation.route.currentVersion = $candidateVersion
        $manifest.generation.route.authorizationVersion = $candidateVersion
        $reviewRelative = 'temp/poster-jobs/' + $manifest.jobId + '/' + $role + '-design-review.md'
        $reviewFull = Join-Path $sandboxFull ($reviewRelative -replace '/', '\')
        [System.IO.File]::WriteAllText($reviewFull, ('Synthetic independent design review for ' + $role))
        $manifest.candidate.designReview.reviewPath = $reviewRelative
        $manifest.candidate.designReview.reviewSha256 = (Get-FileHash -LiteralPath $reviewFull -Algorithm SHA256).Hash
        $manifest | ConvertTo-Json -Depth 15 | Set-Content -Encoding UTF8 -LiteralPath $ManifestPath
        Add-CandidateEvidence -ManifestPath $ManifestPath
    }

    $manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $ManifestPath | ConvertFrom-Json
    $pairReviewRelative = 'temp/poster-jobs/' + $manifest.jobId + '/pair-review.md'
    $pairReviewFull = Join-Path $sandboxFull ($pairReviewRelative -replace '/', '\')
    [System.IO.File]::WriteAllText($pairReviewFull, 'Synthetic pair consistency and distinct-action review.')
    $manifest.candidateSet.pairReview.reviewPath = $pairReviewRelative
    $manifest.candidateSet.pairReview.reviewSha256 = (Get-FileHash -LiteralPath $pairReviewFull -Algorithm SHA256).Hash
    $manifest.candidateSet.pairReview.visualConsistencyChecked = $true
    $manifest.candidateSet.pairReview.factConsistencyChecked = $true
    $manifest.candidateSet.pairReview.distinctPrimaryActionsChecked = $true
    $manifest.candidateSet.pairReview.passed = $true
    $manifest.promotion.outputPath = ''
    $manifest.promotion.outputItems = @(
        [pscustomobject]@{ role = 'event_notice'; candidatePath = [string]$manifest.candidateSet.entries[0].path; outputPath = 'outputs/' + $manifest.jobId + '-event-final.png'; sha256 = [string]$manifest.candidateSet.entries[0].sha256 },
        [pscustomobject]@{ role = 'sales_conversion'; candidatePath = [string]$manifest.candidateSet.entries[1].path; outputPath = 'outputs/' + $manifest.jobId + '-sales-final.png'; sha256 = [string]$manifest.candidateSet.entries[1].sha256 }
    )
    $manifest | ConvertTo-Json -Depth 15 | Set-Content -Encoding UTF8 -LiteralPath $ManifestPath
}

New-Item -ItemType Directory -Force -Path (Join-Path $sandboxFull 'temp'), (Join-Path $sandboxFull 'outputs') | Out-Null

try {
    $missingBrief = Write-Manifest -Name 'missing-brief' -Status 'needs_brief' -BriefConfirmed $false -Missing @('channel')
    $result = Invoke-Gate -Action 'CheckBeforeGenerate' -ManifestPath $missingBrief
    Assert-True ($result.ExitCode -ne 0) 'A vague request must not pass the generation gate.'

    $unconfirmed = Write-Manifest -Name 'unconfirmed' -Status 'awaiting_brief_confirmation' -BriefConfirmed $false
    $result = Invoke-Gate -Action 'CheckBeforeGenerate' -ManifestPath $unconfirmed
    Assert-True ($result.ExitCode -ne 0) 'An unconfirmed brief must not pass the generation gate.'

    $productMissingEvidence = Write-Manifest -Name 'product-missing-evidence' -ProductPoster $true -ProductEvidenceReady $false
    $result = Invoke-Gate -Action 'CheckBeforeGenerate' -ManifestPath $productMissingEvidence
    Assert-True ($result.ExitCode -ne 0) 'A product poster without a verified claim-evidence table must fail before generation.'

    $unauthorizedBuiltIn = Write-Manifest -Name 'unauthorized-built-in' -ProductPoster $true -ProductEvidenceReady $true
    $manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $unauthorizedBuiltIn | ConvertFrom-Json
    $manifest.generation.method = 'Codex built-in image_gen'
    $manifest.generation.route.currentMethod = 'Codex built-in image_gen'
    $manifest.productPoster.productSource.currentBinding.method = 'Codex built-in image_gen'
    $manifest | ConvertTo-Json -Depth 15 | Set-Content -Encoding UTF8 -LiteralPath $unauthorizedBuiltIn
    $result = Invoke-Gate -Action 'CheckBeforeGenerate' -ManifestPath $unauthorizedBuiltIn
    Assert-True ($result.ExitCode -ne 0) 'A built-in generation route without authorization bound to the current job and version must fail.'

    $productWithoutSourceBinding = Write-Manifest -Name 'product-without-source-binding' -ProductPoster $true -ProductEvidenceReady $true
    $manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $productWithoutSourceBinding | ConvertFrom-Json
    $manifest.productPoster.productSource.required = $false
    $manifest | ConvertTo-Json -Depth 15 | Set-Content -Encoding UTF8 -LiteralPath $productWithoutSourceBinding
    $result = Invoke-Gate -Action 'CheckBeforeGenerate' -ManifestPath $productWithoutSourceBinding
    Assert-True ($result.ExitCode -ne 0) 'A product poster without archived source assets and a product identity lock must fail.'

    $globalizedChannelRefusal = Write-Manifest -Name 'globalized-channel-refusal' -ProductPoster $true -ProductEvidenceReady $true
    $manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $globalizedChannelRefusal | ConvertFrom-Json
    $manifest.generation.refusals = @([pscustomobject]@{
        method = 'Codex built-in image_gen'
        version = 'V1'
        category = 'sexual_policy'
        scope = 'global'
        occurredAt = '2026-07-17T16:00:00+08:00'
        originalMessage = 'moderation_blocked'
    })
    $manifest | ConvertTo-Json -Depth 15 | Set-Content -Encoding UTF8 -LiteralPath $globalizedChannelRefusal
    $result = Invoke-Gate -Action 'CheckBeforeGenerate' -ManifestPath $globalizedChannelRefusal
    Assert-True ($result.ExitCode -ne 0) 'A refusal from one channel must not be recorded as a global prohibition.'

    $unconfirmedDirectionFallback = Write-Manifest -Name 'unconfirmed-direction-fallback' -ProductPoster $true -ProductEvidenceReady $true
    $manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $unconfirmedDirectionFallback | ConvertFrom-Json
    $manifest.generation.route.fallback = [pscustomobject]@{
        method = 'mannequin_composite'
        changesConfirmedDirection = $true
        confirmed = $false
        confirmationStatement = ''
        confirmedAt = ''
    }
    $manifest | ConvertTo-Json -Depth 15 | Set-Content -Encoding UTF8 -LiteralPath $unconfirmedDirectionFallback
    $result = Invoke-Gate -Action 'CheckBeforeGenerate' -ManifestPath $unconfirmedDirectionFallback
    Assert-True ($result.ExitCode -ne 0) 'A fallback that changes the confirmed human-model direction must require renewed confirmation.'

    $productMisclassified = Write-Manifest -Name 'product-misclassified' -ProductPoster $true -ProductEvidenceReady $true
    $manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $productMisclassified | ConvertFrom-Json
    $manifest.productPoster.required = $false
    $manifest | ConvertTo-Json -Depth 15 | Set-Content -Encoding UTF8 -LiteralPath $productMisclassified
    $result = Invoke-Gate -Action 'CheckBeforeGenerate' -ManifestPath $productMisclassified
    Assert-True ($result.ExitCode -ne 0) 'A task classified as a product sales poster must not disable the product branch.'

    $vagueBuiltInAuthorization = Write-Manifest -Name 'vague-built-in-authorization' -ProductPoster $true -ProductEvidenceReady $true
    $manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $vagueBuiltInAuthorization | ConvertFrom-Json
    $manifest.generation.route.currentMethod = 'Codex built-in image_gen'
    $manifest.generation.route.authorizationType = 'user_explicit_current_job'
    $manifest.generation.route.authorizationStatement = 'Broad permission to use uploaded materials'
    $manifest.generation.method = 'Codex built-in image_gen'
    $manifest.productPoster.productSource.currentBinding.method = 'Codex built-in image_gen'
    $manifest | ConvertTo-Json -Depth 15 | Set-Content -Encoding UTF8 -LiteralPath $vagueBuiltInAuthorization
    $result = Invoke-Gate -Action 'CheckBeforeGenerate' -ManifestPath $vagueBuiltInAuthorization
    Assert-True ($result.ExitCode -ne 0) 'A vague material-use statement must not count as explicit built-in image generation authorization.'

    $nonCanonicalRefusal = Write-Manifest -Name 'non-canonical-refusal' -ProductPoster $true -ProductEvidenceReady $true
    $manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $nonCanonicalRefusal | ConvertFrom-Json
    $manifest.generation.refusals = @([pscustomobject]@{
        method = 'Codex built-in image_gen'
        version = 'V1'
        category = 'content_policy_alias'
        scope = 'current_channel'
        occurredAt = '2026-07-17T16:00:00+08:00'
        originalMessage = 'moderation_blocked'
    })
    $manifest | ConvertTo-Json -Depth 15 | Set-Content -Encoding UTF8 -LiteralPath $nonCanonicalRefusal
    $result = Invoke-Gate -Action 'CheckBeforeGenerate' -ManifestPath $nonCanonicalRefusal
    Assert-True ($result.ExitCode -ne 0) 'A refusal category must use a canonical value so the retry stop condition cannot be split by aliases.'

    $missingDesignTranslation = Write-Manifest -Name 'missing-design-translation' -ProductPoster $true -ProductEvidenceReady $true
    $manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $missingDesignTranslation | ConvertFrom-Json
    $manifest.PSObject.Properties.Remove('designTranslation')
    $manifest | ConvertTo-Json -Depth 15 | Set-Content -Encoding UTF8 -LiteralPath $missingDesignTranslation
    $result = Invoke-Gate -Action 'CheckBeforeGenerate' -ManifestPath $missingDesignTranslation
    Assert-True ($result.ExitCode -ne 0) 'A poster without prompt-framework provenance, visual-DNA translation, and selected design direction must fail.'

    $highRiskWithoutThree = Write-Manifest -Name 'high-risk-without-three' -ProductPoster $true -ProductEvidenceReady $true
    $manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $highRiskWithoutThree | ConvertFrom-Json
    $manifest.designTranslation.directionSelection.mode = 'direct_confirmed'
    $manifest.designTranslation.directionSelection.options = @($manifest.designTranslation.directionSelection.options[0])
    $manifest | ConvertTo-Json -Depth 15 | Set-Content -Encoding UTF8 -LiteralPath $highRiskWithoutThree
    $result = Invoke-Gate -Action 'CheckBeforeGenerate' -ManifestPath $highRiskWithoutThree
    Assert-True ($result.ExitCode -ne 0) 'A reference-sensitive product poster must not skip three-direction preselection.'

    $referenceWithoutEvidence = Write-Manifest -Name 'reference-without-evidence' -ProductPoster $true -ProductEvidenceReady $true
    $manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $referenceWithoutEvidence | ConvertFrom-Json
    $manifest.designTranslation.visualDNA.referenceAssets = @()
    $manifest | ConvertTo-Json -Depth 15 | Set-Content -Encoding UTF8 -LiteralPath $referenceWithoutEvidence
    $result = Invoke-Gate -Action 'CheckBeforeGenerate' -ManifestPath $referenceWithoutEvidence
    Assert-True ($result.ExitCode -ne 0) 'Reference visual DNA must be bound to archived, hash-verified reference files.'

    $frameworkBypassed = Write-Manifest -Name 'framework-bypassed' -ProductPoster $true -ProductEvidenceReady $true
    $manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $frameworkBypassed | ConvertFrom-Json
    $manifest.designTranslation.promptBuild.frameworkApplied = $false
    $manifest | ConvertTo-Json -Depth 15 | Set-Content -Encoding UTF8 -LiteralPath $frameworkBypassed
    $result = Invoke-Gate -Action 'CheckBeforeGenerate' -ManifestPath $frameworkBypassed
    Assert-True ($result.ExitCode -ne 0) 'A hand-written prompt that bypasses the confirmed poster framework must fail.'

    $unknownPlatform = Write-Manifest -Name 'unknown-platform' -Platform 'unknown_social'
    $result = Invoke-Gate -Action 'CheckBeforeGenerate' -ManifestPath $unknownPlatform
    Assert-True ($result.ExitCode -ne 0) 'An unverified platform profile must fail before generation.'

    $intimateBatch = Write-Manifest -Name 'intimate-batch' -ProductPoster $true -ProductEvidenceReady $true -Platform 'xiaohongshu' -CategoryId 'intimate_apparel_adult' -HumanSubject 'adult' -SafetyProfile 'adult_nonsexual_retail_v1' -RequestedOutputs 6 -OutputsPerRequest 6
    $result = Invoke-Gate -Action 'CheckBeforeGenerate' -ManifestPath $intimateBatch
    Assert-True ($result.ExitCode -ne 0) 'An adult intimate-apparel task must not request six images in one generation request.'
    $normalizedIntimateBatchOutput = ($result.Output -replace '\s+', ' ')
    Assert-True ($normalizedIntimateBatchOutput.Contains('only one image per request')) ('The intimate-apparel batch failure must explain the single-image request rule. Output: ' + $result.Output)

    $intimateWrongSafety = Write-Manifest -Name 'intimate-wrong-safety' -ProductPoster $true -ProductEvidenceReady $true -Platform 'xiaohongshu' -CategoryId 'intimate_apparel_adult' -HumanSubject 'adult' -SafetyProfile 'general_commercial_v1' -RequestedOutputs 6
    $result = Invoke-Gate -Action 'CheckBeforeGenerate' -ManifestPath $intimateWrongSafety
    Assert-True ($result.ExitCode -ne 0) 'Adult intimate apparel must use the dedicated nonsexual retail safety profile.'

    $minorIntimate = Write-Manifest -Name 'minor-intimate' -ProductPoster $true -ProductEvidenceReady $true -CategoryId 'intimate_apparel_adult' -HumanSubject 'child' -SafetyProfile 'adult_nonsexual_retail_v1'
    $result = Invoke-Gate -Action 'CheckBeforeGenerate' -ManifestPath $minorIntimate
    Assert-True ($result.ExitCode -ne 0) 'An intimate-apparel human subject must be explicitly adult.'

    $toyWrongChildSafety = Write-Manifest -Name 'toy-wrong-child-safety' -ProductPoster $true -ProductEvidenceReady $true -CategoryId 'toys' -HumanSubject 'child' -SafetyProfile 'general_product_v1'
    $result = Invoke-Gate -Action 'CheckBeforeGenerate' -ManifestPath $toyWrongChildSafety
    Assert-True ($result.ExitCode -ne 0) 'A toy task with child subjects must use the child-safe product profile.'

    $seriesWithoutAnchor = Write-Manifest -Name 'series-without-anchor' -RequestedOutputs 6
    $manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $seriesWithoutAnchor | ConvertFrom-Json
    $manifest.generation.series.currentIndex = 2
    $manifest.generation.series.anchorStatus = 'pending'
    $manifest | ConvertTo-Json -Depth 15 | Set-Content -Encoding UTF8 -LiteralPath $seriesWithoutAnchor
    $result = Invoke-Gate -Action 'CheckBeforeGenerate' -ManifestPath $seriesWithoutAnchor
    Assert-True ($result.ExitCode -ne 0) 'Later series outputs must not start before the first style anchor is approved.'

    $intimateSequentialReady = Write-Manifest -Name 'intimate-sequential-ready' -ProductPoster $true -ProductEvidenceReady $true -Platform 'xiaohongshu' -CategoryId 'intimate_apparel_adult' -HumanSubject 'adult' -SafetyProfile 'adult_nonsexual_retail_v1' -RequestedOutputs 6 -OutputsPerRequest 1
    $result = Invoke-Gate -Action 'CheckBeforeGenerate' -ManifestPath $intimateSequentialReady
    Assert-True ($result.ExitCode -eq 0) ('A confirmed adult retail task using sequential single-image generation should pass: ' + $result.Output)

    $maleIntimateReady = Write-Manifest -Name 'male-intimate-sequential-ready' -ProductPoster $true -ProductEvidenceReady $true -CategoryId 'intimate_apparel_adult' -HumanSubject 'adult' -SafetyProfile 'adult_nonsexual_retail_v1'
    $result = Invoke-Gate -Action 'CheckBeforeGenerate' -ManifestPath $maleIntimateReady
    Assert-True ($result.ExitCode -eq 0) ('Adult male and female intimate apparel must share the same nonsexual retail adapter: ' + $result.Output)

    $fashionReady = Write-Manifest -Name 'fashion-ready' -ProductPoster $true -ProductEvidenceReady $true -CategoryId 'fashion_apparel' -HumanSubject 'adult' -SafetyProfile 'general_commercial_v1'
    $result = Invoke-Gate -Action 'CheckBeforeGenerate' -ManifestPath $fashionReady
    Assert-True ($result.ExitCode -eq 0) ('A normal adult fashion-apparel route should pass: ' + $result.Output)

    $electronicsReady = Write-Manifest -Name 'electronics-ready' -ProductPoster $true -ProductEvidenceReady $true -CategoryId 'electronics' -HumanSubject 'none' -SafetyProfile 'general_product_v1'
    $result = Invoke-Gate -Action 'CheckBeforeGenerate' -ManifestPath $electronicsReady
    Assert-True ($result.ExitCode -eq 0) ('A verified electronics route should pass: ' + $result.Output)

    $toyReady = Write-Manifest -Name 'toy-child-safe-ready' -ProductPoster $true -ProductEvidenceReady $true -CategoryId 'toys' -HumanSubject 'child' -SafetyProfile 'child_safe_product_v1'
    $result = Invoke-Gate -Action 'CheckBeforeGenerate' -ManifestPath $toyReady
    Assert-True ($result.ExitCode -eq 0) ('A toy route with the child-safe profile should pass: ' + $result.Output)

    $momentsReady = Write-Manifest -Name 'wechat-moments-ready' -Platform 'wechat_moments'
    $result = Invoke-Gate -Action 'CheckBeforeGenerate' -ManifestPath $momentsReady
    Assert-True ($result.ExitCode -eq 0) ('A WeChat Moments platform route should pass: ' + $result.Output)

    $wechatEventReady = Write-Manifest -Name 'wechat-event-ready' -Platform 'wechat_chat' -PrimaryIntent 'event_notice'
    $result = Invoke-Gate -Action 'CheckBeforeGenerate' -ManifestPath $wechatEventReady
    Assert-True ($result.ExitCode -eq 0) ('A WeChat chat event-notice route should pass: ' + $result.Output)

    $wechatSalesReady = Write-Manifest -Name 'wechat-sales-ready' -Platform 'wechat_chat' -PrimaryIntent 'sales_conversion' -ProductPoster $true -ProductEvidenceReady $true
    $result = Invoke-Gate -Action 'CheckBeforeGenerate' -ManifestPath $wechatSalesReady
    Assert-True ($result.ExitCode -eq 0) ('A WeChat chat sales-conversion route should pass: ' + $result.Output)

    $wechatDualNotSplit = Write-Manifest -Name 'wechat-dual-not-split' -Platform 'wechat_chat' -PrimaryIntent 'event_notice' -SecondaryIntent 'sales_conversion' -SplitRequired $false
    $result = Invoke-Gate -Action 'CheckBeforeGenerate' -ManifestPath $wechatDualNotSplit
    Assert-True ($result.ExitCode -ne 0) 'Two independent WeChat chat actions must not be placed in one poster.'

    $wechatDualSplit = Write-Manifest -Name 'wechat-dual-split' -Platform 'wechat_chat' -PrimaryIntent 'event_notice' -SecondaryIntent 'sales_conversion' -SplitRequired $true -RequestedOutputs 2
    $result = Invoke-Gate -Action 'CheckBeforeGenerate' -ManifestPath $wechatDualSplit
    Assert-True ($result.ExitCode -eq 0) ('A verified WeChat dual-intent pair should pass: ' + $result.Output)

    $unknownIntent = Write-Manifest -Name 'unknown-intent' -Platform 'wechat_chat' -PrimaryIntent 'unknown_intent'
    $result = Invoke-Gate -Action 'CheckBeforeGenerate' -ManifestPath $unknownIntent
    Assert-True ($result.ExitCode -ne 0) 'An unknown campaign intent must fail.'

    $duplicateIntent = Write-Manifest -Name 'duplicate-intent' -Platform 'wechat_chat' -PrimaryIntent 'event_notice' -SecondaryIntent 'event_notice' -SplitRequired $true -RequestedOutputs 2
    $result = Invoke-Gate -Action 'CheckBeforeGenerate' -ManifestPath $duplicateIntent
    Assert-True ($result.ExitCode -ne 0) 'Primary and secondary campaign intents must be different.'

    $dualMissingRole = Write-Manifest -Name 'dual-missing-role' -Platform 'wechat_chat' -PrimaryIntent 'event_notice' -SecondaryIntent 'sales_conversion' -SplitRequired $true -RequestedOutputs 2
    $manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $dualMissingRole | ConvertFrom-Json
    $manifest.campaignIntent.candidateRoles = @('event_notice')
    $manifest | ConvertTo-Json -Depth 15 | Set-Content -Encoding UTF8 -LiteralPath $dualMissingRole
    $result = Invoke-Gate -Action 'CheckBeforeGenerate' -ManifestPath $dualMissingRole
    Assert-True ($result.ExitCode -ne 0) 'A dual-intent pair must record both candidate roles.'

    $momentsDualPair = Write-Manifest -Name 'moments-dual-pair' -Platform 'wechat_moments' -PrimaryIntent 'event_notice' -SecondaryIntent 'sales_conversion' -SplitRequired $true -RequestedOutputs 2
    $result = Invoke-Gate -Action 'CheckBeforeGenerate' -ManifestPath $momentsDualPair
    Assert-True ($result.ExitCode -ne 0) 'WeChat Moments must not masquerade as the WeChat chat dual-intent pair.'

    $productReady = Write-Manifest -Name 'product-ready' -ProductPoster $true -ProductEvidenceReady $true
    $result = Invoke-Gate -Action 'CheckBeforeGenerate' -ManifestPath $productReady
    Assert-True ($result.ExitCode -eq 0) ('A product poster with verified claim evidence should pass generation gate: ' + $result.Output)

    $ready = Write-Manifest -Name 'ready'
    $result = Invoke-Gate -Action 'CheckBeforeGenerate' -ManifestPath $ready
    Assert-True ($result.ExitCode -eq 0) ('A complete confirmed brief should pass: ' + $result.Output)

    $defaultRootManifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $ready | ConvertFrom-Json
    $defaultPromptSource = Join-Path $sandboxFull ($defaultRootManifest.designTranslation.promptBuild.path -replace '/', '\')
    $defaultPromptDir = Join-Path $projectRoot ('temp\poster-jobs\_gate-default-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $defaultPromptDir | Out-Null
    $defaultRootArtifacts += $defaultPromptDir
    $defaultPromptFull = Join-Path $defaultPromptDir 'final-V1.txt'
    Copy-Item -LiteralPath $defaultPromptSource -Destination $defaultPromptFull
    $defaultRootManifest.designTranslation.promptBuild.path = $defaultPromptFull.Substring($projectRoot.Length).TrimStart('\', '/').Replace('\', '/')
    $defaultRootManifest | ConvertTo-Json -Depth 15 | Set-Content -Encoding UTF8 -LiteralPath $ready
    $result = Invoke-GateWithDefaultProjectRoot -Action 'CheckBeforeGenerate' -ManifestPath $ready
    Assert-True ($result.ExitCode -eq 0) ('The documented command must resolve ProjectRoot automatically in Windows PowerShell 5.1: ' + $result.Output)

    $invalidOrigin = Write-Manifest -Name 'invalid-origin' -OriginThreadMode 'unknown'
    $result = Invoke-Gate -Action 'CheckBeforeGenerate' -ManifestPath $invalidOrigin
    Assert-True ($result.ExitCode -ne 0) 'An unknown origin thread mode must fail.'

    $escapeCandidate = Write-Manifest -Name 'escape-candidate' -Status 'candidate_ready' -CandidateRelativePath '../outside.png'
    $result = Invoke-Gate -Action 'CheckCandidate' -ManifestPath $escapeCandidate
    Assert-True ($result.ExitCode -ne 0) 'A candidate path that escapes the project must fail.'

    $wrongDirectory = Write-Manifest -Name 'wrong-directory' -Status 'candidate_ready' -CandidateRelativePath 'outputs/wrong.png' -Approved $true
    Add-CandidateEvidence -ManifestPath $wrongDirectory
    $result = Invoke-Gate -Action 'CheckCandidate' -ManifestPath $wrongDirectory
    Assert-True ($result.ExitCode -ne 0) 'A candidate in outputs must fail candidate validation.'

    $noSource = Write-Manifest -Name 'no-source' -Status 'candidate_ready' -IncludeSource $false
    Add-CandidateEvidence -ManifestPath $noSource
    $result = Invoke-Gate -Action 'CheckCandidate' -ManifestPath $noSource
    Assert-True ($result.ExitCode -ne 0) 'A candidate without provenance must fail.'

    $noAcceptance = Write-Manifest -Name 'no-acceptance' -Status 'candidate_ready' -IncludeAcceptance $false
    Add-CandidateEvidence -ManifestPath $noAcceptance
    $result = Invoke-Gate -Action 'CheckCandidate' -ManifestPath $noAcceptance
    Assert-True ($result.ExitCode -ne 0) 'A candidate without acceptance evidence must fail.'

    $badQuality = Write-Manifest -Name 'bad-quality' -Status 'candidate_ready' -QualityPassed $false
    Add-CandidateEvidence -ManifestPath $badQuality
    $result = Invoke-Gate -Action 'CheckCandidate' -ManifestPath $badQuality
    Assert-True ($result.ExitCode -ne 0) 'A candidate with incomplete quality checks must fail.'

    $badAesthetic = Write-Manifest -Name 'bad-aesthetic' -Status 'candidate_ready'
    Add-CandidateEvidence -ManifestPath $badAesthetic
    $manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $badAesthetic | ConvertFrom-Json
    $manifest.candidate.designReview.visualDNAAligned = $false
    $manifest.candidate.designReview.passed = $false
    $manifest | ConvertTo-Json -Depth 15 | Set-Content -Encoding UTF8 -LiteralPath $badAesthetic
    $result = Invoke-Gate -Action 'CheckCandidate' -ManifestPath $badAesthetic
    Assert-True ($result.ExitCode -ne 0) 'A technically valid but visually off-direction AI poster must fail candidate validation.'

    $productWrongMapping = Write-Manifest -Name 'product-wrong-mapping' -Status 'candidate_ready' -ProductPoster $true -ProductEvidenceReady $true -ProductMappingPassed $false
    Add-CandidateEvidence -ManifestPath $productWrongMapping
    $result = Invoke-Gate -Action 'CheckCandidate' -ManifestPath $productWrongMapping
    Assert-True ($result.ExitCode -ne 0) 'A product poster with mismatched claim text and feature visual must fail candidate validation.'

    $productMapped = Write-Manifest -Name 'product-mapped' -Status 'candidate_ready' -ProductPoster $true -ProductEvidenceReady $true -ProductMappingPassed $true
    Add-CandidateEvidence -ManifestPath $productMapped
    $result = Invoke-Gate -Action 'CheckCandidate' -ManifestPath $productMapped
    Assert-True ($result.ExitCode -eq 0) ('A product poster with verified claim-to-visual mapping should pass candidate validation: ' + $result.Output)

    $badHash = Write-Manifest -Name 'bad-hash' -Status 'candidate_ready'
    Add-CandidateEvidence -ManifestPath $badHash
    $badHashManifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $badHash | ConvertFrom-Json
    $badHashManifest.candidate.sha256 = ('0' * 64)
    $badHashManifest | ConvertTo-Json -Depth 12 | Set-Content -Encoding UTF8 -LiteralPath $badHash
    $result = Invoke-Gate -Action 'CheckCandidate' -ManifestPath $badHash
    Assert-True ($result.ExitCode -ne 0) 'A candidate with a mismatched hash must fail.'

    $dualWithoutLedger = Write-Manifest -Name 'dual-without-ledger' -Status 'candidate_ready' -Platform 'wechat_chat' -PrimaryIntent 'event_notice' -SecondaryIntent 'sales_conversion' -SplitRequired $true -RequestedOutputs 2
    Add-CandidateEvidence -ManifestPath $dualWithoutLedger
    $manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $dualWithoutLedger | ConvertFrom-Json
    $manifest.candidateSet.required = $false
    $manifest.candidateSet.entries = @()
    $manifest | ConvertTo-Json -Depth 15 | Set-Content -Encoding UTF8 -LiteralPath $dualWithoutLedger
    $result = Invoke-Gate -Action 'CheckCandidate' -ManifestPath $dualWithoutLedger
    Assert-True ($result.ExitCode -ne 0) 'A dual-intent task without an independent candidate ledger must fail.'

    $dualIncompletePair = Write-Manifest -Name 'dual-incomplete-pair' -Status 'approved' -Approved $true -Platform 'wechat_chat' -PrimaryIntent 'event_notice' -SecondaryIntent 'sales_conversion' -SplitRequired $true -RequestedOutputs 2
    Add-CandidateEvidence -ManifestPath $dualIncompletePair
    $result = Invoke-Gate -Action 'CheckBeforePromote' -ManifestPath $dualIncompletePair -ActorMode 'main'
    Assert-True ($result.ExitCode -ne 0) 'A dual-intent task with only one candidate and no pair review must not be promoted.'

    $notApproved = Write-Manifest -Name 'not-approved' -Status 'awaiting_final_approval'
    Add-CandidateEvidence -ManifestPath $notApproved
    $result = Invoke-Gate -Action 'CheckBeforePromote' -ManifestPath $notApproved -ActorMode 'main'
    Assert-True ($result.ExitCode -ne 0) 'Promotion without user approval must fail.'

    $testActor = Write-Manifest -Name 'test-actor' -Status 'approved' -Approved $true
    Add-CandidateEvidence -ManifestPath $testActor
    $result = Invoke-Gate -Action 'Promote' -ManifestPath $testActor -ActorMode 'test'
    Assert-True ($result.ExitCode -ne 0) 'A test-thread actor must not promote.'

    $escapeOutput = Write-Manifest -Name 'escape-output' -Status 'approved' -Approved $true
    Add-CandidateEvidence -ManifestPath $escapeOutput
    $escapeOutputManifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $escapeOutput | ConvertFrom-Json
    $escapeOutputManifest.promotion.outputPath = '../outside-final.png'
    $escapeOutputManifest | ConvertTo-Json -Depth 12 | Set-Content -Encoding UTF8 -LiteralPath $escapeOutput
    $result = Invoke-Gate -Action 'CheckBeforePromote' -ManifestPath $escapeOutput -ActorMode 'main'
    Assert-True ($result.ExitCode -ne 0) 'An output path that escapes the project must fail.'

    $approved = Write-Manifest -Name 'approved' -Status 'approved' -Approved $true
    Add-CandidateEvidence -ManifestPath $approved
    $sourceHash = (Get-Content -Raw -Encoding UTF8 -LiteralPath $approved | ConvertFrom-Json).candidate.sha256
    $result = Invoke-Gate -Action 'Promote' -ManifestPath $approved -ActorMode 'main'
    Assert-True ($result.ExitCode -eq 0) ('A complete approved job should promote: ' + $result.Output)

    $approvedState = Get-Content -Raw -Encoding UTF8 -LiteralPath $approved | ConvertFrom-Json
    $promotedFull = Join-Path $sandboxFull ($approvedState.promotion.outputPath -replace '/', '\')
    $candidateFull = Join-Path $sandboxFull ($approvedState.candidate.path -replace '/', '\')
    Assert-True (Test-Path -LiteralPath $promotedFull -PathType Leaf) 'Promoted output is missing.'
    Assert-True (Test-Path -LiteralPath $candidateFull -PathType Leaf) 'Promotion must preserve the temp candidate.'
    Assert-True ((Get-FileHash -LiteralPath $promotedFull -Algorithm SHA256).Hash -eq $sourceHash) 'Promoted hash differs from candidate hash.'
    Assert-True ($approvedState.status -eq 'promoted') 'Manifest status was not updated to promoted.'

    $receiptFull = Join-Path (Split-Path -Parent $approved) 'promotion-receipt.json'
    Assert-True (Test-Path -LiteralPath $receiptFull -PathType Leaf) 'Promote must create a gate-owned promotion receipt.'
    $receiptState = Get-Content -Raw -Encoding UTF8 -LiteralPath $receiptFull | ConvertFrom-Json
    $receiptEvidence = @($receiptState.evidence)
    Assert-True ($receiptEvidence.Count -gt 0) 'Promotion receipt must bind every external gate evidence file.'
    Assert-True (@($receiptEvidence | Where-Object { [string]$_.kind -eq 'acceptance' -and [string]$_.role -eq [string]$approvedState.candidate.role }).Count -eq 1) 'Promotion receipt must bind the single-poster acceptance evidence.'
    foreach ($evidence in $receiptEvidence) {
        Assert-True (-not [System.IO.Path]::IsPathRooted([string]$evidence.path)) 'Receipt evidence paths must be project-relative.'
        Assert-True ([int64]$evidence.bytes -gt 0) 'Receipt evidence must record a positive byte length.'
        Assert-True ([string]$evidence.sha256 -match '^[A-Fa-f0-9]{64}$') 'Receipt evidence must record SHA-256.'
        Assert-True (-not [string]::IsNullOrWhiteSpace([string]$evidence.kind)) 'Receipt evidence must record kind.'
        Assert-True (-not [string]::IsNullOrWhiteSpace([string]$evidence.role)) 'Receipt evidence must record role.'
    }
    $result = Invoke-Gate -Action 'VerifyPromoted' -ManifestPath $approved -ActorMode 'main'
    Assert-True ($result.ExitCode -eq 0) ('VerifyPromoted must accept the unchanged gate-promoted poster: ' + $result.Output)
    $verification = $result.Output | ConvertFrom-Json
    Assert-True ($verification.verified -eq $true) 'VerifyPromoted must return a machine-readable verified descriptor.'
    Assert-True ($verification.gateKind -eq 'promotional-poster') 'VerifyPromoted returned the wrong gate kind.'
    Assert-True (@($verification.outputs).Count -eq 1) 'VerifyPromoted must describe every promoted poster output.'

    $acceptanceFull = Join-Path $sandboxFull ($approvedState.candidate.acceptancePath -replace '/', '\')
    $acceptanceBytes = [System.IO.File]::ReadAllBytes($acceptanceFull)
    [System.IO.File]::WriteAllText($acceptanceFull, 'Tampered but still non-empty acceptance evidence.')
    $result = Invoke-Gate -Action 'VerifyPromoted' -ManifestPath $approved -ActorMode 'main'
    Assert-True ($result.ExitCode -ne 0 -and $result.Output.Contains('evidence')) 'VerifyPromoted must reject non-empty acceptance evidence whose bytes changed after promotion.'
    [System.IO.File]::WriteAllBytes($acceptanceFull, $acceptanceBytes)

    $designReviewFull = Join-Path $sandboxFull ($approvedState.candidate.designReview.reviewPath -replace '/', '\')
    $designReviewBytes = [System.IO.File]::ReadAllBytes($designReviewFull)
    Remove-Item -LiteralPath $designReviewFull -Force
    $result = Invoke-Gate -Action 'VerifyPromoted' -ManifestPath $approved -ActorMode 'main'
    Assert-True ($result.ExitCode -ne 0 -and $result.Output.Contains('design review')) 'VerifyPromoted must reject a promoted poster whose design-review evidence is missing.'
    [System.IO.File]::WriteAllBytes($designReviewFull, $designReviewBytes)

    Remove-Item -LiteralPath $acceptanceFull -Force
    $result = Invoke-Gate -Action 'VerifyPromoted' -ManifestPath $approved -ActorMode 'main'
    Assert-True ($result.ExitCode -ne 0 -and $result.Output.Contains('Acceptance evidence')) 'VerifyPromoted must reject a promoted poster whose acceptance evidence is missing.'
    [System.IO.File]::WriteAllBytes($acceptanceFull, $acceptanceBytes)

    Remove-Item -LiteralPath $receiptFull -Force
    $result = Invoke-Gate -Action 'VerifyPromoted' -ManifestPath $approved -ActorMode 'main'
    Assert-True ($result.ExitCode -ne 0) 'A fully populated promoted manifest without the gate-owned receipt must be rejected.'

    $result = Invoke-Gate -Action 'Promote' -ManifestPath $approved -ActorMode 'main'
    Assert-True ($result.ExitCode -ne 0) 'A second promotion must refuse to overwrite an existing output.'

    $dualApproved = Write-Manifest -Name 'dual-approved' -Status 'approved' -Approved $true -Platform 'wechat_chat' -PrimaryIntent 'event_notice' -SecondaryIntent 'sales_conversion' -SplitRequired $true -RequestedOutputs 2
    Add-DualCandidateEvidence -ManifestPath $dualApproved
    $result = Invoke-Gate -Action 'Promote' -ManifestPath $dualApproved -ActorMode 'main'
    Assert-True ($result.ExitCode -eq 0) ('A reviewed dual-intent pair should promote both outputs atomically: ' + $result.Output)
    $dualState = Get-Content -Raw -Encoding UTF8 -LiteralPath $dualApproved | ConvertFrom-Json
    Assert-True ($dualState.status -eq 'promoted') 'Dual-pair manifest status was not updated to promoted.'
    Assert-True (@($dualState.promotion.outputItems).Count -eq 2) 'Dual-pair promotion must retain two output records.'
    foreach ($item in @($dualState.promotion.outputItems)) {
        $outputFull = Join-Path $sandboxFull ($item.outputPath -replace '/', '\')
        Assert-True (Test-Path -LiteralPath $outputFull -PathType Leaf) ('Dual-pair promoted output is missing: ' + $item.role)
        Assert-True ((Get-FileHash -LiteralPath $outputFull -Algorithm SHA256).Hash -eq [string]$item.sha256) ('Dual-pair output hash differs: ' + $item.role)
    }

    $dualReceiptFull = Join-Path (Split-Path -Parent $dualApproved) 'promotion-receipt.json'
    $dualReceipt = Get-Content -Raw -Encoding UTF8 -LiteralPath $dualReceiptFull | ConvertFrom-Json
    Assert-True (@($dualReceipt.evidence | Where-Object { [string]$_.kind -eq 'pair_review' -and [string]$_.role -eq 'dual_intent_pair' }).Count -eq 1) 'Dual-pair receipt must bind pair-review evidence.'
    foreach ($role in @('event_notice', 'sales_conversion')) {
        Assert-True (@($dualReceipt.evidence | Where-Object { [string]$_.kind -eq 'acceptance' -and [string]$_.role -eq $role }).Count -eq 1) ("Dual-pair receipt must bind acceptance evidence: $role")
        Assert-True (@($dualReceipt.evidence | Where-Object { [string]$_.kind -eq 'design_review' -and [string]$_.role -eq $role }).Count -eq 1) ("Dual-pair receipt must bind design-review evidence: $role")
    }

    $concurrent = Write-Manifest -Name 'concurrent-promote' -Status 'approved' -Approved $true
    Add-CandidateEvidence -ManifestPath $concurrent
    $concurrentState = Get-Content -Raw -Encoding UTF8 -LiteralPath $concurrent | ConvertFrom-Json
    $concurrentCandidate = Join-Path $sandboxFull ($concurrentState.candidate.path -replace '/', '\')
    $largeCandidate = [System.IO.File]::Open($concurrentCandidate, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    try { $largeCandidate.SetLength(128 * 1024 * 1024) }
    finally { $largeCandidate.Dispose() }
    $concurrentState.candidate.sha256 = (Get-FileHash -LiteralPath $concurrentCandidate -Algorithm SHA256).Hash
    $concurrentState.candidate.bytes = (Get-Item -LiteralPath $concurrentCandidate).Length
    $concurrentState | ConvertTo-Json -Depth 15 | Set-Content -Encoding UTF8 -LiteralPath $concurrent

    $barrierRoot = Join-Path (Split-Path -Parent $concurrent) 'concurrency-barrier'
    New-Item -ItemType Directory -Force -Path $barrierRoot | Out-Null
    $workerPath = Join-Path $barrierRoot 'promote-worker.ps1'
    @'
param([string]$WorkerId,[string]$GatePath,[string]$ProjectRoot,[string]$ManifestPath,[string]$BarrierRoot)
$ErrorActionPreference = 'Stop'
[System.IO.File]::WriteAllText((Join-Path $BarrierRoot ('ready-' + $WorkerId)), 'ready')
$deadline = [DateTime]::UtcNow.AddSeconds(10)
while (-not (Test-Path -LiteralPath (Join-Path $BarrierRoot ('go-' + $WorkerId)) -PathType Leaf)) {
    if ([DateTime]::UtcNow -ge $deadline) { throw 'Barrier timed out.' }
    Start-Sleep -Milliseconds 10
}
& $GatePath -Action Promote -ProjectRoot $ProjectRoot -ManifestPath $ManifestPath -ActorMode main
'@ | Set-Content -Encoding UTF8 -LiteralPath $workerPath
    $workerOne = Start-ConcurrentGateWorker -WorkerPath $workerPath -WorkerId 'one' -ManifestPath $concurrent -BarrierRoot $barrierRoot
    $workerTwo = Start-ConcurrentGateWorker -WorkerPath $workerPath -WorkerId 'two' -ManifestPath $concurrent -BarrierRoot $barrierRoot
    Wait-ForPaths -Paths @((Join-Path $barrierRoot 'ready-one'), (Join-Path $barrierRoot 'ready-two'))
    [System.IO.File]::WriteAllText((Join-Path $barrierRoot 'go-one'), 'go')
    $ownerPath = Join-Path (Split-Path -Parent $concurrent) '.promotion.lock\owner.json'
    $ownerDeadline = [DateTime]::UtcNow.AddSeconds(5)
    while (-not (Test-Path -LiteralPath $ownerPath -PathType Leaf) -and [DateTime]::UtcNow -lt $ownerDeadline) { Start-Sleep -Milliseconds 10 }
    $ownerObserved = Test-Path -LiteralPath $ownerPath -PathType Leaf
    if ($ownerObserved) {
        $observedOwner = Get-Content -Raw -Encoding UTF8 -LiteralPath $ownerPath | ConvertFrom-Json
        $ownerObserved = ([string]$observedOwner.nonce -match '^[a-f0-9]{32}$' -and [int]$observedOwner.pid -gt 0)
    }
    [System.IO.File]::WriteAllText((Join-Path $barrierRoot 'go-two'), 'go')
    Assert-True ($workerOne.WaitForExit(20000)) 'First concurrent Promote worker did not exit in time.'
    Assert-True ($workerTwo.WaitForExit(20000)) 'Second concurrent Promote worker did not exit in time.'
    $concurrentResults = @(
        [pscustomobject]@{ ExitCode = $workerOne.ExitCode; Output = $workerOne.StandardOutput.ReadToEnd(); Error = $workerOne.StandardError.ReadToEnd() },
        [pscustomobject]@{ ExitCode = $workerTwo.ExitCode; Output = $workerTwo.StandardOutput.ReadToEnd(); Error = $workerTwo.StandardError.ReadToEnd() }
    )
    Assert-True $ownerObserved 'Concurrent Promote must publish a task-level owner nonce lock before preflight and keep it through the transaction.'
    Assert-True (@($concurrentResults | Where-Object { $_.ExitCode -eq 0 }).Count -eq 1) ('Exactly one concurrent Promote must succeed: ' + ($concurrentResults | ConvertTo-Json -Compress))
    $concurrentFinal = Get-Content -Raw -Encoding UTF8 -LiteralPath $concurrent | ConvertFrom-Json
    Assert-True ([string]$concurrentFinal.status -eq 'promoted' -and $concurrentFinal.promotion.promoted -eq $true) 'Concurrent Promote must leave the winning promoted manifest intact.'
    $concurrentOutput = Join-Path $sandboxFull ($concurrentFinal.promotion.outputPath -replace '/', '\')
    Assert-True (Test-Path -LiteralPath $concurrentOutput -PathType Leaf) 'Concurrent Promote loser must not delete the winning output.'
    Assert-True ((Get-FileHash -LiteralPath $concurrentOutput -Algorithm SHA256).Hash -eq [string]$concurrentFinal.candidate.sha256) 'Concurrent Promote output hash must match the winning manifest.'
    Assert-True (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $concurrent) 'promotion-receipt.json') -PathType Leaf) 'Concurrent Promote loser must not delete the winning receipt.'
    $result = Invoke-Gate -Action 'VerifyPromoted' -ManifestPath $concurrent -ActorMode 'main'
    Assert-True ($result.ExitCode -eq 0) ('Concurrent Promote final state must pass VerifyPromoted: ' + $result.Output)
    Assert-True (-not (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $concurrent) '.promotion.lock'))) 'Concurrent Promote must release its task lock.'
    Assert-True (@(Get-ChildItem -LiteralPath (Split-Path -Parent $concurrent) -Force | Where-Object { $_.Name -like '.promotion.lock.*' }).Count -eq 0) 'Concurrent Promote must not leave staging or isolation lock artifacts.'

    $staleRecovery = Write-Manifest -Name 'stale-lock-recovery' -Status 'approved' -Approved $true
    Add-CandidateEvidence -ManifestPath $staleRecovery
    $staleLockPath = Join-Path (Split-Path -Parent $staleRecovery) '.promotion.lock'
    New-Item -ItemType Directory -Path $staleLockPath | Out-Null
    [ordered]@{
        schemaVersion = '1.0'; nonce = 'a' * 32; pid = 2147483646
        processStartUtcTicks = 1; acquiredAt = [DateTimeOffset]::UtcNow.AddMinutes(-5).ToString('o')
    } | ConvertTo-Json -Compress | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $staleLockPath 'owner.json')
    $result = Invoke-Gate -Action 'Promote' -ManifestPath $staleRecovery -ActorMode 'main'
    Assert-True ($result.ExitCode -eq 0) ('A valid stale lock owned by a dead process must be atomically isolated and recovered: ' + $result.Output)
    $result = Invoke-Gate -Action 'VerifyPromoted' -ManifestPath $staleRecovery -ActorMode 'main'
    Assert-True ($result.ExitCode -eq 0) ('Stale-lock recovery must leave a complete verifiable promotion: ' + $result.Output)
    Assert-True (@(Get-ChildItem -LiteralPath (Split-Path -Parent $staleRecovery) -Force | Where-Object { $_.Name -like '.promotion.lock*' }).Count -eq 0) 'Stale-lock recovery must remove only its isolated old lock and release the new lock.'

    $productApproved = Write-Manifest -Name 'product-approved-evidence' -Status 'approved' -Approved $true -ProductPoster $true
    Add-CandidateEvidence -ManifestPath $productApproved
    $result = Invoke-Gate -Action 'Promote' -ManifestPath $productApproved -ActorMode 'production'
    Assert-True ($result.ExitCode -eq 0) ('A complete product poster should promote with evidence binding: ' + $result.Output)
    $productReceipt = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path (Split-Path -Parent $productApproved) 'promotion-receipt.json') | ConvertFrom-Json
    foreach ($kind in @('visual_reference','product_asset','product_identity_lock','asset_transfer','acceptance','design_review')) {
        Assert-True (@($productReceipt.evidence | Where-Object { [string]$_.kind -eq $kind }).Count -gt 0) ("Product promotion receipt is missing evidence kind: $kind")
    }
    $result = Invoke-Gate -Action 'VerifyPromoted' -ManifestPath $productApproved -ActorMode 'production'
    Assert-True ($result.ExitCode -eq 0) ('Product evidence-bound promotion must pass VerifyPromoted: ' + $result.Output)

    Write-Output 'PASS: poster workflow gate accepted valid general/product/dual-chat paths and rejected unsafe paths.'
}
finally {
    foreach ($artifact in $defaultRootArtifacts) {
        if (Test-Path -LiteralPath $artifact) {
            $artifactFull = [System.IO.Path]::GetFullPath($artifact)
            if (-not $artifactFull.StartsWith($projectTempFull, [System.StringComparison]::OrdinalIgnoreCase)) {
                throw 'Refusing to remove a default-root test artifact outside project temp.'
            }
            Remove-Item -LiteralPath $artifactFull -Recurse -Force
        }
    }
    if (Test-Path -LiteralPath $sandboxFull) {
        $verified = [System.IO.Path]::GetFullPath($sandboxFull)
        if (-not $verified.StartsWith($projectTempFull, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw 'Refusing to remove a test path outside project temp.'
        }
        Remove-Item -LiteralPath $verified -Recurse -Force
    }
}
