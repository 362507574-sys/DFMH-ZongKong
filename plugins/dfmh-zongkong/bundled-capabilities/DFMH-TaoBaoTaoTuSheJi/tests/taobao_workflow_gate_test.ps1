param()

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$gatePath = Join-Path $projectRoot 'scripts\taobao_workflow_gate.ps1'
$sandbox = Join-Path $projectRoot ('temp\taobao-workflow-gate-test-' + [guid]::NewGuid().ToString('N'))
$sandboxFull = [System.IO.Path]::GetFullPath($sandbox)
$projectTempFull = [System.IO.Path]::GetFullPath((Join-Path $projectRoot 'temp')) + [System.IO.Path]::DirectorySeparatorChar
$outsideFiles = New-Object System.Collections.ArrayList
$promotionInjectionJob = $null
$promotionInjectionReleasePath = $null

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Invoke-Gate {
    param(
        [string]$Action,
        [string]$ManifestPath,
        [ValidateSet('main', 'production', 'test')]
        [string]$ActorMode = 'test'
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

    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = ($output -join "`n")
    }
}

function Save-Manifest {
    param([string]$Path, [object]$Manifest)
    $Manifest | ConvertTo-Json -Depth 20 | Set-Content -Encoding UTF8 -LiteralPath $Path
}

function Read-Manifest {
    param([string]$Path)
    return Get-Content -Raw -Encoding UTF8 -LiteralPath $Path | ConvertFrom-Json
}

function Write-TestPng {
    param([string]$Path, [int]$Width, [int]$Height)

    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    Add-Type -AssemblyName System.Drawing
    $bitmap = New-Object System.Drawing.Bitmap($Width, $Height)
    try {
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        try {
            $graphics.Clear([System.Drawing.Color]::FromArgb(242, 242, 242))
        }
        finally {
            $graphics.Dispose()
        }
        $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $bitmap.Dispose()
    }
}

function Get-PromptDefinitions {
    param([ValidateSet('home', 'detail', 'full')][string]$ScopeMode)

    if ($ScopeMode -eq 'home') {
        return @(
            [ordered]@{ id = 'H01'; type = 'home'; claimId = 'S01'; roleId = ''; width = 1000; height = 1000 },
            [ordered]@{ id = 'H02'; type = 'home'; claimId = 'S01'; roleId = ''; width = 1000; height = 1000 }
        )
    }
    if ($ScopeMode -eq 'detail') {
        return @(
            [ordered]@{ id = 'D01'; type = 'detail'; claimId = 'S01'; roleId = 'R01'; width = 1080; height = 2340 },
            [ordered]@{ id = 'D02'; type = 'detail'; claimId = 'S01'; roleId = 'R02'; width = 1080; height = 2340 }
        )
    }
    return @(
        [ordered]@{ id = 'H01'; type = 'home'; claimId = 'S01'; roleId = ''; width = 1000; height = 1000 },
        [ordered]@{ id = 'H02'; type = 'home'; claimId = 'S01'; roleId = ''; width = 1000; height = 1000 },
        [ordered]@{ id = 'D01'; type = 'detail'; claimId = 'S01'; roleId = 'R01'; width = 1080; height = 2340 }
    )
}

