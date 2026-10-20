function Get-PSGPOResultantPasswordPolicy {
    <#
    .SYNOPSIS
        Which fine-grained password policy (PSO) applies to a user, and why.
    .DESCRIPTION
        As "View resultant password settings" of the Active Directory Administrative Center, with
        the reasons: every PSO that concerns the user or the group, applied directly or through
        which groups (nested ones included), by order of priority, and the one that applies.

        The PSOs applied directly to a user win over those of its groups; of several, the lowest
        precedence wins, then the smallest objectGUID; without any, the password policy of the
        domain applies. A PSO reaches the members of a group through global security groups on
        Windows domain controllers, through every security group but the built-in ones on Samba AD.
        For a user, the domain controller tells which PSO it applies (msDS-ResultantPSO): its answer
        is AppliedPolicy, and Differs says when it is not the one this computation finds. For a
        group: the PSO its members get through it, when no closer PSO applies to them.

        The Status of each PSO: Applied, LowerPriority (another one comes first), DirectWins (a PSO
        applied directly to the user wins over those of its groups) or GroupIgnored (it is applied
        through a group that passes no PSO on).
    .PARAMETER Identity
        User or group: account name (DOMAIN\name too), name or distinguished name.
    .PARAMETER Server
        Domain controller to read the domain from: its DNS name. By default, the domain of the
        computer (see Get-PSGPODirectory).
    .PARAMETER Credential
        Account to read the domain with, instead of the current identity (Kerberos).
    .PARAMETER UseSsl
        LDAPS (port 636): the certificate of the server must be trusted by the system.
    .EXAMPLE
        Get-PSGPOResultantPasswordPolicy -Identity tiers1
    .EXAMPLE
        (Get-PSGPOResultantPasswordPolicy -Identity tiers1).Candidates | Format-Table Order, Name, Precedence, AppliesThrough, Status, Reason
    .OUTPUTS
        PSGPOTools.ResultantPasswordPolicy
    .LINK
        https://jm2k69.github.io/PSGPOTools/en/reference/commands/get-psgporesultantpasswordpolicy/
    .LINK
        Get-PSGPOFineGrainedPasswordPolicy
    .LINK
        Show-PSOManagerAvalonia
    #>
    [CmdletBinding()]
    [OutputType('PSGPOTools.ResultantPasswordPolicy')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)] [string[]]$Identity,
        [string]$Server,
        [pscredential]$Credential,
        [switch]$UseSsl
    )

    begin {
        $store = Get-PSGPOPasswordPolicyStore -BoundParameters $PSBoundParameters
    }
    process {
        foreach ($item in $Identity) {
            try {
                $result = Resolve-PSGPOPasswordPolicy -Store $store -Account $store.ResolveAccount($item)
            } catch {
                Write-Error $_.Exception.GetBaseException().Message
                continue
            }
            # Policy objects of the module stay inside: the settings as the commands give them.
            $result.Settings = if ($result.Settings) { ConvertTo-PSGPOPasswordPolicyOutput -Policy $result.Settings -Store $store }
            foreach ($candidate in $result.Candidates) { $candidate.PSObject.Properties.Remove('Policy') }
            $result
        }
    }
}
