<#
.SYNOPSIS
    Free, read-only Microsoft 365 offboarding check.
    Finds accounts that look like leavers and shows what they still hold.

.DESCRIPTION
    When someone leaves, the license is usually the only thing anyone remembers to remove. The
    account often keeps its group memberships and a user mailbox that was never converted to
    shared, and nobody notices until an audit.

    This connects to Microsoft Graph with delegated, READ-ONLY scopes via device-code sign-in
    (nothing to register, no app, no secrets). It never writes, removes, or changes anything in
    your tenant, and it stores nothing. You act on the list yourself.

    For each account that looks like a leaver (disabled, or no activity for -InactiveDays) it
    reports:
      * whether it still holds a paid license, and which
      * how many groups it is still a member of
      * whether its mailbox is still a user mailbox rather than converted to shared

    Activity signal is chosen automatically, exactly as the license scan does it: directory
    sign-in activity when the tenant has Entra ID P1/P2, otherwise the Microsoft 365 usage
    reports. Disabled accounts are flagged on any tenant.

    What it deliberately does NOT do (that's the paid ServerBridge License Auditor):
      * mailbox size and archive detail, app role assignments, a formatted PDF, scheduled
        re-runs with drift tracking, and multi-tenant roll-up.
    See https://server-bridge.com/license-auditor.html

.PARAMETER InactiveDays
    An account with no activity in this many days is treated as a possible leaver.
    Default 90. Range 1-3650. (The usage-report fallback resolves to the nearest supported
    window: 30, 90 or 180 days.)

.PARAMETER OutputCsv
    Path for the CSV export. Default: .\offboarding-check_<tenant>_<date>.csv

.PARAMETER IncludeGuests
    Include guest (external) users. Off by default.

.PARAMETER UseExchangeOnline
    EXPERIMENTAL. Read mailbox types from Exchange Online instead of Microsoft's usage report.

    Worth it when you want mailboxes nobody has used. The usage report only lists mailboxes that
    have had activity, so a shared mailbox sitting untouched is missing from it entirely - which is
    the mailbox most likely to be wasting a license.

    Costs a SECOND sign-in (Exchange Online is a separate connection from Graph) and needs
    ExchangeOnlineManagement installed. Read-only, and if it fails the check carries on with the
    usage report.

.PARAMETER PassThru
    Emit the finding objects to the pipeline in addition to the CSV.

.EXAMPLE
    Invoke-OffboardingCheck

.EXAMPLE
    Invoke-OffboardingCheck -InactiveDays 30 -OutputCsv C:\reports\leavers.csv

.NOTES
    Requires the Microsoft Graph PowerShell SDK:
        Install-Module Microsoft.Graph -Scope CurrentUser
    Delegated scopes requested (all read-only), the same set the license scan uses:
        User.Read.All, Organization.Read.All, AuditLog.Read.All, Reports.Read.All

    The mailbox type comes from Microsoft's mailbox usage report, which is unavailable when your
    tenant conceals user names in reports, and which only covers mailboxes that have had
    ACTIVITY - a mailbox nobody has touched is missing from it entirely, so its type reads
    "unknown". Use -UseExchangeOnline to read types from Exchange instead (second sign-in).
    Either way an unreadable type is reported as unknown rather than guessed.

    Project: https://github.com/lbcrowe-del/ServerBridge-LicenseScan
    License: MIT
#>

[CmdletBinding()]
param(
    [ValidateRange(1, 3650)]
    [int]$InactiveDays = 90,

    [string]$OutputCsv,

    [switch]$IncludeGuests,

    [switch]$UseExchangeOnline,

    [switch]$PassThru
)

# Snapshot what the caller actually passed, BEFORE the dot-source below.
#
# Invoke-LicenseScan.ps1 has its own param() block with InactiveDays, OutputCsv, IncludeGuests and
# PassThru. Dot-sourcing runs it in THIS scope, so those four variables are re-declared at their
# defaults and whatever the caller passed here is wiped. The symptom was silent: -OutputCsv wrote to
# the default path instead, and -IncludeGuests did nothing at all while reporting success.
# Found 2026-09-22 when a run ignored the -OutputCsv it was given.
$callerArgs = @{
    InactiveDays      = $InactiveDays
    OutputCsv         = $OutputCsv
    IncludeGuests     = [bool]$IncludeGuests
    UseExchangeOnline = [bool]$UseExchangeOnline
    PassThru          = [bool]$PassThru
}

# Shared helpers (sign-in, activity signal, CSV escaping) live in Invoke-LicenseScan.ps1 so there
# is exactly one copy. Dot-sourcing it defines the functions without running a scan: that script
# only runs its entry point when it is not dot-sourced.
if (-not (Get-Command -Name Connect-ScanGraph -ErrorAction SilentlyContinue)) {
    $sharedPath = Join-Path $PSScriptRoot 'Invoke-LicenseScan.ps1'
    if (-not (Test-Path -LiteralPath $sharedPath)) {
        throw "Invoke-LicenseScan.ps1 must sit next to this script (it holds the shared sign-in and activity helpers)."
    }
    . $sharedPath
}

# ---------------------------------------------------------------------------
# Pure, testable helpers (no Graph calls - safe to dot-source)
# ---------------------------------------------------------------------------

function Get-MailboxTypeLabel {
    <#
    Plain-English label for a mailbox recipient type from Microsoft's usage report.
    $null/empty means the report didn't cover this account (it lags a day or two).
    #>
    [CmdletBinding()]
    param([Parameter()][AllowNull()][AllowEmptyString()][string]$RecipientType)

    if ([string]::IsNullOrWhiteSpace($RecipientType)) { return 'unknown' }
    switch ($RecipientType.Trim().ToLower()) {
        'usermailbox'      { return 'user' }
        'user'             { return 'user' }
        'sharedmailbox'    { return 'shared' }
        'shared'           { return 'shared' }
        'roommailbox'      { return 'room' }
        'room'             { return 'room' }
        'equipmentmailbox' { return 'equipment' }
        'equipment'        { return 'equipment' }
        default            { return $RecipientType.Trim().ToLower() }
    }
}

function Get-OffboardingRow {
    <#
    Pure projection: given normalized user objects (DisplayName, UserPrincipalName, UserType,
    AccountEnabled, LastActivity, AssignedLicenses[].SkuId, GroupCount, MailboxType), a
    SkuId->PartNumber map and a cutoff, emit one row per leaver-looking account. No Graph, no
    I/O - unit-testable.

    An account is a possible leaver when disabled, OR (when an activity signal is available)
    when last activity is older than the cutoff or unknown. With no activity signal only
    disabled accounts are flagged, because everything else would be a guess.

    Unlike the license scan this emits ONE row per account, not one per license, because the
    unit of work when offboarding is the person.
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

        $reason = $null
        if (-not $u.AccountEnabled) {
            $reason = 'disabled'
        } elseif ($ActivitySignalAvailable -and (Test-UserDormant -LastActivity $u.LastActivity -Cutoff $Cutoff)) {
            $reason = 'inactive'
        }
        if (-not $reason) { continue }

        $licenses = @()
        foreach ($lic in $u.AssignedLicenses) {
            $part = $SkuMap[$lic.SkuId]
            if (-not $part) { continue }
            if ((Get-SkuMonthlyPrice -PartNumber $part) -le 0) { continue }  # free SKUs aren't worth reclaiming
            $licenses += $part
        }

        $mailboxType = if ($u.MailboxType) { $u.MailboxType } else { 'unknown' }
        $groupCount = if ($null -ne $u.GroupCount) { [int]$u.GroupCount } else { $null }

        $findings = @()
        if ($licenses.Count -gt 0) { $findings += 'still licensed' }
        if ($groupCount -gt 0) { $findings += 'still in groups' }
        if ($mailboxType -eq 'user') { $findings += 'mailbox not shared' }

        [pscustomobject]@{
            DisplayName       = $u.DisplayName
            UserPrincipalName = $u.UserPrincipalName
            UserType          = $u.UserType
            AccountEnabled    = $u.AccountEnabled
            Reason            = $reason
            LastActivity      = if ($u.LastActivity) { ([datetime]$u.LastActivity).ToString('yyyy-MM-dd') } else { 'never/unknown' }
            Licenses          = ($licenses -join '; ')
            LicenseCount      = $licenses.Count
            GroupCount        = $groupCount
            MailboxType       = $mailboxType
            Findings          = ($findings -join '; ')
        }
    }
}

