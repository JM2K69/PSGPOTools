<#
    WMI filters of a domain, as GPMC handles them: msWMI-Som objects in
    CN=SOM,CN=WMIPolicy,CN=System,<domain>, named after their Id ({GUID}), with their name
    (msWMI-Name), description (msWMI-Parm1) and queries (msWMI-Parm2). A GPO is linked to one by
    its gPCWQLFilter: [<domain>;{<Id>};0].

    msWMI-Parm2 holds the number of queries, then each query: 3;<length of the namespace>;<length
    of the query>;WQL;<namespace>;<query>; (the lengths, in characters, tell where a query that
    holds a semicolon ends).
#>

# The field of msWMI-Parm2 at $Position, up to the next semicolon; $Position moves after it.
function Read-PSGPOWmiField {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [string]$Text, [Parameter(Mandatory)] [ref]$Position, [int]$Length = -1)

    $end = if ($Length -ge 0) { $Position.Value + $Length } else { $Text.IndexOf(';', $Position.Value) }
    if ($end -lt 0 -or $end -ge $Text.Length -or $Text[$end] -ne ';') { throw "Not the queries of a WMI filter: '$Text'." }
    $field = $Text.Substring($Position.Value, $end - $Position.Value)
    $Position.Value = $end + 1
    $field
}

# The queries of msWMI-Parm2: Namespace and Query.
function ConvertFrom-PSGPOWmiQueryText {
    [CmdletBinding()]
    param([AllowNull()] [AllowEmptyString()] [string]$Text)

    if (-not $Text) { return }
    $position = 0
    $count = [int](Read-PSGPOWmiField -Text $Text -Position ([ref]$position))
    for ($i = 0; $i -lt $count; $i++) {
        $null = Read-PSGPOWmiField -Text $Text -Position ([ref]$position)
        $namespaceLength = [int](Read-PSGPOWmiField -Text $Text -Position ([ref]$position))
        $queryLength = [int](Read-PSGPOWmiField -Text $Text -Position ([ref]$position))
        $null = Read-PSGPOWmiField -Text $Text -Position ([ref]$position)
        $namespace = Read-PSGPOWmiField -Text $Text -Position ([ref]$position) -Length $namespaceLength
        $query = Read-PSGPOWmiField -Text $Text -Position ([ref]$position) -Length $queryLength
        [pscustomobject]@{ Namespace = $namespace; Query = $query }
    }
}

# msWMI-Parm2 of queries (Namespace and Query).
function ConvertTo-PSGPOWmiQueryText {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [object[]]$Query)

    $text = [System.Text.StringBuilder]::new("$(@($Query).Count);")
    foreach ($item in $Query) {
        [void]$text.AppendFormat('3;{0};{1};WQL;{2};{3};', $item.Namespace.Length, $item.Query.Length, $item.Namespace, $item.Query)
    }
    $text.ToString()
}

# The Id of the WMI filter a gPCWQLFilter value names; $null without one.
function ConvertFrom-PSGPOWqlFilterLink {
    [CmdletBinding()]
    param([AllowNull()] [AllowEmptyString()] [string]$Value)

    $id = [guid]::Empty
    if ("$Value" -match '^\[[^;]*;\{?([0-9a-fA-F-]{36})\}?;\d+\]$' -and [guid]::TryParse($Matches[1], [ref]$id)) { return $id }
    $null
}

