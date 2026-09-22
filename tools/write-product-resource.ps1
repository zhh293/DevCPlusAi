[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Brcc32Path)
$ErrorActionPreference = 'Stop'
$source = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\Source'))
$text = [IO.File]::ReadAllText((Join-Path $source 'Version.pas'))
$version = [regex]::Match($text, "DEVCPP_VERSION = '([0-9]+\.[0-9]+\.[0-9]+)'").Groups[1].Value
if (-not $version) { throw 'Missing product version in Version.pas' }
$numeric = $version.Replace('.', ',') + ',0'
$rc = @"
1 VERSIONINFO
FILEVERSION $numeric
PRODUCTVERSION $numeric
FILEOS 0x40004
FILETYPE 0x1
BEGIN
 BLOCK "StringFileInfo"
 BEGIN
  BLOCK "040904E4"
  BEGIN
   VALUE "CompanyName", "DevCPlusAi contributors\0"
   VALUE "FileDescription", "DevCPlusAi IDE\0"
   VALUE "FileVersion", "$version\0"
   VALUE "ProductName", "DevCPlusAi\0"
   VALUE "ProductVersion", "$version\0"
   VALUE "OriginalFilename", "devcpp.exe\0"
  END
 END
 BLOCK "VarFileInfo"
 BEGIN
  VALUE "Translation", 0x0409, 1252
 END
END
"@
$rcPath = Join-Path $source 'ProductVersion.generated.rc'
$resPath = Join-Path $source 'ProductVersion.generated.res'
[IO.File]::WriteAllText($rcPath, $rc, [Text.Encoding]::ASCII)
& $Brcc32Path ('-fo' + $resPath) $rcPath
if ($LASTEXITCODE -ne 0) { throw 'Product version resource compilation failed' }
# Keep the original application icon; replace its legacy VERSIONINFO resource.
$original = [IO.File]::ReadAllBytes((Join-Path $source 'devcpp.res'))
$output = New-Object IO.MemoryStream
try {
    $position = 0
    while ($position -lt $original.Length) {
        $dataSize = [BitConverter]::ToUInt32($original, $position)
        $headerSize = [BitConverter]::ToUInt32($original, $position + 4)
        $size = [int](($dataSize + $headerSize + 3) -band 0xfffffffcL)
        if ($size -lt 32 -or $position + $size -gt $original.Length) { throw 'Invalid base resource' }
        $ordinal = [BitConverter]::ToUInt16($original, $position + 8)
        $type = [BitConverter]::ToUInt16($original, $position + 10)
        if ($ordinal -ne 65535 -or $type -ne 16) { $output.Write($original, $position, $size) }
        $position += $size
    }
    $generated = [IO.File]::ReadAllBytes($resPath)
    $output.Write($generated, 32, $generated.Length - 32)
    [IO.File]::WriteAllBytes((Join-Path $source 'Product.generated.res'), $output.ToArray())
} finally { $output.Dispose() }
Write-Host "Product resources: DevCPlusAi $version"
