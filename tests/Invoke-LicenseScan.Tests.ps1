#Requires -Modules Pester

BeforeAll {
    # Dot-source the script; InvocationName '.' prevents Invoke-LicenseScanMain from running.
    . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Invoke-LicenseScan.ps1')
}

Describe 'Get-SkuMonthlyPrice' {
    It 'returns the mapped price for a known SKU' {
        Get-SkuMonthlyPrice -PartNumber 'ENTERPRISEPACK' | Should -Be 36.00
    }
    It 'returns the mapped price for Copilot' {
        Get-SkuMonthlyPrice -PartNumber 'Microsoft_365_Copilot' | Should -Be 30.00
    }
    It 'returns the default price for an unknown SKU' {
        Get-SkuMonthlyPrice -PartNumber 'TOTALLY_MADE_UP_SKU' | Should -Be 20.00
    }
    It 'returns 0 for a known free SKU' {
        Get-SkuMonthlyPrice -PartNumber 'TEAMS_EXPLORATORY' | Should -Be 0
    }
}

Describe 'Get-NewestSignIn' {
    BeforeAll {
        $old = (Get-Date).AddDays(-400)
        $recent = (Get-Date).AddDays(-5)
        $newest = (Get-Date).AddDays(-1)
    }

    It 'returns nothing when the user has no sign-in timestamps at all' {
        Get-NewestSignIn -Interactive $null -NonInteractive $null -Successful $null | Should -BeNullOrEmpty
    }

    It 'does NOT call a mobile-only user dormant' {
        # robofski, r/PowerShell 2026-09-17: Outlook and Teams on a phone sign in non-interactively,
        # so a working user can have no interactive sign-in. Reading only the interactive timestamp
        # returned nothing here and flagged them for licence removal.
        Get-NewestSignIn -Interactive $null -NonInteractive $recent -Successful $null |
            Should -Be $recent
    }

    It 'takes the most recent timestamp whichever property it came from' {
        Get-NewestSignIn -Interactive $newest -NonInteractive $old -Successful $recent | Should -Be $newest
        Get-NewestSignIn -Interactive $old -NonInteractive $newest -Successful $recent | Should -Be $newest
        Get-NewestSignIn -Interactive $old -NonInteractive $recent -Successful $newest | Should -Be $newest
    }

    It 'still works on tenants where lastSuccessfulSignInDateTime was never backfilled' {
        # Microsoft only began populating that property in Dec 2023 and did not backfill it.
        Get-NewestSignIn -Interactive $recent -NonInteractive $old -Successful $null | Should -Be $recent
    }

    It 'errs toward active, which is the deliberate choice' {
        # Under-flagging costs a missed saving; over-flagging tells an admin to strip a licence
        # from someone still working.
        Get-NewestSignIn -Interactive $old -NonInteractive $newest -Successful $null | Should -Be $newest
    }

    It 'accepts the string timestamps Graph sometimes hands back' {
        $asText = (Get-Date).AddDays(-3).ToString('o')
        (Get-NewestSignIn -Interactive $asText -NonInteractive $old -Successful $null) |
            Should -BeOfType [datetime]
    }
}

Describe 'Test-UserDormant' {
    BeforeAll { $cutoff = (Get-Date).AddDays(-90) }

    It 'treats a never-active user (null) as dormant' {
        Test-UserDormant -LastActivity $null -Cutoff $cutoff | Should -BeTrue
    }
    It 'treats old activity as dormant' {
        Test-UserDormant -LastActivity (Get-Date).AddDays(-120) -Cutoff $cutoff | Should -BeTrue
    }
    It 'treats recent activity as active' {
        Test-UserDormant -LastActivity (Get-Date).AddDays(-10) -Cutoff $cutoff | Should -BeFalse
    }
}

