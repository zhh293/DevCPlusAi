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

function Invoke-ClaudeCompatibilityCheck {
    param([string]$RelativePath)

    $path = Join-Path $RepoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return
    }

    $helpOutput = & $path --help 2>&1
    if ($LASTEXITCODE -ne 0) {
        $failures.Add("Claude CLI help command failed: $RelativePath")
        return
    }
    $helpText = ($helpOutput | Out-String)
    $requiredOptions = @(
        '--print',
        '--input-format',
        '--output-format',
        '--verbose',
        '--include-partial-messages',
        '--include-hook-events',
        '--prompt-suggestions',
        '--model',
        '--resume',
        '--permission-mode',
        '--mcp-config',
        '--plugin-dir'
    )
    foreach ($option in $requiredOptions) {
        if (-not $helpText.Contains($option)) {
            $failures.Add("Claude CLI no longer advertises required option: $option")
        }
    }

    $requiredPermissionModes = @(
        'manual', 'acceptEdits', 'auto', 'bypassPermissions', 'dontAsk', 'plan'
    )
    foreach ($mode in $requiredPermissionModes) {
        if (-not $helpText.Contains('"' + $mode + '"')) {
            $failures.Add("Claude CLI no longer advertises permission mode: $mode")
        }
    }

    # Exercise the exact non-interactive base flags with an empty, closed stdin.
    # The file form of append-system-prompt is hidden from the short help in
    # current Claude builds, so this behavior check is its compatibility test.
    # No user prompt is sent and therefore this does not make an API request.
    $promptFile = [System.IO.Path]::GetTempFileName()
    [System.IO.File]::WriteAllText($promptFile, 'verify')
    $process = $null
    try {
        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = $path
        $startInfo.Arguments = '--print --input-format stream-json --output-format stream-json --verbose --include-partial-messages --include-hook-events --prompt-suggestions --permission-mode manual --append-system-prompt-file "' + $promptFile + '"'
        $startInfo.WorkingDirectory = $RepoRoot
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardInput = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $startInfo
        if (-not $process.Start()) {
            $failures.Add('Claude CLI argument smoke test did not start.')
            return
        }
        $process.StandardInput.Close()
        if (-not $process.WaitForExit(15000)) {
            $process.Kill()
            $failures.Add('Claude CLI argument smoke test timed out.')
            return
        }
        $stderr = $process.StandardError.ReadToEnd().Trim()
        if ($process.ExitCode -ne 0) {
            $failures.Add("Claude CLI rejected AgentProcess arguments: $stderr")
        }
    }
    finally {
        if ($null -ne $process) {
            $process.Dispose()
        }
        Remove-Item -LiteralPath $promptFile -Force -ErrorAction SilentlyContinue
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
Invoke-ClaudeCompatibilityCheck 'claude-cli\bin\claude.exe'

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