# The WMI filters of the domain, into the directory; a domain without the container has none.
function Read-PSGPODomainWmiFilter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Connection,
        [Parameter(Mandatory)] [GPOToolsDirectory]$Directory
    )

    $base = "CN=SOM,CN=WMIPolicy,CN=System,$($Directory.Domain.DistinguishedName)"
    $entries = @(Invoke-PSGPOLdapSearch -Connection $Connection -SearchBase $base -Scope OneLevel -Filter '(objectClass=msWMI-Som)' `
            -Attribute 'msWMI-ID', 'msWMI-Name', 'msWMI-Parm1', 'msWMI-Parm2' -AllowMissing)
    $Directory.WmiFilters.Clear()
    foreach ($entry in $entries) {
        $id = [guid]::Empty
        if (-not [guid]::TryParse("$(Get-PSGPOLdapValue $entry 'msWMI-ID')".Trim('{', '}'), [ref]$id)) {
            Write-Warning "WMI filter ignored, its Id is not a GUID: $($entry.DistinguishedName)"
            continue
        }
        $filter = [GPOToolsWmiFilter]::new()
        $filter.Id = $id
        $filter.DistinguishedName = $entry.DistinguishedName
        $filter.Name = Get-PSGPOLdapValue $entry 'msWMI-Name'
        $filter.Description = Get-PSGPOLdapValue $entry 'msWMI-Parm1'
        try {
            $filter.Queries = @(ConvertFrom-PSGPOWmiQueryText -Text (Get-PSGPOLdapValue $entry 'msWMI-Parm2'))
        } catch {
            Write-Warning "The queries of the WMI filter '$($filter.Name)' cannot be read: $($_.Exception.Message)"
        }
        $Directory.WmiFilters.Add($filter)
    }
    $Directory.WmiFilters.Sort([System.Comparison[GPOToolsWmiFilter]] { param($a, $b) [string]::Compare($a.Name, $b.Name, $true) })
}

# Links a GPO to a WMI filter in the domain ($null: none), refused if its gPCWQLFilter changed
# meanwhile.
function Set-PSGPODomainWmiFilterLink {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsLdapDirectory]$Directory,
        [Parameter(Mandatory)] [GPOToolsGpo]$Gpo,
        [AllowNull()] [GPOToolsWmiFilter]$Filter
    )

    $connection = New-PSGPODirectoryConnection -Directory $Directory
    try {
        $entry = Invoke-PSGPOLdapSearch -Connection $connection -SearchBase $Gpo.DistinguishedName -Scope Base -Attribute 'gPCWQLFilter' -AllowMissing
        if (-not $entry) { throw "The GPO $($Gpo.DisplayName) is not in the domain anymore." }
        $old = Get-PSGPOLdapValue $entry 'gPCWQLFilter'
        $new = if ($Filter) { '[{0};{{{1}}};0]' -f $Directory.DomainName, $Filter.Id.ToString().ToUpperInvariant() } else { '' }
        if ("$old" -eq $new) { return }
        $request = [System.DirectoryServices.Protocols.ModifyRequest]::new()
        $request.DistinguishedName = $Gpo.DistinguishedName
        Add-PSGPOLdapValueChange -Request $request -Name 'gPCWQLFilter' -Old $old -New $new
        try {
            [void]$connection.SendRequest($request)
        } catch {
            $base = $_.Exception.GetBaseException()
            if ($base.PSObject.Properties['Response'] -and $base.Response.ResultCode -in 'NoSuchAttribute', 'AttributeOrValueExists') {
                throw "The WMI filter of the GPO $($Gpo.DisplayName) changed in the domain meanwhile: read the domain again, then try again."
            }
            if ($base.PSObject.Properties['Response'] -and $base.Response.ResultCode -eq 'InsufficientAccessRights') {
                throw "The account cannot change the WMI filter of the GPO '$($Gpo.DisplayName)': $($base.Message)"
            }
            throw
        }
    } finally {
        $connection.Dispose()
    }
    Write-Verbose "GPO '$($Gpo.DisplayName)': WMI filter $(if ($Filter) { "'$($Filter.Name)'" } else { 'none' })."
}

# Creates a WMI filter in the domain, as GPMC does.
function New-PSGPODomainWmiFilter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsLdapDirectory]$Directory,
        [Parameter(Mandatory)] [GPOToolsWmiFilter]$Filter
    )

    $now = [datetime]::UtcNow.ToString('yyyyMMddHHmmss.ffffff-000', [cultureinfo]::InvariantCulture)
    $request = [System.DirectoryServices.Protocols.AddRequest]::new($Filter.DistinguishedName, 'msWMI-Som')
    $values = [ordered]@{
        'msWMI-ID' = '{' + $Filter.Id.ToString().ToUpperInvariant() + '}'
        'msWMI-Name' = $Filter.Name
        'msWMI-Parm2' = ConvertTo-PSGPOWmiQueryText -Query $Filter.Queries
        'msWMI-Author' = if ($Directory.Account) { $Directory.Account } else { [Environment]::UserName }
        'msWMI-CreationDate' = $now
        'msWMI-ChangeDate' = $now
        'showInAdvancedViewOnly' = 'TRUE'
    }
    if ($Filter.Description) { $values['msWMI-Parm1'] = $Filter.Description }
    foreach ($name in $values.Keys) { [void]$request.Attributes.Add([System.DirectoryServices.Protocols.DirectoryAttribute]::new($name, [string]$values[$name])) }
    $connection = New-PSGPODirectoryConnection -Directory $Directory
    try {
        [void]$connection.SendRequest($request)
    } catch {
        $base = $_.Exception.GetBaseException()
        if ($base.PSObject.Properties['Response'] -and $base.Response.ResultCode -eq 'InsufficientAccessRights') {
            throw "The account cannot create WMI filters in $($Directory.DomainName): $($base.Message)"
        }
        throw
    } finally {
        $connection.Dispose()
    }
    Write-Verbose "WMI filter '$($Filter.Name)' created: $($Filter.DistinguishedName)."
}

# Writes the name, description and queries of a WMI filter ($Changed) in the domain, as GPMC does,
# refused if the filter changed there since it was read ($Filter).
function Set-PSGPODomainWmiFilter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsLdapDirectory]$Directory,
        [Parameter(Mandatory)] [GPOToolsWmiFilter]$Filter,
        [Parameter(Mandatory)] [GPOToolsWmiFilter]$Changed
    )

    $connection = New-PSGPODirectoryConnection -Directory $Directory
    try {
        $entry = Invoke-PSGPOLdapSearch -Connection $connection -SearchBase $Filter.DistinguishedName -Scope Base -Attribute 'msWMI-Name', 'msWMI-Parm1', 'msWMI-Parm2' -AllowMissing
        if (-not $entry) { throw "The WMI filter '$($Filter.Name)' is not in the domain anymore." }
        $old = @{}
        foreach ($name in 'msWMI-Name', 'msWMI-Parm1', 'msWMI-Parm2') { $old[$name] = Get-PSGPOLdapValue $entry $name }
        $queries = try { (@(ConvertFrom-PSGPOWmiQueryText -Text $old['msWMI-Parm2']) | ForEach-Object { "$($_.Namespace): $($_.Query)" }) -join '; ' } catch { $null }
        if ("$($old['msWMI-Name'])" -cne $Filter.Name -or "$($old['msWMI-Parm1'])" -cne "$($Filter.Description)" -or "$queries" -cne $Filter.GetQueryText()) {
            throw "The WMI filter '$($Filter.Name)' changed in the domain meanwhile: read the domain again, then try again."
        }
        $request = [System.DirectoryServices.Protocols.ModifyRequest]::new()
        $request.DistinguishedName = $Filter.DistinguishedName
        # The values read are removed: the change is refused if another one came in between.
        Add-PSGPOLdapValueChange -Request $request -Name 'msWMI-Name' -Old $old['msWMI-Name'] -New $Changed.Name
        Add-PSGPOLdapValueChange -Request $request -Name 'msWMI-Parm1' -Old $old['msWMI-Parm1'] -New $Changed.Description
        Add-PSGPOLdapValueChange -Request $request -Name 'msWMI-Parm2' -Old $old['msWMI-Parm2'] -New (ConvertTo-PSGPOWmiQueryText -Query $Changed.Queries)
        if (-not $request.Modifications.Count) { return }
        $date = [System.DirectoryServices.Protocols.DirectoryAttributeModification]::new()
        $date.Name = 'msWMI-ChangeDate'
        $date.Operation = [System.DirectoryServices.Protocols.DirectoryAttributeOperation]::Replace
        [void]$date.Add([datetime]::UtcNow.ToString('yyyyMMddHHmmss.ffffff-000', [cultureinfo]::InvariantCulture))
        [void]$request.Modifications.Add($date)
        try {
            [void]$connection.SendRequest($request)
        } catch {
            $base = $_.Exception.GetBaseException()
            if ($base.PSObject.Properties['Response'] -and $base.Response.ResultCode -in 'NoSuchAttribute', 'AttributeOrValueExists') {
                throw "The WMI filter '$($Filter.Name)' changed in the domain meanwhile: read the domain again, then try again."
            }
            if ($base.PSObject.Properties['Response'] -and $base.Response.ResultCode -eq 'InsufficientAccessRights') {
                throw "The account cannot change the WMI filter '$($Filter.Name)': $($base.Message)"
            }
            throw
        }
    } finally {
        $connection.Dispose()
    }
    Write-Verbose "WMI filter '$($Changed.Name)' changed: $($Changed.GetQueryText())."
}

function Remove-PSGPODomainWmiFilter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [GPOToolsLdapDirectory]$Directory,
        [Parameter(Mandatory)] [GPOToolsWmiFilter]$Filter
    )

    $connection = New-PSGPODirectoryConnection -Directory $Directory
    try {
        # No GPO of the domain may use it, those this console cannot see included.
        $users = @(Invoke-PSGPOLdapSearch -Connection $connection -SearchBase "CN=Policies,CN=System,$($Directory.Domain.DistinguishedName)" -Scope OneLevel `
                -Filter "(gPCWQLFilter=*$(ConvertTo-PSGPOLdapFilterValue $Filter.Id.ToString())*)" -Attribute 'displayName')
        if ($users.Count) { throw "The WMI filter '$($Filter.Name)' is used by $(@($users | ForEach-Object { Get-PSGPOLdapValue $_ 'displayName' }) -join ', '): it is not deleted." }
        try {
            [void]$connection.SendRequest([System.DirectoryServices.Protocols.DeleteRequest]::new($Filter.DistinguishedName))
        } catch {
            $base = $_.Exception.GetBaseException()
            if ($base.PSObject.Properties['Response'] -and $base.Response.ResultCode -eq 'InsufficientAccessRights') {
                throw "The account cannot delete the WMI filter '$($Filter.Name)': $($base.Message)"
            }
            throw
        }
    } finally {
        $connection.Dispose()
    }
    Write-Verbose "WMI filter '$($Filter.Name)' deleted."
}
