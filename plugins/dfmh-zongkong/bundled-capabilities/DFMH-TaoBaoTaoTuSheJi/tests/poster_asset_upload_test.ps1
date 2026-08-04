param()

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$scriptPath = Join-Path $projectRoot 'scripts\prepare_poster_asset_clipboard.ps1'
$skillPath = Join-Path $projectRoot 'skills\creating-promotional-posters\SKILL.md'
$workflowPath = Join-Path $projectRoot 'workflows\PROMOTIONAL_POSTER_PILOT.md'

if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
    throw 'Missing safe poster asset clipboard preparation script.'
}

$corpus = (Get-Content -Raw -Encoding UTF8 -LiteralPath $skillPath) + "`n" +
    (Get-Content -Raw -Encoding UTF8 -LiteralPath $workflowPath)
function Decode-Text {
    param([string]$Base64)
    return [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Base64))
}

$requiredRules = @(
    'powershell -Sta',
    (Decode-Text '5paH5Lu25pys5L2T5aSN5Yi257KY6LS0'),
    (Decode-Text '56aB5q2i5oqK5paH5Lu26Lev5b6E5paH5a2X6L6T5YWl'),
    (Decode-Text '5YWI6aqM6K+B57Sg5p2Q57yp55Wl5Zu+'),
    (Decode-Text '5Y6f55Sf5paH5Lu26YCJ5oup56qX5Y+j5LiN5piv6buY6K6k5LiK5Lyg5pa55byP'),
    (Decode-Text '5ZCM5LiA57Sg5p2Q5LiK5Lyg5aSx6LSl5LiA5qyh5ZCO5YGc5q2i')
)
foreach ($rule in $requiredRules) {
    if (-not $corpus.Contains($rule)) {
        throw "Missing poster asset upload rule: $rule"
    }
}

$sandbox = Join-Path $projectRoot ('temp\poster-upload-test-' + [guid]::NewGuid().ToString('N'))
$sandboxFull = [System.IO.Path]::GetFullPath($sandbox)
$projectTempFull = [System.IO.Path]::GetFullPath((Join-Path $projectRoot 'temp')) + [System.IO.Path]::DirectorySeparatorChar
if (-not $sandboxFull.StartsWith($projectTempFull, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Refusing to create upload test sandbox outside project temp.'
}

function Invoke-Prepare {
    param(
        [string]$AssetPath,
        [string]$ExpectedSha256
    )
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

New-Item -ItemType Directory -Force -Path (Join-Path $sandboxFull 'temp\poster-jobs\synthetic') | Out-Null

try {
    $assetPath = Join-Path $sandboxFull 'temp\poster-jobs\synthetic\asset.png'
    $png = [Convert]::FromBase64String('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=')
    [System.IO.File]::WriteAllBytes($assetPath, $png)
    $hash = (Get-FileHash -LiteralPath $assetPath -Algorithm SHA256).Hash

    $valid = Invoke-Prepare -AssetPath $assetPath -ExpectedSha256 $hash
    Assert-True ($valid.ExitCode -eq 0) ('A valid project asset should pass: ' + $valid.Output)
    $evidence = $valid.Output | ConvertFrom-Json
    Assert-True ($evidence.sha256 -eq $hash) 'Validated asset hash is missing or incorrect.'
    Assert-True ($evidence.bytes -eq $png.Length) 'Validated asset byte length is incorrect.'
    Assert-True ($evidence.clipboardApplied -eq $false) 'ValidateOnly must not modify the clipboard.'

    $jpegWithTrailingData = Join-Path $sandboxFull 'temp\poster-jobs\synthetic\trailing-metadata.jpg'
    [System.IO.File]::WriteAllBytes($jpegWithTrailingData, [byte[]](255,216,255,224,0,16,0,0,255,217,1,2))
    $jpegHash = (Get-FileHash -LiteralPath $jpegWithTrailingData -Algorithm SHA256).Hash
    $jpegResult = Invoke-Prepare -AssetPath $jpegWithTrailingData -ExpectedSha256 $jpegHash
    Assert-True ($jpegResult.ExitCode -eq 0) ('A JPEG with valid EOI before trailing metadata should pass: ' + $jpegResult.Output)

    $wrongHash = Invoke-Prepare -AssetPath $assetPath -ExpectedSha256 ('0' * 64)
    Assert-True ($wrongHash.ExitCode -ne 0) 'A mismatched asset hash must fail.'

    $unsupported = Join-Path $sandboxFull 'temp\poster-jobs\synthetic\asset.txt'
    [System.IO.File]::WriteAllText($unsupported, 'not an image')
    $unsupportedHash = (Get-FileHash -LiteralPath $unsupported -Algorithm SHA256).Hash
    $unsupportedResult = Invoke-Prepare -AssetPath $unsupported -ExpectedSha256 $unsupportedHash
    Assert-True ($unsupportedResult.ExitCode -ne 0) 'A non-image asset must fail.'

    $outside = Join-Path $projectRoot 'temp\poster-upload-outside.png'
    [System.IO.File]::WriteAllBytes($outside, $png)
    try {
        $outsideHash = (Get-FileHash -LiteralPath $outside -Algorithm SHA256).Hash
        $outsideResult = Invoke-Prepare -AssetPath $outside -ExpectedSha256 $outsideHash
        Assert-True ($outsideResult.ExitCode -ne 0) 'An asset outside the selected project root must fail.'
    }
    finally {
        if (Test-Path -LiteralPath $outside) { Remove-Item -LiteralPath $outside -Force }
    }

    Write-Output 'PASS: poster asset preparation accepted PNG and trailing-metadata JPEG files and rejected three unsafe inputs.'
}
finally {
    if (Test-Path -LiteralPath $sandboxFull) {
        $verified = [System.IO.Path]::GetFullPath($sandboxFull)
        if (-not $verified.StartsWith($projectTempFull, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw 'Refusing to remove an upload test path outside project temp.'
        }
        Remove-Item -LiteralPath $verified -Recurse -Force
    }
}
