[CmdletBinding()]
param(
    [string]$NodeArchive = '',
    [string]$ClaudeCliSource = '',
    [string]$ClaudeCliArchive = '',
    [string]$OutputRoot = '',
    [string]$NodeVersion = '',
    [string]$ClaudeCliVersion = '',
    [switch]$VerifyOnly
)

$ErrorActionPreference = 'Stop'

function Fail([string]$Message) {
    throw "Agent runtime preparation failed: $Message"
}

function RequireFile([string]$Path, [string]$Description) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Fail "$Description was not found: $Path"
    }
}

function RequireDirectory([string]$Path, [string]$Description) {
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        Fail "$Description was not found: $Path"
    }
}

if (-not $OutputRoot) { $OutputRoot = Join-Path $PSScriptRoot '..' }
$OutputRoot = (Resolve-Path -LiteralPath $OutputRoot).Path
$NodeRoot = Join-Path $OutputRoot 'nodejs'
$ClaudeRoot = Join-Path $OutputRoot 'claude-cli'
$NodeExe = Join-Path $NodeRoot 'node.exe'
$ClaudeExe = Join-Path $ClaudeRoot 'bin\claude.exe'
$VersionFile = Join-Path $OutputRoot 'AGENT-RUNTIME-VERSIONS.txt'

if (-not $VerifyOnly) {
    if (($ClaudeCliSource -ne '') -and ($ClaudeCliArchive -ne '')) {
        Fail 'use only one of -ClaudeCliSource and -ClaudeCliArchive'
    }
    if (($ClaudeCliSource -eq '') -and ($ClaudeCliArchive -eq '') -and
        (-not (Test-Path -LiteralPath $ClaudeRoot -PathType Container))) {
        Fail 'pass -ClaudeCliSource or -ClaudeCliArchive, or stage claude-cli\ before running this script'
    }

    if ($NodeArchive -ne '') {
        RequireFile $NodeArchive 'Node.js archive'
        $TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('devcpp-agent-runtime-' + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $TempRoot | Out-Null
        try {
            Expand-Archive -LiteralPath $NodeArchive -DestinationPath $TempRoot -Force
            $NodeSource = Get-ChildItem -LiteralPath $TempRoot -Directory | Select-Object -First 1
            if ($null -eq $NodeSource) {
                $NodeSource = Get-Item -LiteralPath $TempRoot
            }
            RequireFile (Join-Path $NodeSource.FullName 'node.exe') 'node.exe in Node.js archive'
            New-Item -ItemType Directory -Path $NodeRoot -Force | Out-Null
            Copy-Item (Join-Path $NodeSource.FullName '*') $NodeRoot -Recurse -Force
        } finally {
            Remove-Item -LiteralPath $TempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    if ($ClaudeCliSource -ne '') {
        RequireDirectory $ClaudeCliSource 'Claude CLI source directory'
        RequireFile (Join-Path $ClaudeCliSource 'bin\claude.exe') 'native Claude CLI source executable'
        New-Item -ItemType Directory -Path $ClaudeRoot -Force | Out-Null
        Copy-Item (Join-Path $ClaudeCliSource '*') $ClaudeRoot -Recurse -Force
    }

    if ($ClaudeCliArchive -ne '') {
        RequireFile $ClaudeCliArchive 'Claude CLI archive'
        $TempClaudeRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('devcpp-claude-cli-' + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $TempClaudeRoot | Out-Null
        try {
            Expand-Archive -LiteralPath $ClaudeCliArchive -DestinationPath $TempClaudeRoot -Force
            $ClaudeSourceRoot = Get-Item -LiteralPath $TempClaudeRoot
            if (-not (Test-Path -LiteralPath (Join-Path $ClaudeSourceRoot.FullName 'bin\claude.exe') -PathType Leaf)) {
                $ClaudeSourceRoot = Get-ChildItem -LiteralPath $TempClaudeRoot -Directory |
                    Where-Object {
                        (Test-Path -LiteralPath (Join-Path $_.FullName 'bin\claude.exe') -PathType Leaf)
                    } | Select-Object -First 1
            }
            if ($null -eq $ClaudeSourceRoot) {
                Fail 'Claude CLI archive must contain native bin\claude.exe'
            }
            New-Item -ItemType Directory -Path $ClaudeRoot -Force | Out-Null
            Copy-Item (Join-Path $ClaudeSourceRoot.FullName '*') $ClaudeRoot -Recurse -Force
        } finally {
            Remove-Item -LiteralPath $TempClaudeRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

RequireFile $ClaudeExe 'native Claude CLI executable required for the Node-free release'

$OriginalPath = $env:Path
try {
    $env:Path = "$NodeRoot;$ClaudeRoot\bin;$OriginalPath"
    $NodeReportedVersion = 'not bundled (native Claude CLI)'
    if ($NodeArchive -ne '' -or $NodeVersion -ne '') {
        RequireFile $NodeExe 'explicitly requested optional Node.js executable'
        $NodeReportedVersion = (& $NodeExe '--version' 2>&1 | Out-String).Trim()
        if ($LASTEXITCODE -ne 0) { Fail 'Optional Node.js could not start' }
    }

    $ClaudeReportedVersion = (& $ClaudeExe '--version' 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $ClaudeReportedVersion -eq '') {
        Fail "Claude CLI could not be started: $ClaudeReportedVersion"
    }
} finally {
    $env:Path = $OriginalPath
}

if ($NodeVersion -ne '' -and $NodeReportedVersion -ne "v$NodeVersion") {
    Fail "expected Node.js v$NodeVersion but found $NodeReportedVersion"
}
if ($ClaudeCliVersion -ne '' -and $ClaudeReportedVersion -notmatch ('^' + [regex]::Escape($ClaudeCliVersion) + '(\s|$)')) {
    Fail "expected Claude CLI $ClaudeCliVersion but found $ClaudeReportedVersion"
}

$VersionLines = @(
    'DevCPlusAi bundled Agent runtime',
    "Node.js requested: $NodeVersion",
    "Node.js reported: $NodeReportedVersion",
    "Claude CLI requested: $ClaudeCliVersion",
    "Claude CLI reported: $ClaudeReportedVersion",
    'Generated by tools/prepare-agent-runtime.ps1',
    ''
)
Set-Content -LiteralPath $VersionFile -Value $VersionLines -Encoding ASCII

Write-Host "Agent runtime ready:"
Write-Host "  Node.js: $NodeReportedVersion"
Write-Host "  Claude CLI: $ClaudeReportedVersion"
Write-Host "  Version file: $VersionFile"
