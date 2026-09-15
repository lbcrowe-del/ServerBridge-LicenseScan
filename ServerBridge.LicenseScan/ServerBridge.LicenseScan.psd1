@{
    RootModule        = 'ServerBridge.LicenseScan.psm1'
    ModuleVersion     = '1.1.1'
    GUID              = '24b0a1fa-4b98-4900-99db-b0f3c9f960cf'
    Author            = 'Lee Crowe Software Solutions LLC'
    CompanyName       = 'Lee Crowe Software Solutions LLC'
    Copyright         = '(c) Lee Crowe Software Solutions LLC. MIT License.'
    Description       = 'Free, read-only Microsoft 365 unused-license scan. Cross-checks every assigned license against real sign-in or usage activity and shows the seats you pay for that nobody uses, in dollars. Device-code sign-in, no app registration, nothing stored, never changes your tenant.'

    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')

    # Installed automatically by Install-Module, so the scan works in one step.
    RequiredModules = @(
        @{ ModuleName = 'Microsoft.Graph.Authentication';               ModuleVersion = '2.0.0' }
        @{ ModuleName = 'Microsoft.Graph.Users';                        ModuleVersion = '2.0.0' }
        @{ ModuleName = 'Microsoft.Graph.Identity.DirectoryManagement'; ModuleVersion = '2.0.0' }
    )

    FunctionsToExport = @('Invoke-LicenseScan')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    FileList = @('ServerBridge.LicenseScan.psd1', 'ServerBridge.LicenseScan.psm1', 'Invoke-LicenseScan.ps1', 'LICENSE')

    PrivateData = @{
        PSData = @{
            Tags         = @('Microsoft365', 'M365', 'Office365', 'Licensing', 'License', 'Audit', 'CostOptimization',
                             'MicrosoftGraph', 'Entra', 'ReadOnly', 'PSEdition_Desktop', 'PSEdition_Core',
                             'Windows', 'Linux', 'MacOS')
            LicenseUri   = 'https://github.com/lbcrowe-del/ServerBridge-LicenseScan/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/lbcrowe-del/ServerBridge-LicenseScan'
            ReleaseNotes = 'Sign-in: says up front that the device code must be entered within 2 minutes, and if it expires offers a new code in the same window instead of stopping. See CHANGELOG.md on GitHub for earlier changes.'
        }
    }
}
