@{
    # This is an interactive, colorized CLI tool for humans at a console, so
    # Write-Host is the correct output mechanism (not Write-Output/streams).
    ExcludeRules = @(
        'PSAvoidUsingWriteHost'
    )
    Severity = @('Error', 'Warning')
}
