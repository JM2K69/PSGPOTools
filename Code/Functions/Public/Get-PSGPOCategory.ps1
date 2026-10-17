function Get-PSGPOCategory {
    <#
    .SYNOPSIS
        The categories of the administrative templates loaded by Initialize-PSGPOAdmx.
    .DESCRIPTION
        Each category of the ADMX files loaded (Initialize-PSGPOAdmx), with its name in the language
        of the ADML files and its parent category: the tree of Administrative Templates in the
        policy editor.
    .EXAMPLE
        Initialize-PSGPOAdmx -Path C:\Windows\PolicyDefinitions
        Get-PSGPOCategory | Where-Object DisplayName -Like '*Windows Update*'
    .OUTPUTS
        GPOToolsCategory
    .LINK
        Initialize-PSGPOAdmx
    #>
    [CmdletBinding()]
    [OutputType([GPOToolsCategory])]
    param()

    $Categories = [GPOToolsUtility]::Categories
    if ($Categories.Count -eq 0) {
        Write-Warning 'No administrative template is loaded: run Initialize-PSGPOAdmx first.'
        return
    }
    $Categories
}
