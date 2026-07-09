<#
.SYNOPSIS
    Free, read-only Microsoft 365 unused-license scan.
    Cross-checks every assigned license against real sign-in activity and
    reports the seats you're paying for but nobody is using.

.DESCRIPTION
    Community edition of the ServerBridge License Auditor. Connects to Microsoft
    Graph with delegated, READ-ONLY scopes via device-code sign-in (nothing to
    register, no app, no secrets). It never writes, removes, or changes anything
    in your tenant, and it stores nothing.

    Outputs:
      * A console summary of wasted spend by SKU
      * A CSV of every dormant licensed user (for your own follow-up)

    What it deliberately does NOT do (that's the paid ServerBridge audit):
      * Formatted PDF report you can hand to a boss or client
      * Per-SKU downgrade recommendations
      * Scheduled re-audits and month-over-month drift tracking
      * Service-level waste, guest/shared-license flags, multi-tenant roll-up
      * Support
    See https://server-bridge.com/license-auditor.html

.PARAMETER InactiveDays
    A licensed user with no interactive sign-in in this many days is counted
    as dormant. Default 90. Range 1-3650.

.PARAMETER OutputCsv
    Path for the CSV export. Default: .\license-scan_<tenant>_<date>.csv

.PARAMETER IncludeGuests
    Include guest (external) users in the scan. Off by default - guests are
    rarely the licensing waste you're looking for.

.PARAMETER PassThru
    Emit the dormant-seat objects to the pipeline in addition to the CSV.

.EXAMPLE
    .\Invoke-LicenseScan.ps1

.EXAMPLE
    .\Invoke-LicenseScan.ps1 -InactiveDays 60 -OutputCsv C:\reports\waste.csv

.NOTES
    Requires the Microsoft Graph PowerShell SDK:
        Install-Module Microsoft.Graph -Scope CurrentUser
    Delegated scopes requested (all read-only):
        User.Read.All, Organization.Read.All, AuditLog.Read.All
    You must be able to consent to these (Global Reader is sufficient).
    Prices are public list-price ESTIMATES (USD/user/month) - adjust the
    price table below to match your actual contract for exact figures.

    Project: https://github.com/lbcrowe-del/ServerBridge-LicenseScan
    License: MIT
#>

[CmdletBinding()]
param(
    [ValidateRange(1, 3650)]
    [int]$InactiveDays = 90,

    [string]$OutputCsv,

    [switch]$IncludeGuests,

    [switch]$PassThru
)

$script:RequiredScopes = @('User.Read.All', 'Organization.Read.All', 'AuditLog.Read.All')

# --- Approximate public list prices, USD / user / month, keyed by SkuPartNumber.
# --- ESTIMATES so the tool can put a dollar figure on waste out of the box.
# --- Edit to match your real per-seat cost for precise numbers.
$script:SkuPrice = @{
    'O365_BUSINESS_ESSENTIALS' = 6.00    # Microsoft 365 Business Basic
    'O365_BUSINESS_PREMIUM'    = 12.50   # Microsoft 365 Business Standard
    'SPB'                      = 22.00   # Microsoft 365 Business Premium
    'ENTERPRISEPACK'           = 36.00   # Office 365 E3
    'ENTERPRISEPREMIUM'        = 57.00   # Office 365 E5
    'SPE_E3'                   = 36.00   # Microsoft 365 E3
    'SPE_E5'                   = 57.00   # Microsoft 365 E5
    'SPE_F1'                   = 8.00    # Microsoft 365 F3
    'DESKLESSPACK'             = 4.00    # Office 365 F3
    'EXCHANGESTANDARD'         = 4.00    # Exchange Online Plan 1
    'EXCHANGEENTERPRISE'       = 8.00    # Exchange Online Plan 2
    'MCOEV'                    = 8.00    # Teams Phone Standard
    'POWER_BI_PRO'             = 10.00   # Power BI Pro
    'POWER_BI_PREMIUM_PER_USER' = 20.00  # Power BI Premium Per User
    'PROJECTPROFESSIONAL'      = 30.00   # Project Plan 3
    'PROJECTPREMIUM'           = 55.00   # Project Plan 5
    'VISIOCLIENT'              = 15.00   # Visio Plan 2
    'Microsoft_365_Copilot'    = 30.00   # Microsoft 365 Copilot
    'FLOW_FREE'                = 0.00    # Power Automate (free)
    'TEAMS_EXPLORATORY'        = 0.00    # Teams Exploratory (free)
    'POWERAPPS_VIRAL'          = 0.00    # Power Apps (free/viral)
}
$script:DefaultPrice = 20.00  # fallback for SKUs not in the table

# ---------------------------------------------------------------------------
# Pure, testable helpers (no Graph calls - safe to dot-source)
# ---------------------------------------------------------------------------

function Get-SkuMonthlyPrice {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$PartNumber)
    if ($script:SkuPrice.ContainsKey($PartNumber)) { return [double]$script:SkuPrice[$PartNumber] }
    return [double]$script:DefaultPrice
}

