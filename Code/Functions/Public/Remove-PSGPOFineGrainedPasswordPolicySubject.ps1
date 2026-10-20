function Remove-PSGPOFineGrainedPasswordPolicySubject {
    <#
    .SYNOPSIS
        Stops applying fine-grained password policies (PSO) to users and groups.
    .DESCRIPTION
        Removes the users and groups from the "Directly Applies To" list of the PSO
        (msDS-PSOAppliesTo). They then get the next PSO that concerns them, or the password policy
        of the domain.
    .PARAMETER Name
        Names of the PSOs (* and ? make a pattern).
    .PARAMETER Subject
        Users and groups: account names (DOMAIN\name too), names or distinguished names.
    .PARAMETER Server
        Domain controller to write to: its DNS name. By default, the domain of the computer.
    .PARAMETER Credential
        Account to write with, instead of the current identity (Kerberos).
    .PARAMETER UseSsl
        LDAPS (port 636): the certificate of the server must be trusted by the system.
    .EXAMPLE
        Remove-PSGPOFineGrainedPasswordPolicySubject -Name 'PSO - Tier 1 Admins' -Subject 'tiers1'
    .OUTPUTS
        PSGPOTools.FineGrainedPasswordPolicy
    .LINK
        https://jm2k69.github.io/PSGPOTools/en/reference/commands/remove-psgpofinegrainedpasswordpolicysubject/
    .LINK
        Add-PSGPOFineGrainedPasswordPolicySubject
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('PSGPOTools.FineGrainedPasswordPolicy')]
    param(
        [Parameter(Mandatory, Position = 0)] [string[]]$Name,
        [Parameter(Mandatory, Position = 1)] [string[]]$Subject,
        [string]$Server,
        [pscredential]$Credential,
        [switch]$UseSsl
    )

    $store = Get-PSGPOPasswordPolicyStore -BoundParameters $PSBoundParameters
    $accounts = @(foreach ($item in $Subject) { $store.ResolveAccount($item) })
    foreach ($policy in @(Find-PSGPOPasswordPolicy -Store $store -Name $Name)) {
        foreach ($account in $accounts) {
            if (-not $PSCmdlet.ShouldProcess("password settings object '$($policy.Name)' of $($store.DomainName)", "Stop applying it to $($account.Name)")) { continue }
            try {
                $store.RemoveSubject($policy, $account.DistinguishedName)
            } catch {
                Write-Error "The password settings object '$($policy.Name)' still applies to $($account.Name): $($_.Exception.GetBaseException().Message)"
            }
        }
        ConvertTo-PSGPOPasswordPolicyOutput -Policy $policy -Store $store
    }
}
