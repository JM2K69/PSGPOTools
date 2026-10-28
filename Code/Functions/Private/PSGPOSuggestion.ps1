<#
    Suggestions while typing, in the boxes of the windows (Avalonia AutoCompleteBox):
    - the accounts: the well-known accounts of every computer and of the domain
      (GPOToolsWellKnownSid, in the language of the interface, with their SID), then the accounts
      of the domain read whose name begins with what is typed;
    - the registry keys and value names of the loaded ADMX files, for a registry preference, with
      the policies that write them.
    A box gets its suggestions from Register-PSGPOAccountSuggestion or
    Register-PSGPORegistrySuggestion; what they need is kept in its Tag, as its handlers run after
    the function that made the form returned.
#>

# The SID of the domain of a directory read over LDAP, read once; $null in memory or when it cannot
# be read (the accounts of the domain are then suggested by their name).
function Get-PSGPODirectoryDomainSid {
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowNull()] [GPOToolsDirectory]$Directory)

    if ($Directory -isnot [GPOToolsLdapDirectory]) { return $null }
    if (-not $script:PSGPODirectoryDomainSids) { $script:PSGPODirectoryDomainSids = @{} }
    $key = "$($Directory.Server)|$($Directory.Domain.DistinguishedName)"
    if ($script:PSGPODirectoryDomainSids.ContainsKey($key)) { return $script:PSGPODirectoryDomainSids[$key] }
    $sid = $null
    try {
        $connection = New-PSGPOLdapConnection -Server $Directory.Server -Credential $Directory.Credential -UseSsl:$Directory.UseSsl -Port $Directory.Port
        try {
            $entry = @(Invoke-PSGPOLdapBinarySearch -Connection $connection -SearchBase $Directory.Domain.DistinguishedName -Scope Base -Attribute 'objectSid') | Select-Object -First 1
            if ($entry -and $entry.Values['objectSid']) { $sid = ConvertFrom-PSGPOBinarySid -Bytes ([byte[]]$entry.Values['objectSid'][0]) }
        } finally {
            $connection.Dispose()
        }
    } catch {
        Write-Verbose "The SID of the domain is not read: $($_.Exception.Message)"
    }
    $script:PSGPODirectoryDomainSids[$key] = $sid
    $sid
}

# The name of a well-known account in the language of the interface.
function Get-PSGPOWellKnownSidName {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [GPOToolsWellKnownSid]$Entry)

    if ("$script:PSGPOLanguage" -like 'fr*') { $Entry.FrenchName } else { $Entry.Name }
}

# The accounts of the domain whose name (sAMAccountName, name, display name) begins with a text:
# Name (sAMAccountName), Sid and Kind (user, group, computer), 25 at most.
function Find-PSGPOAccountSuggestion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsLdapDirectory]$Directory,
        [Parameter(Mandatory)] [string]$Text
    )

    $value = ConvertTo-PSGPOLdapFilterValue $Text
    $filter = "(&(|(objectCategory=person)(objectCategory=group)(objectCategory=computer))(|(sAMAccountName=$value*)(cn=$value*)(displayName=$value*)))"
    $connection = New-PSGPOLdapConnection -Server $Directory.Server -Credential $Directory.Credential -UseSsl:$Directory.UseSsl -Port $Directory.Port
    try {
        $count = 0
        foreach ($entry in @(Invoke-PSGPOLdapBinarySearch -Connection $connection -SearchBase $Directory.Domain.DistinguishedName -Filter $filter -Attribute 'sAMAccountName', 'objectSid', 'objectClass')) {
            if (-not $entry.Values['objectSid'] -or -not $entry.Values['sAMAccountName']) { continue }
            $classes = @($entry.Values['objectClass'] | ForEach-Object { [System.Text.Encoding]::UTF8.GetString([byte[]]$_) })
            [pscustomobject]@{
                Name = [System.Text.Encoding]::UTF8.GetString([byte[]]$entry.Values['sAMAccountName'][0])
                Sid = ConvertFrom-PSGPOBinarySid -Bytes ([byte[]]$entry.Values['objectSid'][0])
                Kind = if ($classes -contains 'computer') { 'computer' } elseif ($classes -contains 'group') { 'group' } else { 'user' }
            }
            if (++$count -ge 25) { break }
        }
    } finally {
        $connection.Dispose()
    }
}

