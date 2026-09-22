#Requires -Modules Pester

BeforeAll {
    # Dot-source the script; InvocationName '.' prevents Invoke-OffboardingCheckMain from running.
    # It dot-sources Invoke-LicenseScan.ps1 itself for the shared helpers.
    . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Invoke-OffboardingCheck.ps1')
}

Describe 'Get-MailboxTypeLabel' {
    It 'maps Microsoft''s recipient types to plain words' {
        Get-MailboxTypeLabel -RecipientType 'UserMailbox' | Should -Be 'user'
        Get-MailboxTypeLabel -RecipientType 'SharedMailbox' | Should -Be 'shared'
        Get-MailboxTypeLabel -RecipientType 'RoomMailbox' | Should -Be 'room'
        Get-MailboxTypeLabel -RecipientType 'EquipmentMailbox' | Should -Be 'equipment'
    }
    It 'accepts the short forms the report sometimes uses' {
        Get-MailboxTypeLabel -RecipientType 'Shared' | Should -Be 'shared'
        Get-MailboxTypeLabel -RecipientType 'User' | Should -Be 'user'
    }
    It 'says unknown rather than guessing when the report has no value' {
        Get-MailboxTypeLabel -RecipientType $null | Should -Be 'unknown'
        Get-MailboxTypeLabel -RecipientType '' | Should -Be 'unknown'
        Get-MailboxTypeLabel -RecipientType '   ' | Should -Be 'unknown'
    }
    It 'passes an unrecognised type through instead of dropping it' {
        Get-MailboxTypeLabel -RecipientType 'SomethingNew' | Should -Be 'somethingnew'
    }
}

