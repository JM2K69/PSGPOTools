<#
    Fine-grained password policies (GPOToolsPasswordPolicyStore) read and written over LDAP, the
    same way on a Windows or a Samba domain controller: the msDS-PasswordSettings objects of the
    Password Settings Container, the password policy of the domain (its domain object), the users
    and groups they apply to, and the PSO that applies to an account.

    Durations are stored as negative numbers of 100-nanosecond intervals; -9223372036854775808
    means "never" (a password that does not expire, a lockout until an administrator unlocks
    the account), as the Active Directory Administrative Center writes it.

    Which PSO applies to a user ([MS-ADTS] 3.1.1.4.5.36, msDS-ResultantPSO): the PSOs applied
    directly to the user first; without one, the PSOs applied to its groups, nested ones included.
    Of several, the lowest precedence wins, then the smallest objectGUID. Without any, the password
    policy of the domain applies. Which groups count differs: the global security groups for
    Windows ("account groups" of [MS-DRSR] 4.1.8.1.3), every security group but the built-in
    ones for Samba AD (get_group_sids, ACCOUNT_GROUPS).
#>

$script:PSGPOPasswordPolicyAttributes = @(
    'msDS-PasswordSettingsPrecedence', 'msDS-MinimumPasswordLength', 'msDS-PasswordHistoryLength', 'msDS-PasswordComplexityEnabled',
    'msDS-PasswordReversibleEncryptionEnabled', 'msDS-MinimumPasswordAge', 'msDS-MaximumPasswordAge', 'msDS-LockoutThreshold',
    'msDS-LockoutDuration', 'msDS-LockoutObservationWindow', 'description', 'msDS-PSOAppliesTo')

# Everyone, and the rights "Delete" and "Delete subtree" an accidental deletion needs.
$script:PSGPOEveryoneSid = 'S-1-1-0'
$script:PSGPODeleteMask = [uint32]0x00010040
$script:PSGPODeleteChildMask = [uint32]0x00000002

# A value of a distinguished name (RFC 4514): CN=<value>.
function ConvertTo-PSGPODistinguishedNameValue {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [AllowEmptyString()] [string]$Value)

    $escaped = $Value -replace '([,\\+<>;"=])', '\$1'
    if ($escaped.StartsWith('#') -or $escaped.StartsWith(' ')) { $escaped = '\' + $escaped }
    if ($escaped.EndsWith(' ') -and -not $escaped.EndsWith('\ ')) { $escaped = $escaped.Substring(0, $escaped.Length - 1) + '\ ' }
    $escaped
}

# A duration of the directory as a TimeSpan; "never" is TimeSpan.Zero.
function ConvertFrom-PSGPODirectoryInterval {
    [CmdletBinding()]
    [OutputType([TimeSpan])]
    param([AllowNull()] [AllowEmptyString()] [string]$Value)

    $ticks = [long]0
    if (-not [long]::TryParse("$Value", [System.Globalization.NumberStyles]::Integer, [cultureinfo]::InvariantCulture, [ref]$ticks) -or $ticks -eq [long]::MinValue) {
        return [TimeSpan]::Zero
    }
    [TimeSpan]::FromTicks([Math]::Abs($ticks))
}

# The value of the directory of a duration; with -ZeroIsNever, TimeSpan.Zero is "never".
function ConvertTo-PSGPODirectoryInterval {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [TimeSpan]$Value, [switch]$ZeroIsNever)

    if ($ZeroIsNever -and $Value -eq [TimeSpan]::Zero) { return ([long]::MinValue).ToString([cultureinfo]::InvariantCulture) }
    (-$Value.Ticks).ToString([cultureinfo]::InvariantCulture)
}

# The values the directory stores for a PSO, by attribute (msDS-PSOAppliesTo: a string array).
function Get-PSGPOPasswordPolicyValue {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter(Mandatory)] [GPOToolsPasswordPolicy]$Policy)

    $invariant = [cultureinfo]::InvariantCulture
    @{
        'msDS-PasswordSettingsPrecedence' = $Policy.Precedence.ToString($invariant)
        'msDS-MinimumPasswordLength' = $Policy.MinPasswordLength.ToString($invariant)
        'msDS-PasswordHistoryLength' = $Policy.PasswordHistoryCount.ToString($invariant)
        'msDS-PasswordComplexityEnabled' = if ($Policy.ComplexityEnabled) { 'TRUE' } else { 'FALSE' }
        'msDS-PasswordReversibleEncryptionEnabled' = if ($Policy.ReversibleEncryptionEnabled) { 'TRUE' } else { 'FALSE' }
        'msDS-MinimumPasswordAge' = ConvertTo-PSGPODirectoryInterval -Value $Policy.MinPasswordAge
        'msDS-MaximumPasswordAge' = ConvertTo-PSGPODirectoryInterval -Value $Policy.MaxPasswordAge -ZeroIsNever
        'msDS-LockoutThreshold' = $Policy.LockoutThreshold.ToString($invariant)
        'msDS-LockoutDuration' = ConvertTo-PSGPODirectoryInterval -Value $Policy.LockoutDuration -ZeroIsNever
        'msDS-LockoutObservationWindow' = ConvertTo-PSGPODirectoryInterval -Value $Policy.LockoutObservationWindow
        'description' = "$($Policy.Description)"
        'msDS-PSOAppliesTo' = [string[]]@($Policy.AppliesTo)
    }
}

