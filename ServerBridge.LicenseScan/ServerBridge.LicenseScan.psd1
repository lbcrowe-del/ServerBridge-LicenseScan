@{
    RootModule        = 'ServerBridge.LicenseScan.psm1'
    ModuleVersion     = '1.4.0'
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
            ReleaseNotes = 'Both commands now say whether the paid Auditor is actually worth it for your tenant, using the numbers the scan just produced. If the recoverable spend is less than the tool costs, they say so and tell you to keep your money - no link. If there is nothing to recover, they say there is nothing worth paying for. New: the offboarding check shows what the leavers are still costing per year, both in the summary and as an AnnualCost column in the CSV - note this adds a column, which matters if you parse the CSV by position. See CHANGELOG.md on GitHub for earlier changes.'
        }
    }
}
