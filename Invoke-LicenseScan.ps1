<#
.SYNOPSIS
    Free, read-only Microsoft 365 unused-license scan.
    Cross-checks every assigned license against real activity and reports the
    seats you're paying for but nobody is using.

.DESCRIPTION
    Community edition of the ServerBridge License Auditor. Connects to Microsoft
    Graph with delegated, READ-ONLY scopes via device-code sign-in (nothing to
    register, no app, no secrets). It never writes, removes, or changes anything
    in your tenant, and it stores nothing.

    Activity signal (chosen automatically):
      * If the tenant has Microsoft Entra ID P1/P2, it uses directory
        sign-in activity (signInActivity) - the cleanest signal.
      * Otherwise it falls back to the Microsoft 365 usage reports
        (getOffice365ActiveUserDetail), which need no premium license.
      * Disabled accounts that still hold paid licenses are always flagged -
        that works on every tenant regardless of the above.

    Outputs:
      * A console summary of wasted spend by SKU
      * A CSV of every dormant licensed user (for your own follow-up)

    What it deliberately does NOT do (that's the paid ServerBridge License Auditor):
      * A formatted PDF report, costed recommended actions, scheduled re-audits
        with drift tracking, multi-tenant roll-up, and support.
    See https://server-bridge.com/license-auditor.html

.PARAMETER InactiveDays
    A licensed user with no activity in this many days is counted as dormant.
    Default 90. Range 1-3650. (The usage-report fallback resolves to the nearest
    supported window: 30, 90 or 180 days.)

.PARAMETER OutputCsv
    Path for the CSV export. Default: .\license-scan_<tenant>_<date>.csv

.PARAMETER IncludeGuests
    Include guest (external) users. Off by default.

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
        User.Read.All, Organization.Read.All, AuditLog.Read.All, Reports.Read.All
    You must be able to consent to these (Global Reader is sufficient).
    Prices are public list-price ESTIMATES (USD/user/month) - adjust the price
    table below to match your actual contract for exact figures.

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

$script:RequiredScopes = @('User.Read.All', 'Organization.Read.All', 'AuditLog.Read.All', 'Reports.Read.All')

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
    <# $true when a user has no activity since $Cutoff (never-active counts as dormant). #>
    [CmdletBinding()]
    param(
        [Parameter()][Nullable[datetime]]$LastActivity,
        [Parameter(Mandatory)][datetime]$Cutoff
    )
    if ($null -eq $LastActivity) { return $true }
    return ($LastActivity -lt $Cutoff)
}

function Get-DormantLicenseRow {
    <#
    Pure projection: given normalized user objects (DisplayName, UserPrincipalName,
    UserType, AccountEnabled, LastActivity, AssignedLicenses[].SkuId), a
    SkuId->PartNumber map and a cutoff, emit one row per dormant user per priced
    license. No Graph, no I/O - unit-testable.

    A user is dormant when disabled, OR (when an activity signal is available) when
    last activity is older than the cutoff or unknown. With no activity signal only
    disabled accounts are flagged.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowNull()][AllowEmptyCollection()][object[]]$Users,
        [Parameter(Mandatory)][hashtable]$SkuMap,
        [Parameter(Mandatory)][datetime]$Cutoff,
        [bool]$ActivitySignalAvailable = $true,
        [switch]$IncludeGuests
    )

    foreach ($u in @($Users | Where-Object { $null -ne $_ })) {
        if (-not $IncludeGuests -and $u.UserType -eq 'Guest') { continue }

        $dormant = $false
        $reason = $null
        if (-not $u.AccountEnabled) {
            $dormant = $true; $reason = 'disabled'
        } elseif ($ActivitySignalAvailable -and (Test-UserDormant -LastActivity $u.LastActivity -Cutoff $Cutoff)) {
            $dormant = $true; $reason = 'inactive'
        }
        if (-not $dormant) { continue }

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
                Reason            = $reason
                Sku               = $part
                LastActivity      = if ($u.LastActivity) { ([datetime]$u.LastActivity).ToString('yyyy-MM-dd') } else { 'never/unknown' }
                MonthlyCost       = $price
                AnnualCost        = [math]::Round($price * 12, 2)
            }
        }
    }
}

