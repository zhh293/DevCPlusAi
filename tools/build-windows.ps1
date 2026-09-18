[CmdletBinding()]
param(
    [string]$Dcc32Path,
    [string]$DelphiLibPath,
    [string]$GppPath,
    [switch]$SkipConsolePauser
)

$ErrorActionPreference = 'Stop'

$RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$SourceRoot = Join-Path $RepoRoot 'Source'
$SkipRootDevCppCopy = $false

function Resolve-Executable {
    param(
        [string]$ExplicitPath,
        [string]$CommandName,
        [string[]]$Candidates
    )

    if ($ExplicitPath) {
        if (-not (Test-Path -LiteralPath $ExplicitPath -PathType Leaf)) {
            throw "Executable not found: $ExplicitPath"
        }
        return (Resolve-Path -LiteralPath $ExplicitPath).Path
    }

    $command = Get-Command $CommandName -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    foreach ($candidate in $Candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    throw "Unable to find $CommandName. Pass its full path explicitly."
}

function Invoke-NativeBuild {
    param(
        [string]$Executable,
        [string[]]$Arguments,
        [string]$Description
    )

    Write-Host "==> $Description"
    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Description failed with exit code $LASTEXITCODE"
    }
}

function Invoke-SmokeTest {
    param(
        [string]$Executable,
        [int]$TimeoutMilliseconds = 15000,
        [string]$Arguments = ''
    )

    Write-Host "==> Run $(Split-Path -Leaf $Executable)"
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $Executable
    $startInfo.Arguments = $Arguments
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    if (-not $process.Start()) {
        throw "Unable to start smoke test: $Executable"
    }
    if (-not $process.WaitForExit($TimeoutMilliseconds)) {
        $process.Kill()
        $process.WaitForExit()
        throw "Smoke test timed out after $TimeoutMilliseconds ms: $Executable"
    }
    $standardOutput = $process.StandardOutput.ReadToEnd()
    $standardError = $process.StandardError.ReadToEnd()
    if ($standardOutput) {
        Write-Host $standardOutput.TrimEnd()
    }
    if ($standardError) {
        Write-Host $standardError.TrimEnd()
    }
    if ($process.ExitCode -ne 0) {
        throw "Smoke test failed with exit code $($process.ExitCode): $Executable"
    }
}

$Dcc32Path = Resolve-Executable -ExplicitPath $Dcc32Path -CommandName 'dcc32.exe' -Candidates @(
    'C:\Program Files (x86)\Borland\Delphi7\Bin\DCC32.EXE',
    'C:\Program Files\Borland\Delphi7\Bin\DCC32.EXE'
)
$DelphiBinPath = Split-Path -Parent $Dcc32Path
$Brcc32Path = Resolve-Executable -CommandName 'brcc32.exe' -Candidates @(
    (Join-Path $DelphiBinPath 'BRCC32.EXE')
)

$libCandidates = @()
if ($DelphiLibPath) {
    $libCandidates += $DelphiLibPath
}
$libCandidates += (Join-Path (Split-Path -Parent $DelphiBinPath) 'Lib')
# Reuse a previously generated local DCU directory when a compact Delphi 7
# installation omits optional units such as Spin.dcu.
$libCandidates += (Join-Path $SourceRoot 'dcu')
# Some Delphi 7 installations keep the complete library on mounted media.
$libCandidates += 'F:\program files\Borland\Delphi7\Lib'

$DelphiLibPath = $null
foreach ($candidate in $libCandidates) {
    # Join-Path throws when an optional candidate points at an unmounted drive.
    if ($candidate -and
        (Test-Path -LiteralPath $candidate -PathType Container) -and
        (Test-Path -LiteralPath (Join-Path $candidate 'Spin.dcu') -PathType Leaf)) {
        $DelphiLibPath = (Resolve-Path -LiteralPath $candidate).Path
        break
    }
}
if (-not $DelphiLibPath) {
    throw 'Spin.dcu was not found. Pass -DelphiLibPath with the full Delphi 7 Lib directory.'
}

$mainUnitPaths = @(
    (Join-Path $SourceRoot 'VCL\ClassBrowsing'),
    (Join-Path $SourceRoot 'VCL\DevCpp'),
    (Join-Path $SourceRoot 'VCL\DevCpp\devFileMonitor'),
    (Join-Path $SourceRoot 'VCL\DevCpp\devShortcuts'),
    (Join-Path $SourceRoot 'VCL\DevCpp\CompOptionsList'),
    (Join-Path $SourceRoot 'VCL\SynEdit\Source'),
    (Join-Path $SourceRoot 'VCL\VirtualTreeView\Source'),
    $DelphiLibPath
)

