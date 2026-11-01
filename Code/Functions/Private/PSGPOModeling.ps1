<#
    Group Policy Modeling, as GPMC: the GPOs a computer and a user would apply, from the directory
    alone. The links of the site of the computer, of the domain and of the OUs above the account, in
    the order Windows applies them (the enforced links from the site down, the others from the OU
    up to an OU that blocks the inheritance); for each GPO, applied or denied, and why: a disabled
    link or GPO part, its security filtering (the token of the account: its SID, its groups with
    the nested ones, Everyone and Authenticated Users; the computer must also read a user GPO,
    MS16-072), its WMI filter (assumed true, but those said false), no settings in that part
    (Empty). Loopback processing (Merge, Replace) comes from the computer GPOs applied, as the
    setting "Configure user Group Policy loopback processing mode" gives it, or is given.
#>

# The well-known SIDs every token has: Everyone, Authenticated Users.
$script:PSGPOModelingTokenSids = 'S-1-1-0', 'S-1-5-11'

# The links of a SOM and of the SOMs above it, and of a site, in the order of their precedence
# (1 wins), the disabled ones and those to a GPO not found included: Link, Som, Enforced.
function Get-PSGPOModelingLink {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsSom]$Som,
        [GPOToolsSom]$Site
    )

    # From the account up: its OU, the OUs above, the domain, then the site.
    $chain = [System.Collections.Generic.List[GPOToolsSom]]::new()
    for ($node = $Som; $node; $node = $node.Parent) { $chain.Add($node) }
    if ($Site) { $chain.Add($Site) }
    # The enforced links, from the site down: the highest wins.
    for ($index = $chain.Count - 1; $index -ge 0; $index--) {
        foreach ($link in @($chain[$index].Links | Where-Object Enforced | Sort-Object Order)) { [pscustomobject]@{ Link = $link; Som = $chain[$index]; Enforced = $true } }
    }
    # The others, from the OU up, until a SOM that blocks the inheritance (its links included).
    foreach ($node in $chain) {
        foreach ($link in @($node.Links | Where-Object { -not $_.Enforced } | Sort-Object Order)) { [pscustomobject]@{ Link = $link; Som = $node; Enforced = $false } }
        if ($node.BlockInheritance) { break }
    }
}

# The SOM an object of the directory is in: the nearest domain or OU above its distinguished name
# (CN=Computers and CN=Users are not OUs: their objects are in the domain).
function Find-PSGPOModelingSom {
    [CmdletBinding()]
    [OutputType([GPOToolsSom])]
    param(
        [Parameter(Mandatory)] [GPOToolsDirectory]$Directory,
        [Parameter(Mandatory)] [string]$DistinguishedName
    )

    for ($dn = [GPOToolsDirectory]::GetParentDistinguishedName($DistinguishedName); $dn; $dn = [GPOToolsDirectory]::GetParentDistinguishedName($dn)) {
        $som = $Directory.FindSom($dn)
        if ($som) { return $som }
    }
    $Directory.Domain
}