function Get-NewestSignIn {
    <#
    The most recent of a user's sign-in timestamps, or $null when none are set.

    Microsoft splits sign-in activity across three properties and reading only the first one
    (lastSignInDateTime) makes people who live in Outlook or Teams on a phone look dormant, because
    those clients sign in non-interactively. Reported by robofski on r/PowerShell, 2026-09-17.

      * lastSuccessfulSignInDateTime - "the account was truly accessed", interactive OR
        non-interactive. Best signal, but Microsoft only started populating it in Dec 2023 and did
        not backfill, so older tenants can have it empty.
      * lastSignInDateTime - INTERACTIVE attempts only, successful or not.
      * lastNonInteractiveSignInDateTime - client sign-ins on the user's behalf (mobile mail,
        Teams). Microsoft's own inactive-user guidance says to use it alongside the interactive one.

    Taking the newest of the three deliberately errs toward "active": under-flagging costs a missed
    saving, over-flagging tells someone to remove a license from a person who is still working.
    #>
    [CmdletBinding()]
    param(
        [Parameter()][AllowNull()][object]$Interactive,
        [Parameter()][AllowNull()][object]$NonInteractive,
        [Parameter()][AllowNull()][object]$Successful
    )

    $dates = @($Successful, $Interactive, $NonInteractive) |
        ForEach-Object { if ($_) { $_ -as [datetime] } } |
        Where-Object { $_ }
    if (-not $dates) { return $null }
    return (@($dates) | Sort-Object -Descending)[0]
}

# ---------------------------------------------------------------------------
# Graph I/O (kept in functions so tests can dot-source without a tenant)
# ---------------------------------------------------------------------------