# ---------------------------------------------------------------------------
# Graph I/O (kept in functions so tests can dot-source without a tenant)
# ---------------------------------------------------------------------------

function Merge-MailboxTypeMap {
    <#
    Pure merge of two mailbox-type maps. Exchange wins wherever it has an answer, because it reads
    Exchange's own directory; the usage report only fills gaps.

    This exists because of a limit found on a live tenant 2026-09-22: getMailboxUsageDetail only
    lists mailboxes that have HAD ACTIVITY. A shared mailbox nobody has touched is absent from the
    report entirely - not blank, absent - at D7 and at D180 alike. That is exactly the mailbox worth
    finding, since an unused licensed shared mailbox is the clearest wasted license there is.
    #>
    [CmdletBinding()]
    param(
        [Parameter()][AllowNull()][hashtable]$ReportMap,
        [Parameter()][AllowNull()][hashtable]$ExchangeMap
    )

    $merged = @{}
    foreach ($k in @($ReportMap.Keys)) { $merged[$k] = $ReportMap[$k] }
    foreach ($k in @($ExchangeMap.Keys)) { $merged[$k] = $ExchangeMap[$k] }
    return $merged
}

function Test-ExchangeOnlineModulePresent {
    <# Separate from the call so tests can mock it without Exchange installed. #>
    [CmdletBinding()] param()
    return [bool](Get-Module -ListAvailable -Name ExchangeOnlineManagement)
}