# What is wrong with the settings of a PSO, as the domain controllers and the Active Directory
# Administrative Center check them; nothing when they can be saved. -Localized: in the language
# of the interface.
function Test-PSGPOPasswordPolicy {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [GPOToolsPasswordPolicy]$Policy,
        [switch]$Localized
    )

    $T = if ($Localized) { ${function:Get-PSGPOText} } else { { param($Text, [Parameter(ValueFromRemainingArguments)] $Argument) if ($Argument.Count) { $Text -f $Argument } else { $Text } } }
    if ([string]::IsNullOrWhiteSpace($Policy.Name)) { & $T 'The name is required.' }
    elseif ($Policy.Name.Length -gt 64) { & $T 'The name has 64 characters at most.' }
    if ($Policy.Precedence -lt 1) { & $T 'The precedence is a number of 1 or more.' }
    if ($Policy.MinPasswordLength -lt 0 -or $Policy.MinPasswordLength -gt 255) { & $T 'The minimum password length is between 0 and 255 characters.' }
    if ($Policy.PasswordHistoryCount -lt 0 -or $Policy.PasswordHistoryCount -gt 1024) { & $T 'The password history is between 0 and 1024 passwords.' }
    if ($Policy.LockoutThreshold -lt 0 -or $Policy.LockoutThreshold -gt 65535) { & $T 'The number of failed logon attempts is between 0 and 65535.' }
    foreach ($duration in $Policy.MinPasswordAge, $Policy.MaxPasswordAge, $Policy.LockoutDuration, $Policy.LockoutObservationWindow) {
        if ($duration -lt [TimeSpan]::Zero) { & $T 'A duration cannot be negative.'; break }
    }
    if ($Policy.MaxPasswordAge -ne [TimeSpan]::Zero -and $Policy.MinPasswordAge -ge $Policy.MaxPasswordAge) {
        & $T 'The minimum password age is shorter than the maximum password age.'
    }
    if ($Policy.LockoutThreshold -gt 0 -and $Policy.LockoutObservationWindow -le [TimeSpan]::Zero) {
        & $T 'With a lockout, the failed logon attempts count is reset after one minute or more.'
    }
    if ($Policy.LockoutDuration -ne [TimeSpan]::Zero -and $Policy.LockoutObservationWindow -gt $Policy.LockoutDuration) {
        & $T 'The failed logon attempts count is reset after a time no longer than the lockout duration.'
    }
}

# Text value of an attribute of a binary search entry ($null when absent); -All: every value.
function Get-PSGPOLdapBinaryText {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Entry, [Parameter(Mandatory)] [string]$Name, [switch]$All)

    $values = @($Entry.Values[$Name] | Where-Object { $null -ne $_ } | ForEach-Object { [System.Text.Encoding]::UTF8.GetString([byte[]]$_) })
    # -All: the values one by one; callers collect them with @(...).
    if ($All) { return $values }
    if ($values.Count) { $values[0] }
}

# The password policy of the domain from its domain object (string attributes).
function ConvertTo-PSGPODomainPasswordPolicy {
    [CmdletBinding()]
    [OutputType([GPOToolsPasswordPolicy])]
    param([Parameter(Mandatory)] $Entry)

    $policy = [GPOToolsPasswordPolicy]::new()
    $policy.Name = 'Default domain password policy'
    $policy.DistinguishedName = $Entry.DistinguishedName
    $policy.IsDefault = $true
    $policy.CanEdit = $false
    $properties = [int](Get-PSGPOLdapValue $Entry 'pwdProperties')
    $policy.MinPasswordLength = [int](Get-PSGPOLdapValue $Entry 'minPwdLength')
    $policy.PasswordHistoryCount = [int](Get-PSGPOLdapValue $Entry 'pwdHistoryLength')
    $policy.ComplexityEnabled = ($properties -band 1) -ne 0
    $policy.ReversibleEncryptionEnabled = ($properties -band 16) -ne 0
    $policy.MinPasswordAge = ConvertFrom-PSGPODirectoryInterval (Get-PSGPOLdapValue $Entry 'minPwdAge')
    $policy.MaxPasswordAge = ConvertFrom-PSGPODirectoryInterval (Get-PSGPOLdapValue $Entry 'maxPwdAge')
    $policy.LockoutThreshold = [int](Get-PSGPOLdapValue $Entry 'lockoutThreshold')
    $policy.LockoutDuration = ConvertFrom-PSGPODirectoryInterval (Get-PSGPOLdapValue $Entry 'lockoutDuration')
    $policy.LockoutObservationWindow = ConvertFrom-PSGPODirectoryInterval (Get-PSGPOLdapValue $Entry 'lockOutObservationWindow')
    $policy
}

# A PSO from a binary search entry (Invoke-PSGPOLdapBinarySearch): its settings, its subjects,
# whether the account may change it, and its protection from accidental deletion.
function ConvertTo-PSGPOPasswordPolicy {
    [CmdletBinding()]
    [OutputType([GPOToolsPasswordPolicy])]
    param(
        [Parameter(Mandatory)] $Entry,
        # The entry holds allowedAttributesEffective: an attribute missing means no right.
        [switch]$EffectiveRights
    )

    $text = { param($Name) Get-PSGPOLdapBinaryText -Entry $Entry -Name $Name }
    $policy = [GPOToolsPasswordPolicy]::new()
    $policy.DistinguishedName = $Entry.DistinguishedName
    $policy.Name = & $text 'name'
    if (-not $policy.Name) { $policy.Name = & $text 'cn' }
    $guid = @($Entry.Values['objectGUID'])
    if ($guid.Count -and $guid[0]) { $policy.Id = [guid]::new([byte[]]$guid[0]) }
    $policy.Precedence = [int](& $text 'msDS-PasswordSettingsPrecedence')
    $policy.MinPasswordLength = [int](& $text 'msDS-MinimumPasswordLength')
    $policy.PasswordHistoryCount = [int](& $text 'msDS-PasswordHistoryLength')
    $policy.ComplexityEnabled = (& $text 'msDS-PasswordComplexityEnabled') -eq 'TRUE'
    $policy.ReversibleEncryptionEnabled = (& $text 'msDS-PasswordReversibleEncryptionEnabled') -eq 'TRUE'
    $policy.MinPasswordAge = ConvertFrom-PSGPODirectoryInterval (& $text 'msDS-MinimumPasswordAge')
    $policy.MaxPasswordAge = ConvertFrom-PSGPODirectoryInterval (& $text 'msDS-MaximumPasswordAge')
    $policy.LockoutThreshold = [int](& $text 'msDS-LockoutThreshold')
    $policy.LockoutDuration = ConvertFrom-PSGPODirectoryInterval (& $text 'msDS-LockoutDuration')
    $policy.LockoutObservationWindow = ConvertFrom-PSGPODirectoryInterval (& $text 'msDS-LockoutObservationWindow')
    $policy.Description = & $text 'description'
    $policy.AppliesTo.AddRange([string[]]@(Get-PSGPOLdapBinaryText -Entry $Entry -Name 'msDS-PSOAppliesTo' -All))
    $policy.Modified = ConvertFrom-PSGPOGeneralizedTime (& $text 'whenChanged')
    if ($EffectiveRights) {
        $policy.CanEdit = @(Get-PSGPOLdapBinaryText -Entry $Entry -Name 'allowedAttributesEffective' -All) -contains 'msDS-PasswordSettingsPrecedence'
    }
    $descriptor = @($Entry.Values['nTSecurityDescriptor'])
    if ($descriptor.Count -and $descriptor[0]) {
        $policy.ProtectedFromAccidentalDeletion = Test-PSGPODeletionProtection -Descriptor ([GPOToolsSecurityDescriptor]::Parse([byte[]]$descriptor[0]))
    }
    $values = @{}
    foreach ($name in $script:PSGPOPasswordPolicyAttributes) {
        $values[$name] = if ($name -eq 'msDS-PSOAppliesTo') { [string[]]@($policy.AppliesTo) } else { "$(& $text $name)" }
    }
    $policy.DirectoryValues = $values
    $policy
}

