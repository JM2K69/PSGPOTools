<#
    Group Policy Results, as GPMC: what a computer and a user applied the last time, as the computer
    logged it. Windows: gpresult /x (the RSoP of the computer, XML in UTF-16), locally or on another
    computer (/s). Linux, a member of a Samba domain: samba-gpupdate --rsop, which reads the policy
    with the machine account (root). A file of either, made elsewhere, is read the same way.
    Group Policy Update: gpupdate (Invoke-GPUpdate for another computer, as GPMC), samba-gpupdate.
#>

# The GPOs of one part of a gpresult /x document, as GPMC shows them: Precedence (among those
# applied, 1 wins), Name, Id, Applied, Reason, Link (the path of where it is linked), LinkOrder,
# Enforced, VersionDirectory, VersionSysvol, SecurityFilter.
function ConvertFrom-PSGPOGpresultGpo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [System.Xml.XmlElement]$Part,
        [Parameter(Mandatory)] [ValidateSet('Computer', 'User')] [string]$Scope,
        [Parameter(Mandatory)] [System.Xml.XmlNamespaceManager]$Namespace
    )

    $value = { param($Node, [string]$Path) $found = $Node.SelectSingleNode($Path, $Namespace); if ($found) { $found.InnerText } else { '' } }
    $gpos = foreach ($node in @($Part.SelectNodes('r:GPO', $Namespace))) {
        $applied = [int](& $value $node 'r:Link/r:AppliedOrder')
        $versionDirectory = [int](& $value $node 'r:VersionDirectory')
        $versionSysvol = [int](& $value $node 'r:VersionSysvol')
        $reason = if ($applied -gt 0) { 'Applied' }
        elseif ((& $value $node 'r:Link/r:Enabled') -eq 'false') { 'Disabled link' }
        elseif ((& $value $node 'r:Enabled') -eq 'false') { 'Disabled GPO' }
        elseif ((& $value $node 'r:AccessDenied') -eq 'true') { 'Denied (security)' }
        elseif (-not $versionDirectory -and -not $versionSysvol) { 'Empty' }
        elseif ((& $value $node 'r:FilterAllowed') -eq 'false') { 'WMI filter false' }
        elseif ((& $value $node 'r:IsValid') -eq 'false') { 'Not valid' }
        else { 'Not applied' }
        # In the namespace of the types of GPMC, not of the RSoP: by its local name.
        $identifier = & $value $node "r:Path/*[local-name()='Identifier']"
        $id = [guid]::Empty
        [pscustomobject]@{
            PSTypeName = 'PSGPOTools.ResultGpo'
            Scope = $Scope
            AppliedOrder = $applied
            Precedence = $null
            Name = & $value $node 'r:Name'
            Id = if ([guid]::TryParse($identifier.Trim('{', '}'), [ref]$id)) { $id } else { $null }
            Applied = $applied -gt 0
            Reason = $reason
            Link = & $value $node 'r:Link/r:SOMPath'
            LinkOrder = [int](& $value $node 'r:Link/r:LinkOrder')
            Enforced = (& $value $node 'r:Link/r:NoOverride') -eq 'true'
            VersionDirectory = $versionDirectory
            VersionSysvol = $versionSysvol
            SecurityFilter = @($node.SelectNodes('r:SecurityFilter', $Namespace) | ForEach-Object InnerText)
        }
    }
    # Applied last, wins: the precedence of GPMC.
    $applied = @($gpos | Where-Object Applied | Sort-Object AppliedOrder -Descending)
    for ($index = 0; $index -lt $applied.Count; $index++) { $applied[$index].Precedence = $index + 1 }
    @($applied) + @($gpos | Where-Object { -not $_.Applied })
}

# The results of gpresult /x (its XML, UTF-16 or not), as Get-PSGPOResult gives them.
function ConvertFrom-PSGPOGpresultXml {
    [CmdletBinding()]
    [OutputType('PSGPOTools.Result')]
    param([Parameter(Mandatory)] [string]$Xml)

    $settings = [System.Xml.XmlReaderSettings]::new()
    $settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
    $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($Xml), $settings)
    $document = [System.Xml.XmlDocument]::new()
    try { $document.Load($reader) } finally { $reader.Dispose() }
    $namespace = [System.Xml.XmlNamespaceManager]::new($document.NameTable)
    $namespace.AddNamespace('r', 'http://www.microsoft.com/GroupPolicy/Rsop')
    $root = $document.SelectSingleNode('/r:Rsop', $namespace)
    if (-not $root) { throw 'This is not the result of gpresult /x: it has no <Rsop> element.' }
    $value = { param($Node, [string]$Path) if (-not $Node) { return '' }; $found = $Node.SelectSingleNode($Path, $namespace); if ($found) { $found.InnerText } else { '' } }
    $computer = $root.SelectSingleNode('r:ComputerResults', $namespace)
    $user = $root.SelectSingleNode('r:UserResults', $namespace)
    # Their SID and Name in the namespace of the types of GPMC: by their local name.
    $groups = { param($Part) if ($Part) { @($Part.SelectNodes('r:SecurityGroup', $namespace) | ForEach-Object { [pscustomobject]@{ Name = & $value $_ "*[local-name()='Name']"; Sid = & $value $_ "*[local-name()='SID']" } }) } else { @() } }
    $extensions = {
        param($Part)
        if (-not $Part) { return @() }
        @($Part.SelectNodes('r:ExtensionStatus', $namespace) | ForEach-Object {
                [pscustomobject]@{ Name = & $value $_ 'r:Name'; Id = & $value $_ 'r:Identifier'; EndTime = & $value $_ 'r:EndTime'; Status = & $value $_ 'r:LoggingStatus'; Error = [int](& $value $_ 'r:Error') }
            })
    }
    [pscustomobject]@{
        PSTypeName = 'PSGPOTools.Result'
        Source = 'gpresult'
        ReadTime = & $value $root 'r:ReadTime'
        Computer = & $value $computer 'r:Name'
        ComputerSom = & $value $computer 'r:SOM'
        User = & $value $user 'r:Name'
        UserSom = & $value $user 'r:SOM'
        Site = if ($computer) { & $value $computer 'r:Site' } else { & $value $user 'r:Site' }
        ComputerGpos = if ($computer) { @(ConvertFrom-PSGPOGpresultGpo -Part $computer -Scope Computer -Namespace $namespace) } else { @() }
        UserGpos = if ($user) { @(ConvertFrom-PSGPOGpresultGpo -Part $user -Scope User -Namespace $namespace) } else { @() }
        ComputerGroups = & $groups $computer
        UserGroups = & $groups $user
        ComputerExtensions = & $extensions $computer
        UserExtensions = & $extensions $user
        Settings = @()
    }
}