# A computer or a user of the modeling: Name, DistinguishedName, Som, Sids (its token) and
# Container ($true: a domain or an OU given, the token its groups given). An account is read from
# the domain (its SID, its groups with the nested ones: tokenGroups); a directory in memory has
# no accounts, only its containers.
function Get-PSGPOModelingAccount {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsDirectory]$Directory,
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [ValidateSet('Computer', 'User')] [string]$Kind,
        [string[]]$Group = @()
    )

    $sids = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($sid in $script:PSGPOModelingTokenSids) { [void]$sids.Add($sid) }
    foreach ($item in @($Group | Where-Object { $_ })) {
        $account = Resolve-PSGPOApplyTo -Directory $Directory -Name $item
        if (-not $account) { throw "No group named '$item' in $($Directory.DomainName)." }
        [void]$sids.Add($account.Sid)
        [void]$sids.Add($account.Name)
    }
    $Name = $Name.Trim()
    $container = if ($Name -match '=') { $Directory.FindSom($Name) } elseif ([string]::Equals($Name, $Directory.DomainName, [System.StringComparison]::OrdinalIgnoreCase)) { $Directory.Domain }
    if ($container) {
        # As GPMC for a container: the group of every computer, or of every user, of the domain.
        $every = Resolve-PSGPOApplyTo -Directory $Directory -Name $(if ($Kind -eq 'Computer') { 'Domain Computers' } else { 'Domain Users' })
        if ($every) { [void]$sids.Add($every.Sid); [void]$sids.Add($every.Name) }
        return [pscustomobject]@{ Name = $container.Name; DistinguishedName = $container.DistinguishedName; Som = $container; Sids = $sids; Container = $true }
    }
    if ($Directory -isnot [GPOToolsLdapDirectory]) {
        throw "This directory has no accounts: give the domain or an OU as the $($Kind.ToLowerInvariant()), its groups with -$($Kind)Group."
    }
    $connection = New-PSGPODirectoryConnection -Directory $Directory
    try {
        $domainDn = $Directory.Domain.DistinguishedName
        $entry = if ($Name -match '^[A-Za-z]+=.+,(?i:DC)=') {
            @(Invoke-PSGPOLdapBinarySearch -Connection $connection -SearchBase $Name -Scope Base -Attribute 'objectSid', 'objectClass') | Select-Object -First 1
        } else {
            $account = ($Name -split '\\')[-1]
            if ($Kind -eq 'Computer' -and -not $account.EndsWith('$')) { $account += '$' }
            @(Invoke-PSGPOLdapBinarySearch -Connection $connection -SearchBase $domainDn -Filter "(sAMAccountName=$(ConvertTo-PSGPOLdapFilterValue $account))" -Attribute 'objectSid', 'objectClass') | Select-Object -First 1
        }
        if (-not $entry -or -not $entry.Values['objectSid']) { throw "No $($Kind.ToLowerInvariant()) named '$Name' in $($Directory.DomainName)." }
        $classes = @($entry.Values['objectClass'] | ForEach-Object { if ($_ -is [byte[]]) { [System.Text.Encoding]::UTF8.GetString($_) } else { "$_" } })
        if ($Kind -eq 'Computer' -and $classes -notcontains 'computer') { throw "'$Name' is not a computer of $($Directory.DomainName)." }
        if ($Kind -eq 'User' -and ($classes -notcontains 'user' -or $classes -contains 'computer')) { throw "'$Name' is not a user of $($Directory.DomainName)." }
        # Not in @(): the function returns its array as one object already.
        $groupSids = Get-PSGPOAccountGroupSid -Connection $connection -DomainDistinguishedName $domainDn -Account $entry.DistinguishedName
        foreach ($sid in $groupSids) { [void]$sids.Add($sid) }
    } finally {
        $connection.Dispose()
    }
    $rdn = [regex]::Match($entry.DistinguishedName, '^[^=]+=((?:\\.|[^,])+)').Groups[1].Value -replace '\\(.)', '$1'
    [pscustomobject]@{ Name = $rdn; DistinguishedName = $entry.DistinguishedName; Som = (Find-PSGPOModelingSom -Directory $Directory -DistinguishedName $entry.DistinguishedName); Sids = $sids; Container = $false }
}

# A part of a GPO without settings, which Windows does not apply (Empty): its version is 0, or, for
# a domain read, no client-side extension declares it (a GPO whose settings of that part were all
# removed keeps its version; seen on a Windows lab). A JSON description gives no extensions: its
# version alone.
function Test-PSGPOModelingEmpty {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [GPOToolsDirectory]$Directory,
        [Parameter(Mandatory)] [GPOToolsGpo]$Gpo,
        [Parameter(Mandatory)] [ValidateSet('Computer', 'User')] [string]$Scope
    )

    $version = if ($Scope -eq 'Computer') { $Gpo.GetComputerVersion() } else { $Gpo.GetUserVersion() }
    if (-not $version) { return $true }
    $extensions = if ($Scope -eq 'Computer') { $Gpo.MachineExtensionNames } else { $Gpo.UserExtensionNames }
    $Directory -is [GPOToolsLdapDirectory] -and [string]::IsNullOrWhiteSpace($extensions)
}

# Whether a token applies a GPO, as its permissions say: Applied, Denied (a deny for one of its
# SIDs), or no Apply Group Policy with Read for it.
function Test-PSGPOModelingSecurity {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]]$Permission,
        [Parameter(Mandatory)] [System.Collections.Generic.HashSet[string]]$Sids,
        # Read is enough (the computer reading a user GPO, MS16-072).
        [switch]$ReadOnly
    )

    $rows = @($Permission | Where-Object { $Sids.Contains("$($_.Sid)") -or $Sids.Contains("$($_.Name)") })
    if (@($rows | Where-Object Denied).Count) { return 'Denied' }
    $read = [uint32]0x00020094
    $reads = @($rows | Where-Object { $_.Permission -in 'GpoRead', 'GpoApply', 'GpoEdit', 'GpoEditDeleteModifySecurity' -or (([uint32]$_.Mask -band $read) -eq $read) }).Count -gt 0
    if ($ReadOnly) { return $(if ($reads) { 'Applied' } else { 'NoRead' }) }
    if ($reads -and @($rows | Where-Object Applies).Count) { return 'Applied' }
    'NoApply'
}

