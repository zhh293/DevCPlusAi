[CmdletBinding()]
param([string]$Destination = (Join-Path $PSScriptRoot '..'))
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$Destination = [IO.Path]::GetFullPath($Destination)
& (Join-Path $PSScriptRoot 'build-agent-web-probe.cmd')
if ($LASTEXITCODE -ne 0) { throw 'WebView2 bridge build failed' }
$assets = Join-Path $Destination 'AgentWeb'
New-Item -ItemType Directory -Force $assets | Out-Null
foreach ($name in @('index.html','panel.css','panel.js','messages.js','highlight.js','highlight.css')) {
    Copy-Item -LiteralPath (Join-Path $root "Source\AgentWeb\$name") -Destination $assets -Force
}
New-Item -ItemType Directory -Force (Join-Path $assets 'vendor') | Out-Null
Copy-Item -Path (Join-Path $root 'Source\AgentWeb\vendor\*') -Destination (Join-Path $assets 'vendor') -Force
$bridge = Join-Path $root '.tools\web-probe\AgentWebHost.dll'
if ($bridge -ne (Join-Path $Destination 'AgentWebHost.dll')) {
    Copy-Item -LiteralPath $bridge -Destination $Destination -Force
}
Write-Host "Web renderer deployed to $Destination"