# The object is protected from accidental deletion: an explicit ACE denies Everyone to delete it.
function Test-PSGPODeletionProtection {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)] [GPOToolsSecurityDescriptor]$Descriptor)

    foreach ($ace in @($Descriptor.Dacl)) {
        if ($ace.IsKnown() -and $ace.Type -eq [GPOToolsAce]::AccessDenied -and -not ($ace.Flags -band [GPOToolsAce]::Inherited) -and
            $ace.Sid -eq $script:PSGPOEveryoneSid -and ($ace.Mask -band $script:PSGPODeleteMask) -eq $script:PSGPODeleteMask) { return $true }
    }
    $false
}

# Protects an object of the directory from accidental deletion, or no longer, as the Active
# Directory Administrative Center does: Everyone is denied "Delete" and "Delete subtree" on the
# object, and "Delete all child objects" on its container (without it, who may delete the
# children of the container would still delete it).
function Set-PSGPODomainDeletionProtection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Connection,
        [Parameter(Mandatory)] [string]$DistinguishedName,
        [Parameter(Mandatory)] [bool]$Protected,
        [string]$Name = $DistinguishedName
    )

    $descriptor = Get-PSGPODomainSecurityDescriptor -Connection $Connection -DistinguishedName $DistinguishedName
    if ((Test-PSGPODeletionProtection -Descriptor $descriptor) -eq $Protected) { return }
    $explicit = Get-PSGPOExplicitDescriptor -Descriptor $descriptor
    for ($i = $explicit.Dacl.Count - 1; $i -ge 0; $i--) {
        $ace = $explicit.Dacl[$i]
        if ($ace.IsKnown() -and $ace.Type -eq [GPOToolsAce]::AccessDenied -and $ace.Sid -eq $script:PSGPOEveryoneSid -and ($ace.Mask -band $script:PSGPODeleteMask)) {
            $ace.Mask = $ace.Mask -band -bnot $script:PSGPODeleteMask
            if (-not $ace.Mask) { $explicit.Dacl.RemoveAt($i) }
        }
    }
    if ($Protected) { $explicit.AddAce([GPOToolsAce]::new([GPOToolsAce]::AccessDenied, 0, $script:PSGPODeleteMask, $script:PSGPOEveryoneSid, [guid]::Empty)) }
    Set-PSGPODomainDacl -Connection $Connection -DistinguishedName $DistinguishedName -Descriptor $explicit -Name $Name
    if (-not $Protected) { return }

    $container = [GPOToolsDirectory]::GetParentDistinguishedName($DistinguishedName)
    try {
        $parent = Get-PSGPODomainSecurityDescriptor -Connection $Connection -DistinguishedName $container
        $denied = @($parent.Dacl | Where-Object { $_.IsKnown() -and $_.Type -eq [GPOToolsAce]::AccessDenied -and -not ($_.Flags -band [GPOToolsAce]::Inherited) -and
                $_.Sid -eq $script:PSGPOEveryoneSid -and ($_.Mask -band $script:PSGPODeleteChildMask) }).Count
        if (-not $denied) {
            $parentExplicit = Get-PSGPOExplicitDescriptor -Descriptor $parent
            $parentExplicit.AddAce([GPOToolsAce]::new([GPOToolsAce]::AccessDenied, 0, $script:PSGPODeleteChildMask, $script:PSGPOEveryoneSid, [guid]::Empty))
            Set-PSGPODomainDacl -Connection $Connection -DistinguishedName $container -Descriptor $parentExplicit -Name $container
        }
    } catch {
        Write-Warning "$Name is protected, but its container is not ($($_.Exception.GetBaseException().Message)): who may delete the objects of $container may still delete it."
    }
}

# Reads the PSOs and the password policy of the domain into the store, and whether the account
# may create PSOs.
function Read-PSGPODomainPasswordPolicy {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [GPOToolsLdapPasswordPolicyStore]$Store)

    $connection = New-PSGPODirectoryConnection -Directory $Store.Directory
    try {
        $domain = Invoke-PSGPOLdapSearch -Connection $connection -SearchBase $Store.DomainDistinguishedName -Scope Base `
            -Attribute 'minPwdLength', 'pwdHistoryLength', 'pwdProperties', 'minPwdAge', 'maxPwdAge', 'lockoutThreshold', 'lockoutDuration', 'lockOutObservationWindow'
        if (-not $domain) { throw "The domain object $($Store.DomainDistinguishedName) cannot be read: the account has no access to the directory (anonymous bind?)." }
        $container = Invoke-PSGPOLdapSearch -Connection $connection -SearchBase $Store.GetContainer() -Scope Base -Attribute 'allowedChildClassesEffective' -AllowMissing
        if (-not $container) {
            throw "The domain $($Store.DomainName) has no Password Settings Container: fine-grained password policies need the functional level Windows Server 2008 or later."
        }
        $entries = @(Invoke-PSGPOLdapBinarySearch -Connection $connection -SearchBase $Store.GetContainer() -Scope OneLevel -Filter '(objectClass=msDS-PasswordSettings)' `
                -Attribute (@('name', 'cn', 'objectGUID', 'whenChanged', 'allowedAttributesEffective', 'nTSecurityDescriptor') + $script:PSGPOPasswordPolicyAttributes) -SecurityMasks Dacl)
    } finally {
        $connection.Dispose()
    }
    $Store.DomainPolicy = ConvertTo-PSGPODomainPasswordPolicy -Entry $domain
    $Store.CanCreate = @($container.Attributes['allowedChildClassesEffective']) -contains 'msDS-PasswordSettings'
    $Store.Policies.Clear()
    foreach ($entry in $entries) { $Store.Policies.Add((ConvertTo-PSGPOPasswordPolicy -Entry $entry -EffectiveRights)) }
    $Store.SortPolicies()
}

