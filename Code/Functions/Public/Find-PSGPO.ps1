function Find-PSGPO {
    <#
    .SYNOPSIS
        Searches the GPOs of a domain, as the Search of GPMC: by name, link, WMI filter, permission, client-side extension, setting, status, approval or comment.
    .DESCRIPTION
        Every criterion given must match. The name, the links, the WMI filter, the status, the
        approval and the client-side extensions are those of the domain read once; -Account reads
        the permissions of each GPO left, -Setting and -Comment the folder of each GPO left in
        SYSVOL: they take longer on a large domain, and come last. The GPOs found are those of the
        directory, by name: give them to Set-PSGPO, Backup-PSGPO, Get-PSGPOReport...
    .PARAMETER Name
        A part of the display name of the GPOs, or a pattern with * and ?.
    .PARAMETER Id
        The unique ID (GUID) of a GPO.
    .PARAMETER LinkedTo
        The domain, an OU (its distinguished name, or its name when only one OU has it) or a site
        of the forest (its name or its distinguished name): the GPOs linked there.
    .PARAMETER Linked
        The GPOs linked somewhere in the domain or in a site of the forest.
    .PARAMETER NotLinked
        The GPOs linked nowhere, in the domain nor in a site of the forest.
    .PARAMETER WmiFilter
        Name (or Id) of a WMI filter of the domain: the GPOs linked to it.
    .PARAMETER Account
        An account or a group, by its name (DOMAIN\name, name) or its SID: the GPOs it has a
        permission on, -Permission saying which one (any by default). A permission denied is not
        one it has.
    .PARAMETER Permission
        GpoRead, GpoApply (security filtering), GpoEdit, GpoEditDeleteModifySecurity or GpoCustom,
        with -Account.
    .PARAMETER Extension
        A client-side extension the GPOs declare: its name (Registry, Security, Scripts, Group
        Policy Drive Maps...), a part of it or a pattern with * and ?, or its GUID.
    .PARAMETER Setting
        A text found in the settings of the GPOs, as their Settings tab shows them: the names of
        the policies (with the ADMX files loaded, Initialize-PSGPOAdmx) and of the settings, the
        registry keys and values, their states and options.
    .PARAMETER Status
        Enabled, ComputerOnly (User configuration settings disabled), UserOnly (Computer
        configuration settings disabled) or Disabled.
    .PARAMETER ApprovalState
        Pending (waiting for approval) or Approved, with the approval workflow.
    .PARAMETER Comment
        A text found in the comment of the GPOs (GPO.cmt).
    .PARAMETER Directory
        Directory of the domain (Get-PSGPODirectory); the domain is read when not given.
    .PARAMETER Server
        Domain controller to read the domain from, without -Directory.
    .EXAMPLE
        Find-PSGPO -NotLinked
        The GPOs linked nowhere: candidates to delete, or forgotten.
    .EXAMPLE
        Find-PSGPO -Account 'Paris-Workstations' -Permission GpoApply
        The GPOs that apply to the group Paris-Workstations through their security filtering.
    .EXAMPLE
        Find-PSGPO -Setting 'Turn off Windows Defender' | Get-PSGPOReport -ReportType Html -Path ./reports
    .EXAMPLE
        Find-PSGPO -Extension 'Scripts' -LinkedTo 'OU=Servers,DC=contoso,DC=com'
    .OUTPUTS
        GPOToolsGpo
    .LINK
        https://jm2k69.github.io/PSGPOTools/en/reference/commands/find-psgpo/
    .LINK
        Set-PSGPO
    #>
    [CmdletBinding(DefaultParameterSetName = 'Any')]
    [OutputType([GPOToolsGpo])]
    param(
        [string]$Name,
        [guid]$Id,
        [string]$LinkedTo,
        [Parameter(ParameterSetName = 'Linked')] [switch]$Linked,
        [Parameter(ParameterSetName = 'NotLinked')] [switch]$NotLinked,
        [string]$WmiFilter,
        [string]$Account,
        [ValidateSet('GpoRead', 'GpoApply', 'GpoEdit', 'GpoEditDeleteModifySecurity', 'GpoCustom')] [string]$Permission,
        [string]$Extension,
        [string]$Setting,
        [ValidateSet('Enabled', 'ComputerOnly', 'UserOnly', 'Disabled')] [string]$Status,
        [ValidateSet('Pending', 'Approved')] [string]$ApprovalState,
        [string]$Comment,
        [GPOToolsDirectory]$Directory,
        [string]$Server
    )

    if ($Permission -and -not $Account) { throw 'Give -Account with -Permission: whose permission.' }
    if (-not $Directory) {
        $read = @{}
        if ($Server) { $read.Server = $Server }
        $Directory = Get-PSGPODirectory @read -ErrorAction Stop
    }
    $criteria = @{
        Name = $Name; Id = $(if ($PSBoundParameters.ContainsKey('Id')) { $Id }); Linked = [bool]$Linked; NotLinked = [bool]$NotLinked
        Account = $Account; Permission = $Permission; Extension = $Extension; Setting = $Setting; Status = $Status
        ApprovalState = $ApprovalState; Comment = $Comment
    }
    if ($LinkedTo) {
        # The domain or an OU; else a site of the forest.
        try { $criteria.LinkedTo = Resolve-PSGPOSom -Directory $Directory -Target $LinkedTo }
        catch {
            $criteria.LinkedTo = $Directory.FindSite($LinkedTo.Trim())
            if (-not $criteria.LinkedTo) { throw }
        }
    }
    if ($WmiFilter) {
        $criteria.WmiFilter = $Directory.FindWmiFilter($WmiFilter)
        if (-not $criteria.WmiFilter) { throw "No WMI filter named '$WmiFilter' in $($Directory.DomainName): $(@($Directory.WmiFilters.Name) -join ', ')." }
    }
    Find-PSGPOMatch -Directory $Directory -Criteria $criteria
}