# The accounts that match a text being typed: the well-known accounts whose name (English or
# French) holds it or whose SID begins with it, then the accounts of the domain whose name begins
# with it. -Insert Sid: the suggestion writes *S-1-... (GptTmpl.inf: a restricted group, a user
# right), Name: its name (a permission, the security filtering). -Kind BuiltinGroup: the groups
# of every computer only (a local group).
function Get-PSGPOAccountSuggestion {
    [CmdletBinding()]
    [OutputType([AvaloniaSuggestionRow])]
    param(
        [AllowNull()] [GPOToolsDirectory]$Directory,
        [AllowEmptyString()] [string]$Text,
        [ValidateSet('Sid', 'Name')] [string]$Insert = 'Name',
        [ValidateSet('Any', 'BuiltinGroup')] [string]$Kind = 'Any',
        [string]$DomainSid
    )

    $search = "$Text".Trim().TrimStart('*')
    $domain = if ($Directory) { ($Directory.DomainName -split '\.')[0].ToUpperInvariant() } else { 'DOMAIN' }
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $contains = { param($Value) $Value -and $Value.IndexOf($search, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 }
    $starts = { param($Entry) $Entry.Name.StartsWith($search, [System.StringComparison]::OrdinalIgnoreCase) -or $Entry.FrenchName.StartsWith($search, [System.StringComparison]::OrdinalIgnoreCase) }
    # The names that begin with what is typed first (Domain Admins before Key Admins for "dom").
    $entries = @([GPOToolsWellKnownSid]::All | Where-Object { & $starts $_ }) + @([GPOToolsWellKnownSid]::All | Where-Object { -not (& $starts $_) })
    foreach ($entry in $entries) {
        if ($Kind -eq 'BuiltinGroup' -and -not $entry.Sid.StartsWith('S-1-5-32-')) { continue }
        $sid = $entry.GetSid($DomainSid)
        if ($search -and -not ((& $contains $entry.Name) -or (& $contains $entry.FrenchName) -or ($sid -and $sid.StartsWith($search, [System.StringComparison]::OrdinalIgnoreCase)))) { continue }
        $name = Get-PSGPOWellKnownSidName -Entry $entry
        $row = [AvaloniaSuggestionRow]::new()
        $row.Name = if ($entry.IsDomainAccount()) { $name } else { $(if ($entry.Authority) { "$($entry.Authority)\$name" } else { $name }) }
        $row.Sid = $sid
        $row.Display = '{0}   {1}' -f $row.Name, $(if ($sid) { $sid } else { "RID $($entry.Sid.TrimStart('-'))" })
        $row.Value = if ($Insert -eq 'Sid' -and $sid) { "*$sid" } elseif ($Kind -eq 'BuiltinGroup') { "$($entry.Name) (built-in)" } else { $name }
        if ($sid) { [void]$seen.Add($sid) }
        $row
    }
    if ($Kind -ne 'Any' -or $Directory -isnot [GPOToolsLdapDirectory] -or $search.Length -lt 2 -or $search -match '^S-1-') { return }
    try {
        foreach ($account in @(Find-PSGPOAccountSuggestion -Directory $Directory -Text $search)) {
            if ($seen.Contains($account.Sid)) { continue }
            $row = [AvaloniaSuggestionRow]::new()
            $row.Name = "$domain\$($account.Name)"
            $row.Sid = $account.Sid
            $row.Display = '{0}   {1}, {2}' -f $row.Name, (Get-PSGPOText $account.Kind), $account.Sid
            $row.Value = if ($Insert -eq 'Sid') { "*$($account.Sid)" } else { $account.Name }
            $row
        }
    } catch {
        Write-Verbose "The accounts of the domain are not searched: $($_.Exception.Message)"
    }
}

# Gives an AutoCompleteBox the suggestions of the accounts (Get-PSGPOAccountSuggestion). The SID of
# the domain is read the first time something is typed.
function Register-PSGPOAccountSuggestion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Box,
        [AllowNull()] [GPOToolsDirectory]$Directory,
        [ValidateSet('Sid', 'Name')] [string]$Insert = 'Name',
        [ValidateSet('Any', 'BuiltinGroup')] [string]$Kind = 'Any'
    )

    $Box.Tag = @{ Directory = $Directory; Insert = $Insert; Kind = $Kind; DomainSid = $null; DomainSidRead = $false }
    Initialize-PSGPOSuggestionBox -Box $Box
    $Box.add_Populating({
            param($control, $e)
            $e.Cancel = $true
            $state = $control.Tag
            if (-not $state.DomainSidRead) { $state.DomainSid = Get-PSGPODirectoryDomainSid -Directory $state.Directory; $state.DomainSidRead = $true }
            $control.ItemsSource = @(Get-PSGPOAccountSuggestion -Directory $state.Directory -Text $e.Parameter -Insert $state.Insert -Kind $state.Kind -DomainSid $state.DomainSid | Select-Object -First 60)
            $control.PopulateComplete()
        })
}

