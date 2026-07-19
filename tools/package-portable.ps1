[CmdletBinding()]
param(
    [ValidatePattern('^[0-9A-Za-z][0-9A-Za-z._-]*$')]
    [string]$Version = 'dev'
)

$ErrorActionPreference = 'Stop'
$RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))

& (Join-Path $PSScriptRoot 'verify-release.ps1') -PackageType NoCompiler

$distRoot = Join-Path $RepoRoot 'dist'
$packageRoot = Join-Path $distRoot 'DevCPlusAi'
$zipPath = Join-Path $RepoRoot ("DevCPlusAi-{0}-windows-no-compiler.zip" -f $Version)

if (Test-Path -LiteralPath $packageRoot) {
    $resolvedDist = [System.IO.Path]::GetFullPath($distRoot).TrimEnd('\') + '\'
    $resolvedPackage = [System.IO.Path]::GetFullPath($packageRoot)
    if (-not $resolvedPackage.StartsWith($resolvedDist, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove an unexpected package path: $resolvedPackage"
    }
    Remove-Item -LiteralPath $packageRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $packageRoot | Out-Null

$files = @(
    'devcpp.exe',
    'Packman.exe',
    'PackMaker.exe',
    'ConsolePauser.exe',
    'devcpp.exe.manifest',
    'RedPanda.ico',
    'LICENSE',
    'NEWS.txt',
    'README.md',
    'AGENT-RUNTIME-VERSIONS.txt'
)
foreach ($file in $files) {
    Copy-Item -LiteralPath (Join-Path $RepoRoot $file) -Destination $packageRoot -Force
}

$directories = @('Lang', 'Templates', 'Icons', 'Help', 'contributes', 'nodejs', 'claude-cli')
foreach ($directory in $directories) {
    Copy-Item -LiteralPath (Join-Path $RepoRoot $directory) -Destination $packageRoot -Recurse -Force
}

foreach ($optionalDirectory in @('AStyle', 'ResEd')) {
    $source = Join-Path $RepoRoot $optionalDirectory
    if (Test-Path -LiteralPath $source -PathType Container) {
        Copy-Item -LiteralPath $source -Destination $packageRoot -Recurse -Force
    }
}

$gitCommand = Get-Command 'git.exe' -ErrorAction SilentlyContinue
$sourceCommit = 'unknown'
$sourceDirty = 'unknown'
if ($gitCommand) {
    $sourceCommitOutput = & $gitCommand.Source -C $RepoRoot rev-parse HEAD 2>$null
    if ($LASTEXITCODE -eq 0) {
        $sourceCommit = ($sourceCommitOutput | Out-String).Trim()
        $dirtyOutput = & $gitCommand.Source -C $RepoRoot status --porcelain 2>$null
        if ($LASTEXITCODE -eq 0) {
            if ($dirtyOutput) {
                $sourceDirty = 'true'
            } else {
                $sourceDirty = 'false'
            }
        }
    }
}

$buildInfo = New-Object System.Collections.Generic.List[string]
$buildInfo.Add('DevCPlusAi portable build')
$buildInfo.Add("Package-Version: $Version")
$buildInfo.Add("Source-Commit: $sourceCommit")
$buildInfo.Add("Source-Dirty: $sourceDirty")
$buildInfo.Add("Generated-UTC: $([DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ'))")
$buildInfo.Add('')
$buildInfo.Add('Component SHA256:')
foreach ($component in @('devcpp.exe', 'Packman.exe', 'PackMaker.exe', 'ConsolePauser.exe')) {
    $componentPath = Join-Path $packageRoot $component
    $componentHash = (Get-FileHash -LiteralPath $componentPath -Algorithm SHA256).Hash
    $buildInfo.Add("$componentHash  $component")
}
$buildInfo.Add('')
$buildInfo.Add('Runtime versions:')
$buildInfo.AddRange([string[]](Get-Content -LiteralPath (Join-Path $packageRoot 'AGENT-RUNTIME-VERSIONS.txt')))
$buildInfo | Set-Content -LiteralPath (Join-Path $packageRoot 'BUILD-INFO.txt') -Encoding UTF8

if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}

$tar = Get-Command 'tar.exe' -ErrorAction SilentlyContinue
if ($tar) {
    & $tar.Source '-a' '-c' '-f' $zipPath '-C' $packageRoot '.'
    if ($LASTEXITCODE -ne 0) {
        throw "tar.exe failed with exit code $LASTEXITCODE"
    }
} else {
    Compress-Archive -Path (Join-Path $packageRoot '*') -DestinationPath $zipPath -CompressionLevel Optimal
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
try {
    $archiveEntries = @{}
    foreach ($entry in $archive.Entries) {
        $normalizedName = $entry.FullName.Replace('\', '/').TrimStart('.', '/')
        $archiveEntries[$normalizedName] = $entry
    }
    foreach ($requiredEntry in @(
        'devcpp.exe',
        'Packman.exe',
        'PackMaker.exe',
        'ConsolePauser.exe',
        'nodejs/node.exe',
        'claude-cli/bin/claude.exe',
        'AGENT-RUNTIME-VERSIONS.txt',
        'BUILD-INFO.txt'
    )) {
        if (-not $archiveEntries.ContainsKey($requiredEntry)) {
            throw "Portable archive is missing: $requiredEntry"
        }
        $sourcePath = Join-Path $packageRoot $requiredEntry.Replace('/', '\')
        if ($archiveEntries[$requiredEntry].Length -ne (Get-Item -LiteralPath $sourcePath).Length) {
            throw "Portable archive entry size mismatch: $requiredEntry"
        }
        $entryStream = $archiveEntries[$requiredEntry].Open()
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        try {
            $entryHash = [System.BitConverter]::ToString($sha256.ComputeHash($entryStream)).Replace('-', '')
        }
        finally {
            $sha256.Dispose()
            $entryStream.Dispose()
        }
        $sourceHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash
        if ($entryHash -ne $sourceHash) {
            throw "Portable archive entry hash mismatch: $requiredEntry"
        }
    }
}
finally {
    $archive.Dispose()
}

$sevenZip = Get-Command '7z.exe' -ErrorAction SilentlyContinue
if (-not $sevenZip) {
    foreach ($candidate in @(
        'C:\Program Files\7-Zip\7z.exe',
        'C:\Program Files (x86)\7-Zip\7z.exe'
    )) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            $sevenZip = Get-Item -LiteralPath $candidate
            break
        }
    }
}
if ($sevenZip) {
    Write-Host 'Testing every archive entry with 7-Zip...'
    if ($sevenZip -is [System.IO.FileInfo]) {
        $sevenZipPath = $sevenZip.FullName
    } else {
        $sevenZipPath = $sevenZip.Source
    }
    & $sevenZipPath 't' '-bso0' '-bsp0' $zipPath
    if ($LASTEXITCODE -ne 0) {
        throw "7-Zip archive test failed with exit code $LASTEXITCODE"
    }
}

$zip = Get-Item -LiteralPath $zipPath
$hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash
Write-Host ("Portable package: {0}" -f $zip.FullName)
Write-Host ("Size: {0} bytes" -f $zip.Length)
Write-Host ("SHA256: {0}" -f $hash)