function Get-MailboxTypeMapFromExchange {
    <#
    PROTOTYPE (opt-in via -UseExchangeOnline).

    Returns @{ ok=$bool; map=@{ upn(lower) -> label }; note=$string }.

    Get-EXOMailbox reads Exchange's own directory, so it sees every mailbox whether or not anyone
    has used it - the case the usage report misses. The cost is a SECOND sign-in: Exchange Online is
    a different token audience from Graph, so this cannot ride on the Graph connection.

    That cost is why this is opt-in rather than the default. Everything here is read-only
    (Get-EXOMailbox), and a failure degrades to the usage report instead of failing the check.
    #>
    [CmdletBinding()] param()

    if (-not (Test-ExchangeOnlineModulePresent)) {
        return @{ ok = $false; map = @{}; note = 'ExchangeOnlineManagement is not installed (Install-Module ExchangeOnlineManagement -Scope CurrentUser).' }
    }

    try {
        Import-Module ExchangeOnlineManagement -ErrorAction Stop
        Write-Host '  a second sign-in is needed for Exchange Online (read-only)...' -ForegroundColor DarkGray
        Connect-ExchangeOnline -ShowBanner:$false -ErrorAction Stop | Out-Null
    } catch {
        return @{ ok = $false; map = @{}; note = "Exchange Online sign-in failed: $($_.Exception.Message)" }
    }

    try {
        $map = @{}
        foreach ($mb in @(Get-EXOMailbox -ResultSize Unlimited -Properties RecipientTypeDetails -ErrorAction Stop)) {
            $upn = $mb.UserPrincipalName
            if (-not $upn) { continue }
            $map[$upn.ToLower()] = Get-MailboxTypeLabel -RecipientType $mb.RecipientTypeDetails
        }
        return @{ ok = $true; map = $map; note = $null }
    } catch {
        return @{ ok = $false; map = @{}; note = "Reading mailboxes failed: $($_.Exception.Message)" }
    } finally {
        Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
    }
}

