[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ZipPath)
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$ZipPath = (Resolve-Path -LiteralPath $ZipPath).Path
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Run-Probe([string]$File, [string]$Arguments, [int]$Timeout = 45000) {
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $File
    $info.Arguments = $Arguments
    $info.WorkingDirectory = $testRoot
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    # Do not share the user's browser profile or application settings.
    $info.EnvironmentVariables['LOCALAPPDATA'] = (Join-Path $testRoot 'test-profile')
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $info
    try {
        if (-not $process.Start()) { throw "Probe failed to start: $File" }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($Timeout)) {
            $process.Kill(); $process.WaitForExit()
            throw "Probe timed out: $File"
        }
        $message = ($stdout.Result + $stderr.Result).Trim()
        if ($process.ExitCode -ne 0) { throw "Probe failed ($($process.ExitCode)): $File`n$message" }
        Write-Host $message
        return $message
    } finally { $process.Dispose() }
}

$suffix = [Guid]::NewGuid().ToString('N').Substring(0,8)
$unicodeName = -join [char[]](0x53d1,0x5e03,0x9a8c,0x6536)
$testRoot = Join-Path $repo ('.tools\release app ' + $suffix)
New-Item -ItemType Directory -Path $testRoot | Out-Null
$archive = [IO.Compression.ZipFile]::OpenRead($ZipPath)
$shell = $null; $sourceFolder = $null; $destination = $null
try {
    $expected = @($archive.Entries | Where-Object { -not $_.FullName.EndsWith('/') })
    if ($expected.Count -eq 0) { throw 'Empty release ZIP' }
    foreach ($entry in $expected) {
        if ($entry.FullName -match '(^|/)\.\.?(/|$)|[:\\]' -or $entry.FullName.StartsWith('/')) { throw "Unsafe ZIP entry: $($entry.FullName)" }
    }
    $shell = New-Object -ComObject Shell.Application
    $sourceFolder = $shell.NameSpace($ZipPath)
    $destination = $shell.NameSpace($testRoot)
    if ($null -eq $sourceFolder -or $sourceFolder.Items().Count -eq 0) { throw 'Windows cannot read this ZIP' }
    Write-Host "Extracting $($expected.Count) files with Windows Compressed Folders..."
    $destination.CopyHere($sourceFolder.Items(), (4 + 16 + 512 + 1024))
    $deadline = [DateTime]::UtcNow.AddMinutes(6)
    do {
        Start-Sleep -Milliseconds 1000
        $count = [IO.Directory]::GetFiles($testRoot, '*', [IO.SearchOption]::AllDirectories).Length
        if ([DateTime]::UtcNow -gt $deadline) { throw "Windows extraction timed out ($count/$($expected.Count) files)" }
    } while ($count -lt $expected.Count)
    if ($count -ne $expected.Count) { throw 'Windows extracted an unexpected number of files' }
    # CopyHere is asynchronous. Verify every byte, including files being flushed.
    foreach ($entry in $expected) {
        $path = Join-Path $testRoot $entry.FullName.Replace('/', '\')
        $stream = $entry.Open(); $sha = [Security.Cryptography.SHA256]::Create()
        try { $hash = [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-', '') }
        finally { $sha.Dispose(); $stream.Dispose() }
        $verified = $false
        for ($attempt = 0; $attempt -lt 20; $attempt++) {
            try { $verified = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -eq $hash } catch { $verified = $false }
            if ($verified) { break }
            Start-Sleep -Milliseconds 500
        }
        if (-not $verified) { throw "Windows extraction content mismatch: $($entry.FullName)" }
    }
    Write-Host "PASS: Windows extracted all $count files with matching SHA256."
    # Web assets support Unicode/punctuation independently of the legacy GCC
    # toolchain (whose specs treat '%' specially in its installation path).
    $webRoot = Join-Path $testRoot ($unicodeName + ' WebView # % &')
    New-Item -ItemType Directory -Path $webRoot | Out-Null
    Copy-Item -LiteralPath (Join-Path $testRoot 'AgentWeb') -Destination $webRoot -Recurse
    Copy-Item -LiteralPath (Join-Path $testRoot 'AgentWebHost.dll') -Destination $webRoot
    foreach ($probe in @('AgentWebNavigationSmoke.exe', 'AgentWebPanelSmoke.exe')) {
        Copy-Item -LiteralPath (Join-Path $repo "Source\Tests\$probe") -Destination $webRoot
    }
    $bridge = Join-Path $webRoot 'AgentWebHost.dll'
    $page = Join-Path $webRoot 'AgentWeb\index.html'
    $profile = Join-Path $testRoot 'test-profile\raw'
    $webResult = Run-Probe (Join-Path $webRoot 'AgentWebNavigationSmoke.exe') ('"' + $bridge + '" "' + $page + '" "' + $profile + '"')
    $panelResult = Run-Probe (Join-Path $webRoot 'AgentWebPanelSmoke.exe') ''
    $compilerResult = 'Not bundled'
    $compiler = Join-Path $testRoot 'MinGW64\bin\g++.exe'
    if (Test-Path -LiteralPath $compiler) {
        $cpp = Join-Path $testRoot 'release-test.cpp'; $exe = Join-Path $testRoot 'release-test.exe'
        [IO.File]::WriteAllText($cpp, '#include <iostream>' + "`r`n" + 'int main(){std::cout << "compiler-ok";}', [Text.Encoding]::ASCII)
        [void](Run-Probe $compiler ('-std=c++11 -static -o "' + $exe + '" "' + $cpp + '"'))
        $compilerResult = Run-Probe $exe ''
        if ($compilerResult -ne 'compiler-ok') { throw 'Bundled C++ executable did not run correctly' }
    }
    $report = [ordered]@{
        archive = [IO.Path]::GetFileName($ZipPath)
        sha256 = (Get-FileHash -LiteralPath $ZipPath -Algorithm SHA256).Hash
        windowsShellExtraction = $true
        verifiedFiles = $count
        webPathCases = 'Chinese, spaces, #, %, &'
        compilerPathCases = 'ASCII with spaces (GCC installation paths containing percent or hash are unsupported)'
        productVersion = (Get-Item -LiteralPath (Join-Path $testRoot 'devcpp.exe')).VersionInfo.ProductVersion
        web = $webResult
        panel = $panelResult
        compiler = $compilerResult
        utc = [DateTime]::UtcNow.ToString('o')
    }
    $reportPath = Join-Path $repo ('.tools\' + [IO.Path]::GetFileNameWithoutExtension($ZipPath) + '-acceptance.json')
    $report | ConvertTo-Json | Set-Content -LiteralPath $reportPath -Encoding UTF8
    Write-Host "Acceptance report: $reportPath"
} finally {
    $archive.Dispose()
    foreach ($com in @($destination, $sourceFolder, $shell)) {
        if ($null -ne $com) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($com) }
    }
    $allowed = [IO.Path]::GetFullPath((Join-Path $repo '.tools')).TrimEnd('\') + '\'
    if (-not [IO.Path]::GetFullPath($testRoot).StartsWith($allowed, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe test cleanup path' }
    # Let WebView2 finish closing its own profile handles before cleanup.
    Start-Sleep -Milliseconds 500
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
