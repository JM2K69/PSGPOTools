function Get-PSGPOPolicy {
    <#
    .SYNOPSIS
        The policies of the administrative templates loaded by Initialize-PSGPOAdmx.
    .DESCRIPTION
        Each policy of the ADMX files loaded (Initialize-PSGPOAdmx): its name and explanation in the
        language of the ADML files, its category, its supported platforms, the registry values it
        writes when enabled or disabled, and its options (elements). A policy of both scopes in the
        ADMX is listed once for each.
    .PARAMETER Scope
        Machine (Computer Configuration) or User (User Configuration); both by default.
    .EXAMPLE
        Initialize-PSGPOAdmx -Path C:\Windows\PolicyDefinitions -UICulture fr-FR
        Get-PSGPOPolicy -Scope Machine | Where-Object DisplayName -Like '*biom*' | Select-Object DisplayName, Registry
    .OUTPUTS
        GPOToolsPolicy
    .LINK
        https://jm2k69.github.io/PSGPOTools/en/reference/commands/get-psgpopolicy/
    .LINK
        Initialize-PSGPOAdmx
    #>
    [CmdletBinding()]
    [OutputType([GPOToolsPolicy])]
    param(
        [ValidateSet('User', 'Machine')]
        [string]$Scope
    )

    $Policies = [GPOToolsUtility]::Policies
    if ($Policies.Count -eq 0) {
        Write-Warning 'No administrative template is loaded: run Initialize-PSGPOAdmx first.'
        return
    }
    if ($Scope) { $Policies | Where-Object Scope -EQ $Scope } else { $Policies }
}
