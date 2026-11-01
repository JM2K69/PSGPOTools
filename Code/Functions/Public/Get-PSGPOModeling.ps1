function Get-PSGPOModeling {
    <#
    .SYNOPSIS
        Models the GPOs a computer and a user would apply, as Group Policy Modeling of GPMC, from the directory alone.
    .DESCRIPTION
        The links of the site, of the domain and of the OUs above the computer and the user, in the
        order Windows applies them: the enforced links from the site down, the others from the OU
        up to an OU that blocks the inheritance. Each GPO is Applied, with its precedence (1 wins),
        or denied, with its reason: Disabled link, Disabled GPO (that part disabled by its status),
        Denied (security), Not applied (security filtering), Inaccessible (the computer cannot read
        a user GPO, MS16-072), WMI filter not found, WMI filter false, Empty (no settings in that
        part: its version is 0, or no client-side extension declares it), Not found (a GPO of
        another domain).

        The security filtering is checked against the token of the account: its SID and its groups,
        the nested ones included (tokenGroups), Everyone and Authenticated Users. For the domain or
        an OU in place of an account (a container, as GPMC allows it), the token is the group of
        every computer or user of the domain and the groups given. A directory in memory
        (Import-PSGPODirectory) has no accounts: containers only. The WMI filters are not run:
        assumed true, but those given false. Loopback processing comes from the computer GPOs
        applied (Configure user Group Policy loopback processing mode), or is given: Merge adds the
        user GPOs of the computer after those of the user, Replace takes them alone.
    .PARAMETER Computer
        The computer: its name, its distinguished name, or the domain or an OU (a container).
    .PARAMETER ComputerGroup
        Groups the computer is in, for a container (or added to the groups of an account).
    .PARAMETER User
        The user: its name (DOMAIN\name or name), its distinguished name, or the domain or an OU.
    .PARAMETER UserGroup
        Groups the user is in, for a container (or added to the groups of an account).
    .PARAMETER Site
        The site of the computer (its name): its GPOs apply before those of the domain.
    .PARAMETER Loopback
        Loopback processing, in place of what the computer GPOs set: None, Merge or Replace.
    .PARAMETER FalseWmiFilter
        Names of the WMI filters that would be false on the computer: the GPOs that use them are denied.
    .PARAMETER Directory
        Directory of the domain (Get-PSGPODirectory); the domain is read when not given.
    .PARAMETER Server
        Domain controller to read the domain from, without -Directory.
    .EXAMPLE
        Get-PSGPOModeling -Computer 'PC-LYON-042' -User 'CONTOSO\jdoe' -Site 'Lyon-Site'
    .EXAMPLE
        (Get-PSGPOModeling -Computer 'OU=Kiosks,OU=Workstations,DC=contoso,DC=com' -ComputerGroup 'APPLY_C - Kiosks').ComputerGpos | Format-Table Precedence, Name, Link, Reason
    .OUTPUTS
        PSGPOTools.Modeling
    .LINK
        https://jm2k69.github.io/PSGPOTools/en/reference/commands/get-psgpomodeling/
    .LINK
        Get-PSGPOInheritance
    #>
    [CmdletBinding()]
    [OutputType('PSGPOTools.Modeling')]
    param(
        [string]$Computer,
        [string[]]$ComputerGroup = @(),
        [string]$User,
        [string[]]$UserGroup = @(),
        [string]$Site,
        [ValidateSet('None', 'Merge', 'Replace')] [string]$Loopback,
        [string[]]$FalseWmiFilter = @(),
        [GPOToolsDirectory]$Directory,
        [string]$Server
    )

    if (-not $Computer -and -not $User) { throw 'Give -Computer, -User, or both: the GPOs they would apply.' }
    if (-not $Directory) {
        $read = @{}
        if ($Server) { $read.Server = $Server }
        $Directory = Get-PSGPODirectory @read -ErrorAction Stop
    }
    $modeling = @{ Directory = $Directory; Computer = $Computer; ComputerGroup = $ComputerGroup; User = $User; UserGroup = $UserGroup; Site = $Site; FalseWmiFilter = $FalseWmiFilter }
    if ($Loopback) { $modeling.Loopback = $Loopback }
    Get-PSGPOModelingData @modeling
}
