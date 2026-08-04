param()

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$gatePath = Join-Path $projectRoot 'scripts\taobao_workflow_gate.ps1'
$sandbox = Join-Path $projectRoot ('temp\taobao-upload-gate-test-' + [guid]::NewGuid().ToString('N'))
$sandboxFull = [System.IO.Path]::GetFullPath($sandbox)
$projectTempFull = [System.IO.Path]::GetFullPath((Join-Path $projectRoot 'temp')) + [System.IO.Path]::DirectorySeparatorChar
$outsideFiles = New-Object System.Collections.ArrayList

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

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

function Save-Manifest {
    param([string]$Path, [object]$Manifest)
    $Manifest | ConvertTo-Json -Depth 20 | Set-Content -Encoding UTF8 -LiteralPath $Path
}

function Read-Manifest {
    param([string]$Path)
    return Get-Content -Raw -Encoding UTF8 -LiteralPath $Path | ConvertFrom-Json
}

function New-UploadFixture {
    param([string]$Name)

    $jobId = 'upload-' + $Name
    $jobRelative = 'temp/taobao-jobs/' + $jobId
    $jobRoot = Join-Path $sandboxFull ($jobRelative -replace '/', '\')
    $assetRelative = $jobRelative + '/assets/product.png'
    $assetFull = Join-Path $sandboxFull ($assetRelative -replace '/', '\')
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $assetFull) | Out-Null
    [System.IO.File]::WriteAllBytes($assetFull, [Convert]::FromBase64String('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII='))
    $assetHash = (Get-FileHash -LiteralPath $assetFull -Algorithm SHA256).Hash
    $assetBytes = (Get-Item -LiteralPath $assetFull).Length
    $manifestPath = Join-Path $jobRoot 'manifest.json'
    $manifest = [ordered]@{
        schemaVersion = '1.0'
        jobId = $jobId
        originThreadMode = 'test'
        status = 'assets_archived'
        scope = [ordered]@{ mode = 'full'; homeRequired = $true; detailRequired = $true }
        product = [ordered]@{
            name = 'Synthetic upload product'
            assets = @([ordered]@{
                id = 'A01'
                path = $assetRelative
                sourcePath = 'synthetic://fixture/product.png'
                fileName = 'product.png'
                bytes = $assetBytes
                sha256 = $assetHash
                authorizationConfirmed = $true
                authorizationStatement = 'Authorized synthetic upload fixture'
            })
            facts = @()
        }
        sellingPoints = [ordered]@{ confirmed = $false; confirmationStatement = ''; confirmedAt = ''; items = @() }
        promptSet = [ordered]@{
            confirmed = $false
            confirmationStatement = ''
            confirmedAt = ''
            styleLock = [ordered]@{}
            structureLock = [ordered]@{}
            items = @([ordered]@{ id = 'H01'; version = 'V1'; proofAddsNewInformation = $true })
        }
        assetTransfer = [ordered]@{
            required = $true
            assetPath = $assetRelative
            expectedSha256 = $assetHash
            itemId = 'H01'
            promptVersion = 'V1'
            verifiedAt = '2026-07-16T12:01:00+08:00'
            chatSessionReference = 'synthetic://upload/session'
            conversationAction = 'opened_new'
            authorizationConfirmed = $true
            destination = 'ChatGPT web via QQ Browser'
            method = ''
            clipboardPrepared = $false
            thumbnailVerified = $false
            verifiedAssetName = ''
            pathTextEntered = $false
            status = 'authorized'
            failureReason = ''
        }
        generation = [ordered]@{
            currentItemId = 'H01'
            channel = 'chatgpt_web_qq'
            channelStatus = 'default'
            channelAuthorization = [ordered]@{}
            chatSessionPolicy = 'single_conversation_full_set'
            chatSessionReference = 'synthetic://upload/session'
            chatSessionOpenedForItemId = 'H01'
            newConversationCount = 1
            styleAnchor = [ordered]@{ itemId = 'H01'; confirmed = $false; confirmationStatement = ''; confirmedAt = '' }
        }
        candidates = @()
        setAcceptance = [ordered]@{ path = ''; passed = $false; checks = [ordered]@{} }
        approval = [ordered]@{ approved = $false; statement = ''; approvedAt = '' }
        promotion = [ordered]@{ outputDirectory = ''; promoted = $false; promotedAt = ''; promotedBy = ''; files = @() }
        history = @([ordered]@{ at = '2026-07-16T12:00:00+08:00'; actor = 'test'; action = 'fixture_created'; itemId = ''; version = 'V1'; statement = 'Synthetic upload fixture' })
    }
    Save-Manifest -Path $manifestPath -Manifest $manifest
    return [pscustomobject]@{ ManifestPath = $manifestPath; AssetPath = $assetFull }
}

function Assert-GateFails {
    param([string]$Action, [string]$ManifestPath, [string]$Message)
    $result = Invoke-Gate -Action $Action -ManifestPath $ManifestPath
    Assert-True ($result.ExitCode -ne 0) ($Message + "`nGate output:`n" + $result.Output)
}

function Assert-GatePasses {
    param([string]$Action, [string]$ManifestPath, [string]$Message)
    $result = Invoke-Gate -Action $Action -ManifestPath $ManifestPath
    Assert-True ($result.ExitCode -eq 0) ($Message + "`nGate output:`n" + $result.Output)
}

New-Item -ItemType Directory -Force -Path (Join-Path $sandboxFull 'temp\taobao-jobs'), (Join-Path $sandboxFull 'outputs'), (Join-Path $sandboxFull 'templates') | Out-Null
foreach ($templateName in @('TAOBAO_HOME_IMAGE_PROMPT.md', 'TAOBAO_HOME_IMAGE_PROMPT.lock.json', 'TAOBAO_DETAIL_IMAGE_PROMPT.md', 'TAOBAO_DETAIL_IMAGE_PROMPT.lock.json')) {
    Copy-Item -LiteralPath (Join-Path $projectRoot ('templates\' + $templateName)) -Destination (Join-Path $sandboxFull ('templates\' + $templateName))
}

try {
    $smokeFixture = New-UploadFixture -Name 'fixture-smoke'
    Assert-True (Test-Path -LiteralPath $smokeFixture.ManifestPath -PathType Leaf) 'Upload test fixture manifest was not initialized.'
    Assert-True (Test-Path -LiteralPath $smokeFixture.AssetPath -PathType Leaf) 'Upload test fixture asset was not initialized.'
    $smokeManifest = Read-Manifest -Path $smokeFixture.ManifestPath
    Assert-True ((Get-FileHash -LiteralPath $smokeFixture.AssetPath -Algorithm SHA256).Hash -eq $smokeManifest.assetTransfer.expectedSha256) 'Upload test fixture hash is inconsistent.'
    Write-Output ('FIXTURE_READY: ' + $smokeFixture.ManifestPath)
    Assert-True (Test-Path -LiteralPath $gatePath -PathType Leaf) ('TARGET_GATE_MISSING: expected gate script does not exist: ' + $gatePath)

    $authorized = New-UploadFixture -Name 'authorized'
    Assert-GatePasses 'CheckBeforeUpload' $authorized.ManifestPath 'An authorized in-job asset with matching hash should pass before-upload validation.'

    $authorizationWrongType = New-UploadFixture -Name 'authorization-string'
    $manifest = Read-Manifest $authorizationWrongType.ManifestPath
    $manifest.assetTransfer.authorizationConfirmed = 'true'
    Save-Manifest $authorizationWrongType.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeUpload' $authorizationWrongType.ManifestPath 'assetTransfer.authorizationConfirmed must be a JSON Boolean, not the string "true".'

    $productAssetsNotArray = New-UploadFixture -Name 'product-assets-object'
    $manifest = Read-Manifest $productAssetsNotArray.ManifestPath
    $manifest.product.assets = $manifest.product.assets[0]
    Save-Manifest $productAssetsNotArray.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeUpload' $productAssetsNotArray.ManifestPath 'product.assets must remain a JSON array even when it contains one asset.'

    $assetJunction = New-UploadFixture -Name 'asset-junction'
    $manifest = Read-Manifest $assetJunction.ManifestPath
    $assetJunctionJobRoot = Split-Path -Parent $assetJunction.ManifestPath
    $junctionExternal = Join-Path $sandboxFull ('temp\junction-external-asset-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $junctionExternal | Out-Null
    $junctionAssetFull = Join-Path $junctionExternal 'product.png'
    Copy-Item -LiteralPath $assetJunction.AssetPath -Destination $junctionAssetFull
    $assetJunctionPath = Join-Path $assetJunctionJobRoot 'assets\external-link'
    try {
        New-Item -ItemType Junction -Path $assetJunctionPath -Target $junctionExternal -ErrorAction Stop | Out-Null
    }
    catch {
        throw ('JUNCTION_TEST_BLOCKED: unable to create the required asset junction: ' + $_.Exception.Message)
    }
    Assert-True ((((Get-Item -LiteralPath $assetJunctionPath -Force).Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)) 'JUNCTION_TEST_BLOCKED: asset junction was not created as a reparse point.'
    $junctionRelative = 'temp/taobao-jobs/' + $manifest.jobId + '/assets/external-link/product.png'
    $manifest.product.assets[0].path = $junctionRelative
    $manifest.product.assets[0].bytes = (Get-Item -LiteralPath $junctionAssetFull).Length
    $manifest.product.assets[0].sha256 = (Get-FileHash -LiteralPath $junctionAssetFull -Algorithm SHA256).Hash
    $manifest.assetTransfer.assetPath = $junctionRelative
    $manifest.assetTransfer.expectedSha256 = $manifest.product.assets[0].sha256
    Save-Manifest $assetJunction.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeUpload' $assetJunction.ManifestPath 'An archived asset reached through a junction that leaves the task directory must fail.'

    $unauthorized = New-UploadFixture -Name 'unauthorized'
    $manifest = Read-Manifest $unauthorized.ManifestPath
    $manifest.assetTransfer.authorizationConfirmed = $false
    $manifest.product.assets[0].authorizationConfirmed = $false
    Save-Manifest $unauthorized.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeUpload' $unauthorized.ManifestPath 'An unauthorized asset must fail before upload.'

    $hashMismatch = New-UploadFixture -Name 'hash-mismatch'
    $manifest = Read-Manifest $hashMismatch.ManifestPath
    $manifest.assetTransfer.expectedSha256 = ('0' * 64)
    Save-Manifest $hashMismatch.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeUpload' $hashMismatch.ManifestPath 'A mismatched asset hash must fail before upload.'

    $bytesMismatch = New-UploadFixture -Name 'bytes-mismatch'
    $manifest = Read-Manifest $bytesMismatch.ManifestPath
    $manifest.product.assets[0].bytes = [int64]$manifest.product.assets[0].bytes + 1
    Save-Manifest $bytesMismatch.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeUpload' $bytesMismatch.ManifestPath 'A mismatched product asset byte count must fail before upload.'

    $wrongDestination = New-UploadFixture -Name 'wrong-destination'
    $manifest = Read-Manifest $wrongDestination.ManifestPath
    $manifest.assetTransfer.destination = 'Unapproved third-party website'
    Save-Manifest $wrongDestination.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeUpload' $wrongDestination.ManifestPath 'An upload destination other than the approved ChatGPT web target must fail.'

    $pathEscape = New-UploadFixture -Name 'path-escape'
    $manifest = Read-Manifest $pathEscape.ManifestPath
    $outsideName = 'taobao-upload-outside-' + [guid]::NewGuid().ToString('N') + '.png'
    $outsidePath = Join-Path (Split-Path -Parent $sandboxFull) $outsideName
    Copy-Item -LiteralPath $pathEscape.AssetPath -Destination $outsidePath
    [void]$outsideFiles.Add($outsidePath)
    $outsideHash = (Get-FileHash -LiteralPath $outsidePath -Algorithm SHA256).Hash
    $outsideBytes = (Get-Item -LiteralPath $outsidePath).Length
    $manifest.product.assets[0].path = '../' + $outsideName
    $manifest.product.assets[0].fileName = $outsideName
    $manifest.product.assets[0].bytes = $outsideBytes
    $manifest.product.assets[0].sha256 = $outsideHash
    $manifest.assetTransfer.assetPath = '../' + $outsideName
    $manifest.assetTransfer.expectedSha256 = $outsideHash
    Save-Manifest $pathEscape.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeUpload' $pathEscape.ManifestPath 'A real, hash-valid asset outside the project root must fail before upload.'

    $foreignAssetFixture = New-UploadFixture -Name 'foreign-source'
    $foreignManifest = Read-Manifest $foreignAssetFixture.ManifestPath
    $crossJobAsset = New-UploadFixture -Name 'cross-job-reference'
    $manifest = Read-Manifest $crossJobAsset.ManifestPath
    $foreignAsset = $foreignManifest.product.assets[0]
    $foreignAssetFull = Join-Path $sandboxFull ($foreignAsset.path -replace '/', '\')
    Assert-True (Test-Path -LiteralPath $foreignAssetFull -PathType Leaf) 'Cross-job upload fixture asset was not created.'
    Assert-True ((Get-FileHash -LiteralPath $foreignAssetFull -Algorithm SHA256).Hash -eq $foreignAsset.sha256) 'Cross-job upload fixture hash is inconsistent.'
    Assert-True ((Get-Item -LiteralPath $foreignAssetFull).Length -eq $foreignAsset.bytes) 'Cross-job upload fixture byte count is inconsistent.'
    $manifest.product.assets[0].path = $foreignAsset.path
    $manifest.product.assets[0].fileName = $foreignAsset.fileName
    $manifest.product.assets[0].bytes = $foreignAsset.bytes
    $manifest.product.assets[0].sha256 = $foreignAsset.sha256
    $manifest.assetTransfer.assetPath = $foreignAsset.path
    $manifest.assetTransfer.expectedSha256 = $foreignAsset.sha256
    Save-Manifest $crossJobAsset.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeUpload' $crossJobAsset.ManifestPath 'A real asset owned by another Taobao job must be rejected before upload.'

    $pathAlreadyEntered = New-UploadFixture -Name 'path-before-upload'
    $manifest = Read-Manifest $pathAlreadyEntered.ManifestPath
    $manifest.assetTransfer.pathTextEntered = $true
    Save-Manifest $pathAlreadyEntered.ManifestPath $manifest
    Assert-GateFails 'CheckBeforeUpload' $pathAlreadyEntered.ManifestPath 'A local path entered as web text must fail before upload.'

    $afterValid = New-UploadFixture -Name 'after-valid'
    $manifest = Read-Manifest $afterValid.ManifestPath
    $manifest.assetTransfer.method = 'clipboard_file_copy'
    $manifest.assetTransfer.clipboardPrepared = $true
    $manifest.assetTransfer.thumbnailVerified = $true
    $manifest.assetTransfer.verifiedAssetName = 'product.png'
    $manifest.assetTransfer.status = 'verified'
    Save-Manifest $afterValid.ManifestPath $manifest
    Assert-GatePasses 'CheckAfterUpload' $afterValid.ManifestPath 'A verified file-body clipboard upload should pass after-upload validation.'

    $wrongMethod = New-UploadFixture -Name 'wrong-method'
    $manifest = Read-Manifest $wrongMethod.ManifestPath
    $manifest.assetTransfer.method = 'native_file_picker'
    $manifest.assetTransfer.clipboardPrepared = $true
    $manifest.assetTransfer.thumbnailVerified = $true
    $manifest.assetTransfer.verifiedAssetName = 'product.png'
    Save-Manifest $wrongMethod.ManifestPath $manifest
    Assert-GateFails 'CheckAfterUpload' $wrongMethod.ManifestPath 'A non-clipboard upload method must fail after upload.'

    $clipboardNotPrepared = New-UploadFixture -Name 'clipboard-not-prepared'
    $manifest = Read-Manifest $clipboardNotPrepared.ManifestPath
    $manifest.assetTransfer.method = 'clipboard_file_copy'
    $manifest.assetTransfer.clipboardPrepared = $false
    $manifest.assetTransfer.thumbnailVerified = $true
    $manifest.assetTransfer.verifiedAssetName = 'product.png'
    Save-Manifest $clipboardNotPrepared.ManifestPath $manifest
    Assert-GateFails 'CheckAfterUpload' $clipboardNotPrepared.ManifestPath 'An unprepared clipboard transfer must fail after upload.'

    $noThumbnail = New-UploadFixture -Name 'no-thumbnail'
    $manifest = Read-Manifest $noThumbnail.ManifestPath
    $manifest.assetTransfer.method = 'clipboard_file_copy'
    $manifest.assetTransfer.clipboardPrepared = $true
    $manifest.assetTransfer.thumbnailVerified = $false
    $manifest.assetTransfer.verifiedAssetName = ''
    Save-Manifest $noThumbnail.ManifestPath $manifest
    Assert-GateFails 'CheckAfterUpload' $noThumbnail.ManifestPath 'An upload without a verified thumbnail must fail.'

    $wrongThumbnail = New-UploadFixture -Name 'wrong-thumbnail'
    $manifest = Read-Manifest $wrongThumbnail.ManifestPath
    $manifest.assetTransfer.method = 'clipboard_file_copy'
    $manifest.assetTransfer.clipboardPrepared = $true
    $manifest.assetTransfer.thumbnailVerified = $true
    $manifest.assetTransfer.verifiedAssetName = 'wrong-product.png'
    Save-Manifest $wrongThumbnail.ManifestPath $manifest
    Assert-GateFails 'CheckAfterUpload' $wrongThumbnail.ManifestPath 'A thumbnail whose filename does not match the asset must fail.'

    $pathLeak = New-UploadFixture -Name 'path-leak'
    $manifest = Read-Manifest $pathLeak.ManifestPath
    $manifest.assetTransfer.method = 'clipboard_file_copy'
    $manifest.assetTransfer.clipboardPrepared = $true
    $manifest.assetTransfer.thumbnailVerified = $true
    $manifest.assetTransfer.verifiedAssetName = 'product.png'
    $manifest.assetTransfer.pathTextEntered = $true
    Save-Manifest $pathLeak.ManifestPath $manifest
    Assert-GateFails 'CheckAfterUpload' $pathLeak.ManifestPath 'An upload that entered a local path as text must fail.'

    Write-Output 'PASS: Taobao upload gate accepted verified clipboard transfer and rejected unsafe states.'
}
finally {
    foreach ($outsideFile in $outsideFiles) {
        if (Test-Path -LiteralPath $outsideFile -PathType Leaf) {
            $verifiedOutside = [System.IO.Path]::GetFullPath($outsideFile)
            Assert-True ($verifiedOutside.StartsWith($projectTempFull, [System.StringComparison]::OrdinalIgnoreCase)) 'Refusing to remove an outside upload fixture beyond project temp.'
            Assert-True (-not $verifiedOutside.StartsWith(([System.IO.Path]::GetFullPath($sandboxFull) + [System.IO.Path]::DirectorySeparatorChar), [System.StringComparison]::OrdinalIgnoreCase)) 'Expected outside upload fixture is unexpectedly inside the sandbox.'
            Remove-Item -LiteralPath $verifiedOutside -Force
        }
    }
    if (Test-Path -LiteralPath $sandboxFull) {
        $verified = [System.IO.Path]::GetFullPath($sandboxFull)
        Assert-True ($verified.StartsWith($projectTempFull, [System.StringComparison]::OrdinalIgnoreCase)) 'Refusing to remove an upload test sandbox outside project temp.'
        Remove-Item -LiteralPath $verified -Recurse -Force
    }
}
