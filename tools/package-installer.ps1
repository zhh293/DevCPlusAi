[CmdletBinding()]
param(
    [string]$Version = '1.0.2',
    [string]$NsisPath,
    [string]$WebViewInstallerPath,
    [switch]$TestBuild
)
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw 'Installer version must use major.minor.patch' }
$zip = Join-Path $repo "DevCPlusAi-$Version-windows-x64-gcc.zip"
$reportFile = Join-Path $repo ".tools\DevCPlusAi-$Version-windows-x64-gcc-acceptance.json"
if (-not (Test-Path -LiteralPath $zip) -or -not (Test-Path -LiteralPath $reportFile)) {
    throw 'Build and validate the compiler ZIP with package-portable.ps1 first.'
}
$report = Get-Content -LiteralPath $reportFile -Raw | ConvertFrom-Json
if ($report.sha256 -ne (Get-FileHash -LiteralPath $zip).Hash -or
    -not $report.windowsShellExtraction -or $report.compiler -ne 'compiler-ok' -or $report.productVersion -ne $Version) {
    throw 'The ZIP does not have a matching successful release acceptance report.'
}
if (-not $NsisPath) {
    $NsisPath = Join-Path $repo '.tools\nsis\nsis-3.11\makensis.exe'
    if (-not (Test-Path -LiteralPath $NsisPath)) { $NsisPath = (Get-Command makensis.exe -ErrorAction Stop).Source }
}
if (-not $WebViewInstallerPath) { $WebViewInstallerPath = Join-Path $repo '.tools\downloads\MicrosoftEdgeWebView2RuntimeInstallerX64.exe' }
$signature = Get-AuthenticodeSignature -LiteralPath $WebViewInstallerPath
if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') {
    throw 'The offline WebView2 installer must have a valid Microsoft signature.'
}
$buildRoot = Join-Path $repo ('.tools\installer-' + [Guid]::NewGuid().ToString('N').Substring(0,8))
$payload = Join-Path $buildRoot 'payload'
New-Item -ItemType Directory -Path $payload -Force | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::ExtractToDirectory($zip, $payload)
$files = @(Get-ChildItem -LiteralPath $payload -File -Recurse)
$manifest = New-Object Collections.Generic.List[string]
foreach ($file in $files) {
    $relative = $file.FullName.Substring($payload.Length + 1)
    if ($relative -match '[\r\n"$]') { throw "Unsupported NSIS filename: $relative" }
    $manifest.Add('Delete "$INSTDIR\' + $relative + '"')
}
foreach ($directory in (Get-ChildItem -LiteralPath $payload -Directory -Recurse | Sort-Object { $_.FullName.Length } -Descending)) {
    $relative = $directory.FullName.Substring($payload.Length + 1)
    $manifest.Add('RMDir "$INSTDIR\' + $relative + '"')
}
$manifestPath = Join-Path $buildRoot 'delete-files.nsh'
[IO.File]::WriteAllLines($manifestPath, $manifest, (New-Object Text.UTF8Encoding($true)))
$name = "DevCPlusAi-$Version-windows-x64-gcc-setup.exe"
if ($TestBuild) { $name = "DevCPlusAi-$Version-installer-test.exe" }
$output = Join-Path $repo $name
$arguments = @('/V2', '/INPUTCHARSET', 'UTF8', "/DVERSION=$Version", "/DOUTPUT=$output", "/DPAYLOAD=$payload",
    "/DWEBVIEW_INSTALLER=$WebViewInstallerPath", "/DDELETE_MANIFEST=$manifestPath",
    ('/DINSTALLED_KB=' + [int][Math]::Ceiling(($files | Measure-Object Length -Sum).Sum / 1024)))
if ($TestBuild) { $arguments += @('/DPRODUCT_KEY=DevCPlusAi.InstallerTest', '/DSHORTCUT_NAME=DevCPlusAi Installer Test') }
$arguments += (Join-Path $repo 'installer\DevCPlusAi.nsi')
try {
    & $NsisPath @arguments
    if ($LASTEXITCODE -ne 0) { throw "NSIS build failed: $LASTEXITCODE" }
    $hash = (Get-FileHash -LiteralPath $output).Hash
    Write-Host "Installer: $output"
    Write-Host "SHA256: $hash"
} finally {
    $allowed = (Join-Path $repo '.tools').TrimEnd('\') + '\'
    if (-not [IO.Path]::GetFullPath($buildRoot).StartsWith($allowed, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe installer cleanup path' }
    Remove-Item -LiteralPath $buildRoot -Recurse -Force
}
