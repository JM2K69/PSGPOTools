<#
    The security posture of the management of the GPOs of a domain: who can create, change and
    link GPOs beyond the Tier 0 and the delegations of the approval workflow, who owns the folders
    of SYSVOL the consoles and the computers read (Policies, the central store, the configuration of
    HGPM), and what the configuration of HGPM leaves open. Test-PSGPOSecurityPosture returns the
    findings; with -SystemLog, those of severity High go to the log of the system (event 4001), with
    a summary (event 4000), for a SIEM.

    It only reads: the descriptors of the directory and the ACLs of SYSVOL, which an account of the
    domain reads (a group managed service account of no group, in a scheduled task).

    Group Policy Creator Owners keeps the rights the domain gives it (CN=Policies, the Policies
    folder): its members are the finding, each of them outside of the Tier 0.
#>

# The rights of the directory that change an object: write a property, its DACL or its owner, and
# the generic rights that hold them.
$script:PSGPODirectoryWriteMask = [uint32](0x20 -bor 0x40000 -bor 0x80000 -bor 0x10000000 -bor 0x40000000)
# The rights of a file or folder that change it or what it holds: write and append data (create
# files and folders), write its attributes, delete what it holds, delete it, write its DACL or its
# owner, and the generic rights that hold them.
$script:PSGPOFileWriteMask = [uint32](0x2 -bor 0x4 -bor 0x10 -bor 0x40 -bor 0x100 -bor 0x10000 -bor 0x40000 -bor 0x80000 -bor 0x10000000 -bor 0x40000000)
# The classes an ACE may name (schemaIDGUID): organizationalUnit, domainDNS, groupPolicyContainer, container.
$script:PSGPOObjectClass = @{
    OrganizationalUnit = [guid]'bf967aa5-0de6-11d0-a285-00aa003049e2'
    Domain = [guid]'19195a5b-6da0-11d0-afd3-00c04fd930c9'
    Gpo = [guid]'f30e3bc2-9ff0-11d1-b603-0000f80367c1'
    Container = [guid]'bf967a8b-0de6-11d0-a285-00aa003049e2'
}
# The attributes a link writes (Block Inheritance with gPOptions), and those of a GPO that change
# what the computers apply: read from the schema (Get-PSGPOSchemaGuid).
$script:PSGPOLinkAttributeNames = @('gPLink', 'gPOptions')
$script:PSGPOGpoAttributeNames = @('gPCFileSysPath', 'gPCMachineExtensionNames', 'gPCUserExtensionNames', 'gPCWQLFilter', 'versionNumber', 'flags', 'gPCFunctionalityVersion')

# The groups of every account: Everyone, Anonymous, Authenticated Users, Network, Interactive,
# Users, Guests; Domain Users, Domain Guests, Domain Computers.
function Get-PSGPOEveryoneSid {
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory)] [string]$DomainSid)

    , [string[]]@('S-1-1-0', 'S-1-5-7', 'S-1-5-11', 'S-1-5-2', 'S-1-5-4', 'S-1-5-32-545', 'S-1-5-32-546', "$DomainSid-513", "$DomainSid-514", "$DomainSid-515")
}

# The Tier 0 of a domain: Administrator, the domain controllers, SYSTEM, and the groups the domain
# protects (AdminSDHolder): Domain Admins, Enterprise Admins, Schema Admins, Key Admins, Enterprise
# Key Admins, Administrators, Account, Server, Print and Backup Operators; and the SIDs of -Sid (the
# approvers, the owner of the approved GPOs).
function Get-PSGPOTier0Sid {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$DomainSid,
        [AllowEmptyCollection()] [string[]]$Sid = @()
    )

    $tier0 = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $domain = @('500', '512', '516', '518', '519', '526', '527' | ForEach-Object { "$DomainSid-$_" })
    $builtin = @('544', '548', '549', '550', '551' | ForEach-Object { "S-1-5-32-$_" })
    foreach ($value in $domain + $builtin + @('S-1-5-18', 'S-1-5-9') + $Sid) {
        if ($value) { [void]$tier0.Add($value) }
    }
    , $tier0
}

