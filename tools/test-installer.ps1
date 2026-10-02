[CmdletBinding()]
param(
    [string]$Version = '1.0.3',
    [ValidateSet('Offline', 'Online')][string]$WebViewMode = 'Offline',
    [ValidateSet('all', 'cpp', 'ai', 'editor')][string]$Components = 'all',
    [switch]$NoDesktop,
    [switch]$TestBuild
)
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$product = 'DevCPlusAi'; $shortcut = 'DevCPlusAi'
$installer = Join-Path $repo "DevCPlusAi-$Version-windows-x64-gcc-setup.exe"
if ($WebViewMode -eq 'Online') { $installer = Join-Path $repo "DevCPlusAi-$Version-windows-online-setup.exe" }
if ($TestBuild) {
    $product = 'DevCPlusAi.InstallerTest'; $shortcut = 'DevCPlusAi Installer Test'
    $installer = Join-Path $repo "DevCPlusAi-$Version-$($WebViewMode.ToLowerInvariant())-installer-test.exe"
}
$key = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\$product"
$settingsKey = "HKCU:\Software\$product"
$startMenu = Join-Path ([Environment]::GetFolderPath('Programs')) $shortcut
$desktop = Join-Path ([Environment]::GetFolderPath('Desktop')) ($shortcut + '.lnk')
foreach ($path in @($key, $settingsKey, $startMenu, $desktop)) {
    if (Test-Path -LiteralPath $path) { throw "Existing installation would be affected: $path. Use -TestBuild with a test installer." }
}
$testRoot = Join-Path $repo ('.tools\setup acceptance ' + [Guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $testRoot | Out-Null

function Run([string]$File, [string]$Arguments, [int]$Expected = 0, [int]$Timeout = 180000) {
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $File; $info.Arguments = $Arguments; $info.WorkingDirectory = $testRoot
    $info.UseShellExecute = $false; $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true; $info.RedirectStandardError = $true
    if ([IO.Path]::GetFileName($File) -eq 'AgentWebPanelSmoke.exe') {
        $info.EnvironmentVariables['LOCALAPPDATA'] = (Join-Path $testRoot 'test-profile')
    }
    $p = New-Object Diagnostics.Process; $p.StartInfo = $info
    try {
        [void]$p.Start(); $out = $p.StandardOutput.ReadToEndAsync(); $err = $p.StandardError.ReadToEndAsync()
        if (-not $p.WaitForExit($Timeout)) { $p.Kill(); throw "Timed out: $File" }
        if ($p.ExitCode -ne $Expected) { throw "Unexpected exit $($p.ExitCode) from $File : $($out.Result) $($err.Result)" }
        if ($out.Result.Trim()) { Write-Host $out.Result.Trim() }
    } finally { $p.Dispose() }
}

$completed = $false
$hasCompiler = $Components -in @('all', 'cpp')
$hasAI = $Components -in @('all', 'ai')
$installArguments = "/S /COMPONENTS=$Components"
if ($NoDesktop) { $installArguments += ' /NODESKTOP' }
function Is-SelectedFile([string]$Name) {
    if ($Name -like 'MinGW64/*') { return $hasCompiler }
    if ($Name -match '^(AgentWeb/|nodejs/|claude-cli/|AgentWebHost\.dll$|AGENT-RUNTIME-VERSIONS\.txt$)') { return $hasAI }
    return $true
}
try {
    if ($TestBuild) {
        Run $installer ('/S /COMPONENTS=invalid /D=' + $testRoot) 1
        Run $installer ('/S /COMPONENTS=ai /TESTWEBVIEW=fail /D=' + $testRoot) 1
        if ((Test-Path -LiteralPath $key) -or (Test-Path -LiteralPath (Join-Path $testRoot 'devcpp.exe'))) {
            throw 'Failed prerequisite left a partial installation'
        }
        Write-Host 'PASS: invalid selection and failed WebView prerequisite leave no app files or registration.'
    }
    Run $installer ('/S /D=' + $testRoot + ' invalid%path') 1
    if (Test-Path -LiteralPath $key) { throw 'Invalid compiler directory was installed' }
    # Exercise missing-runtime branches without modifying the machine runtime.
    $prerequisite = ''
    if ($TestBuild) {
        $prerequisite = if ($hasAI) { ' /TESTWEBVIEW=success' } else { ' /TESTWEBVIEW=fail' }
    }
    Run $installer ($installArguments + $prerequisite + ' /D=' + $testRoot)
    $registration = Get-ItemProperty -LiteralPath $key
    if ($registration.DisplayVersion -ne $Version -or $registration.InstallLocation -ne $testRoot) { throw 'App registration mismatch' }
    $wsh = New-Object -ComObject WScript.Shell
    $links = @((Join-Path $startMenu 'DevCPlusAi.lnk'))
    if (-not $NoDesktop) { $links += $desktop }
    elseif (Test-Path -LiteralPath $desktop) { throw 'Unchecked desktop shortcut was created' }
    foreach ($link in $links) {
        if (-not (Test-Path -LiteralPath $link)) { throw "Shortcut missing: $link" }
        $resolved = $wsh.CreateShortcut($link)
        if ($resolved.TargetPath -ne (Join-Path $testRoot 'devcpp.exe') -or $resolved.WorkingDirectory -ne $testRoot) { throw "Shortcut target mismatch: $link" }
    }
    [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($wsh)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead((Join-Path $repo "DevCPlusAi-$Version-windows-x64-gcc.zip"))
    try {
        foreach ($entry in $archive.Entries) {
            if ($entry.FullName.EndsWith('/')) { continue }
            if (-not (Is-SelectedFile $entry.FullName)) {
                if (Test-Path -LiteralPath (Join-Path $testRoot $entry.FullName)) { throw "Unchecked component was installed: $($entry.FullName)" }
                continue
            }
            $stream = $entry.Open(); $sha = [Security.Cryptography.SHA256]::Create()
            try { $expectedHash = [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-', '') }
            finally { $sha.Dispose(); $stream.Dispose() }
            if ((Get-FileHash -LiteralPath (Join-Path $testRoot $entry.FullName)).Hash -ne $expectedHash) { throw "Installed content mismatch: $($entry.FullName)" }
        }
    } finally { $archive.Dispose() }
    Run (Join-Path $repo 'Source\Tests\AgentProviderSmoke.exe') ('--expect-ai "' + $testRoot + '" ' + [int]$hasAI)
    Write-Host "PASS: $Components selection, Start Menu, desktop preference, app registration, every installed file hash."
    New-Item -ItemType Directory -Path (Join-Path $testRoot 'config') | Out-Null
    $keptConfig = Join-Path $testRoot 'config\keep-user-data.txt'
    $keptSource = Join-Path $testRoot 'user-example.cpp'
    [IO.File]::WriteAllText($keptConfig, 'preserve-user-settings')
    [IO.File]::WriteAllText($keptSource, '#include <iostream>' + "`r`n" + 'int main(){std::cout << "installer-ok";}')
    if ($hasCompiler) {
        Run (Join-Path $testRoot 'MinGW64\bin\g++.exe') ('-static "' + $keptSource + '" -o "' + (Join-Path $testRoot 'sample.exe') + '"')
        Run (Join-Path $testRoot 'sample.exe') ''
    }
    if ($hasAI) {
        Copy-Item -LiteralPath (Join-Path $repo 'Source\Tests\AgentWebPanelSmoke.exe') -Destination $testRoot
        Run (Join-Path $testRoot 'AgentWebPanelSmoke.exe') '' 0 45000
    }
    Run $installer ($installArguments + ' /D=' + $testRoot)
    if ([IO.File]::ReadAllText($keptConfig) -ne 'preserve-user-settings') { throw 'Upgrade damaged user data' }
    $lock = [IO.File]::Open((Join-Path $testRoot 'devcpp.exe'), [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try { Run $installer ('/S /D=' + $testRoot) 1 } finally { $lock.Dispose() }
    Write-Host 'PASS: in-place reinstall preserves config; occupied application blocks overwrite.'
    if ($Components -eq 'editor') {
        Run $installer ('/S /COMPONENTS=all /D=' + $testRoot)
        if (-not (Test-Path -LiteralPath (Join-Path $testRoot 'MinGW64\bin\g++.exe'))) { throw 'Compiler add-on failed' }
        Run (Join-Path $repo 'Source\Tests\AgentProviderSmoke.exe') ('--expect-ai "' + $testRoot + '" 1')
        Run $installer ($installArguments + ' /D=' + $testRoot)
        if (-not (Test-Path -LiteralPath (Join-Path $testRoot 'MinGW64\bin\g++.exe'))) { throw 'Reinstall removed an existing component' }
        Run (Join-Path $repo 'Source\Tests\AgentProviderSmoke.exe') ('--expect-ai "' + $testRoot + '" 1')
        Write-Host 'PASS: editor-only install can add components and retains them on later unchecked reinstall.'
    }
    Run (Join-Path $testRoot 'Uninstall.exe') ('/S _?=' + $testRoot)
    if ((Test-Path -LiteralPath (Join-Path $testRoot 'devcpp.exe')) -or (Test-Path -LiteralPath $key) -or
        (Test-Path -LiteralPath $settingsKey) -or (Test-Path -LiteralPath $startMenu) -or (Test-Path -LiteralPath $desktop)) { throw 'Uninstall left product files or registration behind' }
    if ([IO.File]::ReadAllText($keptConfig) -ne 'preserve-user-settings' -or -not (Test-Path -LiteralPath $keptSource)) { throw 'Uninstall removed user data' }
    Write-Host 'PASS: uninstall removes app/shortcuts/registration and preserves source/configuration.'
    $completed = $true
    [ordered]@{installer=[IO.Path]::GetFileName($installer);sha256=(Get-FileHash -LiteralPath $installer).Hash;
        mode=$WebViewMode;components=$Components;installedFileHashes=$true;shortcuts=$true;registry=$true;compiler=$hasCompiler;webPanel=$hasAI;
        upgrade=$true;lockedExe=$true;uninstall=$true;userDataPreserved=$true;utc=[DateTime]::UtcNow.ToString('o')} |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $repo ".tools\installer-$Version-$WebViewMode-$Components-acceptance.json") -Encoding UTF8
} finally {
    if ($completed) {
        $allowed = (Join-Path $repo '.tools').TrimEnd('\') + '\'
        if (-not [IO.Path]::GetFullPath($testRoot).StartsWith($allowed, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe test cleanup path' }
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    } else { Write-Warning "Test files retained for investigation: $testRoot" }
}