# The message of a refused change of a PSO, with what to do about it.
function Get-PSGPOPasswordPolicyErrorMessage {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [Exception]$Exception, [Parameter(Mandatory)] [string]$Action)

    $base = $Exception.GetBaseException()
    $code = if ($base.PSObject.Properties['Response'] -and $base.Response) { "$($base.Response.ResultCode)" }
    $detail = if ($base.PSObject.Properties['Response'] -and $base.Response.ErrorMessage) { "$($base.Message) ($($base.Response.ErrorMessage.Trim()))" } else { $base.Message }
    switch ($code) {
        'InsufficientAccessRights' { "The account cannot $Action`: $detail" }
        { $_ -in 'NoSuchAttribute', 'AttributeOrValueExists' } { "Cannot $Action`: it changed in the domain meanwhile. Read the domain again, then try again." }
        'EntryAlreadyExists' { "Cannot $Action`: an object of that name already exists in the Password Settings Container." }
        default { "Cannot $Action`: $detail" }
    }
}

# Creates a PSO in the domain and gives it the objectGUID the domain chose.
function New-PSGPODomainPasswordPolicy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsLdapDirectory]$Directory,
        [Parameter(Mandatory)] [GPOToolsPasswordPolicy]$Policy
    )

    $values = Get-PSGPOPasswordPolicyValue -Policy $Policy
    $request = [System.DirectoryServices.Protocols.AddRequest]::new($Policy.DistinguishedName, 'msDS-PasswordSettings')
    foreach ($name in $script:PSGPOPasswordPolicyAttributes) {
        $value = $values[$name]
        if ($name -eq 'msDS-PSOAppliesTo') {
            if (@($value).Count) { [void]$request.Attributes.Add([System.DirectoryServices.Protocols.DirectoryAttribute]::new($name, [object[]]@($value))) }
        } elseif ($value) {
            [void]$request.Attributes.Add([System.DirectoryServices.Protocols.DirectoryAttribute]::new($name, [string]$value))
        }
    }
    $connection = New-PSGPODirectoryConnection -Directory $Directory
    try {
        try { [void]$connection.SendRequest($request) }
        catch { throw (Get-PSGPOPasswordPolicyErrorMessage -Exception $_.Exception -Action "create the password settings object '$($Policy.Name)' in $($Directory.DomainName)") }
        if ($Policy.ProtectedFromAccidentalDeletion) {
            Set-PSGPODomainDeletionProtection -Connection $connection -DistinguishedName $Policy.DistinguishedName -Protected $true -Name "the password settings object '$($Policy.Name)'"
        }
        $entry = @(Invoke-PSGPOLdapBinarySearch -Connection $connection -SearchBase $Policy.DistinguishedName -Scope Base -Attribute 'objectGUID') | Select-Object -First 1
    } finally {
        $connection.Dispose()
    }
    if ($entry -and @($entry.Values['objectGUID']).Count) { $Policy.Id = [guid]::new([byte[]]$entry.Values['objectGUID'][0]) }
    $Policy.Modified = [datetime]::UtcNow
    $Policy.DirectoryValues = $values
    Write-Verbose "Password settings object '$($Policy.Name)' created: $($Policy.DistinguishedName)."
}

# Changes a PSO to the settings, subjects, name and protection of $Changed; each value is changed
# only if the domain still has the one read. Returns its distinguished name.
function Set-PSGPODomainPasswordPolicy {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [GPOToolsLdapDirectory]$Directory,
        [Parameter(Mandatory)] [GPOToolsPasswordPolicy]$Policy,
        [Parameter(Mandatory)] [GPOToolsPasswordPolicy]$Changed
    )

    $old = if ($Policy.DirectoryValues) { $Policy.DirectoryValues } else { Get-PSGPOPasswordPolicyValue -Policy $Policy }
    $new = Get-PSGPOPasswordPolicyValue -Policy $Changed
    $request = [System.DirectoryServices.Protocols.ModifyRequest]::new()
    $request.DistinguishedName = $Policy.DistinguishedName
    foreach ($name in $script:PSGPOPasswordPolicyAttributes) {
        if ($name -ne 'msDS-PSOAppliesTo') {
            Add-PSGPOLdapValueChange -Request $request -Name $name -Old $old[$name] -New $new[$name]
            continue
        }
        $removed = @($old[$name] | Where-Object { $_ -and -not $Changed.AppliesDirectlyTo($_) })
        $added = @($new[$name] | Where-Object { $subject = $_; $_ -and -not @($old[$name] | Where-Object { [string]::Equals($_, $subject, [System.StringComparison]::OrdinalIgnoreCase) }).Count })
        foreach ($pair in @(@('Delete', $removed), @('Add', $added))) {
            if (-not @($pair[1]).Count) { continue }
            $modification = [System.DirectoryServices.Protocols.DirectoryAttributeModification]::new()
            $modification.Name = $name
            $modification.Operation = [System.DirectoryServices.Protocols.DirectoryAttributeOperation]$pair[0]
            foreach ($value in $pair[1]) { [void]$modification.Add([string]$value) }
            [void]$request.Modifications.Add($modification)
        }
    }

    $distinguishedName = $Policy.DistinguishedName
    $connection = New-PSGPODirectoryConnection -Directory $Directory
    try {
        if ($request.Modifications.Count) {
            try { [void]$connection.SendRequest($request) }
            catch { throw (Get-PSGPOPasswordPolicyErrorMessage -Exception $_.Exception -Action "change the password settings object '$($Policy.Name)'") }
        }
        $Policy.DirectoryValues = $new
        if ($Changed.ProtectedFromAccidentalDeletion -ne $Policy.ProtectedFromAccidentalDeletion) {
            Set-PSGPODomainDeletionProtection -Connection $connection -DistinguishedName $distinguishedName -Protected $Changed.ProtectedFromAccidentalDeletion -Name "the password settings object '$($Policy.Name)'"
        }
        if (-not [string]::Equals($Changed.Name, $Policy.Name, [System.StringComparison]::Ordinal)) {
            $container = [GPOToolsDirectory]::GetParentDistinguishedName($distinguishedName)
            $rdn = 'CN=' + (ConvertTo-PSGPODistinguishedNameValue -Value $Changed.Name)
            try { [void]$connection.SendRequest([System.DirectoryServices.Protocols.ModifyDNRequest]::new($distinguishedName, $container, $rdn)) }
            catch { throw (Get-PSGPOPasswordPolicyErrorMessage -Exception $_.Exception -Action "rename the password settings object '$($Policy.Name)' to '$($Changed.Name)'") }
            $distinguishedName = "$rdn,$container"
        }
    } finally {
        $connection.Dispose()
    }
    Write-Verbose "Password settings object '$($Changed.Name)' changed."
    $distinguishedName
}