# Is the account of the Tier 0: one of $Tier0, or in one of them (its groups, nested ones
# included). $Cache keeps the answers of the directory.
function Test-PSGPOTier0Account {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] $Connection,
        [Parameter(Mandatory)] [string]$DomainDistinguishedName,
        [Parameter(Mandatory)] [System.Collections.Generic.HashSet[string]]$Tier0,
        [Parameter(Mandatory)] [hashtable]$Cache,
        [Parameter(Mandatory)] [string]$Sid
    )

    if ($Tier0.Contains($Sid)) { return $true }
    if ($Sid -notmatch '^S-1-5-(21|32)-') { return $false }
    if (-not $Cache.ContainsKey($Sid)) {
        # Not @(...): the function returns its array as one object.
        $groups = try { Get-PSGPOAccountGroupSid -Connection $Connection -DomainDistinguishedName $DomainDistinguishedName -Sid $Sid } catch { Write-Verbose "The groups of $Sid are not read: $($_.Exception.Message)"; [string[]]@() }
        $Cache[$Sid] = [bool]@($groups | Where-Object { $_ -and $Tier0.Contains($_) }).Count
    }
    $Cache[$Sid]
}

# The schemaIDGUID of attributes, by their lDAPDisplayName; those the schema does not have are left out.
function Get-PSGPOSchemaGuid {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)] $Connection,
        [Parameter(Mandatory)] [string[]]$Name
    )

    $rootDse = Invoke-PSGPOLdapSearch -Connection $Connection -SearchBase '' -Scope Base -Attribute 'schemaNamingContext'
    $schema = Get-PSGPOLdapValue $rootDse 'schemaNamingContext'
    if (-not $schema) { throw 'The rootDSE has no schemaNamingContext.' }
    $filter = '(|{0})' -f (-join ($Name | ForEach-Object { "(lDAPDisplayName=$(ConvertTo-PSGPOLdapFilterValue $_))" }))
    $guids = @{}
    foreach ($entry in @(Invoke-PSGPOLdapBinarySearch -Connection $Connection -SearchBase $schema -Scope OneLevel -Filter $filter -Attribute 'lDAPDisplayName', 'schemaIDGUID')) {
        if ($entry.Values['schemaIDGUID'] -and $entry.Values['lDAPDisplayName']) {
            $guids[[System.Text.Encoding]::UTF8.GetString([byte[]]$entry.Values['lDAPDisplayName'][0])] = [guid]::new([byte[]]$entry.Values['schemaIDGUID'][0])
        }
    }
    $guids
}

# The ACE gives its account the rights of $Mask on the object itself (not only on what it holds),
# for an object of the class $Class. Writing a property counts for the properties of $Property
# only (any when -AnyProperty).
function Test-PSGPOAceGrant {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [GPOToolsAce]$Ace,
        [Parameter(Mandatory)] [uint32]$Mask,
        [guid]$Class = [guid]::Empty,
        [guid[]]$Property = @(),
        [switch]$AnyProperty
    )

    if (-not $Ace.IsKnown() -or $Ace.IsDeny() -or ($Ace.Flags -band [GPOToolsAce]::InheritOnly)) { return $false }
    if (-not ($Ace.Mask -band $Mask)) { return $false }
    if ($Ace.IsObjectAce()) {
        if ($Class -ne [guid]::Empty -and $Ace.InheritedObjectType -ne [guid]::Empty -and $Ace.InheritedObjectType -ne $Class) { return $false }
        # An object ACE that writes properties names one (or a property set): the properties of
        # $Property only, unless it also writes the DACL or the owner.
        $beyond = $Ace.Mask -band ($Mask -band -bnot [uint32]0x20)
        if (-not $beyond -and -not $AnyProperty -and $Ace.ObjectType -ne [guid]::Empty -and $Property -notcontains $Ace.ObjectType) { return $false }
    }
    $true
}

