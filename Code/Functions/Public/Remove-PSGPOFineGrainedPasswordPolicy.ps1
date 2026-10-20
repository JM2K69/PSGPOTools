function Remove-PSGPOFineGrainedPasswordPolicy {
    <#
    .SYNOPSIS
        Deletes fine-grained password policies (PSO) of the domain.
    .DESCRIPTION
        The users the PSO applied to get the next PSO that concerns them, or the password policy of
        the domain. As in the Active Directory Administrative Center, a PSO protected from
        accidental deletion is kept: clear its protection first (Set-PSGPOFineGrainedPasswordPolicy
        -ProtectedFromAccidentalDeletion $false).
    .PARAMETER Name
        Names of the PSOs (* and ? make a pattern).
    .PARAMETER Server
        Domain controller to write to: its DNS name. By default, the domain of the computer.
    .PARAMETER Credential
        Account to write with, instead of the current identity (Kerberos).
    .PARAMETER UseSsl
        LDAPS (port 636): the certificate of the server must be trusted by the system.
    .EXAMPLE
        Remove-PSGPOFineGrainedPasswordPolicy -Name 'PSO - Old'
    .LINK
        https://jm2k69.github.io/PSGPOTools/en/reference/commands/remove-psgpofinegrainedpasswordpolicy/
    .LINK
        Set-PSGPOFineGrainedPasswordPolicy
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, Position = 0)] [string[]]$Name,
        [string]$Server,
        [pscredential]$Credential,
        [switch]$UseSsl
    )

    $store = Get-PSGPOPasswordPolicyStore -BoundParameters $PSBoundParameters
    foreach ($policy in @(Find-PSGPOPasswordPolicy -Store $store -Name $Name)) {
        if (-not $PSCmdlet.ShouldProcess("password settings object '$($policy.Name)' of $($store.DomainName)", 'Delete it')) { continue }
        try {
            $store.RemovePolicy($policy)
        } catch {
            Write-Error "The password settings object '$($policy.Name)' is not deleted: $($_.Exception.GetBaseException().Message)"
        }
    }
}