function Remove-PSGPODomainPasswordPolicy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsLdapDirectory]$Directory,
        [Parameter(Mandatory)] [GPOToolsPasswordPolicy]$Policy
    )

    $connection = New-PSGPODirectoryConnection -Directory $Directory
    try {
        try { [void]$connection.SendRequest([System.DirectoryServices.Protocols.DeleteRequest]::new($Policy.DistinguishedName)) }
        catch {
            $message = Get-PSGPOPasswordPolicyErrorMessage -Exception $_.Exception -Action "delete the password settings object '$($Policy.Name)'"
            if ("$($_.Exception.GetBaseException().Response.ResultCode)" -eq 'InsufficientAccessRights') { $message += ' Is it protected from accidental deletion?' }
            throw $message
        }
    } finally {
        $connection.Dispose()
    }
    Write-Verbose "Password settings object '$($Policy.Name)' deleted."
}

# A user or a group from a binary search entry.
function ConvertTo-PSGPOPasswordAccount {
    [CmdletBinding()]
    [OutputType([GPOToolsPasswordAccount])]
    param([Parameter(Mandatory)] $Entry)

    $account = [GPOToolsPasswordAccount]::new()
    $account.DistinguishedName = $Entry.DistinguishedName
    $account.Name = Get-PSGPOLdapBinaryText -Entry $Entry -Name 'name'
    if (-not $account.Name) { $account.Name = Get-PSGPOLdapBinaryText -Entry $Entry -Name 'cn' }
    $account.SamAccountName = Get-PSGPOLdapBinaryText -Entry $Entry -Name 'sAMAccountName'
    $classes = @(Get-PSGPOLdapBinaryText -Entry $Entry -Name 'objectClass' -All)
    $account.Kind = if ($classes -contains 'group') { 'Group' } else { 'User' }
    if ($account.Kind -eq 'Group') { $account.SetGroupType([int](Get-PSGPOLdapBinaryText -Entry $Entry -Name 'groupType')) }
    $sid = @($Entry.Values['objectSid'])
    if ($sid.Count -and $sid[0]) { $account.Sid = ConvertFrom-PSGPOBinarySid -Bytes ([byte[]]$sid[0]) }
    $account.MemberOf = [string[]]@(Get-PSGPOLdapBinaryText -Entry $Entry -Name 'memberOf' -All)
    $account
}