function Get-SignInActivityMap {
    <#
    Returns @{ ok=$bool; map=@{ upn(lower) -> [datetime] } }. ok=$false when the
    tenant lacks Entra ID P1 (signInActivity is premium-only) so the caller can
    fall back. Other errors are rethrown.
    #>
    [CmdletBinding()] param()
    $map = @{}
    try {
        $users = Get-MgUser -All -Property 'userPrincipalName,signInActivity' `
            -Filter 'assignedLicenses/$count ne 0' -ConsistencyLevel eventual `
            -CountVariable siaCount -ErrorAction Stop
        foreach ($u in $users) {
            if ($u.UserPrincipalName) {
                # All three timestamps, not just the interactive one - see Get-NewestSignIn.
                $map[$u.UserPrincipalName.ToLower()] = Get-NewestSignIn `
                    -Interactive $u.SignInActivity.LastSignInDateTime `
                    -NonInteractive $u.SignInActivity.LastNonInteractiveSignInDateTime `
                    -Successful $u.SignInActivity.LastSuccessfulSignInDateTime
            }
        }
        return @{ ok = $true; map = $map }
    } catch {
        $msg = "$($_.Exception.Message)"
        if ($msg -match 'NonPremium' -or $msg -match 'premium') { return @{ ok = $false; map = $map } }
        throw
    }
}

function Get-UsageReportActivityMap {
    <#
    Fallback that needs no Entra premium: pulls the Microsoft 365 active-user
    detail report and returns @{ ok=$bool; map=@{ upn(lower) -> [datetime] } }.
    ok=$false when the tenant de-identifies report data (UPNs masked) so activity
    can't be matched to users.
    #>
    [CmdletBinding()] param([int]$InactiveDays = 90)

    # NB: the Graph reports API keeps the legacy "Office365" name for this function.
    $period = if ($InactiveDays -le 30) { 'D30' } elseif ($InactiveDays -le 90) { 'D90' } else { 'D180' }
    $uri = "https://graph.microsoft.com/v1.0/reports/getOffice365ActiveUserDetail(period='$period')"
    $resp = Invoke-MgGraphRequest -Method GET -Uri $uri -OutputType HttpResponseMessage -ErrorAction Stop
    $csv = $resp.Content.ReadAsStringAsync().Result
    $rows = @($csv | ConvertFrom-Csv)

    $map = @{}
    $sawUpn = $false
    foreach ($r in $rows) {
        $upn = $r.'User Principal Name'
        if (-not $upn) { continue }
        if ($upn -like '*@*') { $sawUpn = $true }
        # Take the most recent activity across every per-service "* Last Activity Date" column.
        $maxDate = $null
        foreach ($p in $r.PSObject.Properties) {
            if ($p.Name -like '*Last Activity Date' -and $p.Value) {
                $d = $p.Value -as [datetime]
                if ($d -and ($null -eq $maxDate -or $d -gt $maxDate)) { $maxDate = $d }
            }
        }
        $map[$upn.ToLower()] = $maxDate
    }
    if (-not $sawUpn -and $rows.Count -gt 0) { return @{ ok = $false; map = @{} } }
    return @{ ok = $true; map = $map }
}

function Test-SignInTimedOut {
    <#
    $true when Connect-MgGraph gave up because the device code wasn't used in time. Microsoft's
    Graph PowerShell module allows 2 minutes and the limit can't be changed, so the scan offers a
    new code instead of making the admin start over.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Message)
    return ($Message -match 'timed out after \d+ seconds')
}

function ConvertTo-SafeCsvValue {
    <#
    Spreadsheet apps run a cell as a formula when it starts with = + - @ (or tab/CR).
    Directory text such as a guest's display name is attacker-controllable, so prefix a
    single quote to keep it as plain text when the CSV is opened in Excel.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowNull()][AllowEmptyString()][object]$Value)
    if ($Value -is [string] -and $Value -match '^[=+\-@\t\r]') { return "'" + $Value }
    return $Value
}

function Get-ConcealedNamesHelpText {
    <# The one-minute fix for de-identified usage reports, as lines of text (testable). #>
    [CmdletBinding()] param()
    @(
        'Microsoft is hiding user names in your usage reports, so this scan cannot tell who is inactive.'
        'Fix it in about a minute (needs a Global Administrator):'
        '  1. Open https://admin.microsoft.com'
        '  2. Go to Settings > Org settings > Services > Reports'
        '  3. Untick "Conceal user, group, and site names in all reports", then click Save'
        'This only changes what admins see in Microsoft''s own reports. You can turn it back on after the audit.'
    )
}

function Test-GraphSdkPresent {
    <#
    $true when the Microsoft Graph PowerShell SDK is installed; otherwise prints the install hint
    and returns $false. Shared so every command in this module gives the same first-run message.
    #>
    [CmdletBinding()] param()
    if (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication) { return $true }
    Write-Host 'Microsoft Graph PowerShell SDK not found.' -ForegroundColor Yellow
    Write-Host 'Install it with:  Install-Module Microsoft.Graph -Scope CurrentUser' -ForegroundColor Yellow
    return $false
}

function Connect-ScanGraph {
    <#
    Device-code sign-in with the read-only scopes, offering a fresh code when Microsoft's
    2-minute limit expires. Returns $true once connected, $false if the user quit or it failed.

    Shared by every command in this module: this retry behaviour was a real bug fix (1.1.1) and
    must not be reimplemented per command.
    #>
    [CmdletBinding()] param()
    $signedIn = $false
    while (-not $signedIn) {
        try {
            Write-Host 'Signing you in. A device code will appear below - enter it within 2 minutes.' -ForegroundColor Cyan
            Connect-MgGraph -Scopes $script:RequiredScopes -UseDeviceCode -NoWelcome -ContextScope Process -ErrorAction Stop
            $signedIn = $true
        } catch {
            $message = "$($_.Exception.Message)"
            if ((Test-SignInTimedOut -Message $message) -and -not [Console]::IsInputRedirected) {
                Write-Host 'The sign-in code expired (Microsoft allows 2 minutes).' -ForegroundColor Yellow
                $answer = Read-Host 'Press Enter for a new code, or type Q to quit'
                if ($answer -match '^\s*[qQ]') { return $false }
                continue
            }
            Write-Host "Sign-in failed: $message" -ForegroundColor Red
            return $false
        }
    }
    if (-not (Get-MgContext)) { Write-Host 'Sign-in cancelled.' -ForegroundColor Red; return $false }
    return $true
}

function Resolve-ActivityMap {
    <#
    Picks the best available activity signal and returns
    @{ available=$bool; map=@{ upn(lower) -> [datetime] }; signalName=[string] }.

    Prefers directory sign-in activity (needs Entra ID P1), else the Microsoft 365 usage reports.
    When the tenant conceals user names in those reports it shows the one-minute fix and re-checks
    on Enter without a new sign-in. available=$false means the admin skipped, so only disabled
    accounts can be judged.

    Shared by every command in this module.
    #>
    [CmdletBinding()] param([int]$InactiveDays = 90)

    $sia = Get-SignInActivityMap
    if ($sia.ok) {
        return @{ available = $true; map = $sia.map; signalName = 'directory sign-in activity' }
    }

    Write-Host 'Sign-in activity needs Entra ID P1; falling back to Microsoft 365 usage reports...' -ForegroundColor Yellow
    $rep = $null
    $attempt = 0
    while ($true) {
        try {
            $rep = Get-UsageReportActivityMap -InactiveDays $InactiveDays
        } catch {
            $rep = $null
            Write-Host "Usage reports unavailable: $($_.Exception.Message)" -ForegroundColor Yellow
            break
        }
        if ($rep.ok) { break }

        $attempt++
        Write-Host ''
        if ($attempt -gt 1) {
            Write-Host 'Names are still hidden. Microsoft can take a few minutes to apply the change.' -ForegroundColor Yellow
        } else {
            Get-ConcealedNamesHelpText | ForEach-Object { Write-Host $_ -ForegroundColor Yellow }
        }
        if ([Console]::IsInputRedirected) { break }
        $answer = Read-Host 'Press Enter when done to check again (no new sign-in), or type S to skip'
        if ($answer -match '^\s*[sS]') { break }
    }

    if ($rep -and $rep.ok) {
        return @{ available = $true; map = $rep.map; signalName = 'Microsoft 365 usage reports' }
    }
    return @{ available = $false; map = @{}; signalName = $null }
}

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

    if (-not (Test-GraphSdkPresent)) { return }
    if (-not (Connect-ScanGraph)) { return }

    try {
        $org = Get-MgOrganization -ErrorAction Stop
        $tenantName = ($org.DisplayName | Select-Object -First 1)
        Write-Host "Connected to: $tenantName (signed in as $((Get-MgContext).Account))" -ForegroundColor Green

        $skuMap = @{}
        foreach ($s in (Get-MgSubscribedSku -All -ErrorAction Stop)) { $skuMap[$s.SkuId] = $s.SkuPartNumber }

        $select = 'id,displayName,userPrincipalName,userType,accountEnabled,assignedLicenses'
        $rawUsers = Get-MgUser -All -Property $select -Filter 'assignedLicenses/$count ne 0' `
            -ConsistencyLevel eventual -CountVariable userCount -ErrorAction Stop
    } catch {
        Write-Host "Graph read failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host 'Confirm you consented to User.Read.All, Organization.Read.All, AuditLog.Read.All and Reports.Read.All.' -ForegroundColor Yellow
        Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
        return
    }

    # Resolve an activity signal: prefer sign-in activity (premium), fall back to usage reports.
    $signal = Resolve-ActivityMap -InactiveDays $InactiveDays
    $activity = $signal.map
    $signalAvailable = $signal.available
    $signalName = $signal.signalName
    if (-not $signalAvailable) {
        Write-Host ''
        Write-Host 'PARTIAL AUDIT: only disabled accounts that still hold licenses can be checked.' -ForegroundColor Yellow
    }

    if ($signalAvailable) {
        Write-Host "Flagging licensed users dormant $InactiveDays+ days (via $signalName)..." -ForegroundColor Cyan
    }

    $normalized = foreach ($u in $rawUsers) {
        [pscustomobject]@{
            DisplayName       = $u.DisplayName
            UserPrincipalName = $u.UserPrincipalName
            UserType          = $u.UserType
            AccountEnabled    = $u.AccountEnabled
            AssignedLicenses  = $u.AssignedLicenses
            LastActivity      = if ($u.UserPrincipalName) { $activity[$u.UserPrincipalName.ToLower()] } else { $null }
        }
    }

    if ($signalAvailable) {
        $resolved = @($normalized | Where-Object { $_.LastActivity }).Count
        Write-Host ("  activity resolved for {0} of {1} licensed users" -f $resolved, @($normalized).Count) -ForegroundColor DarkGray
    }

    $cutoff = (Get-Date).AddDays(-1 * $InactiveDays)
    $dormant = @(Get-DormantLicenseRow -Users $normalized -SkuMap $skuMap -Cutoff $cutoff `
            -ActivitySignalAvailable $signalAvailable -IncludeGuests:$IncludeGuests)

    Write-Host ''
    Write-Host 'Wasted spend by license' -ForegroundColor Green
    Write-Host '-----------------------' -ForegroundColor DarkGray
    if ($dormant.Count -eq 0) {
        Write-Host '  Nothing obvious to reclaim.' -ForegroundColor Green
    } else {
        $dormant | Group-Object Sku | ForEach-Object {
            [pscustomobject]@{
                License      = $_.Name
                DormantSeats = $_.Count
                'Annual $'   = [int][math]::Round((($_.Group | Measure-Object AnnualCost -Sum).Sum), 0)
            }
        } | Sort-Object 'Annual $' -Descending | Format-Table -AutoSize
    }

    $totalAnnual = [math]::Round((($dormant | Measure-Object AnnualCost -Sum).Sum), 0)
    Write-Host ("  Reclaimable seats : {0:N0}" -f $dormant.Count) -ForegroundColor White
    Write-Host ("  Wasted spend      : `${0:N0} / year" -f $totalAnnual) -ForegroundColor Green
    Write-Host ''

    if (-not $OutputCsv) {
        $safeTenant = ($tenantName -replace '[^\w]', '')
        $OutputCsv = Join-Path (Get-Location) ("license-scan_{0}_{1}.csv" -f $safeTenant, (Get-Date -Format 'yyyyMMdd'))
    }
    if ($dormant.Count -gt 0) {
        $dormant | Sort-Object AnnualCost -Descending | ForEach-Object {
            $row = $_.PSObject.Copy()
            foreach ($name in 'DisplayName', 'UserPrincipalName', 'UserType', 'Sku') {
                $row.$name = ConvertTo-SafeCsvValue -Value $row.$name
            }
            $row
        } | Export-Csv -Path $OutputCsv -NoTypeInformation -Encoding UTF8
        Write-Host "Full per-user list saved to:" -ForegroundColor Cyan
        Write-Host "  $OutputCsv" -ForegroundColor White
        Write-Host ''
    }

    Write-Host 'Prices are list-price estimates - edit the price table for exact figures.' -ForegroundColor DarkGray
    Write-Host 'Got a number that looks wrong, or something confusing? Tell me:' -ForegroundColor DarkGray
    Write-Host '  https://github.com/lbcrowe-del/ServerBridge-LicenseScan/issues' -ForegroundColor Cyan
    Write-Host 'Want the PDF report, costed recommended actions and scheduled re-audits?' -ForegroundColor DarkGray
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
