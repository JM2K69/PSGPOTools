function Set-PSGPOFineGrainedPasswordPolicy {
    <#
    .SYNOPSIS
        Changes the settings, the name or the protection of fine-grained password policies (PSO).
    .DESCRIPTION
        As the properties of a PSO in the Active Directory Administrative Center: only the settings
        given change. A value is changed only if the domain still has the one read: a PSO another
        console changed meanwhile is refused (run the command again). The users and groups it
        applies to change with Add- and Remove-PSGPOFineGrainedPasswordPolicySubject.
    .PARAMETER Name
        Names of the PSOs (* and ? make a pattern).
    .PARAMETER NewName
        New name of the PSO (one PSO only).
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
        Denies everyone to delete the PSO; $false lets it be deleted.
    .PARAMETER Server
        Domain controller to write to: its DNS name. By default, the domain of the computer.
    .PARAMETER Credential
        Account to write with, instead of the current identity (Kerberos).
    .PARAMETER UseSsl
        LDAPS (port 636): the certificate of the server must be trusted by the system.
    .EXAMPLE
        Set-PSGPOFineGrainedPasswordPolicy -Name 'PSO - Tier 1 Admins' -MinPasswordLength 18 -LockoutDuration 0
    .EXAMPLE
        Set-PSGPOFineGrainedPasswordPolicy -Name 'PSO - Old' -ProtectedFromAccidentalDeletion $false
        Remove-PSGPOFineGrainedPasswordPolicy -Name 'PSO - Old'
    .OUTPUTS
        PSGPOTools.FineGrainedPasswordPolicy
    .LINK
        https://jm2k69.github.io/PSGPOTools/en/reference/commands/set-psgpofinegrainedpasswordpolicy/
    .LINK
        Get-PSGPOFineGrainedPasswordPolicy
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('PSGPOTools.FineGrainedPasswordPolicy')]
    param(
        [Parameter(Mandatory, Position = 0)] [string[]]$Name,
        [string]$NewName,
        [ValidateRange(1, [int]::MaxValue)] [int]$Precedence,
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
        [bool]$ProtectedFromAccidentalDeletion,
        [string]$Server,
        [pscredential]$Credential,
        [switch]$UseSsl
    )

    $store = Get-PSGPOPasswordPolicyStore -BoundParameters $PSBoundParameters
    $policies = @(Find-PSGPOPasswordPolicy -Store $store -Name $Name)
    if ($NewName -and $policies.Count -gt 1) { throw "-NewName renames one password settings object, not $($policies.Count)." }
    foreach ($policy in $policies) {
        $changed = $policy.Clone()
        if ($NewName) { $changed.Name = $NewName }
        Set-PSGPOPasswordPolicySetting -Policy $changed -BoundParameters $PSBoundParameters
        if (-not $PSCmdlet.ShouldProcess("password settings object '$($policy.Name)' of $($store.DomainName)", 'Change it')) { continue }
        try {
            $null = $store.SetPolicy($policy, $changed)
            ConvertTo-PSGPOPasswordPolicyOutput -Policy $policy -Store $store
        } catch {
            Write-Error "The password settings object '$($policy.Name)' is not changed: $($_.Exception.GetBaseException().Message)"
        }
    }
}
