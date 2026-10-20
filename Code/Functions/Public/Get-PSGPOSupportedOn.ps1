function Get-PSGPOSupportedOn {
    <#
    .SYNOPSIS
        The platforms the policies of the loaded administrative templates support.
    .DESCRIPTION
        Each supportedOn definition of the ADMX files loaded (Initialize-PSGPOAdmx), with its text in
        the language of the ADML files ("At least Windows 10"...): what the Details tab of a policy
        shows, and what the policy editor filters on.
    .EXAMPLE
        Initialize-PSGPOAdmx -Path C:\Windows\PolicyDefinitions
        Get-PSGPOSupportedOn | Where-Object DisplayName -Like '*Windows 11*'
    .OUTPUTS
        GPOToolsSupportedOn
    .LINK
        https://jm2k69.github.io/PSGPOTools/en/reference/commands/get-psgposupportedon/
    .LINK
        Initialize-PSGPOAdmx
    #>
    [CmdletBinding()]
    [OutputType([GPOToolsSupportedOn])]
    param()

    $Support = [GPOToolsUtility]::SupportOnTable
    if ($Support.Count -eq 0) {
        Write-Warning 'No administrative template is loaded: run Initialize-PSGPOAdmx first.'
        return
    }
    $Support
}