# Is a folder of the SYSVOL share there?
function Test-PSGPOSysvolFolder {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [GPOToolsLdapDirectory]$Directory,
        [Parameter(Mandatory)] [string]$Path
    )

    if ($IsWindows) {
        Use-PSGPOSysvolCredential -Directory $Directory -Share 'SYSVOL'
        return Test-Path -LiteralPath "\\$($Directory.Server)\SYSVOL\$Path" -PathType Container
    }
    Assert-PSGPOKerberosOnly -Directory $Directory
    $result = Invoke-PSGPOSmbClient -Server $Directory.Server -Share 'SYSVOL' -AllowMissing -Command ('ls "{0}"' -f $Path)
    $null -ne $result
}

# The findings of the security posture of the domain: Severity (High, Medium, Low), Check,
# Target, Principal and Detail, as PSGPOTools.PostureFinding, the most severe first.
function Get-PSGPOPostureData {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [GPOToolsLdapDirectory]$Directory)

    $findings = [System.Collections.Generic.List[object]]::new()
    $add = {
        param([string]$Severity, [string]$Check, [string]$Target, [string]$Principal, [string]$Detail)
        $findings.Add([pscustomobject]@{
                PSTypeName = 'PSGPOTools.PostureFinding'
                Severity = $Severity
                Check = $Check
                Target = $Target
                Principal = $Principal
                Detail = $Detail
            })
    }
    $setting = Get-PSGPOWorkflowSetting
    $configuration = Get-PSGPOConfigurationData
    $domainDN = $Directory.Domain.DistinguishedName
    $policies = "CN=Policies,CN=System,$domainDN"
    $masks = [System.DirectoryServices.Protocols.SecurityMasks]'Owner,Dacl'
    $descriptor = { param($Entry) if ($Entry -and $Entry.Values['nTSecurityDescriptor']) { [GPOToolsSecurityDescriptor]::Parse([byte[]]$Entry.Values['nTSecurityDescriptor'][0]) } }
    $sameName = { param([string]$A, [string]$B) [string]::Equals($A, $B, [System.StringComparison]::OrdinalIgnoreCase) }

    $connection = New-PSGPODirectoryConnection -Directory $Directory
    try {
        $domain = @(Invoke-PSGPOLdapBinarySearch -Connection $connection -SearchBase $domainDN -Scope Base -Attribute 'objectSid', 'wellKnownObjects', 'nTSecurityDescriptor' -SecurityMasks $masks)[0]
        if (-not $domain -or -not $domain.Values['objectSid']) { throw "The SID of the domain $domainDN cannot be read." }
        $domainSid = ConvertFrom-PSGPOBinarySid -Bytes ([byte[]]$domain.Values['objectSid'][0])
        $everyone = Get-PSGPOEveryoneSid -DomainSid $domainSid

        # The roles of the workflow: the approvers and the owner of the approved GPOs are of the
        # Tier 0. A name that is not an account stops the workflow: said, and left out.
        $configured = @{ Approvers = @(); Creators = @(); Owner = $null }
        foreach ($role in 'Approvers', 'Creators', 'ApprovedOwner') {
            $names = switch ($role) { 'Approvers' { $setting.Approvers } 'Creators' { $setting.Creators } default { @($setting.ApprovedOwner | Where-Object { $_ }) } }
            foreach ($name in @($names)) {
                try {
                    $account = @(Find-PSGPODomainAccount -Connection $connection -DomainDistinguishedName $domainDN -Name $name)[0]
                    if ($role -eq 'ApprovedOwner') { $configured.Owner = $account } else { $configured[$role] += $account }
                } catch {
                    & $add 'High' 'Configuration' "Workflow.$role" $name "$name is not an account of the domain: the workflow cannot give its rights (it stops), and the posture is checked without it."
                }
            }
        }
        $creatorSids = @($configured.Creators | ForEach-Object { $_.Sid })
        $tier0 = Get-PSGPOTier0Sid -DomainSid $domainSid -Sid (@($configured.Approvers | ForEach-Object { $_.Sid }) + @($configured.Owner | Where-Object { $_ } | ForEach-Object { $_.Sid }))
        $cache = @{}
        $isTier0 = { param([string]$Sid) Test-PSGPOTier0Account -Connection $connection -DomainDistinguishedName $domainDN -Tier0 $tier0 -Cache $cache -Sid $Sid }

        # The attributes that count, from the schema; any attribute when it cannot be read.
        $schema = try { Get-PSGPOSchemaGuid -Connection $connection -Name ($script:PSGPOLinkAttributeNames + $script:PSGPOGpoAttributeNames) } catch { Write-Verbose "The schema is not read: $($_.Exception.Message)"; @{} }
        $linkAttributes = [guid[]]@($script:PSGPOLinkAttributeNames | Where-Object { $schema.ContainsKey($_) } | ForEach-Object { $schema[$_] })
        $gpoAttributes = [guid[]]@($script:PSGPOGpoAttributeNames | Where-Object { $schema.ContainsKey($_) } | ForEach-Object { $schema[$_] })
        $anyProperty = -not $schema.Count

        # The domain controllers OU, from the well-known objects of the domain.
        $controllersDN = "OU=Domain Controllers,$domainDN"
        foreach ($value in @($domain.Values['wellKnownObjects'])) {
            if (-not $value) { continue }
            $text = [System.Text.Encoding]::UTF8.GetString([byte[]]$value)
            if ($text -match '^B:32:A361B2FFFFD211D1AA4B00C04FD7D83A:(.+)$') { $controllersDN = $Matches[1] }
        }
        $organizationalUnits = @(Invoke-PSGPOLdapBinarySearch -Connection $connection -SearchBase $domainDN -Filter '(objectClass=organizationalUnit)' -Attribute 'nTSecurityDescriptor' -SecurityMasks $masks)
        $container = @(Invoke-PSGPOLdapBinarySearch -Connection $connection -SearchBase $policies -Scope Base -Attribute 'nTSecurityDescriptor' -SecurityMasks $masks)[0]
        $gpoEntries = @(Invoke-PSGPOLdapBinarySearch -Connection $connection -SearchBase $policies -Scope OneLevel -Filter '(objectClass=groupPolicyContainer)' -Attribute 'cn', 'nTSecurityDescriptor' -SecurityMasks $masks)

        # 1. Group Policy Creator Owners: its members create GPOs outside of the workflow.
        $creatorOwners = @(Invoke-PSGPOLdapBinarySearch -Connection $connection -SearchBase $domainDN -Filter "(objectSid=$(ConvertTo-PSGPOLdapBinaryFilter -Bytes ([GPOToolsSecurityDescriptor]::ConvertSidToBytes("$domainSid-520"))))" -Attribute 'member')[0]
        # Not @(if ...): one member (a byte array) would be unrolled into its bytes.
        $members = @()
        if ($creatorOwners -and $creatorOwners.Values['member']) { $members = $creatorOwners.Values['member'] }
        foreach ($value in $members) {
            if (-not $value) { continue }
            $member = [System.Text.Encoding]::UTF8.GetString([byte[]]$value)
            $entry = @(Invoke-PSGPOLdapBinarySearch -Connection $connection -SearchBase $member -Scope Base -Attribute 'objectSid')[0]
            $sid = if ($entry -and $entry.Values['objectSid']) { ConvertFrom-PSGPOBinarySid -Bytes ([byte[]]$entry.Values['objectSid'][0]) }
            if ($sid -and (& $isTier0 $sid)) { continue }
            $severity = if ($setting.Enabled) { 'High' } else { 'Medium' }
            & $add $severity 'GroupPolicyCreatorOwners' 'Group Policy Creator Owners' $(if ($sid) { $sid } else { $member }) "A member of Group Policy Creator Owners ($member): it creates GPOs, and owns them, outside of the approval workflow. Give the creation of GPOs with Initialize-PSGPOWorkflow instead, and keep the group empty."
        }

        # 2. The creation of GPOs: CN=Policies, beyond the creators of the workflow.
        foreach ($ace in @((& $descriptor $container).Dacl)) {
            if ($ace.Sid -eq "$domainSid-520" -or $ace.Sid -eq [GPOToolsSecurityDescriptor]::CreatorOwner) { continue }
            $create = Test-PSGPOAceGrant -Ace $ace -Mask $script:PSGPOCreateChildMask -Class $script:PSGPOObjectClass.Container
            if ($create -and $ace.IsObjectAce() -and $ace.ObjectType -ne [guid]::Empty -and $ace.ObjectType -ne $script:PSGPOObjectClass.Gpo) { $create = $false }
            $write = Test-PSGPOAceGrant -Ace $ace -Mask ([uint32](0x40000 -bor 0x80000 -bor 0x10000000)) -Class $script:PSGPOObjectClass.Container
            if (-not ($create -or $write) -or (& $isTier0 $ace.Sid)) { continue }
            if ($everyone -contains $ace.Sid) {
                & $add 'High' 'GpoCreation' $policies $ace.Sid 'A group of every account can create GPOs, or change who can (CN=Policies).'
            } elseif ($write) {
                & $add 'High' 'GpoCreation' $policies $ace.Sid 'It can change who creates GPOs: the DACL or the owner of CN=Policies.'
            } elseif ($creatorSids -notcontains $ace.Sid) {
                & $add 'High' 'GpoCreation' $policies $ace.Sid 'It creates GPOs, and is not a group of creators of the workflow (Workflow.Creators): its GPOs do not wait for an approval.'
            }
        }

        # 3 and 4. The GPOs: changed by every account; those that apply to the domain controllers
        # (linked to the domain or to their OU) changed or owned outside of the Tier 0.
        $tier0Gpo = @{}
        $soms = [System.Collections.Generic.List[object]]::new()
        $soms.Add($Directory.Domain)
        $stack = [System.Collections.Generic.Stack[object]]::new()
        foreach ($child in @($Directory.Domain.Children)) { if ($child) { $stack.Push($child) } }
        while ($stack.Count) {
            $som = $stack.Pop()
            if (& $sameName $som.DistinguishedName $controllersDN) { $soms.Add($som) }
            foreach ($child in @($som.Children)) { if ($child) { $stack.Push($child) } }
        }
        foreach ($som in $soms) {
            foreach ($link in @($som.Links | Where-Object { $_.Gpo })) { $tier0Gpo["$($link.Gpo.Id)"] = $som.Name }
        }
        foreach ($entry in $gpoEntries) {
            $id = [guid]::Empty
            if (-not $entry.Values['cn'] -or -not [guid]::TryParse([System.Text.Encoding]::UTF8.GetString([byte[]]$entry.Values['cn'][0]).Trim('{', '}'), [ref]$id)) { continue }
            $gpoDescriptor = & $descriptor $entry
            if (-not $gpoDescriptor) { continue }
            $gpo = @($Directory.Gpos | Where-Object { $_.Id -eq $id })[0]
            $name = if ($gpo) { $gpo.DisplayName } else { "{$id}" }
            $linkedTo = $tier0Gpo["$id"]
            $reported = [System.Collections.Generic.HashSet[string]]::new()
            if ($everyone -contains $gpoDescriptor.Owner) {
                & $add 'High' 'GpoEditableByAll' $name $gpoDescriptor.Owner 'A group of every account owns the GPO: any account can change it, and its permissions.'
                [void]$reported.Add($gpoDescriptor.Owner)
            } elseif ($linkedTo -and $gpoDescriptor.Owner -and -not (& $isTier0 $gpoDescriptor.Owner)) {
                & $add 'High' 'Tier0Gpo' $name $gpoDescriptor.Owner "It owns the GPO, linked to $linkedTo, which applies to the domain controllers: it can change the GPO and its permissions, and so the domain controllers."
                [void]$reported.Add($gpoDescriptor.Owner)
            }
            foreach ($ace in @($gpoDescriptor.Dacl)) {
                if ($reported.Contains($ace.Sid) -or $ace.Sid -eq [GPOToolsSecurityDescriptor]::CreatorOwner) { continue }
                if (-not (Test-PSGPOAceGrant -Ace $ace -Mask $script:PSGPODirectoryWriteMask -Class $script:PSGPOObjectClass.Gpo -Property $gpoAttributes -AnyProperty:$anyProperty)) { continue }
                if ($everyone -contains $ace.Sid) {
                    & $add 'High' 'GpoEditableByAll' $name $ace.Sid 'A group of every account can change the GPO: every account can change what the computers it applies to run.'
                    [void]$reported.Add($ace.Sid)
                } elseif ($linkedTo -and -not (& $isTier0 $ace.Sid)) {
                    & $add 'High' 'Tier0Gpo' $name $ace.Sid "It can change the GPO, linked to $linkedTo, which applies to the domain controllers: an account outside of the Tier 0 controls them."
                    [void]$reported.Add($ace.Sid)
                }
            }
        }

        # 5. The links: on the domain and the domain controllers outside of the Tier 0, anywhere by
        # every account.
        $targets = @(@{ Name = $Directory.DomainName; Entry = $domain; Class = $script:PSGPOObjectClass.Domain; Tier0 = $true }) +
            @(foreach ($entry in $organizationalUnits) {
                    @{ Name = $entry.DistinguishedName; Entry = $entry; Class = $script:PSGPOObjectClass.OrganizationalUnit; Tier0 = (& $sameName $entry.DistinguishedName $controllersDN) }
                })
        if (-not @($organizationalUnits | Where-Object { & $sameName $_.DistinguishedName $controllersDN }).Count) {
            # Not an OU (moved, or a container): read on its own.
            $controllers = @(try { Invoke-PSGPOLdapBinarySearch -Connection $connection -SearchBase $controllersDN -Scope Base -Attribute 'nTSecurityDescriptor' -SecurityMasks $masks } catch { Write-Verbose "$controllersDN is not read: $($_.Exception.Message)" })[0]
            if ($controllers) { $targets += @{ Name = $controllersDN; Entry = $controllers; Class = $script:PSGPOObjectClass.OrganizationalUnit; Tier0 = $true } }
        }
        foreach ($target in $targets) {
            $targetDescriptor = & $descriptor $target.Entry
            if (-not $targetDescriptor) { continue }
            $reported = [System.Collections.Generic.HashSet[string]]::new()
            foreach ($ace in @($targetDescriptor.Dacl)) {
                if ($reported.Contains($ace.Sid) -or $ace.Sid -eq [GPOToolsSecurityDescriptor]::CreatorOwner) { continue }
                if (-not (Test-PSGPOAceGrant -Ace $ace -Mask $script:PSGPODirectoryWriteMask -Class $target.Class -Property $linkAttributes -AnyProperty:$anyProperty)) { continue }
                if ($everyone -contains $ace.Sid) {
                    & $add 'High' 'LinkByAll' $target.Name $ace.Sid 'A group of every account can link GPOs here, or block their inheritance.'
                    [void]$reported.Add($ace.Sid)
                } elseif ($target.Tier0 -and -not (& $isTier0 $ace.Sid)) {
                    & $add 'High' 'Tier0Link' $target.Name $ace.Sid 'It can link a GPO here, or block the inheritance: the GPOs it links apply to the domain controllers.'
                    [void]$reported.Add($ace.Sid)
                }
            }
        }

        # 6 to 8. The folders of SYSVOL: Policies, the central store, the configuration of HGPM.
        $folders = @(
            @{ Check = 'PoliciesFolder'; Path = "$($Directory.DomainName)\Policies"; Why = 'the folders of the GPOs, which the computers apply' }
            @{ Check = 'CentralStore'; Path = "$($Directory.DomainName)\Policies\PolicyDefinitions"; Why = 'the central store, the ADMX files every console reads' }
            @{ Check = 'ConfigurationFolder'; Path = "$($Directory.DomainName)\PSGPOTools"; Why = 'the configuration of HGPM: its workflow, its roles' }
        )
        foreach ($folder in $folders) {
            $target = "\\$($Directory.Server)\SYSVOL\$($folder.Path)"
            try {
                if (-not (Test-PSGPOSysvolFolder -Directory $Directory -Path $folder.Path)) {
                    if ($folder.Check -eq 'CentralStore' -and $creatorSids.Count) {
                        & $add 'Medium' 'CentralStore' $target '' 'There is no central store, and the creators of the workflow create folders in Policies: one of them could create it, own it, and choose the ADMX files every console reads. Create it (Install-PSGPOAdmx -CentralStore, or a copy of PolicyDefinitions), owned by the Tier 0.'
                    }
                    continue
                }
                $acl = Get-PSGPOSysvolItemAcl -Directory $Directory -Share 'SYSVOL' -Path $folder.Path
            } catch {
                & $add 'Medium' $folder.Check $target '' "Its permissions cannot be read ($($_.Exception.GetBaseException().Message)): $($folder.Why) are not checked."
                continue
            }
            $reported = [System.Collections.Generic.HashSet[string]]::new()
            if ($acl.Owner -and -not (& $isTier0 $acl.Owner)) {
                & $add 'High' $folder.Check $target $acl.Owner "It owns $($folder.Why): it can change them, and their permissions."
                [void]$reported.Add($acl.Owner)
            }
            foreach ($ace in @($acl.Dacl)) {
                if ($reported.Contains($ace.Sid) -or $ace.Sid -eq [GPOToolsSecurityDescriptor]::CreatorOwner -or $ace.Sid -eq "$domainSid-520") { continue }
                if (-not (Test-PSGPOAceGrant -Ace $ace -Mask $script:PSGPOFileWriteMask)) { continue }
                # The creators of the workflow create folders in Policies, this folder only.
                $onlyFolders = ($ace.Mask -band $script:PSGPOFileWriteMask) -eq 0x4 -and -not ($ace.Flags -band ([GPOToolsAce]::ObjectInherit -bor [GPOToolsAce]::ContainerInherit))
                if ($folder.Check -eq 'PoliciesFolder' -and $onlyFolders -and $creatorSids -contains $ace.Sid) { continue }
                $everyoneAce = $everyone -contains $ace.Sid
                if (-not $everyoneAce -and (& $isTier0 $ace.Sid)) { continue }
                $detail = if ($onlyFolders -and $folder.Check -eq 'PoliciesFolder') { 'It creates folders in Policies, and is not a group of creators of the workflow.' } else { "It can change $($folder.Why)." }
                & $add 'High' $folder.Check $target $ace.Sid $(if ($everyoneAce) { "A group of every account. $detail" } else { $detail })
                [void]$reported.Add($ace.Sid)
            }
        }

        # The names of the accounts found.
        $names = Resolve-PSGPODomainSid -Connection $connection -DomainDistinguishedName $domainDN -Sid @($findings | Where-Object { $_.Principal -match '^S-1-' } | ForEach-Object { $_.Principal })
    } finally {
        $connection.Dispose()
    }
    foreach ($finding in $findings) { if ($finding.Principal -and $names.ContainsKey($finding.Principal)) { $finding.Principal = $names[$finding.Principal] } }

    # 9 to 11. The configuration of HGPM: its workflow, its logs.
    if ($setting.Enabled) {
        if ($configured.Owner) {
            foreach ($problem in @(Test-PSGPOWorkflowRole -Approvers $configured.Approvers -Creators $configured.Creators -Owner $configured.Owner -DomainSid $domainSid)) {
                & $add 'High' 'WorkflowRoles' 'Workflow' '' $problem
            }
        }
    } else {
        & $add 'Low' 'Workflow' 'Workflow.Enabled' '' 'The approval workflow is off: a change of a GPO applies without being approved.'
    }
    if (-not $configuration.Audit.Enabled -or -not "$($configuration.Audit.Path)".Trim()) {
        & $add 'Low' 'AuditLog' 'Audit.Path' '' 'There is no central audit log (Audit.Enabled, Audit.Path): the changes are only in the backups of each account.'
    }
    if ($configuration.Log.SystemLog -eq $false) {
        & $add 'Low' 'SystemLog' 'Log.SystemLog' '' 'Nothing goes to the log of the system: a SIEM sees neither the changes nor the findings of this check.'
    }
    $order = @{ High = 0; Medium = 1; Low = 2 }
    , @($findings | Sort-Object { $order[$_.Severity] }, Check, Target, Principal)
}
