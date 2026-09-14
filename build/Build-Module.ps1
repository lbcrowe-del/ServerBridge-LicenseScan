<#
.SYNOPSIS
    Stages the ServerBridge.LicenseScan module in out/ServerBridge.LicenseScan and validates it.
    Outputs the staged folder path. Used by CI, the release workflow and the module tests.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$repo   = Split-Path -Parent $PSScriptRoot
$source = Join-Path $repo 'ServerBridge.LicenseScan'
$out    = Join-Path (Join-Path $repo 'out') 'ServerBridge.LicenseScan'

if (Test-Path $out) { Remove-Item -Path $out -Recurse -Force }
New-Item -ItemType Directory -Path $out -Force | Out-Null

Copy-Item -Path (Join-Path $source 'ServerBridge.LicenseScan.psd1') -Destination $out
Copy-Item -Path (Join-Path $source 'ServerBridge.LicenseScan.psm1') -Destination $out
Copy-Item -Path (Join-Path $repo 'Invoke-LicenseScan.ps1') -Destination $out
Copy-Item -Path (Join-Path $repo 'LICENSE') -Destination $out

Test-ModuleManifest -Path (Join-Path $out 'ServerBridge.LicenseScan.psd1') | Out-Null
$out
