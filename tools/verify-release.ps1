[CmdletBinding()]
param(
    [ValidateSet('NoCompiler', 'X64Compiler')]
    [string]$PackageType = 'NoCompiler'
)

$ErrorActionPreference = 'Stop'
$RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$failures = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]

function Require-File {
    param([string]$RelativePath)
    $path = Join-Path $RepoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $failures.Add("Missing file: $RelativePath")
        return
    }
    if ((Get-Item -LiteralPath $path).Length -le 0) {
        $failures.Add("Empty file: $RelativePath")
    }
}

function Require-Directory {
    param([string]$RelativePath)
    $path = Join-Path $RepoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Container)) {
        $failures.Add("Missing directory: $RelativePath")
        return
    }
    if (-not (Get-ChildItem -LiteralPath $path -Force | Select-Object -First 1)) {
        $failures.Add("Empty directory: $RelativePath")
    }
}

function Warn-OptionalDirectory {
    param([string]$RelativePath)
    $path = Join-Path $RepoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Container)) {
        $warnings.Add("Optional integration directory is absent: $RelativePath")
    }
}

function Invoke-VersionCheck {
    param(
        [string]$RelativePath,
        [string]$ExpectedText
    )
    $path = Join-Path $RepoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return
    }
    $output = & $path --version 2>&1
    if ($LASTEXITCODE -ne 0) {
        $failures.Add("Version command failed: $RelativePath")
        return
    }
    $text = ($output | Out-String).Trim()
    Write-Host "$RelativePath => $text"
    if (($ExpectedText -ne '') -and ($text -notmatch [regex]::Escape($ExpectedText))) {
        $failures.Add("Unexpected version for ${RelativePath}: $text (expected $ExpectedText)")
    }
}

$requiredFiles = @(
    'devcpp.exe',
    'Packman.exe',
    'PackMaker.exe',
    'ConsolePauser.exe',
    'devcpp.exe.manifest',
    'LICENSE',
    'NEWS.txt',
    'README.md',
    'AGENT-RUNTIME-VERSIONS.txt',
    'nodejs\node.exe',
    'claude-cli\bin\claude.exe'
)
foreach ($file in $requiredFiles) {
    Require-File $file
}

$requiredDirectories = @('Lang', 'Templates', 'Help', 'Icons', 'contributes')
foreach ($directory in $requiredDirectories) {
    Require-Directory $directory
}

if ($PackageType -eq 'X64Compiler') {
    Require-Directory 'MinGW64'
}
Warn-OptionalDirectory 'AStyle'
Warn-OptionalDirectory 'ResEd'

Invoke-VersionCheck 'nodejs\node.exe' 'v24.18.0'
Invoke-VersionCheck 'claude-cli\bin\claude.exe' '2.1.211'

Write-Host ''
foreach ($warning in $warnings) {
    Write-Warning $warning
}
if ($failures.Count -gt 0) {
    Write-Host ''
    foreach ($failure in $failures) {
        Write-Host "ERROR: $failure" -ForegroundColor Red
    }
    throw "Release verification failed with $($failures.Count) error(s)."
}

Write-Host "Release resources verified for package type: $PackageType"
