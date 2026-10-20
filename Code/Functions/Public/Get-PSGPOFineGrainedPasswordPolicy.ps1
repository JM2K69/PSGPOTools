function Get-PSGPOFineGrainedPasswordPolicy {
    <#
    .SYNOPSIS
        The fine-grained password policies (password settings objects, PSO) of the domain.
    .DESCRIPTION
        As the Password Settings Container of the Active Directory Administrative Center: the
        msDS-PasswordSettings objects of CN=Password Settings Container,CN=System of the domain,
        by order of priority (the lowest precedence first), with their settings and the users and
        groups each one directly applies to. Windows and Samba AD (4.9 and later) domains, read
        over LDAP from Windows or Linux.

        By default, only the administrators of the domain read the PSOs: another account gets none.
        A MaxPasswordAge of zero means that the passwords never expire, a LockoutDuration of zero
        that a locked out account stays locked until an administrator unlocks it.
    .PARAMETER Name
        Names of the PSOs (* and ? make a pattern); all of them by default.
    .PARAMETER Server
        Domain controller to read the domain from: its DNS name. By default, the domain of the
        computer (see Get-PSGPODirectory).
    .PARAMETER Credential
        Account to read the domain with, instead of the current identity (Kerberos).
    .PARAMETER UseSsl
        LDAPS (port 636): the certificate of the server must be trusted by the system.
    .EXAMPLE
        Get-PSGPOFineGrainedPasswordPolicy | Format-Table Name, Precedence, MinPasswordLength, MaxPasswordAge, AppliesTo
    .EXAMPLE
        # Linux, Samba AD: Kerberos ticket first
        kinit administrator@HARDENBOX.LABO
        Get-PSGPOFineGrainedPasswordPolicy -Server dc.hardenbox.labo -Name 'PSO - Tier*'
    .OUTPUTS
        PSGPOTools.FineGrainedPasswordPolicy
    .LINK
        https://jm2k69.github.io/PSGPOTools/en/reference/commands/get-psgpofinegrainedpasswordpolicy/
    .LINK
        Get-PSGPOResultantPasswordPolicy
    .LINK
        Show-PSOManagerAvalonia
    #>
    [CmdletBinding()]
    [OutputType('PSGPOTools.FineGrainedPasswordPolicy')]
    param(
        [Parameter(Position = 0)]
        [string[]]$Name = '*',
        [string]$Server,
        [pscredential]$Credential,
        [switch]$UseSsl
    )

    $store = Get-PSGPOPasswordPolicyStore -BoundParameters $PSBoundParameters
    foreach ($policy in $store.Policies) {
        if (-not @($Name | Where-Object { Test-PSGPONameMatch -Name $policy.Name -Pattern $_ }).Count) { continue }
        ConvertTo-PSGPOPasswordPolicyOutput -Policy $policy -Store $store
    }
}