# The GPOs of one part (Computer or User) for a token, in the order of $Candidate: Precedence
# (among those applied, 1 wins), Name, Gpo, Link and LinkPath (where it is linked), Enforced,
# Applied, Reason, WmiFilter. $ReaderSids: the computer, which must read a user GPO.
function Get-PSGPOModelingGpo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsDirectory]$Directory,
        [Parameter(Mandatory)] [ValidateSet('Computer', 'User')] [string]$Scope,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]]$Candidate,
        [Parameter(Mandatory)] [System.Collections.Generic.HashSet[string]]$Sids,
        [System.Collections.Generic.HashSet[string]]$ReaderSids,
        [string[]]$FalseWmiFilter = @(),
        [hashtable]$PermissionCache = @{}
    )

    # A GPO linked twice applies once: its link of highest precedence.
    $appliedIds = [System.Collections.Generic.HashSet[guid]]::new()
    $precedence = 0
    foreach ($item in $Candidate) {
        $gpo = $item.Link.Gpo
        if ($gpo -and $appliedIds.Contains($gpo.Id)) { continue }
        $filter = if ($gpo) { $Directory.GetWmiFilter($gpo) }
        $reason = if (-not $gpo) { 'Not found' }
        elseif (-not $item.Link.Enabled) { 'Disabled link' }
        elseif (($Scope -eq 'Computer' -and ($gpo.Flags -band 2)) -or ($Scope -eq 'User' -and ($gpo.Flags -band 1))) { 'Disabled GPO' }
        else {
            if (-not $PermissionCache.ContainsKey($gpo.Id)) { $PermissionCache[$gpo.Id] = @($Directory.GetGpoPermissions($gpo)) }
            $security = Test-PSGPOModelingSecurity -Permission $PermissionCache[$gpo.Id] -Sids $Sids
            if ($security -eq 'Denied') { 'Denied (security)' }
            elseif ($security -ne 'Applied') { 'Not applied (security filtering)' }
            elseif ($ReaderSids -and (Test-PSGPOModelingSecurity -Permission $PermissionCache[$gpo.Id] -Sids $ReaderSids -ReadOnly) -ne 'Applied') { 'Inaccessible (the computer cannot read it, MS16-072)' }
            elseif ($null -ne $gpo.WmiFilterId -and -not $filter) { 'WMI filter not found' }
            elseif ($filter -and @($FalseWmiFilter | Where-Object { [string]::Equals($_, $filter.Name, [System.StringComparison]::OrdinalIgnoreCase) }).Count) { 'WMI filter false' }
            elseif (Test-PSGPOModelingEmpty -Directory $Directory -Gpo $gpo -Scope $Scope) { 'Empty' }
            else { 'Applied' }
        }
        $applied = $reason -eq 'Applied'
        if ($applied) { $precedence++; [void]$appliedIds.Add($gpo.Id) }
        [pscustomobject]@{
            PSTypeName = 'PSGPOTools.ModelingGpo'
            Scope = $Scope
            Precedence = if ($applied) { $precedence } else { $null }
            Name = $item.Link.GetDisplayName()
            Gpo = $gpo
            Link = $item.Som.Name
            LinkPath = $item.Som.DistinguishedName
            Enforced = $item.Enforced
            Applied = $applied
            Reason = $reason
            WmiFilter = if ($filter) { $filter.Name } else { '' }
        }
    }
}

# Loopback processing as the computer GPOs applied set it (Configure user Group Policy loopback
# processing mode: UserPolicyMode in Software\Policies\Microsoft\Windows\System, 1 Merge, 2
# Replace): the one of highest precedence. Mode (None, Merge or Replace) and Gpo.
function Get-PSGPOModelingLoopback {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsDirectory]$Directory,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]]$ComputerGpo
    )

    foreach ($row in @($ComputerGpo | Where-Object Applied | Sort-Object Precedence)) {
        $bytes = $Directory.ReadPolicyFile($row.Gpo, 'Machine')
        if (-not $bytes) { continue }
        $entry = @([GPOToolsRegistryPol]::Parse([byte[]]$bytes).Entries | Where-Object {
                [string]::Equals($_.Key, 'Software\Policies\Microsoft\Windows\System', [System.StringComparison]::OrdinalIgnoreCase) -and
                [string]::Equals($_.ValueName, 'UserPolicyMode', [System.StringComparison]::OrdinalIgnoreCase) -and $_.Data.Length -ge 4 })[0]
        if (-not $entry) { continue }
        $mode = switch ([BitConverter]::ToUInt32($entry.Data, 0)) { 1 { 'Merge' } 2 { 'Replace' } default { $null } }
        if ($mode) { return [pscustomobject]@{ Mode = $mode; Gpo = $row.Gpo } }
    }
    [pscustomobject]@{ Mode = 'None'; Gpo = $null }
}

