@{
    RootModule        = 'ServerBridge.LicenseScan.psm1'
    ModuleVersion     = '1.2.2'
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
            ReleaseNotes = 'Important fix: sign-in was impossible on Microsoft Graph PowerShell SDK 2.38. Both commands printed "a device code will appear below", then no code, then timed out after two minutes. If you hit that, nothing was wrong on your side. Also fixes -OutputCsv, -IncludeGuests and -PassThru being ignored when Invoke-OffboardingCheck.ps1 was run as a script, and a summary line that said "0 mailboxes not converted to shared" when no mailbox type could be read at all - it now says unknown. New, experimental: Invoke-OffboardingCheck -UseExchangeOnline reads mailbox types from Exchange Online, which unlike Microsoft''s usage report can see mailboxes that have never been used. Off by default; it needs a second sign-in. See CHANGELOG.md on GitHub for earlier changes.'
        }
    }
}