Describe 'Get-OffboardingRow' {
    BeforeAll {
        $skuMap = @{
            'sku-e3'   = 'ENTERPRISEPACK'
            'sku-e5'   = 'SPE_E5'
            'sku-free' = 'TEAMS_EXPLORATORY'
        }
        $cutoff = (Get-Date).AddDays(-90)

        function New-TestAccount {
            param(
                $Name,
                $Type = 'Member',
                $Enabled = $true,
                $Last = $null,
                $Skus = @('sku-e3'),
                $Groups = 0,
                $Mailbox = 'user'
            )
            [pscustomobject]@{
                DisplayName       = $Name
                UserPrincipalName = "$Name@contoso.com"
                UserType          = $Type
                AccountEnabled    = $Enabled
                LastActivity      = $Last
                AssignedLicenses  = @($Skus | ForEach-Object { [pscustomobject]@{ SkuId = $_ } })
                GroupCount        = $Groups
                MailboxType       = $Mailbox
            }
        }
    }

    It 'emits ONE row per account, not one per license' {
        $users = @(New-TestAccount -Name 'dana' -Skus @('sku-e3', 'sku-e5'))
        $rows = @(Get-OffboardingRow -Users $users -SkuMap $skuMap -Cutoff $cutoff)
        $rows.Count | Should -Be 1
        $rows[0].LicenseCount | Should -Be 2
        $rows[0].Licenses | Should -Be 'ENTERPRISEPACK; SPE_E5'
    }

    It 'flags a disabled account as disabled' {
        $rows = @(Get-OffboardingRow -Users @(New-TestAccount -Name 'gone' -Enabled $false -Last (Get-Date)) `
                -SkuMap $skuMap -Cutoff $cutoff)
        $rows.Count | Should -Be 1
        $rows[0].Reason | Should -Be 'disabled'
    }

    It 'flags an inactive account as inactive' {
        $rows = @(Get-OffboardingRow -Users @(New-TestAccount -Name 'quiet' -Last (Get-Date).AddDays(-200)) `
                -SkuMap $skuMap -Cutoff $cutoff)
        $rows[0].Reason | Should -Be 'inactive'
        $rows[0].LastActivity | Should -Not -Be 'never/unknown'
    }

    It 'skips accounts that are enabled and recently active' {
        (Get-OffboardingRow -Users @(New-TestAccount -Name 'here' -Last (Get-Date).AddDays(-2)) `
                -SkuMap $skuMap -Cutoff $cutoff) | Should -BeNullOrEmpty
    }

    It 'does not count free SKUs as licenses worth reclaiming' {
        $rows = @(Get-OffboardingRow -Users @(New-TestAccount -Name 'freeonly' -Skus @('sku-free')) `
                -SkuMap $skuMap -Cutoff $cutoff)
        $rows.Count | Should -Be 1
        $rows[0].LicenseCount | Should -Be 0
        $rows[0].Findings | Should -Not -Match 'still licensed'
    }

    It 'excludes guests by default but includes them with -IncludeGuests' {
        $guest = @(New-TestAccount -Name 'guest' -Type 'Guest')
        (Get-OffboardingRow -Users $guest -SkuMap $skuMap -Cutoff $cutoff) | Should -BeNullOrEmpty
        @(Get-OffboardingRow -Users $guest -SkuMap $skuMap -Cutoff $cutoff -IncludeGuests).Count | Should -Be 1
    }

    Context 'findings summary' {
        It 'names every problem it found' {
            $rows = @(Get-OffboardingRow -Users @(New-TestAccount -Name 'all' -Groups 4 -Mailbox 'user') `
                    -SkuMap $skuMap -Cutoff $cutoff)
            $rows[0].Findings | Should -Match 'still licensed'
            $rows[0].Findings | Should -Match 'still in groups'
            $rows[0].Findings | Should -Match 'mailbox not shared'
        }

        It 'does not complain about a mailbox already converted to shared' {
            $rows = @(Get-OffboardingRow -Users @(New-TestAccount -Name 'converted' -Mailbox 'shared') `
                    -SkuMap $skuMap -Cutoff $cutoff)
            $rows[0].Findings | Should -Not -Match 'mailbox not shared'
        }

        It 'does not claim group membership when the count is zero' {
            $rows = @(Get-OffboardingRow -Users @(New-TestAccount -Name 'nogroups' -Groups 0) `
                    -SkuMap $skuMap -Cutoff $cutoff)
            $rows[0].Findings | Should -Not -Match 'still in groups'
        }
    }

    It 'keeps an unknown group count as unknown rather than reporting 0' {
        $rows = @(Get-OffboardingRow -Users @(New-TestAccount -Name 'unknowngroups' -Groups $null) `
                -SkuMap $skuMap -Cutoff $cutoff)
        $rows[0].GroupCount | Should -BeNullOrEmpty
        $rows[0].Findings | Should -Not -Match 'still in groups'
    }

    It 'reports an unknown mailbox type rather than assuming it is a user mailbox' {
        $rows = @(Get-OffboardingRow -Users @(New-TestAccount -Name 'nomailboxdata' -Mailbox $null) `
                -SkuMap $skuMap -Cutoff $cutoff)
        $rows[0].MailboxType | Should -Be 'unknown'
        $rows[0].Findings | Should -Not -Match 'mailbox not shared'
    }

    Context 'when no activity signal is available' {
        It 'flags only disabled accounts, never inactive-looking enabled ones' {
            $users = @(
                New-TestAccount -Name 'enabled-noactivity' -Last $null
                New-TestAccount -Name 'disabled' -Enabled $false -Last $null
            )
            $rows = @(Get-OffboardingRow -Users $users -SkuMap $skuMap -Cutoff $cutoff -ActivitySignalAvailable $false)
            $rows.Count | Should -Be 1
            $rows[0].UserPrincipalName | Should -Be 'disabled@contoso.com'
        }
    }

    It 'handles a null user set without error (tenant with 0 users)' {
        { Get-OffboardingRow -Users $null -SkuMap $skuMap -Cutoff $cutoff } | Should -Not -Throw
        (Get-OffboardingRow -Users $null -SkuMap $skuMap -Cutoff $cutoff) | Should -BeNullOrEmpty
    }

    It 'handles an empty user set without error' {
        (Get-OffboardingRow -Users @() -SkuMap $skuMap -Cutoff $cutoff) | Should -BeNullOrEmpty
    }
}

Describe 'Shared helpers are reused, not reimplemented' {
    It 'relies on Invoke-LicenseScan.ps1 for sign-in and activity rather than its own copy' {
        $src = Get-Content -Raw (Join-Path (Split-Path -Parent $PSScriptRoot) 'Invoke-OffboardingCheck.ps1')
        $src | Should -Match 'Connect-ScanGraph'
        $src | Should -Match 'Resolve-ActivityMap'
        # The device-code retry lives in exactly one place; a second copy here would drift.
        $src | Should -Not -Match 'UseDeviceCode'
    }
}

Describe 'Offboarding upsell text' {
    It 'never advertises paid features that are not built' {
        $src = Get-Content -Raw (Join-Path (Split-Path -Parent $PSScriptRoot) 'Invoke-OffboardingCheck.ps1')
        $src | Should -Not -Match '(?i)downgrade'
        $src | Should -Not -Match '(?i)service-level waste'
        $src | Should -Not -Match '(?i)white.?label'
    }
    It 'says plainly that it changes nothing' {
        $src = Get-Content -Raw (Join-Path (Split-Path -Parent $PSScriptRoot) 'Invoke-OffboardingCheck.ps1')
        $src | Should -Match 'never writes, removes, or changes anything'
    }
}

Describe 'Exchange Online mailbox types (prototype)' {
    # Why this exists: on 2026-09-22 a mailbox Exchange reports as SharedMailbox (since 09-15) was
    # ABSENT from getMailboxUsageDetail at D7 and D180 alike. The report only lists mailboxes with
    # activity, so an untouched shared mailbox - the one most likely to be wasting a license - can
    # never be found through it.

    It 'prefers the Exchange answer and keeps report-only entries' {
        $merged = Merge-MailboxTypeMap `
            -ReportMap   @{ 'a@c.com' = 'user'; 'b@c.com' = 'user' } `
            -ExchangeMap @{ 'a@c.com' = 'shared'; 'z@c.com' = 'room' }

        $merged['a@c.com'] | Should -Be 'shared'   # Exchange wins on conflict
        $merged['b@c.com'] | Should -Be 'user'     # report-only entry survives
        $merged['z@c.com'] | Should -Be 'room'     # Exchange-only entry is added
    }

    It 'handles either side being empty' {
        (Merge-MailboxTypeMap -ReportMap @{} -ExchangeMap @{ 'a@c.com' = 'shared' })['a@c.com'] | Should -Be 'shared'
        (Merge-MailboxTypeMap -ReportMap @{ 'a@c.com' = 'user' } -ExchangeMap @{})['a@c.com'] | Should -Be 'user'
        (Merge-MailboxTypeMap -ReportMap @{} -ExchangeMap @{}).Count | Should -Be 0
    }

    It 'degrades to the usage report when ExchangeOnlineManagement is absent' {
        Mock -CommandName Test-ExchangeOnlineModulePresent -MockWith { $false }

        $result = Get-MailboxTypeMapFromExchange

        $result.ok | Should -BeFalse
        $result.map.Count | Should -Be 0
        $result.note | Should -Match 'ExchangeOnlineManagement'
    }

    It 'is opt-in, so the default run keeps one sign-in and Graph-only scopes' {
        $src = Get-Content -Raw (Join-Path (Split-Path -Parent $PSScriptRoot) 'Invoke-OffboardingCheck.ps1')
        $src | Should -Match '\[switch\]\$UseExchangeOnline'
        $src | Should -Match 'if \(\$UseExchangeOnline\)'
    }

    It 'only ever reads from Exchange' {
        $src = Get-Content -Raw (Join-Path (Split-Path -Parent $PSScriptRoot) 'Invoke-OffboardingCheck.ps1')
        $src | Should -Not -Match '(?m)^\s*(Set|New|Remove|Disable|Enable)-(EXO)?Mailbox'
    }
}

Describe 'An unreadable mailbox type is never reported as zero' {
    # The paid CLI printed "0 mailbox(es) not converted to shared" when NO type could be read,
    # which reads as an all-clear on work nobody checked. Same defect, same shape, here.
    It 'says unknown rather than 0 when nothing could be read' {
        $src = Get-Content -Raw (Join-Path (Split-Path -Parent $PSScriptRoot) 'Invoke-OffboardingCheck.ps1')
        $src | Should -Match 'unknown \(no mailbox types could be read\)'
    }
}

Describe 'Caller parameters survive the shared dot-source' {
    # Invoke-LicenseScan.ps1 has its own param() block (InactiveDays, OutputCsv, IncludeGuests,
    # PassThru). Dot-sourcing it runs it in THIS script's scope, re-declaring those four at their
    # defaults and wiping what the caller passed. Found 2026-09-22 when a run ignored -OutputCsv and
    # wrote to the default path instead; -IncludeGuests was silently doing nothing too.
    It 'snapshots the caller arguments before dot-sourcing the shared script' {
        $src = Get-Content -Raw (Join-Path (Split-Path -Parent $PSScriptRoot) 'Invoke-OffboardingCheck.ps1')
        $snapshotAt = $src.IndexOf('$callerArgs = @{')
        $dotSourceAt = $src.IndexOf('. $sharedPath')

        $snapshotAt | Should -BeGreaterThan 0
        $dotSourceAt | Should -BeGreaterThan 0
        $snapshotAt | Should -BeLessThan $dotSourceAt
    }

    It 'passes the snapshot to the entry point, not the clobbered variables' {
        $src = Get-Content -Raw (Join-Path (Split-Path -Parent $PSScriptRoot) 'Invoke-OffboardingCheck.ps1')
        # The INVOCATION at the bottom of the script, not the function definition above it.
        $call = [regex]::Match($src, "InvocationName -ne '\.'\)\s*\{[\s\S]*?\n\}").Value

        $call | Should -Match '\$callerArgs\.OutputCsv'
        $call | Should -Match '\$callerArgs\.IncludeGuests'
        $call | Should -Not -Match '-OutputCsv \$OutputCsv'
    }
}