# The modeling of a computer and a user (either may be missing), as Get-PSGPOModeling gives it.
function Get-PSGPOModelingData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsDirectory]$Directory,
        [string]$Computer,
        [string[]]$ComputerGroup = @(),
        [string]$User,
        [string[]]$UserGroup = @(),
        [string]$Site,
        [ValidateSet('', 'None', 'Merge', 'Replace')] [string]$Loopback = '',
        [string[]]$FalseWmiFilter = @()
    )

    if (-not $Computer -and -not $User) { throw 'Give a computer, a user, or both: the GPOs they would apply.' }
    $siteSom = $null
    if ($Site) {
        $siteSom = $Directory.FindSite($Site.Trim())
        if (-not $siteSom) { throw "No site named '$Site' in the forest: $(@($Directory.Sites.Name) -join ', ')." }
    }
    $cache = @{}
    $computerAccount = if ($Computer) { Get-PSGPOModelingAccount -Directory $Directory -Name $Computer -Kind Computer -Group $ComputerGroup }
    $userAccount = if ($User) { Get-PSGPOModelingAccount -Directory $Directory -Name $User -Kind User -Group $UserGroup }
    $computerGpos = @()
    $loopbackMode = [pscustomobject]@{ Mode = 'None'; Gpo = $null }
    if ($computerAccount) {
        $computerGpos = @(Get-PSGPOModelingGpo -Directory $Directory -Scope Computer -Candidate @(Get-PSGPOModelingLink -Som $computerAccount.Som -Site $siteSom) -Sids $computerAccount.Sids -FalseWmiFilter $FalseWmiFilter -PermissionCache $cache)
        $loopbackMode = if ($Loopback) { [pscustomobject]@{ Mode = $Loopback; Gpo = $null } } else { Get-PSGPOModelingLoopback -Directory $Directory -ComputerGpo $computerGpos }
    } elseif ($Loopback -and $Loopback -ne 'None') {
        throw 'Loopback processing takes the user GPOs of the computer: give the computer too.'
    }
    $userGpos = @()
    if ($userAccount) {
        $candidates = switch ($loopbackMode.Mode) {
            # The GPOs of the computer win: applied after those of the user.
            'Merge' { @(Get-PSGPOModelingLink -Som $computerAccount.Som -Site $siteSom) + @(Get-PSGPOModelingLink -Som $userAccount.Som -Site $siteSom) }
            'Replace' { @(Get-PSGPOModelingLink -Som $computerAccount.Som -Site $siteSom) }
            default { @(Get-PSGPOModelingLink -Som $userAccount.Som -Site $siteSom) }
        }
        $readers = if ($computerAccount) { $computerAccount.Sids }
        $userGpos = @(Get-PSGPOModelingGpo -Directory $Directory -Scope User -Candidate $candidates -Sids $userAccount.Sids -ReaderSids $readers -FalseWmiFilter $FalseWmiFilter -PermissionCache $cache)
    }
    [pscustomobject]@{
        PSTypeName = 'PSGPOTools.Modeling'
        Computer = if ($computerAccount) { $computerAccount.Name } else { '' }
        ComputerPath = if ($computerAccount) { $computerAccount.DistinguishedName } else { '' }
        ComputerSom = if ($computerAccount) { $computerAccount.Som.DistinguishedName } else { '' }
        User = if ($userAccount) { $userAccount.Name } else { '' }
        UserPath = if ($userAccount) { $userAccount.DistinguishedName } else { '' }
        UserSom = if ($userAccount) { $userAccount.Som.DistinguishedName } else { '' }
        Site = if ($siteSom) { $siteSom.Name } else { '' }
        Loopback = $loopbackMode.Mode
        LoopbackGpo = if ($loopbackMode.Gpo) { $loopbackMode.Gpo.DisplayName } elseif ($Loopback) { 'Given' } else { '' }
        ComputerGpos = $computerGpos
        UserGpos = $userGpos
        WmiFilters = 'Assumed true, but those given with -FalseWmiFilter'
    }
}
