<#
    What Show-PSOManagerAvalonia shows of the fine-grained password policies, in the language of
    the interface: the settings of a PSO, its line in the list, the users and groups, and the rows
    of the Resultant Password Settings view. Kept free of any Avalonia type (the rows are the
    classes of AvaloniaModels.ps1) so that it can be tested without a UI.
#>

# A number of days or minutes of a duration ("1.5", "42").
function Format-PSGPOPasswordPolicyNumber {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [double]$Value)

    [Math]::Round($Value, 2).ToString('0.##', [cultureinfo]::InvariantCulture)
}

# A number of days or of minutes, singular or plural.
function Format-PSGPOPasswordPolicyDuration {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [TimeSpan]$Value, [switch]$Minutes)

    $number = if ($Minutes) { $Value.TotalMinutes } else { $Value.TotalDays }
    $text = Format-PSGPOPasswordPolicyNumber $number
    if ($Minutes) { if ($text -eq '1') { Get-PSGPOText '{0} minute' $text } else { Get-PSGPOText '{0} minutes' $text } }
    elseif ($text -eq '1') { Get-PSGPOText '{0} day' $text } else { Get-PSGPOText '{0} days' $text }
}

# The settings of a PSO, or of the password policy of the domain: Key and Value rows.
function Get-PSGPOPasswordPolicySettingRow {
    [CmdletBinding()]
    [OutputType([AvaloniaRegistryRow])]
    param([Parameter(Mandatory)] [GPOToolsPasswordPolicy]$Policy)

    $row = { param($Key, $Value) $item = [AvaloniaRegistryRow]::new(); $item.Key = $Key; $item.Value = $Value; $item }
    $yesNo = { param($Value) if ($Value) { Get-PSGPOText 'Yes' } else { Get-PSGPOText 'No' } }
    if (-not $Policy.IsDefault) { & $row (Get-PSGPOText 'Precedence') "$($Policy.Precedence)" }
    & $row (Get-PSGPOText 'Minimum password length') $(if ($Policy.MinPasswordLength) { Get-PSGPOText '{0} characters' $Policy.MinPasswordLength } else { Get-PSGPOText 'Not enforced' })
    & $row (Get-PSGPOText 'Password history') $(if ($Policy.PasswordHistoryCount) { Get-PSGPOText '{0} passwords remembered' $Policy.PasswordHistoryCount } else { Get-PSGPOText 'Not enforced' })
    & $row (Get-PSGPOText 'Password must meet complexity requirements') (& $yesNo $Policy.ComplexityEnabled)
    & $row (Get-PSGPOText 'Store password using reversible encryption') (& $yesNo $Policy.ReversibleEncryptionEnabled)
    & $row (Get-PSGPOText 'Minimum password age') $(if ($Policy.MinPasswordAge -gt [TimeSpan]::Zero) { Format-PSGPOPasswordPolicyDuration $Policy.MinPasswordAge } else { Get-PSGPOText 'Not enforced' })
    & $row (Get-PSGPOText 'Maximum password age') $(if ($Policy.MaxPasswordAge -gt [TimeSpan]::Zero) { Format-PSGPOPasswordPolicyDuration $Policy.MaxPasswordAge } else { Get-PSGPOText 'The password never expires' })
    if ($Policy.LockoutThreshold) {
        & $row (Get-PSGPOText 'Account lockout') (Get-PSGPOText 'After {0} failed logon attempts' $Policy.LockoutThreshold)
        & $row (Get-PSGPOText 'Reset failed logon attempts count after') (Format-PSGPOPasswordPolicyDuration $Policy.LockoutObservationWindow -Minutes)
        & $row (Get-PSGPOText 'Account will be locked out') $(if ($Policy.LockoutDuration -gt [TimeSpan]::Zero) { Get-PSGPOText 'For {0}' (Format-PSGPOPasswordPolicyDuration $Policy.LockoutDuration -Minutes) } else { Get-PSGPOText 'Until an administrator manually unlocks the account' })
    } else {
        & $row (Get-PSGPOText 'Account lockout') (Get-PSGPOText 'Not enforced')
    }
    if (-not $Policy.IsDefault) {
        & $row (Get-PSGPOText 'Protect from accidental deletion') (& $yesNo $Policy.ProtectedFromAccidentalDeletion)
        if ($Policy.Modified) { & $row (Get-PSGPOText 'Modified') ([datetime]$Policy.Modified).ToLocalTime().ToString('g', [cultureinfo]::CurrentCulture) }
    }
}

# The settings of a PSO in one line: length, history, maximum age, lockout.
function Get-PSGPOPasswordPolicySummary {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [GPOToolsPasswordPolicy]$Policy)

    @(
        if ($Policy.MinPasswordLength) { Get-PSGPOText '{0} characters' $Policy.MinPasswordLength } else { Get-PSGPOText 'no minimum length' }
        Get-PSGPOText 'history {0}' $Policy.PasswordHistoryCount
        if ($Policy.MaxPasswordAge -gt [TimeSpan]::Zero) { Get-PSGPOText 'expires after {0} days' (Format-PSGPOPasswordPolicyNumber $Policy.MaxPasswordAge.TotalDays) } else { Get-PSGPOText 'never expires' }
        if ($Policy.LockoutThreshold) { Get-PSGPOText 'locked out after {0} attempts' $Policy.LockoutThreshold } else { Get-PSGPOText 'no lockout' }
    ) -join ', '
}