# The users and groups whose name, account name or display name starts with $Text, by name (200 at
# most); computers are left out: a PSO applies to users.
function Find-PSGPODomainPasswordAccount {
    [CmdletBinding()]
    [OutputType([GPOToolsPasswordAccount])]
    param(
        [Parameter(Mandatory)] $Connection,
        [Parameter(Mandatory)] [string]$DomainDistinguishedName,
        [AllowEmptyString()] [string]$Text
    )

    $value = ConvertTo-PSGPOLdapFilterValue -Value "$Text".Trim()
    $filter = '(&(|(&(objectClass=user)(!(objectClass=computer)))(objectClass=group))(|(cn={0}*)(sAMAccountName={0}*)(displayName={0}*)))' -f $value
    @(Invoke-PSGPOLdapBinarySearch -Connection $Connection -SearchBase $DomainDistinguishedName -Filter $filter `
            -Attribute 'name', 'cn', 'sAMAccountName', 'objectClass', 'objectSid', 'groupType' | Select-Object -First 200 |
            ForEach-Object { ConvertTo-PSGPOPasswordAccount -Entry $_ }) | Sort-Object Name
}

# A user or a group with its groups (memberOf, and the primary group of a user); $null when the
# domain has none.
function Get-PSGPODomainPasswordAccount {
    [CmdletBinding()]
    [OutputType([GPOToolsPasswordAccount])]
    param(
        [Parameter(Mandatory)] $Connection,
        [Parameter(Mandatory)] [string]$DistinguishedName
    )

    $request = [System.DirectoryServices.Protocols.SearchRequest]::new($DistinguishedName, '(|(objectClass=user)(objectClass=group))', 'Base',
        'name', 'cn', 'sAMAccountName', 'objectClass', 'objectSid', 'groupType', 'memberOf', 'primaryGroupID')
    try {
        $response = $Connection.SendRequest($request)
    } catch {
        $base = $_.Exception.GetBaseException()
        if ($base.PSObject.Properties['Response'] -and "$($base.Response.ResultCode)" -eq 'NoSuchObject') { return $null }
        throw
    }
    if (-not $response.Entries.Count) { return $null }
    $source = $response.Entries[0]
    $values = @{}
    foreach ($name in $source.Attributes.AttributeNames) { $values[$name] = @($source.Attributes[$name].GetValues([byte[]])) }
    $account = ConvertTo-PSGPOPasswordAccount -Entry ([pscustomobject]@{ DistinguishedName = $source.DistinguishedName; Values = $values })
    $rid = Get-PSGPOLdapBinaryText -Entry ([pscustomobject]@{ Values = $values }) -Name 'primaryGroupID'
    if ($rid -and $account.Sid -match '^(S-1-5-21-\d+-\d+-\d+)-\d+$') {
        $domainSid = $Matches[1]
        $domainDN = (@($DistinguishedName -split '(?<!\\),' | Where-Object { $_ -match '^(?i)DC=' })) -join ','
        $sidFilter = ConvertTo-PSGPOLdapBinaryFilter -Bytes ([GPOToolsSecurityDescriptor]::ConvertSidToBytes("$domainSid-$rid"))
        $primary = @(Invoke-PSGPOLdapBinarySearch -Connection $Connection -SearchBase $domainDN -Filter "(objectSid=$sidFilter)" -Attribute 'cn') | Select-Object -First 1
        if ($primary) { $account.PrimaryGroup = $primary.DistinguishedName }
    }
    $account
}

# The PSO the domain controller applies to a user (msDS-ResultantPSO): its distinguished name, or
# '' when none applies (or the account may not read it).
function Get-PSGPODomainResultantPasswordPolicy {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] $Connection,
        [Parameter(Mandatory)] [string]$DistinguishedName
    )

    $entry = Invoke-PSGPOLdapSearch -Connection $Connection -SearchBase $DistinguishedName -Scope Base -Attribute 'msDS-ResultantPSO' -AllowMissing
    if (-not $entry) { return '' }
    "$(Get-PSGPOLdapValue $entry 'msDS-ResultantPSO')"
}

# Which PSOs concern a user or a group, and which one applies: one row per PSO (applied directly,
# or through which groups), by order of priority, and the password policy of the domain last.
# For a group: the PSOs its members get through it. The domain controller has the last word for a
# user (msDS-ResultantPSO), when it answers.
function Resolve-PSGPOPasswordPolicy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsPasswordPolicyStore]$Store,
        [Parameter(Mandatory)] [GPOToolsPasswordAccount]$Account
    )

    # The account with its groups (one found by a search has none).
    $read = $Store.GetAccount($Account.DistinguishedName)
    if ($read) { $Account = $read }

    # The groups of the account, nested ones included: by distinguished name, the group, the
    # chain of groups that leads to it, and whether that chain passes a PSO on (global security
    # groups all along).
    $groups = [ordered]@{}
    $queue = [System.Collections.Generic.Queue[object]]::new()
    $start = @($Account.MemberOf) + @(if ($Account.PrimaryGroup) { $Account.PrimaryGroup })
    $passes = $Account.Kind -eq 'User' -or $Store.PassesPasswordPolicy($Account)
    foreach ($dn in $start) { $queue.Enqueue(@{ Dn = $dn; Path = @(); Passes = $passes }) }
    while ($queue.Count) {
        $item = $queue.Dequeue()
        if ($groups.Contains($item.Dn.ToLowerInvariant())) { continue }
        $group = $Store.GetAccount($item.Dn)
        if (-not $group -or $group.Kind -ne 'Group') { continue }
        $path = @($item.Path) + $group.Name
        $groupPasses = $item.Passes -and $Store.PassesPasswordPolicy($group)
        $groups[$item.Dn.ToLowerInvariant()] = [pscustomobject]@{ Group = $group; Path = $path; Passes = $groupPasses }
        foreach ($parent in @($group.MemberOf)) { $queue.Enqueue(@{ Dn = $parent; Path = $path; Passes = $groupPasses }) }
    }

    $rows = foreach ($policy in $Store.Policies) {
        $direct = $policy.AppliesDirectlyTo($Account.DistinguishedName)
        $through = @($groups.Values | Where-Object { $policy.AppliesDirectlyTo($_.Group.DistinguishedName) })
        if (-not $direct -and -not $through.Count) { continue }
        # For a group, a PSO applied to it reaches its members as one applied to any of their groups.
        $directCounts = $direct -and $Account.Kind -eq 'User'
        $groupCounts = $direct -and $Account.Kind -eq 'Group' -and $Store.PassesPasswordPolicy($Account)
        [pscustomobject]@{
            Policy = $policy
            Direct = $direct
            # Through a global security group (a group of groups of them) only
            ThroughGroups = [string[]]@($through | Where-Object Passes | ForEach-Object { $_.Path -join ' > ' })
            IgnoredGroups = [string[]]@($through | Where-Object { -not $_.Passes } | ForEach-Object { $_.Path -join ' > ' })
            # The group itself, applied directly, when it passes no PSO on
            IgnoredSelf = $direct -and $Account.Kind -eq 'Group' -and -not $groupCounts
            Counts = $directCounts -or $groupCounts -or @($through | Where-Object Passes).Count
            DirectCounts = $directCounts
        }
    }
    $rows = @($rows)
    $directRows = @($rows | Where-Object DirectCounts)
    $candidates = if ($directRows.Count) { $directRows } else { @($rows | Where-Object Counts) }
    $computed = $null
    foreach ($row in $candidates) { if (-not $computed -or [GPOToolsPasswordPolicy]::Compare($row.Policy, $computed) -lt 0) { $computed = $row.Policy } }

    # The domain controller's answer, for a user.
    $server = $Store.GetServerResultant($Account)
    $applied = $computed
    $source = 'Computed'
    if ($null -ne $server) {
        $source = 'DomainController'
        $applied = if ($server) { $Store.Policies | Where-Object { [string]::Equals($_.DistinguishedName, $server, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1 }
        if ($server -and -not $applied) {
            # A PSO the account may not read: its name only.
            $applied = [GPOToolsPasswordPolicy]::new()
            $applied.Name = (($server -split '(?<!\\),')[0] -replace '^(?i)CN=', '') -replace '\\(.)', '$1'
            $applied.DistinguishedName = $server
            $applied.CanEdit = $false
        }
    }

    $order = 0
    $candidateRows = foreach ($row in @($rows | Sort-Object { $_.Policy.Precedence }, { $_.Policy.Id })) {
        $order++
        $isApplied = $applied -and [object]::ReferenceEquals($row.Policy, $applied)
        $status = if ($isApplied) { 'Applied' }
            elseif (-not $row.Counts) { 'GroupIgnored' }
            elseif ($directRows.Count -and -not $row.DirectCounts) { 'DirectWins' }
            else { 'LowerPriority' }
        $through = @(if ($row.Direct) { 'Direct' }) + @($row.ThroughGroups) + @($row.IgnoredGroups)
        [pscustomobject]@{
            PSTypeName = 'PSGPOTools.PasswordPolicyCandidate'
            Order = $order
            Name = $row.Policy.Name
            Precedence = $row.Policy.Precedence
            AppliesThrough = [string[]]$through
            Status = $status
            # The groups it is applied to that pass no PSO on (the group itself included)
            IgnoredGroups = [string[]]@(@(if ($row.IgnoredSelf) { $Account.Name }) + @($row.IgnoredGroups))
            Reason = switch ($status) {
                'Applied' { 'Applies.' }
                'GroupIgnored' { "Not applied: $(@(@(if ($row.IgnoredSelf) { $Account.Name }) + @($row.IgnoredGroups)) -join ', ') passes no PSO on ($(if ($Store.GroupRule -eq 'Security') { 'Samba AD: only the security groups that are not built-in do' } else { 'only global security groups do' }))." }
                'DirectWins' { 'Not applied: a PSO applies directly to the account.' }
                default { "Not applied: $($applied.Name) comes first (lower precedence, or the same and a smaller GUID)." }
            }
            Policy = $row.Policy
        }
    }
    $domainRow = [pscustomobject]@{
        PSTypeName = 'PSGPOTools.PasswordPolicyCandidate'
        Order = $order + 1
        Name = $Store.DomainPolicy.Name
        Precedence = $null
        AppliesThrough = [string[]]@('Domain')
        Status = if ($applied) { 'LowerPriority' } else { 'Applied' }
        IgnoredGroups = [string[]]@()
        Reason = if ($applied) { "Not applied: $($applied.Name) applies." } else { 'Applies: no PSO applies to the account.' }
        Policy = $Store.DomainPolicy
    }

    [pscustomobject]@{
        PSTypeName = 'PSGPOTools.ResultantPasswordPolicy'
        Identity = $Account.Name
        SamAccountName = $Account.SamAccountName
        DistinguishedName = $Account.DistinguishedName
        Kind = $Account.Kind
        AppliedPolicy = if ($applied) { $applied.Name } else { $Store.DomainPolicy.Name }
        Source = $source
        # The domain controller does not apply the PSO this computation finds
        Differs = $source -eq 'DomainController' -and -not [object]::ReferenceEquals($applied, $computed) -and
            -not ($applied -and $computed -and $applied.DistinguishedName -eq $computed.DistinguishedName)
        ComputedPolicy = if ($computed) { $computed.Name } else { $Store.DomainPolicy.Name }
        # The settings that apply; $null for a PSO the account may not read
        Settings = if (-not $applied) { $Store.DomainPolicy } elseif ($Store.Policies.Contains($applied)) { $applied } else { $null }
        Candidates = @(@($candidateRows) + $domainRow)
        Groups = @($groups.Values | ForEach-Object { [pscustomobject]@{ Name = $_.Group.Name; Path = $_.Path -join ' > '; Scope = $_.Group.GroupScope; Security = $_.Group.IsSecurityGroup; PassesPolicy = $_.Passes } })
    }
}

# What the audit log keeps of a PSO: its settings, or what a change changed.
function Get-PSGPOPasswordPolicyAuditDetail {
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)] [GPOToolsPasswordPolicy]$Policy,
        [GPOToolsPasswordPolicy]$Before
    )

    $names = 'Name', 'Precedence', 'MinPasswordLength', 'PasswordHistoryCount', 'ComplexityEnabled', 'ReversibleEncryptionEnabled', 'MinPasswordAge', 'MaxPasswordAge',
    'LockoutThreshold', 'LockoutDuration', 'LockoutObservationWindow', 'Description', 'ProtectedFromAccidentalDeletion'
    $details = [ordered]@{ Name = $Policy.Name }
    foreach ($name in $names) {
        $value = if ($Policy.$name -is [TimeSpan]) { $Policy.$name.ToString() } else { $Policy.$name }
        if (-not $Before) { $details[$name] = $value; continue }
        $old = if ($Before.$name -is [TimeSpan]) { $Before.$name.ToString() } else { $Before.$name }
        if ("$old" -cne "$value") { $details[$name] = [ordered]@{ Before = $old; After = $value } }
    }
    if (-not $Before) { $details.AppliesTo = [string[]]@($Policy.AppliesTo); return $details }
    $added = @($Policy.AppliesTo | Where-Object { -not $Before.AppliesDirectlyTo($_) })
    $removed = @($Before.AppliesTo | Where-Object { -not $Policy.AppliesDirectlyTo($_) })
    if ($added.Count) { $details.AddedSubjects = [string[]]$added }
    if ($removed.Count) { $details.RemovedSubjects = [string[]]$removed }
    $details
}

# Connects to a domain controller and reads the fine-grained password policies of its domain,
# without its GPOs.
function Connect-PSGPOPasswordPolicyStore {
    [CmdletBinding()]
    [OutputType([GPOToolsLdapPasswordPolicyStore])]
    param(
        [string]$Server,
        [pscredential]$Credential,
        [switch]$UseSsl,
        [int]$Port
    )

    $Server = Resolve-PSGPODomainServer -Server $Server
    $connection = New-PSGPOLdapConnection -Server $Server -Credential $Credential -UseSsl:$UseSsl -Port $Port
    try {
        $rootDse = Invoke-PSGPOLdapSearch -Connection $connection -SearchBase '' -Scope Base -Attribute 'defaultNamingContext', 'dnsHostName', 'vendorName'
        $domainDN = Get-PSGPOLdapValue $rootDse 'defaultNamingContext'
        if (-not $domainDN) { throw "$Server did not give its default naming context: is it a domain controller?" }
        $dnsHostName = Get-PSGPOLdapValue $rootDse 'dnsHostName'
        $account = Get-PSGPOLdapAccount -Connection $connection
    } finally {
        $connection.Dispose()
    }
    $domainName = (@([regex]::Matches($domainDN, '(?i)(?:^|,)DC=([^,]+)') | ForEach-Object { $_.Groups[1].Value }) -join '.').ToLowerInvariant()
    $directory = [GPOToolsLdapDirectory]::new($domainName, $domainDN, $(if ($dnsHostName) { $dnsHostName } else { $Server }), [GPOToolsLdapDirectory]::GetServerType((Get-PSGPOLdapValue $rootDse 'vendorName')))
    $directory.Account = $account
    $directory.Credential = $Credential
    $directory.UseSsl = [bool]$UseSsl
    $directory.Port = $Port
    $store = [GPOToolsLdapPasswordPolicyStore]::new($directory)
    $store.Refresh()
    $store
}

# The fine-grained password policies of the commands: those of the domain of -Server (or of the
# domain of the computer), read with -Credential and -UseSsl when given.
function Get-PSGPOPasswordPolicyStore {
    [CmdletBinding()]
    [OutputType([GPOToolsPasswordPolicyStore])]
    param([hashtable]$BoundParameters)

    $read = @{}
    foreach ($name in 'Server', 'Credential', 'UseSsl') { if ($BoundParameters.ContainsKey($name)) { $read[$name] = $BoundParameters[$name] } }
    Connect-PSGPOPasswordPolicyStore @read
}

# The fine-grained password policies of a JSON description (Samples/PasswordPolicy.sample.json):
# the domain, its password policy, its users and groups (by account name), and its PSOs.
function Import-PSGPOPasswordPolicyStore {
    [CmdletBinding()]
    [OutputType([GPOToolsPasswordPolicyStore])]
    param([Parameter(Mandatory)] [string]$Path)

    $data = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json
    $store = [GPOToolsPasswordPolicyStore]::new($data.domain)
    $store.Source = "read from $Path"
    $setPolicy = {
        param($Policy, $Values)
        $Policy.MinPasswordLength = [int]$Values.minPasswordLength
        $Policy.PasswordHistoryCount = [int]$Values.passwordHistoryCount
        $Policy.ComplexityEnabled = [bool]$Values.complexityEnabled
        $Policy.ReversibleEncryptionEnabled = [bool]$Values.reversibleEncryptionEnabled
        $Policy.MinPasswordAge = [TimeSpan]::FromDays([double]$Values.minPasswordAgeDays)
        $Policy.MaxPasswordAge = [TimeSpan]::FromDays([double]$Values.maxPasswordAgeDays)
        $Policy.LockoutThreshold = [int]$Values.lockoutThreshold
        $Policy.LockoutDuration = [TimeSpan]::FromMinutes([double]$Values.lockoutDurationMinutes)
        $Policy.LockoutObservationWindow = [TimeSpan]::FromMinutes([double]$Values.lockoutObservationWindowMinutes)
    }
    & $setPolicy $store.DomainPolicy $data.domainPolicy
    $store.DomainPolicy.DistinguishedName = $store.DomainDistinguishedName

    $bySam = @{}
    foreach ($item in @($data.accounts)) {
        $account = [GPOToolsPasswordAccount]::new()
        $account.Name = $item.name
        $account.SamAccountName = if ($item.samAccountName) { $item.samAccountName } else { $item.name }
        $account.Kind = $item.kind
        $container = if ($item.container) { $item.container } else { 'CN=Users' }
        $account.DistinguishedName = 'CN={0},{1},{2}' -f (ConvertTo-PSGPODistinguishedNameValue -Value $item.name), $container, $store.DomainDistinguishedName
        if ($account.Kind -eq 'Group') {
            $account.GroupScope = if ($item.scope) { $item.scope } else { 'Global' }
            $account.IsSecurityGroup = $item.security -ne $false
        }
        $bySam[$account.SamAccountName] = @{ Account = $account; MemberOf = @($item.memberOf); PrimaryGroup = $item.primaryGroup }
        $store.Accounts[$account.DistinguishedName] = $account
    }
    $resolve = { param($Name) if (-not $bySam.ContainsKey($Name)) { throw "$Path names an unknown account: $Name." }; $bySam[$Name].Account.DistinguishedName }
    foreach ($entry in $bySam.Values) {
        $entry.Account.MemberOf = [string[]]@($entry.MemberOf | Where-Object { $_ } | ForEach-Object { & $resolve $_ })
        if ($entry.PrimaryGroup) { $entry.Account.PrimaryGroup = & $resolve $entry.PrimaryGroup }
    }

    foreach ($item in @($data.policies)) {
        $policy = [GPOToolsPasswordPolicy]::new()
        $policy.Name = $item.name
        $policy.Id = [guid]$item.id
        $policy.Precedence = [int]$item.precedence
        & $setPolicy $policy $item
        $policy.Description = $item.description
        $policy.ProtectedFromAccidentalDeletion = [bool]$item.protectedFromAccidentalDeletion
        $policy.DistinguishedName = 'CN={0},{1}' -f (ConvertTo-PSGPODistinguishedNameValue -Value $policy.Name), $store.GetContainer()
        foreach ($name in @($item.appliesTo)) { if ($name) { $policy.AppliesTo.Add((& $resolve $name)) } }
        $store.Policies.Add($policy)
    }
    $store.SortPolicies()
    $store
}

# What the commands return of a PSO, or of the password policy of the domain.
function ConvertTo-PSGPOPasswordPolicyOutput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsPasswordPolicy]$Policy,
        [Parameter(Mandatory)] [GPOToolsPasswordPolicyStore]$Store
    )

    $output = [ordered]@{
        PSTypeName = if ($Policy.IsDefault) { 'PSGPOTools.DefaultPasswordPolicy' } else { 'PSGPOTools.FineGrainedPasswordPolicy' }
        Name = $Policy.Name
    }
    if (-not $Policy.IsDefault) { $output.Precedence = $Policy.Precedence }
    $output.MinPasswordLength = $Policy.MinPasswordLength
    $output.PasswordHistoryCount = $Policy.PasswordHistoryCount
    $output.ComplexityEnabled = $Policy.ComplexityEnabled
    $output.ReversibleEncryptionEnabled = $Policy.ReversibleEncryptionEnabled
    $output.MinPasswordAge = $Policy.MinPasswordAge
    # Zero: never
    $output.MaxPasswordAge = $Policy.MaxPasswordAge
    $output.LockoutThreshold = $Policy.LockoutThreshold
    # Zero: until an administrator unlocks the account
    $output.LockoutDuration = $Policy.LockoutDuration
    $output.LockoutObservationWindow = $Policy.LockoutObservationWindow
    if (-not $Policy.IsDefault) {
        $output.Description = $Policy.Description
        $output.ProtectedFromAccidentalDeletion = $Policy.ProtectedFromAccidentalDeletion
        $output.AppliesTo = [string[]]@($Policy.AppliesTo)
        $output.Id = $Policy.Id
    }
    $output.DistinguishedName = $Policy.DistinguishedName
    $output.Domain = $Store.DomainName
    [pscustomobject]$output
}

# The PSOs of the store whose name matches the patterns; an error for a pattern without one.
function Find-PSGPOPasswordPolicy {
    [CmdletBinding()]
    [OutputType([GPOToolsPasswordPolicy])]
    param(
        [Parameter(Mandatory)] [GPOToolsPasswordPolicyStore]$Store,
        [Parameter(Mandatory)] [string[]]$Name
    )

    foreach ($pattern in $Name) {
        $found = @($Store.Policies | Where-Object { Test-PSGPONameMatch -Name $_.Name -Pattern $pattern })
        if (-not $found) { Write-Error "No password settings object named '$pattern' in $($Store.DomainName)."; continue }
        $found
    }
}

# The settings of a PSO given to New- and Set-PSGPOFineGrainedPasswordPolicy.
function Set-PSGPOPasswordPolicySetting {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsPasswordPolicy]$Policy,
        [Parameter(Mandatory)] [hashtable]$BoundParameters
    )

    foreach ($name in 'Precedence', 'MinPasswordLength', 'PasswordHistoryCount', 'ComplexityEnabled', 'ReversibleEncryptionEnabled', 'MinPasswordAge', 'MaxPasswordAge',
        'LockoutThreshold', 'LockoutDuration', 'LockoutObservationWindow', 'Description', 'ProtectedFromAccidentalDeletion') {
        if ($BoundParameters.ContainsKey($name)) { $Policy.$name = $BoundParameters[$name] }
    }
}
