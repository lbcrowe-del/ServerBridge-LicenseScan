# ServerBridge.LicenseScan module.
# Each command lives in the same .ps1 file that ships as a standalone GitHub release download, so
# there is one copy of the logic. Dot-sourcing loads the functions without running anything: each
# script only runs its main entry point when it is not dot-sourced.
#
# Invoke-LicenseScan.ps1 also holds the helpers both commands share (device-code sign-in with the
# 2-minute retry, the activity signal with its usage-report fallback, CSV escaping), so it must be
# dot-sourced first.
. (Join-Path $PSScriptRoot 'Invoke-LicenseScan.ps1')
. (Join-Path $PSScriptRoot 'Invoke-OffboardingCheck.ps1')

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

function Invoke-OffboardingCheck {
    <#
    .SYNOPSIS
        Free, read-only Microsoft 365 offboarding check.

    .DESCRIPTION
        Finds accounts that look like leavers - disabled, or no activity for -InactiveDays - and
        shows what each one still holds: paid licenses, how many groups it is still a member of,
        and whether its mailbox was never converted to shared.

        Signs in to Microsoft Graph with a device code (read-only scopes, nothing to register).
        It never changes anything in your tenant and stores nothing: you act on the list yourself.

        Uses directory sign-in activity when the tenant has Microsoft Entra ID P1/P2, otherwise
        Microsoft 365 usage reports. Mailbox type comes from Microsoft's mailbox usage report,
        which lags a day or two and is unavailable when your tenant conceals user names in
        reports - both cases are reported rather than guessed.

    .PARAMETER InactiveDays
        An account with no activity in this many days is treated as a possible leaver.
        Default 90. Range 1-3650.

    .PARAMETER OutputCsv
        Path for the CSV export. Default: offboarding-check_<tenant>_<date>.csv in the current folder.

    .PARAMETER IncludeGuests
        Also include guest (external) users. Off by default.

    .PARAMETER PassThru
        Also return the finding objects to the pipeline.

    .EXAMPLE
        Install-Module ServerBridge.LicenseScan -Scope CurrentUser
        Invoke-OffboardingCheck

    .EXAMPLE
        Invoke-OffboardingCheck -InactiveDays 30 -OutputCsv C:\reports\leavers.csv

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

    Invoke-OffboardingCheckMain -InactiveDays $InactiveDays -OutputCsv $OutputCsv `
        -IncludeGuests:$IncludeGuests -PassThru:$PassThru
}

Export-ModuleMember -Function Invoke-LicenseScan, Invoke-OffboardingCheck
