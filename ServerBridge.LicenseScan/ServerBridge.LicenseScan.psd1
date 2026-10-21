@{
    RootModule        = 'ServerBridge.LicenseScan.psm1'
    ModuleVersion     = '1.6.0'
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
            ReleaseNotes = 'Prices corrected and updated to Microsoft''s July 1, 2026 list. Office 365 E3 and E5 had been priced as Microsoft 365 E3 and E5 ($36 and $57 instead of $26 and $41), overstating waste on those seats by about 40%. The scan now prints one plainly labelled estimate line, and when the waste is worth more than the paid tool costs, one line about the paid License Auditor. Existing customers keep their old Microsoft price until renewal, so figures are list-price estimates. See CHANGELOG.md on GitHub for earlier changes.'
        }
    }
}
