# ServerBridge.LicenseScan module.
# The scan itself lives in Invoke-LicenseScan.ps1 (the same file shipped as the standalone GitHub
# release download), so there is one copy of the logic. Dot-sourcing it loads the functions without
# running a scan: the script only runs its main entry point when it is not dot-sourced.
. (Join-Path $PSScriptRoot 'Invoke-LicenseScan.ps1')

function Invoke-LicenseScan {
    <#
    .SYNOPSIS
        Free, read-only Microsoft 365 unused-license scan.

    .DESCRIPTION
        Signs in to Microsoft Graph with a device code (read-only scopes, nothing to register),
        cross-checks every assigned license against real activity, prints the wasted spend by
        license and saves a per-user CSV. It never changes anything in your tenant and stores
        nothing.

        Uses directory sign-in activity when the tenant has Microsoft Entra ID P1/P2, otherwise
        Microsoft 365 usage reports. If Microsoft is hiding user names in those reports, the scan
        explains the one-minute fix and lets you check again without signing in again.

    .PARAMETER InactiveDays
        A licensed user with no activity in this many days counts as dormant. Default 90. Range 1-3650.

    .PARAMETER OutputCsv
        Path for the CSV export. Default: license-scan_<tenant>_<date>.csv in the current folder.

    .PARAMETER IncludeGuests
        Also score guest (external) users. Off by default.

    .PARAMETER PassThru
        Also return the dormant-seat objects to the pipeline.

    .EXAMPLE
        Install-Module ServerBridge.LicenseScan -Scope CurrentUser
        Invoke-LicenseScan

    .EXAMPLE
        Invoke-LicenseScan -InactiveDays 60 -OutputCsv C:\reports\waste.csv

    .LINK
        https://github.com/lbcrowe-del/ServerBridge-LicenseScan

    .LINK
        https://server-bridge.com/license-auditor.html
    #>
    [CmdletBinding()]
    param(
        [ValidateRange(1, 3650)]
        [int]$InactiveDays = 90,

        [string]$OutputCsv,

        [switch]$IncludeGuests,

        [switch]$PassThru
    )

    Invoke-LicenseScanMain -InactiveDays $InactiveDays -OutputCsv $OutputCsv `
        -IncludeGuests:$IncludeGuests -PassThru:$PassThru
}

Export-ModuleMember -Function Invoke-LicenseScan
