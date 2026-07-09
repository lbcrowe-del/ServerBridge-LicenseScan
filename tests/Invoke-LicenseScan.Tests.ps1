#Requires -Modules Pester

BeforeAll {
    # Dot-source the script; InvocationName '.' prevents Invoke-LicenseScanMain from running.
    . (Join-Path $PSScriptRoot '..' 'Invoke-LicenseScan.ps1')
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

Describe 'Test-UserDormant' {
    BeforeAll { $cutoff = (Get-Date).AddDays(-90) }

    It 'treats a never-signed-in user (null) as dormant' {
        Test-UserDormant -LastSignIn $null -Cutoff $cutoff | Should -BeTrue
    }
    It 'treats an old sign-in as dormant' {
        Test-UserDormant -LastSignIn (Get-Date).AddDays(-120) -Cutoff $cutoff | Should -BeTrue
    }
    It 'treats a recent sign-in as active' {
        Test-UserDormant -LastSignIn (Get-Date).AddDays(-10) -Cutoff $cutoff | Should -BeFalse
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
            param($Name, $Type, $Enabled, $Last, $Skus)
            [pscustomobject]@{
                DisplayName       = $Name
                UserPrincipalName = "$Name@contoso.com"
                UserType          = $Type
                AccountEnabled    = $Enabled
                SignInActivity    = [pscustomobject]@{ LastSignInDateTime = $Last }
                AssignedLicenses  = @($Skus | ForEach-Object { [pscustomobject]@{ SkuId = $_ } })
            }
        }
    }

    It 'emits a row for a dormant member with a priced license' {
        $users = @(New-TestUser 'dana' 'Member' $true $null @('sku-e3'))
        $rows = @(Get-DormantLicenseRow -Users $users -SkuMap $skuMap -Cutoff $cutoff)
        $rows.Count | Should -Be 1
        $rows[0].Sku | Should -Be 'ENTERPRISEPACK'
        $rows[0].AnnualCost | Should -Be 432.00
        $rows[0].LastSignIn | Should -Be 'never'
    }

    It 'skips active users' {
        $users = @(New-TestUser 'active' 'Member' $true (Get-Date).AddDays(-5) @('sku-e3'))
        (Get-DormantLicenseRow -Users $users -SkuMap $skuMap -Cutoff $cutoff) | Should -BeNullOrEmpty
    }

    It 'skips free SKUs even when the user is dormant' {
        $users = @(New-TestUser 'freeonly' 'Member' $true $null @('sku-free'))
        (Get-DormantLicenseRow -Users $users -SkuMap $skuMap -Cutoff $cutoff) | Should -BeNullOrEmpty
    }

    It 'excludes guests by default but includes them with -IncludeGuests' {
        $users = @(New-TestUser 'guest' 'Guest' $true $null @('sku-e3'))
        (Get-DormantLicenseRow -Users $users -SkuMap $skuMap -Cutoff $cutoff) | Should -BeNullOrEmpty
        (Get-DormantLicenseRow -Users $users -SkuMap $skuMap -Cutoff $cutoff -IncludeGuests).Count | Should -Be 1
    }

    It 'handles an empty user set without error' {
        (Get-DormantLicenseRow -Users @() -SkuMap $skuMap -Cutoff $cutoff) | Should -BeNullOrEmpty
    }
}
