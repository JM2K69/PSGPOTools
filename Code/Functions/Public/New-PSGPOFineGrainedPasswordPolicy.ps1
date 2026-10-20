function New-PSGPOFineGrainedPasswordPolicy {
    <#
    .SYNOPSIS
        Creates a fine-grained password policy (PSO) in the domain.
    .DESCRIPTION
        As "New > Password Settings" of the Active Directory Administrative Center: a
        msDS-PasswordSettings object in the Password Settings Container, with its precedence, its
        password and lockout settings, and the users and groups it directly applies to. The settings
        not given are those of a new PSO in the Administrative Center: 7 characters, 24 passwords
        remembered, complexity, 1 day minimum and 42 days maximum age, no lockout (30 minutes when a
        threshold is given), protected from accidental deletion.

        A PSO applies to the users it names, and to the members of the groups it names: on Windows
        domain controllers through the global security groups only, on Samba AD through every
        security group but the built-in ones. Of several PSOs, the lowest precedence wins; one
        applied directly to a user wins over those of its groups (Get-PSGPOResultantPasswordPolicy).
    .PARAMETER Name
        Name of the PSO, unique in the domain.
    .PARAMETER Precedence
        Priority of the PSO: of the PSOs that concern a user, the lowest precedence applies (1 or more).
    .PARAMETER MinPasswordLength
        Minimum length of the passwords, in characters (0 to 255).
    .PARAMETER PasswordHistoryCount
        Number of passwords remembered, that a new password cannot repeat (0 to 1024).
    .PARAMETER ComplexityEnabled
        The passwords must meet the complexity requirements.
    .PARAMETER ReversibleEncryptionEnabled
        Stores the passwords with a reversible encryption (to be avoided).
    .PARAMETER MinPasswordAge
        Time before a password can be changed again (0 for none).
    .PARAMETER MaxPasswordAge
        Time after which a password must be changed; zero: the passwords never expire.
    .PARAMETER LockoutThreshold
        Number of failed logon attempts that lock the account out; 0: never locked out.
    .PARAMETER LockoutDuration
        Time an account stays locked out; zero: until an administrator unlocks it.
    .PARAMETER LockoutObservationWindow
        Time after which the count of failed logon attempts is reset (no longer than LockoutDuration).
    .PARAMETER Description
        What the PSO is for.
    .PARAMETER ProtectedFromAccidentalDeletion
        Denies everyone to delete the PSO, as the Administrative Center does ($true by default).
    .PARAMETER AppliesTo
        Users and groups the PSO applies to: account names (DOMAIN\name too), names or distinguished names.
    .PARAMETER Server
        Domain controller to write to: its DNS name. By default, the domain of the computer.
    .PARAMETER Credential
        Account to write with, instead of the current identity (Kerberos).
    .PARAMETER UseSsl
        LDAPS (port 636): the certificate of the server must be trusted by the system.
    .EXAMPLE
        New-PSGPOFineGrainedPasswordPolicy -Name 'PSO - Tier 1 Admins' -Precedence 20 -MinPasswordLength 16 -MaxPasswordAge 180.00:00:00 -LockoutThreshold 10 -AppliesTo 'GPO-Tier1-Admins'
    .EXAMPLE
        # Service accounts: long passwords that never expire, never locked out
        New-PSGPOFineGrainedPasswordPolicy -Name 'PSO - Service Accounts' -Precedence 40 -MinPasswordLength 30 -MinPasswordAge 0 -MaxPasswordAge 0 -AppliesTo 'SVC-Accounts'
    .OUTPUTS
        PSGPOTools.FineGrainedPasswordPolicy
    .LINK
        https://jm2k69.github.io/PSGPOTools/en/reference/commands/new-psgpofinegrainedpasswordpolicy/
    .LINK
        Set-PSGPOFineGrainedPasswordPolicy
    .LINK
        Add-PSGPOFineGrainedPasswordPolicySubject
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('PSGPOTools.FineGrainedPasswordPolicy')]
    param(
        [Parameter(Mandatory, Position = 0)] [string]$Name,
        [Parameter(Mandatory)] [ValidateRange(1, [int]::MaxValue)] [int]$Precedence,
        [int]$MinPasswordLength,
        [int]$PasswordHistoryCount,
        [bool]$ComplexityEnabled,
        [bool]$ReversibleEncryptionEnabled,
        [TimeSpan]$MinPasswordAge,
        [TimeSpan]$MaxPasswordAge,
        [int]$LockoutThreshold,
        [TimeSpan]$LockoutDuration,
        [TimeSpan]$LockoutObservationWindow,
        [string]$Description,
        [bool]$ProtectedFromAccidentalDeletion = $true,
        [string[]]$AppliesTo,
        [string]$Server,
        [pscredential]$Credential,
        [switch]$UseSsl
    )

    $store = Get-PSGPOPasswordPolicyStore -BoundParameters $PSBoundParameters
    $policy = [GPOToolsPasswordPolicy]::NewDefault()
    $policy.Name = $Name
    $values = @{} + $PSBoundParameters
    $values.ProtectedFromAccidentalDeletion = $ProtectedFromAccidentalDeletion
    Set-PSGPOPasswordPolicySetting -Policy $policy -BoundParameters $values
    foreach ($subject in @($AppliesTo | Where-Object { $_ })) { $policy.AppliesTo.Add($store.ResolveAccount($subject).DistinguishedName) }
    if (-not $PSCmdlet.ShouldProcess("password settings object '$Name' of $($store.DomainName)", 'Create it')) { return }
    $new = $store.NewPolicy($policy)
    ConvertTo-PSGPOPasswordPolicyOutput -Policy $new -Store $store
}