# What every box of suggestions has: the list as given (not filtered again), from the first
# character, a quarter of a second after the last one typed, the value of the row written.
function Initialize-PSGPOSuggestionBox {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Box)

    $Box.FilterMode = [Avalonia.Controls.AutoCompleteFilterMode]::None
    $Box.MinimumPrefixLength = 1
    $Box.MinimumPopulateDelay = [TimeSpan]::FromMilliseconds(250)
    $Box.MaxDropDownHeight = 320
    $Box.ItemSelector = [Avalonia.Controls.AutoCompleteSelector[object]] { param($Search, $Item) if ($Item) { $Item.Value } else { $Search } }
}

# The registry keys of the loaded ADMX files, for a scope (Machine, User): each key with the
# policies that write it, sorted; kept for the loaded set.
function Get-PSGPORegistryKeyCatalog {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [ValidateSet('Machine', 'User')] [string]$Scope)

    if (-not $script:PSGPORegistryKeyCatalog -or $script:PSGPORegistryKeyCatalogGeneration -ne [GPOToolsUtility]::Generation -or $script:PSGPORegistryKeyCatalogCount -ne [GPOToolsUtility]::Policies.Count) {
        $catalog = @{ Machine = [System.Collections.Generic.List[object]]::new(); User = [System.Collections.Generic.List[object]]::new() }
        $index = Get-PSGPOPolicyKeyIndex
        foreach ($entry in $index.GetEnumerator()) {
            $separator = $entry.Key.IndexOf('|')
            $scope = $entry.Key.Substring(0, $separator)
            if (-not $catalog.ContainsKey($scope)) { continue }
            $catalog[$scope].Add([pscustomobject]@{ Key = $entry.Key.Substring($separator + 1); Policies = @($entry.Value) })
        }
        foreach ($name in @($catalog.Keys)) {
            $catalog[$name] = @([System.Linq.Enumerable]::ToArray([System.Linq.Enumerable]::OrderBy($catalog[$name], [Func[object, string]] { param($Item) $Item.Key }, [System.StringComparer]::OrdinalIgnoreCase)))
        }
        $script:PSGPORegistryKeyCatalog = $catalog
        $script:PSGPORegistryKeyCatalogGeneration = [GPOToolsUtility]::Generation
        $script:PSGPORegistryKeyCatalogCount = [GPOToolsUtility]::Policies.Count
    }
    $script:PSGPORegistryKeyCatalog[$Scope]
}

# The scope of a hive of a registry preference: Machine for HKEY_LOCAL_MACHINE, User for
# HKEY_CURRENT_USER, $null for the others (no ADMX file writes them).
function Get-PSGPOHiveScope {
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowEmptyString()] [AllowNull()] [string]$Hive)

    switch ($Hive) { 'HKEY_LOCAL_MACHINE' { 'Machine' } 'HKEY_CURRENT_USER' { 'User' } default { $null } }
}