$spinUpBmp = Join-Path $SourceRoot 'spinup.bmp'
$spinDownBmp = Join-Path $SourceRoot 'spindown.bmp'
Push-Location $SourceRoot
try {
    New-Item -ItemType Directory -Force -Path 'dcu' | Out-Null
    Invoke-NativeBuild $Brcc32Path @('manifest.rc') 'Compile application manifest'
    [IO.File]::WriteAllBytes($spinUpBmp,
        [Convert]::FromBase64String((Get-Content -Raw -LiteralPath 'spinup.bmp.b64').Trim()))
    [IO.File]::WriteAllBytes($spinDownBmp,
        [Convert]::FromBase64String((Get-Content -Raw -LiteralPath 'spindown.bmp.b64').Trim()))
    Invoke-NativeBuild $Brcc32Path @('spin.rc') 'Compile Spin resources'
    Invoke-NativeBuild $Dcc32Path @(
        '-B',
        'devcpp.dpr',
        '-N.\dcu',
        ('-U' + ($mainUnitPaths -join ';'))
    ) 'Compile Dev-C++'
    try {
        Copy-Item -LiteralPath 'devcpp.exe' -Destination (Join-Path $RepoRoot 'devcpp.exe') -Force
    }
    catch {
        $runningFromRepo = $false
        foreach ($process in @(Get-Process -Name 'devcpp' -ErrorAction SilentlyContinue)) {
            try {
                if ($process.Path -and [String]::Equals(
                    [System.IO.Path]::GetFullPath($process.Path),
                    (Join-Path $RepoRoot 'devcpp.exe'),
                    [StringComparison]::OrdinalIgnoreCase)) {
                    $runningFromRepo = $true
                    break
                }
            }
            catch { }
        }
        if (-not $runningFromRepo) { throw }
        $SkipRootDevCppCopy = $true
        Write-Warning 'Dev-C++ is running, so the root executable was left untouched. The fresh build remains at Source\devcpp.exe; close Dev-C++ and rerun to deploy it.'
    }
}
finally {
    Remove-Item -LiteralPath $spinUpBmp, $spinDownBmp -Force -ErrorAction SilentlyContinue
    Pop-Location
}

$protocolTestRoot = Join-Path $SourceRoot 'Tests'
Push-Location $protocolTestRoot
try {
    New-Item -ItemType Directory -Force -Path 'dcu' | Out-Null
    Invoke-NativeBuild $Dcc32Path @(
        '-B',
        'AgentProtocolSmoke.dpr',
        '-N.\dcu',
        ('-U' + $SourceRoot + ';' + (Join-Path $SourceRoot 'VCL\DevCpp'))
    ) 'Compile AgentProtocol smoke test'
    Invoke-SmokeTest (Join-Path $protocolTestRoot 'AgentProtocolSmoke.exe')
    Invoke-NativeBuild $Dcc32Path @(
        '-B',
        'AgentReaderSmoke.dpr',
        '-N.\dcu',
        ('-U' + $SourceRoot)
    ) 'Compile AgentReader smoke test'
    Invoke-SmokeTest (Join-Path $protocolTestRoot 'AgentReaderSmoke.exe')
    Invoke-NativeBuild $Dcc32Path @(
        '-B',
        'AgentPipeIOSmoke.dpr',
        '-N.\dcu',
        ('-U' + $SourceRoot)
    ) 'Compile AgentPipeIO smoke test'
    Invoke-SmokeTest (Join-Path $protocolTestRoot 'AgentPipeIOSmoke.exe')
    Invoke-NativeBuild $Dcc32Path @(
        '-B',
        'AgentUISmoke.dpr',
        '-N.\dcu',
        ('-R' + $SourceRoot),
        ('-U' + $SourceRoot + ';' + ($mainUnitPaths -join ';'))
    ) 'Compile Agent UI smoke test'
    Invoke-SmokeTest (Join-Path $protocolTestRoot 'AgentUISmoke.exe')
    Invoke-NativeBuild $Dcc32Path @(
        '-B',
        'AgentProviderSmoke.dpr',
        '-N.\dcu',
        ('-R' + $SourceRoot),
        ('-U' + $SourceRoot + ';' + ($mainUnitPaths -join ';'))
    ) 'Compile Agent provider smoke test'
    Invoke-SmokeTest (Join-Path $protocolTestRoot 'AgentProviderSmoke.exe')
    New-Item -ItemType Directory -Force -Path 'dcu-agent-main' | Out-Null
    Invoke-NativeBuild $Dcc32Path @('-B', 'AgentFixtureCli.dpr', '-N.\dcu-agent-main') 'Compile local Agent CLI fixture'
    Invoke-NativeBuild $Dcc32Path @(
        '-B', '-DAGENT_TESTS', 'AgentMainSmoke.dpr', '-N.\dcu-agent-main',
        ('-R' + $SourceRoot),
        ('-U' + $SourceRoot + ';' + ($mainUnitPaths -join ';'))
    ) 'Compile Agent main integration tests'
    $agentTestRoot = Join-Path $RepoRoot ('.tools\ai-' + [Guid]::NewGuid().ToString('N').Substring(0,8))
    New-Item -ItemType Directory -Force -Path $agentTestRoot | Out-Null
    $agentFixture = Join-Path $protocolTestRoot 'AgentFixtureCli.exe'
    Invoke-SmokeTest (Join-Path $protocolTestRoot 'AgentMainSmoke.exe') -TimeoutMilliseconds 45000 -Arguments ('"' + $agentTestRoot + '" "' + $agentFixture + '"')
}
finally {
    Pop-Location
}