function New-WorkflowFixture {
    param(
        [string]$Name,
        [ValidateSet('home', 'detail', 'full')]
        [string]$ScopeMode = 'full',
        [string]$CurrentItemId = '',
        [string]$AnchorItemId = '',
        [bool]$AnchorConfirmed = $false,
        [ValidateSet('chatgpt_web_qq', 'codex_internal_image_gen')]
        [string]$GenerationChannel = 'chatgpt_web_qq',
        [switch]$IncludeCandidates,
        [switch]$AcceptAllItems,
        [switch]$Approve
    )

    $jobId = 'gate-' + $Name
    $jobRelative = 'temp/taobao-jobs/' + $jobId
    $jobRoot = Join-Path $sandboxFull ($jobRelative -replace '/', '\')
    New-Item -ItemType Directory -Force -Path $jobRoot | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $jobRoot 'assets'), (Join-Path $jobRoot 'benchmark'), (Join-Path $jobRoot 'prompts\home'), (Join-Path $jobRoot 'prompts\detail'), (Join-Path $jobRoot 'candidates\home'), (Join-Path $jobRoot 'candidates\detail'), (Join-Path $jobRoot 'acceptance') | Out-Null

    $assetRelative = $jobRelative + '/assets/product.png'
    $assetFull = Join-Path $sandboxFull ($assetRelative -replace '/', '\')
    Copy-Item -LiteralPath (Join-Path $sandboxFull 'temp\fixture-assets\product.png') -Destination $assetFull
    $assetHash = (Get-FileHash -LiteralPath $assetFull -Algorithm SHA256).Hash
    $assetBytes = (Get-Item -LiteralPath $assetFull).Length
    $profileRelative = 'templates/taobao-category-profiles/shoes-v1.json'
    $profileFull = Join-Path $sandboxFull ($profileRelative -replace '/', '\')
    [System.IO.File]::WriteAllText(
        $profileFull,
        '{"id":"shoes","version":"shoes-v1","state":"pilot","subtypes":["performance_running"],"applicableCategories":["synthetic shoe"],"excludedCategories":["stroller"],"sellingPointPriority":["purchase_outcome","core_performance","structure_proof","appearance_difference"],"recommendedViews":["outer side","outsole","top","heel"],"structureChecks":["upper","midsole","outsole","heel"],"homePageRoles":["hero","performance"],"detailPageRoles":["hero","proof","scene","summary"],"shotFamilies":["side hero","three-quarter","top"],"proofModes":["integrated","borderless macro"],"forbiddenPatterns":["isolated_floating_detail_box","per_image_emperor_approval"],"copyTone":["clear","professional"],"pageRhythm":["hero","proof","scene","summary"],"plannerPromptPath":"templates/TAOBAO_SHOES_PAGE_PLANNER_PROMPT.md","imagePromptPath":"templates/TAOBAO_SHOES_IMAGE_PROMPT.md"}'
    )
    $profileHash = (Get-FileHash -LiteralPath $profileFull -Algorithm SHA256).Hash
    $structureLockRelative = $jobRelative + '/product-structure-lock.md'
    [System.IO.File]::WriteAllText(
        (Join-Path $sandboxFull ($structureLockRelative -replace '/', '\')),
        'Synthetic product structure fingerprint and visible-view boundary.'
    )
    $structureLockHash = (Get-FileHash -LiteralPath (Join-Path $sandboxFull ($structureLockRelative -replace '/', '\')) -Algorithm SHA256).Hash
    $benchmarkReportRelative = $jobRelative + '/benchmark/market-benchmark-v1.md'
    [System.IO.File]::WriteAllText(
        (Join-Path $sandboxFull ($benchmarkReportRelative -replace '/', '\')),
        'Synthetic four-platform visual benchmark and professional style decision.'
    )
    $benchmarkReferences = New-Object System.Collections.ArrayList
    $benchmarkPlatforms = @('taobao_tmall', 'taobao_tmall', 'amazon', 'amazon', 'xiaohongshu', 'xiaohongshu', 'dewu', 'dewu')
    for ($benchmarkIndex = 0; $benchmarkIndex -lt $benchmarkPlatforms.Count; $benchmarkIndex++) {
        $benchmarkId = 'B{0:d2}' -f ($benchmarkIndex + 1)
        $benchmarkEvidenceRelative = $jobRelative + '/benchmark/' + $benchmarkId + '.md'
        [System.IO.File]::WriteAllText(
            (Join-Path $sandboxFull ($benchmarkEvidenceRelative -replace '/', '\')),
            'Synthetic visual evidence for ' + $benchmarkPlatforms[$benchmarkIndex]
        )
        [void]$benchmarkReferences.Add([ordered]@{
            id = $benchmarkId
            platform = $benchmarkPlatforms[$benchmarkIndex]
            url = 'https://example.com/' + $benchmarkId.ToLowerInvariant()
            capturedAt = '2026-07-23T10:00:00+08:00'
            evidencePath = $benchmarkEvidenceRelative
            observation = 'Product-led composition with integrated proof and continuous page rhythm.'
        })
    }

    $definitions = @(Get-PromptDefinitions -ScopeMode $ScopeMode)
    if (-not $CurrentItemId) { $CurrentItemId = $definitions[0].id }
    if (-not $AnchorItemId) { $AnchorItemId = if ($ScopeMode -eq 'detail') { 'D01' } else { 'H01' } }

    $promptItems = New-Object System.Collections.ArrayList
    $candidateItems = New-Object System.Collections.ArrayList
    foreach ($definition in $definitions) {
        $cardRelative = $jobRelative + '/prompts/' + $definition.type + '/' + $definition.id + '-V1-card.md'
        $promptRelative = $jobRelative + '/prompts/' + $definition.type + '/' + $definition.id + '-V1-prompt.txt'
        [System.IO.File]::WriteAllText((Join-Path $sandboxFull ($cardRelative -replace '/', '\')), 'Synthetic design card for ' + $definition.id)
        [System.IO.File]::WriteAllText((Join-Path $sandboxFull ($promptRelative -replace '/', '\')), 'Synthetic clean prompt for ' + $definition.id)

        [void]$promptItems.Add([ordered]@{
            id = $definition.id
            type = $definition.type
            version = 'V1'
            claimId = $definition.claimId
            roleId = $definition.roleId
            referenceSha256 = $assetHash
            structureLockSha256 = $structureLockHash
            viewConstraint = 'Only the source-supported front three-quarter view and its crops'
            compositionFamily = if ($definition.id -eq 'D02') { 'split_story' } elseif ($definition.type -eq 'detail') { 'scene_integrated' } else { 'product_led' }
            proofPresentation = if ($definition.id -eq 'D02') { 'split_story' } elseif ($definition.type -eq 'detail') { 'scene_integrated' } else { 'product_led' }
            proofAddsNewInformation = $true
            cardPath = $cardRelative
            promptPath = $promptRelative
            width = $definition.width
            height = $definition.height
            status = if ($AcceptAllItems) { 'accepted' } else { 'ready' }
        })

        if ($IncludeCandidates) {
            $candidateRelative = $jobRelative + '/candidates/' + $definition.type + '/' + $definition.id + '-V1.png'
            $candidateFull = Join-Path $sandboxFull ($candidateRelative -replace '/', '\')
            $fixtureImage = if ($definition.type -eq 'detail') { 'detail.png' } else { 'home.png' }
            Copy-Item -LiteralPath (Join-Path $sandboxFull ('temp\fixture-assets\' + $fixtureImage)) -Destination $candidateFull
            $acceptanceRelative = $jobRelative + '/acceptance/' + $definition.id + '-V1.md'
            [System.IO.File]::WriteAllText((Join-Path $sandboxFull ($acceptanceRelative -replace '/', '\')), 'Synthetic acceptance evidence for ' + $definition.id)
            [void]$candidateItems.Add([ordered]@{
                id = $definition.id
                type = $definition.type
                version = 'V1'
                promptId = $definition.id
                path = $candidateRelative
                acceptancePath = $acceptanceRelative
                sha256 = (Get-FileHash -LiteralPath $candidateFull -Algorithm SHA256).Hash
                bytes = (Get-Item -LiteralPath $candidateFull).Length
                width = $definition.width
                height = $definition.height
                status = if ($AcceptAllItems) { 'accepted' } else { 'candidate_ready' }
                quality = [ordered]@{
                    productConsistency = $true
                    claimEvidence = $true
                    claimVisualMapping = $true
                    textAccuracy = $true
                    dimensions = $true
                    aiArtifacts = $true
                    forbiddenContent = $true
                    mechanismLegibility = $true
                    relativeProportion = $true
                    structureConsistency = $true
                    benchmarkAlignment = $true
                    categoryFit = $true
                    visualIntegration = $true
                    proofRelevance = $true
                    lowerHalfContinuity = $true
                    moduleNovelty = $true
                    fourLayerCompleteness = $true
                    detailContentDensity = $true
                    singleChatSession = $true
                }
            })
        }
    }

    $setAcceptanceRelative = $jobRelative + '/acceptance/set-V1.md'
    [System.IO.File]::WriteAllText((Join-Path $sandboxFull ($setAcceptanceRelative -replace '/', '\')), 'Synthetic full-set acceptance evidence')
    $outputRelative = 'outputs/' + $jobId + '-V1'
    $manifestPath = Join-Path $jobRoot 'manifest.json'
    $isInternalChannel = $GenerationChannel -eq 'codex_internal_image_gen'
    $chatSessionReference = if ($isInternalChannel) { 'codex-internal://' + $jobId } else { 'synthetic://chat/session' }
    $manifest = [ordered]@{
        schemaVersion = '1.0'
        jobId = $jobId
        originThreadMode = 'test'
        status = if ($Approve) { 'approved' } elseif ($AcceptAllItems) { 'single_images_passed' } else { 'prompts_confirmed' }
        scope = [ordered]@{
            mode = $ScopeMode
            homeRequired = ($ScopeMode -eq 'home' -or $ScopeMode -eq 'full')
            detailRequired = ($ScopeMode -eq 'detail' -or $ScopeMode -eq 'full')
        }
        category = [ordered]@{
            id = 'shoes'
            subtype = 'performance_running'
            profileVersion = 'shoes-v1'
            profilePath = $profileRelative
            profileSha256 = $profileHash
            confirmed = $true
        }
        product = [ordered]@{
            name = 'Synthetic stroller'
            assets = @([ordered]@{
                id = 'A01'
                path = $assetRelative
                sourcePath = 'synthetic://fixture/product.png'
                fileName = 'product.png'
                bytes = $assetBytes
                sha256 = $assetHash
                authorizationConfirmed = $true
                authorizationStatement = 'Authorized synthetic fixture'
            })
            facts = @([ordered]@{
                id = 'F01'
                name = 'Reversible handle'
                value = 'Front and rear positions'
                evidenceType = 'user_confirmed'
                evidenceReference = 'Synthetic fixture confirmation'
                verified = $true
            })
        }
        sellingPoints = [ordered]@{
            confirmed = $true
            confirmationStatement = 'Emperor confirmed synthetic selling points'
            confirmedAt = '2026-07-16T12:00:00+08:00'
            items = @([ordered]@{
                id = 'S01'
                purchaseRole = 'core_purchase_driver'
                shortTitle = 'Two-way interaction'
                buyerBenefit = 'Switch interaction direction to suit the caregiving scene'
                copy = 'Handle supports front and rear positions'
                visualProof = 'Show both verified handle endpoints around the same pivot'
                claimBoundary = 'Do not imply rotation directions or locking modes not present in evidence'
                evidenceType = 'user_confirmed'
                evidenceReference = 'Synthetic fixture confirmation'
                homeEligible = $true
                detailEligible = $true
                verified = $true
            })
        }
        marketBenchmark = [ordered]@{
            completed = $true
            completedAt = '2026-07-23T10:00:00+08:00'
            productCategory = 'Synthetic stroller'
            reportPath = $benchmarkReportRelative
            references = @($benchmarkReferences)
            styleDecision = [ordered]@{
                name = 'Product-led integrated proof'
                rationale = 'Synthetic professional decision based on four-platform visual evidence.'
                platformBlend = 'Tmall 40%, Dewu 25%, Amazon 20%, Xiaohongshu 15%'
                visualPrinciples = @('large product subject', 'integrated proof', 'continuous page rhythm')
                forbiddenPatterns = @('isolated_floating_detail_box', 'consecutive_same_detail_module')
                detailProofStrategy = 'Use scene-integrated proof, borderless macro bands and anchored callouts.'
            }
        }
        promptSet = [ordered]@{
            confirmed = $true
            confirmationStatement = 'Emperor confirmed synthetic prompt set'
            confirmedAt = '2026-07-16T12:01:00+08:00'
            styleLock = [ordered]@{
                brand = 'Synthetic brand'
                productColor = 'White'
                productStructure = 'Locked to source'
                productMaterial = 'Locked to source'
                productProportion = 'Locked to source'
                productAccessories = 'No additions'
                corePalette = 'Warm neutral'
                typography = 'Bold Chinese ecommerce'
                informationHierarchy = 'Title subtitle tags'
                lighting = 'Soft studio light'
                photographyStyle = 'Realistic ecommerce photography'
                forbiddenContent = @('watermark', 'QR code', 'invented price')
                benchmarkReportPath = $benchmarkReportRelative
                styleDirection = 'Product-led integrated proof'
                proofIntegrationRules = @('Proof must be connected to the product or scene', 'Every proof module must add new information')
                forbiddenLayouts = @('isolated_floating_detail_box', 'consecutive_same_detail_module')
            }
            structureLock = [ordered]@{
                referenceAssetId = 'A01'
                referencePath = $assetRelative
                referenceSha256 = $assetHash
                recordPath = $structureLockRelative
                confirmed = $true
                immutableComponents = @(
                    'striped canopy assembly and its support rods',
                    'brown seat bumper and striped harness assembly',
                    'gray reversible push handle and side pivot',
                    'gray crossing frame and triangular storage basket',
                    'paired front and rear wheel assemblies'
                )
                connectionTopology = @('handle connects to the same side pivot', 'basket stays below the same frame')
                relativeGeometry = @('rear wheel is moderately larger than front wheel')
                visibleViewBoundary = @('only source-supported front three-quarter views and crops')
                allowedVariations = @('background, lighting, text layout and crop')
                forbiddenVariations = @('invented front, rear, top or underside structure', 'replacement with a generic similar product')
            }
            items = @($promptItems)
        }
        assetTransfer = [ordered]@{
            required = $true
            assetPath = $assetRelative
            expectedSha256 = $assetHash
            itemId = $CurrentItemId
            promptVersion = 'V1'
            verifiedAt = '2026-07-16T12:01:30+08:00'
            chatSessionReference = $chatSessionReference
            conversationAction = if ($isInternalChannel) { 'direct_tool_call' } elseif ($CurrentItemId -eq $AnchorItemId) { 'opened_new' } else { 'reused_existing' }
            authorizationConfirmed = $true
            destination = if ($isInternalChannel) { 'Codex internal ImageGen' } else { 'ChatGPT web via QQ Browser' }
            method = if ($isInternalChannel) { 'referenced_image_paths' } else { 'clipboard_file_copy' }
            clipboardPrepared = -not $isInternalChannel
            thumbnailVerified = -not $isInternalChannel
            verifiedAssetName = 'product.png'
            pathTextEntered = $false
            status = 'verified'
            failureReason = ''
        }
        generation = [ordered]@{
            currentItemId = $CurrentItemId
            channel = $GenerationChannel
            channelStatus = if ($isInternalChannel) { 'experimental' } else { 'default' }
            executionMode = 'batch_after_style_anchor'
            reviewPolicy = 'anchor_once_batch_qc_final_set_review'
            batchAuthorization = [ordered]@{
                jobId = $jobId
                categoryId = 'shoes'
                profileVersion = 'shoes-v1'
                channel = $GenerationChannel
                scope = 'remaining_queue_after_anchor'
                statement = 'Emperor authorized synthetic automatic remaining queue'
                authorizedAt = '2026-07-24T12:00:00+08:00'
                confirmed = $true
            }
            channelAuthorization = if ($isInternalChannel) {
                [ordered]@{
                    jobId = $jobId
                    itemId = $CurrentItemId
                    promptVersion = 'V1'
                    channel = 'codex_internal_image_gen'
                    purpose = 'Synthetic internal-channel workflow test'
                    statement = 'Emperor authorized this exact internal-channel fixture'
                    authorizedAt = '2026-07-24T12:00:00+08:00'
                    confirmed = $true
                }
            } else {
                [ordered]@{}
            }
            chatSessionPolicy = if ($isInternalChannel) { 'stateless_reference_bound' } else { 'single_conversation_full_set' }
            chatSessionReference = $chatSessionReference
            chatSessionOpenedForItemId = if ($isInternalChannel) { '' } else { $AnchorItemId }
            newConversationCount = if ($isInternalChannel) { 0 } else { 1 }
            styleAnchor = [ordered]@{
                itemId = $AnchorItemId
                confirmed = $AnchorConfirmed
                confirmationStatement = if ($AnchorConfirmed) { 'Emperor confirmed synthetic visual direction' } else { '' }
                confirmedAt = if ($AnchorConfirmed) { '2026-07-16T12:02:00+08:00' } else { '' }
            }
        }
        candidates = @($candidateItems)
        setAcceptance = [ordered]@{
            path = $setAcceptanceRelative
            passed = [bool]$AcceptAllItems
            checks = [ordered]@{
                productConsistency = $true
                brandConsistency = $true
                styleConsistency = $true
                compositionVariation = $true
                claimCompleteness = $true
                claimVisualMapping = $true
                detailRhythm = $true
                promptImageVersionMapping = $true
                mechanismLegibility = $true
                relativeProportion = $true
                structureConsistency = $true
                marketBenchmarkAlignment = $true
                proofIntegration = $true
                moduleRepetitionControl = $true
                lowerHalfContinuity = $true
            }
        }
        approval = [ordered]@{
            approved = [bool]$Approve
            statement = if ($Approve) { 'Emperor approved synthetic final set' } else { '' }
            approvedAt = if ($Approve) { '2026-07-16T12:03:00+08:00' } else { '' }
        }
        promotion = [ordered]@{
            outputDirectory = $outputRelative
            promoted = $false
            promotedAt = ''
            promotedBy = ''
            files = @()
        }
        history = @([ordered]@{
            at = '2026-07-16T12:00:00+08:00'
            actor = 'test'
            action = 'fixture_created'
            itemId = ''
            version = 'V1'
            statement = 'Synthetic workflow fixture'
        })
    }

    Save-Manifest -Path $manifestPath -Manifest $manifest
    return [pscustomobject]@{
        ManifestPath = $manifestPath
        JobRoot = $jobRoot
        JobRelative = $jobRelative
        OutputRelative = $outputRelative
    }
}

function Set-PromptStatus {
    param([object]$Manifest, [string]$Id, [string]$Status)
    $item = @($Manifest.promptSet.items | Where-Object { $_.id -eq $Id })
    Assert-True ($item.Count -eq 1) ('Fixture prompt item missing or duplicated: ' + $Id)
    $item[0].status = $Status
}

function Assert-GateFails {
    param([string]$Action, [string]$ManifestPath, [string]$Message, [string]$ActorMode = 'test')
    $result = Invoke-Gate -Action $Action -ManifestPath $ManifestPath -ActorMode $ActorMode
    Assert-True ($result.ExitCode -ne 0) ($Message + "`nGate output:`n" + $result.Output)
}

function Assert-GatePasses {
    param([string]$Action, [string]$ManifestPath, [string]$Message, [string]$ActorMode = 'test')
    $result = Invoke-Gate -Action $Action -ManifestPath $ManifestPath -ActorMode $ActorMode
    Assert-True ($result.ExitCode -eq 0) ($Message + "`nGate output:`n" + $result.Output)
}

New-Item -ItemType Directory -Force -Path (Join-Path $sandboxFull 'temp\fixture-assets'), (Join-Path $sandboxFull 'temp\taobao-jobs'), (Join-Path $sandboxFull 'outputs'), (Join-Path $sandboxFull 'templates'), (Join-Path $sandboxFull 'templates\taobao-category-profiles') | Out-Null

try {
    Copy-Item -LiteralPath (Join-Path $projectRoot 'templates\TAOBAO_HOME_IMAGE_PROMPT.md') -Destination (Join-Path $sandboxFull 'templates\TAOBAO_HOME_IMAGE_PROMPT.md')
    Copy-Item -LiteralPath (Join-Path $projectRoot 'templates\TAOBAO_HOME_IMAGE_PROMPT.lock.json') -Destination (Join-Path $sandboxFull 'templates\TAOBAO_HOME_IMAGE_PROMPT.lock.json')
    Copy-Item -LiteralPath (Join-Path $projectRoot 'templates\TAOBAO_DETAIL_IMAGE_PROMPT.md') -Destination (Join-Path $sandboxFull 'templates\TAOBAO_DETAIL_IMAGE_PROMPT.md')
    Copy-Item -LiteralPath (Join-Path $projectRoot 'templates\TAOBAO_DETAIL_IMAGE_PROMPT.lock.json') -Destination (Join-Path $sandboxFull 'templates\TAOBAO_DETAIL_IMAGE_PROMPT.lock.json')
    Write-TestPng -Path (Join-Path $sandboxFull 'temp\fixture-assets\product.png') -Width 1000 -Height 1000
    Write-TestPng -Path (Join-Path $sandboxFull 'temp\fixture-assets\home.png') -Width 1000 -Height 1000
    Write-TestPng -Path (Join-Path $sandboxFull 'temp\fixture-assets\detail.png') -Width 1080 -Height 2340
    $smokeFixture = New-WorkflowFixture -Name 'fixture-smoke' -ScopeMode full
    Assert-True (Test-Path -LiteralPath $smokeFixture.ManifestPath -PathType Leaf) 'Workflow test fixture manifest was not initialized.'
    $smokeManifest = Read-Manifest -Path $smokeFixture.ManifestPath
    Assert-True ($smokeManifest.generation.styleAnchor.itemId -eq 'H01') 'Workflow test fixture anchor was not initialized.'
    Write-Output ('FIXTURE_READY: ' + $smokeFixture.ManifestPath)
    Assert-True (Test-Path -LiteralPath $gatePath -PathType Leaf) ('TARGET_GATE_MISSING: expected gate script does not exist: ' + $gatePath)

    $statusResult = Invoke-Gate -Action 'Status' -ManifestPath $smokeFixture.ManifestPath
    Assert-True ($statusResult.ExitCode -eq 0) ('Status must succeed for a valid manifest.' + "`nGate output:`n" + $statusResult.Output)
    Assert-True ($statusResult.Output -match 'prompts_confirmed') ('Status output must report the current workflow status.' + "`nGate output:`n" + $statusResult.Output)
    Assert-True ($statusResult.Output -match 'gate-fixture-smoke') ('Status output must identify the current job.' + "`nGate output:`n" + $statusResult.Output)

    $sandboxHomePrompt = Join-Path $sandboxFull 'templates\TAOBAO_HOME_IMAGE_PROMPT.md'
    [System.IO.File]::AppendAllText($sandboxHomePrompt, "`nUNAPPROVED_APPEND")
    Assert-GateFails 'Status' $smokeFixture.ManifestPath 'Any addition to the Emperor-fixed home prompt must be rejected before a Taobao workflow action.'
    Copy-Item -LiteralPath (Join-Path $projectRoot 'templates\TAOBAO_HOME_IMAGE_PROMPT.md') -Destination $sandboxHomePrompt -Force

    $sandboxDetailPrompt = Join-Path $sandboxFull 'templates\TAOBAO_DETAIL_IMAGE_PROMPT.md'
    [System.IO.File]::AppendAllText($sandboxDetailPrompt, "`nUNAPPROVED_APPEND")
    Assert-GateFails 'Status' $smokeFixture.ManifestPath 'Any addition to the Emperor-fixed detail prompt must be rejected before a Taobao workflow action.'
    Copy-Item -LiteralPath (Join-Path $projectRoot 'templates\TAOBAO_DETAIL_IMAGE_PROMPT.md') -Destination $sandboxDetailPrompt -Force

    $uploadConfirmationWrongType = New-WorkflowFixture -Name 'upload-confirmation-string'
    $manifest = Read-Manifest $uploadConfirmationWrongType.ManifestPath
    $manifest.assetTransfer.authorizationConfirmed = 'true'
    Save-Manifest $uploadConfirmationWrongType.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $uploadConfirmationWrongType.ManifestPath 'assetTransfer.authorizationConfirmed must be a JSON Boolean, not the string "true".'

    $uploadCannotBeDisabled = New-WorkflowFixture -Name 'upload-required-false'
    $manifest = Read-Manifest $uploadCannotBeDisabled.ManifestPath
    $manifest.assetTransfer.required = $false
    Save-Manifest $uploadCannotBeDisabled.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $uploadCannotBeDisabled.ManifestPath 'The first product-image upload requirement cannot be disabled before generation.'

    $uploadWrongItem = New-WorkflowFixture -Name 'upload-wrong-item' -CurrentItemId H01
    $manifest = Read-Manifest $uploadWrongItem.ManifestPath
    $manifest.assetTransfer.itemId = 'H02'
    Save-Manifest $uploadWrongItem.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $uploadWrongItem.ManifestPath 'A verified upload from another image item must not be reusable.'

    $uploadWrongVersion = New-WorkflowFixture -Name 'upload-wrong-version' -CurrentItemId H01
    $manifest = Read-Manifest $uploadWrongVersion.ManifestPath
    $manifest.assetTransfer.promptVersion = 'V2'
    Save-Manifest $uploadWrongVersion.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $uploadWrongVersion.ManifestPath 'A verified upload from another prompt version must not be reusable.'

    $uploadMissingTime = New-WorkflowFixture -Name 'upload-missing-time' -CurrentItemId H01
    $manifest = Read-Manifest $uploadMissingTime.ManifestPath
    $manifest.assetTransfer.verifiedAt = ''
    Save-Manifest $uploadMissingTime.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $uploadMissingTime.ManifestPath 'A verified upload without a binding timestamp must fail.'

    $uploadInvalidTime = New-WorkflowFixture -Name 'upload-invalid-time' -CurrentItemId H01
    $manifest = Read-Manifest $uploadInvalidTime.ManifestPath
    $manifest.assetTransfer.verifiedAt = 'not-a-time'
    Save-Manifest $uploadInvalidTime.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $uploadInvalidTime.ManifestPath 'A verified upload with an invalid binding timestamp must fail.'

    $wrongConversationPolicy = New-WorkflowFixture -Name 'wrong-conversation-policy'
    $manifest = Read-Manifest $wrongConversationPolicy.ManifestPath
    $manifest.generation.chatSessionPolicy = 'new_conversation_per_image'
    Save-Manifest $wrongConversationPolicy.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $wrongConversationPolicy.ManifestPath 'Taobao generation must use one conversation for the full set.'

    $mismatchedConversationReference = New-WorkflowFixture -Name 'mismatched-conversation-reference'
    $manifest = Read-Manifest $mismatchedConversationReference.ManifestPath
    $manifest.assetTransfer.chatSessionReference = 'synthetic://chat/another-session'
    Save-Manifest $mismatchedConversationReference.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $mismatchedConversationReference.ManifestPath 'Per-image binding must use the original full-set conversation.'

    $multipleConversations = New-WorkflowFixture -Name 'multiple-conversations'
    $manifest = Read-Manifest $multipleConversations.ManifestPath
    $manifest.generation.newConversationCount = 2
    Save-Manifest $multipleConversations.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $multipleConversations.ManifestPath 'Opening more than one conversation must fail.'

    $detailOpenedNewConversation = New-WorkflowFixture -Name 'detail-opened-new-conversation' -ScopeMode full -CurrentItemId D01 -AnchorConfirmed $true
    $manifest = Read-Manifest $detailOpenedNewConversation.ManifestPath
    $manifest.promptSet.items[0].status = 'accepted'
    $manifest.promptSet.items[1].status = 'accepted'
    $manifest.promptSet.items[2].status = 'ready'
    $manifest.assetTransfer.conversationAction = 'opened_new'
    Save-Manifest $detailOpenedNewConversation.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $detailOpenedNewConversation.ManifestPath 'The first detail image in a full set must reuse the home-image conversation.'

    $internalReady = New-WorkflowFixture -Name 'internal-ready' -GenerationChannel codex_internal_image_gen
    Assert-GatePasses 'CheckBeforeGenerate' $internalReady.ManifestPath 'An explicitly authorized internal ImageGen item with a fresh source-image binding must pass.'

    $internalMissingAuthorization = New-WorkflowFixture -Name 'internal-missing-authorization' -GenerationChannel codex_internal_image_gen
    $manifest = Read-Manifest $internalMissingAuthorization.ManifestPath
    $manifest.generation.channelAuthorization = [pscustomobject]@{}
    Save-Manifest $internalMissingAuthorization.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $internalMissingAuthorization.ManifestPath 'Internal ImageGen must fail without current-job and current-version authorization.'

    $internalWrongAuthorizedItem = New-WorkflowFixture -Name 'internal-wrong-authorized-item' -GenerationChannel codex_internal_image_gen
    $manifest = Read-Manifest $internalWrongAuthorizedItem.ManifestPath
    $manifest.generation.channelAuthorization.itemId = 'H02'
    Save-Manifest $internalWrongAuthorizedItem.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $internalWrongAuthorizedItem.ManifestPath 'Internal ImageGen authorization from another item must not be reusable.'

    $internalWrongAuthorizedVersion = New-WorkflowFixture -Name 'internal-wrong-authorized-version' -GenerationChannel codex_internal_image_gen
    $manifest = Read-Manifest $internalWrongAuthorizedVersion.ManifestPath
    $manifest.generation.channelAuthorization.promptVersion = 'V2'
    Save-Manifest $internalWrongAuthorizedVersion.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $internalWrongAuthorizedVersion.ManifestPath 'Internal ImageGen authorization from another prompt version must not be reusable.'

    $internalPretendsClipboard = New-WorkflowFixture -Name 'internal-pretends-clipboard' -GenerationChannel codex_internal_image_gen
    $manifest = Read-Manifest $internalPretendsClipboard.ManifestPath
    $manifest.assetTransfer.method = 'clipboard_file_copy'
    $manifest.assetTransfer.clipboardPrepared = $true
    $manifest.assetTransfer.thumbnailVerified = $true
    Save-Manifest $internalPretendsClipboard.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $internalPretendsClipboard.ManifestPath 'Internal ImageGen must not pretend that a webpage clipboard or thumbnail step occurred.'

    $internalWrongPolicy = New-WorkflowFixture -Name 'internal-wrong-policy' -GenerationChannel codex_internal_image_gen
    $manifest = Read-Manifest $internalWrongPolicy.ManifestPath
    $manifest.generation.chatSessionPolicy = 'single_conversation_full_set'
    Save-Manifest $internalWrongPolicy.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $internalWrongPolicy.ManifestPath 'Internal ImageGen must use the stateless reference-bound policy.'

    $internalInventsConversation = New-WorkflowFixture -Name 'internal-invents-conversation' -GenerationChannel codex_internal_image_gen
    $manifest = Read-Manifest $internalInventsConversation.ManifestPath
    $manifest.generation.newConversationCount = 1
    $manifest.generation.chatSessionOpenedForItemId = 'H01'
    Save-Manifest $internalInventsConversation.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $internalInventsConversation.ManifestPath 'Internal ImageGen must not claim that a ChatGPT conversation was opened.'

    $internalWrongAction = New-WorkflowFixture -Name 'internal-wrong-action' -GenerationChannel codex_internal_image_gen
    $manifest = Read-Manifest $internalWrongAction.ManifestPath
    $manifest.assetTransfer.conversationAction = 'reused_existing'
    Save-Manifest $internalWrongAction.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $internalWrongAction.ManifestPath 'Internal ImageGen must record a direct tool call rather than a reused webpage conversation.'

    $singleItemExecution = New-WorkflowFixture -Name 'single-item-execution'
    $manifest = Read-Manifest $singleItemExecution.ManifestPath
    $manifest.generation.executionMode = 'single_item_turn'
    Save-Manifest $singleItemExecution.ManifestPath $manifest
    Assert-GateFails 'Status' $singleItemExecution.ManifestPath 'Taobao execution must not revert to one user approval per image.'

    $perImageReview = New-WorkflowFixture -Name 'per-image-review'
    $manifest = Read-Manifest $perImageReview.ManifestPath
    $manifest.generation.reviewPolicy = 'per_image_emperor_approval'
    Save-Manifest $perImageReview.ManifestPath $manifest
    Assert-GateFails 'Status' $perImageReview.ManifestPath 'The review policy must keep Emperor review at the style anchor and final set only.'

    $awaitingEmperorPerImage = New-WorkflowFixture -Name 'awaiting-emperor-per-image'
    $manifest = Read-Manifest $awaitingEmperorPerImage.ManifestPath
    $manifest.promptSet.items[0].status = 'generated_awaiting_emperor_review'
    Save-Manifest $awaitingEmperorPerImage.ManifestPath $manifest
    Assert-GateFails 'Status' $awaitingEmperorPerImage.ManifestPath 'A generated item must enter agent QC instead of waiting for Emperor review.'

    $missingBatchAuthorization = New-WorkflowFixture -Name 'missing-batch-authorization' -ScopeMode home -CurrentItemId H02 -AnchorConfirmed $true
    $manifest = Read-Manifest $missingBatchAuthorization.ManifestPath
    $manifest.promptSet.items[0].status = 'accepted'
    $manifest.promptSet.items[1].status = 'ready'
    $manifest.generation.batchAuthorization = [pscustomobject]@{}
    Save-Manifest $missingBatchAuthorization.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $missingBatchAuthorization.ManifestPath 'Images after the style anchor require a job-scoped batch authorization record.'

    $wrongBatchAuthorization = New-WorkflowFixture -Name 'wrong-batch-authorization' -ScopeMode home -CurrentItemId H02 -AnchorConfirmed $true
    $manifest = Read-Manifest $wrongBatchAuthorization.ManifestPath
    $manifest.promptSet.items[0].status = 'accepted'
    $manifest.promptSet.items[1].status = 'ready'
    $manifest.generation.batchAuthorization.jobId = 'another-job'
    Save-Manifest $wrongBatchAuthorization.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $wrongBatchAuthorization.ManifestPath 'Batch authorization must be bound to the current job and category profile.'

    $automaticNext = New-WorkflowFixture -Name 'automatic-next' -ScopeMode home -CurrentItemId H02 -AnchorConfirmed $true -IncludeCandidates -AcceptAllItems
    $automaticNextResult = Invoke-Gate -Action 'CheckBeforeNext' -ManifestPath $automaticNext.ManifestPath
    Assert-True ($automaticNextResult.ExitCode -eq 0) ('Accepted item should be able to advance automatically. Output: ' + $automaticNextResult.Output)
    Assert-True ($automaticNextResult.Output -match 'automatically without Emperor approval') 'The gate must explicitly report autonomous progression after agent QC.'

    $scopeMissing = New-WorkflowFixture -Name 'scope-missing'
    $manifest = Read-Manifest $scopeMissing.ManifestPath
    $manifest.scope.mode = ''
    $manifest.scope.homeRequired = $false
    $manifest.scope.detailRequired = $false
    Save-Manifest $scopeMissing.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $scopeMissing.ManifestPath 'Unconfirmed scope must fail before generation.'

    $invalidJobId = New-WorkflowFixture -Name 'invalid-job-id'
    $manifest = Read-Manifest $invalidJobId.ManifestPath
    $manifest.jobId = 'Gate_Invalid'
    Save-Manifest $invalidJobId.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $invalidJobId.ManifestPath 'Runtime jobId must follow the initializer lowercase-hyphen pattern and reject uppercase or underscores.'

    $invalidSellingConfirmationTime = New-WorkflowFixture -Name 'invalid-selling-time'
    $manifest = Read-Manifest $invalidSellingConfirmationTime.ManifestPath
    $manifest.sellingPoints.confirmedAt = 'not-a-confirmation-time'
    Save-Manifest $invalidSellingConfirmationTime.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $invalidSellingConfirmationTime.ManifestPath 'sellingPoints.confirmedAt must be a valid timestamp.'

    $invalidPromptConfirmationTime = New-WorkflowFixture -Name 'invalid-prompt-time'
    $manifest = Read-Manifest $invalidPromptConfirmationTime.ManifestPath
    $manifest.promptSet.confirmedAt = 'not-a-confirmation-time'
    Save-Manifest $invalidPromptConfirmationTime.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $invalidPromptConfirmationTime.ManifestPath 'promptSet.confirmedAt must be a valid timestamp.'

    $sellingUnconfirmed = New-WorkflowFixture -Name 'selling-unconfirmed'
    $manifest = Read-Manifest $sellingUnconfirmed.ManifestPath
    $manifest.sellingPoints.confirmed = $false
    Save-Manifest $sellingUnconfirmed.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $sellingUnconfirmed.ManifestPath 'Unconfirmed selling points must fail before generation.'

    $sellingItemsNotArray = New-WorkflowFixture -Name 'selling-items-object'
    $manifest = Read-Manifest $sellingItemsNotArray.ManifestPath
    $manifest.sellingPoints.items = $manifest.sellingPoints.items[0]
    Save-Manifest $sellingItemsNotArray.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $sellingItemsNotArray.ManifestPath 'sellingPoints.items must remain a JSON array even when it contains one item.'

    $sellingUnverified = New-WorkflowFixture -Name 'selling-unverified'
    $manifest = Read-Manifest $sellingUnverified.ManifestPath
    $manifest.sellingPoints.items[0].verified = $false
    Save-Manifest $sellingUnverified.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $sellingUnverified.ManifestPath 'Unverified selling-point evidence must fail before generation.'

    $sellingMissingPurchaseRole = New-WorkflowFixture -Name 'selling-missing-purchase-role'
    $manifest = Read-Manifest $sellingMissingPurchaseRole.ManifestPath
    $manifest.sellingPoints.items[0].PSObject.Properties.Remove('purchaseRole')
    Save-Manifest $sellingMissingPurchaseRole.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $sellingMissingPurchaseRole.ManifestPath 'Every selling point must declare its purchase role.'

    $sellingInvalidPurchaseRole = New-WorkflowFixture -Name 'selling-invalid-purchase-role'
    $manifest = Read-Manifest $sellingInvalidPurchaseRole.ManifestPath
    $manifest.sellingPoints.items[0].purchaseRole = 'visual_detail'
    Save-Manifest $sellingInvalidPurchaseRole.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $sellingInvalidPurchaseRole.ManifestPath 'Unknown selling-point purchase roles must fail.'

    $sellingMissingBuyerBenefit = New-WorkflowFixture -Name 'selling-missing-buyer-benefit'
    $manifest = Read-Manifest $sellingMissingBuyerBenefit.ManifestPath
    $manifest.sellingPoints.items[0].PSObject.Properties.Remove('buyerBenefit')
    Save-Manifest $sellingMissingBuyerBenefit.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $sellingMissingBuyerBenefit.ManifestPath 'Every selling point must explain the buyer benefit.'

    $sellingMissingVisualProof = New-WorkflowFixture -Name 'selling-missing-visual-proof'
    $manifest = Read-Manifest $sellingMissingVisualProof.ManifestPath
    $manifest.sellingPoints.items[0].PSObject.Properties.Remove('visualProof')
    Save-Manifest $sellingMissingVisualProof.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $sellingMissingVisualProof.ManifestPath 'Every selling point must define an honest visual proof.'

    $sellingMissingClaimBoundary = New-WorkflowFixture -Name 'selling-missing-claim-boundary'
    $manifest = Read-Manifest $sellingMissingClaimBoundary.ManifestPath
    $manifest.sellingPoints.items[0].PSObject.Properties.Remove('claimBoundary')
    Save-Manifest $sellingMissingClaimBoundary.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $sellingMissingClaimBoundary.ManifestPath 'Every selling point must define its claim boundary.'

    $sellingMissingHomeEligibility = New-WorkflowFixture -Name 'selling-missing-home-eligibility'
    $manifest = Read-Manifest $sellingMissingHomeEligibility.ManifestPath
    $manifest.sellingPoints.items[0].PSObject.Properties.Remove('homeEligible')
    Save-Manifest $sellingMissingHomeEligibility.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $sellingMissingHomeEligibility.ManifestPath 'Every selling point must declare homeEligible.'

    $sellingMissingDetailEligibility = New-WorkflowFixture -Name 'selling-missing-detail-eligibility'
    $manifest = Read-Manifest $sellingMissingDetailEligibility.ManifestPath
    $manifest.sellingPoints.items[0].PSObject.Properties.Remove('detailEligible')
    Save-Manifest $sellingMissingDetailEligibility.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $sellingMissingDetailEligibility.ManifestPath 'Every selling point must declare detailEligible.'

    $sellingInvalidHomeEligibility = New-WorkflowFixture -Name 'selling-invalid-home-eligibility'
    $manifest = Read-Manifest $sellingInvalidHomeEligibility.ManifestPath
    $manifest.sellingPoints.items[0].homeEligible = 'true'
    Save-Manifest $sellingInvalidHomeEligibility.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $sellingInvalidHomeEligibility.ManifestPath 'sellingPoints.items[].homeEligible must be a Boolean.'

    $sellingInvalidDetailEligibility = New-WorkflowFixture -Name 'selling-invalid-detail-eligibility'
    $manifest = Read-Manifest $sellingInvalidDetailEligibility.ManifestPath
    $manifest.sellingPoints.items[0].detailEligible = 1
    Save-Manifest $sellingInvalidDetailEligibility.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $sellingInvalidDetailEligibility.ManifestPath 'sellingPoints.items[].detailEligible must be a Boolean.'

    $factMissingField = New-WorkflowFixture -Name 'fact-missing-field'
    $manifest = Read-Manifest $factMissingField.ManifestPath
    $manifest.product.facts[0].PSObject.Properties.Remove('evidenceReference')
    Save-Manifest $factMissingField.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $factMissingField.ManifestPath 'A nonempty product fact must contain every required evidence field.'

    $factInvalidVerified = New-WorkflowFixture -Name 'fact-invalid-verified'
    $manifest = Read-Manifest $factInvalidVerified.ManifestPath
    $manifest.product.facts[0].verified = 'true'
    Save-Manifest $factInvalidVerified.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $factInvalidVerified.ManifestPath 'product.facts[].verified must be the Boolean true.'

    $historyMissingField = New-WorkflowFixture -Name 'history-missing-field'
    $manifest = Read-Manifest $historyMissingField.ManifestPath
    $manifest.history[0].PSObject.Properties.Remove('statement')
    Save-Manifest $historyMissingField.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $historyMissingField.ManifestPath 'A nonempty history item must contain every required field.'

    $historyInvalidFormat = New-WorkflowFixture -Name 'history-invalid-format'
    $manifest = Read-Manifest $historyInvalidFormat.ManifestPath
    $manifest.history[0].at = 'not-a-timestamp'
    $manifest.history[0].version = 'version-one'
    Save-Manifest $historyInvalidFormat.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $historyInvalidFormat.ManifestPath 'History timestamps and versions must use the documented formats.'

    $historyNotArray = New-WorkflowFixture -Name 'history-object'
    $manifest = Read-Manifest $historyNotArray.ManifestPath
    $manifest.history = $manifest.history[0]
    Save-Manifest $historyNotArray.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $historyNotArray.ManifestPath 'history must remain a JSON array when nonempty.'

    $promptsUnconfirmed = New-WorkflowFixture -Name 'prompts-unconfirmed'
    $manifest = Read-Manifest $promptsUnconfirmed.ManifestPath
    $manifest.promptSet.confirmed = $false
    Save-Manifest $promptsUnconfirmed.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $promptsUnconfirmed.ManifestPath 'Unconfirmed prompts must fail before generation.'

    $promptItemsNotArray = New-WorkflowFixture -Name 'prompt-items-object' -ScopeMode home -CurrentItemId H01
    $manifest = Read-Manifest $promptItemsNotArray.ManifestPath
    $manifest.promptSet.items = $manifest.promptSet.items[0]
    Save-Manifest $promptItemsNotArray.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $promptItemsNotArray.ManifestPath 'promptSet.items must remain a JSON array even when one valid prompt remains.'

    $promptMissingClaimId = New-WorkflowFixture -Name 'prompt-missing-claim-id'
    $manifest = Read-Manifest $promptMissingClaimId.ManifestPath
    $manifest.promptSet.items[0].PSObject.Properties.Remove('claimId')
    Save-Manifest $promptMissingClaimId.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $promptMissingClaimId.ManifestPath 'Every prompt item must declare claimId, including an explicit empty value.'

    $promptMissingRoleId = New-WorkflowFixture -Name 'prompt-missing-role-id'
    $manifest = Read-Manifest $promptMissingRoleId.ManifestPath
    $manifest.promptSet.items[0].PSObject.Properties.Remove('roleId')
    Save-Manifest $promptMissingRoleId.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $promptMissingRoleId.ManifestPath 'Every prompt item must declare roleId, including an explicit empty value.'

    $promptInvalidClaimId = New-WorkflowFixture -Name 'prompt-invalid-claim-id'
    $manifest = Read-Manifest $promptInvalidClaimId.ManifestPath
    $manifest.promptSet.items[0].claimId = '01'
    Save-Manifest $promptInvalidClaimId.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $promptInvalidClaimId.ManifestPath 'A nonempty prompt claimId must use S plus two digits.'

    $promptInvalidRoleId = New-WorkflowFixture -Name 'prompt-invalid-role-id' -ScopeMode detail
    $manifest = Read-Manifest $promptInvalidRoleId.ManifestPath
    $manifest.promptSet.items[0].roleId = 'ROLE1'
    Save-Manifest $promptInvalidRoleId.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $promptInvalidRoleId.ManifestPath 'A nonempty prompt roleId must use R plus two digits.'

    $promptPurposeConflict = New-WorkflowFixture -Name 'prompt-purpose-conflict' -ScopeMode home
    $manifest = Read-Manifest $promptPurposeConflict.ManifestPath
    $manifest.promptSet.items[0].claimId = ''
    $manifest.promptSet.items[0].roleId = 'R01'
    Save-Manifest $promptPurposeConflict.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $promptPurposeConflict.ManifestPath 'A home selling-point image cannot be represented only as a detail-page role item.'

    $styleLockMissingField = New-WorkflowFixture -Name 'style-lock-missing-field'
    $manifest = Read-Manifest $styleLockMissingField.ManifestPath
    $manifest.promptSet.styleLock.PSObject.Properties.Remove('lighting')
    Save-Manifest $styleLockMissingField.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $styleLockMissingField.ManifestPath 'A confirmed prompt set must contain every fixed styleLock field.'

    $benchmarkMissing = New-WorkflowFixture -Name 'benchmark-missing'
    $manifest = Read-Manifest $benchmarkMissing.ManifestPath
    $manifest.PSObject.Properties.Remove('marketBenchmark')
    Save-Manifest $benchmarkMissing.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $benchmarkMissing.ManifestPath 'Generation must be blocked when the market benchmark is missing.'

    $benchmarkIncomplete = New-WorkflowFixture -Name 'benchmark-incomplete'
    $manifest = Read-Manifest $benchmarkIncomplete.ManifestPath
    $manifest.marketBenchmark.completed = $false
    Save-Manifest $benchmarkIncomplete.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $benchmarkIncomplete.ManifestPath 'Generation must be blocked until market benchmarking is complete.'

    $benchmarkTooFew = New-WorkflowFixture -Name 'benchmark-too-few'
    $manifest = Read-Manifest $benchmarkTooFew.ManifestPath
    $manifest.marketBenchmark.references = @($manifest.marketBenchmark.references | Select-Object -First 7)
    Save-Manifest $benchmarkTooFew.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $benchmarkTooFew.ManifestPath 'Market benchmarking must contain at least eight references.'

    $benchmarkMissingPlatform = New-WorkflowFixture -Name 'benchmark-missing-platform'
    $manifest = Read-Manifest $benchmarkMissingPlatform.ManifestPath
    foreach ($reference in $manifest.marketBenchmark.references) {
        if ($reference.platform -eq 'dewu') { $reference.platform = 'amazon' }
    }
    Save-Manifest $benchmarkMissingPlatform.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $benchmarkMissingPlatform.ManifestPath 'Market benchmarking must contain at least two references from every required platform.'

    $benchmarkMissingBan = New-WorkflowFixture -Name 'benchmark-missing-ban'
    $manifest = Read-Manifest $benchmarkMissingBan.ManifestPath
    $manifest.marketBenchmark.styleDecision.forbiddenPatterns = @('consecutive_same_detail_module')
    Save-Manifest $benchmarkMissingBan.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $benchmarkMissingBan.ManifestPath 'The benchmark decision must explicitly forbid isolated floating detail boxes.'

    $promptIsolatedBox = New-WorkflowFixture -Name 'prompt-isolated-box' -ScopeMode detail
    $manifest = Read-Manifest $promptIsolatedBox.ManifestPath
    $manifest.promptSet.items[0].proofPresentation = 'isolated_floating_box'
    Save-Manifest $promptIsolatedBox.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $promptIsolatedBox.ManifestPath 'An isolated floating detail box must never reach image generation.'

    $promptProofNoNewInformation = New-WorkflowFixture -Name 'prompt-proof-no-new-information' -ScopeMode detail
    $manifest = Read-Manifest $promptProofNoNewInformation.ManifestPath
    $manifest.promptSet.items[0].proofAddsNewInformation = $false
    Save-Manifest $promptProofNoNewInformation.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $promptProofNoNewInformation.ManifestPath 'A proof module that adds no new information must be rejected.'

    $promptRepeatedComposition = New-WorkflowFixture -Name 'prompt-repeated-composition' -ScopeMode detail
    $manifest = Read-Manifest $promptRepeatedComposition.ManifestPath
    $manifest.promptSet.items[1].compositionFamily = $manifest.promptSet.items[0].compositionFamily
    Save-Manifest $promptRepeatedComposition.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $promptRepeatedComposition.ManifestPath 'Consecutive detail screens must not repeat the same composition family.'

    $promptRepeatedFrame = New-WorkflowFixture -Name 'prompt-repeated-frame' -ScopeMode detail
    $manifest = Read-Manifest $promptRepeatedFrame.ManifestPath
    foreach ($item in $manifest.promptSet.items) {
        $item.proofPresentation = 'framed_anchored'
    }
    Save-Manifest $promptRepeatedFrame.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $promptRepeatedFrame.ManifestPath 'Anchored framed proof may not repeat on consecutive detail screens.'

    $structureLockMissing = New-WorkflowFixture -Name 'structure-lock-missing'
    $manifest = Read-Manifest $structureLockMissing.ManifestPath
    $manifest.promptSet.PSObject.Properties.Remove('structureLock')
    Save-Manifest $structureLockMissing.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $structureLockMissing.ManifestPath 'A confirmed prompt set must contain a product structure fingerprint.'

    $structureLockMissingField = New-WorkflowFixture -Name 'structure-lock-missing-field'
    $manifest = Read-Manifest $structureLockMissingField.ManifestPath
    $manifest.promptSet.structureLock.PSObject.Properties.Remove('visibleViewBoundary')
    Save-Manifest $structureLockMissingField.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $structureLockMissingField.ManifestPath 'The product structure fingerprint must declare every fixed field.'

    $structureLockUnconfirmed = New-WorkflowFixture -Name 'structure-lock-unconfirmed'
    $manifest = Read-Manifest $structureLockUnconfirmed.ManifestPath
    $manifest.promptSet.structureLock.confirmed = $false
    Save-Manifest $structureLockUnconfirmed.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $structureLockUnconfirmed.ManifestPath 'An unconfirmed product structure fingerprint must block generation.'

    $structureLockHashMismatch = New-WorkflowFixture -Name 'structure-lock-hash-mismatch'
    $manifest = Read-Manifest $structureLockHashMismatch.ManifestPath
    $manifest.promptSet.structureLock.referenceSha256 = ('0' * 64)
    Save-Manifest $structureLockHashMismatch.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $structureLockHashMismatch.ManifestPath 'The structure-lock reference hash must match the archived product asset.'

    $structureLockEmptyBoundary = New-WorkflowFixture -Name 'structure-lock-empty-boundary'
    $manifest = Read-Manifest $structureLockEmptyBoundary.ManifestPath
    $manifest.promptSet.structureLock.visibleViewBoundary = @()
    Save-Manifest $structureLockEmptyBoundary.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $structureLockEmptyBoundary.ManifestPath 'An empty visible-view boundary must block generation.'

    $structureLockMissingRecord = New-WorkflowFixture -Name 'structure-lock-missing-record'
    $manifest = Read-Manifest $structureLockMissingRecord.ManifestPath
    Remove-Item -LiteralPath (Join-Path $sandboxFull ($manifest.promptSet.structureLock.recordPath -replace '/', '\'))
    Assert-GateFails 'CheckBeforeGenerate' $structureLockMissingRecord.ManifestPath 'A missing product-structure record must block generation.'

    $structureLockTooFewComponents = New-WorkflowFixture -Name 'structure-lock-too-few-components'
    $manifest = Read-Manifest $structureLockTooFewComponents.ManifestPath
    $manifest.promptSet.structureLock.immutableComponents = @('same')
    Save-Manifest $structureLockTooFewComponents.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $structureLockTooFewComponents.ManifestPath 'A vague one-line component lock must not count as a structure fingerprint.'

    $structureLockTooFewTopology = New-WorkflowFixture -Name 'structure-lock-too-few-topology'
    $manifest = Read-Manifest $structureLockTooFewTopology.ManifestPath
    $manifest.promptSet.structureLock.connectionTopology = @('same')
    Save-Manifest $structureLockTooFewTopology.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $structureLockTooFewTopology.ManifestPath 'The structure fingerprint must contain multiple concrete topology relations.'

    $structureLockTooFewForbidden = New-WorkflowFixture -Name 'structure-lock-too-few-forbidden'
    $manifest = Read-Manifest $structureLockTooFewForbidden.ManifestPath
    $manifest.promptSet.structureLock.forbiddenVariations = @('same')
    Save-Manifest $structureLockTooFewForbidden.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $structureLockTooFewForbidden.ManifestPath 'The structure fingerprint must contain multiple concrete forbidden variations.'

    $promptMissingReferenceHash = New-WorkflowFixture -Name 'prompt-missing-reference-hash'
    $manifest = Read-Manifest $promptMissingReferenceHash.ManifestPath
    $manifest.promptSet.items[0].PSObject.Properties.Remove('referenceSha256')
    Save-Manifest $promptMissingReferenceHash.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $promptMissingReferenceHash.ManifestPath 'Every prompt item must bind the archived reference-image hash.'

    $promptWrongReferenceHash = New-WorkflowFixture -Name 'prompt-wrong-reference-hash'
    $manifest = Read-Manifest $promptWrongReferenceHash.ManifestPath
    $manifest.promptSet.items[0].referenceSha256 = ('0' * 64)
    Save-Manifest $promptWrongReferenceHash.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $promptWrongReferenceHash.ManifestPath 'A prompt item bound to another reference hash must fail.'

    $promptMissingStructureHash = New-WorkflowFixture -Name 'prompt-missing-structure-hash'
    $manifest = Read-Manifest $promptMissingStructureHash.ManifestPath
    $manifest.promptSet.items[0].PSObject.Properties.Remove('structureLockSha256')
    Save-Manifest $promptMissingStructureHash.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $promptMissingStructureHash.ManifestPath 'Every prompt item must bind the current structure-lock record hash.'

    $promptWrongStructureHash = New-WorkflowFixture -Name 'prompt-wrong-structure-hash'
    $manifest = Read-Manifest $promptWrongStructureHash.ManifestPath
    $manifest.promptSet.items[0].structureLockSha256 = ('0' * 64)
    Save-Manifest $promptWrongStructureHash.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $promptWrongStructureHash.ManifestPath 'A prompt item bound to a different structure-lock record must fail.'

    $promptVagueViewConstraint = New-WorkflowFixture -Name 'prompt-vague-view-constraint'
    $manifest = Read-Manifest $promptVagueViewConstraint.ManifestPath
    $manifest.promptSet.items[0].viewConstraint = 'same'
    Save-Manifest $promptVagueViewConstraint.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $promptVagueViewConstraint.ManifestPath 'Every prompt item must declare a concrete source-supported view constraint.'

    $currentMissing = New-WorkflowFixture -Name 'current-missing' -CurrentItemId 'H99'
    Assert-GateFails 'CheckBeforeGenerate' $currentMissing.ManifestPath 'Current image missing from the prompt queue must fail.'

    $currentDuplicated = New-WorkflowFixture -Name 'current-duplicated' -CurrentItemId 'H01'
    $manifest = Read-Manifest $currentDuplicated.ManifestPath
    $duplicatePrompt = $manifest.promptSet.items[0] | ConvertTo-Json -Depth 10 | ConvertFrom-Json
    $manifest.promptSet.items = @($manifest.promptSet.items) + @($duplicatePrompt)
    Save-Manifest $currentDuplicated.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $currentDuplicated.ManifestPath 'A duplicated current item in the prompt queue must fail.'

    $missingCard = New-WorkflowFixture -Name 'current-missing-card' -CurrentItemId 'H01'
    $manifest = Read-Manifest $missingCard.ManifestPath
    $manifest.promptSet.items[0].cardPath = $missingCard.JobRelative + '/prompts/home/missing-card.md'
    Save-Manifest $missingCard.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $missingCard.ManifestPath 'A current item whose design card does not exist must fail.'

    $missingPrompt = New-WorkflowFixture -Name 'current-missing-prompt' -CurrentItemId 'H01'
    $manifest = Read-Manifest $missingPrompt.ManifestPath
    $manifest.promptSet.items[0].promptPath = $missingPrompt.JobRelative + '/prompts/home/missing-prompt.txt'
    Save-Manifest $missingPrompt.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $missingPrompt.ManifestPath 'A current item whose clean prompt does not exist must fail.'

    $homeAnchor = New-WorkflowFixture -Name 'home-anchor' -ScopeMode home -CurrentItemId H01 -AnchorItemId H01 -AnchorConfirmed $false
    Assert-GatePasses 'CheckBeforeGenerate' $homeAnchor.ManifestPath 'H01 must be allowed as the first home queue item after selling-point and prompt confirmation.'

    $fullAnchor = New-WorkflowFixture -Name 'full-anchor' -ScopeMode full -CurrentItemId H01 -AnchorItemId H01 -AnchorConfirmed $false
    Assert-GatePasses 'CheckBeforeGenerate' $fullAnchor.ManifestPath 'H01 must be allowed as the first full-set queue item after selling-point and prompt confirmation.'

    $detailAnchor = New-WorkflowFixture -Name 'detail-anchor' -ScopeMode detail -CurrentItemId D01 -AnchorItemId D01 -AnchorConfirmed $false
    Assert-GatePasses 'CheckBeforeGenerate' $detailAnchor.ManifestPath 'D01 must be allowed as the first detail queue item after selling-point and prompt confirmation.'

    $homeNumberGap = New-WorkflowFixture -Name 'home-number-gap' -ScopeMode home -CurrentItemId H01
    $manifest = Read-Manifest $homeNumberGap.ManifestPath
    $manifest.promptSet.items[1].id = 'H99'
    Save-Manifest $homeNumberGap.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $homeNumberGap.ManifestPath 'A home queue with H01 followed by H99 must fail continuous numbering.'

    $detailNumberGap = New-WorkflowFixture -Name 'detail-number-gap' -ScopeMode detail -CurrentItemId D01 -AnchorItemId D01
    $manifest = Read-Manifest $detailNumberGap.ManifestPath
    $manifest.promptSet.items[1].id = 'D77'
    Save-Manifest $detailNumberGap.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $detailNumberGap.ManifestPath 'A detail queue with D01 followed by D77 must fail continuous numbering.'

    $fullInterleaved = New-WorkflowFixture -Name 'full-interleaved' -ScopeMode full -CurrentItemId H01
    $manifest = Read-Manifest $fullInterleaved.ManifestPath
    $manifest.promptSet.items = @($manifest.promptSet.items[0], $manifest.promptSet.items[2], $manifest.promptSet.items[1])
    Save-Manifest $fullInterleaved.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $fullInterleaved.ManifestPath 'A full queue must not insert a detail item between home items.'

    $fullWrongHomeOrder = New-WorkflowFixture -Name 'full-wrong-home-order' -ScopeMode full -CurrentItemId H01
    $manifest = Read-Manifest $fullWrongHomeOrder.ManifestPath
    $h03 = $manifest.promptSet.items[1] | ConvertTo-Json -Depth 10 | ConvertFrom-Json
    $h03.id = 'H03'
    $h03.cardPath = $fullWrongHomeOrder.JobRelative + '/prompts/home/H03-V1-card.md'
    $h03.promptPath = $fullWrongHomeOrder.JobRelative + '/prompts/home/H03-V1-prompt.txt'
    [System.IO.File]::WriteAllText((Join-Path $sandboxFull ($h03.cardPath -replace '/', '\')), 'Synthetic design card for H03')
    [System.IO.File]::WriteAllText((Join-Path $sandboxFull ($h03.promptPath -replace '/', '\')), 'Synthetic clean prompt for H03')
    $manifest.promptSet.items = @($manifest.promptSet.items[0], $h03, $manifest.promptSet.items[1], $manifest.promptSet.items[2])
    Save-Manifest $fullWrongHomeOrder.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $fullWrongHomeOrder.ManifestPath 'A full queue containing H01,H03,H02 must fail ordered continuous numbering.'

    $detailWrongAnchor = New-WorkflowFixture -Name 'detail-wrong-anchor' -ScopeMode detail -CurrentItemId D01 -AnchorItemId H01
    Assert-GateFails 'CheckBeforeGenerate' $detailWrongAnchor.ManifestPath 'A detail-only task fixed to H01 must fail.'

    $laterWithoutAnchor = New-WorkflowFixture -Name 'later-without-anchor' -ScopeMode full -CurrentItemId H02 -AnchorItemId H01 -AnchorConfirmed $false
    $manifest = Read-Manifest $laterWithoutAnchor.ManifestPath
    Set-PromptStatus $manifest 'H01' 'accepted'
    Save-Manifest $laterWithoutAnchor.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeGenerate' $laterWithoutAnchor.ManifestPath 'A non-anchor item must fail until the visual anchor is confirmed.'

    $previousNotAccepted = New-WorkflowFixture -Name 'previous-not-accepted' -ScopeMode full -CurrentItemId H02 -AnchorItemId H01 -AnchorConfirmed $true
    Assert-GateFails 'CheckBeforeGenerate' $previousNotAccepted.ManifestPath 'A later item must fail while a preceding queue item is not accepted.'

    $laterReady = New-WorkflowFixture -Name 'later-ready' -ScopeMode full -CurrentItemId H02 -AnchorItemId H01 -AnchorConfirmed $true
    $manifest = Read-Manifest $laterReady.ManifestPath
    Set-PromptStatus $manifest 'H01' 'accepted'
    Save-Manifest $laterReady.ManifestPath $manifest
    Assert-GatePasses 'CheckBeforeGenerate' $laterReady.ManifestPath 'A later item should pass after the anchor and all preceding items are accepted.'

    $candidateInOutputs = New-WorkflowFixture -Name 'candidate-in-outputs' -ScopeMode home -IncludeCandidates -AcceptAllItems
    $manifest = Read-Manifest $candidateInOutputs.ManifestPath
    $source = Join-Path $sandboxFull ($manifest.candidates[0].path -replace '/', '\')
    $unsafeRelative = 'outputs/unsafe-candidate.png'
    Copy-Item -LiteralPath $source -Destination (Join-Path $sandboxFull ($unsafeRelative -replace '/', '\'))
    $manifest.candidates[0].path = $unsafeRelative
    Save-Manifest $candidateInOutputs.ManifestPath $manifest
    Assert-GateFails 'CheckImageCandidate' $candidateInOutputs.ManifestPath 'A candidate inside outputs must fail candidate validation.'

    $candidateOutside = New-WorkflowFixture -Name 'candidate-outside' -ScopeMode home -IncludeCandidates -AcceptAllItems
    $manifest = Read-Manifest $candidateOutside.ManifestPath
    $source = Join-Path $sandboxFull ($manifest.candidates[0].path -replace '/', '\')
    $outsidePath = Join-Path (Split-Path -Parent $sandboxFull) ('taobao-outside-' + [guid]::NewGuid().ToString('N') + '.png')
    Copy-Item -LiteralPath $source -Destination $outsidePath
    [void]$outsideFiles.Add($outsidePath)
    $manifest.candidates[0].path = '../' + [System.IO.Path]::GetFileName($outsidePath)
    Save-Manifest $candidateOutside.ManifestPath $manifest
    Assert-GateFails 'CheckImageCandidate' $candidateOutside.ManifestPath 'A candidate outside the project root must fail candidate validation.'

    $foreignCandidateFixture = New-WorkflowFixture -Name 'candidate-foreign-source' -ScopeMode home -IncludeCandidates -AcceptAllItems
    $foreignCandidateManifest = Read-Manifest $foreignCandidateFixture.ManifestPath
    $crossJobCandidate = New-WorkflowFixture -Name 'candidate-cross-job' -ScopeMode home -IncludeCandidates -AcceptAllItems
    $manifest = Read-Manifest $crossJobCandidate.ManifestPath
    $foreignCandidate = $foreignCandidateManifest.candidates[0]
    $foreignCandidateFull = Join-Path $sandboxFull ($foreignCandidate.path -replace '/', '\')
    $foreignAcceptanceFull = Join-Path $sandboxFull ($foreignCandidate.acceptancePath -replace '/', '\')
    Assert-True (Test-Path -LiteralPath $foreignCandidateFull -PathType Leaf) 'Cross-job candidate fixture image was not created.'
    Assert-True (Test-Path -LiteralPath $foreignAcceptanceFull -PathType Leaf) 'Cross-job candidate fixture acceptance record was not created.'
    Assert-True ((Get-FileHash -LiteralPath $foreignCandidateFull -Algorithm SHA256).Hash -eq $foreignCandidate.sha256) 'Cross-job candidate fixture hash is inconsistent.'
    Assert-True ((Get-Item -LiteralPath $foreignCandidateFull).Length -eq $foreignCandidate.bytes) 'Cross-job candidate fixture byte count is inconsistent.'
    $manifest.candidates[0].path = $foreignCandidate.path
    $manifest.candidates[0].acceptancePath = $foreignCandidate.acceptancePath
    $manifest.candidates[0].sha256 = $foreignCandidate.sha256
    $manifest.candidates[0].bytes = $foreignCandidate.bytes
    $manifest.candidates[0].width = $foreignCandidate.width
    $manifest.candidates[0].height = $foreignCandidate.height
    Save-Manifest $crossJobCandidate.ManifestPath $manifest
    Assert-GateFails 'CheckImageCandidate' $crossJobCandidate.ManifestPath 'A real candidate and acceptance record owned by another Taobao job must be rejected.'

    $candidateNotArray = New-WorkflowFixture -Name 'candidate-object' -ScopeMode home -CurrentItemId H01 -IncludeCandidates -AcceptAllItems
    $manifest = Read-Manifest $candidateNotArray.ManifestPath
    $manifest.candidates = $manifest.candidates[0]
    Save-Manifest $candidateNotArray.ManifestPath $manifest
    Assert-GateFails 'CheckImageCandidate' $candidateNotArray.ManifestPath 'candidates must remain a JSON array even when validating one image.'

    $candidateQualityWrongType = New-WorkflowFixture -Name 'candidate-quality-string' -ScopeMode home -CurrentItemId H01 -IncludeCandidates -AcceptAllItems
    $manifest = Read-Manifest $candidateQualityWrongType.ManifestPath
    $manifest.candidates[0].quality.productConsistency = 'true'
    Save-Manifest $candidateQualityWrongType.ManifestPath $manifest
    Assert-GateFails 'CheckImageCandidate' $candidateQualityWrongType.ManifestPath 'Candidate quality flags must be JSON Booleans, not the string "true".'

    $candidateEmptyAcceptancePath = New-WorkflowFixture -Name 'candidate-empty-acceptance-path' -ScopeMode home -CurrentItemId H01 -IncludeCandidates -AcceptAllItems
    $manifest = Read-Manifest $candidateEmptyAcceptancePath.ManifestPath
    $manifest.candidates[0].acceptancePath = ''
    Save-Manifest $candidateEmptyAcceptancePath.ManifestPath $manifest
    Assert-GateFails 'CheckImageCandidate' $candidateEmptyAcceptancePath.ManifestPath 'A candidate acceptancePath cannot be empty.'

    $candidateBlankAcceptance = New-WorkflowFixture -Name 'candidate-blank-acceptance' -ScopeMode home -CurrentItemId H01 -IncludeCandidates -AcceptAllItems
    $manifest = Read-Manifest $candidateBlankAcceptance.ManifestPath
    $candidateAcceptanceFull = Join-Path $sandboxFull ($manifest.candidates[0].acceptancePath -replace '/', '\')
    [System.IO.File]::WriteAllText($candidateAcceptanceFull, "  `r`n`t")
    Assert-GateFails 'CheckImageCandidate' $candidateBlankAcceptance.ManifestPath 'A candidate acceptance record containing only whitespace must fail.'

    $candidateFakeWebp = New-WorkflowFixture -Name 'candidate-fake-webp' -ScopeMode home -CurrentItemId H01 -IncludeCandidates -AcceptAllItems
    $manifest = Read-Manifest $candidateFakeWebp.ManifestPath
    $pngCandidateFull = Join-Path $sandboxFull ($manifest.candidates[0].path -replace '/', '\')
    $webpRelative = $candidateFakeWebp.JobRelative + '/candidates/home/H01-V1.webp'
    $webpFull = Join-Path $sandboxFull ($webpRelative -replace '/', '\')
    Copy-Item -LiteralPath $pngCandidateFull -Destination $webpFull
    $manifest.candidates[0].path = $webpRelative
    $manifest.candidates[0].sha256 = (Get-FileHash -LiteralPath $webpFull -Algorithm SHA256).Hash
    $manifest.candidates[0].bytes = (Get-Item -LiteralPath $webpFull).Length
    Save-Manifest $candidateFakeWebp.ManifestPath $manifest
    Assert-GateFails 'CheckImageCandidate' $candidateFakeWebp.ManifestPath 'A .webp candidate must fail because the PowerShell 5.1 gate only verifies PNG and JPEG, even when the bytes contain a valid PNG.'

    $candidateJunction = New-WorkflowFixture -Name 'candidate-junction' -ScopeMode home -CurrentItemId H01 -IncludeCandidates -AcceptAllItems
    $manifest = Read-Manifest $candidateJunction.ManifestPath
    $junctionExternal = Join-Path $sandboxFull ('temp\junction-external-candidate-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $junctionExternal | Out-Null
    $junctionCandidateFull = Join-Path $junctionExternal 'H01-V1.png'
    Copy-Item -LiteralPath (Join-Path $sandboxFull ($manifest.candidates[0].path -replace '/', '\')) -Destination $junctionCandidateFull
    $candidateJunctionPath = Join-Path $candidateJunction.JobRoot 'candidates\home\external-link'
    try {
        New-Item -ItemType Junction -Path $candidateJunctionPath -Target $junctionExternal -ErrorAction Stop | Out-Null
    }
    catch {
        throw ('JUNCTION_TEST_BLOCKED: unable to create the required candidate junction: ' + $_.Exception.Message)
    }
    Assert-True ((((Get-Item -LiteralPath $candidateJunctionPath -Force).Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)) 'JUNCTION_TEST_BLOCKED: candidate junction was not created as a reparse point.'
    $manifest.candidates[0].path = $candidateJunction.JobRelative + '/candidates/home/external-link/H01-V1.png'
    $manifest.candidates[0].sha256 = (Get-FileHash -LiteralPath $junctionCandidateFull -Algorithm SHA256).Hash
    $manifest.candidates[0].bytes = (Get-Item -LiteralPath $junctionCandidateFull).Length
    Save-Manifest $candidateJunction.ManifestPath $manifest
    Assert-GateFails 'CheckImageCandidate' $candidateJunction.ManifestPath 'A candidate reached through a junction that leaves the task directory must fail.'

    $badHash = New-WorkflowFixture -Name 'candidate-bad-hash' -ScopeMode home -IncludeCandidates -AcceptAllItems
    $manifest = Read-Manifest $badHash.ManifestPath
    $manifest.candidates[0].sha256 = ('0' * 64)
    Save-Manifest $badHash.ManifestPath $manifest
    Assert-GateFails 'CheckImageCandidate' $badHash.ManifestPath 'A candidate with a mismatched hash must fail.'

    $missingCandidateFile = New-WorkflowFixture -Name 'candidate-file-missing' -ScopeMode home -IncludeCandidates -AcceptAllItems
    $manifest = Read-Manifest $missingCandidateFile.ManifestPath
    Remove-Item -LiteralPath (Join-Path $sandboxFull ($manifest.candidates[0].path -replace '/', '\')) -Force
    Assert-GateFails 'CheckImageCandidate' $missingCandidateFile.ManifestPath 'A candidate whose image file is missing must fail.'

    $missingAcceptanceFile = New-WorkflowFixture -Name 'candidate-acceptance-missing' -ScopeMode home -IncludeCandidates -AcceptAllItems
    $manifest = Read-Manifest $missingAcceptanceFile.ManifestPath
    Remove-Item -LiteralPath (Join-Path $sandboxFull ($manifest.candidates[0].acceptancePath -replace '/', '\')) -Force
    Assert-GateFails 'CheckImageCandidate' $missingAcceptanceFile.ManifestPath 'A candidate whose acceptance record is missing must fail.'

    $badBytes = New-WorkflowFixture -Name 'candidate-bad-bytes' -ScopeMode home -IncludeCandidates -AcceptAllItems
    $manifest = Read-Manifest $badBytes.ManifestPath
    $manifest.candidates[0].bytes = [int64]$manifest.candidates[0].bytes + 1
    Save-Manifest $badBytes.ManifestPath $manifest
    Assert-GateFails 'CheckImageCandidate' $badBytes.ManifestPath 'A candidate with a mismatched byte count must fail.'

    $badType = New-WorkflowFixture -Name 'candidate-bad-type' -ScopeMode home -IncludeCandidates -AcceptAllItems
    $manifest = Read-Manifest $badType.ManifestPath
    $manifest.candidates[0].type = 'detail'
    Save-Manifest $badType.ManifestPath $manifest
    Assert-GateFails 'CheckImageCandidate' $badType.ManifestPath 'A candidate whose type differs from its prompt must fail.'

    $badDimensions = New-WorkflowFixture -Name 'candidate-bad-dimensions' -ScopeMode home -IncludeCandidates -AcceptAllItems
    $manifest = Read-Manifest $badDimensions.ManifestPath
    $manifest.candidates[0].width = 999
    Save-Manifest $badDimensions.ManifestPath $manifest
    Assert-GateFails 'CheckImageCandidate' $badDimensions.ManifestPath 'A candidate with mismatched dimensions must fail.'

    foreach ($qualityField in @('productConsistency', 'claimEvidence', 'claimVisualMapping', 'textAccuracy', 'dimensions', 'aiArtifacts', 'forbiddenContent', 'mechanismLegibility', 'relativeProportion', 'structureConsistency', 'benchmarkAlignment', 'categoryFit', 'visualIntegration', 'proofRelevance', 'lowerHalfContinuity', 'moduleNovelty')) {
        $qualityFixture = New-WorkflowFixture -Name ('candidate-quality-' + $qualityField.ToLowerInvariant()) -ScopeMode home -IncludeCandidates -AcceptAllItems
        $manifest = Read-Manifest $qualityFixture.ManifestPath
        $manifest.candidates[0].quality.$qualityField = $false
        Save-Manifest $qualityFixture.ManifestPath $manifest
        Assert-GateFails 'CheckImageCandidate' $qualityFixture.ManifestPath ('A candidate must fail when quality.' + $qualityField + ' is false.')
    }

    foreach ($qualityField in @('fourLayerCompleteness', 'detailContentDensity', 'singleChatSession')) {
        $qualityFixture = New-WorkflowFixture -Name ('detail-quality-' + $qualityField.ToLowerInvariant()) -ScopeMode detail -IncludeCandidates -AcceptAllItems
        $manifest = Read-Manifest $qualityFixture.ManifestPath
        $manifest.candidates[0].quality.$qualityField = $false
        Save-Manifest $qualityFixture.ManifestPath $manifest
        Assert-GateFails 'CheckImageCandidate' $qualityFixture.ManifestPath ('A detail candidate must fail when quality.' + $qualityField + ' is false.')
    }

    $promptMismatch = New-WorkflowFixture -Name 'candidate-prompt-mismatch' -ScopeMode home -IncludeCandidates -AcceptAllItems
    $manifest = Read-Manifest $promptMismatch.ManifestPath
    $manifest.candidates[0].promptId = 'H99'
    Save-Manifest $promptMismatch.ManifestPath $manifest
    Assert-GateFails 'CheckImageCandidate' $promptMismatch.ManifestPath 'A candidate with a mismatched prompt ID must fail.'

    $validCandidate = New-WorkflowFixture -Name 'candidate-valid' -ScopeMode home -CurrentItemId H01 -IncludeCandidates -AcceptAllItems
    Assert-GatePasses 'CheckImageCandidate' $validCandidate.ManifestPath 'A complete single-image candidate should pass.'

    $nextBlocked = New-WorkflowFixture -Name 'next-blocked' -ScopeMode home -CurrentItemId H01 -IncludeCandidates
    Assert-GateFails 'CheckBeforeNext' $nextBlocked.ManifestPath 'CheckBeforeNext must fail while the current item is not accepted.'

    $nextAllowed = New-WorkflowFixture -Name 'next-allowed' -ScopeMode home -CurrentItemId H01 -IncludeCandidates -AcceptAllItems
    Assert-GatePasses 'CheckBeforeNext' $nextAllowed.ManifestPath 'CheckBeforeNext should pass for an accepted current item.'

    $setMissingCandidate = New-WorkflowFixture -Name 'set-missing-candidate' -ScopeMode full -IncludeCandidates -AcceptAllItems
    $manifest = Read-Manifest $setMissingCandidate.ManifestPath
    $manifest.candidates = @($manifest.candidates | Where-Object { $_.id -ne 'D01' })
    Save-Manifest $setMissingCandidate.ManifestPath $manifest
    Assert-GateFails 'CheckSet' $setMissingCandidate.ManifestPath 'CheckSet must fail when prompt and candidate IDs do not match.'

    $setUnaccepted = New-WorkflowFixture -Name 'set-unaccepted' -ScopeMode full -IncludeCandidates -AcceptAllItems
    $manifest = Read-Manifest $setUnaccepted.ManifestPath
    $manifest.candidates[1].status = 'candidate_ready'
    Save-Manifest $setUnaccepted.ManifestPath $manifest
    Assert-GateFails 'CheckSet' $setUnaccepted.ManifestPath 'CheckSet must fail when any candidate is not accepted.'

    foreach ($setField in @('productConsistency', 'brandConsistency', 'styleConsistency', 'compositionVariation', 'claimCompleteness', 'claimVisualMapping', 'detailRhythm', 'promptImageVersionMapping', 'mechanismLegibility', 'relativeProportion', 'structureConsistency', 'marketBenchmarkAlignment', 'proofIntegration', 'moduleRepetitionControl', 'lowerHalfContinuity')) {
        $setFixture = New-WorkflowFixture -Name ('set-check-' + $setField.ToLowerInvariant()) -ScopeMode full -IncludeCandidates -AcceptAllItems
        $manifest = Read-Manifest $setFixture.ManifestPath
        $manifest.setAcceptance.checks.$setField = $false
        Save-Manifest $setFixture.ManifestPath $manifest
        Assert-GateFails 'CheckSet' $setFixture.ManifestPath ('CheckSet must fail when setAcceptance.checks.' + $setField + ' is false.')
    }

    $setPassedWrongType = New-WorkflowFixture -Name 'set-passed-number' -ScopeMode full -IncludeCandidates -AcceptAllItems
    $manifest = Read-Manifest $setPassedWrongType.ManifestPath
    $manifest.setAcceptance.passed = 1
    Save-Manifest $setPassedWrongType.ManifestPath $manifest
    Assert-GateFails 'CheckSet' $setPassedWrongType.ManifestPath 'setAcceptance.passed must be a JSON Boolean, not number 1.'

    $setEmptyAcceptancePath = New-WorkflowFixture -Name 'set-empty-acceptance-path' -ScopeMode full -IncludeCandidates -AcceptAllItems
    $manifest = Read-Manifest $setEmptyAcceptancePath.ManifestPath
    $manifest.setAcceptance.path = ''
    Save-Manifest $setEmptyAcceptancePath.ManifestPath $manifest
    Assert-GateFails 'CheckSet' $setEmptyAcceptancePath.ManifestPath 'setAcceptance.path cannot be empty.'

    $setBlankAcceptance = New-WorkflowFixture -Name 'set-blank-acceptance' -ScopeMode full -IncludeCandidates -AcceptAllItems
    $manifest = Read-Manifest $setBlankAcceptance.ManifestPath
    $setAcceptanceFull = Join-Path $sandboxFull ($manifest.setAcceptance.path -replace '/', '\')
    [System.IO.File]::WriteAllText($setAcceptanceFull, " `r`n`t ")
    Assert-GateFails 'CheckSet' $setBlankAcceptance.ManifestPath 'A full-set acceptance record containing only whitespace must fail.'

    $validSet = New-WorkflowFixture -Name 'set-valid' -ScopeMode full -IncludeCandidates -AcceptAllItems
    Assert-GatePasses 'CheckSet' $validSet.ManifestPath 'A complete accepted image set should pass CheckSet.'

    $notApproved = New-WorkflowFixture -Name 'promote-not-approved' -ScopeMode full -IncludeCandidates -AcceptAllItems
    Assert-GateFails 'CheckBeforePromote' $notApproved.ManifestPath 'Promotion must fail without explicit Emperor approval.' 'main'

    $approvalWrongType = New-WorkflowFixture -Name 'approval-string' -ScopeMode full -IncludeCandidates -AcceptAllItems -Approve
    $manifest = Read-Manifest $approvalWrongType.ManifestPath
    $manifest.approval.approved = 'true'
    Save-Manifest $approvalWrongType.ManifestPath $manifest
    Assert-GateFails 'CheckBeforePromote' $approvalWrongType.ManifestPath 'approval.approved must be a JSON Boolean, not the string "true".' 'main'

    $approvalInvalidTime = New-WorkflowFixture -Name 'approval-invalid-time' -ScopeMode full -IncludeCandidates -AcceptAllItems -Approve
    $manifest = Read-Manifest $approvalInvalidTime.ManifestPath
    $manifest.approval.approvedAt = 'not-an-approval-time'
    Save-Manifest $approvalInvalidTime.ManifestPath $manifest
    Assert-GateFails 'CheckBeforePromote' $approvalInvalidTime.ManifestPath 'approval.approvedAt must be a valid timestamp.' 'main'

    $testActor = New-WorkflowFixture -Name 'promote-test-actor' -ScopeMode full -IncludeCandidates -AcceptAllItems -Approve
    Assert-GateFails 'Promote' $testActor.ManifestPath 'A test-thread actor must not promote.' 'test'

    $existingOutput = New-WorkflowFixture -Name 'promote-existing-output' -ScopeMode full -IncludeCandidates -AcceptAllItems -Approve
    $manifest = Read-Manifest $existingOutput.ManifestPath
    New-Item -ItemType Directory -Force -Path (Join-Path $sandboxFull ($manifest.promotion.outputDirectory -replace '/', '\')) | Out-Null
    Assert-GateFails 'CheckBeforePromote' $existingOutput.ManifestPath 'Promotion must refuse an existing output directory.' 'main'

    $escapingOutput = New-WorkflowFixture -Name 'promote-output-escape' -ScopeMode full -IncludeCandidates -AcceptAllItems -Approve
    $manifest = Read-Manifest $escapingOutput.ManifestPath
    $manifest.promotion.outputDirectory = 'temp/taobao-jobs/escaped-formal-output'
    Save-Manifest $escapingOutput.ManifestPath $manifest
    Assert-GateFails 'CheckBeforePromote' $escapingOutput.ManifestPath 'Promotion outputDirectory must not escape the outputs root.' 'main'

    $rollbackFixture = New-WorkflowFixture -Name 'promote-rollback' -ScopeMode full -IncludeCandidates -AcceptAllItems -Approve
    $rollbackBefore = Read-Manifest $rollbackFixture.ManifestPath
    $rollbackSourceHashes = @{}
    foreach ($candidate in $rollbackBefore.candidates) {
        $candidateFull = Join-Path $sandboxFull ($candidate.path -replace '/', '\')
        $rollbackSourceHashes[$candidate.id] = (Get-FileHash -LiteralPath $candidateFull -Algorithm SHA256).Hash
    }
    $rollbackBefore.candidates[1].sha256 = ('F' * 64)
    Save-Manifest $rollbackFixture.ManifestPath $rollbackBefore
    Assert-GateFails 'Promote' $rollbackFixture.ManifestPath 'A hash failure during promotion must roll back every new formal target.' 'main'
    $rollbackAfter = Read-Manifest $rollbackFixture.ManifestPath
    $rollbackOutputFull = Join-Path $sandboxFull ($rollbackAfter.promotion.outputDirectory -replace '/', '\')
    $rollbackOutputs = if (Test-Path -LiteralPath $rollbackOutputFull -PathType Container) { @(Get-ChildItem -LiteralPath $rollbackOutputFull -File -Recurse) } else { @() }
    Assert-True ($rollbackOutputs.Count -eq 0) 'A failed promotion must remove all files created by that promotion attempt.'
    foreach ($candidate in $rollbackAfter.candidates) {
        $candidateFull = Join-Path $sandboxFull ($candidate.path -replace '/', '\')
        Assert-True (Test-Path -LiteralPath $candidateFull -PathType Leaf) ('A failed promotion must preserve temp candidate: ' + $candidate.id)
        Assert-True ((Get-FileHash -LiteralPath $candidateFull -Algorithm SHA256).Hash -eq $rollbackSourceHashes[$candidate.id]) ('A failed promotion changed a temp candidate: ' + $candidate.id)
    }

    $copyFailureFixture = New-WorkflowFixture -Name 'promote-copy-failure-rollback' -ScopeMode full -IncludeCandidates -AcceptAllItems -Approve
    $copyFailureManifest = Read-Manifest $copyFailureFixture.ManifestPath
    $firstCandidateFull = Join-Path $sandboxFull ($copyFailureManifest.candidates[0].path -replace '/', '\')
    $largeBuffer = New-Object byte[] (1024 * 1024)
    $appendStream = [System.IO.File]::Open($firstCandidateFull, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    try {
        for ($block = 0; $block -lt 32; $block++) {
            $appendStream.Write($largeBuffer, 0, $largeBuffer.Length)
        }
    }
    finally {
        $appendStream.Dispose()
    }
    $copyFailureManifest.candidates[0].sha256 = (Get-FileHash -LiteralPath $firstCandidateFull -Algorithm SHA256).Hash
    $copyFailureManifest.candidates[0].bytes = (Get-Item -LiteralPath $firstCandidateFull).Length
    Save-Manifest $copyFailureFixture.ManifestPath $copyFailureManifest
    $copyFailureSourceHashes = @{}
    foreach ($candidate in $copyFailureManifest.candidates) {
        $candidateFull = Join-Path $sandboxFull ($candidate.path -replace '/', '\')
        $copyFailureSourceHashes[$candidate.id] = (Get-FileHash -LiteralPath $candidateFull -Algorithm SHA256).Hash
    }

    $copyFailureOutputFull = Join-Path $sandboxFull ($copyFailureManifest.promotion.outputDirectory -replace '/', '\')
    $firstTargetFull = Join-Path $copyFailureOutputFull ([System.IO.Path]::GetFileName($copyFailureManifest.candidates[0].path))
    $secondCandidateFull = Join-Path $sandboxFull ($copyFailureManifest.candidates[1].path -replace '/', '\')
    $secondCandidateBackup = Join-Path $copyFailureFixture.JobRoot 'promotion-fault-source-backup.png'
    Copy-Item -LiteralPath $secondCandidateFull -Destination $secondCandidateBackup
    $watchReadyPath = Join-Path $copyFailureFixture.JobRoot 'promotion-watch-ready.txt'
    $watchInjectedPath = Join-Path $copyFailureFixture.JobRoot 'promotion-watch-injected.txt'
    $promotionInjectionReleasePath = Join-Path $copyFailureFixture.JobRoot 'promotion-watch-release.txt'
    $promotionInjectionJob = Start-Job -ScriptBlock {
        param($FirstTarget, $SecondSource, $ReadyPath, $InjectedPath, $ReleasePath)
        [System.IO.File]::WriteAllText($ReadyPath, 'ready')
        $deadline = [DateTime]::UtcNow.AddSeconds(60)
        while (-not (Test-Path -LiteralPath $FirstTarget)) {
            if ([DateTime]::UtcNow -gt $deadline) { throw 'Timed out waiting for the first promoted target.' }
            Start-Sleep -Milliseconds 2
        }
        Remove-Item -LiteralPath $SecondSource -Force
        [System.IO.File]::WriteAllText($InjectedPath, 'injected')
        while (-not (Test-Path -LiteralPath $ReleasePath)) {
            Start-Sleep -Milliseconds 5
        }
    } -ArgumentList $firstTargetFull, $secondCandidateFull, $watchReadyPath, $watchInjectedPath, $promotionInjectionReleasePath

    $readyDeadline = [DateTime]::UtcNow.AddSeconds(10)
    while (-not (Test-Path -LiteralPath $watchReadyPath -PathType Leaf)) {
        if ([DateTime]::UtcNow -gt $readyDeadline) { throw 'Promotion failure injector did not become ready.' }
        Start-Sleep -Milliseconds 10
    }
    $copyFailureResult = Invoke-Gate -Action 'Promote' -ManifestPath $copyFailureFixture.ManifestPath -ActorMode main
    [System.IO.File]::WriteAllText($promotionInjectionReleasePath, 'release')
    $null = Wait-Job -Job $promotionInjectionJob -Timeout 10
    $injectionOutput = @(Receive-Job -Job $promotionInjectionJob -ErrorAction SilentlyContinue)
    Remove-Job -Job $promotionInjectionJob -Force
    $promotionInjectionJob = $null
    $promotionInjectionReleasePath = $null
    Assert-True ($copyFailureResult.ExitCode -ne 0) ('The injected second-copy failure must make Promote fail.' + "`nGate output:`n" + $copyFailureResult.Output + "`nInjector output:`n" + ($injectionOutput -join "`n"))
    Assert-True (Test-Path -LiteralPath $watchInjectedPath -PathType Leaf) 'The promotion test did not actually inject a failure after the first target was created.'
    Assert-True (-not (Test-Path -LiteralPath $secondCandidateFull)) 'The fault injector did not remove the second temp candidate after promotion began.'
    Copy-Item -LiteralPath $secondCandidateBackup -Destination $secondCandidateFull
    Assert-True (-not (Test-Path -LiteralPath $firstTargetFull)) 'Rollback must remove the already copied first formal file; this assertion would fail if rollback code were absent.'
    Assert-True (-not (Test-Path -LiteralPath $copyFailureOutputFull)) 'A mid-copy promotion failure must remove the entire new formal output directory; this assertion would fail if rollback code were absent.'
    foreach ($candidate in $copyFailureManifest.candidates) {
        $candidateFull = Join-Path $sandboxFull ($candidate.path -replace '/', '\')
        Assert-True (Test-Path -LiteralPath $candidateFull -PathType Leaf) ('A mid-copy failure must preserve temp candidate: ' + $candidate.id)
        Assert-True ((Get-FileHash -LiteralPath $candidateFull -Algorithm SHA256).Hash -eq $copyFailureSourceHashes[$candidate.id]) ('A mid-copy failure changed temp candidate: ' + $candidate.id)
    }

    $concurrentFixture = New-WorkflowFixture -Name 'promote-concurrent-owner' -ScopeMode full -IncludeCandidates -AcceptAllItems -Approve
    $concurrentJobs = @()
    try {
        for ($attempt = 1; $attempt -le 2; $attempt++) {
            $concurrentJobs += Start-Job -ScriptBlock {
                param($GatePath, $ProjectRoot, $ManifestPath)
                $output = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $GatePath -Action Promote -ProjectRoot $ProjectRoot -ManifestPath $ManifestPath -ActorMode main 2>&1)
                [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output -join "`n") }
            } -ArgumentList $gatePath, $sandboxFull, $concurrentFixture.ManifestPath
        }
        $null = Wait-Job -Job $concurrentJobs -Timeout 90
        Assert-True (@($concurrentJobs | Where-Object { $_.State -eq 'Completed' }).Count -eq 2) 'Concurrent promotion attempts must terminate within the bounded wait.'
        $concurrentResults = @(Receive-Job -Job $concurrentJobs)
        Assert-True (@($concurrentResults | Where-Object { $_.ExitCode -eq 0 }).Count -eq 1) 'Exactly one concurrent promotion attempt must own the non-overwrite promotion.'
        Assert-True (@($concurrentResults | Where-Object { $_.ExitCode -ne 0 }).Count -eq 1) 'The losing concurrent promotion attempt must fail closed.'
    }
    finally {
        foreach ($job in @($concurrentJobs)) {
            Stop-Job -Job $job -ErrorAction SilentlyContinue
            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        }
    }
    $concurrentReceipt = Join-Path (Split-Path -Parent $concurrentFixture.ManifestPath) 'promotion-receipt.json'
    Assert-True (Test-Path -LiteralPath $concurrentReceipt -PathType Leaf) 'The losing concurrent promotion attempt must not delete the winner-owned receipt.'
    Assert-GatePasses 'VerifyPromoted' $concurrentFixture.ManifestPath 'The winning concurrent promotion must remain fully verifiable.' 'main'

    foreach ($actor in @('main', 'production')) {
        $promotionFixture = New-WorkflowFixture -Name ('promote-valid-' + $actor) -ScopeMode full -IncludeCandidates -AcceptAllItems -Approve
        Assert-GatePasses 'CheckBeforePromote' $promotionFixture.ManifestPath ('A complete job should pass promotion preflight for ' + $actor + '.') $actor
        $before = Read-Manifest $promotionFixture.ManifestPath
        $expectedHashes = @{}
        foreach ($candidate in $before.candidates) { $expectedHashes[$candidate.id] = $candidate.sha256 }

        Assert-GatePasses 'Promote' $promotionFixture.ManifestPath ('A complete job should promote for ' + $actor + '.') $actor
        $after = Read-Manifest $promotionFixture.ManifestPath
        Assert-True ($after.status -eq 'promoted') 'Successful promotion must set manifest status to promoted.'
        Assert-True ($after.promotion.promoted -eq $true) 'Successful promotion must set promotion.promoted=true.'
        Assert-True (@($after.promotion.files).Count -eq @($after.candidates).Count) 'Promotion must record every accepted output file.'
        $receiptFull = Join-Path (Split-Path -Parent $promotionFixture.ManifestPath) 'promotion-receipt.json'
        Assert-True (Test-Path -LiteralPath $receiptFull -PathType Leaf) 'Promote must create a gate-owned Taobao promotion receipt.'
        $receipt = Get-Content -Raw -Encoding UTF8 -LiteralPath $receiptFull | ConvertFrom-Json
        $expectedEvidenceCount = @($after.product.assets).Count + 1 + (@($after.promptSet.items).Count * 2) + (@($after.candidates).Count * 2) + 1
        Assert-True (@($receipt.evidence).Count -eq $expectedEvidenceCount) 'Promotion receipt must bind every product asset, structure-lock record, design card, clean prompt, candidate image, candidate acceptance record, and full-set acceptance record.'
        foreach ($evidence in @($receipt.evidence)) {
            foreach ($field in @('path', 'kind', 'id', 'sha256')) {
                Assert-True (-not [string]::IsNullOrWhiteSpace([string]$evidence.$field)) ('Promotion receipt evidence is missing field ' + $field + '.')
            }
            Assert-True (-not [System.IO.Path]::IsPathRooted([string]$evidence.path)) 'Promotion receipt evidence paths must be project-relative.'
            Assert-True ([int64]$evidence.bytes -gt 0) 'Promotion receipt evidence byte lengths must be positive.'
            Assert-True ([string]$evidence.sha256 -match '^[A-Fa-f0-9]{64}$') 'Promotion receipt evidence hashes must be SHA-256 values.'
        }
        $verificationResult = Invoke-Gate -Action 'VerifyPromoted' -ManifestPath $promotionFixture.ManifestPath -ActorMode $actor
        Assert-True ($verificationResult.ExitCode -eq 0) ('VerifyPromoted must accept the unchanged gate-promoted Taobao set: ' + $verificationResult.Output)
        $verification = $verificationResult.Output | ConvertFrom-Json
        Assert-True ($verification.verified -eq $true) 'VerifyPromoted must return a machine-readable verified descriptor.'
        Assert-True ($verification.gateKind -eq 'taobao-ecommerce') 'VerifyPromoted returned the wrong gate kind.'
        Assert-True (@($verification.outputs).Count -eq @($after.candidates).Count) 'VerifyPromoted must describe every promoted Taobao output.'
        if ($actor -eq 'main') {
            $promotedRaw = Get-Content -Raw -Encoding UTF8 -LiteralPath $promotionFixture.ManifestPath
            foreach ($invalidScope in @('home_only', 'home_and_detail')) {
                $mutated = $promotedRaw | ConvertFrom-Json
                $mutated.scope.mode = $invalidScope
                Save-Manifest $promotionFixture.ManifestPath $mutated
                $invalidResult = Invoke-Gate -Action 'VerifyPromoted' -ManifestPath $promotionFixture.ManifestPath -ActorMode $actor
                $compactInvalidOutput = $invalidResult.Output -replace '\s', ''
                Assert-True ($invalidResult.ExitCode -ne 0 -and $compactInvalidOutput.Contains('UnsupportedorunconfirmedTaobaoscope')) ("VerifyPromoted must reject illegal scope: $invalidScope")
                [System.IO.File]::WriteAllText($promotionFixture.ManifestPath, $promotedRaw, (New-Object System.Text.UTF8Encoding($false)))
            }

            $mutated = $promotedRaw | ConvertFrom-Json
            $mutated.sellingPoints.items = @()
            Save-Manifest $promotionFixture.ManifestPath $mutated
            $invalidResult = Invoke-Gate -Action 'VerifyPromoted' -ManifestPath $promotionFixture.ManifestPath -ActorMode $actor
            Assert-True ($invalidResult.ExitCode -ne 0) ('VerifyPromoted must reject an empty confirmed selling-point list. Output: ' + $invalidResult.Output)
            [System.IO.File]::WriteAllText($promotionFixture.ManifestPath, $promotedRaw, (New-Object System.Text.UTF8Encoding($false)))

            $artifactManifest = $promotedRaw | ConvertFrom-Json
            $tamperCases = New-Object System.Collections.ArrayList
            foreach ($candidate in @($artifactManifest.candidates)) {
                [void]$tamperCases.Add([pscustomobject]@{ Path = $candidate.acceptancePath; Label = ('candidate acceptance ' + $candidate.id) })
            }
            [void]$tamperCases.Add([pscustomobject]@{ Path = $artifactManifest.setAcceptance.path; Label = 'full-set acceptance' })
            foreach ($promptItem in @($artifactManifest.promptSet.items)) {
                [void]$tamperCases.Add([pscustomobject]@{ Path = $promptItem.cardPath; Label = ('design card ' + $promptItem.id) })
                [void]$tamperCases.Add([pscustomobject]@{ Path = $promptItem.promptPath; Label = ('clean prompt ' + $promptItem.id) })
            }
            foreach ($case in @($tamperCases)) {
                $artifactFull = Join-Path $sandboxFull ($case.Path -replace '/', '\')
                $artifactBytes = [System.IO.File]::ReadAllBytes($artifactFull)
                [System.IO.File]::WriteAllText($artifactFull, ('nonblank replacement for ' + $case.Label), (New-Object System.Text.UTF8Encoding($false)))
                $invalidResult = Invoke-Gate -Action 'VerifyPromoted' -ManifestPath $promotionFixture.ManifestPath -ActorMode $actor
                Assert-True ($invalidResult.ExitCode -ne 0) ('VerifyPromoted must reject nonblank replacement of ' + $case.Label + '. Output: ' + $invalidResult.Output)
                [System.IO.File]::WriteAllBytes($artifactFull, $artifactBytes)
                $restoredResult = Invoke-Gate -Action 'VerifyPromoted' -ManifestPath $promotionFixture.ManifestPath -ActorMode $actor
                Assert-True ($restoredResult.ExitCode -eq 0) ('VerifyPromoted must accept restored ' + $case.Label + '. Output: ' + $restoredResult.Output)
            }

            $artifactCases = @(
                [pscustomobject]@{ Path = $artifactManifest.promptSet.items[0].cardPath; Marker = 'Design card'; Label = 'design card' },
                [pscustomobject]@{ Path = $artifactManifest.promptSet.items[0].promptPath; Marker = 'Clean prompt'; Label = 'clean prompt' },
                [pscustomobject]@{ Path = $artifactManifest.candidates[0].acceptancePath; Marker = 'Candidate acceptance record'; Label = 'candidate acceptance' },
                [pscustomobject]@{ Path = $artifactManifest.setAcceptance.path; Marker = 'Full-set acceptance record'; Label = 'set acceptance' }
            )
            foreach ($case in $artifactCases) {
                $artifactFull = Join-Path $sandboxFull ($case.Path -replace '/', '\')
                $artifactBytes = [System.IO.File]::ReadAllBytes($artifactFull)
                Remove-Item -LiteralPath $artifactFull -Force
                $invalidResult = Invoke-Gate -Action 'VerifyPromoted' -ManifestPath $promotionFixture.ManifestPath -ActorMode $actor
                Assert-True ($invalidResult.ExitCode -ne 0 -and $invalidResult.Output.Contains($case.Marker)) ('VerifyPromoted must reject missing ' + $case.Label + ' evidence.')
                [System.IO.File]::WriteAllBytes($artifactFull, $artifactBytes)
            }

            $receiptRaw = Get-Content -Raw -Encoding UTF8 -LiteralPath $receiptFull
            $legacyReceipt = $receiptRaw | ConvertFrom-Json
            $legacyReceipt.PSObject.Properties.Remove('evidence')
            [System.IO.File]::WriteAllText($receiptFull, ($legacyReceipt | ConvertTo-Json -Depth 20), (New-Object System.Text.UTF8Encoding($false)))
            $legacyResult = Invoke-Gate -Action 'VerifyPromoted' -ManifestPath $promotionFixture.ManifestPath -ActorMode $actor
            Assert-True ($legacyResult.ExitCode -ne 0 -and $legacyResult.Output.Contains('evidence')) 'A legacy Taobao receipt without evidence[] must fail closed and require a new Promote.'
            [System.IO.File]::WriteAllText($receiptFull, $receiptRaw, (New-Object System.Text.UTF8Encoding($false)))

            $outputToTamper = Join-Path $sandboxFull ($after.promotion.files[0].path -replace '/', '\')
            $outputBytes = [System.IO.File]::ReadAllBytes($outputToTamper)
            [System.IO.File]::WriteAllText($outputToTamper, 'tampered promoted output')
            $invalidResult = Invoke-Gate -Action 'VerifyPromoted' -ManifestPath $promotionFixture.ManifestPath -ActorMode $actor
            Assert-True ($invalidResult.ExitCode -ne 0 -and $invalidResult.Output.Contains('integrity differs')) 'VerifyPromoted must reject a promoted output hash or byte mismatch.'
            [System.IO.File]::WriteAllBytes($outputToTamper, $outputBytes)
        }
        foreach ($file in $after.promotion.files) {
            $outputFull = Join-Path $sandboxFull ($file.path -replace '/', '\')
            Assert-True (Test-Path -LiteralPath $outputFull -PathType Leaf) ('Promoted output is missing: ' + $file.path)
            Assert-True ((Get-FileHash -LiteralPath $outputFull -Algorithm SHA256).Hash -eq $expectedHashes[$file.id]) ('Promoted output hash mismatch: ' + $file.id)
            Assert-True ($file.sha256 -eq $expectedHashes[$file.id]) ('Recorded promotion hash mismatch: ' + $file.id)
        }
        foreach ($candidate in $after.candidates) {
            Assert-True (Test-Path -LiteralPath (Join-Path $sandboxFull ($candidate.path -replace '/', '\')) -PathType Leaf) 'Promotion must preserve all temp candidates.'
        }
        Remove-Item -LiteralPath $receiptFull -Force
        Assert-GateFails 'VerifyPromoted' $promotionFixture.ManifestPath 'A fully populated promoted manifest without the gate-owned receipt must be rejected.' $actor
        Assert-GateFails 'Promote' $promotionFixture.ManifestPath 'A second promotion must refuse same-name overwrite.' $actor
    }

    Write-Output 'PASS: Taobao workflow gate accepted valid sequence and rejected unsafe states.'
}
finally {
    if ($promotionInjectionReleasePath) {
        try { [System.IO.File]::WriteAllText($promotionInjectionReleasePath, 'release') } catch {}
    }
    if ($promotionInjectionJob) {
        Stop-Job -Job $promotionInjectionJob -ErrorAction SilentlyContinue
        Remove-Job -Job $promotionInjectionJob -Force -ErrorAction SilentlyContinue
    }
    foreach ($outsideFile in $outsideFiles) {
        if (Test-Path -LiteralPath $outsideFile -PathType Leaf) {
            $verifiedOutside = [System.IO.Path]::GetFullPath($outsideFile)
            Assert-True ($verifiedOutside.StartsWith($projectTempFull, [System.StringComparison]::OrdinalIgnoreCase)) 'Refusing to remove an outside fixture beyond project temp.'
            Remove-Item -LiteralPath $verifiedOutside -Force
        }
    }
    if (Test-Path -LiteralPath $sandboxFull) {
        $verified = [System.IO.Path]::GetFullPath($sandboxFull)
        Assert-True ($verified.StartsWith($projectTempFull, [System.StringComparison]::OrdinalIgnoreCase)) 'Refusing to remove a workflow test sandbox outside project temp.'
        Remove-Item -LiteralPath $verified -Recurse -Force
    }
}
