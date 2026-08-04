param()

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$scriptPath = Join-Path $projectRoot 'scripts\prepare_taobao_asset_clipboard.ps1'

if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
    throw 'Missing safe Taobao asset clipboard preparation script.'
}

$sandbox = Join-Path $projectRoot ('temp\taobao-clipboard-test-' + [guid]::NewGuid().ToString('N'))
$sandboxFull = [System.IO.Path]::GetFullPath($sandbox)
$projectTempFull = [System.IO.Path]::GetFullPath((Join-Path $projectRoot 'temp')) + [System.IO.Path]::DirectorySeparatorChar
if (-not $sandboxFull.StartsWith($projectTempFull, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Refusing to create Taobao clipboard test sandbox outside project temp.'
}

function Invoke-Prepare {
    param([string]$AssetPath, [string]$ExpectedSha256)
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $scriptPath -ProjectRoot $sandboxFull -AssetPath $AssetPath -ExpectedSha256 $ExpectedSha256 -ValidateOnly 2>&1)
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

New-Item -ItemType Directory -Force -Path (Join-Path $sandboxFull 'temp\taobao-jobs\synthetic\assets') | Out-Null

try {
    $assetPath = Join-Path $sandboxFull 'temp\taobao-jobs\synthetic\assets\product.png'
    $png = [Convert]::FromBase64String('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=')
    [System.IO.File]::WriteAllBytes($assetPath, $png)
    $hash = (Get-FileHash -LiteralPath $assetPath -Algorithm SHA256).Hash

    $valid = Invoke-Prepare -AssetPath $assetPath -ExpectedSha256 $hash
    Assert-True ($valid.ExitCode -eq 0) ('A valid Taobao job asset should pass: ' + $valid.Output)
    $evidence = $valid.Output | ConvertFrom-Json
    Assert-True ($evidence.sha256 -eq $hash) 'Validated Taobao asset hash is missing or incorrect.'
    Assert-True ($evidence.bytes -eq $png.Length) 'Validated Taobao asset byte length is incorrect.'
    Assert-True ($evidence.clipboardApplied -eq $false) 'ValidateOnly must not modify the clipboard.'

    $wrongHash = Invoke-Prepare -AssetPath $assetPath -ExpectedSha256 ('0' * 64)
    Assert-True ($wrongHash.ExitCode -ne 0) 'A mismatched Taobao asset hash must fail.'

    $outside = Join-Path $sandboxFull 'temp\outside.png'
    [System.IO.File]::WriteAllBytes($outside, $png)
    $outsideHash = (Get-FileHash -LiteralPath $outside -Algorithm SHA256).Hash
    $outsideResult = Invoke-Prepare -AssetPath $outside -ExpectedSha256 $outsideHash
    Assert-True ($outsideResult.ExitCode -ne 0) 'An asset outside temp/taobao-jobs must fail.'

    Write-Output 'PASS: Taobao asset clipboard preparation accepted a verified in-job image and rejected unsafe inputs.'
}
finally {
    if (Test-Path -LiteralPath $sandboxFull) {
        $verified = [System.IO.Path]::GetFullPath($sandboxFull)
        if (-not $verified.StartsWith($projectTempFull, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw 'Refusing to remove a Taobao clipboard test path outside project temp.'
        }
        Remove-Item -LiteralPath $verified -Recurse -Force
    }
}