# A PSO in the list of the Password Settings view.
function ConvertTo-PSGPOPasswordPolicyRow {
    [CmdletBinding()]
    [OutputType([AvaloniaPasswordPolicyRow])]
    param([Parameter(Mandatory)] [GPOToolsPasswordPolicy]$Policy)

    $row = [AvaloniaPasswordPolicyRow]::new()
    $row.Precedence = "$($Policy.Precedence)"
    $row.Name = $Policy.Name
    $row.Description = $Policy.Description
    $row.Summary = Get-PSGPOPasswordPolicySummary -Policy $Policy
    $row.AppliesTo = "$($Policy.AppliesTo.Count)"
    $row.IsProtected = $Policy.ProtectedFromAccidentalDeletion
    $row.Policy = $Policy
    $row
}

# What an account is: a user, or the scope and kind of a group.
function Get-PSGPOPasswordAccountKindText {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [GPOToolsPasswordAccount]$Account)

    if ($Account.Kind -ne 'Group') { return Get-PSGPOText 'User' }
    if ($Account.IsBuiltin) { return Get-PSGPOText 'Built-in local group' }
    if ($Account.IsSecurityGroup) {
        Get-PSGPOText $(switch ($Account.GroupScope) { 'Global' { 'Global security group' } 'Universal' { 'Universal security group' } default { 'Domain local security group' } })
    } else {
        Get-PSGPOText $(switch ($Account.GroupScope) { 'Global' { 'Global distribution group' } 'Universal' { 'Universal distribution group' } default { 'Domain local distribution group' } })
    }
}

# A user or a group in a list; a subject the domain does not have anymore keeps its name only.
function ConvertTo-PSGPOPasswordAccountRow {
    [CmdletBinding()]
    [OutputType([AvaloniaPasswordAccountRow])]
    param(
        [GPOToolsPasswordAccount]$Account,
        # A subject of a PSO not found in the domain
        [string]$DistinguishedName
    )

    $row = [AvaloniaPasswordAccountRow]::new()
    if ($Account) {
        $row.Name = $Account.Name
        $row.Kind = Get-PSGPOPasswordAccountKindText -Account $Account
        $row.IconData = Get-PSGPOIconData -Name $(if ($Account.Kind -eq 'Group') { 'people' } else { 'person' })
        $row.DistinguishedName = $Account.DistinguishedName
        $row.Account = $Account
    } else {
        $row.Name = (($DistinguishedName -split '(?<!\\),')[0] -replace '^(?i)CN=', '') -replace '\\(.)', '$1'
        $row.Kind = Get-PSGPOText 'Not found in the domain'
        $row.IconData = Get-PSGPOIconData -Name 'info'
        $row.DistinguishedName = $DistinguishedName
    }
    $row
}

# A PSO that concerns an account (Resolve-PSGPOPasswordPolicy), in the Resultant Password
# Settings view: how it reaches the account, whether it applies, and why.
function ConvertTo-PSGPOPasswordCandidateRow {
    [CmdletBinding()]
    [OutputType([AvaloniaPasswordCandidateRow])]
    param(
        [Parameter(Mandatory)] $Candidate,
        [Parameter(Mandatory)] $Result,
        [Parameter(Mandatory)] [GPOToolsPasswordPolicyStore]$Store
    )

    $isDomain = $Candidate.Policy.IsDefault
    $row = [AvaloniaPasswordCandidateRow]::new()
    $row.Order = "$($Candidate.Order)"
    $row.Name = if ($isDomain) { Get-PSGPOText 'Default domain password policy' } else { $Candidate.Name }
    $row.Precedence = if ($isDomain) { '' } else { Get-PSGPOText 'Precedence {0}' $Candidate.Precedence }
    $row.Through = if ($isDomain) { Get-PSGPOText 'Password policy of the domain' } else {
        @(foreach ($way in $Candidate.AppliesThrough) { if ($way -eq 'Direct') { Get-PSGPOText 'Directly applied' } else { Get-PSGPOText 'Through {0}' $way } }) -join '; '
    }
    $row.IsApplied = $Candidate.Status -eq 'Applied'
    $row.Status = Get-PSGPOText $(switch ($Candidate.Status) { 'Applied' { 'Applies' } 'GroupIgnored' { 'Ignored' } default { 'Not applied' } })
    $row.StatusBrush = switch ($Candidate.Status) { 'Applied' { '#107C10' } 'GroupIgnored' { '#CA5010' } default { '#8A8886' } }
    $row.Reason = switch ($Candidate.Status) {
        'Applied' {
            if ($isDomain) { Get-PSGPOText 'Applies: no password settings object applies to the account.' }
            elseif ($Result.Kind -eq 'Group') { Get-PSGPOText 'Applies to the members of the group that no closer password settings object concerns.' }
            else { Get-PSGPOText 'Applies.' }
        }
        'DirectWins' { Get-PSGPOText 'Not applied: a password settings object applies directly to the account, which wins over those of its groups.' }
        'GroupIgnored' {
            $groups = @($Candidate.IgnoredGroups) -join ', '
            if ($Store.GroupRule -eq 'Security') { Get-PSGPOText 'Not applied: {0} passes no password settings on. With Samba AD, only the security groups that are not built-in do.' $groups }
            else { Get-PSGPOText 'Not applied: {0} passes no password settings on. Only global security groups do.' $groups }
        }
        default {
            if ($isDomain) { Get-PSGPOText 'Not applied: {0} applies.' $Result.AppliedPolicy }
            else { Get-PSGPOText 'Not applied: {0} comes first (a lower precedence, or the same one and a smaller GUID).' $Result.AppliedPolicy }
        }
    }
    $row
}