# The registry keys of the ADMX files of a hive that hold a text, 60 at most: those that begin
# with it first; each with the policy that writes it (and how many others).
function Get-PSGPORegistryKeySuggestion {
    [CmdletBinding()]
    [OutputType([AvaloniaSuggestionRow])]
    param(
        [AllowEmptyString()] [AllowNull()] [string]$Hive,
        [AllowEmptyString()] [string]$Text
    )

    $scope = Get-PSGPOHiveScope -Hive $Hive
    if (-not $scope -or -not [GPOToolsUtility]::Policies.Count) { return }
    $search = "$Text".Trim().TrimStart('\')
    $starts = [System.Collections.Generic.List[object]]::new()
    $holds = [System.Collections.Generic.List[object]]::new()
    foreach ($item in (Get-PSGPORegistryKeyCatalog -Scope $scope)) {
        $at = $item.Key.IndexOf($search, [System.StringComparison]::OrdinalIgnoreCase)
        if ($at -eq 0) { $starts.Add($item) } elseif ($at -gt 0) { $holds.Add($item) }
        if ($starts.Count -ge 60) { break }
    }
    foreach ($item in @($starts) + @($holds) | Select-Object -First 60) {
        $row = [AvaloniaSuggestionRow]::new()
        $row.Value = $item.Key
        $first = $item.Policies[0].DisplayName
        $row.Display = if ($item.Policies.Count -gt 1) { Get-PSGPOText '{0}   {1} and {2} other policies' $item.Key $first ($item.Policies.Count - 1) } else { '{0}   {1}' -f $item.Key, $first }
        $row
    }
}

# The value names the ADMX files write under a key of a hive that hold a text, with the policy
# that writes each; the default value of the key is left out (its name is empty).
function Get-PSGPORegistryValueSuggestion {
    [CmdletBinding()]
    [OutputType([AvaloniaSuggestionRow])]
    param(
        [AllowEmptyString()] [AllowNull()] [string]$Hive,
        [AllowEmptyString()] [AllowNull()] [string]$Key,
        [AllowEmptyString()] [string]$Text
    )

    $scope = Get-PSGPOHiveScope -Hive $Hive
    if (-not $scope -or -not "$Key".Trim()) { return }
    $policies = $null
    if (-not (Get-PSGPOPolicyKeyIndex).TryGetValue("$scope|$("$Key".Trim().Trim('\'))", [ref]$policies)) { return }
    $prefix = "$("$Key".Trim().Trim('\'))`0"
    $names = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($policy in $policies) {
        foreach ($valueName in (Get-PSGPOPolicyFootprint -Policy $policy).ValueNames) {
            if (-not $valueName.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
            $name = $valueName.Substring($prefix.Length)
            if ($name -and -not $names.ContainsKey($name)) { $names[$name] = $policy.DisplayName }
        }
    }
    $search = "$Text".Trim()
    # Those that begin with what is typed first (AUOptions before AlwaysAutoReboot... for "AU").
    $sorted = @($names.Keys | Sort-Object { -not $_.StartsWith($search, [System.StringComparison]::OrdinalIgnoreCase) }, { $_ })
    foreach ($name in $sorted) {
        if ($search -and $name.IndexOf($search, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) { continue }
        $row = [AvaloniaSuggestionRow]::new()
        $row.Value = $name
        $row.Display = '{0}   {1}' -f $name, $names[$name]
        $row
    }
}

# The policies of the ADMX files that write a key of a hive: a registry preference there writes
# what a policy manages, and stays when the GPO no longer applies (it tattoos the computers).
function Get-PSGPORegistryKeyPolicy {
    [CmdletBinding()]
    param(
        [AllowEmptyString()] [AllowNull()] [string]$Hive,
        [AllowEmptyString()] [AllowNull()] [string]$Key
    )

    $scope = Get-PSGPOHiveScope -Hive $Hive
    if (-not $scope -or -not "$Key".Trim() -or -not [GPOToolsUtility]::Policies.Count) { return }
    $policies = $null
    if ((Get-PSGPOPolicyKeyIndex).TryGetValue("$scope|$("$Key".Trim().Trim('\'))", [ref]$policies)) { @($policies) }
}

# Gives the key and value name boxes of a registry preference their suggestions, from the ADMX
# files of the hive chosen in $Hive (a ComboBox of HKEY_ names), and the key box its warning
# ($Warning, a TextBlock) when a policy manages the key.
function Register-PSGPORegistrySuggestion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Hive,
        [Parameter(Mandatory)] $KeyBox,
        $ValueBox,
        $Warning
    )

    $KeyBox.Tag = @{ Hive = $Hive; Key = $KeyBox; Warning = $Warning }
    Initialize-PSGPOSuggestionBox -Box $KeyBox
    $KeyBox.add_Populating({
            param($control, $e)
            $e.Cancel = $true
            $control.ItemsSource = @(Get-PSGPORegistryKeySuggestion -Hive "$($control.Tag.Hive.SelectedItem)" -Text $e.Parameter)
            $control.PopulateComplete()
        })
    if ($ValueBox) {
        $ValueBox.Tag = @{ Hive = $Hive; Key = $KeyBox }
        Initialize-PSGPOSuggestionBox -Box $ValueBox
        $ValueBox.MinimumPrefixLength = 0
        $ValueBox.add_Populating({
                param($control, $e)
                $e.Cancel = $true
                $control.ItemsSource = @(Get-PSGPORegistryValueSuggestion -Hive "$($control.Tag.Hive.SelectedItem)" -Key "$($control.Tag.Key.Text)" -Text $e.Parameter)
                $control.PopulateComplete()
            })
    }
    if ($Warning) {
        $KeyBox.add_PropertyChanged({
                param($control, $e)
                if ($e.Property.Name -eq 'Text') { Update-PSGPORegistryKeyWarning -State $control.Tag }
            })
        $Hive.Tag = $KeyBox.Tag
        $Hive.add_SelectionChanged({ param($control, $e) Update-PSGPORegistryKeyWarning -State $control.Tag })
        Update-PSGPORegistryKeyWarning -State $KeyBox.Tag
    }
}

# The warning of the key of a registry preference: the policies that manage it.
function Update-PSGPORegistryKeyWarning {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable]$State)

    $policies = @(Get-PSGPORegistryKeyPolicy -Hive "$($State.Hive.SelectedItem)" -Key "$($State.Key.Text)")
    $State.Warning.Text = if ($policies.Count) {
        $names = @($policies | Select-Object -First 3 | ForEach-Object { "'$($_.DisplayName)'" }) -join ', '
        Get-PSGPOText 'A policy manages this key ({0}{1}): a preference writes it on the computers for good, it stays when the GPO no longer applies. Set the policy instead.' $names $(if ($policies.Count -gt 3) { Get-PSGPOText ' and {0} other' ($policies.Count - 3) } else { '' })
    } else { '' }
}
