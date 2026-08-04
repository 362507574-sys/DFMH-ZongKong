param()

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$scriptPath = Join-Path $projectRoot 'scripts\new_taobao_ecommerce_job.ps1'
$templatePath = Join-Path $projectRoot 'templates\TAOBAO_ECOMMERCE_JOB.json'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Invoke-Initializer {
    param(
        [string]$JobId,
        [string]$Scope,
        [string]$OriginThreadMode = 'test'
    )

    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $scriptPath `
            -ProjectRoot $script:sandboxFull `
            -JobId $JobId `
            -Scope $Scope `
            -OriginThreadMode $OriginThreadMode 2>&1)
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

function Invoke-InitializerWithoutProjectRoot {
    param(
        [Parameter(Mandatory = $true)][string]$CopiedScriptPath,
        [Parameter(Mandatory = $true)][string]$JobId,
        [Parameter(Mandatory = $true)][string]$Scope,
        [string]$OriginThreadMode = 'test'
    )

    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $CopiedScriptPath `
            -JobId $JobId `
            -Scope $Scope `
            -OriginThreadMode $OriginThreadMode 2>&1)
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

if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
    throw 'Missing Taobao job initialization script: scripts/new_taobao_ecommerce_job.ps1'
}
if (-not (Test-Path -LiteralPath $templatePath -PathType Leaf)) {
    throw 'Missing Taobao job manifest template.'
}

$sandbox = Join-Path $projectRoot ('temp\taobao-init-test-' + [guid]::NewGuid().ToString('N'))
$sandboxFull = [System.IO.Path]::GetFullPath($sandbox)
$projectTempFull = [System.IO.Path]::GetFullPath((Join-Path $projectRoot 'temp')) + [System.IO.Path]::DirectorySeparatorChar
if (-not $sandboxFull.StartsWith($projectTempFull, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Refusing to create Taobao initialization test sandbox outside project temp.'
}

$templateDirectory = Join-Path $sandboxFull 'templates'
$copiedScriptDirectory = Join-Path $sandboxFull 'scripts'
New-Item -ItemType Directory -Force -Path $templateDirectory, $copiedScriptDirectory | Out-Null
Copy-Item -LiteralPath $templatePath -Destination (Join-Path $templateDirectory 'TAOBAO_ECOMMERCE_JOB.json')
Copy-Item -LiteralPath $scriptPath -Destination (Join-Path $copiedScriptDirectory 'new_taobao_ecommerce_job.ps1')

try {
    $copiedScriptPath = Join-Path $copiedScriptDirectory 'new_taobao_ecommerce_job.ps1'
    $defaultRootResult = Invoke-InitializerWithoutProjectRoot -CopiedScriptPath $copiedScriptPath -JobId 'default-root-job-001' -Scope 'full' -OriginThreadMode 'main'
    Assert-True ($defaultRootResult.ExitCode -eq 0) ('The real entry point failed when ProjectRoot was omitted: ' + $defaultRootResult.Output)
    try {
        $defaultRootEvidence = $defaultRootResult.Output | ConvertFrom-Json
    }
    catch {
        throw ('Default-root initializer output is not valid JSON: ' + $defaultRootResult.Output)
    }
    $defaultRootManifest = Join-Path $sandboxFull 'temp\taobao-jobs\default-root-job-001\manifest.json'
    Assert-True ($defaultRootEvidence.created -eq $true) 'Default-root initialization did not report created=true.'
    Assert-True ([System.IO.Path]::GetFullPath([string]$defaultRootEvidence.manifestPath) -eq [System.IO.Path]::GetFullPath($defaultRootManifest)) 'Default-root initialization resolved the wrong project directory.'
    Assert-True (Test-Path -LiteralPath $defaultRootManifest -PathType Leaf) 'Default-root initialization did not create its manifest.'

    $cases = @(
        [pscustomobject]@{ JobId = 'home-job-001'; Scope = 'home'; Origin = 'main'; Anchor = 'H01'; Home = $true; Detail = $false },
        [pscustomobject]@{ JobId = 'detail-job-001'; Scope = 'detail'; Origin = 'test'; Anchor = 'D01'; Home = $false; Detail = $true },
        [pscustomobject]@{ JobId = 'full-job-001'; Scope = 'full'; Origin = 'production'; Anchor = 'H01'; Home = $true; Detail = $true }
    )

    $requiredDirectories = @(
        'assets',
        'benchmark',
        'prompts\home',
        'prompts\detail',
        'candidates\home',
        'candidates\detail',
        'acceptance'
    )

    foreach ($case in $cases) {
        $result = Invoke-Initializer -JobId $case.JobId -Scope $case.Scope -OriginThreadMode $case.Origin
        Assert-True ($result.ExitCode -eq 0) ("Valid initialization failed for {0}: {1}" -f $case.Scope, $result.Output)

        try {
            $evidence = $result.Output | ConvertFrom-Json
        }
        catch {
            throw ("Initializer output is not valid JSON for {0}: {1}" -f $case.Scope, $result.Output)
        }

        Assert-True ($evidence.created -eq $true) 'Initializer JSON must report created=true.'
        Assert-True ($evidence.jobId -eq $case.JobId) 'Initializer JSON returned the wrong jobId.'

        $jobRoot = Join-Path $sandboxFull ('temp\taobao-jobs\' + $case.JobId)
        $manifestPath = Join-Path $jobRoot 'manifest.json'
        Assert-True ([System.IO.Path]::GetFullPath([string]$evidence.manifestPath) -eq [System.IO.Path]::GetFullPath($manifestPath)) 'Initializer JSON returned the wrong manifestPath.'
        Assert-True (Test-Path -LiteralPath $manifestPath -PathType Leaf) 'Initialized manifest is missing.'

        foreach ($directory in $requiredDirectories) {
            Assert-True (Test-Path -LiteralPath (Join-Path $jobRoot $directory) -PathType Container) ("Missing fixed job directory: {0}" -f $directory)
        }

        try {
            $manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $manifestPath | ConvertFrom-Json
        }
        catch {
            throw ("Initialized manifest is not valid JSON: {0}" -f $manifestPath)
        }

        Assert-True ($manifest.jobId -eq $case.JobId) 'Manifest jobId does not match the input.'
        Assert-True ($manifest.scope.mode -eq $case.Scope) 'Manifest scope.mode does not match the input.'
        Assert-True ($manifest.scope.homeRequired -eq $case.Home) 'Manifest scope.homeRequired is incorrect.'
        Assert-True ($manifest.scope.detailRequired -eq $case.Detail) 'Manifest scope.detailRequired is incorrect.'
        Assert-True ($manifest.originThreadMode -eq $case.Origin) 'Manifest originThreadMode does not match the input.'
        Assert-True ($manifest.generation.styleAnchor.itemId -eq $case.Anchor) 'Manifest style anchor does not match the selected scope.'
        Assert-True (@(Get-ChildItem -LiteralPath $jobRoot -Filter 'manifest.json.tmp*' -Force).Count -eq 0) 'A successful initialization left a temporary manifest file behind.'
    }

    foreach ($invalidJobId in @('..\escape', 'bad/name', '', '含空格')) {
        $result = Invoke-Initializer -JobId $invalidJobId -Scope 'home'
        Assert-True ($result.ExitCode -ne 0) ("Unsafe or invalid jobId was accepted: '{0}'" -f $invalidJobId)
    }

    $invalidScope = Invoke-Initializer -JobId 'invalid-scope-job' -Scope 'poster'
    Assert-True ($invalidScope.ExitCode -ne 0) 'A scope outside home/detail/full was accepted.'

    $reservedDeviceNames = @('con','prn','aux','nul','com1','com2','com3','com4','com5','com6','com7','com8','com9','lpt1','lpt2','lpt3','lpt4','lpt5','lpt6','lpt7','lpt8','lpt9')
    foreach ($reservedName in $reservedDeviceNames) {
        $reserved = Invoke-Initializer -JobId $reservedName -Scope 'home'
        Assert-True ($reserved.ExitCode -ne 0) ("A reserved Windows device name was accepted: {0}" -f $reservedName)
        Assert-True ($reserved.Output -match 'reserved Windows device name') ("Reserved name did not receive an explicit deterministic rejection: {0}. Output: {1}" -f $reservedName, $reserved.Output)
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $sandboxFull ('temp\taobao-jobs\' + $reservedName)))) ("Reserved name left a task path behind: {0}" -f $reservedName)
    }

    $firstManifest = Join-Path $sandboxFull 'temp\taobao-jobs\home-job-001\manifest.json'
    $beforeHash = (Get-FileHash -LiteralPath $firstManifest -Algorithm SHA256).Hash
    $duplicate = Invoke-Initializer -JobId 'home-job-001' -Scope 'detail' -OriginThreadMode 'production'
    Assert-True ($duplicate.ExitCode -ne 0) 'A duplicate jobId was allowed to overwrite an existing task.'
    $afterHash = (Get-FileHash -LiteralPath $firstManifest -Algorithm SHA256).Hash
    Assert-True ($afterHash -eq $beforeHash) 'Duplicate initialization changed the existing manifest.'

    $failureSandbox = Join-Path $projectRoot ('temp\taobao-init-failure-test-' + [guid]::NewGuid().ToString('N'))
    $failureSandboxFull = [System.IO.Path]::GetFullPath($failureSandbox)
    Assert-True ($failureSandboxFull.StartsWith($projectTempFull, [System.StringComparison]::OrdinalIgnoreCase)) 'Refusing to create failure-path sandbox outside project temp.'
    try {
        $failureTemplateDirectory = Join-Path $failureSandboxFull 'templates'
        $failureJobsRoot = Join-Path $failureSandboxFull 'temp\taobao-jobs'
        $sentinelDirectory = Join-Path $failureJobsRoot 'sentinel-neighbor'
        $sentinelFile = Join-Path $sentinelDirectory 'keep.txt'
        New-Item -ItemType Directory -Force -Path $failureTemplateDirectory, $sentinelDirectory | Out-Null
        Set-Content -LiteralPath (Join-Path $failureTemplateDirectory 'TAOBAO_ECOMMERCE_JOB.json') -Encoding UTF8 -Value '{"schemaVersion":"1.0","scope":'
        Set-Content -LiteralPath $sentinelFile -Encoding UTF8 -Value 'sentinel-must-remain'
        $sentinelHashBefore = (Get-FileHash -LiteralPath $sentinelFile -Algorithm SHA256).Hash

        $previousSandbox = $script:sandboxFull
        $script:sandboxFull = $failureSandboxFull
        try {
            $failedWrite = Invoke-Initializer -JobId 'cleanup-job-001' -Scope 'full'
        }
        finally {
            $script:sandboxFull = $previousSandbox
        }

        Assert-True ($failedWrite.ExitCode -ne 0) 'A damaged manifest template unexpectedly initialized a task.'
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $failureJobsRoot 'cleanup-job-001'))) 'A post-creation failure left its new job directory behind.'
        Assert-True (Test-Path -LiteralPath $sentinelDirectory -PathType Container) 'Failure cleanup removed the adjacent sentinel directory.'
        Assert-True (Test-Path -LiteralPath $sentinelFile -PathType Leaf) 'Failure cleanup removed the adjacent sentinel file.'
        Assert-True ((Get-FileHash -LiteralPath $sentinelFile -Algorithm SHA256).Hash -eq $sentinelHashBefore) 'Failure cleanup changed the adjacent sentinel file.'
    }
    finally {
        if (Test-Path -LiteralPath $failureSandboxFull) {
            $verifiedFailureSandbox = [System.IO.Path]::GetFullPath($failureSandboxFull)
            if (-not $verifiedFailureSandbox.StartsWith($projectTempFull, [System.StringComparison]::OrdinalIgnoreCase)) {
                throw 'Refusing to remove a failure-path sandbox outside project temp.'
            }
            Remove-Item -LiteralPath $verifiedFailureSandbox -Recurse -Force
        }
    }

    $jobsRoot = [System.IO.Path]::GetFullPath((Join-Path $sandboxFull 'temp\taobao-jobs')) + [System.IO.Path]::DirectorySeparatorChar
    foreach ($directory in Get-ChildItem -LiteralPath (Join-Path $sandboxFull 'temp\taobao-jobs') -Directory) {
        Assert-True ($directory.FullName.StartsWith($jobsRoot, [System.StringComparison]::OrdinalIgnoreCase)) 'A job directory escaped temp/taobao-jobs.'
    }

    Write-Output 'PASS: Taobao job initialization is isolated, complete, and non-overwriting.'
}
finally {
    if (Test-Path -LiteralPath $sandboxFull) {
        $verified = [System.IO.Path]::GetFullPath($sandboxFull)
        if (-not $verified.StartsWith($projectTempFull, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw 'Refusing to remove a Taobao initialization test path outside project temp.'
        }
        Remove-Item -LiteralPath $verified -Recurse -Force
    }
}
