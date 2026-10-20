function Add-PSGPOFineGrainedPasswordPolicySubject {
    <#
    .SYNOPSIS
        Applies fine-grained password policies (PSO) to users and groups.
    .DESCRIPTION
        Adds the users and groups to the "Directly Applies To" list of the PSO (msDS-PSOAppliesTo),
        as the Active Directory Administrative Center does. A PSO applied to a group reaches its
        members: on Windows domain controllers through global security groups only, on Samba AD
        through every security group but the built-in ones. Get-PSGPOResultantPasswordPolicy tells
        which PSO applies to a user.
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
        Add-PSGPOFineGrainedPasswordPolicySubject -Name 'PSO - Tier 1 Admins' -Subject 'GPO-Tier1-Admins', 'tiers1'
    .OUTPUTS
        PSGPOTools.FineGrainedPasswordPolicy
    .LINK
        https://jm2k69.github.io/PSGPOTools/en/reference/commands/add-psgpofinegrainedpasswordpolicysubject/
    .LINK
        Remove-PSGPOFineGrainedPasswordPolicySubject
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
            if (-not $PSCmdlet.ShouldProcess("password settings object '$($policy.Name)' of $($store.DomainName)", "Apply it to $($account.Name)")) { continue }
            try {
                $store.AddSubject($policy, $account)
            } catch {
                Write-Error "The password settings object '$($policy.Name)' is not applied to $($account.Name): $($_.Exception.GetBaseException().Message)"
            }
        }
        ConvertTo-PSGPOPasswordPolicyOutput -Policy $policy -Store $store
    }
}