function Test-UserDormant {
    <# Returns $true when a user has not signed in since $Cutoff (never-signed-in counts as dormant). #>
    [CmdletBinding()]
    param(
        [Parameter()][Nullable[datetime]]$LastSignIn,
        [Parameter(Mandatory)][datetime]$Cutoff
    )
    if ($null -eq $LastSignIn) { return $true }
    return ($LastSignIn -lt $Cutoff)
}

function Get-DormantLicenseRow {
    <#
    Pure projection: given users, a SkuId->PartNumber map and a cutoff, emit one
    row per dormant user per priced license. No Graph, no I/O - unit-testable.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Users,
        [Parameter(Mandatory)][hashtable]$SkuMap,
        [Parameter(Mandatory)][datetime]$Cutoff,
        [switch]$IncludeGuests
    )

    foreach ($u in $Users) {
        if (-not $IncludeGuests -and $u.UserType -eq 'Guest') { continue }

        $last = $u.SignInActivity.LastSignInDateTime
        if (-not (Test-UserDormant -LastSignIn $last -Cutoff $Cutoff)) { continue }

        foreach ($lic in $u.AssignedLicenses) {
            $part = $SkuMap[$lic.SkuId]
            if (-not $part) { continue }
            $price = Get-SkuMonthlyPrice -PartNumber $part
            if ($price -le 0) { continue }  # skip free SKUs

            [pscustomobject]@{
                DisplayName       = $u.DisplayName
                UserPrincipalName = $u.UserPrincipalName
                UserType          = $u.UserType
                AccountEnabled    = $u.AccountEnabled
                Sku               = $part
                LastSignIn        = if ($last) { ([datetime]$last).ToString('yyyy-MM-dd') } else { 'never' }
                MonthlyCost       = $price
                AnnualCost        = [math]::Round($price * 12, 2)
            }
        }
    }
}

# ---------------------------------------------------------------------------
# Main (Graph I/O). Kept in a function so tests can dot-source this file
# without connecting to a tenant.
# ---------------------------------------------------------------------------

