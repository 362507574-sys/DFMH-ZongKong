param(
    [Parameter(Mandatory=$true)][ValidatePattern('^[a-z0-9][a-z0-9-]{2,63}$')][string]$JobId,
    [Parameter(Mandatory=$true)][ValidateSet('home','detail','full')][string]$Scope,
    [ValidateSet('main','test','production')][string]$OriginThreadMode='test',
    [string]$ProjectRoot=''
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        throw 'Cannot determine the project root because the script directory is unavailable.'
    }
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}

function Get-NormalizedPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    return [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
}

function Test-IsWithin {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Root
    )

    $fullPath = Get-NormalizedPath -Path $Path
    $fullRoot = (Get-NormalizedPath -Path $Root) + [System.IO.Path]::DirectorySeparatorChar
    return $fullPath.StartsWith($fullRoot, [System.StringComparison]::OrdinalIgnoreCase)
}

$rootFull = Get-NormalizedPath -Path $ProjectRoot
if (-not (Test-Path -LiteralPath $rootFull -PathType Container)) {
    throw "Project root does not exist: $rootFull"
}

if ($JobId -match '^(con|prn|aux|nul|com[1-9]|lpt[1-9])$') {
    throw "JobId is a reserved Windows device name: $JobId"
}

$templatePath = Join-Path $rootFull 'templates\TAOBAO_ECOMMERCE_JOB.json'
if (-not (Test-Path -LiteralPath $templatePath -PathType Leaf)) {
    throw "Taobao job manifest template does not exist: $templatePath"
}

$jobsRoot = Get-NormalizedPath -Path (Join-Path $rootFull 'temp\taobao-jobs')
$jobRoot = Get-NormalizedPath -Path (Join-Path $jobsRoot $JobId)
$jobParent = Get-NormalizedPath -Path (Split-Path -Parent $jobRoot)

if (-not (Test-IsWithin -Path $jobRoot -Root $jobsRoot)) {
    throw 'The requested job directory escapes temp/taobao-jobs.'
}
if (-not $jobParent.Equals($jobsRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'The requested job directory must be a direct child of temp/taobao-jobs.'
}
if ((Split-Path -Leaf $jobRoot) -ne $JobId) {
    throw 'The requested job directory name does not match the validated jobId.'
}

New-Item -ItemType Directory -Force -Path $jobsRoot | Out-Null
if (Test-Path -LiteralPath $jobRoot) {
    throw "Refusing to overwrite an existing Taobao job: $jobRoot"
}

$created = $false
$manifestTempPath = $null
try {
    New-Item -ItemType Directory -Path $jobRoot | Out-Null
    $created = $true

    $fixedDirectories = @(
        'assets',
        'benchmark',
        'prompts\home',
        'prompts\detail',
        'candidates\home',
        'candidates\detail',
        'acceptance'
    )
    foreach ($relativePath in $fixedDirectories) {
        $directoryPath = Get-NormalizedPath -Path (Join-Path $jobRoot $relativePath)
        if (-not (Test-IsWithin -Path $directoryPath -Root $jobRoot)) {
            throw "A fixed task directory escapes the job root: $relativePath"
        }
        New-Item -ItemType Directory -Path $directoryPath | Out-Null
    }

    $manifestPath = Join-Path $jobRoot 'manifest.json'
    $manifestTempPath = Join-Path $jobRoot ('manifest.json.tmp-' + [guid]::NewGuid().ToString('N'))
    Copy-Item -LiteralPath $templatePath -Destination $manifestTempPath
    $manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $manifestTempPath | ConvertFrom-Json

    $manifest.jobId = $JobId
    $manifest.scope.mode = $Scope
    $manifest.scope.homeRequired = ($Scope -eq 'home' -or $Scope -eq 'full')
    $manifest.scope.detailRequired = ($Scope -eq 'detail' -or $Scope -eq 'full')
    $manifest.originThreadMode = $OriginThreadMode
    $manifest.generation.styleAnchor.itemId = if ($Scope -eq 'detail') { 'D01' } else { 'H01' }

    $manifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $manifestTempPath -Encoding UTF8

    $verifiedManifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $manifestTempPath | ConvertFrom-Json
    if ($verifiedManifest.jobId -ne $JobId -or
        $verifiedManifest.scope.mode -ne $Scope -or
        $verifiedManifest.originThreadMode -ne $OriginThreadMode -or
        $verifiedManifest.generation.styleAnchor.itemId -ne $(if ($Scope -eq 'detail') { 'D01' } else { 'H01' })) {
        throw 'The temporary manifest failed post-write verification.'
    }
    if (Test-Path -LiteralPath $manifestPath) {
        throw "Refusing to replace an existing manifest: $manifestPath"
    }
    [System.IO.File]::Move($manifestTempPath, $manifestPath)
    $manifestTempPath = $null

    [ordered]@{
        created = $true
        jobId = $JobId
        manifestPath = $manifestPath
    } | ConvertTo-Json -Compress
}
catch {
    if ($manifestTempPath -and (Test-Path -LiteralPath $manifestTempPath -PathType Leaf)) {
        Remove-Item -LiteralPath $manifestTempPath -Force
    }
    if ($created -and (Test-Path -LiteralPath $jobRoot -PathType Container)) {
        $verifiedJobRoot = Get-NormalizedPath -Path $jobRoot
        if ((Test-IsWithin -Path $verifiedJobRoot -Root $jobsRoot) -and
            (Get-NormalizedPath -Path (Split-Path -Parent $verifiedJobRoot)).Equals($jobsRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $verifiedJobRoot -Recurse -Force
        }
    }
    throw
}
