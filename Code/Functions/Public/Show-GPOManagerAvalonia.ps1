function Show-GPOManagerAvalonia {
    <#
    .SYNOPSIS
        Cross-platform (Windows/Linux/macOS) graphical console for Group Policy.
    .DESCRIPTION
        With -Directory, opens on the Group Policy Management view, as GPMC: the domain, its
        OUs and their GPO links, and the Group Policy Objects container. Its context menu
        creates a GPO (linked to the selected domain or OU, or not linked) and edits a GPO in
        the policy editor.

        The policy editor displays the policies loaded by Initialize-PSGPOAdmx in a tree
        (scope > categories > policies) with their setting form and details. Without
        -Directory, the window opens on it to browse the ADMX policies.

        Proof of concept: the directory is read from JSON (Import-PSGPODirectory) and the
        changes stay in memory; the settings are not saved to the GPO yet.

        Hosted on Avalonia UI under PowerShell 7+; the call blocks until the window is closed.
        The Avalonia assemblies are not bundled with the module; run
        .\Avalonia\Get-AvaloniaBinaries.ps1 once per target platform beforehand (see that
        script's help for details).
    .PARAMETER Directory
        Domain to manage, from Import-PSGPODirectory.
    .EXAMPLE
        Initialize-PSGPOAdmx -UICulture 'en-US'
        Show-GPOManagerAvalonia
    .EXAMPLE
        Initialize-PSGPOAdmx -UICulture 'en-US'
        $Sample = Join-Path (Split-Path (Get-Module PSGPOTools).Path) 'Samples' 'Directory.sample.json'
        Show-GPOManagerAvalonia -Directory (Import-PSGPODirectory -Path $Sample)
    .LINK
        https://www.deploymentresearch.com/using-avalonia-ui-in-deployr-task-sequences/
    #>
    [CmdletBinding()]
    Param(
        [GPOToolsDirectory]$Directory
    )

    Start-PSGPOManagerWindow -Directory $Directory
}
