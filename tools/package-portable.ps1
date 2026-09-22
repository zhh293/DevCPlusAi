[CmdletBinding()]
param(
    [ValidatePattern('^[0-9A-Za-z][0-9A-Za-z._-]*$')]
    [string]$Version = 'dev',
    [ValidateSet('NoCompiler', 'X64Compiler')]
    [string]$PackageType = 'NoCompiler',
    [switch]$SelfExtracting,
    [string]$DevCppExePath
)

$ErrorActionPreference = 'Stop'
$RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))

& (Join-Path $PSScriptRoot 'verify-release.ps1') -PackageType $PackageType

$distRoot = Join-Path $RepoRoot 'dist'
$packageLabel = if ($PackageType -eq 'X64Compiler') {
    'windows-x64-gcc'
} else {
    'windows-no-compiler'
}
$packageRoot = Join-Path $distRoot ("DevCPlusAi-{0}-{1}" -f $Version, $packageLabel)
$zipPath = Join-Path $RepoRoot ("DevCPlusAi-{0}-{1}.zip" -f $Version, $packageLabel)
$sfxPath = Join-Path $RepoRoot ("DevCPlusAi-{0}-{1}-self-extracting.exe" -f $Version, $packageLabel)

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
    'AgentWebHost.dll',
    'RedPanda.ico',
    'LICENSE',
    'NEWS.txt',
    'README.md',
    'AGENT-RUNTIME-VERSIONS.txt'
)
foreach ($file in $files) {
    $sourceFile = Join-Path $RepoRoot $file
    if (($file -eq 'devcpp.exe') -and $DevCppExePath) {
        $sourceFile = [System.IO.Path]::GetFullPath($DevCppExePath)
        if (-not (Test-Path -LiteralPath $sourceFile -PathType Leaf)) {
            throw "Dev-C++ executable not found: $sourceFile"
        }
    }
    Copy-Item -LiteralPath $sourceFile -Destination $packageRoot -Force
}
$exeVersion = (Get-Item -LiteralPath (Join-Path $packageRoot 'devcpp.exe')).VersionInfo.ProductVersion
if ($Version -match '^\d+\.\d+\.\d+$' -and $exeVersion -ne $Version) {
    throw "Executable version $exeVersion does not match package $Version. Rebuild first."
}
foreach ($notes in Get-ChildItem -LiteralPath $RepoRoot -File -Filter 'RELEASE-*.md') {
    Copy-Item -LiteralPath $notes.FullName -Destination $packageRoot
}