function Get-MailboxTypeMap {
    <#
    Returns @{ ok=$bool; map=@{ upn(lower) -> recipient type label } }.

    Uses Microsoft's mailbox usage report, which is the only way to tell a user mailbox from a
    shared one without Exchange Online PowerShell. The v1.0 report has no Recipient Type column,
    so this uses the beta report - still under Reports.Read.All, no extra permission.

    ok=$false when the tenant conceals user names in reports (rows can't be matched to people)
    or the column is missing. The caller reports that rather than guessing.
    #>
    [CmdletBinding()] param()

    $uri = "https://graph.microsoft.com/beta/reports/getMailboxUsageDetail(period='D7')"
    $resp = Invoke-MgGraphRequest -Method GET -Uri $uri -OutputType HttpResponseMessage -ErrorAction Stop
    $csv = $resp.Content.ReadAsStringAsync().Result
    $rows = @($csv | ConvertFrom-Csv)

    if ($rows.Count -eq 0) { return @{ ok = $true; map = @{} } }
    if (-not ($rows[0].PSObject.Properties.Name -contains 'Recipient Type')) {
        return @{ ok = $false; map = @{} }
    }

    $map = @{}
    $sawUpn = $false
    foreach ($r in $rows) {
        $upn = $r.'User Principal Name'
        if (-not $upn) { continue }
        if ($upn -like '*@*') { $sawUpn = $true }
        $map[$upn.ToLower()] = Get-MailboxTypeLabel -RecipientType $r.'Recipient Type'
    }
    if (-not $sawUpn) { return @{ ok = $false; map = @{} } }
    return @{ ok = $true; map = $map }
}

function Get-GroupMembershipCount {
    <#
    Direct group/role memberships for one account, via /users/{id}/memberOf/$count.
    Needs only User.Read.All, which this module already requests.
    Returns $null when the count can't be read, so the caller can say "unknown" honestly
    instead of printing 0 and implying the account is clean.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$UserId)

    try {
        $uri = "https://graph.microsoft.com/v1.0/users/$UserId/memberOf/`$count"
        $resp = Invoke-MgGraphRequest -Method GET -Uri $uri -Headers @{ ConsistencyLevel = 'eventual' } `
            -OutputType HttpResponseMessage -ErrorAction Stop
        $text = $resp.Content.ReadAsStringAsync().Result
        $value = 0
        if ([int]::TryParse(("$text").Trim(), [ref]$value)) { return $value }
        return $null
    } catch {
        Write-Verbose "memberOf count failed for $UserId : $($_.Exception.Message)"
        return $null
    }
}

function Invoke-OffboardingCheckMain {
    [CmdletBinding()]
    param(
        [int]$InactiveDays,
        [string]$OutputCsv,
        [switch]$IncludeGuests,
        [switch]$UseExchangeOnline,
        [switch]$PassThru
    )

    Write-Host ''
    Write-Host 'ServerBridge - Free M365 Offboarding Check (read-only)' -ForegroundColor Green
    Write-Host '-----------------------------------------------------' -ForegroundColor DarkGray

    if (-not (Test-GraphSdkPresent)) { return }
    if (-not (Connect-ScanGraph)) { return }

    try {
        $org = Get-MgOrganization -ErrorAction Stop
        $tenantName = ($org.DisplayName | Select-Object -First 1)
        Write-Host "Connected to: $tenantName (signed in as $((Get-MgContext).Account))" -ForegroundColor Green

        $skuMap = @{}
        foreach ($s in (Get-MgSubscribedSku -All -ErrorAction Stop)) { $skuMap[$s.SkuId] = $s.SkuPartNumber }

        $select = 'id,displayName,userPrincipalName,userType,accountEnabled,assignedLicenses'
        $rawUsers = Get-MgUser -All -Property $select -ErrorAction Stop
    } catch {
        Write-Host "Graph read failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host 'Confirm you consented to User.Read.All, Organization.Read.All, AuditLog.Read.All and Reports.Read.All.' -ForegroundColor Yellow
        Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
        return
    }

    $signal = Resolve-ActivityMap -InactiveDays $InactiveDays
    $activity = $signal.map
    $signalAvailable = $signal.available
    if (-not $signalAvailable) {
        Write-Host ''
        Write-Host 'PARTIAL CHECK: only disabled accounts can be judged without an activity signal.' -ForegroundColor Yellow
    } else {
        Write-Host "Looking for accounts inactive $InactiveDays+ days or disabled (via $($signal.signalName))..." -ForegroundColor Cyan
    }

    # Mailbox types: the only way to spot a mailbox nobody converted to shared.
    $mailboxMap = @{}
    try {
        $mb = Get-MailboxTypeMap
        if ($mb.ok) {
            $mailboxMap = $mb.map
        } else {
            Write-Host 'Mailbox types unavailable (user names are concealed in reports, or the report changed).' -ForegroundColor Yellow
            Write-Host 'Mailbox column will read "unknown".' -ForegroundColor DarkGray
        }
    } catch {
        Write-Host "Mailbox report unavailable: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    # Opt-in: ask Exchange directly, which also sees mailboxes that have never been used.
    if ($UseExchangeOnline) {
        $exo = Get-MailboxTypeMapFromExchange
        if ($exo.ok) {
            $mailboxMap = Merge-MailboxTypeMap -ReportMap $mailboxMap -ExchangeMap $exo.map
            Write-Host ("  mailbox types read from Exchange Online ({0} mailbox(es))" -f $exo.map.Count) -ForegroundColor DarkGray
        } else {
            Write-Host "Exchange Online check skipped: $($exo.note)" -ForegroundColor Yellow
            Write-Host 'Falling back to the usage report, which cannot see mailboxes with no activity.' -ForegroundColor DarkGray
        }
    }

    # Narrow to leaver-looking accounts BEFORE the per-user group lookup: one Graph call each.
    $cutoff = (Get-Date).AddDays(-1 * $InactiveDays)
    $candidates = foreach ($u in $rawUsers) {
        $upnKey = if ($u.UserPrincipalName) { $u.UserPrincipalName.ToLower() } else { $null }
        $last = if ($upnKey) { $activity[$upnKey] } else { $null }
        $isCandidate = (-not $u.AccountEnabled) -or
                       ($signalAvailable -and (Test-UserDormant -LastActivity $last -Cutoff $cutoff))
        if (-not $isCandidate) { continue }
        if (-not $IncludeGuests -and $u.UserType -eq 'Guest') { continue }

        [pscustomobject]@{
            Id                = $u.Id
            DisplayName       = $u.DisplayName
            UserPrincipalName = $u.UserPrincipalName
            UserType          = $u.UserType
            AccountEnabled    = $u.AccountEnabled
            AssignedLicenses  = $u.AssignedLicenses
            LastActivity      = $last
            MailboxType       = if ($upnKey -and $mailboxMap.ContainsKey($upnKey)) { $mailboxMap[$upnKey] } else { 'unknown' }
            GroupCount        = $null
        }
    }
    $candidates = @($candidates)

    if ($candidates.Count -gt 0) {
        Write-Host ("  checking group membership for {0} account(s)..." -f $candidates.Count) -ForegroundColor DarkGray
        foreach ($c in $candidates) { $c.GroupCount = Get-GroupMembershipCount -UserId $c.Id }
    }

    $rows = @(Get-OffboardingRow -Users $candidates -SkuMap $skuMap -Cutoff $cutoff `
            -ActivitySignalAvailable $signalAvailable -IncludeGuests:$IncludeGuests)

    Write-Host ''
    Write-Host 'Accounts to review' -ForegroundColor Green
    Write-Host '------------------' -ForegroundColor DarkGray
    if ($rows.Count -eq 0) {
        Write-Host '  Nothing to review - no leaver-looking accounts found.' -ForegroundColor Green
    } else {
        $rows | Sort-Object LicenseCount -Descending |
            Format-Table UserPrincipalName, Reason, Licenses, GroupCount, MailboxType -AutoSize
    }

    $stillLicensed = @($rows | Where-Object { $_.LicenseCount -gt 0 }).Count
    $notShared = @($rows | Where-Object { $_.MailboxType -eq 'user' }).Count
    $typeUnknown = @($rows | Where-Object { $_.MailboxType -eq 'unknown' }).Count
    Write-Host ("  Accounts to review     : {0:N0}" -f $rows.Count) -ForegroundColor White
    Write-Host ("  Still holding licenses : {0:N0}" -f $stillLicensed) -ForegroundColor Yellow
    # Never print a bare 0 for a count nobody could read: "0 mailboxes not shared" reads as an
    # all-clear on work that was never checked. Same false zero fixed in the paid CLI 2026-09-22.
    if ($typeUnknown -eq $rows.Count -and $rows.Count -gt 0) {
        Write-Host '  Mailbox not shared     : unknown (no mailbox types could be read)' -ForegroundColor Yellow
    } elseif ($typeUnknown -gt 0) {
        Write-Host ("  Mailbox not shared     : {0:N0} ({1:N0} unknown)" -f $notShared, $typeUnknown) -ForegroundColor Yellow
    } else {
        Write-Host ("  Mailbox not shared     : {0:N0}" -f $notShared) -ForegroundColor Yellow
    }
    Write-Host ''

    if (-not $OutputCsv) {
        $safeTenant = ($tenantName -replace '[^\w]', '')
        $OutputCsv = Join-Path (Get-Location) ("offboarding-check_{0}_{1}.csv" -f $safeTenant, (Get-Date -Format 'yyyyMMdd'))
    }
    if ($rows.Count -gt 0) {
        $rows | Sort-Object LicenseCount -Descending | ForEach-Object {
            $row = $_.PSObject.Copy()
            foreach ($name in 'DisplayName', 'UserPrincipalName', 'UserType', 'Licenses', 'MailboxType', 'Findings') {
                $row.$name = ConvertTo-SafeCsvValue -Value $row.$name
            }
            $row
        } | Export-Csv -Path $OutputCsv -NoTypeInformation -Encoding UTF8
        Write-Host 'Full list saved to:' -ForegroundColor Cyan
        Write-Host "  $OutputCsv" -ForegroundColor White
        Write-Host ''
    }

    Write-Host 'Nothing was changed in your tenant. Review each account before acting.' -ForegroundColor DarkGray
    Write-Host 'A licensed shared mailbox under 50 GB without an archive usually needs no license.' -ForegroundColor DarkGray
    Write-Host 'Got an account it judged wrong, or something confusing? Tell me:' -ForegroundColor DarkGray
    Write-Host '  https://github.com/lbcrowe-del/ServerBridge-LicenseScan/issues' -ForegroundColor Cyan
    Write-Host ''

    Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
    if ($PassThru) { $rows }
}

# Run unless dot-sourced (e.g. by Pester tests, where InvocationName is '.').
# Splats the snapshot taken before the dot-source, NOT the live variables - see the note there.
if ($MyInvocation.InvocationName -ne '.') {
    Invoke-OffboardingCheckMain -InactiveDays $callerArgs.InactiveDays -OutputCsv $callerArgs.OutputCsv `
        -IncludeGuests:$callerArgs.IncludeGuests -UseExchangeOnline:$callerArgs.UseExchangeOnline `
        -PassThru:$callerArgs.PassThru
}