# The GPOs and their settings in what samba-gpupdate --rsop prints: GPOs (in the order they apply,
# the last wins) and Settings (Gpo, Extension, PolicyType, Name, Value).
function ConvertFrom-PSGPOSambaRsop {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [AllowEmptyString()] [string[]]$Line,
        [Parameter(Mandatory)] [ValidateSet('Computer', 'User')] [string]$Scope
    )

    if (-not @($Line | Where-Object { $_ -match '^\s*Resultant Set of Policy\s*$' }).Count) {
        throw "This is not what samba-gpupdate --rsop prints: $(@($Line | Select-Object -First 3) -join ' ')"
    }
    $names = [System.Collections.Generic.List[string]]::new()
    $settings = [System.Collections.Generic.List[object]]::new()
    $gpo = $null; $extension = $null; $type = $null
    foreach ($text in $Line) {
        if ($text -match '^GPO: (.+)$') { $gpo = $Matches[1].Trim(); $names.Add($gpo); $extension = $null; $type = $null }
        elseif ($text -match '^\s+CSE: (.+)$') { $extension = $Matches[1].Trim(); $type = $null }
        elseif ($text -match '^\s+Policy Type: (.+)$') { $type = $Matches[1].Trim() }
        elseif ($gpo -and $text -match '^\s+\[ (.+?) \] =\s*(.*)$') {
            $settings.Add([pscustomobject]@{ Scope = $Scope; Gpo = $gpo; Extension = $extension; PolicyType = $type; Name = $Matches[1]; Value = $Matches[2].Trim() })
        }
    }
    $gpos = for ($index = 0; $index -lt $names.Count; $index++) {
        [pscustomobject]@{
            PSTypeName = 'PSGPOTools.ResultGpo'
            Scope = $Scope; AppliedOrder = $index + 1; Precedence = $names.Count - $index; Name = $names[$index]; Id = $null
            Applied = $true; Reason = 'Applied'; Link = ''; LinkOrder = $null; Enforced = $null; VersionDirectory = $null; VersionSysvol = $null; SecurityFilter = @()
        }
    }
    [pscustomobject]@{ Gpos = @($gpos | Sort-Object Precedence); Settings = $settings.ToArray() }
}

# A result of samba-gpupdate --rsop, the computer part and the user part read.
function New-PSGPOSambaResult {
    [CmdletBinding()]
    [OutputType('PSGPOTools.Result')]
    param(
        [AllowNull()] [AllowEmptyString()] [string[]]$ComputerLine,
        [AllowNull()] [AllowEmptyString()] [string[]]$UserLine,
        [string]$Computer,
        [string]$User
    )

    $computerPart = if ($null -ne $ComputerLine) { ConvertFrom-PSGPOSambaRsop -Line $ComputerLine -Scope Computer }
    $userPart = if ($null -ne $UserLine) { ConvertFrom-PSGPOSambaRsop -Line $UserLine -Scope User }
    [pscustomobject]@{
        PSTypeName = 'PSGPOTools.Result'
        Source = 'samba-gpupdate'
        ReadTime = [datetime]::UtcNow.ToString('o')
        Computer = $Computer
        ComputerSom = ''
        User = $User
        UserSom = ''
        Site = ''
        ComputerGpos = if ($computerPart) { @($computerPart.Gpos) } else { @() }
        UserGpos = if ($userPart) { @($userPart.Gpos) } else { @() }
        ComputerGroups = @()
        UserGroups = @()
        ComputerExtensions = @()
        UserExtensions = @()
        Settings = @($(if ($computerPart) { $computerPart.Settings }) + $(if ($userPart) { $userPart.Settings }) | Where-Object { $_ })
    }
}

# samba-gpupdate on this computer, which reads the policy with its machine account: root only.
function Get-PSGPOSambaGpupdatePath {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $command = @(Get-Command -Name 'samba-gpupdate' -CommandType Application -ErrorAction SilentlyContinue) + @(Get-Item -LiteralPath '/usr/sbin/samba-gpupdate', '/usr/local/sbin/samba-gpupdate' -ErrorAction SilentlyContinue) | Select-Object -First 1
    if (-not $command) { throw 'samba-gpupdate is not on this computer: it comes with Samba, on a member of a Samba or Active Directory domain (Debian/Ubuntu: apt install samba-common-bin python3-samba).' }
    if ((Invoke-PSGPONativeCommand -FilePath 'id' -ArgumentList '-u').Output -ne '0') {
        throw 'samba-gpupdate reads and applies the policy with the machine account of this computer: run it as root (sudo pwsh), or give -Path with what "sudo samba-gpupdate --rsop" printed.'
    }
    if ($command.Source) { $command.Source } else { $command.FullName }
}