$directories = @('AgentWeb', 'Lang', 'Templates', 'Icons', 'Help', 'contributes', 'nodejs', 'claude-cli')
if ($PackageType -eq 'X64Compiler') {
    $directories += 'MinGW64'
}
foreach ($directory in $directories) {
    Copy-Item -LiteralPath (Join-Path $RepoRoot $directory) -Destination $packageRoot -Recurse -Force
}
# Refuse a stale deployed web surface even if the executable has a new version.
$webSource = Join-Path $RepoRoot 'Source\AgentWeb'
foreach ($asset in @(Get-ChildItem -LiteralPath $webSource -File) + @(Get-ChildItem -LiteralPath (Join-Path $webSource 'vendor') -File)) {
    if ($asset.Name -eq 'README.md') { continue }
    $relative = $asset.FullName.Substring($webSource.Length + 1)
    $deployed = Join-Path $packageRoot ('AgentWeb\' + $relative)
    if (-not (Test-Path -LiteralPath $deployed) -or
        (Get-FileHash -LiteralPath $asset.FullName).Hash -ne (Get-FileHash -LiteralPath $deployed).Hash) {
        throw "Stale or missing web asset: $relative. Run build-windows.ps1 first."
    }
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
    $sourceCommitOutput = & $gitCommand.Source -c core.excludesFile= -C $RepoRoot rev-parse HEAD 2>$null
    if ($LASTEXITCODE -eq 0) {
        $sourceCommit = ($sourceCommitOutput | Out-String).Trim()
        $releaseInputs = @(
            'devcpp.exe', 'Packman.exe', 'PackMaker.exe', 'ConsolePauser.exe',
            'devcpp.exe.manifest', 'AgentWebHost.dll', 'RedPanda.ico', 'LICENSE',
            'NEWS.txt', 'README.md', 'AGENT-RUNTIME-VERSIONS.txt', 'AgentWeb',
            'Lang', 'Templates', 'Icons', 'Help', 'contributes', 'nodejs',
            'claude-cli', 'MinGW64', 'AStyle', 'ResEd', 'Source',
            'tools', 'installer', 'RELEASE-*.md', '.gitignore',
            ':(exclude)Source/Tests/dcu-agent-main',
            ':(exclude)Source/Tests/ui-compile.log'
        )
        $dirtyOutput = & $gitCommand.Source -c core.excludesFile= -C $RepoRoot status --porcelain --untracked-files=normal -- $releaseInputs 2>$null
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
$buildInfo.Add("Package-Type: $PackageType")
$buildInfo.Add("Executable-Version: $exeVersion")
$buildInfo.Add("Source-Commit: $sourceCommit")
$buildInfo.Add("Source-Dirty: $sourceDirty")
$buildInfo.Add("Generated-UTC: $([DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ'))")
$buildInfo.Add('')
$buildInfo.Add('Component SHA256:')
foreach ($component in @('devcpp.exe', 'Packman.exe', 'PackMaker.exe', 'ConsolePauser.exe', 'AgentWebHost.dll')) {
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

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
# Explicit relative file entries: no './' root entry, Unix attributes, symbolic
# links, or tar-specific ZIP extras. Windows Compressed Folders must see the same
# tree as 7-Zip. Deflate is supported by every Windows ZIP extractor.
$packageFiles = @(Get-ChildItem -LiteralPath $packageRoot -File -Recurse -Force | Sort-Object FullName)
if ($packageFiles.Count -ge 65535) { throw 'ZIP64 entry count would exceed the portable ZIP contract' }
$archive = [IO.Compression.ZipFile]::Open($zipPath, [IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($file in $packageFiles) {
        if ($file.Length -ge [uint32]::MaxValue) { throw "ZIP64 file is not supported: $($file.Name)" }
        if ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Package contains a link: $($file.FullName)" }
        $name = $file.FullName.Substring($packageRoot.Length + 1).Replace('\', '/')
        if ($name -match '(^|/)\.\.?(/|$)|[:\\]' -or $name.StartsWith('/')) { throw "Invalid ZIP entry: $name" }
        $entry = [IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $archive, $file.FullName, $name, [IO.Compression.CompressionLevel]::Optimal)
        $entry.ExternalAttributes = 32 # DOS archive attribute
    }
} finally { $archive.Dispose() }
$archive = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
try {
    $archiveEntries = @{}
    foreach ($entry in $archive.Entries) {
        $normalizedName = $entry.FullName
        if ($normalizedName -match '(^|/)\.\.?(/|$)|[:\\]' -or $normalizedName.StartsWith('/')) {
            throw "Non-portable ZIP entry: $normalizedName"
        }
        if ($archiveEntries.ContainsKey($normalizedName)) { throw "Duplicate ZIP entry: $normalizedName" }
        $archiveEntries[$normalizedName] = $entry
    }
    $requiredEntries = @(
        'devcpp.exe',
        'Packman.exe',
        'PackMaker.exe',
        'ConsolePauser.exe',
        'AgentWebHost.dll',
        'nodejs/node.exe',
        'claude-cli/bin/claude.exe',
        'AgentWeb/index.html',
        'AgentWeb/panel.js',
        'AgentWeb/panel.css',
        'AgentWeb/messages.js',
        'AgentWeb/highlight.js',
        'AgentWeb/highlight.css',
        'AgentWeb/layout.css',
        'AgentWeb/vendor/marked.umd.js',
        'AGENT-RUNTIME-VERSIONS.txt',
        'BUILD-INFO.txt'
    )
    if ($PackageType -eq 'X64Compiler') {
        $requiredEntries += @(
            'MinGW64/bin/g++.exe',
            'MinGW64/bin/gcc.exe',
            'MinGW64/bin/gdb.exe',
            'MinGW64/bin/mingw32-make.exe'
        )
    }
    foreach ($requiredEntry in $requiredEntries) {
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

# This calls Windows' own compressed-folder handler, not a substitute library.
$shell = New-Object -ComObject Shell.Application
$zipFolder = $shell.NameSpace($zipPath)
if ($null -eq $zipFolder -or $zipFolder.Items().Count -eq 0) {
    throw 'Windows Compressed Folders could not open the generated ZIP'
}
[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($zipFolder)
[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell)
Write-Host 'Windows Compressed Folders recognized the ZIP directory.'
& (Join-Path $PSScriptRoot 'test-portable-release.ps1') -ZipPath $zipPath

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

if ($SelfExtracting) {
    if (-not $sevenZip) {
        throw '7-Zip is required to build the self-extracting portable package.'
    }
    $sevenZipDirectory = Split-Path -Parent $sevenZipPath
    $sfxModule = Join-Path $sevenZipDirectory '7z.sfx'
    $sevenZipLicense = Join-Path $sevenZipDirectory 'License.txt'
    if (-not (Test-Path -LiteralPath $sfxModule -PathType Leaf)) {
        throw "7-Zip SFX module was not found: $sfxModule"
    }
    if (-not (Test-Path -LiteralPath $sevenZipLicense -PathType Leaf)) {
        throw "7-Zip redistribution license was not found: $sevenZipLicense"
    }
    Copy-Item -LiteralPath $sevenZipLicense -Destination (
        Join-Path $packageRoot '7-ZIP-LICENSE.txt') -Force

    if (Test-Path -LiteralPath $sfxPath) {
        Remove-Item -LiteralPath $sfxPath -Force
    }
    Push-Location $packageRoot
    try {
        # The payload already contains compressed Node/CLI assets. Moderate
        # compression keeps local release builds bounded without materially
        # inflating the self-extracting artifact.
        & $sevenZipPath 'a' '-t7z' '-mx=3' '-mmt=on' ("-sfx{0}" -f $sfxModule) $sfxPath '.\*'
        if ($LASTEXITCODE -ne 0) {
            Remove-Item -LiteralPath $sfxPath -Force -ErrorAction SilentlyContinue
            throw "7-Zip SFX creation failed with exit code $LASTEXITCODE"
        }
    }
    finally {
        Pop-Location
    }

    Write-Host 'Testing every self-extracting archive entry with 7-Zip...'
    & $sevenZipPath 't' '-bso0' '-bsp0' $sfxPath
    if ($LASTEXITCODE -ne 0) {
        throw "7-Zip SFX archive test failed with exit code $LASTEXITCODE"
    }
    $listedPaths = @(
        & $sevenZipPath 'l' '-slt' $sfxPath |
            Where-Object { $_ -like 'Path = *' } |
            ForEach-Object { $_.Substring(7) }
    )
    foreach ($requiredEntry in @(
        'devcpp.exe',
        'AgentWebHost.dll',
        'nodejs\node.exe',
        'claude-cli\bin\claude.exe',
        'AgentWeb\index.html',
        'AGENT-RUNTIME-VERSIONS.txt',
        'BUILD-INFO.txt',
        '7-ZIP-LICENSE.txt'
    )) {
        if ($listedPaths -notcontains $requiredEntry) {
            throw "Self-extracting package is missing: $requiredEntry"
        }
    }
    $sfx = Get-Item -LiteralPath $sfxPath
    $sfxHash = (Get-FileHash -LiteralPath $sfxPath -Algorithm SHA256).Hash
    Write-Host ("Self-extracting package: {0}" -f $sfx.FullName)
    Write-Host ("Size: {0} bytes" -f $sfx.Length)
    Write-Host ("SHA256: {0}" -f $sfxHash)
}

$zip = Get-Item -LiteralPath $zipPath
$hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash
Write-Host ("Portable package: {0}" -f $zip.FullName)
Write-Host ("Size: {0} bytes" -f $zip.Length)
Write-Host ("SHA256: {0}" -f $hash)