function Invoke-LicenseScanMain {
    [CmdletBinding()]
    param(
        [int]$InactiveDays,
        [string]$OutputCsv,
        [switch]$IncludeGuests,
        [switch]$PassThru
    )

    Write-Host ''
    Write-Host 'ServerBridge - Free M365 License Scan (read-only)' -ForegroundColor Green
    Write-Host '-------------------------------------------------' -ForegroundColor DarkGray

    if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
        Write-Host 'Microsoft Graph PowerShell SDK not found.' -ForegroundColor Yellow
        Write-Host 'Install it with:  Install-Module Microsoft.Graph -Scope CurrentUser' -ForegroundColor Yellow
        return
    }

    try {
        Write-Host 'Signing you in (a device code will appear below)...' -ForegroundColor Cyan
        Connect-MgGraph -Scopes $script:RequiredScopes -UseDeviceCode -NoWelcome -ErrorAction Stop
    } catch {
        Write-Host "Sign-in failed: $($_.Exception.Message)" -ForegroundColor Red
        return
    }

    $ctx = Get-MgContext
    if (-not $ctx) { Write-Host 'Sign-in cancelled.' -ForegroundColor Red; return }

    try {
        $org = Get-MgOrganization -ErrorAction Stop
        $tenantName = ($org.DisplayName | Select-Object -First 1)
        Write-Host "Connected to: $tenantName" -ForegroundColor Green

        $guestNote = if ($IncludeGuests) { ' (including guests)' } else { '' }
        Write-Host "Flagging licensed users with no sign-in in $InactiveDays+ days$guestNote..." -ForegroundColor Cyan

        # SKU GUID -> part number
        $skuMap = @{}
        foreach ($s in (Get-MgSubscribedSku -All -ErrorAction Stop)) {
            $skuMap[$s.SkuId] = $s.SkuPartNumber
        }

        # Licensed users with last sign-in. The SDK retries throttled (429) calls automatically.
        $select = 'id,displayName,userPrincipalName,userType,accountEnabled,assignedLicenses,signInActivity'
        $users = Get-MgUser -All -Property $select `
            -Filter 'assignedLicenses/$count ne 0' `
            -ConsistencyLevel eventual -CountVariable null -ErrorAction Stop
    } catch {
        Write-Host "Graph read failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host 'Confirm you consented to User.Read.All, Organization.Read.All and AuditLog.Read.All.' -ForegroundColor Yellow
        Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
        return
    }

    $cutoff = (Get-Date).AddDays(-1 * $InactiveDays)
    $dormant = @(Get-DormantLicenseRow -Users $users -SkuMap $skuMap -Cutoff $cutoff -IncludeGuests:$IncludeGuests)

    # Summarise
    Write-Host ''
    Write-Host "Wasted spend by license (dormant $InactiveDays+ days)" -ForegroundColor Green
    Write-Host '-----------------------------------------------------' -ForegroundColor DarkGray

    if ($dormant.Count -eq 0) {
        Write-Host '  No dormant licensed users found. Nothing obvious to reclaim.' -ForegroundColor Green
    } else {
        $dormant | Group-Object Sku | ForEach-Object {
            [pscustomobject]@{
                License      = $_.Name
                DormantSeats = $_.Count
                'Annual $'   = [math]::Round((($_.Group | Measure-Object AnnualCost -Sum).Sum), 0)
            }
        } | Sort-Object 'Annual $' -Descending | Format-Table -AutoSize
    }

    $totalSeats = $dormant.Count
    $totalAnnual = [math]::Round((($dormant | Measure-Object AnnualCost -Sum).Sum), 0)
    Write-Host ''
    Write-Host ("  Reclaimable seats : {0:N0}" -f $totalSeats) -ForegroundColor White
    Write-Host ("  Wasted spend      : `${0:N0} / year" -f $totalAnnual) -ForegroundColor Green
    Write-Host ''

    # Export CSV
    if (-not $OutputCsv) {
        $safeTenant = ($tenantName -replace '[^\w]', '')
        $OutputCsv = Join-Path (Get-Location) ("license-scan_{0}_{1}.csv" -f $safeTenant, (Get-Date -Format 'yyyyMMdd'))
    }
    if ($dormant.Count -gt 0) {
        $dormant | Sort-Object AnnualCost -Descending |
            Export-Csv -Path $OutputCsv -NoTypeInformation -Encoding UTF8
        Write-Host 'Full per-user list saved to:' -ForegroundColor Cyan
        Write-Host "  $OutputCsv" -ForegroundColor White
        Write-Host ''
    }

    Write-Host 'Prices are list-price estimates - edit the price table for exact figures.' -ForegroundColor DarkGray
    Write-Host 'Want the PDF report, downgrade recommendations and scheduled re-audits?' -ForegroundColor DarkGray
    Write-Host 'That is the paid ServerBridge License Auditor:' -ForegroundColor DarkGray
    Write-Host '  https://server-bridge.com/license-auditor.html' -ForegroundColor Cyan
    Write-Host ''

    Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null

    if ($PassThru) { $dormant }
}

# Run unless dot-sourced (e.g. by Pester tests, where InvocationName is '.').
if ($MyInvocation.InvocationName -ne '.') {
    Invoke-LicenseScanMain -InactiveDays $InactiveDays -OutputCsv $OutputCsv `
        -IncludeGuests:$IncludeGuests -PassThru:$PassThru
}