$packmanRoot = Join-Path $SourceRoot 'Tools\Packman'
Push-Location $packmanRoot
try {
    New-Item -ItemType Directory -Force -Path 'dcu' | Out-Null
    Invoke-NativeBuild $Dcc32Path @(
        '-B',
        'Packman.dpr',
        '-N.\dcu',
        ('-U' + (Join-Path $SourceRoot 'VCL\DevCpp'))
    ) 'Compile Packman'
    Copy-Item -LiteralPath 'Packman.exe' -Destination (Join-Path $RepoRoot 'Packman.exe') -Force
}
finally {
    Pop-Location
}

$packMakerRoot = Join-Path $SourceRoot 'Tools\PackMaker'
Push-Location $packMakerRoot
try {
    New-Item -ItemType Directory -Force -Path 'dcu' | Out-Null
    Invoke-NativeBuild $Dcc32Path @('-B', 'PackMaker.dpr', '-N.\dcu') 'Compile PackMaker'
    Copy-Item -LiteralPath 'PackMaker.exe' -Destination (Join-Path $RepoRoot 'PackMaker.exe') -Force
}
finally {
    Pop-Location
}

if (-not $SkipConsolePauser) {
    $GppPath = Resolve-Executable -ExplicitPath $GppPath -CommandName 'g++.exe' -Candidates @(
        (Join-Path $RepoRoot 'MinGW64\bin\g++.exe'),
        'C:\TDM-GCC-64\bin\g++.exe'
    )
    $consoleRoot = Join-Path $SourceRoot 'Tools\ConsolePauser'
    $consoleOutput = Join-Path $consoleRoot 'ConsolePauser.exe'
    Push-Location $consoleRoot
    try {
        Invoke-NativeBuild $GppPath @(
            '-O2', '-s', '-static', '-static-libgcc', '-static-libstdc++',
            '-o', $consoleOutput, 'main.cpp'
        ) 'Compile ConsolePauser'
        Invoke-NativeBuild 'cmd.exe' @(
            '/d', '/c', ('(echo.)| "' + $consoleOutput + '" 0 where.exe cmd.exe')
        ) 'Run ConsolePauser smoke test'
        Copy-Item -LiteralPath $consoleOutput -Destination (Join-Path $RepoRoot 'ConsolePauser.exe') -Force
    }
    finally {
        Pop-Location
    }
}

& (Join-Path $PSScriptRoot 'deploy-agent-web.ps1') -Destination $RepoRoot
$devCppOutput = 'devcpp.exe'
if ($SkipRootDevCppCopy) { $devCppOutput = 'Source\devcpp.exe' }
$requiredOutputs = @($devCppOutput, 'Packman.exe', 'PackMaker.exe', 'AgentWebHost.dll')
if (-not $SkipConsolePauser) {
    $requiredOutputs += 'ConsolePauser.exe'
}

Write-Host '==> Build outputs'
foreach ($name in $requiredOutputs) {
    $path = Join-Path $RepoRoot $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Expected build output is missing: $path"
    }
    $item = Get-Item -LiteralPath $path
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    Write-Host ("{0} ({1} bytes) SHA256={2}" -f $name, $item.Length, $hash)
}

Write-Host 'Windows build completed successfully.'
