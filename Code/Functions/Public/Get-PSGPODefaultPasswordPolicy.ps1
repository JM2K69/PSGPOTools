function Get-PSGPODefaultPasswordPolicy {
    <#
    .SYNOPSIS
        The password policy of the domain: what applies to the accounts no PSO applies to.
    .DESCRIPTION
        The password and lockout settings of the domain object (minPwdLength, pwdHistoryLength,
        pwdProperties, minPwdAge, maxPwdAge, lockoutThreshold, lockoutDuration,
        lockOutObservationWindow), which the Default Domain Policy GPO sets. A fine-grained password
        policy (Get-PSGPOFineGrainedPasswordPolicy) replaces them for the users it applies to.

        A MaxPasswordAge of zero means that the passwords never expire, a LockoutDuration of zero
        that a locked out account stays locked until an administrator unlocks it.
    .PARAMETER Server
        Domain controller to read the domain from: its DNS name. By default, the domain of the
        computer (see Get-PSGPODirectory).
    .PARAMETER Credential
        Account to read the domain with, instead of the current identity (Kerberos).
    .PARAMETER UseSsl
        LDAPS (port 636): the certificate of the server must be trusted by the system.
    .EXAMPLE
        Get-PSGPODefaultPasswordPolicy
    .OUTPUTS
        PSGPOTools.DefaultPasswordPolicy
    .LINK
        https://jm2k69.github.io/PSGPOTools/en/reference/commands/get-psgpodefaultpasswordpolicy/
    .LINK
        Get-PSGPOFineGrainedPasswordPolicy
    #>
    [CmdletBinding()]
    [OutputType('PSGPOTools.DefaultPasswordPolicy')]
    param(
        [string]$Server,
        [pscredential]$Credential,
        [switch]$UseSsl
    )

    $store = Get-PSGPOPasswordPolicyStore -BoundParameters $PSBoundParameters
    ConvertTo-PSGPOPasswordPolicyOutput -Policy $store.DomainPolicy -Store $store
}
