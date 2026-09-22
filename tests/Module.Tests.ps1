#Requires -Modules Pester

BeforeAll {
    $repo = Split-Path -Parent $PSScriptRoot
    $modulePath = & (Join-Path (Join-Path $repo 'build') 'Build-Module.ps1')
    $manifestPath = Join-Path $modulePath 'ServerBridge.LicenseScan.psd1'
    $manifest = Import-PowerShellDataFile -Path $manifestPath
    Import-Module $manifestPath -Force
}

AfterAll {
    Remove-Module ServerBridge.LicenseScan -ErrorAction SilentlyContinue
}

Describe 'ServerBridge.LicenseScan module' {
    It 'has a valid manifest at version 1.2.2' {
        (Test-ModuleManifest -Path $manifestPath).Version.ToString() | Should -Be '1.2.2'
    }

    It 'exports exactly the two public commands' {
        $names = @(Get-Command -Module ServerBridge.LicenseScan | ForEach-Object Name) | Sort-Object
        ($names -join ',') | Should -Be 'Invoke-LicenseScan,Invoke-OffboardingCheck'
    }

    It 'declares the Graph modules the scan uses, so Install-Module brings them along' {
        $names = @($manifest.RequiredModules | ForEach-Object { $_.ModuleName }) | Sort-Object
        ($names -join ',') | Should -Be 'Microsoft.Graph.Authentication,Microsoft.Graph.Identity.DirectoryManagement,Microsoft.Graph.Users'
    }

    It 'supports Windows PowerShell 5.1 and PowerShell 7' {
        $manifest.PowerShellVersion | Should -Be '5.1'
        (@($manifest.CompatiblePSEditions) -join ',') | Should -Be 'Desktop,Core'
    }

    It 'ships every file it lists' {
        foreach ($file in $manifest.FileList) {
            Join-Path $modulePath $file | Should -Exist
        }
    }

    It 'keeps the same parameters as the standalone script' {
        $params = (Get-Command Invoke-LicenseScan).Parameters.Keys
        foreach ($name in 'InactiveDays', 'OutputCsv', 'IncludeGuests', 'PassThru') {
            $params | Should -Contain $name
        }
    }

    It 'has help with the Install-Module example' {
        (Get-Help Invoke-LicenseScan -Full | Out-String) | Should -Match 'Install-Module ServerBridge.LicenseScan'
    }

    It 'rejects an out-of-range InactiveDays before trying to sign in' {
        { Invoke-LicenseScan -InactiveDays 0 } | Should -Throw
    }

    It 'does not start a scan when the module is imported' {
        Get-Command Invoke-LicenseScanMain -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
    }

    It 'does not leak the offboarding entry point either' {
        Get-Command Invoke-OffboardingCheckMain -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
    }

    It 'gives Invoke-OffboardingCheck the same parameters as its standalone script' {
        # Derived from the script, not hardcoded. The old version listed four names by hand, so it
        # passed happily while the module wrapper was missing -UseExchangeOnline altogether
        # (found 2026-09-22): a parity test that cannot see a new parameter is not a parity test.
        $scriptPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Invoke-OffboardingCheck.ps1'
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$null)
        $scriptParams = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })

        $scriptParams.Count | Should -BeGreaterThan 0
        $moduleParams = (Get-Command Invoke-OffboardingCheck).Parameters.Keys
        foreach ($name in $scriptParams) {
            $moduleParams | Should -Contain $name
        }
    }

    It 'rejects an out-of-range InactiveDays on the offboarding check too' {
        { Invoke-OffboardingCheck -InactiveDays 0 } | Should -Throw
    }
}
