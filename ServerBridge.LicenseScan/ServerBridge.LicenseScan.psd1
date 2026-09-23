@{
    RootModule        = 'ServerBridge.LicenseScan.psm1'
    ModuleVersion     = '1.3.0'
    GUID              = '24b0a1fa-4b98-4900-99db-b0f3c9f960cf'
    Author            = 'Lee Crowe Software Solutions LLC'
    CompanyName       = 'Lee Crowe Software Solutions LLC'
    Copyright         = '(c) Lee Crowe Software Solutions LLC. MIT License.'
    Description       = 'Free, read-only Microsoft 365 admin scans. Invoke-LicenseScan cross-checks every assigned license against real sign-in or usage activity and shows the seats you pay for that nobody uses, in dollars. Invoke-OffboardingCheck finds accounts that look like leavers and shows what they still hold: licenses, group memberships, and mailboxes never converted to shared. Device-code sign-in, no app registration, nothing stored, never changes your tenant.'

    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')

    # Installed automatically by Install-Module, so the scan works in one step.
    RequiredModules = @(
        @{ ModuleName = 'Microsoft.Graph.Authentication';               ModuleVersion = '2.0.0' }
        @{ ModuleName = 'Microsoft.Graph.Users';                        ModuleVersion = '2.0.0' }
        @{ ModuleName = 'Microsoft.Graph.Identity.DirectoryManagement'; ModuleVersion = '2.0.0' }
    )

    FunctionsToExport = @('Invoke-LicenseScan', 'Invoke-OffboardingCheck')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    FileList = @('ServerBridge.LicenseScan.psd1', 'ServerBridge.LicenseScan.psm1', 'Invoke-LicenseScan.ps1', 'Invoke-OffboardingCheck.ps1', 'LICENSE')

    PrivateData = @{
        PSData = @{
            Tags         = @('Microsoft365', 'M365', 'Office365', 'Licensing', 'License', 'Audit', 'CostOptimization',
                             'Offboarding', 'StaleAccounts', 'Mailbox',
                             'MicrosoftGraph', 'Entra', 'ReadOnly', 'PSEdition_Desktop', 'PSEdition_Core',
                             'Windows', 'Linux', 'MacOS')
            LicenseUri   = 'https://github.com/lbcrowe-del/ServerBridge-LicenseScan/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/lbcrowe-del/ServerBridge-LicenseScan'
            ReleaseNotes = 'Changed: failed sign-in attempts no longer make a dormant account look active. lastSignInDateTime records attempts including failures, so an account being password-sprayed kept a fresh timestamp and stayed licensed without review. Both commands now read the newest of the non-interactive and successful timestamps, with a fallback if lastSuccessfulSignInDateTime is empty across a whole tenant. Affects Entra ID P1/P2 tenants only. Raised by iRyan23 on r/entra. New (experimental): Invoke-OffboardingCheck -UseExchangeOnline reads mailbox types from Exchange Online, which unlike Microsoft''s usage report can see mailboxes that have never been used. Off by default; needs a second sign-in. Fixed: signing in with a personal Microsoft account now says to use your work account instead of suggesting you check permissions. See CHANGELOG.md on GitHub.'
        }
    }
}