Describe 'Get-DormantLicenseRow' {
    BeforeAll {
        $skuMap = @{
            'sku-e3'   = 'ENTERPRISEPACK'
            'sku-free' = 'TEAMS_EXPLORATORY'
        }
        $cutoff = (Get-Date).AddDays(-90)

        function New-TestUser {
            param($Name, $Type = 'Member', $Enabled = $true, $Last = $null, $Skus = @('sku-e3'))
            [pscustomobject]@{
                DisplayName       = $Name
                UserPrincipalName = "$Name@contoso.com"
                UserType          = $Type
                AccountEnabled    = $Enabled
                LastActivity      = $Last
                AssignedLicenses  = @($Skus | ForEach-Object { [pscustomobject]@{ SkuId = $_ } })
            }
        }
    }

    It 'emits a row for a dormant member with a priced license' {
        $users = @(New-TestUser -Name 'dana' -Last $null)
        $rows = @(Get-DormantLicenseRow -Users $users -SkuMap $skuMap -Cutoff $cutoff)
        $rows.Count | Should -Be 1
        $rows[0].Sku | Should -Be 'ENTERPRISEPACK'
        $rows[0].AnnualCost | Should -Be 432.00
        $rows[0].Reason | Should -Be 'inactive'
        $rows[0].LastActivity | Should -Be 'never/unknown'
    }

    It 'skips active users' {
        $users = @(New-TestUser -Name 'active' -Last (Get-Date).AddDays(-5))
        (Get-DormantLicenseRow -Users $users -SkuMap $skuMap -Cutoff $cutoff) | Should -BeNullOrEmpty
    }

    It 'flags a disabled account even if recently active' {
        $users = @(New-TestUser -Name 'exemp' -Enabled $false -Last (Get-Date).AddDays(-1))
        $rows = @(Get-DormantLicenseRow -Users $users -SkuMap $skuMap -Cutoff $cutoff)
        $rows.Count | Should -Be 1
        $rows[0].Reason | Should -Be 'disabled'
    }

    It 'skips free SKUs even when the user is dormant' {
        $users = @(New-TestUser -Name 'freeonly' -Last $null -Skus @('sku-free'))
        (Get-DormantLicenseRow -Users $users -SkuMap $skuMap -Cutoff $cutoff) | Should -BeNullOrEmpty
    }

    It 'excludes guests by default but includes them with -IncludeGuests' {
        $users = @(New-TestUser -Name 'guest' -Type 'Guest' -Last $null)
        (Get-DormantLicenseRow -Users $users -SkuMap $skuMap -Cutoff $cutoff) | Should -BeNullOrEmpty
        @(Get-DormantLicenseRow -Users $users -SkuMap $skuMap -Cutoff $cutoff -IncludeGuests).Count | Should -Be 1  # @() so .Count works on Windows PowerShell 5.1
    }

    Context 'when no activity signal is available' {
        It 'flags only disabled accounts, not inactive enabled ones' {
            $users = @(
                New-TestUser -Name 'enabled-noactivity' -Last $null
                New-TestUser -Name 'disabled' -Enabled $false -Last $null
            )
            $rows = @(Get-DormantLicenseRow -Users $users -SkuMap $skuMap -Cutoff $cutoff -ActivitySignalAvailable $false)
            $rows.Count | Should -Be 1
            $rows[0].UserPrincipalName | Should -Be 'disabled@contoso.com'
            $rows[0].Reason | Should -Be 'disabled'
        }
    }

    It 'handles a null user set without error (tenant with 0 licensed users)' {
        { Get-DormantLicenseRow -Users $null -SkuMap $skuMap -Cutoff $cutoff } | Should -Not -Throw
        (Get-DormantLicenseRow -Users $null -SkuMap $skuMap -Cutoff $cutoff) | Should -BeNullOrEmpty
    }

    It 'handles an empty user set without error' {
        (Get-DormantLicenseRow -Users @() -SkuMap $skuMap -Cutoff $cutoff) | Should -BeNullOrEmpty
    }
}

Describe 'Get-ConcealedNamesHelpText' {
    It "uses Microsoft's exact checkbox wording and the admin center address" {
        $text = (Get-ConcealedNamesHelpText) -join "`n"
        $text | Should -Match 'Conceal user, group, and site names in all reports'
        $text | Should -Match 'https://admin.microsoft.com'
        $text | Should -Match 'Settings > Org settings > Services > Reports'
    }
    It 'gives numbered steps and says it can be turned back on' {
        $lines = @(Get-ConcealedNamesHelpText)
        @($lines | Where-Object { $_ -match '^\s+[123]\. ' }).Count | Should -Be 3
        ($lines -join ' ') | Should -Match 'turn it back on'
    }
}

Describe 'ConvertTo-SafeCsvValue' {
    It 'prefixes a quote to text that a spreadsheet would run as a formula' {
        foreach ($evil in '=HYPERLINK("http://x","y")', '+1+1', '-2+3', '@SUM(A1)', "`tcmd") {
            ConvertTo-SafeCsvValue -Value $evil | Should -Be ("'" + $evil)
        }
    }
    It 'leaves normal names, emails and numbers alone' {
        ConvertTo-SafeCsvValue -Value 'Dana Smith' | Should -Be 'Dana Smith'
        ConvertTo-SafeCsvValue -Value 'dana@contoso.com' | Should -Be 'dana@contoso.com'
        ConvertTo-SafeCsvValue -Value 432.0 | Should -Be 432.0
    }
    It 'passes through null and empty values' {
        ConvertTo-SafeCsvValue -Value $null | Should -BeNullOrEmpty
        ConvertTo-SafeCsvValue -Value '' | Should -Be ''
    }
}

Describe 'Test-SignInTimedOut' {
    It 'recognises Microsoft''s 2-minute device code timeout' {
        Test-SignInTimedOut -Message 'Authentication timed out after 120 seconds due to inactivity. Please try again.' | Should -BeTrue
    }
    It 'does not treat other sign-in errors as a timeout' {
        Test-SignInTimedOut -Message 'AADSTS50105: The signed in user is not assigned to a role for the application.' | Should -BeFalse
    }
    It 'handles an empty message' {
        Test-SignInTimedOut -Message '' | Should -BeFalse
    }
}

Describe 'Sign-in timeout handling' {
    It 'warns about the 2-minute limit and offers a new code' {
        $src = Get-Content (Join-Path (Split-Path -Parent $PSScriptRoot) 'Invoke-LicenseScan.ps1') -Raw
        $src | Should -Match 'enter it within 2 minutes'
        $src | Should -Match 'Press Enter for a new code'
    }
}

Describe 'Sign-in hygiene' {
    It 'keeps the Microsoft sign-in in memory only (process scope)' {
        $src = Get-Content -Raw (Join-Path (Split-Path -Parent $PSScriptRoot) 'Invoke-LicenseScan.ps1')
        $src | Should -Match 'Connect-MgGraph[^\r\n]*-ContextScope Process'
    }
}

Describe 'Upsell text' {
    It 'never advertises paid features that are not built' {
        $src = Get-Content -Raw (Join-Path (Split-Path -Parent $PSScriptRoot) 'Invoke-LicenseScan.ps1')
        $src | Should -Not -Match '(?i)downgrade'
        $src | Should -Not -Match '(?i)service-level waste'
        $src | Should -Not -Match '(?i)guest/shared'
    }
}

