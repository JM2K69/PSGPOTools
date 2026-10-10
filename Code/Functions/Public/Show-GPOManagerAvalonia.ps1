function Show-GPOManagerAvalonia {
    <#
    .SYNOPSIS
        Cross-platform (Windows/Linux/macOS) graphical explorer for the loaded ADMX policies.
    .DESCRIPTION
        Displays the policies loaded by Initialize-PSGPOAdmx in a tree (scope > categories >
        policies) with a details panel, hosted on Avalonia UI under PowerShell 7+.
        The call blocks until the window is closed.

        The Avalonia assemblies are not bundled with the module; run
        .\Avalonia\Get-AvaloniaBinaries.ps1 once per target platform beforehand (see that
        script's help for details). All GPO/ADMX logic stays in PowerShell; Avalonia is
        only used to render the window, its assemblies being loaded at runtime.
    .EXAMPLE
        Initialize-PSGPOAdmx -UICulture 'en-US'
        Show-GPOManagerAvalonia
    .LINK
        https://www.deploymentresearch.com/using-avalonia-ui-in-deployr-task-sequences/
    #>
    [CmdletBinding()]
    Param()

    Start-PSGPOManagerWindow
}
