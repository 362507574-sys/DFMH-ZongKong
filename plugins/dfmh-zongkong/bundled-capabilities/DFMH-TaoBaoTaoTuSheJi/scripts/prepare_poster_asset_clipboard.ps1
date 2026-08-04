param(
    [string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,

    [Parameter(Mandatory = $true)]
    [string]$AssetPath,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Fa-f0-9]{64}$')]
    [string]$ExpectedSha256,

    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

function Get-NormalizedPath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
}

function Test-IsWithin {
    param([string]$Path, [string]$Root)
    $full = [System.IO.Path]::GetFullPath($Path)
    $rootFull = (Get-NormalizedPath $Root) + [System.IO.Path]::DirectorySeparatorChar
    return $full.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)
}

function Assert-ImageSignature {
    param([string]$Path, [string]$Extension)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 12) { throw 'Asset is too small to be a valid image.' }

    switch ($Extension) {
        '.png' {
            $expected = @(137, 80, 78, 71, 13, 10, 26, 10)
            for ($i = 0; $i -lt $expected.Count; $i++) {
                if ($bytes[$i] -ne $expected[$i]) { throw 'PNG signature is invalid.' }
            }
        }
        { $_ -in @('.jpg', '.jpeg') } {
            $hasEndOfImage = $false
            for ($i = 3; $i -lt $bytes.Length; $i++) {
                if ($bytes[$i - 1] -eq 255 -and $bytes[$i] -eq 217) {
                    $hasEndOfImage = $true
                    break
                }
            }
            if ($bytes[0] -ne 255 -or $bytes[1] -ne 216 -or -not $hasEndOfImage) {
                throw 'JPEG signature is invalid.'
            }
        }
        '.webp' {
            $riff = [System.Text.Encoding]::ASCII.GetString($bytes, 0, 4)
            $webp = [System.Text.Encoding]::ASCII.GetString($bytes, 8, 4)
            if ($riff -ne 'RIFF' -or $webp -ne 'WEBP') { throw 'WebP signature is invalid.' }
        }
        default { throw "Unsupported image extension: $Extension" }
    }
}

try {
    $rootFull = Get-NormalizedPath $ProjectRoot
    if (-not (Test-Path -LiteralPath $rootFull -PathType Container)) {
        throw "Project root does not exist: $rootFull"
    }

    $assetFull = [System.IO.Path]::GetFullPath($AssetPath)
    if (-not (Test-IsWithin -Path $assetFull -Root $rootFull)) {
        throw 'Asset must be inside the selected project root.'
    }
    $posterJobsRoot = Join-Path $rootFull 'temp\poster-jobs'
    if (-not (Test-IsWithin -Path $assetFull -Root $posterJobsRoot)) {
        throw 'Asset must be archived inside temp/poster-jobs/ before upload.'
    }
    if (-not (Test-Path -LiteralPath $assetFull -PathType Leaf)) {
        throw "Asset does not exist: $assetFull"
    }

    $extension = [System.IO.Path]::GetExtension($assetFull).ToLowerInvariant()
    if (@('.png', '.jpg', '.jpeg', '.webp') -notcontains $extension) {
        throw "Unsupported image extension: $extension"
    }
    $item = Get-Item -LiteralPath $assetFull
    if ($item.Length -le 0) { throw 'Asset is empty.' }
    if ($item.Length -gt 25MB) { throw 'Asset exceeds the 25 MB safety limit.' }

    Assert-ImageSignature -Path $assetFull -Extension $extension
    $actualHash = (Get-FileHash -LiteralPath $assetFull -Algorithm SHA256).Hash
    if ($actualHash -ne $ExpectedSha256.ToUpperInvariant()) {
        throw 'Asset SHA-256 does not match the expected value.'
    }

    $clipboardApplied = $false
    if (-not $ValidateOnly) {
        if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne [System.Threading.ApartmentState]::STA) {
            throw 'Clipboard mode requires Windows PowerShell started with -Sta.'
        }
        Add-Type -AssemblyName System.Windows.Forms
        $paths = New-Object System.Collections.Specialized.StringCollection
        $null = $paths.Add($assetFull)
        [System.Windows.Forms.Clipboard]::SetFileDropList($paths)
        $clipboardFiles = [System.Windows.Forms.Clipboard]::GetFileDropList()
        if ($clipboardFiles.Count -ne 1 -or $clipboardFiles[0] -ne $assetFull) {
            throw 'Clipboard verification failed after copying the image file.'
        }
        $clipboardApplied = $true
    }

    [ordered]@{
        path = $assetFull
        fileName = $item.Name
        extension = $extension
        bytes = $item.Length
        sha256 = $actualHash
        clipboardApplied = $clipboardApplied
        verifiedAt = (Get-Date).ToString('o')
    } | ConvertTo-Json -Compress
    exit 0
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
