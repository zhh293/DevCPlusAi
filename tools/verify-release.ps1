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

function Invoke-AgentAsciiSourceCheck {
    $sourceRoot = Join-Path $RepoRoot 'Source'
    $files = @(
        Get-ChildItem -LiteralPath $sourceRoot -File | Where-Object {
            $_.Name -like 'Agent*.pas' -or $_.Name -like 'Agent*.dfm'
        }
    )
    if ($files.Count -eq 0) {
        $failures.Add('No Agent Pascal or DFM sources were found for the encoding check.')
        return
    }

    $failed = $false
    foreach ($file in $files) {
        $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
        $highByte = $bytes | Where-Object { $_ -gt 127 } | Select-Object -First 1
        if ($null -ne $highByte) {
            $relativePath = $file.FullName.Substring($RepoRoot.Length).TrimStart('\')
            $failures.Add("Agent source must remain ASCII for Delphi 7 locale safety: $relativePath")
            $failed = $true
        }
    }
    if (-not $failed) {
        Write-Host "Agent source encoding check passed ($($files.Count) ASCII files)."
    }
}

function Invoke-InstallerStaticCheck {
    param([string]$RelativePath)

    $path = Join-Path $RepoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $failures.Add("Missing installer script: $RelativePath")
        return
    }
    $text = [System.IO.File]::ReadAllText($path)
    $requiredFragments = @(
        'Section "AI Agent Runtime"',
        'File "AGENT-RUNTIME-VERSIONS.txt"',
        'File /r "nodejs\*"',
        'File /r "claude-cli\*"',
        'Delete "$INSTDIR\AGENT-RUNTIME-VERSIONS.txt"',
        'RMDir /r "$INSTDIR\nodejs"',
        'RMDir /r "$INSTDIR\claude-cli"'
    )
    foreach ($fragment in $requiredFragments) {
        if (-not $text.Contains($fragment)) {
            $failures.Add("Installer invariant missing in ${RelativePath}: $fragment")
        }
    }
    if ($text.IndexOf('cc-switch', [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
        $failures.Add("Installer must not bundle cc-switch: $RelativePath")
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

function Invoke-ClaudeArgumentSmoke {
    param(
        [string]$FileName,
        [string]$Arguments,
        [string]$Label
    )

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $FileName
    $startInfo.Arguments = $Arguments
    $startInfo.WorkingDirectory = $RepoRoot
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) {
            $failures.Add("Claude CLI $Label smoke test did not start.")
            return
        }
        $process.StandardInput.Close()
        if (-not $process.WaitForExit(15000)) {
            $process.Kill()
            $process.WaitForExit()
            $failures.Add("Claude CLI $Label smoke test timed out.")
            return
        }
        $stderr = $process.StandardError.ReadToEnd().Trim()
        if ($process.ExitCode -ne 0) {
            $failures.Add("Claude CLI rejected $Label AgentProcess arguments: $stderr")
        } else {
            Write-Host "Claude CLI $Label arguments accepted."
        }
    }
    finally {
        $process.Dispose()
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
    # Current Agent CLI builds use this behavior check.
    # No user prompt is sent and therefore this does not make an API request.
    $promptFile = [System.IO.Path]::GetTempFileName()
    [System.IO.File]::WriteAllText($promptFile, 'verify')
    $launcherFile = Join-Path ([System.IO.Path]::GetTempPath()) (
        'devcpp-claude-launcher-' + [Guid]::NewGuid().ToString('N') + '.cmd'
    )
    try {
        $baseArguments = '--print --input-format stream-json --output-format stream-json --verbose --include-partial-messages --include-hook-events --prompt-suggestions --permission-mode manual --append-system-prompt-file "' + $promptFile + '"'
        Invoke-ClaudeArgumentSmoke $path $baseArguments 'native launcher'
        foreach ($model in @('deepseek-v4-flash', 'deepseek-v4-pro')) {
            Invoke-ClaudeArgumentSmoke $path ($baseArguments + ' --model "' +
                $model + '[1m]"') ("DeepSeek " + $model)
        }

        $launcherText = "@echo off`r`n`"$path`" %*`r`n"
        [System.IO.File]::WriteAllText($launcherFile, $launcherText,
            [System.Text.Encoding]::ASCII)
        $commandShell = $env:COMSPEC
        if ([string]::IsNullOrWhiteSpace($commandShell)) {
            $commandShell = 'cmd.exe'
        }
        $shellArguments = '/d /s /c ""' + $launcherFile + '" ' +
            $baseArguments + '"'
        Invoke-ClaudeArgumentSmoke $commandShell $shellArguments 'CMD launcher'
    }
    finally {
        Remove-Item -LiteralPath $promptFile -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $launcherFile -Force -ErrorAction SilentlyContinue
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

foreach ($installerScript in @(
    'devcpp-i686.nsi', 'devcpp-x64.nsi', 'devcppnocompiler.nsi'
)) {
    Invoke-InstallerStaticCheck $installerScript
}

Invoke-AgentAsciiSourceCheck

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
